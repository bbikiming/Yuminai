import Foundation
import Testing
import YuminaiCore

@Suite("Workspace — savedPanes")
struct WorkspaceSavedPanesTests {
    @Test("기본은 빈 배열")
    func defaultsEmpty() {
        let ws = Workspace(name: "test", directoryPath: "/tmp")
        #expect(ws.savedPanes.isEmpty)
    }

    @Test("savedPanes 1개 생성 시 보존")
    func onePane() {
        let pane = AgentPane(agentKind: .claude, role: .primary)
        let ws = Workspace(name: "test", directoryPath: "/tmp", savedPanes: [pane])
        #expect(ws.savedPanes.count == 1)
        #expect(ws.savedPanes[0].id == pane.id)
    }

    @Test("with(savedPanes:) immutable update")
    func withSavedPanesImmutable() {
        let original = Workspace(name: "test", directoryPath: "/tmp")
        let claude = AgentPane(agentKind: .claude, role: .primary)
        let codex = AgentPane(agentKind: .codex, role: .secondary)
        let updated = original.with(savedPanes: [claude, codex])
        #expect(updated.savedPanes.count == 2)
        #expect(original.savedPanes.isEmpty, "원본 불변")
    }

    @Test("Workspace JSON encode/decode round-trip — savedPanes 보존")
    func workspaceCodableRoundTrip() throws {
        let claude = AgentPane(
            id: UUID(),
            agentKind: .claude,
            role: .primary,
            customName: "Claude (설계)"
        )
        let codex = AgentPane(
            id: UUID(),
            agentKind: .codex,
            role: .secondary,
            customName: "Codex (구현)"
        )
        let ws = Workspace(
            name: "test",
            directoryPath: "/tmp",
            agentKind: .claude,
            savedPanes: [claude, codex]
        )

        // Workspace 자체는 Codable이 아니지만 savedPanes는 Codable
        let panesData = try JSONEncoder().encode(ws.savedPanes)
        let decoded = try JSONDecoder().decode([AgentPane].self, from: panesData)

        #expect(decoded.count == 2)
        #expect(decoded[0].id == claude.id)
        #expect(decoded[0].customName == "Claude (설계)")
        #expect(decoded[0].role == .primary)
        #expect(decoded[1].agentKind == .codex)
    }

    @Test("with(agentKind:)/with(deliveryConfig:)도 savedPanes 보존")
    func otherWithMethodsPreserveSavedPanes() {
        let pane = AgentPane(agentKind: .claude, role: .primary)
        let original = Workspace(name: "test", directoryPath: "/tmp", savedPanes: [pane])

        let kindChanged = original.with(agentKind: .codex)
        #expect(kindChanged.savedPanes.count == 1)
        #expect(kindChanged.agentKind == .codex)

        let deliveryChanged = original.with(deliveryConfig: DeliveryConfig(testCommand: "swift test"))
        #expect(deliveryChanged.savedPanes.count == 1)
    }
}
