import Foundation
import Testing
@testable import YuminaiCore

@Suite("SmartFilter (ADR-079 Phase 1)")
struct SmartFilterTests {

    @Test("기본 init — 빈 tagIds + nil folder + accent 색상")
    func defaultInit() {
        let filter = SmartFilter(name: "긴급 작업")
        #expect(filter.name == "긴급 작업")
        #expect(filter.tagIds.isEmpty)
        #expect(filter.folderId == nil)
        #expect(filter.iconName == "line.3.horizontal.decrease.circle")
        #expect(filter.colorName == "accent")
    }

    @Test("Codable round trip with tags + folder")
    func roundTrip() throws {
        let folderId = UUID()
        let tag1 = UUID()
        let tag2 = UUID()
        let original = SmartFilter(
            name: "iOS + 긴급",
            tagIds: [tag1, tag2],
            folderId: folderId,
            iconName: "star.fill",
            colorName: "orange"
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SmartFilter.self, from: encoded)
        #expect(decoded == original)
    }

    @Test("backward-compat — colorName/iconName 없을 때 default")
    func backwardCompat() throws {
        let oldJSON = """
        {
            "id": "12345678-1234-1234-1234-123456789012",
            "name": "old",
            "tagIds": []
        }
        """.data(using: .utf8)!
        let filter = try JSONDecoder().decode(SmartFilter.self, from: oldJSON)
        #expect(filter.colorName == "accent")
        #expect(filter.iconName == "line.3.horizontal.decrease.circle")
    }
}

@Suite("DirtyStats + AutoCommitMessageGenerator (ADR-079 Phase 4-5)")
struct GitDirtyStatsTests {

    @Test("isEmpty — 모든 카운트 0이면 true")
    func emptyStats() {
        let stats = DirtyStats(modified: 0, added: 0, deleted: 0, untracked: 0)
        #expect(stats.isEmpty == true)
        #expect(stats.total == 0)
        #expect(stats.summary == "변경 없음")
    }

    @Test("modified만 있을 때 summary")
    func onlyModified() {
        let stats = DirtyStats(modified: 5, added: 0, deleted: 0, untracked: 0)
        #expect(stats.summary == "수정 5")
        #expect(stats.total == 5)
    }

    @Test("혼합 — 수정 + 추가 + 추적 안 됨")
    func mixedStats() {
        let stats = DirtyStats(modified: 3, added: 1, deleted: 0, untracked: 2)
        #expect(stats.summary.contains("수정 3"))
        #expect(stats.summary.contains("추가 1"))
        #expect(stats.summary.contains("추적 안 됨 2"))
        #expect(stats.total == 6)
    }

    @Test("AutoCommit — 단일 추가만")
    func autoCommitFeat() {
        let stats = DirtyStats(modified: 0, added: 3, deleted: 0, untracked: 0)
        let msg = AutoCommitMessageGenerator.generate(stats: stats)
        #expect(msg.hasPrefix("feat:"))
        #expect(msg.contains("3"))
    }

    @Test("AutoCommit — 단일 수정만")
    func autoCommitFix() {
        let stats = DirtyStats(modified: 2, added: 0, deleted: 0, untracked: 0)
        let msg = AutoCommitMessageGenerator.generate(stats: stats)
        #expect(msg.hasPrefix("fix:"))
        #expect(msg.contains("2"))
    }

    @Test("AutoCommit — 단일 삭제만")
    func autoCommitDelete() {
        let stats = DirtyStats(modified: 0, added: 0, deleted: 1, untracked: 0)
        let msg = AutoCommitMessageGenerator.generate(stats: stats)
        #expect(msg.hasPrefix("chore:"))
        #expect(msg.contains("삭제"))
    }

    @Test("AutoCommit — 혼합은 chore prefix")
    func autoCommitMixed() {
        let stats = DirtyStats(modified: 2, added: 1, deleted: 0, untracked: 1)
        let msg = AutoCommitMessageGenerator.generate(stats: stats)
        #expect(msg.hasPrefix("chore:"))
    }

    @Test("AutoCommit — 빈 stats")
    func autoCommitEmpty() {
        let stats = DirtyStats(modified: 0, added: 0, deleted: 0, untracked: 0)
        let msg = AutoCommitMessageGenerator.generate(stats: stats)
        #expect(msg.contains("no changes"))
    }
}

@Suite("BranchInfo + CommitInfo (ADR-079 Phase 4)")
struct GitBranchInfoTests {

    @Test("BranchInfo Identifiable — id == name")
    func branchIdentifiable() {
        let branch = BranchInfo(name: "main", lastCommitRelative: "방금 전", isCurrent: true)
        #expect(branch.id == "main")
    }

    @Test("CommitInfo Identifiable — id == shortSha")
    func commitIdentifiable() {
        let commit = CommitInfo(shortSha: "abc123", message: "test", relativeDate: "1 hour ago", authorName: "John")
        #expect(commit.id == "abc123")
    }
}

@Suite("AppPreferences ADR-079 fields")
struct AppPreferencesADR079Tests {

    @Test("default — smartFilters 빈 배열, iCloudSync false")
    func defaults() {
        let prefs = AppPreferences()
        #expect(prefs.smartFilters.isEmpty)
        #expect(prefs.iCloudSyncEnabled == false)
    }

    @Test("backward-compat — ADR-079 필드 없을 때 default")
    func backwardCompat() throws {
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
        #expect(prefs.smartFilters.isEmpty)
        #expect(prefs.iCloudSyncEnabled == false)
    }

    @Test("round-trip — smartFilters 보존")
    func roundTripSmartFilters() throws {
        var prefs = AppPreferences()
        prefs.smartFilters = [
            SmartFilter(name: "긴급"),
            SmartFilter(name: "iOS + 긴급", tagIds: [UUID(), UUID()], colorName: "red")
        ]
        prefs.iCloudSyncEnabled = true
        let encoded = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: encoded)
        #expect(decoded.smartFilters.count == 2)
        #expect(decoded.iCloudSyncEnabled == true)
    }
}
