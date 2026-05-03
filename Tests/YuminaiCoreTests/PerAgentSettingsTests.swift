import Foundation
import Testing
@testable import YuminaiCore

@Suite("Workspace.perAgentSettings (ADR-087 Phase 1)")
struct WorkspacePerAgentSettingsTests {

    @Test("default — 빈 dict, settings(for:)는 default 반환")
    func defaultEmpty() {
        let ws = Workspace(name: "test", directoryPath: "/tmp/test")
        #expect(ws.perAgentSettings.isEmpty)
        let claudeSettings = ws.settings(for: .claude)
        #expect(claudeSettings == .default)
        let codexSettings = ws.settings(for: .codex)
        #expect(codexSettings == .default)
    }

    @Test("with(perAgentSettings:) — Claude/Codex 각각 다른 설정")
    func independentSettings() {
        let claudeSettings = SessionSettings(model: .opus, permissionMode: .plan, effortLevel: .high)
        let codexSettings = SessionSettings(model: .haiku, permissionMode: .acceptEdits, effortLevel: .low)
        let ws = Workspace(name: "t", directoryPath: "/tmp/t")
            .with(perAgentSettings: [.claude: claudeSettings, .codex: codexSettings])

        #expect(ws.settings(for: .claude) == claudeSettings)
        #expect(ws.settings(for: .codex) == codexSettings)
        #expect(ws.settings(for: .claude) != ws.settings(for: .codex))
    }

    @Test("with(perAgentSettings:) — 다른 with 메서드들이 perAgentSettings 보존")
    func preservedAcrossOtherWith() {
        let custom = SessionSettings(model: .opus)
        let ws = Workspace(name: "t", directoryPath: "/tmp/t")
            .with(perAgentSettings: [.claude: custom])

        let updated = ws.with(agentKind: .codex)
        #expect(updated.perAgentSettings[.claude] == custom, "agentKind 변경 후에도 perAgentSettings 유지")
    }

    @Test("Codable round-trip — perAgentSettings 보존")
    func codableRoundTrip() throws {
        let claude = SessionSettings(model: .opus, permissionMode: .plan)
        let codex = SessionSettings(model: .haiku, effortLevel: .low)
        let original = Workspace(
            name: "코드 작업",
            directoryPath: "/tmp/proj",
            perAgentSettings: [.claude: claude, .codex: codex]
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Workspace.self, from: encoded)
        #expect(decoded.perAgentSettings.count == 2)
        #expect(decoded.settings(for: .claude) == claude)
        #expect(decoded.settings(for: .codex) == codex)
    }

    @Test("Codable backward-compat — perAgentSettings 누락 시 빈 dict")
    func backwardCompat() throws {
        // 옛 JSON: perAgentSettings 필드 없음
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "name": "Legacy",
            "directoryPath": "/tmp/legacy",
            "createdAt": \(Date().timeIntervalSinceReferenceDate),
            "agentKind": "claude"
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Workspace.self, from: json)
        #expect(decoded.name == "Legacy")
        #expect(decoded.perAgentSettings.isEmpty, "신규 필드 누락 시 빈 dict")
        #expect(decoded.settings(for: .claude) == .default, "빈 dict면 default 반환")
    }

    @Test("settings(for:) — 한 agent만 설정된 경우, 다른 agent는 default")
    func partialSettings() {
        let only = SessionSettings(model: .opus)
        let ws = Workspace(name: "t", directoryPath: "/tmp/t")
            .with(perAgentSettings: [.claude: only])
        #expect(ws.settings(for: .claude) == only)
        #expect(ws.settings(for: .codex) == .default, "Codex 설정 없음 → default")
    }
}
