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
    }

    public struct Snapshot: Sendable, Codable, Hashable {
        public let main: Double
        public let decomposition: Double
        public let rehearsal: Double
        public let routing: Double
        public var total: Double { main + decomposition + rehearsal + routing }

        public init(main: Double, decomposition: Double, rehearsal: Double, routing: Double) {
            self.main = main
            self.decomposition = decomposition
            self.rehearsal = rehearsal
            self.routing = routing
        }

        public func formatted() -> String {
            String(format: "Main: $%.4f / Decomp: $%.4f / Rehearsal: $%.4f / Routing: $%.4f / Total: $%.4f",
                main, decomposition, rehearsal, routing, total)
        }
    }

    /// bucket별 누적 USD
    public private(set) var buckets: [Bucket: Double] = [:]

    public init() {
        for b in Bucket.allCases { buckets[b] = 0.0 }
    }

    public func add(_ bucket: Bucket, usd: Double) {
        buckets[bucket, default: 0.0] += usd
    }

    public func snapshot() -> Snapshot {
        Snapshot(
            main: buckets[.main] ?? 0,
            decomposition: buckets[.decomposition] ?? 0,
            rehearsal: buckets[.rehearsal] ?? 0,
            routing: buckets[.routing] ?? 0
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
