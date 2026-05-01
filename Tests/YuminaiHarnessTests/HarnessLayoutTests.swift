import Foundation
import Testing
import YuminaiCore
@testable import YuminaiHarness

@Suite("HarnessLayout")
struct HarnessLayoutTests {
    @Test("layout이 .harness 하위에 모든 표준 디렉토리/파일을 노출한다")
    func layoutPathsAreCorrect() {
        let workspace = URL(fileURLWithPath: "/tmp/yuminai-test-ws")
        let layout = HarnessLayout(workspaceURL: workspace)

        #expect(layout.harnessURL.path == "/tmp/yuminai-test-ws/.harness")
        #expect(layout.rulesURL.lastPathComponent == "rules")
        #expect(layout.agentsURL.lastPathComponent == "agents")
        #expect(layout.skillsURL.lastPathComponent == "skills")
        #expect(layout.hooksURL.lastPathComponent == "hooks")
        #expect(layout.commandsURL.lastPathComponent == "commands")
        #expect(layout.memoryURL.lastPathComponent == "memory")
        #expect(layout.settingsURL.lastPathComponent == "settings.json")
        #expect(layout.mcpURL.lastPathComponent == ".mcp.json")
    }
}

@Suite("HarnessScaffolder")
struct HarnessScaffolderTests {
    @Test("scaffold는 모든 표준 디렉토리를 만들고 settings/mcp 파일을 작성한다")
    func scaffoldsExpectedTree() throws {
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let layout = HarnessLayout(workspaceURL: temp)
        let scaffolder = HarnessScaffolder()
        try scaffolder.scaffold(template: .swift, at: layout)

        let fm = FileManager.default
        var isDir: ObjCBool = false

        for dir in layout.allDirectoryURLs {
            #expect(fm.fileExists(atPath: dir.path, isDirectory: &isDir))
            #expect(isDir.boolValue)
        }
        #expect(fm.fileExists(atPath: layout.settingsURL.path))
        #expect(fm.fileExists(atPath: layout.mcpURL.path))
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("yuminai-harness-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
