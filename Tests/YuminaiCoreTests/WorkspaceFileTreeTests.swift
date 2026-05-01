import Foundation
import Testing
@testable import YuminaiCore

@Suite("WorkspaceFileTree")
struct WorkspaceFileTreeTests {
    @Test("excludedFolders는 .git, node_modules 등 포함")
    func excludedFolders() {
        #expect(WorkspaceFileTree.excludedFolders.contains(".git"))
        #expect(WorkspaceFileTree.excludedFolders.contains("node_modules"))
        #expect(WorkspaceFileTree.excludedFolders.contains(".build"))
        #expect(WorkspaceFileTree.excludedFolders.contains("__pycache__"))
        #expect(!WorkspaceFileTree.excludedFolders.contains("src"))
    }

    @Test("binaryExtensions는 png/zip/exe 등 포함")
    func binaryExtensions() {
        #expect(WorkspaceFileTree.binaryExtensions.contains("png"))
        #expect(WorkspaceFileTree.binaryExtensions.contains("zip"))
        #expect(WorkspaceFileTree.binaryExtensions.contains("exe"))
        #expect(!WorkspaceFileTree.binaryExtensions.contains("swift"))
        #expect(!WorkspaceFileTree.binaryExtensions.contains("md"))
    }

    @Test("FileNode.isFolder/isBinary 동작")
    func nodeFlags() {
        let folder = FileNode.folder(name: "src", path: "src", children: [])
        #expect(folder.isFolder)
        #expect(!folder.isBinary)

        let txt = FileNode.file(name: "a.txt", path: "a.txt", ext: "txt", size: 10, isBinary: false)
        #expect(!txt.isFolder)
        #expect(!txt.isBinary)

        let png = FileNode.file(name: "logo.png", path: "logo.png", ext: "png", size: 1000, isBinary: true)
        #expect(png.isBinary)
    }

    @Test("실제 디렉토리 트리 + 자동 제외 동작")
    func realDirectoryTree() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appending(path: "yuminai-tree-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        // 일반 파일 + 자동 제외 폴더
        try "swift code".write(to: temp.appending(path: "main.swift"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: temp.appending(path: ".git"), withIntermediateDirectories: true)
        try "git data".write(to: temp.appending(path: ".git/HEAD"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: temp.appending(path: "src"), withIntermediateDirectories: true)
        try "module".write(to: temp.appending(path: "src/Module.swift"), atomically: true, encoding: .utf8)

        let tree = WorkspaceFileTree(rootURL: temp)
        let nodes = try await tree.tree()

        // .git은 제외
        #expect(!nodes.contains { $0.name == ".git" })
        // main.swift + src 폴더 = 2개
        #expect(nodes.count == 2)
        #expect(nodes.contains { $0.name == "main.swift" })
        #expect(nodes.contains { $0.name == "src" })
    }

    @Test("read — 정상 파일")
    func readNormalFile() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appending(path: "yuminai-read-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        try "hello world".write(to: temp.appending(path: "test.txt"), atomically: true, encoding: .utf8)
        let tree = WorkspaceFileTree(rootURL: temp)
        let contents = try await tree.read("test.txt")
        #expect(contents == "hello world")
    }

    @Test("read — 너무 큰 파일은 reject")
    func readTooLargeRejects() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appending(path: "yuminai-large-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let big = String(repeating: "a", count: 200)
        try big.write(to: temp.appending(path: "big.txt"), atomically: true, encoding: .utf8)
        let tree = WorkspaceFileTree(rootURL: temp)
        await #expect(throws: FileTreeError.self) {
            _ = try await tree.read("big.txt", maxBytes: 100)
        }
    }

    @Test("write 후 read round-trip")
    func writeRoundTrip() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appending(path: "yuminai-write-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let tree = WorkspaceFileTree(rootURL: temp)
        try await tree.write("new/nested/file.txt", contents: "content")
        let read = try await tree.read("new/nested/file.txt")
        #expect(read == "content")
    }
}
