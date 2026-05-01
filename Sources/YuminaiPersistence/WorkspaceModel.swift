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
    /// AgentKind raw value. nil/unknown은 .default(claude)로 fallback (마이그레이션 호환).
    public var agentKindRaw: String?
    /// DeliveryConfig JSON 직렬화. nil이면 .disabled로 fallback. ADR-029.
    public var deliveryConfigJSON: Data?
    /// `[AgentPane]` JSON 직렬화 — workspace 재진입 시 panes 복원 (ADR-031, T1).
    /// nil/decode 실패 시 빈 배열 → AppModel이 default primary 1개 자동 생성.
    public var panesJSON: Data?

    public init(
        id: UUID,
        name: String,
        directoryPath: String,
        createdAt: Date,
        lastOpenedAt: Date? = nil,
        harnessTemplateRaw: String? = nil,
        isArchived: Bool = false,
        agentKindRaw: String? = nil,
        deliveryConfigJSON: Data? = nil,
        panesJSON: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.directoryPath = directoryPath
        self.createdAt = createdAt
        self.lastOpenedAt = lastOpenedAt
        self.harnessTemplateRaw = harnessTemplateRaw
        self.isArchived = isArchived
        self.agentKindRaw = agentKindRaw
        self.deliveryConfigJSON = deliveryConfigJSON
        self.panesJSON = panesJSON
    }

    public convenience init(from core: Workspace) {
        self.init(
            id: core.id,
            name: core.name,
            directoryPath: core.directoryPath,
            createdAt: core.createdAt,
            lastOpenedAt: core.lastOpenedAt,
            harnessTemplateRaw: core.harnessTemplate?.rawValue,
            isArchived: core.isArchived,
            agentKindRaw: core.agentKind.rawValue,
            deliveryConfigJSON: try? JSONEncoder().encode(core.deliveryConfig),
            panesJSON: try? JSONEncoder().encode(core.savedPanes)
        )
    }

    public var toCoreWorkspace: Workspace {
        let delivery: DeliveryConfig
        if let data = deliveryConfigJSON,
           let decoded = try? JSONDecoder().decode(DeliveryConfig.self, from: data) {
            delivery = decoded
        } else {
            delivery = .disabled
        }
        let panes: [AgentPane]
        if let data = panesJSON,
           let decoded = try? JSONDecoder().decode([AgentPane].self, from: data) {
            panes = decoded
        } else {
            panes = []
        }
        return Workspace(
            id: id,
            name: name,
            directoryPath: directoryPath,
            createdAt: createdAt,
            lastOpenedAt: lastOpenedAt,
            harnessTemplate: harnessTemplateRaw.flatMap(HarnessTemplateName.init(rawValue:)),
            isArchived: isArchived,
            agentKind: agentKindRaw.flatMap(AgentKind.init(rawValue:)) ?? .default,
            deliveryConfig: delivery,
            savedPanes: panes
        )
    }
}
