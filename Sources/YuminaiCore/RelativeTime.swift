import Foundation

/// **ADR-125** — 상대 시간 포맷 헬퍼.
///
/// 두 `Date` 간격을 사람이 읽기 쉬운 한국어 상대 시간 문자열로 변환한다.
/// 기존 `GitHubSearchSheet`와 `LibrarySheet`에 중복으로 존재하던
/// `relativeDate(_:)` 구현을 통합하고, 1주~1개월 구간 dead branch 버그를 수정한다.
///
/// ### 수정된 버그 (P0-2)
/// 이전 구현:
/// ```swift
/// if diff < 86400 * 7  { return "\(Int(diff / 86400))일 전" }
/// if diff < 86400 * 30 { return "\(Int(diff / 86400))일 전" }  // 동일 표현식 — 1주~1개월이 "29일 전"
/// ```
/// 두 번째 분기가 첫 번째와 동일한 표현식을 사용해 1주~1개월 구간이 "N주 전" 대신 "N일 전"으로 표시됐다.
public enum RelativeTime {

    /// `date`로부터 `now`까지의 경과 시간을 한국어 상대 시간 문자열로 반환한다.
    ///
    /// - Parameters:
    ///   - date: 기준 날짜 (과거).
    ///   - now: 현재 시각 (기본값 `Date.now`, 테스트에서 주입 가능).
    /// - Returns: "방금 전", "N분 전", "N시간 전", "N일 전", "N주 전", "N개월 전", "N년 전" 중 하나.
    public static func format(_ date: Date, now: Date = .now) -> String {
        let diff = now.timeIntervalSince(date)
        if diff < 60          { return "방금 전" }
        if diff < 3_600       { return "\(Int(diff / 60))분 전" }
        if diff < 86_400      { return "\(Int(diff / 3_600))시간 전" }
        if diff < 86_400 * 7  { return "\(Int(diff / 86_400))일 전" }
        if diff < 86_400 * 30 { return "\(Int(diff / (86_400 * 7)))주 전" }   // P0-2 수정
        if diff < 86_400 * 365 { return "\(Int(diff / (86_400 * 30)))개월 전" }
        return "\(Int(diff / (86_400 * 365)))년 전"
    }
}
