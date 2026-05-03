import Foundation
import Testing
@testable import YuminaiCore

@Suite("ChatSession (ADR-089)")
struct ChatSessionTests {

    @Test("init — 기본값 + 필수 필드")
    func defaultInit() {
        let wsId = UUID()
        let s = ChatSession(title: "test", workspaceId: wsId)
        #expect(s.title == "test")
        #expect(s.workspaceId == wsId)
        #expect(s.agentKind == .claude)
        #expect(s.settings == .default)
        #expect(s.savedMessages.isEmpty)
        #expect(!s.isArchived)
    }

    @Test("appending — 메시지 추가 + lastActiveAt 갱신")
    func appendMessage() async throws {
        let initial = ChatSession(title: "t", workspaceId: UUID())
        let initialTime = initial.lastActiveAt
        try await Task.sleep(nanoseconds: 10_000_000)  // 10ms 대기

        let msg = Message(sessionId: UUID(), role: .user, content: "hello")
        let updated = initial.appending(msg)
        #expect(updated.savedMessages.count == 1)
        #expect(updated.savedMessages.first?.content == "hello")
        #expect(updated.lastActiveAt > initialTime)
        // immutability — 원본 유지
        #expect(initial.savedMessages.isEmpty)
    }

    @Test("with(title:) / with(isArchived:) — 불변성 유지")
    func withMutators() {
        let s = ChatSession(title: "old", workspaceId: UUID())
        let renamed = s.with(title: "new")
        #expect(renamed.title == "new")
        #expect(s.title == "old", "원본 변경 없음")

        let archived = s.with(isArchived: true)
        #expect(archived.isArchived == true)
        #expect(!s.isArchived)
    }

    @Test("with(agentKind:settings:) — agent + settings 동시 갱신 + lastActiveAt 갱신")
    func withAgent() async throws {
        let s = ChatSession(
            title: "t", workspaceId: UUID(),
            agentKind: .claude,
            settings: SessionSettings(model: .sonnet)
        )
        let initialTime = s.lastActiveAt
        try await Task.sleep(nanoseconds: 10_000_000)

        let newSettings = SessionSettings(codexModel: .o3)
        let updated = s.with(agentKind: .codex, settings: newSettings)
        #expect(updated.agentKind == .codex)
        #expect(updated.settings.codexModel == .o3)
        #expect(updated.lastActiveAt > initialTime)
    }

    @Test("subtitle — workspace 이름 + agent + model")
    func subtitle() {
        // Claude
        let claude = ChatSession(
            title: "t", workspaceId: UUID(),
            agentKind: .claude,
            settings: SessionSettings(model: .opus)
        )
        let sub = claude.subtitle(workspaceName: "내 프로젝트")
        #expect(sub.contains("내 프로젝트"))
        #expect(sub.contains("Claude"))
        #expect(sub.contains("Opus"))

        // Codex
        let codex = ChatSession(
            title: "t", workspaceId: UUID(),
            agentKind: .codex,
            settings: SessionSettings(codexModel: .gpt5Codex)
        )
        let sub2 = codex.subtitle(workspaceName: "프론트")
        #expect(sub2.contains("프론트"))
        #expect(sub2.contains("Codex"))
        #expect(sub2.contains("GPT-5 Codex"))
    }

    @Test("Codable round-trip — 모든 필드 보존")
    func codableRoundTrip() throws {
        let original = ChatSession(
            title: "버그 디버깅",
            workspaceId: UUID(),
            agentKind: .codex,
            settings: SessionSettings(model: .opus, codexModel: .o3, permissionMode: .plan, effortLevel: .high)
        )
        let msg = Message(sessionId: UUID(), role: .user, content: "재현 단계?")
        let withMsg = original.appending(msg)

        let data = try JSONEncoder().encode(withMsg)
        let decoded = try JSONDecoder().decode(ChatSession.self, from: data)
        #expect(decoded.title == "버그 디버깅")
        #expect(decoded.agentKind == .codex)
        #expect(decoded.settings.codexModel == .o3)
        #expect(decoded.settings.permissionMode == .plan)
        #expect(decoded.savedMessages.count == 1)
        #expect(decoded.savedMessages.first?.content == "재현 단계?")
    }

    @Test("Codable backward-compat — 일부 필드 누락 OK")
    func backwardCompat() throws {
        // 옛 JSON: agentKind/settings/savedMessages/isArchived 누락
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "title": "Legacy",
            "workspaceId": "\(UUID().uuidString)",
            "createdAt": \(Date().timeIntervalSinceReferenceDate)
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ChatSession.self, from: json)
        #expect(decoded.title == "Legacy")
        #expect(decoded.agentKind == .claude, "default")
        #expect(decoded.settings == .default)
        #expect(decoded.savedMessages.isEmpty)
        #expect(!decoded.isArchived)
    }
}
