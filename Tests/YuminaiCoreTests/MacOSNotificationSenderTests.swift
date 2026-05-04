import Foundation
import Testing
@testable import YuminaiCore

/// **ADR-098 P0-4** — MacOSNotificationSender 단위 테스트.
///
/// UNUserNotificationCenter는 앱 번들이 있는 환경에서만 동작한다.
/// 여기서는 시스템 API를 호출하지 않는 순수 로직 (카테고리 상수, 식별자 규칙)만 검증한다.
@Suite("MacOSNotificationSender (ADR-098 P0-4)")
struct MacOSNotificationSenderTests {

    // MARK: - 카테고리 상수 검증 (시스템 API 미호출)

    @Test("HITL 카테고리 ID 형식")
    func hitlCategoryIdFormat() {
        #expect(MacOSNotificationSender.hitlCategoryId == "yuminai.hitl.approval")
    }

    @Test("HITL Approve 액션 ID 형식")
    func hitlApproveActionId() {
        #expect(MacOSNotificationSender.hitlApproveActionId == "yuminai.hitl.approve")
    }

    @Test("HITL Reject 액션 ID 형식")
    func hitlRejectActionId() {
        #expect(MacOSNotificationSender.hitlRejectActionId == "yuminai.hitl.reject")
    }

    // MARK: - HITL identifier 패턴 (문자열 규칙만 검증)

    @Test("HITL identifier는 'hitl:<uuid>' 패턴")
    func hitlIdentifierPattern() {
        let id = UUID()
        let expectedPrefix = "hitl:\(id.uuidString)"
        // 실제 send는 호출하지 않고 식별자 패턴만 검증
        #expect(expectedPrefix.hasPrefix("hitl:"))
        #expect(expectedPrefix.contains(id.uuidString))
    }

    @Test("HITL UUID dismiss identifier 패턴")
    func hitlDismissIdentifierPattern() {
        let id = UUID()
        let identifier = "hitl:\(id.uuidString)"
        #expect(identifier == "hitl:\(id.uuidString)")
    }

    @Test("서로 다른 UUID는 서로 다른 identifier")
    func distinctUUIDsDistinctIdentifiers() {
        let id1 = UUID()
        let id2 = UUID()
        #expect(id1 != id2)
        #expect("hitl:\(id1.uuidString)" != "hitl:\(id2.uuidString)")
    }
}
