import Foundation
import Testing
@testable import YuminaiCore

/// **ADR-099 P1-4** — TelegramHITLCoordinator P1 추가 테스트.
///
/// Request 구조체에 추가된 telegramMessageId / telegramChatId 필드 검증.
@Suite("TelegramHITLCoordinator P1-4 (ADR-099)")
struct TelegramHITLCoordinatorP1Tests {

    @Test("Request — telegramMessageId nil이 기본값")
    func requestDefaultsToNilTelegramFields() async {
        let coordinator = TelegramHITLCoordinator()

        let task = Task {
            await coordinator.request(action: "default fields test", workspace: nil, diffPreview: nil, timeout: 30)
        }

        try? await Task.sleep(for: .milliseconds(50))
        let pending = await coordinator.pendingRequests()
        #expect(pending.count == 1)
        #expect(pending[0].telegramMessageId == nil)
        #expect(pending[0].telegramChatId == nil)

        await coordinator.cancel(id: pending[0].id)
        _ = await task.value
    }

    @Test("setTelegramMessageId — 존재하지 않는 id는 무시됨")
    func setTelegramMessageIdUnknownIdIsNoop() async {
        let coordinator = TelegramHITLCoordinator()
        // 아무 request 없는 상태에서 호출 — crash 없어야 함
        await coordinator.setTelegramMessageId(42, chatId: 100, for: UUID())
        let pending = await coordinator.pendingRequests()
        #expect(pending.isEmpty)
    }

    @Test("setTelegramMessageId — 다중 request 중 하나만 업데이트")
    func setTelegramMessageIdTargetsCorrectRequest() async {
        let coordinator = TelegramHITLCoordinator()

        let task1 = Task { await coordinator.request(action: "action A", workspace: nil, diffPreview: nil, timeout: 30) }
        let task2 = Task { await coordinator.request(action: "action B", workspace: nil, diffPreview: nil, timeout: 30) }

        try? await Task.sleep(for: .milliseconds(100))
        let pending = await coordinator.pendingRequests()
        #expect(pending.count == 2)

        let idA = pending.first { $0.action == "action A" }!.id
        let idB = pending.first { $0.action == "action B" }!.id

        await coordinator.setTelegramMessageId(111, chatId: 222, for: idA)

        let updated = await coordinator.pendingRequests()
        let reqA = updated.first { $0.action == "action A" }!
        let reqB = updated.first { $0.action == "action B" }!

        #expect(reqA.telegramMessageId == 111)
        #expect(reqA.telegramChatId == 222)
        #expect(reqB.telegramMessageId == nil)
        #expect(reqB.telegramChatId == nil)

        await coordinator.cancel(id: idA)
        await coordinator.cancel(id: idB)
        _ = await task1.value
        _ = await task2.value
    }

    @Test("Request — telegramMessageId가 있을 때 respond 후 pending 제거됨")
    func requestWithTelegramIdCleansUpOnRespond() async {
        let coordinator = TelegramHITLCoordinator()

        let task = Task {
            await coordinator.request(action: "cleanup test", workspace: nil, diffPreview: nil, timeout: 30)
        }
        try? await Task.sleep(for: .milliseconds(50))

        let pending = await coordinator.pendingRequests()
        let reqId = pending[0].id
        await coordinator.setTelegramMessageId(999, chatId: 888, for: reqId)

        // respond 후 pending에서 제거되어야 함
        await coordinator.respond(id: reqId, response: .approved(by: "desktop"))
        let afterRespond = await coordinator.pendingRequests()
        #expect(afterRespond.isEmpty)

        let result = await task.value
        #expect(result == .approved(by: "desktop"))
    }

    @Test("Request Equatable — telegramMessageId 다르면 불일치")
    func requestEquatableConsidersTelegramFields() {
        let id = UUID()
        let now = Date()

        let req1 = TelegramHITLCoordinator.Request(
            id: id, action: "test", workspace: nil, diffPreview: nil,
            createdAt: now, timeoutSeconds: 60,
            telegramMessageId: 100, telegramChatId: 200
        )
        let req2 = TelegramHITLCoordinator.Request(
            id: id, action: "test", workspace: nil, diffPreview: nil,
            createdAt: now, timeoutSeconds: 60,
            telegramMessageId: 999, telegramChatId: 200
        )

        #expect(req1 != req2)
    }

    @Test("Request Equatable — 모든 필드 동일하면 일치")
    func requestEquatableAllFieldsSame() {
        let id = UUID()
        let now = Date()

        let req1 = TelegramHITLCoordinator.Request(
            id: id, action: "test", workspace: "ws", diffPreview: "diff",
            createdAt: now, timeoutSeconds: 30,
            telegramMessageId: 42, telegramChatId: 99
        )
        let req2 = TelegramHITLCoordinator.Request(
            id: id, action: "test", workspace: "ws", diffPreview: "diff",
            createdAt: now, timeoutSeconds: 30,
            telegramMessageId: 42, telegramChatId: 99
        )

        #expect(req1 == req2)
    }
}
