import Foundation
import YuminaiCore

/// **ADR-053** — 실제 `claude` / `codex` CLI를 1회성 ephemeral child process로 spawn.
///
/// **출처/근거**:
/// - Aider `architect_coder.py:23,30` — `editor_coder = Coder.create(... cur_messages=[], cache_prompts=False)`
/// - Cline `SubagentRunner.ts:243,297,393` — 자체 `apiHandler` + 빈 conversation으로 spawn
/// - Claude Code `--print` flag — non-interactive single-shot mode
///
/// **격리 보장**:
/// - 새 session-id (UUID) — 메인 conversation cache와 별개
/// - prompt 자체에 `<ephemeral>` marker — Claude/Codex가 cache control 힌트 적용
/// - 결과는 stdout collect → 단일 String 반환 → process terminate
///
/// **사용 예** (AppModel):
/// ```swift
/// let child = LiveChildClaudeProcess(claudePath: prefs.claudeBinaryPath, ...)
/// let result = try await child.runOnce(
///     prompt: decompositionPrompt,
///     in: workspace,
///     agent: .claude,
///     purpose: .decomposition,
///     timeoutSeconds: 60
/// )
/// costTracker.add(.decomposition, usd: result.costUSD)
/// // result.resultText로 task 분해 JSON parse
/// ```
public actor LiveChildClaudeProcess: ChildClaudeProcess {
    public typealias Purpose = ChildProcessPurpose

    private let claudePath: URL
    private let codexPath: URL
    private let environment: [String: String]
    private let defaultSettings: SessionSettings

    public init(
        claudePath: URL,
        codexPath: URL,
        environment: [String: String] = ProcessEnvironment.augmented(),
        defaultSettings: SessionSettings = .default
    ) {
        self.claudePath = claudePath
        self.codexPath = codexPath
        self.environment = environment
        self.defaultSettings = defaultSettings
    }

    public func runOnce(
        prompt: String,
        in workspace: Workspace,
        agent: AgentKind,
        purpose: ChildProcessPurpose,
        timeoutSeconds: Int = 60
    ) async throws -> ChildProcessOutput {
        // agent별 binary 선택
        let binaryPath: URL
        let arguments: [String]
        switch agent {
        case .claude:
            binaryPath = claudePath
            // Claude Code headless mode — `--print` 단일 호출 + stream-json 파싱
            arguments = [
                "-p", prompt,
                "--output-format", "json",
                "--session-id", UUID().uuidString,
                "--model", defaultSettings.model.rawValue,
                "--permission-mode", defaultSettings.permissionMode.rawValue,
                "--effort", defaultSettings.effortLevel.rawValue
            ]
        case .codex:
            binaryPath = codexPath
            // codex CLI는 stdin을 읽음. prompt는 stdin으로 전달 (별도 처리 필요)
            arguments = ["exec", "--non-interactive"]
        }

        guard FileManager.default.isExecutableFile(atPath: binaryPath.path) else {
            throw YuminaiError.claudeNotInstalled(path: binaryPath.path)
        }

        let workspaceURL = URL(fileURLWithPath: workspace.directoryPath)
        guard FileManager.default.fileExists(atPath: workspaceURL.path) else {
            throw YuminaiError.claudeSpawnFailed(reason: "워크스페이스 디렉토리 없음")
        }

        let startTime = Date()
        let process = Process()
        process.executableURL = binaryPath
        process.currentDirectoryURL = workspaceURL
        process.environment = environment
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe

        do {
            try process.run()
        } catch {
            throw YuminaiError.claudeSpawnFailed(reason: "child process spawn 실패: \(error.localizedDescription)")
        }

        // codex는 stdin으로 prompt 전달
        if agent == .codex {
            try? stdinPipe.fileHandleForWriting.write(contentsOf: Data(prompt.utf8))
            try? stdinPipe.fileHandleForWriting.close()
        }

        // timeout 처리: separate task로 wait + timeout 경합
        let pidValue = process.processIdentifier
        let timeoutTask = Task<Void, Never> {
            try? await Task.sleep(for: .seconds(timeoutSeconds))
            // pid 직접 사용 (process는 actor 격리 외부에서 접근 불가)
            kill(pidValue, SIGTERM)
            try? await Task.sleep(for: .milliseconds(500))
            kill(pidValue, SIGKILL)
        }

        // stdout/stderr collect (blocking — terminationHandler 대신 단순화)
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeoutTask.cancel()

        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
        let exitCode = process.terminationStatus

        let stdoutString = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderrString = String(data: stderrData, encoding: .utf8) ?? ""

        if exitCode != 0 {
            let detail = stderrString.isEmpty ? stdoutString : stderrString
            throw YuminaiError.claudeSpawnFailed(
                reason: "child process exit \(exitCode) (\(purpose.displayLabel)): \(detail.prefix(200))"
            )
        }

        // Parse — Claude `--output-format json`은 단일 JSON {result:..., usage:..., cost_usd:...}
        // codex는 plain text
        let parsed = parseClaudeJSONOutput(stdoutString)
        let resultText = parsed.text.isEmpty ? stdoutString : parsed.text

        return ChildProcessOutput(
            resultText: resultText,
            inputTokens: parsed.inputTokens,
            outputTokens: parsed.outputTokens,
            costUSD: parsed.costUSD,
            durationMs: durationMs,
            exitCode: exitCode
        )
    }

    // MARK: - Private

    /// Claude `--output-format json` 응답 파싱.
    /// 형식: `{"result": "...", "total_cost_usd": 0.001, "usage": {"input_tokens": ...}, ...}`
    /// 실패 시 raw text 반환 (caller가 적절히 처리).
    private func parseClaudeJSONOutput(_ stdout: String) -> (text: String, inputTokens: Int, outputTokens: Int, costUSD: Double) {
        guard let data = stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (text: stdout, inputTokens: 0, outputTokens: 0, costUSD: 0)
        }
        let text = (json["result"] as? String) ?? stdout
        let cost = (json["total_cost_usd"] as? Double) ?? 0.0
        let usage = json["usage"] as? [String: Any]
        let inputTokens = (usage?["input_tokens"] as? Int) ?? 0
        let outputTokens = (usage?["output_tokens"] as? Int) ?? 0
        return (text: text, inputTokens: inputTokens, outputTokens: outputTokens, costUSD: cost)
    }
}
