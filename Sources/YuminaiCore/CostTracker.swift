import Foundation

// MARK: - CostTracker (ADR-052)

/// LLM 비용 분리 추적 — 메인 conversation, decomposition, rehearsal 별도 누적.
///
/// **출처/근거**:
/// - Aider `architect_coder.py:29, 47` — `kwargs["total_cost"]` 별도 슬롯 패턴
/// - Cline `SubagentRunStats { totalCost, ... }` — sub-agent별 stats 분리
///   (cline/src/core/task/tools/subagent/SubagentRunner.ts:48-58)
/// - Datadog LLM Obs `metrics` field — span-kind별 비용 집계
///
/// **사용 예**:
/// ```
/// let cost = CostTracker.shared
/// cost.add(.main, usd: 0.0042)
/// cost.add(.decomposition, usd: 0.0011)  // 메인과 분리
/// print(cost.snapshot())
/// // → "Main: $0.0042 / Decomp: $0.0011 / Rehearsal: $0.0000 / Total: $0.0053"
/// ```
@MainActor
@Observable
public final class CostTracker {
    public enum Bucket: String, Sendable, CaseIterable, Codable, Hashable {
        case main          // 사용자 conversation에 직접 들어가는 호출
        case decomposition // /decompose ephemeral session
        case rehearsal     // walk-through rehearsal 재실행
        case routing       // routing classifier (현재는 휴리스틱이라 0, 향후 LLM-based 시 사용)
        case parallel      // ADR-053 — multi-agent parallel 두 번째 pane (BSP barrier)
    }

    public struct Snapshot: Sendable, Codable, Hashable {
        public let main: Double
        public let decomposition: Double
        public let rehearsal: Double
        public let routing: Double
        public let parallel: Double
        public var total: Double { main + decomposition + rehearsal + routing + parallel }

        public init(main: Double, decomposition: Double, rehearsal: Double, routing: Double, parallel: Double = 0.0) {
            self.main = main
            self.decomposition = decomposition
            self.rehearsal = rehearsal
            self.routing = routing
            self.parallel = parallel
        }

        public func formatted() -> String {
            String(format: "Main: $%.4f / Decomp: $%.4f / Rehearsal: $%.4f / Routing: $%.4f / Parallel: $%.4f / Total: $%.4f",
                main, decomposition, rehearsal, routing, parallel, total)
        }
    }

    /// bucket별 누적 USD
    public private(set) var buckets: [Bucket: Double] = [:]
    /// **ADR-059 Phase 1** — cache hit/creation token 누적 (총합 — bucket별 분리는 향후).
    public private(set) var totalCacheReadTokens: Int = 0
    public private(set) var totalCacheCreationTokens: Int = 0
    /// **ADR-059 Phase 1** — cache miss로 input으로 처리된 토큰 누적 (cache 활용율 분모용).
    public private(set) var totalUncachedInputTokens: Int = 0

    public init() {
        for b in Bucket.allCases { buckets[b] = 0.0 }
    }

    public func add(_ bucket: Bucket, usd: Double) {
        buckets[bucket, default: 0.0] += usd
    }

    /// **ADR-059 Phase 1** — ChildProcess 호출 시 cache 활용 누적.
    /// caller: AppModel decompose/rehearsal/parallel 호출 후.
    public func addCacheStats(read: Int, creation: Int, uncachedInput: Int) {
        totalCacheReadTokens += max(0, read)
        totalCacheCreationTokens += max(0, creation)
        totalUncachedInputTokens += max(0, uncachedInput)
    }

    /// **ADR-059 Phase 1** — 누적 cache hit ratio (0~1.0).
    /// 1.0 = 모든 input이 cache. 0.0 = cache 효과 없음.
    public var cumulativeCacheHitRatio: Double {
        let total = totalCacheReadTokens + totalUncachedInputTokens
        guard total > 0 else { return 0 }
        return Double(totalCacheReadTokens) / Double(total)
    }

    public func snapshot() -> Snapshot {
        Snapshot(
            main: buckets[.main] ?? 0,
            decomposition: buckets[.decomposition] ?? 0,
            rehearsal: buckets[.rehearsal] ?? 0,
            routing: buckets[.routing] ?? 0,
            parallel: buckets[.parallel] ?? 0
        )
    }

    public func reset() {
        for b in Bucket.allCases { buckets[b] = 0.0 }
    }

    public func reset(_ bucket: Bucket) {
        buckets[bucket] = 0.0
    }

    /// 토큰 → 비용 추정 (Claude Sonnet 4.5 평균치 기준).
    /// 정확한 비용은 별도 metric 시스템 (LiveClaudeAdapter usage 이벤트)에서 추적.
    /// nonisolated — pure 함수, actor 격리 불필요.
    public nonisolated static func estimateCostUSD(inputTokens: Int, outputTokens: Int) -> Double {
        // Sonnet 4.5: input $3/MTok, output $15/MTok
        let inputCost = Double(inputTokens) / 1_000_000.0 * 3.0
        let outputCost = Double(outputTokens) / 1_000_000.0 * 15.0
        return inputCost + outputCost
    }
}
