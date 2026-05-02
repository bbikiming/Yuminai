import Foundation

/// Telegram bot 통신 추상화. 구현은 `YuminaiTelegram.LiveTelegramBot`.
public protocol TelegramClient: Sendable {
    /// 메시지 전송.
    func send(_ text: String, to chatId: Int64) async throws -> SentTelegramMessage

    /// **ADR-056 Phase 2** — inline keyboard 첨부 메시지 전송.
    /// `buttons`는 [[InlineButton]] 형태 (rows × columns).
    /// callback_data는 callback로 incoming 들어옴 (text=nil, callbackData=...).
    func sendWithKeyboard(
        _ text: String,
        to chatId: Int64,
        buttons: [[InlineButton]]
    ) async throws -> SentTelegramMessage

    /// (옵션) 기존 메시지 본문 갱신 — 작업 진행 상황 한 메시지에 누적 갱신할 때.
    func edit(messageId: Int64, in chatId: Int64, text: String) async throws

    /// long-polling으로 사용자 메시지를 받는 스트림. 앱 실행 중일 때만 동작.
    /// 화이트리스트(허용 user ID)에 없는 메시지는 묵시적으로 무시한다.
    var incoming: AsyncStream<IncomingTelegramMessage> { get }

    func startPolling() async throws
    func stopPolling() async
}

/// **ADR-056 Phase 2** — Telegram inline keyboard button.
public struct InlineButton: Sendable, Hashable, Codable {
    public let text: String
    /// 사용자가 누르면 callback_query로 들어옴 (max 64 bytes).
    public let callbackData: String

    public init(text: String, callbackData: String) {
        self.text = text
        self.callbackData = callbackData
    }
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
    /// **ADR-056 Phase 2** — inline keyboard 버튼 클릭 시 callback_data가 여기에.
    /// `text`는 nil, `callbackData`는 button 정의 시 지정한 값.
    public let callbackData: String?

    public init(
        updateId: Int64,
        userId: Int64,
        chatId: Int64,
        text: String?,
        receivedAt: Date = Date(),
        isFromBot: Bool = false,
        callbackData: String? = nil
    ) {
        self.updateId = updateId
        self.userId = userId
        self.chatId = chatId
        self.text = text
        self.receivedAt = receivedAt
        self.isFromBot = isFromBot
        self.callbackData = callbackData
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
