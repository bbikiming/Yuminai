import Foundation
import Testing
@testable import YuminaiCore

@Suite("HarnessRulesLoader (ADR-132)")
struct HarnessRulesLoaderTests {

    // MARK: - 디렉토리 없음

    @Test("디렉토리 없음 — 빈 문자열 반환")
    func noDirectoryReturnsEmpty() async {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let result = await HarnessRulesLoader.loadAll(workspaceURL: tmp)
        #expect(result.isEmpty)
    }

    // MARK: - 빈 디렉토리

    @Test(".harness/rules 존재하지만 .md 파일 없음 — 빈 문자열 반환")
    func emptyRulesDirectoryReturnsEmpty() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let rulesDir = tmp.appendingPathComponent(".harness/rules")
        try FileManager.default.createDirectory(at: rulesDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let result = await HarnessRulesLoader.loadAll(workspaceURL: tmp)
        #expect(result.isEmpty)
    }

    // MARK: - 빈 파일

    @Test("빈 .md 파일은 결과에서 제외됨")
    func emptyMdFileIsSkipped() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let rulesDir = tmp.appendingPathComponent(".harness/rules")
        try FileManager.default.createDirectory(at: rulesDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // 빈 파일 생성
        let emptyFile = rulesDir.appendingPathComponent("empty.md")
        try "".write(to: emptyFile, atomically: true, encoding: .utf8)

        let result = await HarnessRulesLoader.loadAll(workspaceURL: tmp)
        #expect(result.isEmpty)
    }

    // MARK: - 단일 파일

    @Test("단일 .md 파일 — 내용 포함 + 헤더 추가")
    func singleMdFileIncludesContent() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let rulesDir = tmp.appendingPathComponent(".harness/rules")
        try FileManager.default.createDirectory(at: rulesDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let fileContent = "항상 불변성을 유지하라."
        try fileContent.write(
            to: rulesDir.appendingPathComponent("coding-style.md"),
            atomically: true, encoding: .utf8
        )

        let result = await HarnessRulesLoader.loadAll(workspaceURL: tmp)
        #expect(result.contains("coding-style"))
        #expect(result.contains("항상 불변성을 유지하라."))
        #expect(result.contains("워크스페이스 규칙"))
    }

    // MARK: - 다중 파일 합치기

    @Test("다중 .md 파일 — 파일명 오름차순으로 합쳐짐")
    func multipleFilesAreSortedAndCombined() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let rulesDir = tmp.appendingPathComponent(".harness/rules")
        try FileManager.default.createDirectory(at: rulesDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try "B 파일 내용".write(to: rulesDir.appendingPathComponent("b-rule.md"), atomically: true, encoding: .utf8)
        try "A 파일 내용".write(to: rulesDir.appendingPathComponent("a-rule.md"), atomically: true, encoding: .utf8)
        try "C 파일 내용".write(to: rulesDir.appendingPathComponent("c-rule.md"), atomically: true, encoding: .utf8)

        let result = await HarnessRulesLoader.loadAll(workspaceURL: tmp)

        // 모두 포함
        #expect(result.contains("A 파일 내용"))
        #expect(result.contains("B 파일 내용"))
        #expect(result.contains("C 파일 내용"))

        // 오름차순 정렬 확인 (a가 b보다 먼저)
        let aIndex = result.range(of: "a-rule")
        let bIndex = result.range(of: "b-rule")
        let cIndex = result.range(of: "c-rule")
        if let aIdx = aIndex, let bIdx = bIndex, let cIdx = cIndex {
            #expect(aIdx.lowerBound < bIdx.lowerBound)
            #expect(bIdx.lowerBound < cIdx.lowerBound)
        }
    }

    // MARK: - 비-md 파일 무시

    @Test("비-.md 파일(.txt, .json)은 무시됨")
    func nonMdFilesAreIgnored() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let rulesDir = tmp.appendingPathComponent(".harness/rules")
        try FileManager.default.createDirectory(at: rulesDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try "txt 내용".write(to: rulesDir.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)
        try "{}".write(to: rulesDir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        try "md 내용".write(to: rulesDir.appendingPathComponent("rule.md"), atomically: true, encoding: .utf8)

        let result = await HarnessRulesLoader.loadAll(workspaceURL: tmp)
        #expect(result.contains("md 내용"))
        #expect(!result.contains("txt 내용"))
        #expect(!result.contains("{}"))
    }

    // MARK: - markdownFiles 헬퍼

    @Test("markdownFiles — 존재하지 않는 디렉토리면 빈 배열")
    func markdownFilesNonexistentDir() {
        let nonexistent = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString)")
        let files = HarnessRulesLoader.markdownFiles(in: nonexistent)
        #expect(files.isEmpty)
    }
}
