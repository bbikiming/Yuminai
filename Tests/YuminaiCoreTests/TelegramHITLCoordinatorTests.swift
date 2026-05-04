import Foundation
import Testing
@testable import YuminaiCore

/// **ADR-094 Phase 3** — TelegramHITLCoordinator actor 테스트.
@Suite("TelegramHITLCoordinator (ADR-094 Phase 3)")
struct TelegramHITLCoordinatorTests {

    // MARK: - request + respond

    @Test("respond — .approved 반환")
    func respondApproved() async {
        let coordinator = TelegramHITLCoordinator()

        let task = Task {
            await coordinator.request(action: "git push --force", workspace: "Yuminai", diffPreview: nil, timeout: 5)
        }

        // coordinator에 request가 등록될 시간
        try? await Task.sleep(for: .milliseconds(50))

        let pending = await coordinator.pendingRequests()
        #expect(pending.count == 1)
        let id = pending[0].id

        await coordinator.respond(id: id, response: .approved(by: "desktop"))
        let result = await task.value
        #expect(result == .approved(by: "desktop"))
    }

    @Test("respond — .rejected 반환")
    func respondRejected() async {
        let coordinator = TelegramHITLCoordinator()

        let task = Task {
            await coordinator.request(action: "rm -rf /tmp/test", workspace: nil, diffPreview: nil, timeout: 5)
        }

        try? await Task.sleep(for: .milliseconds(50))

        let pending = await coordinator.pendingRequests()
        #expect(pending.count == 1)

        await coordinator.respond(id: pending[0].id, response: .rejected(by: "@user"))
        let result = await task.value
        #expect(result == .rejected(by: "@user"))
    }

    // MARK: - timeout

    @Test("timeout — 지정된 초 후 .timeout 반환", .timeLimit(.minutes(1)))
    func timeoutFires() async {
        let coordinator = TelegramHITLCoordinator()

        let result = await coordinator.request(
            action: "quick timeout test",
            workspace: nil,
            diffPreview: nil,
            timeout: 1  // 1초 fast timeout
        )
        #expect(result == .timeout)
    }

    @Test("timeout — pending에서 제거됨")
    func timeoutRemovesFromPending() async {
        let coordinator = TelegramHITLCoordinator()

        Task {
            _ = await coordinator.request(
                action: "timeout cleanup test",
                workspace: nil,
                diffPreview: nil,
                timeout: 1
            )
        }

        try? await Task.sleep(for: .milliseconds(50))
        let beforeTimeout = await coordinator.pendingRequests()
        #expect(beforeTimeout.count == 1)

        // 1초 후 timeout
        try? await Task.sleep(for: .milliseconds(1100))
        let afterTimeout = await coordinator.pendingRequests()
        #expect(afterTimeout.count == 0)
    }

    // MARK: - cancel

    @Test("cancel — .cancelled 반환")
    func cancelRequest() async {
        let coordinator = TelegramHITLCoordinator()

        let task = Task {
            await coordinator.request(action: "cancel test", workspace: nil, diffPreview: nil, timeout: 30)
        }

        try? await Task.sleep(for: .milliseconds(50))

        let pending = await coordinator.pendingRequests()
        #expect(pending.count == 1)
        let id = pending[0].id

        await coordinator.cancel(id: id)
        let result = await task.value
        #expect(result == .cancelled)
    }

    @Test("cancel — pending에서 제거됨")
    func cancelRemovesFromPending() async {
        let coordinator = TelegramHITLCoordinator()

        let task = Task {
            await coordinator.request(action: "cancel cleanup", workspace: nil, diffPreview: nil, timeout: 30)
        }

        try? await Task.sleep(for: .milliseconds(50))
        let pending = await coordinator.pendingRequests()
        let id = pending[0].id

        await coordinator.cancel(id: id)
        _ = await task.value

        let afterCancel = await coordinator.pendingRequests()
        #expect(afterCancel.count == 0)
    }

    // MARK: - 다중 동시 request

    @Test("다중 request — 각각 독립적으로 resolve")
    func multipleRequests() async {
        let coordinator = TelegramHITLCoordinator()

        let task1 = Task {
            await coordinator.request(action: "action 1", workspace: nil, diffPreview: nil, timeout: 30)
        }
        let task2 = Task {
            await coordinator.request(action: "action 2", workspace: nil, diffPreview: nil, timeout: 30)
        }

        try? await Task.sleep(for: .milliseconds(100))

        let pending = await coordinator.pendingRequests()
        #expect(pending.count == 2)

        let id1 = pending.first { $0.action == "action 1" }!.id
        let id2 = pending.first { $0.action == "action 2" }!.id

        await coordinator.respond(id: id1, response: .approved(by: "user1"))
        await coordinator.respond(id: id2, response: .rejected(by: "user2"))

        let result1 = await task1.value
        let result2 = await task2.value

        #expect(result1 == .approved(by: "user1"))
        #expect(result2 == .rejected(by: "user2"))
    }

    @Test("다중 request — 하나 cancel, 하나 approve")
    func mixedResponse() async {
        let coordinator = TelegramHITLCoordinator()

        let taskA = Task {
            await coordinator.request(action: "A", workspace: nil, diffPreview: nil, timeout: 30)
        }
        let taskB = Task {
            await coordinator.request(action: "B", workspace: nil, diffPreview: nil, timeout: 30)
        }

        try? await Task.sleep(for: .milliseconds(100))

        let pending = await coordinator.pendingRequests()
        let idA = pending.first { $0.action == "A" }!.id
        let idB = pending.first { $0.action == "B" }!.id

        await coordinator.cancel(id: idA)
        await coordinator.respond(id: idB, response: .approved(by: "desktop"))

        let resultA = await taskA.value
        let resultB = await taskB.value

        #expect(resultA == .cancelled)
        #expect(resultB == .approved(by: "desktop"))
    }

    // MARK: - Request properties

    @Test("Request — action / workspace / diffPreview 보존")
    func requestProperties() async {
        let coordinator = TelegramHITLCoordinator()

        let task = Task {
            await coordinator.request(
                action: "git push --force origin main",
                workspace: "MyProject",
                diffPreview: "--- a/file.swift\n+++ b/file.swift",
                timeout: 5
            )
        }

        try? await Task.sleep(for: .milliseconds(50))

        let pending = await coordinator.pendingRequests()
        #expect(pending.count == 1)
        let req = pending[0]
        #expect(req.action == "git push --force origin main")
        #expect(req.workspace == "MyProject")
        #expect(req.diffPreview == "--- a/file.swift\n+++ b/file.swift")
        #expect(req.timeoutSeconds == 5)

        await coordinator.cancel(id: req.id)
        _ = await task.value
    }

    // MARK: - AsyncStream

    @Test("requestStream — 새 request 생성 시 emit")
    func requestStreamEmit() async {
        let coordinator = TelegramHITLCoordinator()
        let stream = await coordinator.requestStream()

        // Collect via actor-isolated approach to avoid data race
        actor Collector {
            var items: [TelegramHITLCoordinator.Request] = []
            func add(_ req: TelegramHITLCoordinator.Request) { items.append(req) }
        }
        let collector = Collector()

        let consumeTask = Task {
            var count = 0
            for await req in stream {
                await collector.add(req)
                count += 1
                if count >= 1 { break }
            }
        }

        try? await Task.sleep(for: .milliseconds(30))

        let requestTask = Task {
            _ = await coordinator.request(action: "stream test", workspace: nil, diffPreview: nil, timeout: 2)
        }

        try? await Task.sleep(for: .milliseconds(200))

        let items = await collector.items
        #expect(items.count >= 1)
        if !items.isEmpty {
            #expect(items[0].action == "stream test")
        }

        consumeTask.cancel()
        requestTask.cancel()
    }
}
