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

// MARK: - ADR-118 정렬/필터 로직 Tests

/// GitHubRepoResult 배열에 대한 client-side 정렬/필터 로직을 검증한다.
/// 이 로직은 GitHubSearchSheet.displayedRepoResults 에 구현되어 있으며
/// 순수 함수로 테스트 가능하다.
@Suite("GitHubSearchSheet 정렬/필터 로직 (ADR-118)")
struct GitHubSearchSortFilterTests {

    // MARK: - 테스트 픽스처

    private func makeRepo(
        id: Int,
        fullName: String,
        stars: Int,
        language: String? = nil,
        updatedAt: Date? = nil
    ) -> GitHubSearchClient.GitHubRepoResult {
        GitHubSearchClient.GitHubRepoResult(
            id: id,
            fullName: fullName,
            description: nil,
            stars: stars,
            language: language,
            url: URL(string: "https://github.com/\(fullName)")!,
            defaultBranch: "main",
            updatedAt: updatedAt
        )
    }

    private func sortByStars(_ repos: [GitHubSearchClient.GitHubRepoResult]) -> [GitHubSearchClient.GitHubRepoResult] {
        repos.sorted { $0.stars > $1.stars }
    }

    private func sortByUpdatedAt(_ repos: [GitHubSearchClient.GitHubRepoResult]) -> [GitHubSearchClient.GitHubRepoResult] {
        repos.sorted { lhs, rhs in
            let l = lhs.updatedAt ?? .distantPast
            let r = rhs.updatedAt ?? .distantPast
            return l > r
        }
    }

    private func sortByName(_ repos: [GitHubSearchClient.GitHubRepoResult]) -> [GitHubSearchClient.GitHubRepoResult] {
        repos.sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
    }

    private func filterByLanguage(_ repos: [GitHubSearchClient.GitHubRepoResult], language: String) -> [GitHubSearchClient.GitHubRepoResult] {
        repos.filter { $0.language == language }
    }

    // MARK: - 정렬 — 스타 내림차순

    @Test("스타 많은 순 정렬 — 가장 스타 많은 리포가 첫 번째")
    func sortByStarsDescending() {
        let repos = [
            makeRepo(id: 1, fullName: "a/low", stars: 100),
            makeRepo(id: 2, fullName: "b/high", stars: 9999),
            makeRepo(id: 3, fullName: "c/mid", stars: 1234),
        ]
        let sorted = sortByStars(repos)
        #expect(sorted[0].stars == 9999)
        #expect(sorted[1].stars == 1234)
        #expect(sorted[2].stars == 100)
    }

    // MARK: - 정렬 — 갱신일 내림차순

    @Test("최근 갱신순 정렬 — 가장 최근 리포가 첫 번째")
    func sortByUpdatedAtDescending() {
        let now = Date()
        let repos = [
            makeRepo(id: 1, fullName: "a/old", stars: 0, updatedAt: now.addingTimeInterval(-86400 * 30)),
            makeRepo(id: 2, fullName: "b/recent", stars: 0, updatedAt: now.addingTimeInterval(-3600)),
            makeRepo(id: 3, fullName: "c/medium", stars: 0, updatedAt: now.addingTimeInterval(-86400 * 7)),
        ]
        let sorted = sortByUpdatedAt(repos)
        #expect(sorted[0].fullName == "b/recent")
        #expect(sorted[1].fullName == "c/medium")
        #expect(sorted[2].fullName == "a/old")
    }

    @Test("최근 갱신순 정렬 — updatedAt nil인 리포는 맨 끝")
    func sortByUpdatedAtNilLast() {
        let now = Date()
        let repos = [
            makeRepo(id: 1, fullName: "a/nil", stars: 5000, updatedAt: nil),
            makeRepo(id: 2, fullName: "b/recent", stars: 10, updatedAt: now.addingTimeInterval(-60)),
        ]
        let sorted = sortByUpdatedAt(repos)
        #expect(sorted[0].fullName == "b/recent")
        #expect(sorted[1].fullName == "a/nil")
    }

    // MARK: - 정렬 — 이름 알파벳순

    @Test("이름순 정렬 — 알파벳 오름차순")
    func sortByNameAscending() {
        let repos = [
            makeRepo(id: 1, fullName: "zebra/repo", stars: 1000),
            makeRepo(id: 2, fullName: "alpha/repo", stars: 0),
            makeRepo(id: 3, fullName: "mango/repo", stars: 500),
        ]
        let sorted = sortByName(repos)
        #expect(sorted[0].fullName == "alpha/repo")
        #expect(sorted[1].fullName == "mango/repo")
        #expect(sorted[2].fullName == "zebra/repo")
    }

    // MARK: - 언어 필터

    @Test("언어 필터 — Swift만 선택 시 Swift 리포만 반환")
    func filterSwiftOnly() {
        let repos = [
            makeRepo(id: 1, fullName: "a/swift", stars: 100, language: "Swift"),
            makeRepo(id: 2, fullName: "b/python", stars: 200, language: "Python"),
            makeRepo(id: 3, fullName: "c/swift2", stars: 50, language: "Swift"),
            makeRepo(id: 4, fullName: "d/ts", stars: 300, language: "TypeScript"),
        ]
        let filtered = filterByLanguage(repos, language: "Swift")
        #expect(filtered.count == 2)
        #expect(filtered.allSatisfy { $0.language == "Swift" })
    }

    @Test("언어 필터 — 해당 언어 없을 때 빈 배열 반환")
    func filterEmptyResult() {
        let repos = [
            makeRepo(id: 1, fullName: "a/python", stars: 100, language: "Python"),
            makeRepo(id: 2, fullName: "b/go", stars: 200, language: "Go"),
        ]
        let filtered = filterByLanguage(repos, language: "Rust")
        #expect(filtered.isEmpty)
    }
}
