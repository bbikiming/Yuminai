import Foundation
import Testing
@testable import YuminaiCore

/// **ADR-125 P0-2** — `RelativeTime.format(_:now:)` 단위 테스트.
///
/// 방금 전 / N분 전 / N시간 전 / N일 전 / N주 전 / N개월 전 / N년 전 각 구간과
/// 버그가 수정된 1주~1개월 구간("N주 전" 반환)을 검증한다.
@Suite("RelativeTime (ADR-125)")
struct RelativeTimeTests {

    private let anchor = Date(timeIntervalSinceReferenceDate: 1_000_000_000)

    // MARK: - 방금 전 (< 60초)

    @Test("0초 → 방금 전")
    func zeroSeconds() {
        let result = RelativeTime.format(anchor, now: anchor)
        #expect(result == "방금 전")
    }

    @Test("59초 → 방금 전")
    func fiftyNineSeconds() {
        let now = anchor.addingTimeInterval(59)
        let result = RelativeTime.format(anchor, now: now)
        #expect(result == "방금 전")
    }

    // MARK: - N분 전 (60초 ~ 3600초)

    @Test("1분 → 1분 전")
    func oneMinute() {
        let now = anchor.addingTimeInterval(60)
        let result = RelativeTime.format(anchor, now: now)
        #expect(result == "1분 전")
    }

    @Test("45분 → 45분 전")
    func fortyFiveMinutes() {
        let now = anchor.addingTimeInterval(45 * 60)
        let result = RelativeTime.format(anchor, now: now)
        #expect(result == "45분 전")
    }

    // MARK: - N시간 전 (3600초 ~ 86400초)

    @Test("1시간 → 1시간 전")
    func oneHour() {
        let now = anchor.addingTimeInterval(3_600)
        let result = RelativeTime.format(anchor, now: now)
        #expect(result == "1시간 전")
    }

    @Test("23시간 → 23시간 전")
    func twentyThreeHours() {
        let now = anchor.addingTimeInterval(23 * 3_600)
        let result = RelativeTime.format(anchor, now: now)
        #expect(result == "23시간 전")
    }

    // MARK: - N일 전 (1일 ~ 7일 미만)

    @Test("1일 → 1일 전")
    func oneDay() {
        let now = anchor.addingTimeInterval(86_400)
        let result = RelativeTime.format(anchor, now: now)
        #expect(result == "1일 전")
    }

    @Test("6일 → 6일 전")
    func sixDays() {
        let now = anchor.addingTimeInterval(6 * 86_400)
        let result = RelativeTime.format(anchor, now: now)
        #expect(result == "6일 전")
    }

    // MARK: - N주 전 (7일 ~ 30일 미만) ← P0-2 버그 수정 구간

    @Test("정확히 7일 → 1주 전 (P0-2 dead branch 수정 검증)")
    func exactlyOneWeek() {
        let now = anchor.addingTimeInterval(7 * 86_400)
        let result = RelativeTime.format(anchor, now: now)
        #expect(result == "1주 전")
    }

    @Test("14일 → 2주 전")
    func twoWeeks() {
        let now = anchor.addingTimeInterval(14 * 86_400)
        let result = RelativeTime.format(anchor, now: now)
        #expect(result == "2주 전")
    }

    @Test("29일 → 4주 전 (구버그라면 '29일 전'이 반환됐을 위치)")
    func twentyNineDays() {
        let now = anchor.addingTimeInterval(29 * 86_400)
        let result = RelativeTime.format(anchor, now: now)
        // 버그 재현 방지: "29일 전"이 아니라 "4주 전"이어야 한다
        #expect(result == "4주 전")
        #expect(result != "29일 전")
    }

    // MARK: - N개월 전 (30일 ~ 365일 미만)

    @Test("30일 → 1개월 전")
    func oneMonth() {
        let now = anchor.addingTimeInterval(30 * 86_400)
        let result = RelativeTime.format(anchor, now: now)
        #expect(result == "1개월 전")
    }

    @Test("180일 → 6개월 전")
    func sixMonths() {
        let now = anchor.addingTimeInterval(180 * 86_400)
        let result = RelativeTime.format(anchor, now: now)
        #expect(result == "6개월 전")
    }

    // MARK: - N년 전 (≥ 365일)

    @Test("365일 → 1년 전")
    func oneYear() {
        let now = anchor.addingTimeInterval(365 * 86_400)
        let result = RelativeTime.format(anchor, now: now)
        #expect(result == "1년 전")
    }

    @Test("730일 → 2년 전")
    func twoYears() {
        let now = anchor.addingTimeInterval(730 * 86_400)
        let result = RelativeTime.format(anchor, now: now)
        #expect(result == "2년 전")
    }
}
