import Foundation
import Testing
import SwiftData
import YuminaiCore
@testable import YuminaiPersistence

@Suite("SwiftDataWorkspaceStore — CRUD")
struct SwiftDataWorkspaceStoreTests {
    @Test("create 후 list에 포함된다")
    func createAndList() async throws {
        let store = try makeStore()
        let ws = Workspace(name: "test", directoryPath: "/tmp/test")
        try await store.create(ws)
        let listed = try await store.list()
        #expect(listed.contains(where: { $0.id == ws.id }))
    }

    @Test("get은 정확히 매칭하는 항목 반환")
    func getById() async throws {
        let store = try makeStore()
        let ws = Workspace(name: "x", directoryPath: "/x")
        try await store.create(ws)
        let fetched = try await store.get(ws.id)
        #expect(fetched?.name == "x")
    }

    @Test("같은 ID로 중복 create 시 에러")
    func duplicateCreateThrows() async throws {
        let store = try makeStore()
        let id = UUID()
        try await store.create(Workspace(id: id, name: "a", directoryPath: "/a"))
        await #expect(throws: YuminaiError.self) {
            try await store.create(Workspace(id: id, name: "b", directoryPath: "/b"))
        }
    }

    @Test("update가 필드를 갱신한다")
    func updateChangesFields() async throws {
        let store = try makeStore()
        let ws = Workspace(name: "old", directoryPath: "/old")
        try await store.create(ws)

        let updated = Workspace(
            id: ws.id,
            name: "new",
            directoryPath: "/new",
            createdAt: ws.createdAt,
            lastOpenedAt: Date(),
            harnessTemplate: .swift
        )
        try await store.update(updated)

        let fetched = try await store.get(ws.id)
        #expect(fetched?.name == "new")
        #expect(fetched?.directoryPath == "/new")
        #expect(fetched?.harnessTemplate == .swift)
    }

    @Test("delete 후 get은 nil")
    func deleteRemoves() async throws {
        let store = try makeStore()
        let ws = Workspace(name: "x", directoryPath: "/x")
        try await store.create(ws)
        try await store.delete(ws.id)
        let fetched = try await store.get(ws.id)
        #expect(fetched == nil)
    }

    @Test("isArchived=true는 list에 안 나타난다")
    func archivedExcludedFromList() async throws {
        let store = try makeStore()
        let ws = Workspace(name: "archived", directoryPath: "/a", isArchived: true)
        try await store.create(ws)
        let listed = try await store.list()
        #expect(listed.contains(where: { $0.id == ws.id }) == false)
    }

    private func makeStore() throws -> SwiftDataWorkspaceStore {
        let container = try YuminaiModelContainerFactory.inMemory()
        return SwiftDataWorkspaceStore(container: container)
    }
}

@Suite("SwiftDataSessionStore — CRUD + messages")
struct SwiftDataSessionStoreTests {
    @Test("세션 생성/조회")
    func createAndGet() async throws {
        let store = try makeStore()
        let session = Session(workspaceId: UUID())
        try await store.create(session)
        let fetched = try await store.get(session.id)
        #expect(fetched?.id == session.id)
    }

    @Test("workspace별 세션 리스트")
    func sessionsInWorkspace() async throws {
        let store = try makeStore()
        let wsA = UUID()
        let wsB = UUID()
        try await store.create(Session(workspaceId: wsA))
        try await store.create(Session(workspaceId: wsA))
        try await store.create(Session(workspaceId: wsB))

        let aSessions = try await store.sessions(in: wsA)
        let bSessions = try await store.sessions(in: wsB)
        #expect(aSessions.count == 2)
        #expect(bSessions.count == 1)
    }

    @Test("메시지 append + 시간순 조회")
    func messagesArePersistedAndSorted() async throws {
        let store = try makeStore()
        let session = Session(workspaceId: UUID())
        try await store.create(session)

        let earlier = Message(
            sessionId: session.id,
            role: .user,
            content: "first",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let later = Message(
            sessionId: session.id,
            role: .assistant,
            content: "second",
            timestamp: Date(timeIntervalSince1970: 1_700_000_100)
        )
        try await store.append(earlier)
        try await store.append(later)

        let fetched = try await store.messages(in: session.id, limit: 100, before: nil)
        #expect(fetched.count == 2)
        #expect(fetched[0].content == "first")
        #expect(fetched[1].content == "second")
    }

    private func makeStore() throws -> SwiftDataSessionStore {
        let container = try YuminaiModelContainerFactory.inMemory()
        return SwiftDataSessionStore(container: container)
    }
}
