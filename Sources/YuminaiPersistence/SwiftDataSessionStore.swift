import Foundation
import SwiftData
import YuminaiCore

/// SwiftData 기반 `SessionStore`.
public final actor SwiftDataSessionStore: SessionStore {
    private let container: ModelContainer

    public init(container: ModelContainer) {
        self.container = container
    }

    public func sessions(in workspaceId: UUID) async throws -> [Session] {
        let ctx = ModelContext(container)
        let descriptor = FetchDescriptor<SessionModel>(
            predicate: #Predicate { $0.workspaceId == workspaceId },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try ctx.fetch(descriptor).map(\.toCoreSession)
    }

    public func get(_ id: UUID) async throws -> Session? {
        let ctx = ModelContext(container)
        let descriptor = FetchDescriptor<SessionModel>(
            predicate: #Predicate { $0.id == id }
        )
        return try ctx.fetch(descriptor).first?.toCoreSession
    }

    public func create(_ session: Session) async throws {
        let ctx = ModelContext(container)
        ctx.insert(SessionModel(from: session))
        try ctx.save()
    }

    public func update(_ session: Session) async throws {
        let ctx = ModelContext(container)
        let id = session.id
        let descriptor = FetchDescriptor<SessionModel>(
            predicate: #Predicate { $0.id == id }
        )
        guard let model = try ctx.fetch(descriptor).first else {
            throw YuminaiError.sessionCorrupted(id: session.id, reason: "not found in store")
        }
        model.endedAt = session.endedAt
        model.title = session.title
        try ctx.save()
    }

    public func delete(_ id: UUID) async throws {
        let ctx = ModelContext(container)
        let descriptor = FetchDescriptor<SessionModel>(
            predicate: #Predicate { $0.id == id }
        )
        guard let model = try ctx.fetch(descriptor).first else {
            return
        }
        ctx.delete(model)
        try ctx.save()
    }

    public func messages(in sessionId: UUID, limit: Int, before: Date?) async throws -> [Message] {
        let ctx = ModelContext(container)

        var descriptor: FetchDescriptor<MessageModel>
        if let before {
            descriptor = FetchDescriptor<MessageModel>(
                predicate: #Predicate { msg in
                    msg.session?.id == sessionId && msg.timestamp < before
                },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<MessageModel>(
                predicate: #Predicate { msg in
                    msg.session?.id == sessionId
                },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
        }
        descriptor.fetchLimit = limit

        let fetched = try ctx.fetch(descriptor).map(\.toCoreMessage)
        return Array(fetched.reversed())
    }

    public func append(_ message: Message) async throws {
        let ctx = ModelContext(container)
        let sessionId = message.sessionId
        let sessionDesc = FetchDescriptor<SessionModel>(
            predicate: #Predicate { $0.id == sessionId }
        )
        let session = try ctx.fetch(sessionDesc).first
        ctx.insert(MessageModel(from: message, session: session))
        try ctx.save()
    }
}
