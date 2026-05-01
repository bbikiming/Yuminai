import Foundation
import Testing
@testable import YuminaiCore

@Suite("FileTab — multi-tab 편집 state")
struct FileTabTests {
    @Test("기본 생성 시 draft = savedContents, isEditing=false")
    func defaultsMatchSaved() {
        let tab = FileTab(path: "src/main.swift", savedContents: "hello")
        #expect(tab.draft == "hello")
        #expect(tab.isEditing == false)
        #expect(tab.isDirty == false)
    }

    @Test("draft != savedContents 라도 isEditing=false면 dirty 아님 (preview만 변경된 상태)")
    func draftDifferenceWithoutEditingIsNotDirty() {
        var tab = FileTab(path: "a.swift", savedContents: "v1")
        tab.draft = "v2"
        #expect(tab.isDirty == false, "isEditing이 false면 dirty 판단 안 함")
    }

    @Test("isEditing=true + draft 변경 시 dirty=true")
    func editingWithChangeIsDirty() {
        var tab = FileTab(path: "a.swift", savedContents: "v1", isEditing: true)
        #expect(tab.isDirty == false, "draft가 saved와 같으면 dirty 아님")
        tab.draft = "v2"
        #expect(tab.isDirty == true)
    }

    @Test("displayName은 path의 마지막 component")
    func displayNameUsesLastComponent() {
        #expect(FileTab(path: "Sources/Yuminai/Foo.swift", savedContents: "").displayName == "Foo.swift")
        #expect(FileTab(path: "README.md", savedContents: "").displayName == "README.md")
        #expect(FileTab(path: "/abs/path/.env", savedContents: "").displayName == ".env")
    }

    @Test("같은 path 다른 id면 Equatable로 다름")
    func equatabilityUsesId() {
        let t1 = FileTab(path: "x.swift", savedContents: "")
        let t2 = FileTab(path: "x.swift", savedContents: "")
        #expect(t1 != t2, "id가 다르면 같은 path라도 다른 tab으로 취급")
    }

    @Test("Hashable — Set 중복 제거")
    func hashableSet() {
        let t = FileTab(path: "x.swift", savedContents: "")
        let set: Set<FileTab> = [t, t]
        #expect(set.count == 1)
    }

    @Test("isEditing=true에서 saved와 같은 draft로 되돌리면 다시 clean")
    func revertingMakesClean() {
        var tab = FileTab(path: "a.swift", savedContents: "saved", isEditing: true)
        tab.draft = "edit"
        #expect(tab.isDirty)
        tab.draft = "saved"
        #expect(!tab.isDirty)
    }
}

@Suite("CustomQuickCommand")
struct CustomQuickCommandTests {
    @Test("기본 init은 새 UUID 부여")
    func newIdPerInstance() {
        let a = CustomQuickCommand(label: "x", command: "x")
        let b = CustomQuickCommand(label: "x", command: "x")
        #expect(a.id != b.id)
    }

    @Test("명시적 id 보존 (불변)")
    func explicitIdPreserved() {
        let id = UUID()
        let q = CustomQuickCommand(id: id, label: "L", command: "C")
        #expect(q.id == id)
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let q = CustomQuickCommand(label: "서버 시작", command: "npm run dev")
        let data = try JSONEncoder().encode(q)
        let decoded = try JSONDecoder().decode(CustomQuickCommand.self, from: data)
        #expect(decoded == q)
        #expect(decoded.label == "서버 시작")
        #expect(decoded.command == "npm run dev")
    }

    @Test("DeliveryConfig에 customQuickCommands 직렬화 후 동일")
    func deliveryConfigCarriesCustom() throws {
        let cfg = DeliveryConfig(
            testCommand: "swift test",
            customQuickCommands: [
                CustomQuickCommand(label: "서버", command: "npm run dev"),
                CustomQuickCommand(label: "DB 마이그", command: "npm run migrate")
            ]
        )
        let data = try JSONEncoder().encode(cfg)
        let decoded = try JSONDecoder().decode(DeliveryConfig.self, from: data)
        #expect(decoded.customQuickCommands.count == 2)
        #expect(decoded.customQuickCommands[0].label == "서버")
        #expect(decoded.customQuickCommands[1].command == "npm run migrate")
    }
}
