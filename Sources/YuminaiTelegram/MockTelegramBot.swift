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

    public func edit(messageId: Int64, in chatId: Int64, text: String) async throws {
        editLog.append((messageId, chatId, text))
    }

    public func startPolling() async throws {}
    public func stopPolling() async {}

    /// 테스트에서 사용자 incoming 메시지를 시뮬레이션.
    public nonisolated func injectIncoming(_ message: IncomingTelegramMessage) {
        incomingContinuation.yield(message)
    }
}
