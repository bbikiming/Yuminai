import Foundation
import Testing
@testable import YuminaiCore

/// **ADR-095 Phase 4** — NotificationPolicyMatrix 유닛 테스트.
@Suite("NotificationPolicyMatrix (ADR-095 Phase 4)")
struct NotificationPolicyMatrixTests {

    // MARK: - Default 값 검증 (ADR-092 §4.8 표)

    @Test("hitlApprovalRequest — active: macOSOnly")
    func hitlApprovalRequestActive() {
        let matrix = NotificationPolicyMatrix.default
        #expect(matrix.channel(for: .hitlApprovalRequest, in: .desktopActive) == .macOSOnly)
    }

    @Test("hitlApprovalRequest — idle: both")
    func hitlApprovalRequestIdle() {
        let matrix = NotificationPolicyMatrix.default
        #expect(matrix.channel(for: .hitlApprovalRequest, in: .desktopIdle) == .both)
    }

    @Test("hitlApprovalRequest — off: telegramOnly")
    func hitlApprovalRequestOff() {
        let matrix = NotificationPolicyMatrix.default
        #expect(matrix.channel(for: .hitlApprovalRequest, in: .desktopOff) == .telegramOnly)
    }

    @Test("taskCompleteSuccess — active: macOSOnly, idle: suppressed, off: telegramOnly")
    func taskCompleteSuccess() {
        let matrix = NotificationPolicyMatrix.default
        #expect(matrix.channel(for: .taskCompleteSuccess, in: .desktopActive) == .macOSOnly)
        #expect(matrix.channel(for: .taskCompleteSuccess, in: .desktopIdle) == .suppressed)
        #expect(matrix.channel(for: .taskCompleteSuccess, in: .desktopOff) == .telegramOnly)
    }

    @Test("taskCompleteFailure — active: both, idle: both, off: telegramOnly")
    func taskCompleteFailure() {
        let matrix = NotificationPolicyMatrix.default
        #expect(matrix.channel(for: .taskCompleteFailure, in: .desktopActive) == .both)
        #expect(matrix.channel(for: .taskCompleteFailure, in: .desktopIdle) == .both)
        #expect(matrix.channel(for: .taskCompleteFailure, in: .desktopOff) == .telegramOnly)
    }

    @Test("rateLimitAlert — active: macOSOnly, idle: suppressed, off: telegramOnly")
    func rateLimitAlert() {
        let matrix = NotificationPolicyMatrix.default
        #expect(matrix.channel(for: .rateLimitAlert, in: .desktopActive) == .macOSOnly)
        #expect(matrix.channel(for: .rateLimitAlert, in: .desktopIdle) == .suppressed)
        #expect(matrix.channel(for: .rateLimitAlert, in: .desktopOff) == .telegramOnly)
    }

    @Test("generalAlert — active: macOSOnly, idle: macOSOnly, off: telegramOnly")
    func generalAlert() {
        let matrix = NotificationPolicyMatrix.default
        #expect(matrix.channel(for: .generalAlert, in: .desktopActive) == .macOSOnly)
        #expect(matrix.channel(for: .generalAlert, in: .desktopIdle) == .macOSOnly)
        #expect(matrix.channel(for: .generalAlert, in: .desktopOff) == .telegramOnly)
    }

    // MARK: - channel(for:in:) — 항목 없으면 안전 기본값

    @Test("channel(for:in:) — 빈 매트릭스는 macOSOnly 반환")
    func emptyMatrixFallback() {
        let matrix = NotificationPolicyMatrix(rules: [:])
        #expect(matrix.channel(for: .generalAlert, in: .desktopActive) == .macOSOnly)
        #expect(matrix.channel(for: .hitlApprovalRequest, in: .desktopOff) == .macOSOnly)
    }

    // MARK: - Codable round-trip

    @Test("Codable round-trip — default 값")
    func roundTripDefault() throws {
        let original = NotificationPolicyMatrix.default
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NotificationPolicyMatrix.self, from: data)

        for kind in NotificationKind.allCases {
            for state in [DeviceState.desktopActive, .desktopIdle, .desktopOff] {
                #expect(
                    decoded.channel(for: kind, in: state) == original.channel(for: kind, in: state),
                    "Mismatch: kind=\(kind.rawValue) state=\(state.rawValue)"
                )
            }
        }
    }

    @Test("Codable round-trip — 커스텀 규칙")
    func roundTripCustom() throws {
        let custom = NotificationPolicyMatrix(rules: [
            .taskCompleteSuccess: [
                .desktopActive: .both,
                .desktopIdle: .telegramOnly,
                .desktopOff: .suppressed
            ]
        ])
        let data = try JSONEncoder().encode(custom)
        let decoded = try JSONDecoder().decode(NotificationPolicyMatrix.self, from: data)

        #expect(decoded.channel(for: .taskCompleteSuccess, in: .desktopActive) == .both)
        #expect(decoded.channel(for: .taskCompleteSuccess, in: .desktopIdle) == .telegramOnly)
        #expect(decoded.channel(for: .taskCompleteSuccess, in: .desktopOff) == .suppressed)
    }

    // MARK: - NotificationKind CaseIterable

    @Test("NotificationKind.allCases — 5개")
    func allKindsCount() {
        #expect(NotificationKind.allCases.count == 5)
    }

    // MARK: - DeliveryChannel CaseIterable

    @Test("DeliveryChannel.allCases — 4개")
    func allChannelsCount() {
        #expect(DeliveryChannel.allCases.count == 4)
    }
}
