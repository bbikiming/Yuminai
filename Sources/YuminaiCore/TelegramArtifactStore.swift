import Foundation

/// **ADR-097** — HITL/diff/log 컨텐츠를 UUID로 저장 — deep link lookup 용도.
///
/// 메모리 기반 ring buffer (앱 재시작 시 사라짐).
/// Telegram 발송 → 즉시 클릭 시나리오만 보장 (TTL 기본 1시간).
///
/// 동시성: `actor` 기반 — Swift 6.2 strict concurrency 준수.
public actor TelegramArtifactStore {

    // MARK: - Artifact

    public enum Artifact: Sendable, Equatable {
        /// Git diff 컨텐츠.
        case diff(content: String, files: Int, added: Int, removed: Int, workspace: String?)
        /// 빌드/테스트 로그 컨텐츠.
        case log(content: String, title: String, elapsed: TimeInterval, success: Bool)
    }

    // MARK: - Private State

    private struct Entry: Sendable {
        let artifact: Artifact
        let createdAt: Date
    }

    /// 삽입 순서 추적 (ring buffer FIFO eviction).
    private var insertionOrder: [UUID] = []
    private var entries: [UUID: Entry] = [:]

    private let capacity: Int
    private let ttlSeconds: TimeInterval

    // MARK: - Init

    public init(capacity: Int = 50, ttlSeconds: TimeInterval = 3600) {
        self.capacity = capacity
        self.ttlSeconds = ttlSeconds
    }

    // MARK: - Public API

    /// artifact를 저장하고 UUID를 반환한다.
    ///
    /// capacity 초과 시 가장 오래된 항목을 삭제.
    @discardableResult
    public func store(_ artifact: Artifact) -> UUID {
        let id = UUID()
        let entry = Entry(artifact: artifact, createdAt: Date())

        entries[id] = entry
        insertionOrder.append(id)

        // capacity 초과 시 oldest 제거
        while insertionOrder.count > capacity {
            let oldest = insertionOrder.removeFirst()
            entries.removeValue(forKey: oldest)
        }

        return id
    }

    /// UUID로 artifact를 조회한다. TTL 초과 시 nil 반환.
    public func fetch(_ id: UUID) -> Artifact? {
        guard let entry = entries[id] else { return nil }
        let age = Date().timeIntervalSince(entry.createdAt)
        guard age <= ttlSeconds else {
            // 만료 — lazy 정리
            entries.removeValue(forKey: id)
            insertionOrder.removeAll { $0 == id }
            return nil
        }
        return entry.artifact
    }

    /// 만료된 항목 + capacity 초과 항목 정리.
    public func gc() {
        let now = Date()
        var expired: Set<UUID> = []

        for (id, entry) in entries {
            let age = now.timeIntervalSince(entry.createdAt)
            if age > ttlSeconds {
                expired.insert(id)
            }
        }

        for id in expired {
            entries.removeValue(forKey: id)
        }
        insertionOrder.removeAll { expired.contains($0) }
    }

    /// 현재 저장된 항목 수 (TTL 만료 포함).
    public func count() -> Int {
        entries.count
    }
}
