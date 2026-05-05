import Foundation

/// **ADR-122 Phase 1** — GitHub 검색 결과 캐시 (in-memory, TTL + capacity).
///
/// 동일 검색어/파라미터 조합에 대해 반복 API 호출을 방지.
/// actor 기반으로 동시성 안전.
///
/// 기본값:
/// - TTL: 5분 (300초)
/// - capacity: 50개
public actor GitHubSearchCache {

    // MARK: - 캐시 키

    /// 캐시 엔트리를 식별하는 키.
    public struct CacheKey: Hashable, Sendable {
        public let endpoint: String  // "repositories" | "code"
        public let query: String
        public let perPage: Int
        public let page: Int

        public init(endpoint: String, query: String, perPage: Int, page: Int = 1) {
            self.endpoint = endpoint
            self.query = query
            self.perPage = perPage
            self.page = page
        }
    }

    // MARK: - 캐시 값

    /// 캐시에 저장되는 직렬화 가능한 값.
    public enum CacheValue: Sendable {
        case repositories([GitHubSearchClient.GitHubRepoResult])
        case code([GitHubSearchClient.GitHubCodeResult])
    }

    // MARK: - 내부 엔트리

    private struct CacheEntry {
        let value: CacheValue
        let cachedAt: Date
        let accessCount: Int

        init(value: CacheValue, cachedAt: Date = Date(), accessCount: Int = 0) {
            self.value = value
            self.cachedAt = cachedAt
            self.accessCount = accessCount
        }

        func isExpired(ttl: TimeInterval) -> Bool {
            Date().timeIntervalSince(cachedAt) > ttl
        }
    }

    // MARK: - 프로퍼티

    private var entries: [CacheKey: CacheEntry] = [:]
    private let ttl: TimeInterval
    private let capacity: Int

    public init(ttl: TimeInterval = 300, capacity: Int = 50) {
        self.ttl = ttl
        self.capacity = capacity
    }

    // MARK: - 공개 인터페이스

    /// 캐시 조회. 만료됐거나 없으면 nil.
    public func get(_ key: CacheKey) -> CacheValue? {
        guard let entry = entries[key] else { return nil }
        guard !entry.isExpired(ttl: ttl) else {
            entries.removeValue(forKey: key)
            return nil
        }
        // access count 갱신 (immutable update)
        entries[key] = CacheEntry(
            value: entry.value,
            cachedAt: entry.cachedAt,
            accessCount: entry.accessCount + 1
        )
        return entry.value
    }

    /// 캐시에 값 저장. capacity 초과 시 gc() 자동 실행.
    public func set(_ key: CacheKey, value: CacheValue) {
        entries[key] = CacheEntry(value: value)
        if entries.count > capacity {
            gc()
        }
    }

    /// 전체 캐시 초기화.
    public func clear() {
        entries.removeAll()
    }

    /// 만료 엔트리 제거 + capacity 초과 시 오래된 항목 정리.
    public func gc() {
        // 만료 항목 제거
        let now = Date()
        entries = entries.filter { _, entry in
            now.timeIntervalSince(entry.cachedAt) <= ttl
        }

        // 여전히 capacity 초과 시 가장 오래된 항목 제거
        if entries.count > capacity {
            let sorted = entries.sorted { $0.value.cachedAt < $1.value.cachedAt }
            let toRemove = sorted.prefix(entries.count - capacity)
            for (key, _) in toRemove {
                entries.removeValue(forKey: key)
            }
        }
    }

    /// 현재 캐시 항목 수.
    public func count() -> Int {
        entries.count
    }
}
