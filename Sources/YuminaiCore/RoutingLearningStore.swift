import Foundation

// MARK: - RoutingLearningStore (ADR-055)

/// 사용자가 cancel한 routing 결정의 keyword를 학습 → 미래에 같은 keyword에 대해 weight ↓.
///
/// **출처/근거**:
/// - LangSmith Feedback API — user feedback이 future ranking에 영향
/// - Claude Code의 사용자 정의 hooks 패턴 (allow/deny list)
/// - Anthropic prompt cache — keyword 분류 결과의 안정성을 사용자가 통제
///
/// **단순 학습**:
/// - cancel된 횟수가 3회 이상이면 해당 keyword는 "muted" — 다음 routing 시 추천에서 제외
/// - 사용자가 explicitly 추가한 custom keyword는 weight ↑
/// - in-memory + UserDefaults 영속
public actor RoutingLearningStore {
    public static let mutedKey = "yuminai.routing.mutedKeywords"
    public static let cancelCountsKey = "yuminai.routing.cancelCounts"
    public static let customKeywordsKey = "yuminai.routing.customKeywords"
    public static let useCountsKey = "yuminai.routing.useCounts"
    /// cancel 임계 — 이 횟수에 도달하면 keyword muted (binary fallback, ADR-055).
    public static let muteThreshold = 3
    /// **ADR-058 Phase 2** — weight 기반 mute. cancel ratio가 이 값 이상이면 mute.
    /// 동시 사용 (binary OR weight 둘 중 하나라도 trigger).
    public static let muteRatioThreshold = 0.5
    /// minimum sample size — ratio 계산 전 이 횟수만큼 use 후에야 weight 적용.
    public static let minSamplesForRatio = 5

    private let defaults: UserDefaults
    private(set) var cancelCounts: [String: Int] = [:]
    /// **ADR-058 Phase 2** — keyword 사용 (matched) 카운트. ratio = cancel / use.
    private(set) var useCounts: [String: Int] = [:]
    private(set) var mutedKeywords: Set<String> = []
    /// taskKind → 추가 keyword 배열 (사용자 정의)
    private(set) var customKeywords: [String: [String]] = [:]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.mutedKey),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            self.mutedKeywords = Set(arr)
        }
        if let data = defaults.data(forKey: Self.cancelCountsKey),
           let counts = try? JSONDecoder().decode([String: Int].self, from: data) {
            self.cancelCounts = counts
        }
        if let data = defaults.data(forKey: Self.useCountsKey),
           let counts = try? JSONDecoder().decode([String: Int].self, from: data) {
            self.useCounts = counts
        }
        if let data = defaults.data(forKey: Self.customKeywordsKey),
           let custom = try? JSONDecoder().decode([String: [String]].self, from: data) {
            self.customKeywords = custom
        }
    }

    /// **ADR-058 Phase 2** — keyword가 matched 됐을 때 호출 (use count 증가).
    /// AppModel.applyHarnessAutoRoutingIfNeeded에서 classification 후 호출.
    public func recordUse(keyword: String) {
        guard !keyword.isEmpty else { return }
        useCounts[keyword, default: 0] += 1
        persist()
    }

    /// **ADR-058 Phase 2** — keyword cancel ratio (0~1.0).
    /// minSamplesForRatio 미만이면 nil (충분한 sample 없음).
    public func cancelRatio(_ keyword: String) -> Double? {
        let uses = useCounts[keyword] ?? 0
        guard uses >= Self.minSamplesForRatio else { return nil }
        let cancels = cancelCounts[keyword] ?? 0
        return Double(cancels) / Double(uses)
    }

    /// 사용자가 routing을 cancel했을 때 호출.
    /// **ADR-055 (binary)**: muteThreshold 이상 cancel → mute
    /// **ADR-058 Phase 2 (weight)**: cancel ratio ≥ muteRatioThreshold (after minSamples) → mute
    /// 둘 중 하나라도 trigger되면 mute.
    public func recordCancel(keyword: String) {
        guard !keyword.isEmpty else { return }
        cancelCounts[keyword, default: 0] += 1
        let cancels = cancelCounts[keyword] ?? 0
        let uses = useCounts[keyword] ?? 0
        // ADR-055 binary path
        let binaryTrigger = cancels >= Self.muteThreshold
        // ADR-058 weight path — sample 충분 + ratio 도달
        let weightTrigger = uses >= Self.minSamplesForRatio && Double(cancels) / Double(uses) >= Self.muteRatioThreshold
        if binaryTrigger || weightTrigger {
            mutedKeywords.insert(keyword)
        }
        persist()
    }

    /// keyword가 muted인지 (routing skip).
    public func isMuted(_ keyword: String) -> Bool {
        mutedKeywords.contains(keyword)
    }

    /// 명시적 mute / unmute (사용자가 직접 toggle).
    public func setMuted(_ keyword: String, muted: Bool) {
        if muted { mutedKeywords.insert(keyword) }
        else { mutedKeywords.remove(keyword) }
        persist()
    }

    /// 사용자 정의 keyword 추가 (taskKind에 매칭).
    public func addCustomKeyword(_ keyword: String, for taskKind: String) {
        guard !keyword.isEmpty else { return }
        var existing = customKeywords[taskKind] ?? []
        guard !existing.contains(keyword) else { return }
        existing.append(keyword)
        customKeywords[taskKind] = existing
        persist()
    }

    public func removeCustomKeyword(_ keyword: String, for taskKind: String) {
        guard var existing = customKeywords[taskKind] else { return }
        existing.removeAll { $0 == keyword }
        if existing.isEmpty {
            customKeywords.removeValue(forKey: taskKind)
        } else {
            customKeywords[taskKind] = existing
        }
        persist()
    }

    /// 특정 taskKind의 모든 custom keyword (classifier 확장용).
    public func customKeywords(for taskKind: String) -> [String] {
        customKeywords[taskKind] ?? []
    }

    /// snapshot for UI binding.
    public func snapshot() -> Snapshot {
        Snapshot(
            mutedKeywords: mutedKeywords,
            cancelCounts: cancelCounts,
            useCounts: useCounts,
            customKeywords: customKeywords
        )
    }

    public struct Snapshot: Sendable, Hashable {
        public let mutedKeywords: Set<String>
        public let cancelCounts: [String: Int]
        /// **ADR-058 Phase 2** — keyword use 카운트
        public let useCounts: [String: Int]
        public let customKeywords: [String: [String]]

        public init(
            mutedKeywords: Set<String>,
            cancelCounts: [String: Int],
            useCounts: [String: Int] = [:],
            customKeywords: [String: [String]]
        ) {
            self.mutedKeywords = mutedKeywords
            self.cancelCounts = cancelCounts
            self.useCounts = useCounts
            self.customKeywords = customKeywords
        }

        /// **ADR-058 Phase 2** — keyword cancel ratio. minSamplesForRatio 이하는 nil.
        public func cancelRatio(_ keyword: String) -> Double? {
            let uses = useCounts[keyword] ?? 0
            guard uses >= RoutingLearningStore.minSamplesForRatio else { return nil }
            let cancels = cancelCounts[keyword] ?? 0
            return Double(cancels) / Double(uses)
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(Array(mutedKeywords)) {
            defaults.set(data, forKey: Self.mutedKey)
        }
        if let data = try? JSONEncoder().encode(cancelCounts) {
            defaults.set(data, forKey: Self.cancelCountsKey)
        }
        if let data = try? JSONEncoder().encode(useCounts) {
            defaults.set(data, forKey: Self.useCountsKey)
        }
        if let data = try? JSONEncoder().encode(customKeywords) {
            defaults.set(data, forKey: Self.customKeywordsKey)
        }
    }
}
