import Foundation
import YuminaiCore

/// 작업 lifecycle 이벤트를 Telegram 메시지로 변환해 송신.
///
/// 정책(`TelegramAlertPolicy`)에 따라 송신/스킵 결정. 송신 실패는 silent
/// (작업 흐름을 차단하지 않음).
///
/// **ADR-095 Phase 4** — `NotificationPolicyMatrix` + `DeviceState` + quiet hours를
/// 고려한 채널 결정 추가. `deliveryChannelProvider`를 통해 AppModel이 주입한
/// 현재 채널 결정 로직을 사용한다.
public final actor TelegramAlertDispatcher {
    private let client: any TelegramClient
    private var policy: TelegramAlertPolicy
    private let chatId: Int64
    /// **ADR-095 Phase 4** — 현재 전달 채널 결정 provider.
    /// AppModel의 `currentDeliveryChannel(for:)` 클로저를 주입받는다.
    /// nil이면 기존 동작 유지 (policy만 체크, Telegram으로 전송).
    private var deliveryChannelProvider: (@Sendable (NotificationKind) -> DeliveryChannel)?

    public init(
        client: any TelegramClient,
        policy: TelegramAlertPolicy,
        chatId: Int64,
        deliveryChannelProvider: (@Sendable (NotificationKind) -> DeliveryChannel)? = nil
    ) {
        self.client = client
        self.policy = policy
        self.chatId = chatId
        self.deliveryChannelProvider = deliveryChannelProvider
    }

    public func updatePolicy(_ policy: TelegramAlertPolicy) {
        self.policy = policy
    }

    /// **ADR-095 Phase 4** — delivery channel provider 업데이트.
    public func updateDeliveryChannelProvider(_ provider: @escaping @Sendable (NotificationKind) -> DeliveryChannel) {
        self.deliveryChannelProvider = provider
    }

    public func dispatch(category: AlertCategory, message: String) async {
        guard shouldSend(category) else { return }

        let kind = notificationKind(for: category)
        let channel = deliveryChannelProvider?(kind) ?? .telegramOnly

        switch channel {
        case .telegramOnly, .both:
            let formatted = Self.formatted(category, message)
            _ = try? await client.send(formatted, to: chatId)
        case .macOSOnly:
            // macOS 알림은 AppModel 쪽에서 처리 — 여기선 Telegram 전송만 담당
            break
        case .suppressed:
            // no-op (로그만)
            break
        }
    }

    // MARK: - Private

    private func shouldSend(_ category: AlertCategory) -> Bool {
        switch category {
        case .workComplete: return policy.sendOnComplete
        case .workFailed: return policy.sendOnError
        case .decisionRequired: return policy.sendOnDecisionRequired
        case .info: return true
        }
    }

    /// `AlertCategory` → `NotificationKind` 매핑.
    private func notificationKind(for category: AlertCategory) -> NotificationKind {
        switch category {
        case .workComplete: return .taskCompleteSuccess
        case .workFailed: return .taskCompleteFailure
        case .decisionRequired: return .hitlApprovalRequest
        case .info: return .generalAlert
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
