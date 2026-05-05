import Foundation
import YuminaiCore

/// 실제 `claude` CLI를 자식 프로세스로 spawn하는 어댑터.
///
/// ADR-009 결정에 따라 항상 다음 인자 조합으로 호출한다:
/// `claude -p --input-format stream-json --output-format stream-json
///         --include-partial-messages --verbose
///         --session-id <uuid>
///         --model <alias> --permission-mode <mode> --effort <level>`
///
/// 활성 `SessionSettings`는 `updateSettings(_:)`로 변경 가능. 변경은 다음 `spawn(in:)`에 적용.
public final actor LiveClaudeAdapter: ClaudeAdapter {
    private let claudePath: URL
    private let environment: [String: String]
    private let extraArguments: [String]
    private var sessionSettings: SessionSettings
    /// ADR-108 — 매 spawn 시 호출해 사용자 프로필 system prompt를 얻는 provider.
    /// nil이면 주입 없음. Sendable closure로 actor 격리 안전.
    private let userProfileProvider: (@Sendable () -> String?)?

    public init(
        claudePath: URL,
        sessionSettings: SessionSettings = .default,
        environment: [String: String] = ProcessEnvironment.augmented(),
        extraArguments: [String] = [],
        userProfileProvider: (@Sendable () -> String?)? = nil
    ) {
        self.claudePath = claudePath
        self.sessionSettings = sessionSettings
        self.environment = environment
        self.extraArguments = extraArguments
        self.userProfileProvider = userProfileProvider
    }

    public func updateSettings(_ settings: SessionSettings) {
        self.sessionSettings = settings
    }

    public func currentSettings() -> SessionSettings {
        sessionSettings
    }

    public func spawn(in workspace: Workspace) async throws -> any ClaudeStreamSession {
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: claudePath.path) else {
            throw YuminaiError.claudeNotInstalled(path: claudePath.path)
        }
        let workspaceURL = URL(fileURLWithPath: workspace.directoryPath)
        guard fileManager.fileExists(atPath: workspaceURL.path) else {
            throw YuminaiError.claudeSpawnFailed(reason: "워크스페이스 디렉토리 없음: \(workspace.directoryPath)")
        }

        // ADR-049 + ADR-055 #1 — projectProfile을 system prompt appendix로 자동 inject.
        // Anthropic prompt caching 활용 — 같은 system context는 cache 적용됨.
        // ADR-055 #1: `systemPromptAppendix()` 사용 — 결정적 ordering으로 cache key 안정화
        // → child process도 같은 형식으로 inject 가능 (LiveChildClaudeProcess와 동일)
        // ADR-108 — userProfile을 projectProfile 앞에 prepend (cache 친화적 ordering).
        //            userProfile은 자주 안 바뀌므로 앞에 두면 cache hit 유지.
        var combinedExtraArgs = extraArguments

        // 1) userProfile (짧고 자주 안 바뀜 → 앞에)
        if let profilePrompt = userProfileProvider?() {
            combinedExtraArgs.append(contentsOf: ["--append-system-prompt", profilePrompt])
        }

        // 2) projectProfile (워크스페이스별 — 뒤에)
        if let appendix = workspace.projectProfile.systemPromptAppendix() {
            combinedExtraArgs.append(contentsOf: ["--append-system-prompt", appendix])
        }

        return try LiveClaudeStreamSession(
            claudePath: claudePath,
            workspaceURL: workspaceURL,
            environment: environment,
            sessionId: UUID(),
            settings: sessionSettings,
            extraArguments: combinedExtraArgs
        )
    }

    public func terminate(_ session: any ClaudeStreamSession) async {
        guard let live = session as? LiveClaudeStreamSession else { return }
        await live.terminate()
    }
}

/// 단일 Claude CLI 자식 프로세스 세션. NDJSON 양방향 스트림.
final class LiveClaudeStreamSession: ClaudeStreamSession, @unchecked Sendable {
    let events: AsyncThrowingStream<ClaudeEvent, any Error>
    private let continuation: AsyncThrowingStream<ClaudeEvent, any Error>.Continuation
    private let process: Process
    private let stdinPipe: Pipe
    private let stdoutPipe: Pipe
    private let stderrPipe: Pipe
    private let parser = JSONStreamParser()

    init(
        claudePath: URL,
        workspaceURL: URL,
        environment: [String: String],
        sessionId: UUID,
        settings: SessionSettings,
        extraArguments: [String]
    ) throws {
        let process = Process()
        process.executableURL = claudePath
        process.currentDirectoryURL = workspaceURL
        process.environment = environment

        var arguments: [String] = [
            "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--include-partial-messages",
            "--verbose",
            "--session-id", sessionId.uuidString,
            "--model", settings.model.rawValue,
            "--permission-mode", settings.permissionMode.rawValue,
            "--effort", settings.effortLevel.rawValue
        ]
        if settings.includeHookEvents {
            arguments.append("--include-hook-events")
        }
        if let budget = settings.maxBudgetUSD {
            arguments.append("--max-budget-usd")
            arguments.append(String(format: "%.4f", budget))
        }
        arguments.append(contentsOf: extraArguments)
        process.arguments = arguments

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var contLocal: AsyncThrowingStream<ClaudeEvent, any Error>.Continuation!
        let stream = AsyncThrowingStream<ClaudeEvent, any Error> { c in contLocal = c }

        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
        self.events = stream
        self.continuation = contLocal

        let parser = self.parser
        let captured = contLocal!

        process.terminationHandler = { proc in
            Task {
                let tail = await parser.flush()
                for ev in tail {
                    captured.yield(ev)
                }
                captured.yield(.completed(exitCode: proc.terminationStatus))
                captured.finish()
            }
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            Task {
                let events = await parser.feed(chunk)
                for ev in events {
                    captured.yield(ev)
                }
            }
        }

        do {
            try process.run()
        } catch {
            captured.finish(throwing: YuminaiError.claudeSpawnFailed(reason: error.localizedDescription))
            throw YuminaiError.claudeSpawnFailed(reason: error.localizedDescription)
        }

        let weakSelf = WeakBox(self)
        contLocal.onTermination = { _ in
            Task { await weakSelf.value?.terminate() }
        }
    }

    func send(_ text: String) async throws {
        // stream-json 입력 형식: 한 줄 JSON {"type":"user","message":{...}}
        let payload: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": text
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            throw YuminaiError.claudeSpawnFailed(reason: "JSON 직렬화 실패")
        }
        var line = data
        line.append(0x0A)
        try stdinPipe.fileHandleForWriting.write(contentsOf: line)
    }

    func terminate() async {
        guard process.isRunning else { return }
        process.terminate()
        try? await Task.sleep(for: .milliseconds(500))
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }
}

/// `Sendable` 클로저 안에서 weak 참조를 안전하게 캡처하기 위한 박스.
private final class WeakBox<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(_ value: T) { self.value = value }
}
