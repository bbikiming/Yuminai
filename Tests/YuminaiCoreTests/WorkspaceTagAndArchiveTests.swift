import Foundation
import Testing
@testable import YuminaiCore

@Suite("WorkspaceTag (ADR-078 Phase 4)")
struct WorkspaceTagTests {

    @Test("기본 init — colorName default 'blue'")
    func defaultInit() {
        let tag = WorkspaceTag(name: "긴급")
        #expect(tag.name == "긴급")
        #expect(tag.colorName == "blue")
    }

    @Test("Codable round trip")
    func roundTrip() throws {
        let original = WorkspaceTag(name: "iOS", colorName: "purple")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkspaceTag.self, from: encoded)
        #expect(decoded == original)
    }

    @Test("Codable backward-compat — colorName 없는 JSON")
    func backwardCompat() throws {
        let oldJSON = """
        {
            "id": "12345678-1234-1234-1234-123456789012",
            "name": "test"
        }
        """.data(using: .utf8)!
        let tag = try JSONDecoder().decode(WorkspaceTag.self, from: oldJSON)
        #expect(tag.colorName == "blue")  // default
    }
}

@Suite("WorkspaceTagAssignments (ADR-078 Phase 4)")
struct WorkspaceTagAssignmentsTests {

    @Test("add tag to workspace")
    func addTag() {
        var assignments = WorkspaceTagAssignments()
        let wsId = UUID()
        let tagId = UUID()
        assignments.add(tag: tagId, to: wsId)
        #expect(assignments.tags(for: wsId).contains(tagId))
        #expect(assignments.workspaces(withTag: tagId) == [wsId])
    }

    @Test("remove tag — empty 시 entry 자동 정리")
    func removeTag() {
        var assignments = WorkspaceTagAssignments()
        let wsId = UUID()
        let tagId = UUID()
        assignments.add(tag: tagId, to: wsId)
        assignments.remove(tag: tagId, from: wsId)
        #expect(assignments.tags(for: wsId).isEmpty)
        #expect(assignments.workspaceToTags[wsId] == nil)
    }

    @Test("remove tag — 다른 tag는 유지")
    func removeOneOfMultipleTags() {
        var assignments = WorkspaceTagAssignments()
        let wsId = UUID()
        let tag1 = UUID()
        let tag2 = UUID()
        assignments.add(tag: tag1, to: wsId)
        assignments.add(tag: tag2, to: wsId)
        assignments.remove(tag: tag1, from: wsId)
        #expect(assignments.tags(for: wsId) == [tag2])
    }

    @Test("removeAllAssignments — 워크스페이스 삭제 시")
    func removeAll() {
        var assignments = WorkspaceTagAssignments()
        let wsId = UUID()
        assignments.add(tag: UUID(), to: wsId)
        assignments.add(tag: UUID(), to: wsId)
        assignments.removeAllAssignments(for: wsId)
        #expect(assignments.tags(for: wsId).isEmpty)
    }

    @Test("removeTagEverywhere — 태그 삭제 시")
    func removeTagEverywhere() {
        var assignments = WorkspaceTagAssignments()
        let ws1 = UUID()
        let ws2 = UUID()
        let tagToDelete = UUID()
        let otherTag = UUID()
        assignments.add(tag: tagToDelete, to: ws1)
        assignments.add(tag: tagToDelete, to: ws2)
        assignments.add(tag: otherTag, to: ws1)
        assignments.removeTagEverywhere(tagToDelete)
        #expect(assignments.workspaces(withTag: tagToDelete).isEmpty)
        #expect(assignments.tags(for: ws1) == [otherTag])  // otherTag는 유지
    }
}

@Suite("WorkspaceArchive (ADR-078 Phase 5)")
struct WorkspaceArchiveTests {

    @Test("기본 archive 생성 + JSON encode/decode 라운드트립")
    func roundTrip() throws {
        let archive = WorkspaceArchive(
            workspaces: [],
            folders: [],
            pinnedWorkspaceIds: [],
            tags: [],
            tagAssignments: WorkspaceTagAssignments(),
            enabledSmartFolders: []
        )
        let data = try archive.toJSON()
        let decoded = try WorkspaceArchive.fromJSON(data)
        #expect(decoded.version == WorkspaceArchive.currentVersion)
    }

    @Test("unsupportedVersion 에러 — version 999 archive를 만들어 fromJSON로 decode 시 reject")
    func unsupportedVersion() throws {
        // 정상 archive에 version만 999로 setting 후 encode → decode (실제 형식 사용)
        let archive = WorkspaceArchive(
            version: 999,  // 미래 버전
            workspaces: [],
            folders: [],
            pinnedWorkspaceIds: [],
            tags: [],
            tagAssignments: WorkspaceTagAssignments(),
            enabledSmartFolders: []
        )
        let data = try archive.toJSON()
        do {
            _ = try WorkspaceArchive.fromJSON(data)
            Issue.record("future version은 throw해야 함")
        } catch let error as WorkspaceArchiveError {
            switch error {
            case .unsupportedVersion(let v): #expect(v == 999)
            default: Issue.record("unsupportedVersion 에러여야 함")
            }
        } catch {
            Issue.record("WorkspaceArchiveError 타입이어야 함, got: \(error)")
        }
    }

    @Test("currentVersion은 1")
    func currentVersion() {
        #expect(WorkspaceArchive.currentVersion == 1)
    }
}

@Suite("WorkspaceImportStrategy (ADR-078 Phase 5)")
struct WorkspaceImportStrategyTests {

    @Test("3개 strategy 존재")
    func allCases() {
        #expect(WorkspaceImportStrategy.allCases.count == 3)
        #expect(WorkspaceImportStrategy.allCases.contains(.skipExisting))
        #expect(WorkspaceImportStrategy.allCases.contains(.mergeAll))
        #expect(WorkspaceImportStrategy.allCases.contains(.replaceExisting))
    }

    @Test("displayName 한국어")
    func displayNames() {
        #expect(WorkspaceImportStrategy.skipExisting.displayName.contains("기존 항목 유지"))
        #expect(WorkspaceImportStrategy.mergeAll.displayName.contains("모두 추가"))
        #expect(WorkspaceImportStrategy.replaceExisting.displayName.contains("덮어쓰기"))
    }

    @Test("hint 한국어")
    func hints() {
        for strategy in WorkspaceImportStrategy.allCases {
            #expect(!strategy.hint.isEmpty)
        }
    }
}

@Suite("WorkspaceImportResult summary")
struct WorkspaceImportResultTests {

    @Test("빈 result는 '변경 없음'")
    func emptyResult() {
        let result = WorkspaceImportResult()
        #expect(result.summary == "변경 없음")
    }

    @Test("정상 result는 한국어 요약")
    func normalSummary() {
        let result = WorkspaceImportResult(
            workspacesAdded: 5,
            workspacesSkipped: 2,
            foldersAdded: 1,
            tagsAdded: 3
        )
        #expect(result.summary.contains("5개 추가"))
        #expect(result.summary.contains("2개 건너뜀"))
        #expect(result.summary.contains("폴더 1개"))
        #expect(result.summary.contains("태그 3개"))
    }
}
