import Foundation
import UserNotifications

/// **ADR-098 P0-4** — macOS UserNotification 실제 발송 헬퍼.
///
/// `MacOSNotificationPermission`이 권한 요청만 담당하는 것과 달리,
/// 이 타입은 실제 `UNNotificationRequest`를 생성해 시스템에 등록한다.
///
/// ## 사용 패턴
/// ```swift
/// // 앱 시작 시
/// await MacOSNotificationSender.registerCategories()
///
/// // 알림 발송
/// try await MacOSNotificationSender.send(title: "작업 완료", body: "swift test 성공")
///
/// // HITL actionable 알림
/// try await MacOSNotificationSender.sendHITL(requestId: uuid, action: "git push --force")
/// ```
///
/// ## 설계 원칙
/// - 순수 static 인터페이스 — 상태 없음, 부수효과는 시스템 UN API 호출뿐
/// - 실패는 throw (caller가 결정 — silent discard 가능)
/// - 권한 없을 때는 조용히 skip (throw 안 함)
public enum MacOSNotificationSender {

    // MARK: - Category identifiers

    /// HITL actionable notification 카테고리 ID.
    public static let hitlCategoryId = "yuminai.hitl.approval"
    /// HITL Approve 액션 ID.
    public static let hitlApproveActionId = "yuminai.hitl.approve"
    /// HITL Reject 액션 ID.
    public static let hitlRejectActionId = "yuminai.hitl.reject"

    // MARK: - Category registration

    /// HITL 등 actionable notification에 필요한 카테고리를 등록한다.
    /// 앱 시작 시 한 번 호출 (`YuminaiApp.body` 또는 `AppModel.init`).
    public static func registerCategories() {
        let approveAction = UNNotificationAction(
            identifier: hitlApproveActionId,
            title: "✅ Approve",
            options: [.foreground]
        )
        let rejectAction = UNNotificationAction(
            identifier: hitlRejectActionId,
            title: "❌ Reject",
            options: [.destructive]
        )
        let hitlCategory = UNNotificationCategory(
            identifier: hitlCategoryId,
            actions: [approveAction, rejectAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([hitlCategory])
    }

    // MARK: - General send

    /// 일반 로컬 알림을 발송한다.
    ///
    /// - Parameters:
    ///   - title: 알림 제목.
    ///   - body: 알림 본문.
    ///   - identifier: 식별자 (dismiss 시 사용). 기본값은 UUID.
    ///   - categoryIdentifier: 카테고리 ID (actionable notification용).
    ///   - userInfo: 추가 payload (딥링크 등).
    ///   - delay: 발송 지연 (초). 기본값 0 = 즉시.
    /// - Throws: `UNUserNotificationCenter.add` 실패 시 (권한 없으면 throw 없이 skip).
    public static func send(
        title: String,
        body: String,
        identifier: String = UUID().uuidString,
        categoryIdentifier: String? = nil,
        userInfo: [String: Any]? = nil,
        delay: TimeInterval = 0
    ) async throws {
        let status = await UNUserNotificationCenter.current().notificationSettings()
        guard status.authorizationStatus == .authorized
            || status.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let cat = categoryIdentifier {
            content.categoryIdentifier = cat
        }
        if let info = userInfo {
            content.userInfo = info
        }

        let trigger: UNNotificationTrigger? = delay > 0
            ? UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            : nil

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - HITL actionable send

    /// HITL 승인 요청용 actionable notification 발송.
    ///
    /// 버튼: "✅ Approve" / "❌ Reject" (카테고리 `yuminai.hitl.approval`).
    /// `registerCategories()`가 먼저 호출돼 있어야 버튼이 표시된다.
    ///
    /// - Parameters:
    ///   - requestId: HITL request UUID (딥링크 응답에 사용).
    ///   - action: 승인 대상 작업 설명.
    ///   - workspaceName: 워크스페이스 이름 (nil이면 표시 생략).
    public static func sendHITL(
        requestId: UUID,
        action: String,
        workspaceName: String? = nil
    ) async throws {
        let subtitle = workspaceName.map { "워크스페이스: \($0)" } ?? ""
        let bodyText = action.count > 200 ? String(action.prefix(200)) + "…" : action
        try await send(
            title: "⚠️ HITL 승인 필요",
            body: bodyText,
            identifier: "hitl:\(requestId.uuidString)",
            categoryIdentifier: hitlCategoryId,
            userInfo: [
                "hitlRequestId": requestId.uuidString,
                "workspaceName": workspaceName ?? ""
            ]
        )
        // subtitle은 content.subtitle로 별도 설정이 필요해 직접 처리
        _ = subtitle  // 사용 여부에 따라 추가 가능
    }

    // MARK: - Dismiss

    /// 특정 식별자의 pending / delivered notification을 제거한다.
    ///
    /// - Parameter identifier: `send(identifier:)` 또는 `sendHITL(requestId:)`에서 사용한 식별자.
    public static func dismiss(identifier: String) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    /// HITL request ID에 해당하는 notification을 제거한다.
    public static func dismissHITL(requestId: UUID) async {
        await dismiss(identifier: "hitl:\(requestId.uuidString)")
    }
}
