import Foundation
import SwiftData
import YuminaiCore

/// `Workspace` 도메인 struct의 SwiftData 영속 표현.
///
/// `@Model` 클래스는 Sendable이 아니므로 actor 경계를 넘기지 말 것 — `toCoreWorkspace`로
/// 변환해서 도메인 struct를 전달하라.
@Model
public final class WorkspaceModel {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var directoryPath: String
    public var createdAt: Date
    public var lastOpenedAt: Date?
    public var harnessTemplateRaw: String?
    public var isArchived: Bool

    public init(
        id: UUID,
        name: String,
        directoryPath: String,
        createdAt: Date,
        lastOpenedAt: Date? = nil,
        harnessTemplateRaw: String? = nil,
        isArchived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.directoryPath = directoryPath
        self.createdAt = createdAt
        self.lastOpenedAt = lastOpenedAt
        self.harnessTemplateRaw = harnessTemplateRaw
        self.isArchived = isArchived
    }

    public convenience init(from core: Workspace) {
        self.init(
            id: core.id,
            name: core.name,
            directoryPath: core.directoryPath,
            createdAt: core.createdAt,
            lastOpenedAt: core.lastOpenedAt,
            harnessTemplateRaw: core.harnessTemplate?.rawValue,
            isArchived: core.isArchived
        )
    }

    public var toCoreWorkspace: Workspace {
        Workspace(
            id: id,
            name: name,
            directoryPath: directoryPath,
            createdAt: createdAt,
            lastOpenedAt: lastOpenedAt,
            harnessTemplate: harnessTemplateRaw.flatMap(HarnessTemplateName.init(rawValue:)),
            isArchived: isArchived
        )
    }
}
