import Foundation

/// **ADR-085** — 텔레그램 원격 통신 안정성 인프라 (Codex 협업 검수 반영).
///
/// ## Codex perspective 검수 → Claude 반영
/// 1. **Fixed 5초 sleep → Exponential backoff + jitter** (thundering herd 방지)
/// 2. **429 응답 시 Retry-After header 존중** (Telegram API 권고)
/// 3. **per-chat rate limit** (Telegram: 1 msg/sec/chat, 30 msg/sec/bot)
/// 4. **Connection health observable** (AsyncStream — UI에서 실시간 표시)
/// 5. **Structured error log** (ring buffer, 디버깅 + 사용자 알림 양쪽 활용)
///
/// ## 레퍼런스
/// - Telegram Bot API: https://core.telegram.org/bots/api#making-requests-when-getting-updates
/// - AWS SDK Retry pattern: https://docs.aws.amazon.com/sdkref/latest/guide/feature-retry-behavior.html
/// - Anthropic best practices (idempotency keys)

// MARK: - Phase 1: Retry policy

/// **ADR-085 Phase 1** — Exponential backoff + jitter retry policy.
///
/// 공식: `delay = min(maxDelay, baseDelay * 2^attempt + jitter)`
/// jitter = 0~50% of base (full jitter 알고리즘 — AWS Architecture Blog 권고).
public struct TelegramRetryPolicy: Sendable, Hashable {
    public let maxAttempts: Int
    public let baseDelaySeconds: Double
    public let maxDelaySeconds: Double
    /// `true`면 jitter 적용 (production 권장 — thundering herd 방지).
    public let useJitter: Bool

    public init(
        maxAttempts: Int = 5,
        baseDelaySeconds: Double = 1.0,
        maxDelaySeconds: Double = 60.0,
        useJitter: Bool = true
    ) {
        self.maxAttempts = maxAttempts
        self.baseDelaySeconds = baseDelaySeconds
        self.maxDelaySeconds = maxDelaySeconds
        self.useJitter = useJitter
    }

    /// `attempt` (0-based) 시 대기 시간 계산.
    /// 서버가 Retry-After header를 줬다면 그 값 우선 (clamped).
    public func delay(forAttempt attempt: Int, retryAfterSeconds: Double? = nil) -> Double {
        if let retryAfter = retryAfterSeconds {
            // Telegram이 명시한 retry-after는 무조건 존중 (clamp만 적용)
            return min(maxDelaySeconds, max(baseDelaySeconds, retryAfter))
        }
        let exponential = baseDelaySeconds * pow(2.0, Double(attempt))
        let capped = min(maxDelaySeconds, exponential)
        guard useJitter else { return capped }
        // Full jitter — random in [base/2, capped]
        let halfBase = baseDelaySeconds / 2
        let lower = min(halfBase, capped)
        return Double.random(in: lower...max(lower, capped))
    }

    /// 더 시도할지 (max 도달 안 했으면 true).
    public func shouldRetry(attempt: Int) -> Bool {
        attempt < maxAttempts - 1  // attempt 0-based
    }

    public static let `default` = TelegramRetryPolicy()
    /// 빠른 fail용 (test).
    public static let fast = TelegramRetryPolicy(
        maxAttempts: 2, baseDelaySeconds: 0.1, maxDelaySeconds: 0.5, useJitter: false
    )
}

// MARK: - Phase 2: Connection health

/// **ADR-085 Phase 2** — 텔레그램 연결 상태 (UI에서 실시간 표시).
public enum TelegramConnectionState: String, Sendable, Hashable, Codable {
    /// Polling 시작 전 / stopped.
    case idle
    /// Polling 정상 동작.
    case healthy
    /// 일시 오류 (재시도 중).
    case degraded
    /// 영구 실패 (auth invalid 등 — polling 중단).
    case failed

    public var displayName: String {
        switch self {
        case .idle: return "대기"
        case .healthy: return "정상"
        case .degraded: return "재시도 중"
        case .failed: return "실패"
        }
    }

    public var iconName: String {
        switch self {
        case .idle: return "circle"
        case .healthy: return "checkmark.circle.fill"
        case .degraded: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }
}

/// **ADR-085 Phase 2** — Health snapshot.
public struct TelegramHealthSnapshot: Sendable, Hashable {
    public let state: TelegramConnectionState
    public let lastSuccessAt: Date?
    public let lastErrorMessage: String?
    public let consecutiveFailures: Int
    public let totalUpdatesProcessed: Int

    public init(
        state: TelegramConnectionState = .idle,
        lastSuccessAt: Date? = nil,
        lastErrorMessage: String? = nil,
        consecutiveFailures: Int = 0,
        totalUpdatesProcessed: Int = 0
    ) {
        self.state = state
        self.lastSuccessAt = lastSuccessAt
        self.lastErrorMessage = lastErrorMessage
        self.consecutiveFailures = consecutiveFailures
        self.totalUpdatesProcessed = totalUpdatesProcessed
    }

    public var isHealthy: Bool {
        state == .healthy
    }
}

/// **ADR-085 Phase 2** — Health monitor (mutable state — actor).
public actor TelegramHealthMonitor {
    private var snapshot: TelegramHealthSnapshot
    private var continuations: [AsyncStream<TelegramHealthSnapshot>.Continuation] = []

    public init() {
        self.snapshot = TelegramHealthSnapshot()
    }

    public func current() -> TelegramHealthSnapshot {
        snapshot
    }

    /// 변경 이벤트 stream (UI 실시간 구독용).
    public func snapshots() -> AsyncStream<TelegramHealthSnapshot> {
        AsyncStream { continuation in
            continuations.append(continuation)
            // 현재 값 즉시 emit
            continuation.yield(snapshot)
        }
    }

    /// 성공 기록.
    public func recordSuccess(updatesProcessed: Int = 1) {
        snapshot = TelegramHealthSnapshot(
            state: .healthy,
            lastSuccessAt: Date(),
            lastErrorMessage: nil,
            consecutiveFailures: 0,
            totalUpdatesProcessed: snapshot.totalUpdatesProcessed + updatesProcessed
        )
        broadcast()
    }

    /// 일시 오류 기록 (재시도 예정).
    public func recordTransientFailure(_ message: String) {
        snapshot = TelegramHealthSnapshot(
            state: .degraded,
            lastSuccessAt: snapshot.lastSuccessAt,
            lastErrorMessage: message,
            consecutiveFailures: snapshot.consecutiveFailures + 1,
            totalUpdatesProcessed: snapshot.totalUpdatesProcessed
        )
        broadcast()
    }

    /// 영구 실패 기록 (polling 중단).
    public func recordPermanentFailure(_ message: String) {
        snapshot = TelegramHealthSnapshot(
            state: .failed,
            lastSuccessAt: snapshot.lastSuccessAt,
            lastErrorMessage: message,
            consecutiveFailures: snapshot.consecutiveFailures + 1,
            totalUpdatesProcessed: snapshot.totalUpdatesProcessed
        )
        broadcast()
    }

    public func recordIdle() {
        snapshot = TelegramHealthSnapshot()
        broadcast()
    }

    private func broadcast() {
        for continuation in continuations {
            continuation.yield(snapshot)
        }
    }
}

// MARK: - Phase 3: Rate limiter

/// **ADR-085 Phase 3** — 메시지 송신 rate limiter (per-chat token bucket).
///
/// Telegram 한도:
/// - global: 30 msg/sec/bot
/// - per-chat: 1 msg/sec/chat (groups: ~20 msg/min)
///
/// **Codex review**: "단순 Set+Date보다 token bucket이 burst 허용 + steady-state 안정적".
public actor TelegramRateLimiter {
    /// 전역 bot quota — 30 msg/sec.
    private let globalCapacity: Int
    private let globalRefillPerSecond: Double
    /// per-chat bucket: chatId → (lastTokens, lastRefillTime).
    private var perChatBuckets: [Int64: (tokens: Double, lastRefill: Date)] = [:]
    /// per-chat capacity — 1 msg/sec/chat.
    private let perChatCapacity: Double = 1.0
    private let perChatRefillPerSecond: Double = 1.0

    /// 전역 bucket.
    private var globalTokens: Double
    private var globalLastRefill: Date

    public init(globalCapacity: Int = 30, globalRefillPerSecond: Double = 30.0) {
        self.globalCapacity = globalCapacity
        self.globalRefillPerSecond = globalRefillPerSecond
        self.globalTokens = Double(globalCapacity)
        self.globalLastRefill = Date()
    }

    /// 메시지 송신 전 호출 — quota 확보될 때까지 대기.
    /// - Returns: 대기한 시간 (초). 0이면 즉시 송신 가능.
    @discardableResult
    public func acquire(chatId: Int64) async -> Double {
        var totalWait: Double = 0
        while true {
            let now = Date()
            refillGlobal(now: now)
            refillChat(chatId: chatId, now: now)

            let chatBucket = perChatBuckets[chatId]!
            if globalTokens >= 1.0 && chatBucket.tokens >= 1.0 {
                globalTokens -= 1.0
                perChatBuckets[chatId] = (tokens: chatBucket.tokens - 1.0, lastRefill: chatBucket.lastRefill)
                return totalWait
            }
            // 둘 중 더 작은 quota 기준 wait
            let globalWait = max(0, (1.0 - globalTokens) / globalRefillPerSecond)
            let chatWait = max(0, (1.0 - chatBucket.tokens) / perChatRefillPerSecond)
            let wait = max(globalWait, chatWait)
            totalWait += wait
            // 안전 cap (cancellation 가능)
            try? await Task.sleep(for: .milliseconds(Int(wait * 1000) + 10))
        }
    }

    private func refillGlobal(now: Date) {
        let elapsed = now.timeIntervalSince(globalLastRefill)
        globalTokens = min(Double(globalCapacity), globalTokens + elapsed * globalRefillPerSecond)
        globalLastRefill = now
    }

    private func refillChat(chatId: Int64, now: Date) {
        let bucket = perChatBuckets[chatId] ?? (tokens: perChatCapacity, lastRefill: now)
        let elapsed = now.timeIntervalSince(bucket.lastRefill)
        let newTokens = min(perChatCapacity, bucket.tokens + elapsed * perChatRefillPerSecond)
        perChatBuckets[chatId] = (tokens: newTokens, lastRefill: now)
    }
}

// MARK: - Phase 4: Error log (ring buffer)

/// **ADR-085 Phase 4** — Structured error log (디버깅 + 사용자 안내).
public struct TelegramErrorEntry: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let category: Category
    public let message: String
    /// 사용자 친화적 한국어 안내 (UI 표시용).
    public let userFacingMessage: String

    public enum Category: String, Sendable, Hashable {
        case auth          // 401/403/404
        case rateLimit     // 429
        case network       // timeout / DNS / etc
        case server        // 5xx
        case parsing       // JSON decode 실패
        case other
    }

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        category: Category,
        message: String,
        userFacingMessage: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.message = message
        self.userFacingMessage = userFacingMessage
    }
}

/// **ADR-085 Phase 4** — Ring buffer error log (last N).
public actor TelegramErrorLog {
    private let capacity: Int
    private var entries: [TelegramErrorEntry] = []

    public init(capacity: Int = 50) {
        self.capacity = capacity
    }

    public func record(_ entry: TelegramErrorEntry) {
        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }

    /// 최신 N개 (최근 순).
    public func recent(limit: Int = 20) -> [TelegramErrorEntry] {
        Array(entries.suffix(limit).reversed())
    }

    public func count() -> Int {
        entries.count
    }

    public func clear() {
        entries.removeAll()
    }

    /// 카테고리별 통계.
    public func statsByCategory() -> [TelegramErrorEntry.Category: Int] {
        var stats: [TelegramErrorEntry.Category: Int] = [:]
        for entry in entries {
            stats[entry.category, default: 0] += 1
        }
        return stats
    }
}

// MARK: - Phase 1: Idempotency

/// **ADR-085 Phase 1** — 중복 외부 turn 방지 (사용자 같은 메시지 두 번 → 1번 처리).
///
/// Telegram update_id는 고유하지만 race condition 시 중복 처리 가능.
/// 추가로 `messageHash` (chat + text + timestamp 분 단위) 기반 dedup.
public actor TelegramIdempotencyTracker {
    /// 처리한 update_id set (memory ring buffer).
    private var seenUpdateIds: Set<Int64> = []
    private let capacity: Int

    /// `messageHash` 기반 dedup (1분 window).
    private var seenMessageHashes: [String: Date] = [:]

    public init(capacity: Int = 1000) {
        self.capacity = capacity
    }

    /// 새 update인지 확인 + 처리됨 표시.
    /// - Returns: `true`면 새 (처리해야 함), `false`면 이미 처리됨 (skip).
    public func acquire(updateId: Int64) -> Bool {
        if seenUpdateIds.contains(updateId) { return false }
        seenUpdateIds.insert(updateId)
        // 메모리 cap
        if seenUpdateIds.count > capacity {
            // 임의로 절반 제거 (가장 오래된 추적 어려우므로)
            let toRemove = seenUpdateIds.prefix(capacity / 2)
            for id in toRemove { seenUpdateIds.remove(id) }
        }
        return true
    }

    /// 메시지 해시 dedup (1분 window).
    /// Telegram이 같은 메시지를 다시 줄 가능성 (network glitch) 방지.
    public func acquireMessageHash(_ hash: String, window: TimeInterval = 60) -> Bool {
        let now = Date()
        // 만료된 hash 정리
        seenMessageHashes = seenMessageHashes.filter { now.timeIntervalSince($0.value) < window }
        if seenMessageHashes[hash] != nil { return false }
        seenMessageHashes[hash] = now
        return true
    }

    public func clear() {
        seenUpdateIds.removeAll()
        seenMessageHashes.removeAll()
    }
}

// MARK: - 사용자 친화적 에러 변환

/// **ADR-085 Phase 4** — NSError → TelegramErrorEntry 변환 helper.
public enum TelegramErrorClassifier {
    public static func classify(_ error: Error) -> TelegramErrorEntry {
        let nsError = error as NSError
        let category: TelegramErrorEntry.Category
        let userMessage: String
        let rawMessage = "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"

        if nsError.domain == "TelegramBot" {
            switch nsError.code {
            case 401:
                category = .auth
                userMessage = "Telegram 봇 토큰이 유효하지 않아요. 설정에서 새 토큰으로 교체하세요."
            case 403:
                category = .auth
                userMessage = "봇이 차단됐거나 chat에서 제거됐어요. 사용자가 봇을 다시 시작하세요."
            case 404:
                category = .auth
                userMessage = "Telegram API 경로 오류. 토큰 형식을 확인하세요."
            case 429:
                category = .rateLimit
                userMessage = "Telegram API 한도 초과. 잠시 후 자동 재시도."
            case 500...599:
                category = .server
                userMessage = "Telegram 서버 일시 오류. 잠시 후 자동 재시도."
            default:
                category = .other
                userMessage = "Telegram 오류 (\(nsError.code))."
            }
        } else if (nsError.domain == NSURLErrorDomain) {
            category = .network
            userMessage = "네트워크 연결 오류. Wi-Fi 또는 모바일 데이터 확인 후 자동 재시도."
        } else {
            category = .other
            userMessage = "예상치 못한 오류. 디버그 로그 확인."
        }

        return TelegramErrorEntry(
            category: category,
            message: rawMessage,
            userFacingMessage: userMessage
        )
    }

    /// HTTP response의 Retry-After header 추출 (초 단위).
    public static func retryAfterSeconds(from headers: [AnyHashable: Any]) -> Double? {
        if let value = headers["Retry-After"] as? String,
           let seconds = Double(value) {
            return seconds
        }
        if let value = headers["retry-after"] as? String,
           let seconds = Double(value) {
            return seconds
        }
        return nil
    }
}
