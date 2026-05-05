import Foundation

/// **ADR-122** — GitHub Search API 클라이언트 (안정성 강화).
///
/// ## 변경 사항 (ADR-116/118/119 → ADR-122)
/// - Retry 정책 (exponential backoff + jitter): 5xx, timeout 자동 재시도
/// - Rate limit 정확한 파싱: X-RateLimit-* 헤더 전체 파싱
/// - Cache layer: 동일 검색 반복 시 API 호출 skip (TTL 5분)
/// - Pagination: page 파라미터 지원, GitHubSearchPage 타입
/// - Request cancellation: Task.checkCancellation() 통합
/// - 에러 분류 강화: 한국어 친화적 메시지 + recoveryHint
///
/// 사용 패턴:
/// ```swift
/// let client = GitHubSearchClient()
/// let page = try await client.searchRepositories(query: "claude.md tdd", perPage: 30, page: 1)
/// let repos = page.items  // [GitHubRepoResult]
/// let hasMore = page.hasMore
/// ```
public actor GitHubSearchClient {

    // MARK: - URLSession 프로토콜 (테스트 주입용)

    /// URLSession의 데이터 요청 기능을 추상화. 테스트에서 mock 주입 가능.
    public protocol URLSessionProtocol: Sendable {
        func data(for request: URLRequest) async throws -> (Data, URLResponse)
    }

    // MARK: - 결과 타입

    /// GitHub 리포지토리 검색 결과.
    public struct GitHubRepoResult: Sendable, Equatable, Identifiable {
        public let id: Int
        /// "anthropics/anthropic-cookbook" 형태의 풀 이름.
        public let fullName: String
        public let description: String?
        public let stars: Int
        public let language: String?
        /// 리포지토리 HTML URL.
        public let url: URL
        public let defaultBranch: String
        /// 마지막 push 날짜 (GitHub API `updated_at` 필드). nil이면 정보 없음.
        public let updatedAt: Date?

        public init(
            id: Int,
            fullName: String,
            description: String?,
            stars: Int,
            language: String?,
            url: URL,
            defaultBranch: String,
            updatedAt: Date? = nil
        ) {
            self.id = id
            self.fullName = fullName
            self.description = description
            self.stars = stars
            self.language = language
            self.url = url
            self.defaultBranch = defaultBranch
            self.updatedAt = updatedAt
        }

        /// 리포지토리의 특정 파일에 대한 raw content URL.
        public func rawURL(for filePath: String) -> URL? {
            URL(string: "https://raw.githubusercontent.com/\(fullName)/\(defaultBranch)/\(filePath)")
        }

        /// 스타 수를 간결하게 표시 (예: 12.3k).
        public var starsDisplay: String {
            if stars >= 1000 {
                let k = Double(stars) / 1000.0
                if k >= 10 {
                    return "\(Int(k))k"
                } else {
                    return String(format: "%.1fk", k)
                }
            }
            return "\(stars)"
        }
    }

    /// GitHub 코드 파일 검색 결과.
    public struct GitHubCodeResult: Sendable, Equatable, Identifiable {
        /// path + repoFullName 조합 (고유성 보장).
        public let id: String
        /// 파일 경로 (예: "CLAUDE.md").
        public let path: String
        public let repoFullName: String
        public let stars: Int
        /// raw content URL (직접 다운로드 가능).
        public let rawURL: URL
        /// GitHub 뷰어 URL.
        public let htmlURL: URL

        public init(
            path: String,
            repoFullName: String,
            stars: Int,
            rawURL: URL,
            htmlURL: URL
        ) {
            self.id = "\(repoFullName)/\(path)"
            self.path = path
            self.repoFullName = repoFullName
            self.stars = stars
            self.rawURL = rawURL
            self.htmlURL = htmlURL
        }
    }

    // MARK: - Pagination 타입 (ADR-122)

    /// 페이지네이션된 검색 결과.
    public struct GitHubSearchPage<T: Sendable>: Sendable {
        public let items: [T]
        public let totalCount: Int
        public let currentPage: Int
        public let perPage: Int
        /// 더 가져올 결과가 있으면 true.
        public var hasMore: Bool { currentPage * perPage < totalCount }

        public init(items: [T], totalCount: Int, currentPage: Int, perPage: Int) {
            self.items = items
            self.totalCount = totalCount
            self.currentPage = currentPage
            self.perPage = perPage
        }
    }

    // MARK: - Rate Limit 타입 (ADR-122)

    /// GitHub API rate limit 정보 (응답 헤더 파싱).
    public struct GitHubRateLimit: Sendable, Equatable {
        public let limit: Int
        public let remaining: Int
        public let resetAt: Date
        /// 리셋까지 남은 시간 (초).
        public var resetIn: TimeInterval { resetAt.timeIntervalSinceNow }
        /// 한도를 초과한 상태인지.
        public var isLimited: Bool { remaining == 0 }

        public init(limit: Int, remaining: Int, resetAt: Date) {
            self.limit = limit
            self.remaining = remaining
            self.resetAt = resetAt
        }

        public var displayText: String {
            "API \(limit)회 중 \(remaining)회 남음"
        }

        public var resetDisplayText: String {
            let mins = Int(max(0, resetIn) / 60)
            if mins > 0 { return "\(mins)분 후 리셋" }
            return "곧 리셋"
        }
    }

    // MARK: - 에러 타입 (ADR-122 강화)

    /// GitHubSearchClient 호출 시 발생할 수 있는 에러.
    public enum SearchError: Error, LocalizedError, Sendable {
        /// 네트워크 연결 실패.
        case networkError(String)
        /// 요청 시간 초과.
        case timeout
        /// 401 Unauthorized — PAT 없음 또는 만료.
        case unauthorized
        /// 403 Forbidden (rate limit 외).
        case forbidden(String)
        /// GitHub API rate limit 초과.
        case rateLimited(retryAfter: TimeInterval?, resetAt: Date?)
        /// 422 — 검색어 형식 오류.
        case invalidQuery(String)
        /// 5xx 서버 에러.
        case serverError(Int)
        /// 응답 파싱 실패.
        case invalidResponse
        /// JSON 디코딩 실패.
        case decodingError(String)
        /// 요청 취소됨.
        case cancelled

        // MARK: - backward-compat aliases
        /// ADR-116 호환: httpError(Int)
        public static func httpError(_ code: Int) -> SearchError { .serverError(code) }

        public var errorDescription: String? {
            switch self {
            case .networkError(let detail):
                return "네트워크 연결 실패: \(detail)"
            case .timeout:
                return "요청 시간이 초과됐어요. 잠시 후 다시 시도해 주세요."
            case .unauthorized:
                return "토큰이 만료됐거나 권한이 없어요. GitHub PAT를 재설정해 주세요."
            case .forbidden(let detail):
                return "접근이 거부됐어요: \(detail)"
            case .rateLimited(_, let resetAt):
                if let resetAt {
                    let formatter = DateFormatter()
                    formatter.timeStyle = .short
                    return "GitHub API 요청 한도 초과. \(formatter.string(from: resetAt))에 초기화돼요."
                }
                return "GitHub API 요청 한도 초과. 잠시 후 다시 시도해 주세요."
            case .invalidQuery(let detail):
                return "검색어 형식이 올바르지 않아요: \(detail)"
            case .serverError(let code):
                return "GitHub 서버 오류 (\(code)). 잠시 후 다시 시도해 주세요."
            case .invalidResponse:
                return "GitHub API 응답 파싱 실패. 잠시 후 다시 시도해 주세요."
            case .decodingError(let detail):
                return "응답 해석 실패: \(detail)"
            case .cancelled:
                return "검색이 취소됐어요."
            }
        }

        /// 사용자가 취해야 할 다음 액션.
        public var recoveryHint: String? {
            switch self {
            case .unauthorized:
                return "설정 → GitHub PAT에서 새 토큰을 발급해 주세요."
            case .rateLimited:
                return "잠시 후 자동으로 초기화돼요. 또는 GitHub PAT를 추가하면 한도가 늘어나요."
            case .networkError:
                return "Wi-Fi 또는 모바일 데이터 연결을 확인해 주세요."
            case .invalidQuery:
                return "GitHub 검색 문법을 확인해 주세요 (예: filename:CLAUDE.md language:Swift)."
            default:
                return nil
            }
        }
    }

    // MARK: - 프로퍼티

    private let session: any URLSessionProtocol
    /// Personal Access Token (선택). nil이면 비인증 60 req/h 적용.
    private let token: String?
    /// 재시도 정책.
    private let retryPolicy: GitHubRetryPolicy
    /// 캐시 레이어 (nil이면 캐시 비활성).
    private let cache: GitHubSearchCache?
    /// 마지막 응답에서 파싱한 rate limit 정보.
    private var lastRateLimit: GitHubRateLimit?

    // MARK: - 초기화

    public init(
        session: any URLSessionProtocol = URLSession.shared,
        token: String? = nil,
        retryPolicy: GitHubRetryPolicy = .default,
        cache: GitHubSearchCache? = GitHubSearchCache()
    ) {
        self.session = session
        self.token = token
        self.retryPolicy = retryPolicy
        self.cache = cache
    }

    // MARK: - Rate Limit 조회

    /// 마지막 응답에서 파싱한 rate limit 정보. 첫 요청 전에는 nil.
    public func currentRateLimit() -> GitHubRateLimit? {
        lastRateLimit
    }

    // MARK: - 리포지토리 검색 (Pagination 지원)

    /// GitHub 리포지토리 검색 (stars 내림차순 정렬).
    ///
    /// - Parameters:
    ///   - query: 검색어 (예: "claude.md tdd").
    ///   - perPage: 페이지당 결과 수 (기본 30, 최대 100).
    ///   - page: 페이지 번호 (1-based, 기본 1).
    ///   - forceRefresh: true면 캐시 무시.
    /// - Returns: 페이지네이션된 검색 결과.
    /// - Throws: `SearchError`
    public func searchRepositories(
        query: String,
        perPage: Int = 30,
        page: Int = 1,
        forceRefresh: Bool = false
    ) async throws -> GitHubSearchPage<GitHubRepoResult> {
        try Task.checkCancellation()

        let cacheKey = GitHubSearchCache.CacheKey(endpoint: "repositories", query: query, perPage: perPage, page: page)

        if !forceRefresh, let cached = await cache?.get(cacheKey) {
            if case .repositories(let items) = cached {
                return GitHubSearchPage(items: items, totalCount: items.count, currentPage: page, perPage: perPage)
            }
        }

        let perPageClamped = min(perPage, 100)
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://api.github.com/search/repositories?q=\(encoded)+sort:stars&per_page=\(perPageClamped)&page=\(page)"

        guard let url = URL(string: urlString) else {
            throw SearchError.invalidResponse
        }

        let (data, response) = try await fetchWithRetry(url: url)
        updateRateLimit(from: response)

        let decoded: GitHubRepoSearchResponse
        do {
            decoded = try JSONDecoder().decode(GitHubRepoSearchResponse.self, from: data)
        } catch {
            throw SearchError.decodingError(error.localizedDescription)
        }

        let items = decoded.items.compactMap { item -> GitHubRepoResult? in
            guard let htmlURL = URL(string: item.htmlUrl) else { return nil }
            return GitHubRepoResult(
                id: item.id,
                fullName: item.fullName,
                description: item.description,
                stars: item.stargazersCount,
                language: item.language,
                url: htmlURL,
                defaultBranch: item.defaultBranch ?? "main",
                updatedAt: item.updatedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
            )
        }

        await cache?.set(cacheKey, value: .repositories(items))
        return GitHubSearchPage(
            items: items,
            totalCount: decoded.totalCount,
            currentPage: page,
            perPage: perPageClamped
        )
    }

    // MARK: - 코드 파일 검색 (Pagination 지원)

    /// GitHub 코드 파일 검색.
    ///
    /// CLAUDE.md 검색 예: `query = "filename:CLAUDE.md swift"`
    ///
    /// - Parameters:
    ///   - query: 검색어.
    ///   - perPage: 페이지당 결과 수 (기본 30, 최대 100).
    ///   - page: 페이지 번호 (1-based).
    ///   - forceRefresh: true면 캐시 무시.
    /// - Returns: 페이지네이션된 검색 결과.
    /// - Throws: `SearchError`
    public func searchCode(
        query: String,
        perPage: Int = 30,
        page: Int = 1,
        forceRefresh: Bool = false
    ) async throws -> GitHubSearchPage<GitHubCodeResult> {
        try Task.checkCancellation()

        let cacheKey = GitHubSearchCache.CacheKey(endpoint: "code", query: query, perPage: perPage, page: page)

        if !forceRefresh, let cached = await cache?.get(cacheKey) {
            if case .code(let items) = cached {
                return GitHubSearchPage(items: items, totalCount: items.count, currentPage: page, perPage: perPage)
            }
        }

        let perPageClamped = min(perPage, 100)
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://api.github.com/search/code?q=\(encoded)&per_page=\(perPageClamped)&page=\(page)"

        guard let url = URL(string: urlString) else {
            throw SearchError.invalidResponse
        }

        let (data, response) = try await fetchWithRetry(url: url)
        updateRateLimit(from: response)

        let decoded: GitHubCodeSearchResponse
        do {
            decoded = try JSONDecoder().decode(GitHubCodeSearchResponse.self, from: data)
        } catch {
            throw SearchError.decodingError(error.localizedDescription)
        }

        let items = decoded.items.compactMap { item -> GitHubCodeResult? in
            guard
                let rawURL = URL(string: item.url
                    .replacingOccurrences(of: "https://api.github.com/repos/", with: "https://raw.githubusercontent.com/")
                    .replacingOccurrences(of: "/contents/", with: "/\(item.repository.defaultBranch ?? "main")/")),
                let htmlURL = URL(string: item.htmlUrl)
            else { return nil }

            return GitHubCodeResult(
                path: item.path,
                repoFullName: item.repository.fullName,
                stars: item.repository.stargazersCount ?? 0,
                rawURL: rawURL,
                htmlURL: htmlURL
            )
        }

        await cache?.set(cacheKey, value: .code(items))
        return GitHubSearchPage(
            items: items,
            totalCount: decoded.totalCount,
            currentPage: page,
            perPage: perPageClamped
        )
    }

    // MARK: - 단일 파일 fetch (Crawler 용)

    /// URL에서 원시 파일 콘텐츠 다운로드.
    /// - Returns: 파일 문자열 콘텐츠.
    /// - Throws: `SearchError`
    public func fetchRawContent(url: URL) async throws -> String {
        try Task.checkCancellation()

        var request = URLRequest(url: url)
        request.timeoutInterval = 15.0
        request.setValue("Yuminai/1.0", forHTTPHeaderField: "User-Agent")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw SearchError.cancelled
        } catch let urlError as URLError {
            if urlError.code == .timedOut { throw SearchError.timeout }
            throw SearchError.networkError(urlError.localizedDescription)
        } catch {
            throw SearchError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SearchError.invalidResponse
        }

        guard http.statusCode == 200 else {
            throw SearchError.serverError(http.statusCode)
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw SearchError.decodingError("파일을 UTF-8로 디코딩할 수 없어요.")
        }

        return text
    }

    // MARK: - 공통 fetch with retry

    private func fetchWithRetry(url: URL) async throws -> (Data, HTTPURLResponse) {
        var lastError: Error = SearchError.invalidResponse

        for attempt in 0..<retryPolicy.maxAttempts {
            do {
                try Task.checkCancellation()
                let (data, response) = try await fetch(url: url)
                return (data, response)
            } catch is CancellationError {
                throw SearchError.cancelled
            } catch let searchError as SearchError {
                // 재시도 불가능한 에러는 즉시 전파
                switch searchError {
                case .unauthorized, .forbidden, .invalidQuery, .rateLimited, .cancelled:
                    throw searchError
                case .serverError(let code):
                    if !retryPolicy.isRetryable(statusCode: code) {
                        throw searchError
                    }
                    lastError = searchError
                default:
                    lastError = searchError
                }
            } catch {
                lastError = error
            }

            // 마지막 시도면 바로 실패
            guard retryPolicy.shouldRetry(attempt: attempt) else { break }

            let delay = retryPolicy.delay(for: attempt)
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        throw lastError
    }

    private func fetch(url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15.0
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Yuminai/1.0", forHTTPHeaderField: "User-Agent")

        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            if urlError.code == .timedOut { throw SearchError.timeout }
            throw SearchError.networkError(urlError.localizedDescription)
        } catch {
            throw SearchError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SearchError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            return (data, http)
        case 401:
            throw SearchError.unauthorized
        case 403:
            // rate limit 여부 구분
            let remaining = http.value(forHTTPHeaderField: "X-RateLimit-Remaining")
            if remaining == "0" {
                let resetAt = parseResetDate(from: http)
                let retryAfter = parseRetryAfter(from: http)
                throw SearchError.rateLimited(retryAfter: retryAfter, resetAt: resetAt)
            }
            let body = (try? JSONDecoder().decode([String: String].self, from: data))?["message"] ?? "접근 거부"
            throw SearchError.forbidden(body)
        case 422:
            let body = (try? JSONDecoder().decode([String: String].self, from: data))?["message"] ?? "잘못된 검색어"
            throw SearchError.invalidQuery(body)
        case 429:
            let resetAt = parseResetDate(from: http)
            let retryAfter = parseRetryAfter(from: http)
            throw SearchError.rateLimited(retryAfter: retryAfter, resetAt: resetAt)
        case 500...599:
            throw SearchError.serverError(http.statusCode)
        default:
            throw SearchError.serverError(http.statusCode)
        }
    }

    // MARK: - 헤더 파싱

    private func parseResetDate(from response: HTTPURLResponse) -> Date? {
        guard
            let resetHeader = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
            let timestamp = TimeInterval(resetHeader)
        else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    private func parseRetryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After"),
            let seconds = TimeInterval(retryAfter)
        else { return nil }
        return seconds
    }

    private func updateRateLimit(from response: HTTPURLResponse) {
        guard
            let limitStr = response.value(forHTTPHeaderField: "X-RateLimit-Limit"),
            let limit = Int(limitStr),
            let remainingStr = response.value(forHTTPHeaderField: "X-RateLimit-Remaining"),
            let remaining = Int(remainingStr),
            let resetAt = parseResetDate(from: response)
        else { return }

        lastRateLimit = GitHubRateLimit(limit: limit, remaining: remaining, resetAt: resetAt)
    }
}

// MARK: - URLSession conformance

extension URLSession: GitHubSearchClient.URLSessionProtocol {}

// MARK: - Response types (private decodable)

private struct GitHubRepoSearchResponse: Decodable {
    let totalCount: Int
    let items: [RepoItem]

    struct RepoItem: Decodable {
        let id: Int
        let fullName: String
        let description: String?
        let stargazersCount: Int
        let language: String?
        let htmlUrl: String
        let defaultBranch: String?
        let updatedAt: String?

        enum CodingKeys: String, CodingKey {
            case id
            case fullName = "full_name"
            case description
            case stargazersCount = "stargazers_count"
            case language
            case htmlUrl = "html_url"
            case defaultBranch = "default_branch"
            case updatedAt = "updated_at"
        }
    }

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case items
    }
}

private struct GitHubCodeSearchResponse: Decodable {
    let totalCount: Int
    let items: [CodeItem]

    struct CodeItem: Decodable {
        let path: String
        let url: String
        let htmlUrl: String
        let repository: RepoRef

        enum CodingKeys: String, CodingKey {
            case path
            case url
            case htmlUrl = "html_url"
            case repository
        }
    }

    struct RepoRef: Decodable {
        let fullName: String
        let stargazersCount: Int?
        let defaultBranch: String?

        enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
            case stargazersCount = "stargazers_count"
            case defaultBranch = "default_branch"
        }
    }

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case items
    }
}
