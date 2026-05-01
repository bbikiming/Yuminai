import Foundation
import Testing
@testable import YuminaiObsidian

@Suite("ObsidianVault")
struct ObsidianVaultTests {
    @Test("frontmatter 분리 — yaml + body")
    func splitFrontmatterParsesBoth() {
        let raw = """
        ---
        title: Test Note
        tags: a,b
        ---
        # Body

        Hello world
        """
        let (fm, body) = ObsidianVault.splitFrontmatter(raw)
        #expect(fm["title"] == "Test Note")
        #expect(fm["tags"] == "a,b")
        #expect(body.hasPrefix("# Body"))
    }

    @Test("frontmatter 없으면 빈 dict + 원본")
    func splitFrontmatterFallback() {
        let raw = "# Just markdown\n\nNo frontmatter."
        let (fm, body) = ObsidianVault.splitFrontmatter(raw)
        #expect(fm.isEmpty)
        #expect(body == raw)
    }

    @Test("Vault 미존재 경로는 isValid false")
    func nonexistentVaultIsInvalid() async {
        let vault = ObsidianVault(rootURL: URL(fileURLWithPath: "/nonexistent/path/xyz"))
        let valid = await vault.isValid
        #expect(valid == false)
    }

    @Test("임시 디렉토리 vault — md 파일 인덱싱")
    func tempVaultIndexes() async throws {
        let temp = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: temp) }

        try "# Test 1".write(to: temp.appending(path: "note1.md"), atomically: true, encoding: .utf8)
        try "# Test 2".write(to: temp.appending(path: "note2.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: temp.appending(path: "sub"), withIntermediateDirectories: true)
        try "# Sub".write(to: temp.appending(path: "sub/note3.md"), atomically: true, encoding: .utf8)

        let vault = ObsidianVault(rootURL: temp)
        let tree = try await vault.tree()

        // 폴더 + 노트 합 = 3개 (sub 폴더 + note1 + note2)
        #expect(tree.count == 3)
    }

    @Test(".obsidian / .trash 폴더는 트리에서 제외")
    func ignoresHiddenObsidianFolders() async throws {
        let temp = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: temp) }

        try "# Visible".write(to: temp.appending(path: "visible.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: temp.appending(path: ".obsidian"), withIntermediateDirectories: true)
        try "config".write(to: temp.appending(path: ".obsidian/app.json"), atomically: true, encoding: .utf8)

        let vault = ObsidianVault(rootURL: temp)
        let tree = try await vault.tree()
        #expect(tree.count == 1)
        #expect(tree.first?.name == "visible")
    }

    private func makeTempVault() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "yuminai-vault-tests")
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
