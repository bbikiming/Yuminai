import Foundation

/// **ADR-116** — GitHub Search API 클라이언트.
///
/// GitHub REST API를 통해 리포지토리 검색 및 코드 파일 검색을 수행한다.
/// 인증 토큰 없이 사용 시 60 req/h 제한이 적용된다.
///
/// 사용 패턴:
/// ```swift
/// let client = GitHubSearchClient()
/// let repos = try await client.searchRepositories(query: "claude.md tdd")
/// let files = try await client.searchCode(query: "filename:CLAUDE.md swift")
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

    // MARK: - 에러 타입

    /// GitHubSearchClient 호출 시 발생할 수 있는 에러.
    public enum SearchError: Error, LocalizedError, Sendable {
        /// GitHub API rate limit 초과 (X-RateLimit-Reset 헤더 기반).
        case rateLimited(resetAt: Date?)
        /// 네트워크 연결 실패.
        case networkError(String)
        /// 응답 파싱 실패.
        case invalidResponse
        /// HTTP 오류 (401, 403, 404 등).
        case httpError(Int)
        /// **ADR-119** — 401 Unauthorized: 코드 검색에 PAT가 필요하거나 토큰이 만료됨.
        case unauthorized

        public var errorDescription: String? {
            switch self {
            case .rateLimited(let resetAt):
                if let resetAt {
                    let formatter = DateFormatter()
                    formatter.timeStyle = .short
                    return "GitHub API 요청 한도 초과. \(formatter.string(from: resetAt))에 초기화돼요."
                }
                return "GitHub API 요청 한도 초과. 잠시 후 다시 시도해 주세요."
            case .networkError(let detail):
                return "네트워크 연결 실패: \(detail)"
            case .invalidResponse:
                return "GitHub API 응답 파싱 실패. 잠시 후 다시 시도해 주세요."
            case .httpError(let code):
                return "GitHub API HTTP 오류 \(code)."
            case .unauthorized:
                return "토큰이 만료됐거나 권한이 없어요. GitHub PAT를 재설정해 주세요."
            }
        }
    }

    // MARK: - 프로퍼티

    private let session: any URLSessionProtocol
    /// Personal Access Token (선택). nil이면 비인증 60 req/h 적용.
    private let token: String?

    // MARK: - 초기화

    public init(
        session: any URLSessionProtocol = URLSession.shared,
        token: String? = nil
    ) {
        self.session = session
        self.token = token
    }

    // MARK: - 리포지토리 검색

    /// GitHub 리포지토리 검색 (stars 내림차순 정렬).
    ///
    /// - Parameters:
    ///   - query: 검색어 (예: "claude.md tdd").
    ///   - perPage: 최대 결과 수 (기본 20, 최대 100).
    /// - Returns: 검색 결과 배열.
    /// - Throws: `SearchError`
    public func searchRepositories(query: String, perPage: Int = 20) async throws -> [GitHubRepoResult] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://api.github.com/search/repositories?q=\(encoded)+sort:stars&per_page=\(min(perPage, 100))"

        guard let url = URL(string: urlString) else {
            throw SearchError.invalidResponse
        }

        let data = try await fetch(url: url)

        let decoded: GitHubRepoSearchResponse
        do {
            decoded = try JSONDecoder().decode(GitHubRepoSearchResponse.self, from: data)
        } catch {
            throw SearchError.invalidResponse
        }

        return decoded.items.compactMap { item in
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
    }

    // MARK: - 코드 파일 검색

    /// GitHub 코드 파일 검색.
    ///
    /// CLAUDE.md 검색 예: `query = "filename:CLAUDE.md swift"`
    ///
    /// - Parameters:
    ///   - query: 검색어 (예: "filename:CLAUDE.md swift").
    ///   - perPage: 최대 결과 수 (기본 20, 최대 100).
    /// - Returns: 검색 결과 배열.
    /// - Throws: `SearchError`
    public func searchCode(query: String, perPage: Int = 20) async throws -> [GitHubCodeResult] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://api.github.com/search/code?q=\(encoded)&per_page=\(min(perPage, 100))"

        guard let url = URL(string: urlString) else {
            throw SearchError.invalidResponse
        }

        let data = try await fetch(url: url)

        let decoded: GitHubCodeSearchResponse
        do {
            decoded = try JSONDecoder().decode(GitHubCodeSearchResponse.self, from: data)
        } catch {
            throw SearchError.invalidResponse
        }

        return decoded.items.compactMap { item in
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
    }

    // MARK: - 공통 fetch

    private func fetch(url: URL) async throws -> Data {
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
            throw SearchError.networkError(urlError.localizedDescription)
        } catch {
            throw SearchError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SearchError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            return data
        case 401:
            // 인증 실패 — PAT 없음 또는 만료
            throw SearchError.unauthorized
        case 403, 429:
            // Rate limit 처리
            let resetAt = rateLimit(from: http)
            throw SearchError.rateLimited(resetAt: resetAt)
        default:
            throw SearchError.httpError(http.statusCode)
        }
    }

    private func rateLimit(from response: HTTPURLResponse) -> Date? {
        guard
            let resetHeader = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
            let timestamp = TimeInterval(resetHeader)
        else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }
}

// MARK: - URLSession conformance

extension URLSession: GitHubSearchClient.URLSessionProtocol {}

// MARK: - Response types (private decodable)

private struct GitHubRepoSearchResponse: Decodable {
    let items: [RepoItem]

    struct RepoItem: Decodable {
        let id: Int
        let fullName: String
        let description: String?
        let stargazersCount: Int
        let language: String?
        let htmlUrl: String
        let defaultBranch: String?
        /// ISO8601 문자열 (예: "2024-01-15T10:30:00Z"). 파싱은 호출자 측에서 수행.
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
}

private struct GitHubCodeSearchResponse: Decodable {
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
}
