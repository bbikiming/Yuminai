import Foundation
import Testing
@testable import YuminaiCore

/// **ADR-114 P0-1** — `runCommandFromTelegram` chat-specific workspace routing 검증.
///
/// AppModel의 실제 `runCommandFromTelegram(_:chatId:)` 내부 로직:
///   1. chatId 있음 + binding 매칭 + activeWorkspaceId 있음 → bound workspace 선택
///   2. chatId 있음 + binding 없음 → currentWorkspace fallback
///   3. chatId nil → currentWorkspace fallback (legacy 동작)
///
/// 테스트는 `BotChatBinding`/`AppPreferences` 조회 로직을 직접 검증한다
/// (AppModel은 executable target이라 import 불가 — 동일 lookup 재현).
@Suite("RunCommandRouting (ADR-114 P0-1)")
struct RunCommandRoutingTests {

    // MARK: - Helper: workspace lookup 재현

    /// AppModel.runCommandFromTelegram 내부의 workspace lookup 로직을 순수 함수로 추출.
    /// chatId가 있으면 bindings에서 매칭 후 workspaces에서 조회, 없으면 fallback.
    private func resolveWorkspace(
        chatId: Int64?,
        bindings: [BotChatBinding],
        workspaces: [Workspace],
        fallback: Workspace?
    ) -> Workspace? {
        if let chatId,
           let binding = bindings.first(where: { $0.chatId == chatId }),
           let wsId = binding.activeWorkspaceId,
           let bound = workspaces.first(where: { $0.id == wsId }) {
            return bound
        }
        return fallback
    }

    // MARK: - Fixtures

    private func makeWorkspace(name: String) -> Workspace {
        Workspace(name: name, directoryPath: "/tmp/\(name)")
    }

    // MARK: - Tests

    @Test("chatId 있음 + binding 매칭 → bound workspace 반환")
    func chatIdWithMatchingBinding_returnsBoundWorkspace() {
        let wsA = makeWorkspace(name: "workspace-A")
        let wsB = makeWorkspace(name: "workspace-B")
        let binding = BotChatBinding(
            botId: UUID(),
            chatId: 12345,
            activeWorkspaceId: wsA.id
        )

        let result = resolveWorkspace(
            chatId: 12345,
            bindings: [binding],
            workspaces: [wsA, wsB],
            fallback: wsB
        )

        #expect(result?.id == wsA.id)
        #expect(result?.name == "workspace-A")
    }

    @Test("chatId 있음 + binding 없음 → currentWorkspace fallback")
    func chatIdWithNoBinding_returnsFallback() {
        let wsA = makeWorkspace(name: "workspace-A")
        let wsB = makeWorkspace(name: "workspace-B")
        let binding = BotChatBinding(
            botId: UUID(),
            chatId: 99999,  // 다른 chatId
            activeWorkspaceId: wsA.id
        )

        let result = resolveWorkspace(
            chatId: 12345,  // 매칭되는 binding 없음
            bindings: [binding],
            workspaces: [wsA, wsB],
            fallback: wsB
        )

        #expect(result?.id == wsB.id)
        #expect(result?.name == "workspace-B")
    }

    @Test("chatId nil → currentWorkspace fallback (legacy 동작)")
    func nilChatId_returnsFallback() {
        let wsA = makeWorkspace(name: "workspace-A")
        let wsB = makeWorkspace(name: "workspace-B")
        let binding = BotChatBinding(
            botId: UUID(),
            chatId: 12345,
            activeWorkspaceId: wsA.id
        )

        let result = resolveWorkspace(
            chatId: nil,  // legacy path
            bindings: [binding],
            workspaces: [wsA, wsB],
            fallback: wsB
        )

        #expect(result?.id == wsB.id)
        #expect(result?.name == "workspace-B")
    }

    @Test("chatId 있음 + binding 매칭 + activeWorkspaceId nil → fallback")
    func bindingWithNilActiveWorkspaceId_returnsFallback() {
        let wsA = makeWorkspace(name: "workspace-A")
        let wsB = makeWorkspace(name: "workspace-B")
        let binding = BotChatBinding(
            botId: UUID(),
            chatId: 12345,
            activeWorkspaceId: nil  // workspace 미지정 binding
        )

        let result = resolveWorkspace(
            chatId: 12345,
            bindings: [binding],
            workspaces: [wsA, wsB],
            fallback: wsB
        )

        #expect(result?.id == wsB.id)
    }

    @Test("chatId 있음 + binding 매칭 + wsId가 workspaces에 없음 → fallback")
    func bindingWithUnknownWorkspaceId_returnsFallback() {
        let wsA = makeWorkspace(name: "workspace-A")
        let wsB = makeWorkspace(name: "workspace-B")
        let phantomId = UUID()
        let binding = BotChatBinding(
            botId: UUID(),
            chatId: 12345,
            activeWorkspaceId: phantomId  // 존재하지 않는 workspace ID
        )

        let result = resolveWorkspace(
            chatId: 12345,
            bindings: [binding],
            workspaces: [wsA, wsB],
            fallback: wsB
        )

        #expect(result?.id == wsB.id)
    }
}
