import Foundation

/// **ADR-122 Phase 3** — GitHub 검색 history + 즐겨찾기 모델.

// MARK: - 검색 히스토리 엔트리

/// GitHub 검색 기록 엔트리.
public struct GitHubSearchHistoryEntry: Sendable, Codable, Hashable, Identifiable {
    public let id: UUID
    public let query: String
    public let mode: Mode
    public let resultCount: Int
    public let searchedAt: Date

    /// 검색 모드.
    public enum Mode: String, Sendable, Codable, Hashable {
        case repositories
        case code
    }

    public init(
        id: UUID = UUID(),
        query: String,
        mode: Mode,
        resultCount: Int,
        searchedAt: Date = Date()
    ) {
        self.id = id
        self.query = query
        self.mode = mode
        self.resultCount = resultCount
        self.searchedAt = searchedAt
    }
}

// MARK: - 검색 즐겨찾기

/// GitHub 저장된 검색어 (즐겨찾기).
public struct GitHubSearchFavorite: Sendable, Codable, Hashable, Identifiable {
    public let id: UUID
    public let query: String
    public let mode: GitHubSearchHistoryEntry.Mode
    /// 사용자 정의 별명.
    public let label: String
    public let savedAt: Date

    public init(
        id: UUID = UUID(),
        query: String,
        mode: GitHubSearchHistoryEntry.Mode,
        label: String,
        savedAt: Date = Date()
    ) {
        self.id = id
        self.query = query
        self.mode = mode
        self.label = label
        self.savedAt = savedAt
    }
}

// MARK: - Ring Buffer 헬퍼

/// 검색 히스토리를 ring buffer로 관리하는 헬퍼.
/// 최신 항목이 앞에 오며, capacity 초과 시 오래된 항목이 제거된다.
public enum GitHubSearchHistoryBuffer {

    /// 히스토리에 새 항목 추가 (ring buffer, 중복 제거).
    /// - Parameters:
    ///   - entry: 추가할 항목.
    ///   - history: 기존 히스토리 배열.
    ///   - capacity: 최대 보관 수 (기본 50).
    /// - Returns: 업데이트된 히스토리 배열 (최신 순).
    public static func append(
        _ entry: GitHubSearchHistoryEntry,
        to history: [GitHubSearchHistoryEntry],
        capacity: Int = 50
    ) -> [GitHubSearchHistoryEntry] {
        // 같은 query + mode 중복 제거 (최신 것으로 교체)
        var filtered = history.filter { $0.query != entry.query || $0.mode != entry.mode }
        // 최신 항목을 앞에 삽입
        filtered.insert(entry, at: 0)
        // capacity 초과 시 tail 제거
        if filtered.count > capacity {
            filtered = Array(filtered.prefix(capacity))
        }
        return filtered
    }
}
