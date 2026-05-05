import Foundation
import Testing
@testable import YuminaiCore

/// **ADR-122 Phase 5** — GitHubRateLimit TDD (헤더 파싱 + 상태 계산).
@Suite("GitHubRateLimit (ADR-122)")
struct GitHubRateLimitTests {

    // MARK: - 기본 생성

    @Test("isLimited — remaining 0이면 true")
    func isLimitedWhenRemaining0() {
        let rl = GitHubSearchClient.GitHubRateLimit(
            limit: 60,
            remaining: 0,
            resetAt: Date().addingTimeInterval(3600)
        )
        #expect(rl.isLimited == true)
    }

    @Test("isLimited — remaining > 0이면 false")
    func isNotLimitedWhenRemainingPositive() {
        let rl = GitHubSearchClient.GitHubRateLimit(
            limit: 60,
            remaining: 30,
            resetAt: Date().addingTimeInterval(3600)
        )
        #expect(rl.isLimited == false)
    }

    @Test("resetIn — 미래 시각이면 양수")
    func resetInPositive() {
        let rl = GitHubSearchClient.GitHubRateLimit(
            limit: 60,
            remaining: 10,
            resetAt: Date().addingTimeInterval(1800)  // 30분 후
        )
        #expect(rl.resetIn > 0)
        #expect(rl.resetIn < 1810)  // 여유 허용
    }

    @Test("resetIn — 과거 시각이면 음수 또는 0")
    func resetInNegativeOrZero() {
        let rl = GitHubSearchClient.GitHubRateLimit(
            limit: 60,
            remaining: 0,
            resetAt: Date().addingTimeInterval(-60)  // 1분 전
        )
        #expect(rl.resetIn < 0)
    }

    // MARK: - displayText

    @Test("displayText — 포맷 포함")
    func displayTextFormat() {
        let rl = GitHubSearchClient.GitHubRateLimit(
            limit: 60,
            remaining: 12,
            resetAt: Date().addingTimeInterval(1680)
        )
        #expect(rl.displayText.contains("60"))
        #expect(rl.displayText.contains("12"))
    }

    @Test("resetDisplayText — 남은 분 표시")
    func resetDisplayTextMinutes() {
        let rl = GitHubSearchClient.GitHubRateLimit(
            limit: 60,
            remaining: 0,
            resetAt: Date().addingTimeInterval(1680)  // 28분 후
        )
        #expect(rl.resetDisplayText.contains("분") || rl.resetDisplayText.contains("리셋"))
    }
}
