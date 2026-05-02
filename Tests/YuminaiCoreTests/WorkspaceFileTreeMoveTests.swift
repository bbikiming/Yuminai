import Foundation
import Testing
@testable import YuminaiCore

@Suite("WorkspaceFileTree — move + bulk delete (ADR-040)")
struct WorkspaceFileTreeMoveTests {
    private static func makeTree() throws -> (actor: WorkspaceFileTree, root: URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "yuminai-move-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (WorkspaceFileTree(rootURL: root), root)
    }

    // MARK: - move

    @Test("move — 다른 부모 디렉토리로 이동 + 부모 자동 생성")
    func moveCrossParent() async throws {
        let (actor, root) = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        try "x".write(to: root.appending(path: "src.swift"), atomically: true, encoding: .utf8)
        let newPath = try await actor.move("src.swift", to: "dest/sub/src.swift")
        #expect(newPath == "dest/sub/src.swift")
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "src.swift").path))
        let contents = try String(contentsOf: root.appending(path: "dest/sub/src.swift"), encoding: .utf8)
        #expect(contents == "x")
    }

    @Test("move — 폴더 통째로 이동")
    func moveFolder() async throws {
        let (actor, root) = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appending(path: "old/inner"), withIntermediateDirectories: true)
        try "data".write(to: root.appending(path: "old/inner/file.txt"), atomically: true, encoding: .utf8)
        let newPath = try await actor.move("old", to: "new")
        #expect(newPath == "new")
        let contents = try String(contentsOf: root.appending(path: "new/inner/file.txt"), encoding: .utf8)
        #expect(contents == "data")
    }

    @Test("move — 새 path 이미 존재하면 reject")
    func moveTargetExistsRejected() async throws {
        let (actor, root) = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        try "a".write(to: root.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        try "b".write(to: root.appending(path: "b.txt"), atomically: true, encoding: .utf8)
        await #expect(throws: FileTreeError.self) {
            try await actor.move("a.txt", to: "b.txt")
        }
    }

    @Test("move — source 없으면 fileNotFound")
    func moveMissingSource() async throws {
        let (actor, root) = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: FileTreeError.self) {
            try await actor.move("ghost", to: "wherever")
        }
    }

    @Test("move — `..` traversal 차단 (path safety 적용)")
    func moveTraversalRejected() async throws {
        let (actor, root) = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        try "x".write(to: root.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        await #expect(throws: FileTreeError.self) {
            try await actor.move("a.txt", to: "../escape.txt")
        }
    }

    // MARK: - deleteMany

    @Test("deleteMany — 여러 파일 일괄 삭제")
    func deleteManyBasic() async throws {
        let (actor, root) = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["a.txt", "b.txt", "c.txt"] {
            try "x".write(to: root.appending(path: name), atomically: true, encoding: .utf8)
        }
        try await actor.deleteMany(["a.txt", "b.txt", "c.txt"])
        for name in ["a.txt", "b.txt", "c.txt"] {
            #expect(!FileManager.default.fileExists(atPath: root.appending(path: name).path))
        }
    }

    @Test("deleteMany — 일부 missing이어도 나머지 진행 + 첫 에러 throw")
    func deleteManyPartialFailure() async throws {
        let (actor, root) = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        try "x".write(to: root.appending(path: "exists.txt"), atomically: true, encoding: .utf8)
        await #expect(throws: FileTreeError.self) {
            try await actor.deleteMany(["ghost.txt", "exists.txt"])
        }
        // exists.txt는 삭제됐어야 함 (best-effort)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "exists.txt").path))
    }

    @Test("deleteMany — 빈 배열은 안전 noop")
    func deleteManyEmpty() async throws {
        let (actor, root) = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        try await actor.deleteMany([])
    }

    // MARK: - delete with trash option

    @Test("delete — moveToTrash=false면 영구 삭제 (default)")
    func deletePermanent() async throws {
        let (actor, root) = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        try "x".write(to: root.appending(path: "permanent.txt"), atomically: true, encoding: .utf8)
        try await actor.delete("permanent.txt", moveToTrash: false)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "permanent.txt").path))
    }
}
