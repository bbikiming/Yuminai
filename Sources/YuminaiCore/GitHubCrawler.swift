import Foundation

/// **ADR-122 Phase 2** — GitHub 리포지토리 크롤러.
///
/// 단일 리포지토리의 여러 관련 파일(CLAUDE.md, .cursorrules, AGENTS.md 등)을
/// 자동으로 탐색 및 수집한다. 각 경로에 대해 HTTP 요청을 보내고,
/// 200이면 결과에 포함, 404면 skip한다.
///
/// 사용 패턴:
/// ```swift
/// let client = GitHubSearchClient(token: pat)
/// let crawler = GitHubCrawler(client: client)
/// let result = try await crawler.crawlRepository(owner: "anthropics", repo: "anthropic-cookbook")
/// for file in result.files {
///     print(file.path, file.category)
/// }
/// ```
public actor GitHubCrawler {

    // MARK: - 크롤 결과

    /// 크롤링 결과.
    public struct CrawlResult: Sendable, Equatable {
        public let owner: String
        public let repo: String
        /// 리포 메타데이터 (API 조회 성공 시).
        public let metadata: GitHubRepoMetadata?
        /// 수집된 파일 목록.
        public let files: [CrawledFile]
        /// 시도한 경로 전체 (성공 여부 무관).
        public let attemptedPaths: [String]
        /// 크롤 수행 시각.
        public let crawledAt: Date

        public init(
            owner: String,
            repo: String,
            metadata: GitHubRepoMetadata?,
            files: [CrawledFile],
            attemptedPaths: [String],
            crawledAt: Date = Date()
        ) {
            self.owner = owner
            self.repo = repo
            self.metadata = metadata
            self.files = files
            self.attemptedPaths = attemptedPaths
            self.crawledAt = crawledAt
        }
    }

    /// 크롤링으로 수집된 개별 파일.
    public struct CrawledFile: Sendable, Equatable {
        public let path: String
        /// 파일 내용 기반 카테고리 추정.
        public let category: CommunityResource.Category
        public let content: String
        public let size: Int
        public let downloadURL: URL

        public init(path: String, category: CommunityResource.Category, content: String, size: Int, downloadURL: URL) {
            self.path = path
            self.category = category
            self.content = content
            self.size = size
            self.downloadURL = downloadURL
        }
    }

    /// 리포지토리 메타데이터.
    public struct GitHubRepoMetadata: Sendable, Equatable, Codable {
        public let fullName: String
        public let description: String?
        public let stars: Int
        public let language: String?
        public let topics: [String]
        public let license: String?
        public let updatedAt: Date?

        public init(
            fullName: String,
            description: String?,
            stars: Int,
            language: String?,
            topics: [String],
            license: String?,
            updatedAt: Date?
        ) {
            self.fullName = fullName
            self.description = description
            self.stars = stars
            self.language = language
            self.topics = topics
            self.license = license
            self.updatedAt = updatedAt
        }
    }

    // MARK: - 시도 경로 정의

    /// 기본 크롤 경로 → 카테고리 매핑.
    public static let defaultCrawlPaths: [(path: String, category: CommunityResource.Category)] = [
        ("CLAUDE.md",                          .claudeMd),
        ("AGENTS.md",                          .claudeMd),
        (".cursorrules",                       .rules),
        (".github/copilot-instructions.md",   .rules),
        (".windsurfrules",                     .rules),
        ("README.md",                          .template),
        (".github/CONTRIBUTING.md",           .workflow),
        ("docs/architecture.md",              .architecture),
        ("docs/ARCHITECTURE.md",              .architecture),
        ("DESIGN.md",                          .styleGuide),
        (".claude/CLAUDE.md",                 .claudeMd),
    ]

    // MARK: - 프로퍼티

    private let client: GitHubSearchClient

    // MARK: - 초기화

    public init(client: GitHubSearchClient) {
        self.client = client
    }

    // MARK: - 크롤 메서드

    /// 리포지토리 URL 또는 owner/repo로 관련 파일들을 자동 수집.
    ///
    /// - Parameters:
    ///   - owner: 리포지토리 소유자 (예: "anthropics").
    ///   - repo: 리포지토리 이름 (예: "anthropic-cookbook").
    ///   - branch: 대상 브랜치 (nil이면 "main" 사용).
    ///   - customPaths: 추가 크롤 경로 (기본 경로에 추가).
    /// - Returns: 크롤 결과.
    public func crawlRepository(
        owner: String,
        repo: String,
        branch: String = "main",
        customPaths: [(path: String, category: CommunityResource.Category)] = []
    ) async throws -> CrawlResult {
        let allPaths = Self.defaultCrawlPaths + customPaths
        let attemptedPaths = allPaths.map { $0.path }

        // 메타데이터 조회 (실패해도 계속)
        let metadata = await fetchRepoMetadata(owner: owner, repo: repo)

        // 각 파일 병렬 fetch
        var files: [CrawledFile] = []
        await withTaskGroup(of: CrawledFile?.self) { group in
            for (path, category) in allPaths {
                let rawURLString = "https://raw.githubusercontent.com/\(owner)/\(repo)/\(branch)/\(path)"
                guard let rawURL = URL(string: rawURLString) else { continue }

                group.addTask {
                    do {
                        let content = try await self.client.fetchRawContent(url: rawURL)
                        return CrawledFile(
                            path: path,
                            category: category,
                            content: content,
                            size: content.utf8.count,
                            downloadURL: rawURL
                        )
                    } catch {
                        // 404 / 기타 → skip (nil 반환)
                        return nil
                    }
                }
            }

            for await result in group {
                if let file = result {
                    files.append(file)
                }
            }
        }

        // 경로 순서대로 정렬 (재현성)
        let orderedFiles = files.sorted { lhs, rhs in
            let lhsIdx = attemptedPaths.firstIndex(of: lhs.path) ?? Int.max
            let rhsIdx = attemptedPaths.firstIndex(of: rhs.path) ?? Int.max
            return lhsIdx < rhsIdx
        }

        return CrawlResult(
            owner: owner,
            repo: repo,
            metadata: metadata,
            files: orderedFiles,
            attemptedPaths: attemptedPaths
        )
    }

    // MARK: - 메타데이터 fetch

    /// GitHub Repos API로 메타데이터 조회 (실패 시 nil 반환).
    private func fetchRepoMetadata(owner: String, repo: String) async -> GitHubRepoMetadata? {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)") else { return nil }

        do {
            let content = try await client.fetchRawContent(url: url)
            guard let data = content.data(using: .utf8) else { return nil }
            return try parseRepoMetadata(from: data)
        } catch {
            return nil
        }
    }

    private func parseRepoMetadata(from data: Data) throws -> GitHubRepoMetadata {
        struct RepoAPIResponse: Decodable {
            let fullName: String
            let description: String?
            let stargazersCount: Int
            let language: String?
            let topics: [String]?
            let license: LicenseInfo?
            let updatedAt: String?

            struct LicenseInfo: Decodable {
                let spdxId: String?
                enum CodingKeys: String, CodingKey {
                    case spdxId = "spdx_id"
                }
            }

            enum CodingKeys: String, CodingKey {
                case fullName = "full_name"
                case description
                case stargazersCount = "stargazers_count"
                case language
                case topics
                case license
                case updatedAt = "updated_at"
            }
        }

        let decoded = try JSONDecoder().decode(RepoAPIResponse.self, from: data)
        let updatedAt = decoded.updatedAt.flatMap { ISO8601DateFormatter().date(from: $0) }

        return GitHubRepoMetadata(
            fullName: decoded.fullName,
            description: decoded.description,
            stars: decoded.stargazersCount,
            language: decoded.language,
            topics: decoded.topics ?? [],
            license: decoded.license?.spdxId,
            updatedAt: updatedAt
        )
    }
}
