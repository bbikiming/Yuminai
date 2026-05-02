import Foundation
import Testing
@testable import YuminaiCore

@Suite("TerminalSession — activity + persistence (ADR-041)")
struct TerminalSessionActivityTests {
    @Test("activity 기본값은 .idle, hasUnreadOutput=false")
    func defaultActivity() {
        let s = TerminalSession(label: "x", workingDirectory: "/")
        #expect(s.activity == .idle)
        #expect(s.hasUnreadOutput == false)
    }

    @Test("activity는 mutable")
    func activityMutable() {
        var s = TerminalSession(label: "x", workingDirectory: "/")
        s.activity = .running
        s.hasUnreadOutput = true
        #expect(s.activity == .running)
        #expect(s.hasUnreadOutput)
    }

    @Test("Codable 영속화는 activity/hasUnreadOutput을 제외")
    func codableExcludesActivity() throws {
        var s = TerminalSession(label: "main", workingDirectory: "/tmp")
        s.activity = .running
        s.hasUnreadOutput = true
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(TerminalSession.self, from: data)
        // 라벨/cwd/id/createdAt은 보존
        #expect(decoded.id == s.id)
        #expect(decoded.label == "main")
        #expect(decoded.workingDirectory == "/tmp")
        // activity는 fresh (idle), unread도 fresh (false)
        #expect(decoded.activity == .idle)
        #expect(decoded.hasUnreadOutput == false)
    }

    @Test("Activity raw value 안정 (idle/running/completedRecently)")
    func activityRawValues() {
        #expect(TerminalSession.Activity.idle.rawValue == "idle")
        #expect(TerminalSession.Activity.running.rawValue == "running")
        #expect(TerminalSession.Activity.completedRecently.rawValue == "completedRecently")
    }
}

@Suite("Workspace — savedTerminalSessions 영속 (ADR-041 T13)")
struct WorkspaceTerminalPersistenceTests {
    @Test("default는 빈 배열")
    func defaultEmpty() {
        let w = Workspace(name: "X", directoryPath: "/tmp")
        #expect(w.savedTerminalSessions.isEmpty)
    }

    @Test("with(savedTerminalSessions:) 새 인스턴스 + 다른 필드 보존")
    func withSavedTerminals() {
        let w = Workspace(name: "X", directoryPath: "/tmp", agentKind: .claude)
        let s1 = TerminalSession(label: "main", workingDirectory: "/tmp")
        let s2 = TerminalSession(label: "logs", workingDirectory: "/tmp/logs")
        let updated = w.with(savedTerminalSessions: [s1, s2])
        #expect(updated.savedTerminalSessions.count == 2)
        #expect(updated.savedTerminalSessions[0].label == "main")
        #expect(updated.savedTerminalSessions[1].workingDirectory == "/tmp/logs")
        // 다른 필드는 보존
        #expect(updated.id == w.id)
        #expect(updated.name == "X")
        #expect(updated.agentKind == .claude)
    }

    @Test("Workspace 다른 with(...) 메서드들도 savedTerminalSessions 보존")
    func otherWithMethodsPreserveTerminals() {
        let s = TerminalSession(label: "x", workingDirectory: "/")
        let base = Workspace(name: "B", directoryPath: "/").with(savedTerminalSessions: [s])
        let renamed = base.with(agentKind: .codex)
        #expect(renamed.savedTerminalSessions.count == 1)
        let withDelivery = base.with(deliveryConfig: .disabled)
        #expect(withDelivery.savedTerminalSessions.count == 1)
        let withPanes = base.with(savedPanes: [])
        #expect(withPanes.savedTerminalSessions.count == 1)
    }
}
