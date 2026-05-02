import Foundation
import Testing
@testable import YuminaiCore

@Suite("WorkspaceFileTree — CRUD (ADR-039)")
struct WorkspaceFileTreeCRUDTests {
    /// 임시 디렉토리에 트리 actor + cleanup helper.
    private static func makeTree() throws -> (actor: WorkspaceFileTree, root: URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "yuminai-crud-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (WorkspaceFileTree(rootURL: root), root)
    }

    // MARK: - createFile

    @Test("createFile은 빈 파일 생성 + 정규화된 경로 반환")
    func createFileBasic() async throws {
        let (actor, root) = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = try await actor.createFile("hello.swift")
        #expect(path == "hello.swift")
        let contents = try String(contentsOf: root.appending(path: "hello.swift"), encoding: .utf8)
        #expect(contents == "")
    }

    @Test("createFile은 중간 디렉토리 자동 생성")
    func createFileIntermediateDirs() async throws {
        let (actor, root) = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = try await actor.createFile("a/b/c/deep.txt")
        #expect(path == "a/b/c/deep.txt")
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: root.appending(path: "a/b/c").path,
            isDirectory: &isDir
        )
        #expect(exists && isDir.boolValue)
    }

    @Test("createFile — 이미 존재하면 alreadyExists throw")
    func createFileDuplicateRejected() async throws {
        let (actor, root) = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        try await actor.createFile("dup.txt")
        await #expect(throws: FileTreeError.self) {
            try await actor.createFile("dup.txt")
        }
    }

    // MARK: - createFolder

    @Test("createFolder은 폴더 생성 + 중첩 자동")
    func createFolderBasic() async throws {
        let (actor, root) = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = try await actor.createFolder("src/sub")
        #expect(path == "src/sub")
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: root.appending(path: "src/sub").path,
            isDirectory: &isDir
        )
        #expect(exists && isDir.boolValue)
    }

    @Test("createFolder — 이미 존재하면 reject")
    func createFolderDuplicateRejected() async throws {
        let (actor, root) = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        try await actor.createFolder("once")
        await #expect(throws: FileTreeError.self) {
            try await actor.createFolder("once")
        }
    }

    // MARK: - rename

    @Test("rename — 같은 부모 디렉토리 내에서 이름 변경")
    func renameBasic() async throws {
        let (actor, root) = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        try "hello".write(to: root.appending(path: "old.txt"), atomically: true, encoding: .utf8)
        let newPath = try await actor.rename("old.txt", to: "new.txt")
        #expect(newPath == "new.txt")
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "old.txt").path))
        let contents = try String(contentsOf: root.appending(path: "new.txt"), encoding: .utf8)
        #expect(contents == "hello")
    }

    @Test("rename — 중첩 경로의 파일도 같은 부모 내에서 변경")
    func renameInNestedDir() async throws {
        let (actor, root) = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appending(path: "src"), withIntermediateDirectories: true)
        try "x".write(to: root.appending(path: "src/a.swift"), atomically: true, encoding: .utf8)
        let newPath = try await actor.rename("src/a.swift", to: "b.swift")
        #expect(newPath == "src/b.swift")
    }

    @Test("rename — 새 이름에 ‘/’ 포함되면 invalidName throw")
    func renameWithSlashRejected() async throws {
        let (actor, root) = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        try "x".write(to: root.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        await #expect(throws: FileTreeError.self) {
            try await actor.rename("a.txt", to: "moved/a.txt")
        }
    }

    @Test("rename — 새 이름이 빈 string이면 reject")
    func renameEmptyNameRejected() async throws {
        let (actor, root) = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        try "x".write(to: root.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        await #expect(throws: FileTreeError.self) {
            try await actor.rename("a.txt", to: "   ")
        }
    }

    @Test("rename — 대상이 없으면 fileNotFound")
    func renameMissingSource() async throws {
        let (actor, root) = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: FileTreeError.self) {
            try await actor.rename("ghost.txt", to: "new.txt")
        }
    }

    @Test("rename — 새 경로가 이미 존재하면 reject")
    func renameTargetExistsRejected() async throws {
        let (actor, root) = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        try "a".write(to: root.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        try "b".write(to: root.appending(path: "b.txt"), atomically: true, encoding: .utf8)
        await #expect(throws: FileTreeError.self) {
            try await actor.rename("a.txt", to: "b.txt")
        }
    }

    // MARK: - delete

    @Test("delete — 파일 삭제")
    func deleteFile() async throws {
        let (actor, root) = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        try "x".write(to: root.appending(path: "doomed.txt"), atomically: true, encoding: .utf8)
        try await actor.delete("doomed.txt")
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "doomed.txt").path))
    }

    @Test("delete — 폴더는 재귀 삭제")
    func deleteFolderRecursive() async throws {
        let (actor, root) = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appending(path: "kill/me"), withIntermediateDirectories: true)
        try "data".write(to: root.appending(path: "kill/me/file.txt"), atomically: true, encoding: .utf8)
        try await actor.delete("kill")
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "kill").path))
    }

    @Test("delete — 없는 path는 fileNotFound")
    func deleteMissingFails() async throws {
        let (actor, root) = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: FileTreeError.self) {
            try await actor.delete("ghost.txt")
        }
    }

    // MARK: - Path safety

    @Test("path safety — 절대 경로는 차단 (.. 외에도)")
    func absolutePathRejected() async throws {
        let (actor, root) = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: FileTreeError.self) {
            try await actor.createFile("/etc/passwd")
        }
    }

    @Test("path safety — .. traversal 차단")
    func traversalRejected() async throws {
        let (actor, root) = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: FileTreeError.self) {
            try await actor.createFile("../escape.txt")
        }
        await #expect(throws: FileTreeError.self) {
            try await actor.createFolder("a/../../escape")
        }
    }

    @Test("path safety — 빈 경로 차단")
    func emptyPathRejected() async throws {
        let (actor, root) = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: FileTreeError.self) {
            try await actor.createFile("")
        }
        await #expect(throws: FileTreeError.self) {
            try await actor.createFile("   ")
        }
    }

    @Test("createFile 후 read 즉시 가능")
    func createThenRead() async throws {
        let (actor, root) = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        try await actor.createFile("fresh.swift")
        let contents = try await actor.read("fresh.swift")
        #expect(contents == "")
    }

    @Test("createFile + write 결합으로 본문 채우기")
    func createThenWrite() async throws {
        let (actor, root) = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        try await actor.createFile("notes.md")
        try await actor.write("notes.md", contents: "# Hello")
        let contents = try await actor.read("notes.md")
        #expect(contents == "# Hello")
    }
}
