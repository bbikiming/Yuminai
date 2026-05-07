import Foundation

/// **ADR-133** — GitLab Search API 클라이언트.
///
/// GitHubSearchClient 패턴을 따르며, GitLab REST API v4를 사용한다.
/// self-hosted GitLab을 지원하기 위해 hostURL을 init 파라미터로 받는다.
///
/// 인증 헤더: `PRIVATE-TOKEN: <token>` 또는 `Authorization: Bearer <token>`.
///
/// ```swift
/// let client = GitLabSearchClient()
/// let page = try await client.searchProjects(query: "swift tdd", perPage: 20)
/// let projects = page.items  // [GitLabProjectResult]
/// ```
public actor GitLabSearchClient {

    // MARK: - URLSession 프로토콜 (테스트 주입용)

    /// URLSession의 데이터 요청 기능을 추상화. 테스트에서 mock 주입 가능.
    public protocol URLSessionProtocol: Sendable {
        func data(for request: URLRequest) async throws -> (Data, URLResponse)
    }

    // MARK: - 결과 타입

    /// GitLab 프로젝트(리포지토리) 검색 결과.
    public struct GitLabProjectResult: Sendable, Equatable, Identifiable {
        /// GitLab 프로젝트 내부 ID.
        public let id: Int
        /// "group/subgroup/project" 형태의 전체 경로.
        public let pathWithNamespace: String
        /// 프로젝트 이름.
        public let name: String
        /// 프로젝트 설명 (nil이면 미설정).
        public let description: String?
        /// Star 수.
        public let stars: Int
        /// 기본 언어 (nil이면 미감지).
        public let language: String?
        /// GitLab 웹 URL.
        public let webURL: URL
        /// 마지막 수정일.
        public let updatedAt: Date?

        public init(
            id: Int,
            pathWithNamespace: String,
            name: String,
            description: String?,
            stars: Int,
            language: String?,
            webURL: URL,
            updatedAt: Date?
        ) {
            self.id = id
            self.pathWithNamespace = pathWithNamespace
            self.name = name
            self.description = description
            self.stars = stars
            self.language = language
            self.webURL = webURL
            self.updatedAt = updatedAt
        }

        /// 스타 수를 간결하게 표시 (예: 12.3k).
        public var starsDisplay: String {
            if stars >= 1000 {
                let k = Double(stars) / 1000.0
                return String(format: "%.1fk", k)
            }
            return "\(stars)"
        }
    }

    /// GitLab 스니펫 검색 결과.
    public struct GitLabSnippetResult: Sendable, Equatable, Identifiable {
        public let id: Int
        public let title: String
        public let fileName: String
        public let description: String?
        public let webURL: URL
        public let createdAt: Date?

        public init(
            id: Int,
            title: String,
            fileName: String,
            description: String?,
            webURL: URL,
            createdAt: Date?
        ) {
            self.id = id
            self.title = title
            self.fileName = fileName
            self.description = description
            self.webURL = webURL
            self.createdAt = createdAt
        }
    }

    // MARK: - Pagination 타입

    /// 페이지네이션된 검색 결과.
    public struct GitLabSearchPage<T: Sendable>: Sendable {
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

    // MARK: - 에러 타입

    /// GitLabSearchClient 호출 시 발생할 수 있는 에러.
    public enum SearchError: Error, LocalizedError, Sendable, Equatable {
        /// 401 Unauthorized — PAT 없음 또는 만료.
        case unauthorized
        /// 403 Forbidden — 프라이빗 리소스 접근 거부.
        case forbidden
        /// 429 Rate Limited.
        case rateLimited
        /// 네트워크 연결 실패.
        case networkError(String)
        /// 응답 파싱 실패.
        case invalidResponse
        /// JSON 디코딩 실패.
        case decodingError(String)
        /// 요청 취소됨.
        case cancelled

        public var errorDescription: String? {
            switch self {
            case .unauthorized:
                return "GitLab 토큰이 만료됐거나 권한이 없어요. PAT를 재설정해 주세요."
            case .forbidden:
                return "접근이 거부됐어요. 프라이빗 프로젝트는 적절한 scope가 필요해요."
            case .rateLimited:
                return "GitLab API 요청 한도 초과. 잠시 후 다시 시도해 주세요."
            case .networkError(let detail):
                return "네트워크 연결 실패: \(detail)"
            case .invalidResponse:
                return "GitLab API 응답 파싱 실패. 잠시 후 다시 시도해 주세요."
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
                return "설정 → GitLab PAT에서 새 토큰을 발급해 주세요. (api 또는 read_api scope)"
            case .rateLimited:
                return "잠시 후 자동으로 초기화돼요. PAT를 추가하면 한도가 늘어나요."
            case .networkError:
                return "Wi-Fi 또는 모바일 데이터 연결을 확인해 주세요."
            default:
                return nil
            }
        }
    }

    // MARK: - 프로퍼티

    private let session: any URLSessionProtocol
    /// GitLab 호스트 URL. self-hosted 사용 시 변경.
    private let hostURL: URL
    /// Personal Access Token (선택). nil이면 비인증 공개 API만.
    private let token: String?

    // MARK: - 초기화

    public init(
        session: any URLSessionProtocol = URLSession.shared,
        hostURL: URL = URL(string: "https://gitlab.com")!,
        token: String? = nil
    ) {
        self.session = session
        self.hostURL = hostURL
        self.token = token
    }

    // MARK: - 프로젝트 검색

    /// GitLab 프로젝트 검색.
    ///
    /// - Parameters:
    ///   - query: 검색어.
    ///   - perPage: 페이지당 결과 수 (기본 20, 최대 100).
    ///   - page: 페이지 번호 (1-based).
    /// - Returns: 페이지네이션된 프로젝트 결과.
    /// - Throws: `SearchError`
    public func searchProjects(
        query: String,
        perPage: Int = 20,
        page: Int = 1
    ) async throws -> GitLabSearchPage<GitLabProjectResult> {
        try Task.checkCancellation()

        let perPageClamped = min(perPage, 100)
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let baseURL = hostURL.appendingPathComponent("/api/v4/projects")
        let urlString = baseURL.absoluteString + "?search=\(encoded)&order_by=star_count&sort=desc&per_page=\(perPageClamped)&page=\(page)"

        guard let url = URL(string: urlString) else {
            throw SearchError.invalidResponse
        }

        let (data, response) = try await fetch(url: url)

        // X-Total 헤더에서 총 개수 파싱
        let totalCount = response.value(forHTTPHeaderField: "X-Total").flatMap(Int.init) ?? 0

        let decoded: [GitLabProjectItem]
        do {
            decoded = try JSONDecoder().decode([GitLabProjectItem].self, from: data)
        } catch {
            throw SearchError.decodingError(error.localizedDescription)
        }

        let items = decoded.compactMap { item -> GitLabProjectResult? in
            guard let webURL = URL(string: item.webUrl) else { return nil }
            return GitLabProjectResult(
                id: item.id,
                pathWithNamespace: item.pathWithNamespace,
                name: item.name,
                description: item.description,
                stars: item.starCount,
                language: nil, // GitLab projects API는 기본 언어를 별도 제공하지 않음
                webURL: webURL,
                updatedAt: item.lastActivityAt.flatMap { iso8601Date($0) }
            )
        }

        return GitLabSearchPage(
            items: items,
            totalCount: max(totalCount, items.count),
            currentPage: page,
            perPage: perPageClamped
        )
    }

    // MARK: - 스니펫 검색

    /// GitLab 스니펫 검색.
    ///
    /// - Parameters:
    ///   - query: 검색어.
    ///   - perPage: 페이지당 결과 수 (기본 20).
    ///   - page: 페이지 번호 (1-based).
    /// - Returns: 페이지네이션된 스니펫 결과.
    /// - Throws: `SearchError`
    public func searchSnippets(
        query: String,
        perPage: Int = 20,
        page: Int = 1
    ) async throws -> GitLabSearchPage<GitLabSnippetResult> {
        try Task.checkCancellation()

        let perPageClamped = min(perPage, 100)
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let baseURL = hostURL.appendingPathComponent("/api/v4/snippets")
        let urlString = baseURL.absoluteString + "?search=\(encoded)&per_page=\(perPageClamped)&page=\(page)"

        guard let url = URL(string: urlString) else {
            throw SearchError.invalidResponse
        }

        let (data, response) = try await fetch(url: url)
        let totalCount = response.value(forHTTPHeaderField: "X-Total").flatMap(Int.init) ?? 0

        let decoded: [GitLabSnippetItem]
        do {
            decoded = try JSONDecoder().decode([GitLabSnippetItem].self, from: data)
        } catch {
            throw SearchError.decodingError(error.localizedDescription)
        }

        let items = decoded.compactMap { item -> GitLabSnippetResult? in
            guard let webURL = URL(string: item.webUrl) else { return nil }
            return GitLabSnippetResult(
                id: item.id,
                title: item.title,
                fileName: item.fileName,
                description: item.description,
                webURL: webURL,
                createdAt: item.createdAt.flatMap { iso8601Date($0) }
            )
        }

        return GitLabSearchPage(
            items: items,
            totalCount: max(totalCount, items.count),
            currentPage: page,
            perPage: perPageClamped
        )
    }

    // MARK: - 현재 사용자 검증 (/api/v4/user)

    /// PAT 유효성 검증 — /api/v4/user 호출.
    /// - Returns: 사용자 이름 (username).
    /// - Throws: `SearchError` (특히 .unauthorized).
    public func validateToken() async throws -> String {
        try Task.checkCancellation()

        let url = hostURL.appendingPathComponent("/api/v4/user")

        let (data, _) = try await fetch(url: url)

        struct UserResponse: Decodable {
            let username: String
        }

        let user: UserResponse
        do {
            user = try JSONDecoder().decode(UserResponse.self, from: data)
        } catch {
            throw SearchError.decodingError(error.localizedDescription)
        }

        return user.username
    }

    // MARK: - Private

    private func fetch(url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15.0
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Yuminai/1.0", forHTTPHeaderField: "User-Agent")

        if let token {
            request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw SearchError.cancelled
        } catch let urlError as URLError {
            throw SearchError.networkError(urlError.localizedDescription)
        } catch {
            throw SearchError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SearchError.invalidResponse
        }

        switch http.statusCode {
        case 200..<300:
            return (data, http)
        case 401:
            throw SearchError.unauthorized
        case 403:
            throw SearchError.forbidden
        case 429:
            throw SearchError.rateLimited
        default:
            throw SearchError.networkError("HTTP \(http.statusCode)")
        }
    }

    private func iso8601Date(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

// MARK: - URLSession conformance

extension URLSession: GitLabSearchClient.URLSessionProtocol {}

// MARK: - 응답 타입 (private decodable)

private struct GitLabProjectItem: Decodable {
    let id: Int
    let name: String
    let pathWithNamespace: String
    let description: String?
    let starCount: Int
    let webUrl: String
    let lastActivityAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case pathWithNamespace = "path_with_namespace"
        case description
        case starCount = "star_count"
        case webUrl = "web_url"
        case lastActivityAt = "last_activity_at"
    }
}

private struct GitLabSnippetItem: Decodable {
    let id: Int
    let title: String
    let fileName: String
    let description: String?
    let webUrl: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case fileName = "file_name"
        case description
        case webUrl = "web_url"
        case createdAt = "created_at"
    }
}
