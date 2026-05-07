import Foundation
import Testing
@testable import YuminaiCore

// MARK: - Mock URLSession

/// 테스트용 mock URLSession — 미리 설정한 응답을 반환.
final class MockGitLabSession: GitLabSearchClient.URLSessionProtocol, @unchecked Sendable {
    var responseData: Data = Data()
    var responseStatus: Int = 200
    var responseHeaders: [String: String] = [:]
    var shouldThrow: Error? = nil

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let error = shouldThrow {
            throw error
        }

        let url = request.url ?? URL(string: "https://gitlab.com")!
        var headerFields: [String: String] = ["Content-Type": "application/json"]
        responseHeaders.forEach { headerFields[$0.key] = $0.value }

        let response = HTTPURLResponse(
            url: url,
            statusCode: responseStatus,
            httpVersion: "HTTP/1.1",
            headerFields: headerFields
        )!

        return (responseData, response)
    }
}

// MARK: - JSON 헬퍼

private func projectSearchJSON(items: [[String: Any]] = [], total: Int = 0) -> Data {
    let jsonItems = items.isEmpty ? [] as [[String: Any]] : items
    return try! JSONSerialization.data(withJSONObject: jsonItems)
}

private func sampleProjectItem(
    id: Int = 1,
    name: String = "yuminai",
    pathWithNamespace: String = "bbikiming/yuminai",
    description: String? = "AI coding agent",
    starCount: Int = 120,
    webUrl: String = "https://gitlab.com/bbikiming/yuminai",
    lastActivityAt: String? = "2026-05-01T00:00:00Z"
) -> [String: Any] {
    var item: [String: Any] = [
        "id": id,
        "name": name,
        "path_with_namespace": pathWithNamespace,
        "star_count": starCount,
        "web_url": webUrl
    ]
    if let description { item["description"] = description }
    if let lastActivityAt { item["last_activity_at"] = lastActivityAt }
    return item
}

private func sampleSnippetItem(
    id: Int = 10,
    title: String = "GitLab CI Swift 템플릿",
    fileName: String = ".gitlab-ci.yml",
    description: String? = "Swift 빌드·테스트 파이프라인",
    webUrl: String = "https://gitlab.com/snippets/10",
    createdAt: String? = "2026-01-01T00:00:00Z"
) -> [String: Any] {
    var item: [String: Any] = [
        "id": id,
        "title": title,
        "file_name": fileName,
        "web_url": webUrl
    ]
    if let description { item["description"] = description }
    if let createdAt { item["created_at"] = createdAt }
    return item
}

// MARK: - 테스트

/// **ADR-133** — GitLabSearchClient 단위 테스트.
@Suite("GitLabSearchClient (ADR-133)")
struct GitLabSearchClientTests {

    // MARK: - 프로젝트 검색

    @Test("프로젝트 검색 — 정상 응답")
    func searchProjectsSuccess() async throws {
        let session = MockGitLabSession()
        session.responseData = projectSearchJSON(
            items: [sampleProjectItem(id: 1, name: "yuminai", starCount: 120)],
            total: 1
        )
        session.responseHeaders["X-Total"] = "1"

        let client = GitLabSearchClient(session: session)
        let page = try await client.searchProjects(query: "yuminai", perPage: 20)

        #expect(page.items.count == 1)
        #expect(page.items[0].name == "yuminai")
        #expect(page.items[0].stars == 120)
        #expect(page.currentPage == 1)
    }

    @Test("프로젝트 검색 — 빈 결과")
    func searchProjectsEmpty() async throws {
        let session = MockGitLabSession()
        session.responseData = projectSearchJSON(items: [], total: 0)
        session.responseHeaders["X-Total"] = "0"

        let client = GitLabSearchClient(session: session)
        let page = try await client.searchProjects(query: "nonexistent-xyz-12345")

        #expect(page.items.isEmpty)
        #expect(page.totalCount == 0)
        #expect(page.hasMore == false)
    }

    @Test("프로젝트 검색 — pathWithNamespace 파싱")
    func searchProjectsPathWithNamespace() async throws {
        let session = MockGitLabSession()
        session.responseData = projectSearchJSON(
            items: [sampleProjectItem(pathWithNamespace: "org/subgroup/project")],
            total: 1
        )
        session.responseHeaders["X-Total"] = "1"

        let client = GitLabSearchClient(session: session)
        let page = try await client.searchProjects(query: "project")

        #expect(page.items[0].pathWithNamespace == "org/subgroup/project")
    }

    @Test("프로젝트 검색 — starsDisplay 변환")
    func projectStarsDisplay() async throws {
        let session = MockGitLabSession()
        session.responseData = projectSearchJSON(
            items: [sampleProjectItem(starCount: 12300)],
            total: 1
        )
        session.responseHeaders["X-Total"] = "1"

        let client = GitLabSearchClient(session: session)
        let page = try await client.searchProjects(query: "test")

        #expect(page.items[0].starsDisplay == "12.3k")
    }

    // MARK: - 스니펫 검색

    @Test("스니펫 검색 — 정상 응답")
    func searchSnippetsSuccess() async throws {
        let session = MockGitLabSession()
        let snippetData = try! JSONSerialization.data(withJSONObject: [
            sampleSnippetItem(id: 10, title: "CI 템플릿", fileName: ".gitlab-ci.yml")
        ])
        session.responseData = snippetData
        session.responseHeaders["X-Total"] = "1"

        let client = GitLabSearchClient(session: session)
        let page = try await client.searchSnippets(query: "ci")

        #expect(page.items.count == 1)
        #expect(page.items[0].title == "CI 템플릿")
        #expect(page.items[0].fileName == ".gitlab-ci.yml")
    }

    // MARK: - 에러 처리

    @Test("401 Unauthorized → SearchError.unauthorized")
    func unauthorizedError() async throws {
        let session = MockGitLabSession()
        session.responseStatus = 401
        session.responseData = "{}".data(using: .utf8)!

        let client = GitLabSearchClient(session: session)
        await #expect(throws: GitLabSearchClient.SearchError.unauthorized) {
            _ = try await client.searchProjects(query: "test")
        }
    }

    @Test("403 Forbidden → SearchError.forbidden")
    func forbiddenError() async throws {
        let session = MockGitLabSession()
        session.responseStatus = 403
        session.responseData = "{}".data(using: .utf8)!

        let client = GitLabSearchClient(session: session)
        await #expect(throws: GitLabSearchClient.SearchError.forbidden) {
            _ = try await client.searchProjects(query: "private-repo")
        }
    }

    @Test("429 Too Many Requests → SearchError.rateLimited")
    func rateLimitedError() async throws {
        let session = MockGitLabSession()
        session.responseStatus = 429
        session.responseData = "{}".data(using: .utf8)!

        let client = GitLabSearchClient(session: session)
        await #expect(throws: GitLabSearchClient.SearchError.rateLimited) {
            _ = try await client.searchProjects(query: "test")
        }
    }

    @Test("URLError → SearchError.networkError")
    func networkError() async throws {
        let session = MockGitLabSession()
        session.shouldThrow = URLError(.notConnectedToInternet)

        let client = GitLabSearchClient(session: session)
        do {
            _ = try await client.searchProjects(query: "test")
            #expect(Bool(false), "에러가 발생해야 함")
        } catch let error as GitLabSearchClient.SearchError {
            if case .networkError = error {
                // 정상 경로
            } else {
                #expect(Bool(false), "networkError여야 하는데 다른 에러: \(error)")
            }
        }
    }

    @Test("취소 → SearchError.cancelled")
    func cancellationError() async throws {
        let session = MockGitLabSession()
        session.shouldThrow = CancellationError()

        let client = GitLabSearchClient(session: session)
        await #expect(throws: GitLabSearchClient.SearchError.cancelled) {
            _ = try await client.searchProjects(query: "test")
        }
    }

    // MARK: - 에러 메시지

    @Test("SearchError.unauthorized.errorDescription 한국어 포함")
    func unauthorizedErrorDescription() {
        let error = GitLabSearchClient.SearchError.unauthorized
        #expect(error.errorDescription?.contains("토큰") == true)
    }

    @Test("SearchError.rateLimited.recoveryHint 한국어 포함")
    func rateLimitedRecoveryHint() {
        let error = GitLabSearchClient.SearchError.rateLimited
        #expect(error.recoveryHint?.contains("PAT") == true)
    }

    // MARK: - 토큰 검증

    @Test("validateToken 성공 — username 반환")
    func validateTokenSuccess() async throws {
        let session = MockGitLabSession()
        let userJSON = #"{"id":1,"username":"bbikiming","name":"Bikiming"}"#
        session.responseData = userJSON.data(using: .utf8)!

        let client = GitLabSearchClient(session: session, token: "glpat-test")
        let username = try await client.validateToken()
        #expect(username == "bbikiming")
    }

    // MARK: - Pagination

    @Test("페이지네이션 hasMore 계산")
    func paginationHasMore() async throws {
        let session = MockGitLabSession()
        let items = (1...20).map { sampleProjectItem(id: $0) }
        session.responseData = projectSearchJSON(items: items, total: 20)
        session.responseHeaders["X-Total"] = "50"

        let client = GitLabSearchClient(session: session)
        let page = try await client.searchProjects(query: "test", perPage: 20, page: 1)

        // 20 * 1 = 20 < 50 → hasMore = true
        #expect(page.hasMore == true)
    }

    @Test("마지막 페이지 hasMore = false")
    func paginationLastPage() async throws {
        let session = MockGitLabSession()
        let items = (1...5).map { sampleProjectItem(id: $0) }
        session.responseData = projectSearchJSON(items: items, total: 5)
        session.responseHeaders["X-Total"] = "20"

        let client = GitLabSearchClient(session: session)
        // page=2, perPage=20 → 20*2=40 > 20 → hasMore = false
        let page = try await client.searchProjects(query: "test", perPage: 20, page: 2)

        #expect(page.hasMore == false)
    }
}
