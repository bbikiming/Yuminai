import Foundation
import YuminaiCore

/// 작업 lifecycle 이벤트를 Telegram 메시지로 변환해 송신.
///
/// 정책(`TelegramAlertPolicy`)에 따라 송신/스킵 결정. 송신 실패는 silent
/// (작업 흐름을 차단하지 않음).
public final actor TelegramAlertDispatcher {
    private let client: any TelegramClient
    private var policy: TelegramAlertPolicy
    private let chatId: Int64

    public init(client: any TelegramClient, policy: TelegramAlertPolicy, chatId: Int64) {
        self.client = client
        self.policy = policy
        self.chatId = chatId
    }

    public func updatePolicy(_ policy: TelegramAlertPolicy) {
        self.policy = policy
    }

    public func dispatch(category: AlertCategory, message: String) async {
        guard shouldSend(category) else { return }
        let formatted = Self.formatted(category, message)
        _ = try? await client.send(formatted, to: chatId)
    }

    private func shouldSend(_ category: AlertCategory) -> Bool {
        switch category {
        case .workComplete: return policy.sendOnComplete
        case .workFailed: return policy.sendOnError
        case .decisionRequired: return policy.sendOnDecisionRequired
        case .info: return true
        }
    }

    private static func formatted(_ category: AlertCategory, _ message: String) -> String {
        let label: String
        switch category {
        case .workComplete: label = "[COMPLETE]"
        case .workFailed: label = "[FAILED]"
        case .decisionRequired: label = "[DECISION]"
        case .info: label = "[INFO]"
        }
        return "\(label) \(message)"
    }
}
