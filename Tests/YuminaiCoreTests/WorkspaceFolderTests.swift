import Foundation
import Testing
@testable import YuminaiCore

@Suite("WorkspaceFolder (ADR-076 Phase 1)")
struct WorkspaceFolderTests {

    @Test("기본 init — 비어있는 폴더 + expanded + folder.fill 아이콘")
    func defaultInit() {
        let folder = WorkspaceFolder(name: "테스트")
        #expect(folder.name == "테스트")
        #expect(folder.workspaceIds.isEmpty)
        #expect(folder.isExpanded == true)
        #expect(folder.iconName == "folder.fill")
    }

    @Test("workspaceIds + iconName custom")
    func customInit() {
        let id1 = UUID()
        let id2 = UUID()
        let folder = WorkspaceFolder(
            name: "프로젝트",
            workspaceIds: [id1, id2],
            isExpanded: false,
            iconName: "folder.badge.gearshape"
        )
        #expect(folder.workspaceIds == [id1, id2])
        #expect(folder.isExpanded == false)
        #expect(folder.iconName == "folder.badge.gearshape")
    }

    @Test("Codable round trip")
    func roundTrip() throws {
        let original = WorkspaceFolder(
            name: "원본",
            workspaceIds: [UUID(), UUID()],
            isExpanded: false,
            iconName: "folder.badge.questionmark"
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkspaceFolder.self, from: encoded)
        #expect(decoded == original)
    }

    @Test("decode without optional fields — backward-compat")
    func decodeBackwardCompat() throws {
        // 기존 JSON에 isExpanded/iconName 없는 경우 (하위 버전)
        let oldJSON = """
        {
            "id": "12345678-1234-1234-1234-123456789012",
            "name": "구버전",
            "workspaceIds": []
        }
        """.data(using: .utf8)!
        let folder = try JSONDecoder().decode(WorkspaceFolder.self, from: oldJSON)
        #expect(folder.name == "구버전")
        #expect(folder.isExpanded == true)  // default
        #expect(folder.iconName == "folder.fill")  // default
    }

    @Test("Identifiable conformance")
    func identifiable() {
        let id = UUID()
        let folder = WorkspaceFolder(id: id, name: "test")
        #expect(folder.id == id)
    }

    @Test("Hashable conformance — 동일 데이터는 동일 hash")
    func hashable() {
        let id = UUID()
        let f1 = WorkspaceFolder(id: id, name: "a", workspaceIds: [])
        let f2 = WorkspaceFolder(id: id, name: "a", workspaceIds: [])
        #expect(f1 == f2)
        var set: Set<WorkspaceFolder> = []
        set.insert(f1)
        set.insert(f2)
        #expect(set.count == 1)
    }
}

@Suite("AppPreferences pin + folder (ADR-076)")
struct AppPreferencesPinFolderTests {

    @Test("default — 핀 없음 + 폴더 없음")
    func emptyDefaults() {
        let prefs = AppPreferences()
        #expect(prefs.pinnedWorkspaceIds.isEmpty)
        #expect(prefs.workspaceFolders.isEmpty)
    }

    @Test("decode without ADR-076 fields — backward-compat (기존 사용자)")
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
        #expect(prefs.pinnedWorkspaceIds.isEmpty)
        #expect(prefs.workspaceFolders.isEmpty)
    }

    @Test("encode + decode round trip")
    func roundTrip() throws {
        let id1 = UUID()
        let id2 = UUID()
        var prefs = AppPreferences()
        prefs.pinnedWorkspaceIds = [id1, id2]
        prefs.workspaceFolders = [
            WorkspaceFolder(name: "A", workspaceIds: [id1]),
            WorkspaceFolder(name: "B", workspaceIds: [id2], isExpanded: false)
        ]
        let encoded = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: encoded)
        #expect(decoded.pinnedWorkspaceIds == [id1, id2])
        #expect(decoded.workspaceFolders.count == 2)
        #expect(decoded.workspaceFolders[0].name == "A")
        #expect(decoded.workspaceFolders[1].isExpanded == false)
    }
}
