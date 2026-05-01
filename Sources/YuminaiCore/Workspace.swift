import Foundation

/// 사용자 작업 단위. 보통 하나의 git 워크트리 또는 디렉토리에 1:1 대응.
///
/// 영속 표현은 `YuminaiPersistence.WorkspaceModel`이며, 이 struct는 actor 경계를 안전히
/// 넘기는 도메인 표현이다.
public struct Workspace: Sendable, Identifiable, Hashable {
    public let id: UUID
    public let name: String
    public let directoryPath: String
    public let createdAt: Date
    public let lastOpenedAt: Date?
    public let harnessTemplate: HarnessTemplateName?
    public let isArchived: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        directoryPath: String,
        createdAt: Date = Date(),
        lastOpenedAt: Date? = nil,
        harnessTemplate: HarnessTemplateName? = nil,
        isArchived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.directoryPath = directoryPath
        self.createdAt = createdAt
        self.lastOpenedAt = lastOpenedAt
        self.harnessTemplate = harnessTemplate
        self.isArchived = isArchived
    }
}

/// 워크스페이스 생성 시 선택 가능한 하네스 템플릿 종류.
public enum HarnessTemplateName: String, Sendable, Codable, CaseIterable {
    case empty
    case swift
    case typescript
    case python
    case general
}
