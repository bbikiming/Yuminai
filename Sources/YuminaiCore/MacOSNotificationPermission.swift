import Foundation
import UserNotifications

/// **ADR-097** — macOS UserNotification 권한 상태 조회 + 요청.
///
/// `UNUserNotificationCenter`를 래핑하여 권한 상태를 Swift enum으로 제공.
/// 시스템 sandbox/entitlement 환경에서 unavailable 케이스도 처리한다.
public enum MacOSNotificationPermission {

    // MARK: - Status

    public enum Status: String, Sendable, Equatable, CaseIterable {
        case notDetermined
        case denied
        case authorized
        case provisional
        case ephemeral
        case unavailable  // sandbox / 지원 불가 환경
    }

    // MARK: - Public API

    /// 현재 알림 권한 상태를 비동기로 조회한다.
    public static func currentStatus() async -> Status {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return status(from: settings.authorizationStatus)
    }

    /// 알림 권한을 요청한다. 이미 authorized면 즉시 반환.
    ///
    /// - Returns: 요청 후 갱신된 권한 상태.
    public static func requestPermission() async -> Status {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            return granted ? .authorized : .denied
        } catch {
            // 권한 요청 자체가 실패 (sandbox 등)
            return .unavailable
        }
    }

    // MARK: - Private

    private static func status(from authStatus: UNAuthorizationStatus) -> Status {
        switch authStatus {
        case .notDetermined:   return .notDetermined
        case .denied:          return .denied
        case .authorized:      return .authorized
        case .provisional:     return .provisional
        case .ephemeral:       return .ephemeral
        @unknown default:      return .unavailable
        }
    }
}
