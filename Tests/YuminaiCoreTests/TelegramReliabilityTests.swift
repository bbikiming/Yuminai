import Foundation
import Testing
@testable import YuminaiCore

@Suite("TelegramRetryPolicy (ADR-085 Phase 1)")
struct TelegramRetryPolicyTests {

    @Test("default — 5 attempts / base 1s / max 60s")
    func defaults() {
        let p = TelegramRetryPolicy.default
        #expect(p.maxAttempts == 5)
        #expect(p.baseDelaySeconds == 1.0)
        #expect(p.maxDelaySeconds == 60.0)
        #expect(p.useJitter == true)
    }

    @Test("delay — exponential without jitter")
    func exponentialNoJitter() {
        let p = TelegramRetryPolicy(maxAttempts: 5, baseDelaySeconds: 1, maxDelaySeconds: 60, useJitter: false)
        #expect(p.delay(forAttempt: 0) == 1.0)
        #expect(p.delay(forAttempt: 1) == 2.0)
        #expect(p.delay(forAttempt: 2) == 4.0)
        #expect(p.delay(forAttempt: 3) == 8.0)
    }

    @Test("delay — max cap 적용")
    func maxCap() {
        let p = TelegramRetryPolicy(maxAttempts: 10, baseDelaySeconds: 1, maxDelaySeconds: 5, useJitter: false)
        #expect(p.delay(forAttempt: 5) == 5.0)  // 1*32=32 → cap 5
        #expect(p.delay(forAttempt: 100) == 5.0)
    }

    @Test("delay — Retry-After header 우선")
    func retryAfterPriority() {
        let p = TelegramRetryPolicy.default
        // Retry-After 10초 → exponential(어떤 attempt든) 무시하고 10
        #expect(p.delay(forAttempt: 0, retryAfterSeconds: 10) == 10.0)
        #expect(p.delay(forAttempt: 5, retryAfterSeconds: 10) == 10.0)
        // Retry-After가 너무 크면 maxDelay로 cap
        #expect(p.delay(forAttempt: 0, retryAfterSeconds: 9999) == 60.0)
    }

    @Test("delay — jitter 적용 시 [base/2, capped] 범위 내")
    func jitterRange() {
        let p = TelegramRetryPolicy(maxAttempts: 5, baseDelaySeconds: 1, maxDelaySeconds: 60, useJitter: true)
        for attempt in 0..<5 {
            let d = p.delay(forAttempt: attempt)
            let expectedMax = min(60.0, 1.0 * pow(2.0, Double(attempt)))
            #expect(d >= 0.5)  // base/2
            #expect(d <= expectedMax + 0.001)  // floating point tolerance
        }
    }

    @Test("shouldRetry — boundary")
    func shouldRetry() {
        let p = TelegramRetryPolicy(maxAttempts: 3, baseDelaySeconds: 1, maxDelaySeconds: 10, useJitter: false)
        #expect(p.shouldRetry(attempt: 0) == true)
        #expect(p.shouldRetry(attempt: 1) == true)
        #expect(p.shouldRetry(attempt: 2) == false)  // 마지막 attempt
    }
}

@Suite("TelegramRateLimiter (ADR-085 Phase 3)")
struct TelegramRateLimiterTests {

    @Test("초기 burst 즉시 허용 (token bucket)")
    func initialBurst() async {
        let limiter = TelegramRateLimiter(globalCapacity: 30, globalRefillPerSecond: 30.0)
        // 첫 acquire는 0초 대기
        let wait = await limiter.acquire(chatId: 100)
        #expect(wait < 0.1)  // 거의 즉시
    }

    @Test("per-chat 초과 시 대기")
    func perChatLimit() async {
        let limiter = TelegramRateLimiter(globalCapacity: 30, globalRefillPerSecond: 30.0)
        let chat: Int64 = 100
        // 1번째: 즉시
        let wait1 = await limiter.acquire(chatId: chat)
        #expect(wait1 < 0.1)
        // 2번째: per-chat 1/sec → 약 1초 대기 (정확히는 가용 token 부족분)
        let start = Date()
        await limiter.acquire(chatId: chat)
        let elapsed = Date().timeIntervalSince(start)
        // ~1초 (refill 시간)
        #expect(elapsed > 0.5)
        #expect(elapsed < 2.0)  // sanity cap
    }
}

@Suite("TelegramHealthMonitor (ADR-085 Phase 2)")
struct TelegramHealthMonitorTests {

    @Test("초기 — idle state")
    func initialIdle() async {
        let monitor = TelegramHealthMonitor()
        let snap = await monitor.current()
        #expect(snap.state == .idle)
        #expect(snap.lastSuccessAt == nil)
        #expect(snap.consecutiveFailures == 0)
    }

    @Test("recordSuccess — healthy state + counter")
    func successUpdates() async {
        let monitor = TelegramHealthMonitor()
        await monitor.recordSuccess(updatesProcessed: 3)
        let snap = await monitor.current()
        #expect(snap.state == .healthy)
        #expect(snap.totalUpdatesProcessed == 3)
        #expect(snap.consecutiveFailures == 0)
        #expect(snap.lastSuccessAt != nil)
    }

    @Test("recordTransientFailure — degraded + counter 증가")
    func transientFailure() async {
        let monitor = TelegramHealthMonitor()
        await monitor.recordTransientFailure("network timeout")
        await monitor.recordTransientFailure("network timeout")
        let snap = await monitor.current()
        #expect(snap.state == .degraded)
        #expect(snap.consecutiveFailures == 2)
        #expect(snap.lastErrorMessage == "network timeout")
    }

    @Test("성공 후 transient — counter reset")
    func successResetsCounter() async {
        let monitor = TelegramHealthMonitor()
        await monitor.recordTransientFailure("err")
        await monitor.recordTransientFailure("err")
        await monitor.recordSuccess()
        let snap = await monitor.current()
        #expect(snap.state == .healthy)
        #expect(snap.consecutiveFailures == 0)
    }

    @Test("recordPermanentFailure — failed state")
    func permanentFailure() async {
        let monitor = TelegramHealthMonitor()
        await monitor.recordPermanentFailure("token invalid")
        let snap = await monitor.current()
        #expect(snap.state == .failed)
        #expect(snap.lastErrorMessage == "token invalid")
        #expect(snap.isHealthy == false)
    }

    @Test("snapshots stream — 현재 값 즉시 emit")
    func streamEmitsCurrent() async {
        let monitor = TelegramHealthMonitor()
        await monitor.recordSuccess()
        var iterator = await monitor.snapshots().makeAsyncIterator()
        let first = await iterator.next()
        #expect(first?.state == .healthy)
    }
}

@Suite("TelegramIdempotencyTracker (ADR-085 Phase 1)")
struct TelegramIdempotencyTrackerTests {

    @Test("update_id — 첫 acquire true, 두 번째 false")
    func updateIdDedup() async {
        let tracker = TelegramIdempotencyTracker()
        #expect(await tracker.acquire(updateId: 100) == true)
        #expect(await tracker.acquire(updateId: 100) == false)
        #expect(await tracker.acquire(updateId: 101) == true)
    }

    @Test("messageHash — 1분 window 내 dedup")
    func messageHashDedup() async {
        let tracker = TelegramIdempotencyTracker()
        let hash = "chat-1|hello|1234567"
        #expect(await tracker.acquireMessageHash(hash) == true)
        #expect(await tracker.acquireMessageHash(hash) == false)  // 같은 hash
    }

    @Test("messageHash — window 만료 후 다시 허용")
    func messageHashWindowExpiry() async {
        let tracker = TelegramIdempotencyTracker()
        let hash = "chat-1|hello|1234567"
        // window 0.1초로 short
        #expect(await tracker.acquireMessageHash(hash, window: 0.1) == true)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(await tracker.acquireMessageHash(hash, window: 0.1) == true)  // 만료 → 다시 허용
    }

    @Test("clear — 모든 dedup 초기화")
    func clear() async {
        let tracker = TelegramIdempotencyTracker()
        _ = await tracker.acquire(updateId: 1)
        await tracker.clear()
        #expect(await tracker.acquire(updateId: 1) == true)  // 다시 허용
    }
}

@Suite("TelegramErrorLog (ADR-085 Phase 4)")
struct TelegramErrorLogTests {

    @Test("recent — 최신 N개 (역순)")
    func recentReverse() async {
        let log = TelegramErrorLog(capacity: 10)
        for i in 0..<5 {
            let entry = TelegramErrorEntry(
                category: .network,
                message: "err \(i)",
                userFacingMessage: "user err \(i)"
            )
            await log.record(entry)
        }
        let recent = await log.recent(limit: 3)
        #expect(recent.count == 3)
        #expect(recent[0].message == "err 4")  // 최신
        #expect(recent[2].message == "err 2")
    }

    @Test("ring buffer — capacity 초과 시 oldest 삭제")
    func ringBuffer() async {
        let log = TelegramErrorLog(capacity: 3)
        for i in 0..<5 {
            let entry = TelegramErrorEntry(
                category: .network, message: "err \(i)", userFacingMessage: "")
            await log.record(entry)
        }
        let count = await log.count()
        #expect(count == 3)
        let recent = await log.recent(limit: 10)
        #expect(recent[0].message == "err 4")
        #expect(recent[2].message == "err 2")  // 가장 오래된 (capacity 안)
    }

    @Test("statsByCategory")
    func categoryStats() async {
        let log = TelegramErrorLog()
        await log.record(TelegramErrorEntry(category: .auth, message: "", userFacingMessage: ""))
        await log.record(TelegramErrorEntry(category: .network, message: "", userFacingMessage: ""))
        await log.record(TelegramErrorEntry(category: .network, message: "", userFacingMessage: ""))
        let stats = await log.statsByCategory()
        #expect(stats[.auth] == 1)
        #expect(stats[.network] == 2)
        #expect(stats[.rateLimit] == nil)
    }
}

@Suite("TelegramErrorClassifier (ADR-085 Phase 4)")
struct TelegramErrorClassifierTests {

    @Test("auth errors — 401/403/404 한국어 안내")
    func authErrors() {
        let err401 = NSError(domain: "TelegramBot", code: 401, userInfo: nil)
        let entry401 = TelegramErrorClassifier.classify(err401)
        #expect(entry401.category == .auth)
        #expect(entry401.userFacingMessage.contains("토큰"))

        let err403 = NSError(domain: "TelegramBot", code: 403, userInfo: nil)
        let entry403 = TelegramErrorClassifier.classify(err403)
        #expect(entry403.category == .auth)
        #expect(entry403.userFacingMessage.contains("차단"))
    }

    @Test("rate limit — 429")
    func rateLimit() {
        let err = NSError(domain: "TelegramBot", code: 429, userInfo: nil)
        let entry = TelegramErrorClassifier.classify(err)
        #expect(entry.category == .rateLimit)
    }

    @Test("server — 5xx")
    func serverError() {
        let err = NSError(domain: "TelegramBot", code: 503, userInfo: nil)
        let entry = TelegramErrorClassifier.classify(err)
        #expect(entry.category == .server)
    }

    @Test("network — NSURLErrorDomain")
    func networkError() {
        let err = NSError(domain: NSURLErrorDomain, code: -1009, userInfo: nil)
        let entry = TelegramErrorClassifier.classify(err)
        #expect(entry.category == .network)
        #expect(entry.userFacingMessage.contains("네트워크"))
    }

    @Test("Retry-After header 추출")
    func retryAfterExtraction() {
        let headers: [AnyHashable: Any] = ["Retry-After": "30"]
        #expect(TelegramErrorClassifier.retryAfterSeconds(from: headers) == 30.0)

        let lowerHeaders: [AnyHashable: Any] = ["retry-after": "5"]
        #expect(TelegramErrorClassifier.retryAfterSeconds(from: lowerHeaders) == 5.0)

        let noHeader: [AnyHashable: Any] = ["X-Other": "value"]
        #expect(TelegramErrorClassifier.retryAfterSeconds(from: noHeader) == nil)
    }
}

@Suite("TelegramConnectionState (ADR-085 Phase 2)")
struct TelegramConnectionStateTests {

    @Test("displayName + iconName 모든 case")
    func displayAllCases() {
        for state: TelegramConnectionState in [.idle, .healthy, .degraded, .failed] {
            #expect(!state.displayName.isEmpty)
            #expect(!state.iconName.isEmpty)
        }
    }

    @Test("Codable round trip")
    func codable() throws {
        let state = TelegramConnectionState.degraded
        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(TelegramConnectionState.self, from: encoded)
        #expect(decoded == .degraded)
    }
}
