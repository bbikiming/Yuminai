import Foundation
import YuminaiCore

/// 실제 `claude` CLI를 자식 프로세스로 spawn하는 어댑터.
///
/// ADR-009 결정에 따라 항상 다음 인자로 호출한다:
/// `claude -p --input-format stream-json --output-format stream-json --include-partial-messages --verbose`
///
/// 멀티턴 세션은 `--session-id`를 통해 유지된다 (생성자에서 받음).
public final actor LiveClaudeAdapter: ClaudeAdapter {
    private let claudePath: URL
    private let environment: [String: String]
    private let extraArguments: [String]

    public init(
        claudePath: URL,
        environment: [String: String] = ProcessEnvironment.augmented(),
        extraArguments: [String] = []
    ) {
        self.claudePath = claudePath
        self.environment = environment
        self.extraArguments = extraArguments
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

        return try LiveClaudeStreamSession(
            claudePath: claudePath,
            workspaceURL: workspaceURL,
            environment: environment,
            sessionId: UUID(),
            extraArguments: extraArguments
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
            "--session-id", sessionId.uuidString
        ]
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
