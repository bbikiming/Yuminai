import Foundation
import Testing
@testable import YuminaiCore

// MARK: - Mock URLSession for Crawler

/// 경로별로 다른 응답을 반환하는 크롤러 전용 Mock.
final class MockCrawlerSession: GitHubSearchClient.URLSessionProtocol, @unchecked Sendable {
    /// path → (statusCode, bodyString) 매핑.
    var responses: [String: (Int, String)] = [:]
    /// 기본 응답 (매핑에 없는 URL).
    var defaultStatus: Int = 404

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let urlStr = request.url?.absoluteString ?? ""

        // 경로 매칭: URL에 해당 path가 포함되는지 확인
        let matched = responses.first { urlStr.contains($0.key) }
        let (status, body) = matched?.value ?? (defaultStatus, "")

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/plain"]
        )!

        return (Data(body.utf8), response)
    }
}

// MARK: - GitHubCrawler Tests

/// **ADR-122 Phase 5** — GitHubCrawler TDD.
@Suite("GitHubCrawler (ADR-122)")
struct GitHubCrawlerTests {

    // MARK: - 모든 파일 존재

    @Test("모든 시도 경로가 200 → 모두 수집")
    func allFilesExist() async throws {
        let session = MockCrawlerSession()
        session.responses = [
            "CLAUDE.md": (200, "# CLAUDE\nThis is CLAUDE.md"),
            "AGENTS.md": (200, "# AGENTS"),
            ".cursorrules": (200, "use typescript"),
            "README.md": (200, "# README"),
        ]

        let client = GitHubSearchClient(session: session, retryPolicy: .fast, cache: nil)
        let crawler = GitHubCrawler(client: client)
        let result = try await crawler.crawlRepository(owner: "test", repo: "repo")

        #expect(result.owner == "test")
        #expect(result.repo == "repo")
        #expect(result.files.count >= 4)
        #expect(result.attemptedPaths.count == GitHubCrawler.defaultCrawlPaths.count)
    }

    // MARK: - 일부만 존재

    @Test("일부 경로 404 → 해당만 수집")
    func someFilesExist() async throws {
        let session = MockCrawlerSession()
        // ".cursorrules" suffix 매칭 (포함 검색이므로 고유 suffix 사용)
        session.responses = [
            ".cursorrules": (200, "some rules"),
            "docs/architecture.md": (200, "## Architecture"),
        ]
        session.defaultStatus = 404

        let client = GitHubSearchClient(session: session, retryPolicy: .fast, cache: nil)
        let crawler = GitHubCrawler(client: client)
        let result = try await crawler.crawlRepository(owner: "owner", repo: "repo")

        #expect(result.files.count == 2)
        let paths = result.files.map { $0.path }
        #expect(paths.contains(".cursorrules"))
        #expect(paths.contains("docs/architecture.md"))
    }

    // MARK: - 모두 404

    @Test("모든 경로 404 → 빈 결과 + attemptedPaths 채워짐")
    func allFiles404() async throws {
        let session = MockCrawlerSession()
        session.defaultStatus = 404

        let client = GitHubSearchClient(session: session, retryPolicy: .fast, cache: nil)
        let crawler = GitHubCrawler(client: client)
        let result = try await crawler.crawlRepository(owner: "empty", repo: "repo")

        #expect(result.files.isEmpty)
        #expect(!result.attemptedPaths.isEmpty)
        #expect(result.attemptedPaths.count == GitHubCrawler.defaultCrawlPaths.count)
    }

    // MARK: - 카테고리 추정

    @Test("CLAUDE.md → .claudeMd 카테고리")
    func claudeMdCategory() async throws {
        let session = MockCrawlerSession()
        session.responses["CLAUDE.md"] = (200, "# AI Instructions")
        session.defaultStatus = 404

        let client = GitHubSearchClient(session: session, retryPolicy: .fast, cache: nil)
        let crawler = GitHubCrawler(client: client)
        let result = try await crawler.crawlRepository(owner: "x", repo: "y")

        let claudeFile = result.files.first { $0.path == "CLAUDE.md" }
        #expect(claudeFile?.category == .claudeMd)
    }

    @Test(".cursorrules → .rules 카테고리")
    func cursorRulesCategory() async throws {
        let session = MockCrawlerSession()
        session.responses[".cursorrules"] = (200, "rules content")
        session.defaultStatus = 404

        let client = GitHubSearchClient(session: session, retryPolicy: .fast, cache: nil)
        let crawler = GitHubCrawler(client: client)
        let result = try await crawler.crawlRepository(owner: "x", repo: "y")

        let rulesFile = result.files.first { $0.path == ".cursorrules" }
        #expect(rulesFile?.category == .rules)
    }

    @Test("README.md → .template 카테고리")
    func readmeCategory() async throws {
        let session = MockCrawlerSession()
        session.responses["README.md"] = (200, "# README")
        session.defaultStatus = 404

        let client = GitHubSearchClient(session: session, retryPolicy: .fast, cache: nil)
        let crawler = GitHubCrawler(client: client)
        let result = try await crawler.crawlRepository(owner: "x", repo: "y")

        let readmeFile = result.files.first { $0.path == "README.md" }
        #expect(readmeFile?.category == .template)
    }

    // MARK: - 파일 내용

    @Test("파일 내용이 정확하게 저장됨")
    func fileContentPreserved() async throws {
        let expectedContent = "# CLAUDE\n\nThis is AI instructions\n\n## Rules\n- Be helpful"
        let session = MockCrawlerSession()
        session.responses["CLAUDE.md"] = (200, expectedContent)
        session.defaultStatus = 404

        let client = GitHubSearchClient(session: session, retryPolicy: .fast, cache: nil)
        let crawler = GitHubCrawler(client: client)
        let result = try await crawler.crawlRepository(owner: "x", repo: "y")

        let file = result.files.first { $0.path == "CLAUDE.md" }
        #expect(file?.content == expectedContent)
        #expect(file?.size == expectedContent.utf8.count)
    }

    // MARK: - crawledAt

    @Test("crawledAt이 현재 시각 근처")
    func crawledAtIsRecent() async throws {
        let session = MockCrawlerSession()
        session.defaultStatus = 404

        let client = GitHubSearchClient(session: session, retryPolicy: .fast, cache: nil)
        let crawler = GitHubCrawler(client: client)

        let before = Date()
        let result = try await crawler.crawlRepository(owner: "x", repo: "y")
        let after = Date()

        #expect(result.crawledAt >= before)
        #expect(result.crawledAt <= after)
    }

    // MARK: - 기본 크롤 경로 검증

    @Test("defaultCrawlPaths — CLAUDE.md 포함")
    func defaultPathsIncludeCLAUDE() {
        let paths = GitHubCrawler.defaultCrawlPaths.map { $0.path }
        #expect(paths.contains("CLAUDE.md"))
    }

    @Test("defaultCrawlPaths — AGENTS.md 포함")
    func defaultPathsIncludeAGENTS() {
        let paths = GitHubCrawler.defaultCrawlPaths.map { $0.path }
        #expect(paths.contains("AGENTS.md"))
    }

    @Test("defaultCrawlPaths — .cursorrules 포함")
    func defaultPathsIncludeCursorRules() {
        let paths = GitHubCrawler.defaultCrawlPaths.map { $0.path }
        #expect(paths.contains(".cursorrules"))
    }

    @Test("defaultCrawlPaths — 중복 없음")
    func defaultPathsNoDuplicates() {
        let paths = GitHubCrawler.defaultCrawlPaths.map { $0.path }
        #expect(Set(paths).count == paths.count)
    }

    // MARK: - 커스텀 경로

    @Test("customPaths 추가 — 기본 경로에 합산")
    func customPathsAddedToDefault() async throws {
        let session = MockCrawlerSession()
        session.responses["custom/file.md"] = (200, "custom content")
        session.defaultStatus = 404

        let client = GitHubSearchClient(session: session, retryPolicy: .fast, cache: nil)
        let crawler = GitHubCrawler(client: client)
        let result = try await crawler.crawlRepository(
            owner: "x",
            repo: "y",
            customPaths: [("custom/file.md", .claudeMd)]
        )

        let totalExpected = GitHubCrawler.defaultCrawlPaths.count + 1
        #expect(result.attemptedPaths.count == totalExpected)

        let customFile = result.files.first { $0.path == "custom/file.md" }
        #expect(customFile != nil)
    }
}
