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

    /// **ADR-057 Phase 1** — inline keyboard 클릭에 ✓ 응답 (사용자 인지 ↑).
    /// callback_query_id는 callback_query update에서 옴 — Yuminai의 IncomingTelegramMessage에는
    /// 단순화 위해 callbackQueryId 별도 필드 없음. 향후 caller가 알 수 있게 확장 시 사용.
    /// 현재는 caller가 직접 raw id를 보관해서 호출.
    func answerCallback(_ callbackQueryId: String, text: String?) async throws

    /// long-polling으로 사용자 메시지를 받는 스트림. 앱 실행 중일 때만 동작.
    /// 화이트리스트(허용 user ID)에 없는 메시지는 묵시적으로 무시한다.
    var incoming: AsyncStream<IncomingTelegramMessage> { get }

    func startPolling() async throws
    func stopPolling() async

    /// **ADR-094 Phase 3** — BotFather setMyCommands API.
    /// `commands` 배열의 command는 "/" prefix 없이 전달해야 한다 (Telegram API 규격).
    /// command 최대 32자, description 최대 256자.
    func setMyCommands(_ commands: [(command: String, description: String)]) async throws
}

/// **ADR-056 Phase 2** — Telegram inline keyboard button.
public struct InlineButton: Sendable, Hashable, Codable {
    public let text: String
    /// 사용자가 누르면 callback_query로 들어옴 (max 64 bytes).
    /// **ADR-057 Critical Fix 5** — init에서 64 bytes 초과 시 자동 truncate (data loss 보다 그것이 안전).
    public let callbackData: String

    /// Telegram 한도.
    public static let maxCallbackDataBytes = 64

    public init(text: String, callbackData: String) {
        self.text = text
        // ADR-057 Critical Fix 5 — 64 bytes 초과 자동 truncate (silent fail 방지)
        // utf8 byte count로 검사 (Telegram API spec)
        let utf8Count = callbackData.utf8.count
        if utf8Count > Self.maxCallbackDataBytes {
            // safe truncate at character boundary
            var truncated = callbackData
            while truncated.utf8.count > Self.maxCallbackDataBytes && !truncated.isEmpty {
                truncated.removeLast()
            }
            #if DEBUG
            print("[InlineButton] callback_data truncated (\(utf8Count) > \(Self.maxCallbackDataBytes)): \(callbackData) → \(truncated)")
            #endif
            self.callbackData = truncated
        } else {
            self.callbackData = callbackData
        }
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
    /// **ADR-057 Phase 1** — callback_query.id (answerCallbackQuery 호출 시 필요).
    /// callbackData 있을 때만 nil 아님.
    public let callbackQueryId: String?

    public init(
        updateId: Int64,
        userId: Int64,
        chatId: Int64,
        text: String?,
        receivedAt: Date = Date(),
        isFromBot: Bool = false,
        callbackData: String? = nil,
        callbackQueryId: String? = nil
    ) {
        self.updateId = updateId
        self.userId = userId
        self.chatId = chatId
        self.text = text
        self.receivedAt = receivedAt
        self.isFromBot = isFromBot
        self.callbackData = callbackData
        self.callbackQueryId = callbackQueryId
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
