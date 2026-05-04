import Foundation
import Testing
@testable import YuminaiCore

/// **ADR-096** — NotificationPolicy 편집 + Quiet Hours + DeviceState.allCases 추가 테스트.
@Suite("ADR-096 NotificationPolicy Settings")
struct ADR096NotificationSettingsTests {

    // MARK: - DeviceState.allCases (ADR-096에서 CaseIterable 추가)

    @Test("DeviceState.allCases — 3개 (active / idle / off)")
    func deviceStateAllCases() {
        #expect(DeviceState.allCases.count == 3)
        #expect(DeviceState.allCases.contains(.desktopActive))
        #expect(DeviceState.allCases.contains(.desktopIdle))
        #expect(DeviceState.allCases.contains(.desktopOff))
    }

    // MARK: - NotificationPolicyMatrix 단일 셀 변경

    @Test("단일 셀 변경 — generalAlert/active를 both로")
    func singleCellUpdate() {
        var matrix = NotificationPolicyMatrix.default
        var updatedRules = matrix.rules
        var stateMap = updatedRules[.generalAlert] ?? [:]
        stateMap[.desktopActive] = .both
        updatedRules[.generalAlert] = stateMap
        matrix = NotificationPolicyMatrix(rules: updatedRules)

        #expect(matrix.channel(for: .generalAlert, in: .desktopActive) == .both)
        // 다른 셀은 그대로
        #expect(matrix.channel(for: .generalAlert, in: .desktopIdle) == .macOSOnly)
        #expect(matrix.channel(for: .hitlApprovalRequest, in: .desktopActive) == .macOSOnly)
    }

    // MARK: - AppPreferences 불변 업데이트 패턴 (ADR-096 AppModel 메서드 패턴 검증)

    @Test("AppPreferences quietHours 업데이트 — spread 불변 패턴")
    func quietHoursImmutableUpdate() {
        var prefs = AppPreferences()
        #expect(prefs.quietHoursStart == nil)
        #expect(prefs.quietHoursEnd == nil)

        // AppModel.updateQuietHours 내부와 동일한 패턴
        prefs = { var p = prefs; p.quietHoursStart = 22; p.quietHoursEnd = 8; return p }()
        #expect(prefs.quietHoursStart == 22)
        #expect(prefs.quietHoursEnd == 8)

        // 비활성화
        prefs = { var p = prefs; p.quietHoursStart = nil; p.quietHoursEnd = nil; return p }()
        #expect(prefs.quietHoursStart == nil)
        #expect(prefs.quietHoursEnd == nil)
    }

    @Test("AppPreferences hitlTimeoutSeconds 기본값 60 + 업데이트")
    func hitlTimeoutUpdate() {
        var prefs = AppPreferences()
        #expect(prefs.hitlTimeoutSeconds == 60)

        prefs = { var p = prefs; p.hitlTimeoutSeconds = 120; return p }()
        #expect(prefs.hitlTimeoutSeconds == 120)
    }

    @Test("AppPreferences diffPreviewLineLimit 기본값 30 + 업데이트")
    func diffLimitUpdate() {
        var prefs = AppPreferences()
        #expect(prefs.diffPreviewLineLimit == 30)

        prefs = { var p = prefs; p.diffPreviewLineLimit = 50; return p }()
        #expect(prefs.diffPreviewLineLimit == 50)
    }

    @Test("notificationPolicy default 재설정 — 매트릭스 내용 동일")
    func resetToDefault() {
        var prefs = AppPreferences()
        // 변경
        var updatedRules = prefs.notificationPolicy.rules
        var stateMap = updatedRules[.generalAlert] ?? [:]
        stateMap[.desktopActive] = .suppressed
        updatedRules[.generalAlert] = stateMap
        prefs = { var p = prefs; p.notificationPolicy = NotificationPolicyMatrix(rules: updatedRules); return p }()

        #expect(prefs.notificationPolicy.channel(for: .generalAlert, in: .desktopActive) == .suppressed)

        // 재설정
        prefs = { var p = prefs; p.notificationPolicy = .default; return p }()
        #expect(prefs.notificationPolicy.channel(for: .generalAlert, in: .desktopActive) == .macOSOnly)
    }
}
