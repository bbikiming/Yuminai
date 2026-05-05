import Foundation
import Testing
@testable import YuminaiCore

/// **ADR-122 Phase 5** — GitHubSearchCache TDD.
@Suite("GitHubSearchCache (ADR-122)")
struct GitHubSearchCacheTests {

    // MARK: - 픽스처

    private func makeRepoResult(id: Int = 1) -> GitHubSearchClient.GitHubRepoResult {
        GitHubSearchClient.GitHubRepoResult(
            id: id,
            fullName: "owner/repo-\(id)",
            description: nil,
            stars: 100,
            language: "Swift",
            url: URL(string: "https://github.com/owner/repo-\(id)")!,
            defaultBranch: "main"
        )
    }

    private func makeKey(
        endpoint: String = "repositories",
        query: String = "test",
        perPage: Int = 30,
        page: Int = 1
    ) -> GitHubSearchCache.CacheKey {
        GitHubSearchCache.CacheKey(endpoint: endpoint, query: query, perPage: perPage, page: page)
    }

    // MARK: - 기본 get/set

    @Test("set 후 get — 동일 키로 즉시 조회 성공")
    func setThenGet() async {
        let cache = GitHubSearchCache()
        let key = makeKey()
        let repo = makeRepoResult()
        await cache.set(key, value: .repositories([repo]))

        let result = await cache.get(key)
        guard case .repositories(let repos) = result else {
            Issue.record("Expected .repositories")
            return
        }
        #expect(repos.count == 1)
        #expect(repos[0].fullName == "owner/repo-1")
    }

    @Test("없는 키 get → nil")
    func getMissingKey() async {
        let cache = GitHubSearchCache()
        let result = await cache.get(makeKey(query: "nonexistent"))
        #expect(result == nil)
    }

    @Test("다른 키는 서로 독립")
    func differentKeysIndependent() async {
        let cache = GitHubSearchCache()
        let key1 = makeKey(query: "swift")
        let key2 = makeKey(query: "python")

        let repo1 = makeRepoResult(id: 1)
        let repo2 = makeRepoResult(id: 2)

        await cache.set(key1, value: .repositories([repo1]))
        await cache.set(key2, value: .repositories([repo2]))

        let r1 = await cache.get(key1)
        let r2 = await cache.get(key2)

        guard case .repositories(let repos1) = r1 else {
            Issue.record("Expected repos1")
            return
        }
        guard case .repositories(let repos2) = r2 else {
            Issue.record("Expected repos2")
            return
        }
        #expect(repos1[0].id == 1)
        #expect(repos2[0].id == 2)
    }

    // MARK: - 만료 (TTL)

    @Test("만료된 엔트리 get → nil")
    func expiredEntryReturnsNil() async {
        let cache = GitHubSearchCache(ttl: 0.05)  // 50ms
        let key = makeKey()
        await cache.set(key, value: .repositories([makeRepoResult()]))

        try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms

        let result = await cache.get(key)
        #expect(result == nil)
    }

    @Test("만료 전 get → 정상 반환")
    func notExpiredReturnsValue() async {
        let cache = GitHubSearchCache(ttl: 300)  // 5분
        let key = makeKey()
        await cache.set(key, value: .repositories([makeRepoResult()]))

        let result = await cache.get(key)
        #expect(result != nil)
    }

    // MARK: - clear

    @Test("clear 후 모든 엔트리 삭제")
    func clearAllEntries() async {
        let cache = GitHubSearchCache()
        await cache.set(makeKey(query: "a"), value: .repositories([makeRepoResult(id: 1)]))
        await cache.set(makeKey(query: "b"), value: .repositories([makeRepoResult(id: 2)]))

        await cache.clear()

        let count = await cache.count()
        #expect(count == 0)
    }

    // MARK: - gc (garbage collection)

    @Test("gc — 만료 엔트리 제거")
    func gcRemovesExpired() async {
        let cache = GitHubSearchCache(ttl: 0.05)
        await cache.set(makeKey(query: "expired"), value: .repositories([makeRepoResult()]))

        try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms

        let countBefore = await cache.count()
        await cache.gc()
        let countAfter = await cache.count()

        #expect(countBefore >= 1)
        #expect(countAfter < countBefore || countAfter == 0)
    }

    @Test("gc — capacity 초과 시 오래된 항목 제거")
    func gcEnforcesCapacity() async {
        let cache = GitHubSearchCache(ttl: 300, capacity: 3)

        for i in 0..<5 {
            await cache.set(makeKey(query: "q\(i)"), value: .repositories([makeRepoResult(id: i)]))
        }

        await cache.gc()
        let count = await cache.count()
        #expect(count <= 3)
    }

    // MARK: - capacity 자동 gc

    @Test("capacity 초과 시 set에서 자동 gc")
    func autoGCOnCapacityExceed() async {
        let cache = GitHubSearchCache(ttl: 300, capacity: 2)

        for i in 0..<4 {
            await cache.set(makeKey(query: "q\(i)"), value: .repositories([makeRepoResult(id: i)]))
        }

        let count = await cache.count()
        #expect(count <= 3)  // gc가 capacity 기준으로 정리
    }

    // MARK: - count

    @Test("count — 엔트리 수 정확")
    func countAccuracy() async {
        let cache = GitHubSearchCache()
        #expect(await cache.count() == 0)

        await cache.set(makeKey(query: "a"), value: .repositories([makeRepoResult()]))
        #expect(await cache.count() == 1)

        await cache.set(makeKey(query: "b"), value: .code([]))
        #expect(await cache.count() == 2)
    }
}
