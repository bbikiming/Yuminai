import Foundation

/// **ADR-122 Phase 1** — GitHub API 요청 재시도 정책 (Exponential backoff + jitter).
///
/// 공식: `delay = min(maxDelay, baseDelay * 2^attempt + jitter)`
/// jitter = random in [baseDelay/2, capped] (full jitter — AWS Architecture Blog 권고).
///
/// ## 재시도 가능 조건
/// - 5xx 서버 에러 → retry
/// - 네트워크 timeout → retry
/// - 401 / 403 rate-limit-외 / 422 → retry 안 함 (사용자 액션 필요)
/// - 429 rate limit → Retry-After 헤더 우선 적용
public struct GitHubRetryPolicy: Sendable, Codable, Hashable {
    /// 최대 시도 횟수 (첫 시도 포함).
    public var maxAttempts: Int
    /// 기본 delay (초).
    public var baseDelay: TimeInterval
    /// 최대 delay cap (초).
    public var maxDelay: TimeInterval
    /// jitter 적용 여부 (thundering herd 방지).
    public var useJitter: Bool

    public init(
        maxAttempts: Int = 3,
        baseDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 10.0,
        useJitter: Bool = true
    ) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.useJitter = useJitter
    }

    /// `attempt` (0-based) 시 대기 시간 계산.
    /// - Parameter attempt: 현재 시도 번호 (0이 첫 번째 재시도).
    /// - Parameter retryAfterSeconds: 서버가 Retry-After 헤더로 지정한 값 (우선 적용).
    public func delay(for attempt: Int, retryAfterSeconds: TimeInterval? = nil) -> TimeInterval {
        if let retryAfter = retryAfterSeconds {
            return min(maxDelay, max(baseDelay, retryAfter))
        }
        let exponential = baseDelay * pow(2.0, Double(attempt))
        let capped = min(maxDelay, exponential)
        guard useJitter else { return capped }
        let halfBase = baseDelay / 2.0
        let lower = min(halfBase, capped)
        return Double.random(in: lower...max(lower, capped))
    }

    /// 더 시도할지 여부 (maxAttempts 미도달이면 true).
    public func shouldRetry(attempt: Int) -> Bool {
        attempt < maxAttempts - 1
    }

    /// HTTP 상태 코드가 재시도 가능한지 판단.
    /// - Returns: true면 재시도, false면 즉시 실패 전파.
    public func isRetryable(statusCode: Int) -> Bool {
        switch statusCode {
        case 500...599:
            return true   // 5xx 서버 에러
        case 408:
            return true   // Request Timeout
        case 429:
            return true   // Rate limit (Retry-After 포함)
        default:
            return false  // 401, 403, 404, 422 등 — 사용자 액션 필요
        }
    }

    // MARK: - 프리셋

    /// 기본 정책 (3회, 1~10초 backoff).
    public static let `default` = GitHubRetryPolicy()

    /// 빠른 retry (2회, 0.1초 — 테스트/빠른 fail 용).
    public static let fast = GitHubRetryPolicy(
        maxAttempts: 2,
        baseDelay: 0.1,
        maxDelay: 0.5,
        useJitter: false
    )

    /// 강력한 retry (5회, 2~30초 backoff).
    public static let aggressive = GitHubRetryPolicy(
        maxAttempts: 5,
        baseDelay: 2.0,
        maxDelay: 30.0,
        useJitter: true
    )
}
