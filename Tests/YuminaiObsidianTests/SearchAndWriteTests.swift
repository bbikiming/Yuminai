import Foundation
import Testing
@testable import YuminaiObsidian

@Suite("ObsidianVault — searchFullText")
struct SearchFullTextTests {
    @Test("파일명 매칭 우선, source = .filename")
    func filenameMatchPrefersFilename() async throws {
        let temp = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: temp) }

        try "# Hello world".write(to: temp.appending(path: "swift-tutorial.md"), atomically: true, encoding: .utf8)
        try "irrelevant".write(to: temp.appending(path: "other.md"), atomically: true, encoding: .utf8)

        let vault = ObsidianVault(rootURL: temp)
        let hits = try await vault.searchFullText("swift")
        #expect(hits.count == 1)
        #expect(hits[0].matchSource == .filename)
        #expect(hits[0].title == "swift-tutorial")
    }

    @Test("본문 매칭 시 컨텍스트 라인 포함")
    func bodyMatchIncludesContext() async throws {
        let temp = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: temp) }

        let body = "긴 본문... here is the keyword you wanted to find ...더 긴 본문"
        try body.write(to: temp.appending(path: "doc.md"), atomically: true, encoding: .utf8)

        let vault = ObsidianVault(rootURL: temp)
        let hits = try await vault.searchFullText("keyword")
        #expect(hits.count == 1)
        #expect(hits[0].matchSource == .body)
        #expect(hits[0].matchedLine?.contains("keyword") == true)
    }

    @Test("limit 적용")
    func limitClamps() async throws {
        let temp = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: temp) }

        for i in 0..<10 {
            try "common".write(to: temp.appending(path: "note\(i).md"), atomically: true, encoding: .utf8)
        }

        let vault = ObsidianVault(rootURL: temp)
        let hits = try await vault.searchFullText("common", limit: 3)
        #expect(hits.count == 3)
    }

    @Test("빈 쿼리는 빈 결과")
    func emptyQueryReturnsEmpty() async throws {
        let temp = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: temp) }
        try "anything".write(to: temp.appending(path: "x.md"), atomically: true, encoding: .utf8)

        let vault = ObsidianVault(rootURL: temp)
        let hits = try await vault.searchFullText("   ")
        #expect(hits.isEmpty)
    }

    private func makeTempVault() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "yuminai-vault-search-tests")
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@Suite("ObsidianVault — write")
struct VaultWriteTests {
    @Test("write 후 read하면 동일 본문")
    func writeRoundTrip() async throws {
        let temp = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: temp) }
        try "original".write(to: temp.appending(path: "edit.md"), atomically: true, encoding: .utf8)

        let vault = ObsidianVault(rootURL: temp)
        try await vault.write("edit.md", content: "# Updated\n\nNew body.")

        let note = try await vault.read("edit.md")
        #expect(note.body.contains("Updated"))
    }

    private func makeTempVault() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "yuminai-vault-write-tests")
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
