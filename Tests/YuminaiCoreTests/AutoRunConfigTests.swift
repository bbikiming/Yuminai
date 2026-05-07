import Foundation
import Testing
@testable import YuminaiCore

@Suite("AutoRunConfig (ADR-132)")
struct AutoRunConfigTests {

    // MARK: - default 값 검증

    @Test("default config — enabled == false")
    func defaultIsDisabled() {
        #expect(AutoRunConfig.default.enabled == false)
    }

    @Test("default config — maxTurns == 30")
    func defaultMaxTurns() {
        #expect(AutoRunConfig.default.maxTurns == 30)
    }

    @Test("default config — maxBudgetUSD == 3.0")
    func defaultMaxBudget() {
        #expect(AutoRunConfig.default.maxBudgetUSD == 3.0)
    }

    @Test("default config — maxDurationSeconds == 1800")
    func defaultMaxDuration() {
        #expect(AutoRunConfig.default.maxDurationSeconds == 1800)
    }

    @Test("default config — stopOnDestructive == true")
    func defaultStopOnDestructive() {
        #expect(AutoRunConfig.default.stopOnDestructive == true)
    }

    @Test("default config — errorThreshold == 3")
    func defaultErrorThreshold() {
        #expect(AutoRunConfig.default.errorThreshold == 3)
    }

    @Test("default config — autoLoadHarnessRules == true")
    func defaultAutoLoadHarnessRules() {
        #expect(AutoRunConfig.default.autoLoadHarnessRules == true)
    }

    // MARK: - Hard cap 검증

    @Test("maxTurns 초과값은 absoluteMaxTurns(200)으로 clamp")
    func maxTurnsHardCap() {
        let config = AutoRunConfig(maxTurns: 999)
        #expect(config.maxTurns == AutoRunConfig.absoluteMaxTurns)
        #expect(config.maxTurns == 200)
    }

    @Test("maxDurationSeconds 초과값은 absoluteMaxDurationSeconds(4시간)으로 clamp")
    func maxDurationHardCap() {
        let config = AutoRunConfig(maxDurationSeconds: 99_999)
        #expect(config.maxDurationSeconds == AutoRunConfig.absoluteMaxDurationSeconds)
        #expect(config.maxDurationSeconds == 14_400)
    }

    @Test("maxTurns 정상 범위(30)는 clamp 없이 그대로")
    func maxTurnsNormalRange() {
        let config = AutoRunConfig(maxTurns: 30)
        #expect(config.maxTurns == 30)
    }

    @Test("maxTurns 경계값(200)은 허용됨")
    func maxTurnsBoundary() {
        let config = AutoRunConfig(maxTurns: 200)
        #expect(config.maxTurns == 200)
    }

    // MARK: - Codable round-trip

    @Test("AutoRunConfig Codable round-trip")
    func codableRoundTrip() throws {
        var config = AutoRunConfig()
        config.enabled = true
        config.maxTurns = 50
        config.maxBudgetUSD = 5.5
        config.stopKeywords = ["완료", "DONE"]
        config.notifyChannel = .telegram

        let encoded = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AutoRunConfig.self, from: encoded)

        #expect(decoded.enabled == true)
        #expect(decoded.maxTurns == 50)
        #expect(decoded.maxBudgetUSD == 5.5)
        #expect(decoded.stopKeywords == ["완료", "DONE"])
        #expect(decoded.notifyChannel == .telegram)
    }

    @Test("Codable decode 시 누락 필드는 default 적용")
    func codableMissingFieldsFallback() throws {
        let minimalJSON = #"{"enabled":true}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AutoRunConfig.self, from: minimalJSON)
        #expect(decoded.enabled == true)
        #expect(decoded.maxTurns == 30)
        #expect(decoded.stopOnDestructive == true)
        #expect(decoded.autoLoadHarnessRules == true)
    }

    @Test("Codable decode 시 hard cap 초과값도 clamp 적용")
    func codableHardCapOnDecode() throws {
        let json = #"{"maxTurns":999,"maxDurationSeconds":99999}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AutoRunConfig.self, from: json)
        #expect(decoded.maxTurns == 200)
        #expect(decoded.maxDurationSeconds == 14_400)
    }

    // MARK: - NotifyChannel

    @Test("NotifyChannel CaseIterable — 3가지 케이스 존재")
    func notifyChannelAllCases() {
        #expect(AutoRunConfig.NotifyChannel.allCases.count == 3)
    }

    @Test("NotifyChannel displayName — 비어있지 않음")
    func notifyChannelDisplayNames() {
        for channel in AutoRunConfig.NotifyChannel.allCases {
            #expect(!channel.displayName.isEmpty)
        }
    }

    // MARK: - Hashable

    @Test("AutoRunConfig Hashable — 동일 값이면 같은 hash")
    func hashable() {
        let a = AutoRunConfig.default
        let b = AutoRunConfig.default
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }
}
