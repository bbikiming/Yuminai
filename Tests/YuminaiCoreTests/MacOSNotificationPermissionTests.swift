import Foundation
import Testing
@testable import YuminaiCore

/// **ADR-097** — MacOSNotificationPermission 유닛 테스트.
///
/// 시스템 권한 요청은 단위 테스트에서 모킹 불가 — Status enum 동작만 검증.
@Suite("MacOSNotificationPermission (ADR-097)")
struct MacOSNotificationPermissionTests {

    // MARK: - Status Equatable

    @Test("Status Equatable — 동일 케이스")
    func statusEquality() {
        #expect(MacOSNotificationPermission.Status.authorized == .authorized)
        #expect(MacOSNotificationPermission.Status.denied == .denied)
        #expect(MacOSNotificationPermission.Status.notDetermined == .notDetermined)
    }

    @Test("Status Equatable — 다른 케이스")
    func statusInequality() {
        #expect(MacOSNotificationPermission.Status.authorized != .denied)
        #expect(MacOSNotificationPermission.Status.notDetermined != .provisional)
    }

    // MARK: - Status rawValue

    @Test("Status rawValue 문자열 매핑")
    func statusRawValues() {
        #expect(MacOSNotificationPermission.Status.notDetermined.rawValue == "notDetermined")
        #expect(MacOSNotificationPermission.Status.denied.rawValue == "denied")
        #expect(MacOSNotificationPermission.Status.authorized.rawValue == "authorized")
        #expect(MacOSNotificationPermission.Status.provisional.rawValue == "provisional")
        #expect(MacOSNotificationPermission.Status.ephemeral.rawValue == "ephemeral")
        #expect(MacOSNotificationPermission.Status.unavailable.rawValue == "unavailable")
    }

    @Test("Status CaseIterable — 6개 케이스")
    func statusAllCases() {
        #expect(MacOSNotificationPermission.Status.allCases.count == 6)
    }
}
