import Foundation
import Testing
@testable import YuminaiCore

/// **ADR-122 Phase 5** — GitHubRetryPolicy TDD.
@Suite("GitHubRetryPolicy (ADR-122)")
struct GitHubRetryPolicyTests {

    // MARK: - 기본값

    @Test("default 프리셋 — 3회, baseDelay 1s, maxDelay 10s, jitter true")
    func defaultPreset() {
        let p = GitHubRetryPolicy.default
        #expect(p.maxAttempts == 3)
        #expect(p.baseDelay == 1.0)
        #expect(p.maxDelay == 10.0)
        #expect(p.useJitter == true)
    }

    @Test("fast 프리셋 — 2회, 짧은 delay")
    func fastPreset() {
        let p = GitHubRetryPolicy.fast
        #expect(p.maxAttempts == 2)
        #expect(p.baseDelay < 1.0)
        #expect(p.useJitter == false)
    }

    @Test("aggressive 프리셋 — 5회, 긴 delay")
    func aggressivePreset() {
        let p = GitHubRetryPolicy.aggressive
        #expect(p.maxAttempts == 5)
        #expect(p.baseDelay >= 2.0)
        #expect(p.maxDelay >= 30.0)
    }

    // MARK: - delay 계산

    @Test("delay — jitter 없을 때 exponential backoff")
    func exponentialNoJitter() {
        let p = GitHubRetryPolicy(maxAttempts: 5, baseDelay: 1.0, maxDelay: 60.0, useJitter: false)
        #expect(p.delay(for: 0) == 1.0)
        #expect(p.delay(for: 1) == 2.0)
        #expect(p.delay(for: 2) == 4.0)
        #expect(p.delay(for: 3) == 8.0)
    }

    @Test("delay — maxDelay cap 적용")
    func maxDelayCap() {
        let p = GitHubRetryPolicy(maxAttempts: 10, baseDelay: 1.0, maxDelay: 5.0, useJitter: false)
        #expect(p.delay(for: 5) == 5.0)   // 1 * 32 = 32 → cap 5
        #expect(p.delay(for: 100) == 5.0)
    }

    @Test("delay — Retry-After 헤더 우선 적용")
    func retryAfterPriority() {
        let p = GitHubRetryPolicy.default
        #expect(p.delay(for: 0, retryAfterSeconds: 7.0) == 7.0)
        #expect(p.delay(for: 5, retryAfterSeconds: 7.0) == 7.0)
        // maxDelay cap 적용
        #expect(p.delay(for: 0, retryAfterSeconds: 9999.0) == 10.0)
    }

    @Test("delay — jitter 적용 시 [baseDelay/2, capped] 범위 내")
    func jitterRange() {
        let p = GitHubRetryPolicy(maxAttempts: 5, baseDelay: 1.0, maxDelay: 60.0, useJitter: true)
        for attempt in 0..<5 {
            let d = p.delay(for: attempt)
            let expected = min(60.0, 1.0 * pow(2.0, Double(attempt)))
            #expect(d >= 0.5)                   // baseDelay / 2
            #expect(d <= expected + 0.001)      // floating point 허용
        }
    }

    // MARK: - shouldRetry

    @Test("shouldRetry — 마지막 attempt 전까지 true")
    func shouldRetryBoundary() {
        let p = GitHubRetryPolicy(maxAttempts: 3, baseDelay: 1.0, maxDelay: 10.0, useJitter: false)
        #expect(p.shouldRetry(attempt: 0) == true)
        #expect(p.shouldRetry(attempt: 1) == true)
        #expect(p.shouldRetry(attempt: 2) == false)  // maxAttempts-1
    }

    @Test("shouldRetry — maxAttempts 1이면 attempt 0도 false")
    func shouldRetryOnce() {
        let p = GitHubRetryPolicy(maxAttempts: 1, baseDelay: 1.0, maxDelay: 10.0, useJitter: false)
        #expect(p.shouldRetry(attempt: 0) == false)
    }

    // MARK: - isRetryable

    @Test("isRetryable — 5xx는 재시도 가능")
    func retryable5xx() {
        let p = GitHubRetryPolicy.default
        #expect(p.isRetryable(statusCode: 500) == true)
        #expect(p.isRetryable(statusCode: 503) == true)
        #expect(p.isRetryable(statusCode: 599) == true)
    }

    @Test("isRetryable — 429 rate limit은 재시도 가능")
    func retryable429() {
        let p = GitHubRetryPolicy.default
        #expect(p.isRetryable(statusCode: 429) == true)
    }

    @Test("isRetryable — 401/403/404/422는 재시도 불가")
    func notRetryable4xx() {
        let p = GitHubRetryPolicy.default
        #expect(p.isRetryable(statusCode: 401) == false)
        #expect(p.isRetryable(statusCode: 403) == false)
        #expect(p.isRetryable(statusCode: 404) == false)
        #expect(p.isRetryable(statusCode: 422) == false)
    }
}
