import Foundation

/// Telegram bot 통신 추상화. 구현은 `YuminaiTelegram.LiveTelegramBot`.
public protocol TelegramClient: Sendable {
    /// 메시지 전송.
    func send(_ text: String, to chatId: Int64) async throws -> SentTelegramMessage

    /// (옵션) 기존 메시지 본문 갱신 — 작업 진행 상황 한 메시지에 누적 갱신할 때.
    func edit(messageId: Int64, in chatId: Int64, text: String) async throws

    /// long-polling으로 사용자 메시지를 받는 스트림. 앱 실행 중일 때만 동작.
    /// 화이트리스트(허용 user ID)에 없는 메시지는 묵시적으로 무시한다.
    var incoming: AsyncStream<IncomingTelegramMessage> { get }

    func startPolling() async throws
    func stopPolling() async
}

public struct SentTelegramMessage: Sendable, Hashable {
    public let messageId: Int64
    public let chatId: Int64
    public let sentAt: Date

    public init(messageId: Int64, chatId: Int64, sentAt: Date = Date()) {
        self.messageId = messageId
        self.chatId = chatId
        self.sentAt = sentAt
    }
}

public struct IncomingTelegramMessage: Sendable, Hashable {
    public let updateId: Int64
    public let userId: Int64
    public let chatId: Int64
    public let text: String?
    public let receivedAt: Date
    /// ADR-045 — bot reflection 방지. true면 다른 봇이 보낸 메시지로 무시.
    public let isFromBot: Bool

    public init(
        updateId: Int64,
        userId: Int64,
        chatId: Int64,
        text: String?,
        receivedAt: Date = Date(),
        isFromBot: Bool = false
    ) {
        self.updateId = updateId
        self.userId = userId
        self.chatId = chatId
        self.text = text
        self.receivedAt = receivedAt
        self.isFromBot = isFromBot
    }
}

/// Telegram 알림 발송 정책.
public struct TelegramAlertPolicy: Sendable, Codable, Hashable {
    public var sendOnComplete: Bool
    public var sendOnError: Bool
    public var sendOnDecisionRequired: Bool

    public init(
        sendOnComplete: Bool = true,
        sendOnError: Bool = true,
        sendOnDecisionRequired: Bool = true
    ) {
        self.sendOnComplete = sendOnComplete
        self.sendOnError = sendOnError
        self.sendOnDecisionRequired = sendOnDecisionRequired
    }

    public static let `default` = TelegramAlertPolicy()
}

/// 알림 카테고리. Yuminai → Telegram으로 보낼 때의 분류.
public enum AlertCategory: String, Sendable, Codable, CaseIterable {
    case workComplete = "complete"
    case workFailed = "failed"
    case decisionRequired = "decision"
    case info = "info"
}
