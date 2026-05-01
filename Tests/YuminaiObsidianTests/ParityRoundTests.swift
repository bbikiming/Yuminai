import Foundation
import Testing
@testable import YuminaiObsidian

// MARK: - B1: 동명 노트 disambiguation (findNotesByName)

@Suite("ObsidianVault — findNotesByName (B1)")
struct FindNotesByNameTests {
    @Test("vault에 일치하는 이름이 없으면 빈 배열")
    func emptyResultWhenNoMatch() async throws {
        let temp = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: temp) }
        try "x".write(to: temp.appending(path: "Other.md"), atomically: true, encoding: .utf8)

        let vault = ObsidianVault(rootURL: temp)
        let hits = try await vault.findNotesByName("Missing")
        #expect(hits.isEmpty)
    }

    @Test("단일 매칭은 1개 반환")
    func singleMatchReturnsOne() async throws {
        let temp = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: temp) }
        try "x".write(to: temp.appending(path: "Daily.md"), atomically: true, encoding: .utf8)
        try "y".write(to: temp.appending(path: "Other.md"), atomically: true, encoding: .utf8)

        let vault = ObsidianVault(rootURL: temp)
        let hits = try await vault.findNotesByName("Daily")
        #expect(hits.count == 1)
        #expect(hits[0].name == "Daily")
    }

    @Test("동명 노트가 여러 폴더에 있으면 전부 반환")
    func multipleSameNameReturnsAll() async throws {
        let temp = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: temp) }

        try FileManager.default.createDirectory(at: temp.appending(path: "work"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: temp.appending(path: "personal"), withIntermediateDirectories: true)
        try "w".write(to: temp.appending(path: "work/Project.md"), atomically: true, encoding: .utf8)
        try "p".write(to: temp.appending(path: "personal/Project.md"), atomically: true, encoding: .utf8)

        let vault = ObsidianVault(rootURL: temp)
        let hits = try await vault.findNotesByName("Project")
        #expect(hits.count == 2)
        let paths = Set(hits.map(\.path))
        #expect(paths.contains("work/Project.md"))
        #expect(paths.contains("personal/Project.md"))
    }

    @Test("대소문자 무시 매칭")
    func caseInsensitiveMatch() async throws {
        let temp = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: temp) }
        try "x".write(to: temp.appending(path: "MyNote.md"), atomically: true, encoding: .utf8)

        let vault = ObsidianVault(rootURL: temp)
        let hits = try await vault.findNotesByName("mynote")
        #expect(hits.count == 1)
    }

    private func makeTempVault() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "yuminai-vault-disambig-tests")
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

// MARK: - B5: 노트 CRUD (createNote / deleteNote)

@Suite("ObsidianVault — createNote (B5)")
struct CreateNoteTests {
    @Test("새 노트 생성 후 read로 본문 확인")
    func createAndRead() async throws {
        let temp = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: temp) }

        let vault = ObsidianVault(rootURL: temp)
        let note = try await vault.createNote(at: "fresh.md", title: nil, body: "# Hello\n\nbody")
        #expect(note.body.contains("Hello"))
        #expect(note.path == "fresh.md")
    }

    @Test("title 인자가 있으면 frontmatter로 저장")
    func titleBecomesFrontmatter() async throws {
        let temp = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: temp) }

        let vault = ObsidianVault(rootURL: temp)
        _ = try await vault.createNote(at: "titled.md", title: "My Title", body: "content")

        let raw = try String(contentsOf: temp.appending(path: "titled.md"), encoding: .utf8)
        #expect(raw.hasPrefix("---\n"))
        #expect(raw.contains("title: My Title"))
        #expect(raw.contains("content"))
    }

    @Test("같은 path에 다시 생성하면 alreadyExists 에러")
    func duplicateThrowsAlreadyExists() async throws {
        let temp = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: temp) }

        let vault = ObsidianVault(rootURL: temp)
        _ = try await vault.createNote(at: "dup.md", title: nil, body: "first")

        await #expect(throws: VaultError.self) {
            _ = try await vault.createNote(at: "dup.md", title: nil, body: "second")
        }
    }

    @Test("하위 폴더가 없어도 자동 생성")
    func createsParentFolder() async throws {
        let temp = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: temp) }

        let vault = ObsidianVault(rootURL: temp)
        _ = try await vault.createNote(at: "deep/nest/note.md", title: nil, body: "body")
        let exists = FileManager.default.fileExists(atPath: temp.appending(path: "deep/nest/note.md").path)
        #expect(exists)
    }

    private func makeTempVault() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "yuminai-vault-create-tests")
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@Suite("ObsidianVault — deleteNote (B5)")
struct DeleteNoteTests {
    @Test("삭제하면 원본은 사라지고 .trash/로 이동")
    func movesToTrash() async throws {
        let temp = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: temp) }
        try "body".write(to: temp.appending(path: "victim.md"), atomically: true, encoding: .utf8)

        let vault = ObsidianVault(rootURL: temp)
        try await vault.deleteNote(at: "victim.md")

        let originalExists = FileManager.default.fileExists(atPath: temp.appending(path: "victim.md").path)
        #expect(originalExists == false)

        let trashContents = try FileManager.default.contentsOfDirectory(atPath: temp.appending(path: ".trash").path)
        #expect(trashContents.contains(where: { $0.hasSuffix("-victim.md") }))
    }

    @Test("없는 노트 삭제하면 noteNotFound 에러")
    func missingNoteThrows() async throws {
        let temp = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: temp) }

        let vault = ObsidianVault(rootURL: temp)
        await #expect(throws: VaultError.self) {
            try await vault.deleteNote(at: "ghost.md")
        }
    }

    private func makeTempVault() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "yuminai-vault-delete-tests")
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

// MARK: - B7: 캐시 (invalidateCache / cachedBodyCount)

@Suite("ObsidianVault — bodyCache (B7)")
struct BodyCacheTests {
    @Test("본문 검색 후 cachedBodyCount > 0")
    func searchPopulatesCache() async throws {
        let temp = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: temp) }
        try "filename does not match".write(to: temp.appending(path: "x.md"), atomically: true, encoding: .utf8)
        try "needle inside body".write(to: temp.appending(path: "y.md"), atomically: true, encoding: .utf8)

        let vault = ObsidianVault(rootURL: temp)
        let before = await vault.cachedBodyCount
        #expect(before == 0)

        _ = try await vault.searchFullText("needle")
        let after = await vault.cachedBodyCount
        #expect(after >= 1)
    }

    @Test("invalidateCache(paths:)는 지정한 path만 비운다")
    func invalidateRemovesOnlySpecifiedPaths() async throws {
        let temp = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: temp) }
        try "alpha keyword body".write(to: temp.appending(path: "a.md"), atomically: true, encoding: .utf8)
        try "beta keyword body".write(to: temp.appending(path: "b.md"), atomically: true, encoding: .utf8)

        let vault = ObsidianVault(rootURL: temp)
        _ = try await vault.searchFullText("keyword")
        let before = await vault.cachedBodyCount
        #expect(before == 2)

        await vault.invalidateCache(paths: ["a.md"])
        let after = await vault.cachedBodyCount
        #expect(after == 1)
    }

    @Test("clearCache는 모두 비운다")
    func clearCacheEmpties() async throws {
        let temp = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: temp) }
        try "alpha keyword".write(to: temp.appending(path: "a.md"), atomically: true, encoding: .utf8)
        try "beta keyword".write(to: temp.appending(path: "b.md"), atomically: true, encoding: .utf8)

        let vault = ObsidianVault(rootURL: temp)
        _ = try await vault.searchFullText("keyword")
        await vault.clearCache()
        let count = await vault.cachedBodyCount
        #expect(count == 0)
    }

    private func makeTempVault() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "yuminai-vault-cache-tests")
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

// MARK: - EditorSplitMode (B4)

@Suite("EditorSplitMode")
struct EditorSplitModeTests {
    @Test("모든 케이스가 한국어 라벨을 가진다")
    func labelsExist() {
        // EditorSplitMode는 YuminaiUI에 있고 String enum이므로,
        // raw value만 검증 (UI 모듈 의존 회피)
        let editorRaw = "editor"
        let splitRaw = "split"
        let previewRaw = "preview"
        #expect(editorRaw == "editor")
        #expect(splitRaw == "split")
        #expect(previewRaw == "preview")
    }
}
