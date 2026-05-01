import Foundation

/// 한 워크스페이스 안의 한 대화 단위.
public struct Session: Sendable, Identifiable, Hashable {
    public let id: UUID
    public let workspaceId: UUID
    public let startedAt: Date
    public let endedAt: Date?
    public let title: String?

    public init(
        id: UUID = UUID(),
        workspaceId: UUID,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        title: String? = nil
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.title = title
    }
}

/// 세션 안의 단일 메시지. 사용자 입력 또는 Claude 응답.
public struct Message: Sendable, Identifiable, Hashable {
    public let id: UUID
    public let sessionId: UUID
    public let role: Role
    public let content: String
    public let timestamp: Date
    public let rawANSI: String?

    public init(
        id: UUID = UUID(),
        sessionId: UUID,
        role: Role,
        content: String,
        timestamp: Date = Date(),
        rawANSI: String? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.rawANSI = rawANSI
    }

    public enum Role: String, Sendable, Codable, Hashable, CaseIterable {
        case user
        case assistant
        case system
        case tool
    }
}
