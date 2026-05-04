import Foundation
import YuminaiCore

/// 테스트용 인메모리 Telegram bot.
///
/// 송신은 배열에 누적, 수신은 `injectIncoming(_:)`으로 주입한다.
public final actor MockTelegramBot: TelegramClient {
    public private(set) var sentLog: [(text: String, chatId: Int64)] = []
    public private(set) var editLog: [(messageId: Int64, chatId: Int64, text: String)] = []

    public nonisolated let incoming: AsyncStream<IncomingTelegramMessage>
    private nonisolated let incomingContinuation: AsyncStream<IncomingTelegramMessage>.Continuation

    public init() {
        var cont: AsyncStream<IncomingTelegramMessage>.Continuation!
        self.incoming = AsyncStream<IncomingTelegramMessage> { c in cont = c }
        self.incomingContinuation = cont
    }

    public func send(_ text: String, to chatId: Int64) async throws -> SentTelegramMessage {
        sentLog.append((text, chatId))
        return SentTelegramMessage(
            messageId: Int64.random(in: 1...1_000_000),
            chatId: chatId
        )
    }

    /// **ADR-056 Phase 2** — keyboard 첨부 메시지. mock은 단순 send + button 정보 log.
    public private(set) var sentKeyboardLog: [(text: String, chatId: Int64, buttons: [[InlineButton]])] = []
    public func sendWithKeyboard(
        _ text: String,
        to chatId: Int64,
        buttons: [[InlineButton]]
    ) async throws -> SentTelegramMessage {
        sentLog.append((text, chatId))
        sentKeyboardLog.append((text, chatId, buttons))
        return SentTelegramMessage(
            messageId: Int64.random(in: 1...1_000_000),
            chatId: chatId
        )
    }

    public func edit(messageId: Int64, in chatId: Int64, text: String) async throws {
        editLog.append((messageId, chatId, text))
    }

    /// **ADR-057 Phase 1** — answerCallback log (mock).
    public private(set) var answeredCallbacks: [(id: String, text: String?)] = []
    public func answerCallback(_ callbackQueryId: String, text: String?) async throws {
        answeredCallbacks.append((callbackQueryId, text))
    }

    public func startPolling() async throws {}
    public func stopPolling() async {}

    /// **ADR-094 Phase 3** — setMyCommands log (mock).
    public private(set) var setCommandsLog: [[(command: String, description: String)]] = []
    public func setMyCommands(_ commands: [(command: String, description: String)]) async throws {
        setCommandsLog.append(commands)
    }

    /// **ADR-096 Phase C** — sendDocument log (mock).
    public private(set) var sentDocumentLog: [(fileName: String, data: Data, caption: String?, chatId: Int64)] = []
    public func sendDocument(
        fileName: String,
        data: Data,
        caption: String?,
        to chatId: Int64
    ) async throws -> SentTelegramMessage {
        sentDocumentLog.append((fileName, data, caption, chatId))
        sentLog.append((caption ?? fileName, chatId))
        return SentTelegramMessage(
            messageId: Int64.random(in: 1...1_000_000),
            chatId: chatId
        )
    }

    /// 테스트에서 사용자 incoming 메시지를 시뮬레이션.
    public nonisolated func injectIncoming(_ message: IncomingTelegramMessage) {
        incomingContinuation.yield(message)
    }
}
