import Foundation

/// 워크스페이스 영속 인터페이스. 구현은 `YuminaiPersistence.SwiftDataWorkspaceStore`.
public protocol WorkspaceStore: Sendable {
    func list() async throws -> [Workspace]
    func get(_ id: UUID) async throws -> Workspace?
    func create(_ workspace: Workspace) async throws
    func update(_ workspace: Workspace) async throws
    func delete(_ id: UUID) async throws
}

/// 세션 영속 인터페이스. 메시지 본문은 Claude CLI가 sole source of truth (ADR-010),
/// 여기엔 UI/검색 캐시만 저장.
public protocol SessionStore: Sendable {
    func sessions(in workspaceId: UUID) async throws -> [Session]
    func get(_ id: UUID) async throws -> Session?
    func create(_ session: Session) async throws
    func update(_ session: Session) async throws
    func delete(_ id: UUID) async throws

    func messages(in sessionId: UUID, limit: Int, before: Date?) async throws -> [Message]
    func append(_ message: Message) async throws
}
