import Foundation

// MARK: - TelegramUsageStore (ADR-062 Phase 6 — 사용자 신규 요청)

/// **사용자 요청**: 텔레그램과의 연동 기능을 얼마나 이용했고 얼마나 토큰이 소모됐는지 dashboard.
///
/// **저장 데이터**:
/// - chat별 turn 카운트 + 누적 cost + 누적 token
/// - 명령별 사용 빈도 (/decompose, /tasks, /rehearse 등)
/// - 시간별 (hourly bucket) turn count + cost — 시계열 trend
/// - lifetime + today 분리
///
/// **disk persist**: UserDefaults JSON.
public actor TelegramUsageStore {
    public static let chatStatsKey = "yuminai.telegram.chatStats"
    public static let commandStatsKey = "yuminai.telegram.commandStats"
    public static let hourlyBucketsKey = "yuminai.telegram.hourlyBuckets"
    public static let bucketCapHours = 7 * 24  // 7일

    private let defaults: UserDefaults
    private(set) var chatStats: [String: ChatUsageStats] = [:]  // chatId(string) → stats
    private(set) var commandStats: [String: Int] = [:]  // command → count
    private(set) var hourlyBuckets: [HourlyUsageBucket] = []

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.chatStatsKey),
           let map = try? JSONDecoder().decode([String: ChatUsageStats].self, from: data) {
            self.chatStats = map
        }
        if let data = defaults.data(forKey: Self.commandStatsKey),
           let map = try? JSONDecoder().decode([String: Int].self, from: data) {
            self.commandStats = map
        }
        if let data = defaults.data(forKey: Self.hourlyBucketsKey),
           let arr = try? JSONDecoder().decode([HourlyUsageBucket].self, from: data) {
            self.hourlyBuckets = arr
        }
    }

    // MARK: - Recording

    /// turn 시작 시 호출 — chat별 + hourly bucket 카운트.
    public func recordTurnStart(chatId: Int64) {
        let key = String(chatId)
        var stats = chatStats[key] ?? ChatUsageStats(chatId: chatId)
        stats.turnCount += 1
        stats.lastUsedAt = Date()
        chatStats[key] = stats
        // hourly bucket
        upsertHourlyBucket { $0.turnCount += 1 }
        persist()
    }

    /// turn 종료 시 호출 — cost + token 누적.
    public func recordTurnComplete(
        chatId: Int64,
        costUSD: Double,
        inputTokens: Int,
        outputTokens: Int
    ) {
        let key = String(chatId)
        var stats = chatStats[key] ?? ChatUsageStats(chatId: chatId)
        stats.totalCostUSD += costUSD
        stats.totalInputTokens += inputTokens
        stats.totalOutputTokens += outputTokens
        chatStats[key] = stats
        // hourly bucket
        upsertHourlyBucket { bucket in
            bucket.costUSD += costUSD
            bucket.inputTokens += inputTokens
            bucket.outputTokens += outputTokens
        }
        persist()
    }

    /// 명령 실행 시 호출 (router에서).
    public func recordCommand(_ command: String) {
        let key = command.hasPrefix("/") ? command : "/" + command
        commandStats[key, default: 0] += 1
        persist()
    }

    // MARK: - Snapshot

    public func snapshot() -> Snapshot {
        Snapshot(
            chatStats: chatStats,
            commandStats: commandStats,
            hourlyBuckets: hourlyBuckets
        )
    }

    public func clear() {
        chatStats.removeAll()
        commandStats.removeAll()
        hourlyBuckets.removeAll()
        persist()
    }

    // MARK: - Internal

    private func upsertHourlyBucket(_ mutate: (inout HourlyUsageBucket) -> Void) {
        let now = Date()
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let day = cal.startOfDay(for: now)

        if let lastIdx = hourlyBuckets.indices.last,
           let bucketDay = cal.dateInterval(of: .day, for: hourlyBuckets[lastIdx].timestamp)?.start,
           bucketDay == day,
           cal.component(.hour, from: hourlyBuckets[lastIdx].timestamp) == hour {
            // 같은 hour bucket
            mutate(&hourlyBuckets[lastIdx])
        } else {
            // 새 bucket
            var bucket = HourlyUsageBucket(timestamp: now)
            mutate(&bucket)
            hourlyBuckets.append(bucket)
        }
        // cap 7일 prune
        let cutoff = Date().addingTimeInterval(-Double(Self.bucketCapHours) * 3600)
        hourlyBuckets.removeAll { $0.timestamp < cutoff }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(chatStats) {
            defaults.set(data, forKey: Self.chatStatsKey)
        }
        if let data = try? JSONEncoder().encode(commandStats) {
            defaults.set(data, forKey: Self.commandStatsKey)
        }
        if let data = try? JSONEncoder().encode(hourlyBuckets) {
            defaults.set(data, forKey: Self.hourlyBucketsKey)
        }
    }
}

public struct ChatUsageStats: Codable, Sendable, Hashable, Identifiable {
    public var id: Int64 { chatId }
    public let chatId: Int64
    public var turnCount: Int = 0
    public var totalCostUSD: Double = 0
    public var totalInputTokens: Int = 0
    public var totalOutputTokens: Int = 0
    public var lastUsedAt: Date = Date()

    public init(chatId: Int64) {
        self.chatId = chatId
    }
}

public struct HourlyUsageBucket: Codable, Sendable, Hashable, Identifiable {
    public var id: Date { timestamp }
    public let timestamp: Date
    public var turnCount: Int = 0
    public var costUSD: Double = 0
    public var inputTokens: Int = 0
    public var outputTokens: Int = 0

    public init(timestamp: Date) {
        self.timestamp = timestamp
    }
}

extension TelegramUsageStore {
    public struct Snapshot: Sendable, Hashable {
        public let chatStats: [String: ChatUsageStats]
        public let commandStats: [String: Int]
        public let hourlyBuckets: [HourlyUsageBucket]

        public init(
            chatStats: [String: ChatUsageStats],
            commandStats: [String: Int],
            hourlyBuckets: [HourlyUsageBucket]
        ) {
            self.chatStats = chatStats
            self.commandStats = commandStats
            self.hourlyBuckets = hourlyBuckets
        }

        public var totalTurns: Int {
            chatStats.values.reduce(0) { $0 + $1.turnCount }
        }
        public var totalCostUSD: Double {
            chatStats.values.reduce(0) { $0 + $1.totalCostUSD }
        }
        public var totalCommands: Int {
            commandStats.values.reduce(0, +)
        }
    }
}
