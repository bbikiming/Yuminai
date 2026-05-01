import Foundation
import YuminaiCore

/// 워크스페이스 디렉토리 안의 `.harness/` 위치들을 명시한다.
///
/// 사용자 워크스페이스마다 인스턴스 1개. 글로벌(앱) 하네스는 별도 layout.
public struct HarnessLayout: Sendable, Hashable {
    public let workspaceURL: URL

    public init(workspaceURL: URL) {
        self.workspaceURL = workspaceURL
    }

    public var harnessURL: URL {
        workspaceURL.appendingPathComponent(".harness")
    }

    public var rulesURL: URL { harnessURL.appendingPathComponent("rules") }
    public var agentsURL: URL { harnessURL.appendingPathComponent("agents") }
    public var skillsURL: URL { harnessURL.appendingPathComponent("skills") }
    public var hooksURL: URL { harnessURL.appendingPathComponent("hooks") }
    public var commandsURL: URL { harnessURL.appendingPathComponent("commands") }
    public var memoryURL: URL { harnessURL.appendingPathComponent("memory") }
    public var settingsURL: URL { harnessURL.appendingPathComponent("settings.json") }
    public var mcpURL: URL { harnessURL.appendingPathComponent(".mcp.json") }

    public var allDirectoryURLs: [URL] {
        [rulesURL, agentsURL, skillsURL, hooksURL, commandsURL, memoryURL]
    }
}

/// 새 워크스페이스 생성 시 `.harness/` 디렉토리 + 기본 파일을 만든다.
///
/// FileManager는 non-Sendable이므로 인스턴스로 보관하지 않고 호출 시점에 사용한다.
/// 테스트에서 IO를 가짜로 하려면 `FileManagerProtocol` 같은 추상화를 추가하라.
public struct HarnessScaffolder: Sendable {
    public init() {}

    public func scaffold(template: HarnessTemplateName, at layout: HarnessLayout) throws {
        let fileManager = FileManager.default
        do {
            for dir in layout.allDirectoryURLs {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            try writeDefaultSettings(at: layout.settingsURL)
            try writeDefaultMCP(at: layout.mcpURL)
        } catch {
            throw YuminaiError.harnessScaffoldFailed(
                template: template,
                reason: error.localizedDescription
            )
        }
    }

    private func writeDefaultSettings(at url: URL) throws {
        let defaults = """
        {
          "_comment": "워크스페이스 settings — 글로벌 settings를 상속하며 여기서 override.",
          "permissions": { "allow": [], "deny": [] }
        }
        """
        try defaults.write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeDefaultMCP(at url: URL) throws {
        let defaults = """
        {
          "_comment": "워크스페이스 MCP — 사용자가 추가하는 외부 MCP 서버 정의.",
          "mcpServers": {}
        }
        """
        try defaults.write(to: url, atomically: true, encoding: .utf8)
    }
}
