import Foundation
import Testing
import YuminaiCore

@Suite("AgentKind")
struct AgentKindTests {
    @Test("모든 case가 한국어 displayName + icon + hint를 가진다")
    func allCasesHaveMetadata() {
        for kind in AgentKind.allCases {
            #expect(!kind.displayName.isEmpty)
            #expect(!kind.icon.isEmpty)
            #expect(!kind.hint.isEmpty)
            #expect(!kind.shortLabel.isEmpty)
        }
    }

    @Test("Codable round-trip이 동일 값을 보존한다")
    func codableRoundTrip() throws {
        for kind in AgentKind.allCases {
            let encoded = try JSONEncoder().encode(kind)
            let decoded = try JSONDecoder().decode(AgentKind.self, from: encoded)
            #expect(decoded == kind)
        }
    }

    @Test("default는 .claude")
    func defaultIsClaude() {
        #expect(AgentKind.default == .claude)
    }
}

@Suite("Workspace.with(agentKind:)")
struct WorkspaceWithAgentKindTests {
    @Test("agentKind만 다른 새 인스턴스 반환 — id/name/path/createdAt 보존")
    func updatesAgentKindOnly() {
        let original = Workspace(
            id: UUID(),
            name: "test",
            directoryPath: "/tmp/test",
            agentKind: .claude
        )
        let switched = original.with(agentKind: .codex)

        #expect(switched.id == original.id)
        #expect(switched.name == original.name)
        #expect(switched.directoryPath == original.directoryPath)
        #expect(switched.createdAt == original.createdAt)
        #expect(switched.agentKind == .codex)
        #expect(original.agentKind == .claude, "원본은 변경되지 않음 (immutability)")
    }

    @Test("기본 agentKind는 .claude")
    func defaultAgentKind() {
        let ws = Workspace(name: "x", directoryPath: "/tmp")
        #expect(ws.agentKind == .claude)
    }
}
