import Foundation
import Testing
@testable import YuminaiCore

/// **ADR-122 Phase 5** — GitHubSearchHistoryEntry + GitHubSearchFavorite TDD.
@Suite("GitHubSearchHistory (ADR-122)")
struct GitHubSearchHistoryTests {

    // MARK: - GitHubSearchHistoryEntry

    @Test("GitHubSearchHistoryEntry — 기본 생성 및 필드 확인")
    func entryCreation() {
        let entry = GitHubSearchHistoryEntry(
            query: "claude.md swift",
            mode: .repositories,
            resultCount: 42
        )
        #expect(entry.query == "claude.md swift")
        #expect(entry.mode == .repositories)
        #expect(entry.resultCount == 42)
        #expect(entry.id != UUID())  // 고유 ID 생성됨 (항상 다름)
    }

    @Test("GitHubSearchHistoryEntry — Codable round-trip")
    func entryRoundTrip() throws {
        let original = GitHubSearchHistoryEntry(
            id: UUID(),
            query: "test query",
            mode: .code,
            resultCount: 10,
            searchedAt: Date(timeIntervalSince1970: 1700000000)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GitHubSearchHistoryEntry.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.query == original.query)
        #expect(decoded.mode == original.mode)
        #expect(decoded.resultCount == original.resultCount)
    }

    @Test("GitHubSearchHistoryEntry.Mode — Codable")
    func modeCodable() throws {
        let repoData = try JSONEncoder().encode(GitHubSearchHistoryEntry.Mode.repositories)
        let decoded = try JSONDecoder().decode(GitHubSearchHistoryEntry.Mode.self, from: repoData)
        #expect(decoded == .repositories)
    }

    // MARK: - GitHubSearchFavorite

    @Test("GitHubSearchFavorite — 기본 생성")
    func favoriteCreation() {
        let fav = GitHubSearchFavorite(
            query: "filename:CLAUDE.md",
            mode: .code,
            label: "CLAUDE.md 파일 검색"
        )
        #expect(fav.query == "filename:CLAUDE.md")
        #expect(fav.mode == .code)
        #expect(fav.label == "CLAUDE.md 파일 검색")
    }

    @Test("GitHubSearchFavorite — Codable round-trip")
    func favoriteRoundTrip() throws {
        let original = GitHubSearchFavorite(
            id: UUID(),
            query: "swift tdd",
            mode: .repositories,
            label: "Swift TDD 리포",
            savedAt: Date(timeIntervalSince1970: 1700000000)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GitHubSearchFavorite.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.query == original.query)
        #expect(decoded.label == original.label)
    }

    // MARK: - GitHubSearchHistoryBuffer

    @Test("append — 새 항목 맨 앞에 삽입")
    func appendPrependsBefore() {
        let existing = [
            GitHubSearchHistoryEntry(query: "old", mode: .repositories, resultCount: 5)
        ]
        let newEntry = GitHubSearchHistoryEntry(query: "new", mode: .code, resultCount: 3)
        let result = GitHubSearchHistoryBuffer.append(newEntry, to: existing)

        #expect(result.first?.query == "new")
        #expect(result.count == 2)
    }

    @Test("append — 중복 query+mode는 제거 후 최신으로 교체")
    func appendDeduplicates() {
        let old = GitHubSearchHistoryEntry(
            id: UUID(),
            query: "claude",
            mode: .repositories,
            resultCount: 5,
            searchedAt: Date().addingTimeInterval(-100)
        )
        let newer = GitHubSearchHistoryEntry(
            id: UUID(),
            query: "claude",
            mode: .repositories,
            resultCount: 10,
            searchedAt: Date()
        )
        let result = GitHubSearchHistoryBuffer.append(newer, to: [old])

        #expect(result.count == 1)
        #expect(result[0].resultCount == 10)  // 최신 것으로 교체
    }

    @Test("append — capacity 초과 시 오래된 항목 제거")
    func appendRingBuffer() {
        var history: [GitHubSearchHistoryEntry] = []
        for i in 0..<5 {
            let entry = GitHubSearchHistoryEntry(query: "q\(i)", mode: .repositories, resultCount: i)
            history = GitHubSearchHistoryBuffer.append(entry, to: history, capacity: 3)
        }

        #expect(history.count == 3)
        // 가장 최신 항목이 앞에
        #expect(history[0].query == "q4")
    }

    @Test("append — 빈 히스토리에 추가")
    func appendToEmpty() {
        let entry = GitHubSearchHistoryEntry(query: "first", mode: .code, resultCount: 0)
        let result = GitHubSearchHistoryBuffer.append(entry, to: [])

        #expect(result.count == 1)
        #expect(result[0].query == "first")
    }

    @Test("AppPreferences — githubSearchHistory 기본값은 빈 배열")
    func preferencesDefaultHistory() {
        let prefs = AppPreferences()
        #expect(prefs.githubSearchHistory.isEmpty)
    }

    @Test("AppPreferences — githubSearchFavorites 기본값은 빈 배열")
    func preferencesDefaultFavorites() {
        let prefs = AppPreferences()
        #expect(prefs.githubSearchFavorites.isEmpty)
    }

    @Test("AppPreferences — 기존 JSON에 필드 없으면 빈 배열 (backward-compat)")
    func backwardCompatDecode() throws {
        let oldJSON = """
        {
            "claudeBinaryPath": "/usr/local/bin/claude",
            "codexBinaryPath": "/usr/local/bin/codex",
            "telegramEnabled": false,
            "telegramAllowedUserIds": [],
            "fontSizeOffset": 0,
            "showInspectorByDefault": false
        }
        """.data(using: .utf8)!

        let prefs = try JSONDecoder().decode(AppPreferences.self, from: oldJSON)
        #expect(prefs.githubSearchHistory.isEmpty)
        #expect(prefs.githubSearchFavorites.isEmpty)
    }
}
