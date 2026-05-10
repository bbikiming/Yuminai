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
    /// **ADR-095 Phase 4 / ADR-153 P0-1** — 현재 전달 채널 결정 async provider.
    /// AppModel의 `currentDeliveryChannel(for:)` async 클로저를 주입받는다.
    /// nil이면 기존 동작 유지 (policy만 체크, Telegram으로 전송).
    /// ADR-153: sync provider → async provider로 변경 (MainActor.assumeIsolated 제거).
    private var deliveryChannelProvider: (@Sendable (NotificationKind) async -> DeliveryChannel)?

    public init(
        client: any TelegramClient,
        policy: TelegramAlertPolicy,
        chatId: Int64,
        deliveryChannelProvider: (@Sendable (NotificationKind) async -> DeliveryChannel)? = nil
    ) {
        self.client = client
        self.policy = policy
        self.chatId = chatId
        self.deliveryChannelProvider = deliveryChannelProvider
    }

    public func updatePolicy(_ policy: TelegramAlertPolicy) {
        self.policy = policy
    }

    /// **ADR-095 Phase 4 / ADR-153 P0-1** — async delivery channel provider 업데이트.
    public func updateDeliveryChannelProvider(_ provider: @escaping @Sendable (NotificationKind) async -> DeliveryChannel) {
        self.deliveryChannelProvider = provider
    }

    public func dispatch(category: AlertCategory, message: String) async {
        guard shouldSend(category) else { return }

        let kind = notificationKind(for: category)
        let channel: DeliveryChannel
        if let provider = deliveryChannelProvider {
            channel = await provider(kind)
        } else {
            channel = .telegramOnly
        }

        switch channel {
        case .telegramOnly:
            let formatted = Self.formatted(category, message)
            _ = try? await client.send(formatted, to: chatId)
        case .both:
            let formatted = Self.formatted(category, message)
            _ = try? await client.send(formatted, to: chatId)
            // **ADR-098 P0-4** — macOS 알림도 동시 발송
            try? await MacOSNotificationSender.send(
                title: Self.notificationTitle(for: category),
                body: message
            )
        case .macOSOnly:
            // **ADR-098 P0-4** — macOS 알림 발송 (Telegram 전송 skip)
            try? await MacOSNotificationSender.send(
                title: Self.notificationTitle(for: category),
                body: message
            )
        case .suppressed:
            // no-op (quiet hours / matrix 정책 적용됨)
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

    /// **ADR-098 P0-4** — macOS 알림 제목 (Telegram label과 별도 UX).
    private static func notificationTitle(for category: AlertCategory) -> String {
        switch category {
        case .workComplete: return "Yuminai — 작업 완료"
        case .workFailed: return "Yuminai — 작업 실패"
        case .decisionRequired: return "Yuminai — 승인 필요"
        case .info: return "Yuminai"
        }
    }
}
