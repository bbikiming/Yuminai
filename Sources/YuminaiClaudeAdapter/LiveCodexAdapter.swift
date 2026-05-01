import Foundation
import os
import YuminaiCore

private let codexParserLogger = Logger(subsystem: "com.yuminai", category: "CodexJSONL")

/// 실제 `codex` CLI를 자식 프로세스로 spawn하는 어댑터 (ADR-026).
///
/// Claude CLI와 다른 점:
/// - Claude는 long-lived process + 양방향 stream-json (한 프로세스가 여러 turn 처리)
/// - **Codex는 turn마다 새 프로세스** — `codex exec --json` (initial) 또는
///   `codex exec resume <session-id> --json` (subsequent)
///
/// `events` stream은 워크스페이스 lifetime 동안 유지되고, 각 turn 종료 시 `.completed(exitCode:)`
/// 이벤트가 emit되지만 스트림 자체는 finish하지 않음 (다음 send를 기다림).
public final actor LiveCodexAdapter: ClaudeAdapter {
    private let codexPath: URL
    private let environment: [String: String]
    private let extraArguments: [String]
    private var sessionSettings: SessionSettings

    public init(
        codexPath: URL,
        sessionSettings: SessionSettings = .default,
        environment: [String: String] = ProcessEnvironment.augmented(),
        extraArguments: [String] = []
    ) {
        self.codexPath = codexPath
        self.sessionSettings = sessionSettings
        self.environment = environment
        self.extraArguments = extraArguments
    }

    public func updateSettings(_ settings: SessionSettings) {
        self.sessionSettings = settings
    }

    public func currentSettings() -> SessionSettings {
        sessionSettings
    }

    public func spawn(in workspace: Workspace) async throws -> any ClaudeStreamSession {
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: codexPath.path) else {
            throw YuminaiError.claudeSpawnFailed(reason: "codex CLI 미설치 또는 실행 불가: \(codexPath.path)")
        }
        let workspaceURL = URL(fileURLWithPath: workspace.directoryPath)
        guard fileManager.fileExists(atPath: workspaceURL.path) else {
            throw YuminaiError.claudeSpawnFailed(reason: "워크스페이스 디렉토리 없음: \(workspace.directoryPath)")
        }

        return LiveCodexStreamSession(
            codexPath: codexPath,
            workspaceURL: workspaceURL,
            environment: environment,
            settings: sessionSettings,
            extraArguments: extraArguments
        )
    }

    public func terminate(_ session: any ClaudeStreamSession) async {
        guard let codex = session as? LiveCodexStreamSession else { return }
        await codex.terminate()
    }
}

/// Codex CLI 세션 — 한 워크스페이스 동안 살아있고, 매 turn마다 새 프로세스 spawn.
final class LiveCodexStreamSession: ClaudeStreamSession, @unchecked Sendable {
    let events: AsyncThrowingStream<ClaudeEvent, any Error>
    private let continuation: AsyncThrowingStream<ClaudeEvent, any Error>.Continuation

    private let codexPath: URL
    private let workspaceURL: URL
    private let environment: [String: String]
    private let settings: SessionSettings
    private let extraArguments: [String]

    /// codex 첫 turn 후 추출한 session id — 다음 turn에서 `resume`에 사용.
    private var codexSessionId: String?
    private var currentProcess: Process?
    private let parser = CodexJSONLParser()

    init(
        codexPath: URL,
        workspaceURL: URL,
        environment: [String: String],
        settings: SessionSettings,
        extraArguments: [String]
    ) {
        self.codexPath = codexPath
        self.workspaceURL = workspaceURL
        self.environment = environment
        self.settings = settings
        self.extraArguments = extraArguments

        var contLocal: AsyncThrowingStream<ClaudeEvent, any Error>.Continuation!
        self.events = AsyncThrowingStream<ClaudeEvent, any Error> { c in contLocal = c }
        self.continuation = contLocal
    }

    func send(_ text: String) async throws {
        // 이전 turn process가 살아있다면 (보호) 종료
        if let prev = currentProcess, prev.isRunning {
            prev.terminate()
        }

        let process = Process()
        process.executableURL = codexPath
        process.currentDirectoryURL = workspaceURL
        process.environment = environment

        var arguments: [String] = ["exec"]
        if let resumeId = codexSessionId {
            arguments.append(contentsOf: ["resume", resumeId])
        }
        arguments.append(contentsOf: ["--json", "-C", workspaceURL.path])
        // 모델 — codex와 claude의 model alias가 다르므로, 사용자가 codex 모델을 직접 설정할
        // 때까지는 codex의 default 사용 (사용자 ~/.codex/config.toml 우선)
        arguments.append(contentsOf: extraArguments)
        process.arguments = arguments

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let captured = continuation
        let parser = self.parser
        let weakSelf = WeakRef(value: self)

        process.terminationHandler = { proc in
            Task {
                let tail = await parser.flush()
                for ev in tail {
                    captured.yield(ev)
                    if case .text(_) = ev { /* no-op */ }
                    // session id 추출 시도 — 마지막 chunk에서도 가능
                }
                if let extractedId = await parser.extractedSessionId,
                   weakSelf.value?.codexSessionId == nil {
                    weakSelf.value?.codexSessionId = extractedId
                }
                captured.yield(.completed(exitCode: proc.terminationStatus))
                weakSelf.value?.currentProcess = nil
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

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            // stderr는 디버그용 — 최소한 toolResult로 forward (silent drop X)
            if let s = String(data: chunk, encoding: .utf8), !s.isEmpty {
                captured.yield(.toolResult(success: false, output: "[codex stderr] \(s)"))
            }
        }

        do {
            try process.run()
            currentProcess = process
        } catch {
            captured.yield(.completed(exitCode: -1))
            throw YuminaiError.claudeSpawnFailed(reason: "codex 실행 실패: \(error.localizedDescription)")
        }

        // prompt를 stdin으로 전달 (codex는 PROMPT arg 없으면 stdin에서 읽음)
        let promptData = Data((text + "\n").utf8)
        do {
            try stdinPipe.fileHandleForWriting.write(contentsOf: promptData)
            try stdinPipe.fileHandleForWriting.close()
        } catch {
            // stdin 닫기 실패는 보통 process가 빠르게 끝났을 때 — 무시 (terminationHandler가 처리)
        }
    }

    func terminate() async {
        currentProcess?.terminate()
        currentProcess = nil
        continuation.finish()
    }
}

/// `currentProcess`/`codexSessionId`을 terminationHandler에서 mutate하기 위한 약한 참조 박스.
private final class WeakRef<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(value: T) { self.value = value }
}

/// Codex CLI의 `--json` JSONL 출력 파싱 — defensive (스키마가 향후 변경될 수 있음).
///
/// 알려진 패턴 (관찰 기반 + 추정):
/// - SessionCreated/SessionStarted 이벤트에 `session_id` 필드
/// - assistant 텍스트는 `type: "agent_message" | "message" | "text"` + `content`/`text` 필드
/// - 도구 호출은 `type: "tool_call" | "tool_use"` + `name` + `arguments`/`input`
/// - 도구 결과는 `type: "tool_result"` + `output` + (선택) `is_error`
/// - 토큰 사용량은 `type: "usage"` + `input_tokens` 등
///
/// 알 수 없는 shape는 raw text로 forward (사용자가 보고 디버깅 가능).
actor CodexJSONLParser {
    private var buffer = Data()
    var extractedSessionId: String?

    func feed(_ chunk: Data) -> [ClaudeEvent] {
        buffer.append(chunk)
        return drainCompleteLines()
    }

    func flush() -> [ClaudeEvent] {
        let pending = buffer
        buffer.removeAll()
        guard !pending.isEmpty,
              let line = String(data: pending, encoding: .utf8),
              !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return [] }
        return parse(line: line).map { [$0] } ?? []
    }

    private func drainCompleteLines() -> [ClaudeEvent] {
        var events: [ClaudeEvent] = []
        while let newlineIdx = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.subdata(in: 0..<newlineIdx)
            buffer.removeSubrange(0...newlineIdx)
            guard let line = String(data: lineData, encoding: .utf8),
                  !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            if let event = parse(line: line) {
                events.append(event)
            }
        }
        return events
    }

    private func parse(line: String) -> ClaudeEvent? {
        guard let data = line.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data) else {
            // JSON 아니면 raw text로
            return .text(line)
        }
        guard let dict = any as? [String: Any] else {
            return .text(line)
        }

        // session id 추출 (여러 후보)
        for key in ["session_id", "sessionId", "id"] {
            if extractedSessionId == nil, let id = dict[key] as? String, !id.isEmpty {
                extractedSessionId = id
            }
        }
        if let session = dict["session"] as? [String: Any], extractedSessionId == nil {
            for key in ["id", "session_id"] {
                if let id = session[key] as? String { extractedSessionId = id; break }
            }
        }

        let type = (dict["type"] as? String) ?? (dict["event"] as? String) ?? ""

        switch type {
        case "agent_message", "assistant_message", "message", "text",
             "agent_message_delta", "agent_message_chunk", "delta", "stream_text",
             "content_block_delta", "content_part", "completion_chunk":
            let text = extractText(from: dict) ?? ""
            return text.isEmpty ? nil : .text(text)

        case "thinking", "reasoning", "chain_of_thought",
             "thought", "internal_reasoning":
            // thinking은 Yuminai에서 별도 처리 X — 그냥 무시 (verbose mode 아니면 노이즈)
            return nil

        case "tool_call", "tool_use", "function_call",
             "tool_call_delta", "tool_use_started",
             "tool_invocation", "execute_tool":
            let name = (dict["name"] as? String) ?? (dict["tool_name"] as? String) ?? "?"
            let input = serializeInput(dict["arguments"] ?? dict["input"] ?? dict["args"])
            return .toolCall(name: name, input: input)

        case "tool_result", "function_result", "tool_use_result",
             "tool_observation", "tool_output", "execution_result":
            let output = extractText(from: dict) ?? ""
            let success: Bool
            if let isError = dict["is_error"] as? Bool {
                success = !isError
            } else if let status = dict["status"] as? String {
                success = (status == "ok" || status == "success" || status == "completed")
            } else if let exitCode = dict["exit_code"] as? Int {
                success = (exitCode == 0)
            } else {
                success = true
            }
            return .toolResult(success: success, output: output)

        case "usage", "token_usage", "usage_update", "metering":
            let inputTokens = intValue(dict["input_tokens"] ?? dict["prompt_tokens"]) ?? 0
            let outputTokens = intValue(dict["output_tokens"] ?? dict["completion_tokens"]) ?? 0
            let cacheCreate = intValue(dict["cache_creation_tokens"]) ?? 0
            let cacheRead = intValue(dict["cache_read_tokens"] ?? dict["cached_tokens"]) ?? 0
            let cost = dict["cost_usd"] as? Double
                ?? dict["total_cost_usd"] as? Double
                ?? dict["cost"] as? Double
            return .usage(.init(
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheCreationTokens: cacheCreate,
                cacheReadTokens: cacheRead,
                costUSD: cost
            ))

        case "session_started", "session_created", "session_initialized",
             "configured", "ready", "session_metadata", "init":
            // session id만 추출, UI 이벤트는 emit X
            return nil

        case "error", "agent_error", "fatal_error", "warning":
            // 에러는 toolResult(success: false)로 forward (사용자 인지 필요)
            let msg = extractText(from: dict) ?? "Codex 에러"
            return .toolResult(success: false, output: "[\(type)] \(msg)")

        case "completed", "session_ended", "done", "stop":
            // 명시적 turn 종료 — process termination이 처리하므로 emit X
            return nil

        case "":
            // type 없으면 text 추정
            if let text = extractText(from: dict) {
                return .text(text)
            }
            return nil

        default:
            // 알 수 없는 type — logger로 기록 (사용자가 codex 사용 시 데이터 모임)
            // 사용자/개발자가 PR로 매핑 추가 가능
            codexParserLogger.warning("unknown codex JSONL type: \(type, privacy: .public)")
            return .text("[codex \(type)] \(line)")
        }
    }

    private func extractText(from dict: [String: Any]) -> String? {
        for key in ["text", "content", "delta", "message", "output"] {
            if let s = dict[key] as? String, !s.isEmpty { return s }
        }
        // content가 nested array (Anthropic 스타일) 처리
        if let array = dict["content"] as? [[String: Any]] {
            let texts = array.compactMap { $0["text"] as? String }
            if !texts.isEmpty { return texts.joined(separator: "") }
        }
        return nil
    }

    private func serializeInput(_ any: Any?) -> String {
        guard let any else { return "" }
        if let s = any as? String { return s }
        if let data = try? JSONSerialization.data(withJSONObject: any, options: .sortedKeys),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return "\(any)"
    }

    private func intValue(_ any: Any?) -> Int? {
        if let v = any as? Int { return v }
        if let v = any as? Int64 { return Int(v) }
        if let v = any as? NSNumber { return v.intValue }
        if let s = any as? String { return Int(s) }
        return nil
    }
}
