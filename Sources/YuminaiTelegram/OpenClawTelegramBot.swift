import Foundation
import YuminaiCore

/// `openclaw` CLI에 위임하는 Telegram 클라이언트.
///
/// 설계 의도:
/// - Bot 토큰을 Yuminai에 직접 입력하지 않아도 됨 (openclaw vault에 저장된 토큰을 위임 사용)
/// - 송신: `openclaw message send --channel telegram --target <id> --message <text> --json`
/// - 수신: 5초 주기로 `openclaw message read --channel telegram --target <id> --after <last> --json`
///
/// `LiveTelegramBot`의 `chatId: Int64` 시그니처 호환을 위해 init 시점의 `target`(@handle 또는 숫자 id)
/// 을 단일 채팅으로 가정한다. 멀티 챗 라우팅은 차기 라운드.
public final actor OpenClawTelegramBot: TelegramClient {

    /// process runner 추상화 — 테스트에서 mock 주입.
    public typealias ProcessRun = @Sendable (URL, [String]) async throws -> ProcessOutput

    public struct Configuration: Sendable {
        public let binaryURL: URL
        public let target: String
        public let allowedUserIds: Set<Int64>
        public let pollInterval: Duration

        public init(
            binaryURL: URL,
            target: String,
            allowedUserIds: Set<Int64>,
            pollInterval: Duration = .seconds(5)
        ) {
            self.binaryURL = binaryURL
            self.target = target
            self.allowedUserIds = allowedUserIds
            self.pollInterval = pollInterval
        }
    }

    private let config: Configuration
    private let processRun: ProcessRun

    private var lastUpdateId: Int64 = 0
    private var pollingTask: Task<Void, Never>?

    public nonisolated let incoming: AsyncStream<IncomingTelegramMessage>
    private nonisolated let incomingContinuation: AsyncStream<IncomingTelegramMessage>.Continuation

    public init(
        configuration: Configuration,
        processRun: @escaping ProcessRun = OpenClawTelegramBot.defaultProcessRun
    ) {
        self.config = configuration
        self.processRun = processRun

        var cont: AsyncStream<IncomingTelegramMessage>.Continuation!
        self.incoming = AsyncStream<IncomingTelegramMessage> { c in cont = c }
        self.incomingContinuation = cont
    }

    // MARK: - TelegramClient

    public func send(_ text: String, to chatId: Int64) async throws -> SentTelegramMessage {
        let args = [
            "message", "send",
            "--channel", "telegram",
            "--target", config.target,
            "--message", text,
            "--json"
        ]
        let output = try await processRun(config.binaryURL, args)
        try ensureSuccess(output, action: "send")
        let messageId = Self.parseMessageId(from: output.stdout) ?? 0
        return SentTelegramMessage(messageId: messageId, chatId: chatId)
    }

    public func edit(messageId: Int64, in chatId: Int64, text: String) async throws {
        let args = [
            "message", "edit",
            "--channel", "telegram",
            "--target", config.target,
            "--message-id", String(messageId),
            "--message", text,
            "--json"
        ]
        let output = try await processRun(config.binaryURL, args)
        try ensureSuccess(output, action: "edit")
    }

    public func startPolling() async throws {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    public func stopPolling() async {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Internal

    private func pollLoop() async {
        while !Task.isCancelled {
            do {
                var args = [
                    "message", "read",
                    "--channel", "telegram",
                    "--target", config.target,
                    "--limit", "20",
                    "--json"
                ]
                if lastUpdateId > 0 {
                    args.append(contentsOf: ["--after", String(lastUpdateId)])
                }
                let output = try await processRun(config.binaryURL, args)
                try ensureSuccess(output, action: "read")
                let updates = Self.parseIncoming(from: output.stdout)
                for update in updates {
                    if update.updateId > lastUpdateId {
                        lastUpdateId = update.updateId
                    }
                    if config.allowedUserIds.contains(update.userId) {
                        incomingContinuation.yield(update)
                    }
                }
                try? await Task.sleep(for: config.pollInterval)
            } catch {
                // 에러 시 더 긴 간격 — openclaw 채널이 비활성/미설정일 수 있음
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    private func ensureSuccess(_ output: ProcessOutput, action: String) throws {
        guard output.exitCode == 0 else {
            throw OpenClawError.cliFailed(action: action, exitCode: output.exitCode, stderr: output.stderr)
        }
    }

    // MARK: - Parsing (defensive — openclaw JSON shape can evolve)

    static func parseMessageId(from stdout: String) -> Int64? {
        guard let data = stdout.data(using: .utf8) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let dict = json as? [String: Any] {
            return extractMessageId(from: dict)
        }
        return nil
    }

    private static func extractMessageId(from dict: [String: Any]) -> Int64? {
        for key in ["messageId", "message_id", "id"] {
            if let v = coerceInt64(dict[key]) { return v }
        }
        if let result = dict["result"] as? [String: Any] {
            return extractMessageId(from: result)
        }
        if let data = dict["data"] as? [String: Any] {
            return extractMessageId(from: data)
        }
        return nil
    }

    static func parseIncoming(from stdout: String) -> [IncomingTelegramMessage] {
        guard let data = stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        if let array = json as? [[String: Any]] {
            return array.compactMap(parseMessage)
        }
        if let dict = json as? [String: Any] {
            for key in ["messages", "result", "data", "items"] {
                if let arr = dict[key] as? [[String: Any]] {
                    return arr.compactMap(parseMessage)
                }
            }
        }
        return []
    }

    private static func parseMessage(_ raw: [String: Any]) -> IncomingTelegramMessage? {
        let updateId =
            coerceInt64(raw["updateId"])
            ?? coerceInt64(raw["update_id"])
            ?? coerceInt64(raw["id"])
        guard let updateId, updateId > 0 else { return nil }

        let from = raw["from"] as? [String: Any]
        let userId =
            coerceInt64(from?["id"])
            ?? coerceInt64(raw["userId"])
            ?? coerceInt64(raw["user_id"])
            ?? 0

        let chat = raw["chat"] as? [String: Any]
        let chatId =
            coerceInt64(chat?["id"])
            ?? coerceInt64(raw["chatId"])
            ?? coerceInt64(raw["chat_id"])
            ?? 0

        let text = raw["text"] as? String ?? raw["message"] as? String ?? raw["body"] as? String

        return IncomingTelegramMessage(
            updateId: updateId,
            userId: userId,
            chatId: chatId,
            text: text
        )
    }

    private static func coerceInt64(_ any: Any?) -> Int64? {
        if let v = any as? Int64 { return v }
        if let v = any as? Int { return Int64(v) }
        if let v = any as? NSNumber { return v.int64Value }
        if let s = any as? String, let v = Int64(s) { return v }
        return nil
    }

    // MARK: - Default process runner (Process + Pipe)

    public static let defaultProcessRun: ProcessRun = { binaryURL, args in
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return ProcessOutput(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}

public struct ProcessOutput: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public enum OpenClawError: Error, LocalizedError, Sendable {
    case cliFailed(action: String, exitCode: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case .cliFailed(let action, let exitCode, let stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let reason = trimmed.isEmpty ? "exit \(exitCode)" : trimmed
            return "openclaw \(action) 실패: \(reason)"
        }
    }
}

// MARK: - Detection helper

/// openclaw 설치/상태 감지 — UI에서 표시.
public struct OpenClawDetector: Sendable {
    public let binaryPath: String
    public let processRun: OpenClawTelegramBot.ProcessRun

    public init(
        binaryPath: String = OpenClawDetector.defaultBinaryPath(),
        processRun: @escaping OpenClawTelegramBot.ProcessRun = OpenClawTelegramBot.defaultProcessRun
    ) {
        self.binaryPath = binaryPath
        self.processRun = processRun
    }

    public static func defaultBinaryPath() -> String {
        let candidates = [
            "/opt/homebrew/bin/openclaw",
            "/usr/local/bin/openclaw",
            NSString(string: "~/.local/bin/openclaw").expandingTildeInPath
        ]
        let fm = FileManager.default
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return path
        }
        return candidates[0]
    }

    public func detect() async -> Status {
        let url = URL(fileURLWithPath: binaryPath)
        guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
            return Status(installed: false, version: nil, telegramActive: false, message: "openclaw가 설치되지 않았어요. brew로 설치하면 자동 감지됩니다.")
        }
        let version: String?
        do {
            let out = try await processRun(url, ["--version"])
            let trimmed = out.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            version = trimmed.isEmpty ? nil : trimmed
        } catch {
            return Status(installed: true, version: nil, telegramActive: false, message: "openclaw 실행 실패: \(error.localizedDescription)")
        }

        let telegramActive: Bool
        do {
            let out = try await processRun(url, ["channels", "list", "--json"])
            telegramActive = out.stdout.lowercased().contains("telegram")
        } catch {
            telegramActive = false
        }

        let message: String
        if telegramActive {
            message = "openclaw에 telegram 채널이 활성화되어 있어요."
        } else {
            message = "openclaw는 감지했지만 telegram 채널이 비활성이에요. `openclaw channels add --channel telegram --token <token>`로 등록하세요."
        }
        return Status(installed: true, version: version, telegramActive: telegramActive, message: message)
    }

    public struct Status: Sendable, Equatable {
        public let installed: Bool
        public let version: String?
        public let telegramActive: Bool
        public let message: String

        public init(installed: Bool, version: String?, telegramActive: Bool, message: String) {
            self.installed = installed
            self.version = version
            self.telegramActive = telegramActive
            self.message = message
        }
    }
}
