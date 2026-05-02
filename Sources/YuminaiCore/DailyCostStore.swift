import Foundation

// MARK: - DailyCostStore (ADR-060 Phase 1 + 4)

/// **ADR-060 Phase 1** — workspace별 daily cost를 disk에 영속.
/// **ADR-060 Phase 4** — hourly cache hit ratio trend도 함께 저장 (시계열 분석용).
///
/// 저장 구조 (UserDefaults JSON):
/// - `yuminai.dailyCost.workspace`: `[UUID: WorkspaceDayCost]`
/// - `yuminai.dailyCost.cacheTrend`: `[CacheHitSample]` (최근 24시간, 1시간 단위 bucket)
///
/// 자정 reset은 caller (AppModel)가 날짜 비교 후 호출.
public actor DailyCostStore {
    public static let workspaceKey = "yuminai.dailyCost.workspace"
    public static let cacheTrendKey = "yuminai.dailyCost.cacheTrend"
    public static let cacheTrendCapHours = 24

    private let defaults: UserDefaults
    private(set) var workspaceCosts: [UUID: WorkspaceDayCost] = [:]
    private(set) var cacheTrend: [CacheHitSample] = []

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // load
        if let data = defaults.data(forKey: Self.workspaceKey),
           let map = try? JSONDecoder().decode([UUID: WorkspaceDayCost].self, from: data) {
            self.workspaceCosts = map
        }
        if let data = defaults.data(forKey: Self.cacheTrendKey),
           let arr = try? JSONDecoder().decode([CacheHitSample].self, from: data) {
            self.cacheTrend = arr
        }
    }

    // MARK: - Workspace cost

    /// workspace cost 누적. date 비교로 자동 reset.
    public func addCost(workspaceId: UUID, usd: Double) {
        let cal = Calendar.current
        var current = workspaceCosts[workspaceId] ?? WorkspaceDayCost(date: Date(), costUSD: 0)
        if !cal.isDate(current.date, inSameDayAs: Date()) {
            current = WorkspaceDayCost(date: Date(), costUSD: 0)
        }
        current.costUSD += usd
        current.date = Date()
        workspaceCosts[workspaceId] = current
        persistWorkspace()
    }

    public func cost(workspaceId: UUID) -> Double {
        let cal = Calendar.current
        guard let c = workspaceCosts[workspaceId],
              cal.isDate(c.date, inSameDayAs: Date()) else { return 0 }
        return c.costUSD
    }

    public func snapshot() -> Snapshot {
        Snapshot(workspaceCosts: workspaceCosts, cacheTrend: cacheTrend)
    }

    // MARK: - Cache trend (ADR-060 Phase 4)

    /// hourly bucket에 cache hit sample 추가. 시간이 바뀌면 새 bucket 생성.
    /// cap 24시간 이상은 prune.
    /// **ADR-061 Phase 2** — workspaceId 추가 (per-workspace 분리 분석용).
    public func addCacheSample(read: Int, uncachedInput: Int, workspaceId: UUID? = nil) {
        let now = Date()
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let day = cal.startOfDay(for: now)
        // 같은 시간 bucket + 같은 workspace 찾기
        if let lastIdx = cacheTrend.indices.last,
           let lastDay = cal.dateInterval(of: .day, for: cacheTrend[lastIdx].timestamp)?.start,
           lastDay == day,
           cal.component(.hour, from: cacheTrend[lastIdx].timestamp) == hour,
           cacheTrend[lastIdx].workspaceId == workspaceId {
            cacheTrend[lastIdx].readTokens += read
            cacheTrend[lastIdx].uncachedInputTokens += uncachedInput
        } else {
            cacheTrend.append(CacheHitSample(
                timestamp: now,
                readTokens: read,
                uncachedInputTokens: uncachedInput,
                workspaceId: workspaceId
            ))
        }
        // 24시간 이상 prune
        let cutoff = Date().addingTimeInterval(-Double(Self.cacheTrendCapHours) * 3600)
        cacheTrend.removeAll { $0.timestamp < cutoff }
        persistCacheTrend()
    }

    /// **ADR-061 Phase 2** — workspace별 cache hit ratio (해당 workspace의 모든 sample 평균).
    public func cacheHitRatio(workspaceId: UUID) -> Double {
        let samples = cacheTrend.filter { $0.workspaceId == workspaceId }
        let totalRead = samples.reduce(0) { $0 + $1.readTokens }
        let totalUncached = samples.reduce(0) { $0 + $1.uncachedInputTokens }
        let total = totalRead + totalUncached
        guard total > 0 else { return 0 }
        return Double(totalRead) / Double(total)
    }

    // MARK: - Internal

    private func persistWorkspace() {
        if let data = try? JSONEncoder().encode(workspaceCosts) {
            defaults.set(data, forKey: Self.workspaceKey)
        }
    }

    private func persistCacheTrend() {
        if let data = try? JSONEncoder().encode(cacheTrend) {
            defaults.set(data, forKey: Self.cacheTrendKey)
        }
    }
}

public struct WorkspaceDayCost: Codable, Sendable, Hashable {
    public var date: Date
    public var costUSD: Double

    public init(date: Date, costUSD: Double) {
        self.date = date
        self.costUSD = costUSD
    }
}

/// **ADR-060 Phase 4** — hourly cache hit sample.
/// **ADR-061 Phase 2** — workspaceId 추가 (per-workspace 분리).
public struct CacheHitSample: Codable, Sendable, Hashable, Identifiable {
    public var id: Date { timestamp }
    public let timestamp: Date
    public var readTokens: Int
    public var uncachedInputTokens: Int
    public let workspaceId: UUID?

    public init(timestamp: Date, readTokens: Int, uncachedInputTokens: Int, workspaceId: UUID? = nil) {
        self.timestamp = timestamp
        self.readTokens = readTokens
        self.uncachedInputTokens = uncachedInputTokens
        self.workspaceId = workspaceId
    }

    /// 이 bucket의 hit ratio.
    public var hitRatio: Double {
        let total = readTokens + uncachedInputTokens
        guard total > 0 else { return 0 }
        return Double(readTokens) / Double(total)
    }
}

extension DailyCostStore {
    public struct Snapshot: Sendable, Hashable {
        public let workspaceCosts: [UUID: WorkspaceDayCost]
        public let cacheTrend: [CacheHitSample]

        public init(workspaceCosts: [UUID: WorkspaceDayCost], cacheTrend: [CacheHitSample]) {
            self.workspaceCosts = workspaceCosts
            self.cacheTrend = cacheTrend
        }
    }
}
