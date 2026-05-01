import Foundation
import Testing
import YuminaiCore

@Suite("AgentPane")
struct AgentPaneTests {
    @Test("기본값은 claude/.secondary/customName=nil")
    func defaults() {
        let pane = AgentPane()
        #expect(pane.agentKind == .claude)
        #expect(pane.role == .secondary)
        #expect(pane.customName == nil)
        #expect(pane.displayName == "Claude")
    }

    @Test("customName이 있으면 displayName으로 노출")
    func customNameOverridesDisplayName() {
        let pane = AgentPane(customName: "Claude (설계)")
        #expect(pane.displayName == "Claude (설계)")
    }

    @Test("customName이 빈 문자열이면 fallback to agentKind")
    func emptyCustomNameFallsBack() {
        let pane = AgentPane(agentKind: .codex, customName: "")
        #expect(pane.displayName == "Codex")
    }

    @Test("with(agentKind:)는 immutable update")
    func withAgentKindImmutable() {
        let original = AgentPane(agentKind: .claude, role: .primary)
        let switched = original.with(agentKind: .codex)
        #expect(switched.agentKind == .codex)
        #expect(switched.id == original.id)
        #expect(switched.role == .primary, "role 보존")
        #expect(original.agentKind == .claude, "원본 불변")
    }

    @Test("with(role:) immutable update")
    func withRoleImmutable() {
        let p = AgentPane(role: .secondary)
        let promoted = p.with(role: .primary)
        #expect(promoted.role == .primary)
        #expect(p.role == .secondary)
    }

    @Test("with(customName:) — nil/empty/text 모두 처리")
    func withCustomNameVariants() {
        let p = AgentPane(customName: "초기")
        #expect(p.with(customName: nil).customName == nil)
        #expect(p.with(customName: "변경").customName == "변경")
    }

    @Test("PaneRole 한국어 라벨 + icon")
    func paneRoleMetadata() {
        #expect(PaneRole.primary.label == "기본")
        #expect(PaneRole.secondary.label == "보조")
        #expect(!PaneRole.primary.icon.isEmpty)
        #expect(!PaneRole.secondary.icon.isEmpty)
    }

    @Test("Codable round-trip")
    func paneRoleCodable() throws {
        for role in PaneRole.allCases {
            let data = try JSONEncoder().encode(role)
            let decoded = try JSONDecoder().decode(PaneRole.self, from: data)
            #expect(decoded == role)
        }
    }

    @Test("두 개 같은 agentKind pane은 id로만 구별")
    func sameKindDistinctById() {
        let a = AgentPane(agentKind: .claude, customName: "설계")
        let b = AgentPane(agentKind: .claude, customName: "검토")
        #expect(a.id != b.id)
        #expect(a != b)
    }
}
