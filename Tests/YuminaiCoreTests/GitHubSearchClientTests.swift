import Foundation
import Testing
@testable import YuminaiCore

// MARK: - Mock URLSession

/// 테스트용 mock URLSession — 미리 설정한 응답을 반환.
final class MockGitHubSession: GitHubSearchClient.URLSessionProtocol, @unchecked Sendable {
    var responseData: Data = Data()
    var responseStatus: Int = 200
    var responseHeaders: [String: String] = [:]
    var shouldThrow: Error? = nil

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let error = shouldThrow {
            throw error
        }

        let url = request.url ?? URL(string: "https://api.github.com")!
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

// MARK: - 테스트용 JSON 헬퍼

private func repoSearchJSON(items: [[String: Any]] = []) -> Data {
    let json: [String: Any] = [
        "total_count": items.count,
        "incomplete_results": false,
        "items": items
    ]
    return try! JSONSerialization.data(withJSONObject: json)
}

private func sampleRepoItem(
    id: Int = 1,
    fullName: String = "anthropics/anthropic-cookbook",
    description: String? = "Anthropic 공식 쿡북",
    stars: Int = 12000,
    language: String? = "Python",
    htmlUrl: String = "https://github.com/anthropics/anthropic-cookbook",
    defaultBranch: String = "main"
) -> [String: Any] {
    var item: [String: Any] = [
        "id": id,
        "full_name": fullName,
        "stargazers_count": stars,
        "html_url": htmlUrl,
        "default_branch": defaultBranch
    ]
    if let description { item["description"] = description }
    if let language { item["language"] = language }
    return item
}

private func codeSearchJSON(items: [[String: Any]] = []) -> Data {
    let json: [String: Any] = [
        "total_count": items.count,
        "incomplete_results": false,
        "items": items
    ]
    return try! JSONSerialization.data(withJSONObject: json)
}

private func sampleCodeItem(
    path: String = "CLAUDE.md",
    url: String = "https://api.github.com/repos/test/repo/contents/CLAUDE.md",
    htmlUrl: String = "https://github.com/test/repo/blob/main/CLAUDE.md",
    repoFullName: String = "test/repo",
    repoStars: Int = 500
) -> [String: Any] {
    [
        "path": path,
        "url": url,
        "html_url": htmlUrl,
        "repository": [
            "full_name": repoFullName,
            "stargazers_count": repoStars,
            "default_branch": "main"
        ]
    ]
}

// MARK: - GitHubSearchClient Tests

@Suite("GitHubSearchClient (ADR-116)")
struct GitHubSearchClientTests {

    // MARK: - 리포지토리 검색 — 성공

    @Test("searchRepositories — 정상 응답 파싱")
    func searchRepositoriesSuccess() async throws {
        let session = MockGitHubSession()
        session.responseData = repoSearchJSON(items: [
            sampleRepoItem(id: 1, fullName: "anthropics/anthropic-cookbook", stars: 12000),
            sampleRepoItem(id: 2, fullName: "example/repo", stars: 500, language: nil, defaultBranch: "trunk")
        ])

        let client = GitHubSearchClient(session: session)
        let results = try await client.searchRepositories(query: "claude.md")

        #expect(results.count == 2)
        #expect(results[0].fullName == "anthropics/anthropic-cookbook")
        #expect(results[0].stars == 12000)
        #expect(results[0].defaultBranch == "main")
        #expect(results[1].defaultBranch == "trunk")
    }

    @Test("searchRepositories — 빈 결과 처리")
    func searchRepositoriesEmpty() async throws {
        let session = MockGitHubSession()
        session.responseData = repoSearchJSON(items: [])

        let client = GitHubSearchClient(session: session)
        let results = try await client.searchRepositories(query: "nonexistent-xyzzy-99999")

        #expect(results.isEmpty)
    }

    @Test("searchRepositories — rawURL(for:) 헬퍼 동작 확인")
    func rawURLHelper() async throws {
        let session = MockGitHubSession()
        session.responseData = repoSearchJSON(items: [
            sampleRepoItem(id: 1, fullName: "owner/myrepo", defaultBranch: "main")
        ])

        let client = GitHubSearchClient(session: session)
        let results = try await client.searchRepositories(query: "test")

        let rawURL = results[0].rawURL(for: "CLAUDE.md")
        #expect(rawURL?.absoluteString == "https://raw.githubusercontent.com/owner/myrepo/main/CLAUDE.md")
    }

    // MARK: - 코드 검색 — 성공

    @Test("searchCode — 정상 응답 파싱")
    func searchCodeSuccess() async throws {
        let session = MockGitHubSession()
        session.responseData = codeSearchJSON(items: [
            sampleCodeItem(
                path: "CLAUDE.md",
                url: "https://api.github.com/repos/test/repo/contents/CLAUDE.md",
                htmlUrl: "https://github.com/test/repo/blob/main/CLAUDE.md",
                repoFullName: "test/repo",
                repoStars: 999
            )
        ])

        let client = GitHubSearchClient(session: session)
        let results = try await client.searchCode(query: "filename:CLAUDE.md swift")

        #expect(results.count == 1)
        #expect(results[0].path == "CLAUDE.md")
        #expect(results[0].repoFullName == "test/repo")
        #expect(results[0].stars == 999)
        #expect(results[0].id == "test/repo/CLAUDE.md")
    }

    // MARK: - Rate limit

    @Test("searchRepositories — 429 rate limit 에러")
    func rateLimitError() async throws {
        let session = MockGitHubSession()
        session.responseStatus = 429
        session.responseData = Data("{\"message\":\"rate limit exceeded\"}".utf8)
        // reset at 한 시간 후
        let resetTimestamp = Int(Date().timeIntervalSince1970) + 3600
        session.responseHeaders["X-RateLimit-Reset"] = "\(resetTimestamp)"

        let client = GitHubSearchClient(session: session)

        do {
            _ = try await client.searchRepositories(query: "test")
            Issue.record("Expected rateLimited error")
        } catch let error as GitHubSearchClient.SearchError {
            if case .rateLimited(let resetAt) = error {
                #expect(resetAt != nil)
            } else {
                Issue.record("Expected rateLimited, got \(error)")
            }
        }
    }

    @Test("searchRepositories — 403 forbidden rate limit 에러")
    func forbiddenRateLimitError() async throws {
        let session = MockGitHubSession()
        session.responseStatus = 403
        session.responseData = Data("{\"message\":\"API rate limit exceeded\"}".utf8)

        let client = GitHubSearchClient(session: session)

        do {
            _ = try await client.searchRepositories(query: "test")
            Issue.record("Expected rateLimited error")
        } catch let error as GitHubSearchClient.SearchError {
            if case .rateLimited = error {
                // 정상
            } else {
                Issue.record("Expected rateLimited, got \(error)")
            }
        }
    }

    // MARK: - 네트워크 오류

    @Test("searchRepositories — URLError 네트워크 오류")
    func networkError() async throws {
        let session = MockGitHubSession()
        session.shouldThrow = URLError(.notConnectedToInternet)

        let client = GitHubSearchClient(session: session)

        do {
            _ = try await client.searchRepositories(query: "test")
            Issue.record("Expected networkError")
        } catch let error as GitHubSearchClient.SearchError {
            if case .networkError = error {
                // 정상
            } else {
                Issue.record("Expected networkError, got \(error)")
            }
        }
    }

    // MARK: - 잘못된 응답

    @Test("searchRepositories — 잘못된 JSON 파싱 오류")
    func invalidJSON() async throws {
        let session = MockGitHubSession()
        session.responseData = Data("not json at all".utf8)

        let client = GitHubSearchClient(session: session)

        do {
            _ = try await client.searchRepositories(query: "test")
            Issue.record("Expected invalidResponse error")
        } catch let error as GitHubSearchClient.SearchError {
            if case .invalidResponse = error {
                // 정상
            } else {
                Issue.record("Expected invalidResponse, got \(error)")
            }
        }
    }

    // MARK: - starsDisplay

    @Test("starsDisplay — 1000 미만은 그대로")
    func starsDisplayUnderThousand() async throws {
        let session = MockGitHubSession()
        session.responseData = repoSearchJSON(items: [
            sampleRepoItem(id: 1, stars: 999)
        ])

        let client = GitHubSearchClient(session: session)
        let results = try await client.searchRepositories(query: "test")

        #expect(results[0].starsDisplay == "999")
    }

    @Test("starsDisplay — 10000 이상은 Xk 형식")
    func starsDisplayTenK() async throws {
        let session = MockGitHubSession()
        session.responseData = repoSearchJSON(items: [
            sampleRepoItem(id: 1, stars: 12345)
        ])

        let client = GitHubSearchClient(session: session)
        let results = try await client.searchRepositories(query: "test")

        #expect(results[0].starsDisplay == "12k")
    }

    @Test("starsDisplay — 1000~9999는 X.Xk 형식")
    func starsDisplayOneToNineK() async throws {
        let session = MockGitHubSession()
        session.responseData = repoSearchJSON(items: [
            sampleRepoItem(id: 1, stars: 1500)
        ])

        let client = GitHubSearchClient(session: session)
        let results = try await client.searchRepositories(query: "test")

        #expect(results[0].starsDisplay == "1.5k")
    }

    // MARK: - HTTP 오류

    @Test("searchRepositories — 401 HTTP 오류")
    func httpError401() async throws {
        let session = MockGitHubSession()
        session.responseStatus = 401
        session.responseData = Data("{\"message\":\"Bad credentials\"}".utf8)

        let client = GitHubSearchClient(session: session)

        do {
            _ = try await client.searchRepositories(query: "test")
            Issue.record("Expected httpError")
        } catch let error as GitHubSearchClient.SearchError {
            if case .httpError(let code) = error {
                #expect(code == 401)
            } else {
                Issue.record("Expected httpError(401), got \(error)")
            }
        }
    }
}
