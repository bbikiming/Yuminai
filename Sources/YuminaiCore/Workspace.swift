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
    /// 이 워크스페이스에서 활성 코딩 에이전트. ADR-026.
    public let agentKind: AgentKind
    /// 자동 build/test/lint 정책. ADR-029 (M4 delivery loop).
    public let deliveryConfig: DeliveryConfig
    /// 영속된 panes 메타. workspace 재진입 시 복원 (ADR-031, T1).
    /// 빈 배열이면 AppModel이 default primary 1개 자동 생성. session/messages는 복원 X (메타만).
    public let savedPanes: [AgentPane]
    /// 영속된 터미널 세션들 (ADR-041 T13). 라벨 + cwd만 복원 — process는 새로 spawn.
    public let savedTerminalSessions: [TerminalSession]
    /// ADR-048 — 프로젝트 프로필 (platform/언어/백엔드 등). Harness가 활용.
    public let projectProfile: ProjectProfile

    public init(
        id: UUID = UUID(),
        name: String,
        directoryPath: String,
        createdAt: Date = Date(),
        lastOpenedAt: Date? = nil,
        harnessTemplate: HarnessTemplateName? = nil,
        isArchived: Bool = false,
        agentKind: AgentKind = .default,
        deliveryConfig: DeliveryConfig = .disabled,
        savedPanes: [AgentPane] = [],
        savedTerminalSessions: [TerminalSession] = [],
        projectProfile: ProjectProfile = .empty
    ) {
        self.id = id
        self.name = name
        self.directoryPath = directoryPath
        self.createdAt = createdAt
        self.lastOpenedAt = lastOpenedAt
        self.harnessTemplate = harnessTemplate
        self.isArchived = isArchived
        self.agentKind = agentKind
        self.deliveryConfig = deliveryConfig
        self.savedPanes = savedPanes
        self.savedTerminalSessions = savedTerminalSessions
        self.projectProfile = projectProfile
    }

    /// agentKind만 다른 새 인스턴스 반환 (불변성 유지).
    public func with(agentKind: AgentKind) -> Workspace {
        Workspace(
            id: id, name: name, directoryPath: directoryPath, createdAt: createdAt,
            lastOpenedAt: lastOpenedAt, harnessTemplate: harnessTemplate,
            isArchived: isArchived, agentKind: agentKind, deliveryConfig: deliveryConfig,
            savedPanes: savedPanes, savedTerminalSessions: savedTerminalSessions,
            projectProfile: projectProfile
        )
    }

    public func with(deliveryConfig: DeliveryConfig) -> Workspace {
        Workspace(
            id: id, name: name, directoryPath: directoryPath, createdAt: createdAt,
            lastOpenedAt: lastOpenedAt, harnessTemplate: harnessTemplate,
            isArchived: isArchived, agentKind: agentKind, deliveryConfig: deliveryConfig,
            savedPanes: savedPanes, savedTerminalSessions: savedTerminalSessions,
            projectProfile: projectProfile
        )
    }

    public func with(savedPanes: [AgentPane]) -> Workspace {
        Workspace(
            id: id, name: name, directoryPath: directoryPath, createdAt: createdAt,
            lastOpenedAt: lastOpenedAt, harnessTemplate: harnessTemplate,
            isArchived: isArchived, agentKind: agentKind, deliveryConfig: deliveryConfig,
            savedPanes: savedPanes, savedTerminalSessions: savedTerminalSessions,
            projectProfile: projectProfile
        )
    }

    public func with(savedTerminalSessions: [TerminalSession]) -> Workspace {
        Workspace(
            id: id, name: name, directoryPath: directoryPath, createdAt: createdAt,
            lastOpenedAt: lastOpenedAt, harnessTemplate: harnessTemplate,
            isArchived: isArchived, agentKind: agentKind, deliveryConfig: deliveryConfig,
            savedPanes: savedPanes, savedTerminalSessions: savedTerminalSessions,
            projectProfile: projectProfile
        )
    }

    public func with(projectProfile: ProjectProfile) -> Workspace {
        Workspace(
            id: id, name: name, directoryPath: directoryPath, createdAt: createdAt,
            lastOpenedAt: lastOpenedAt, harnessTemplate: harnessTemplate,
            isArchived: isArchived, agentKind: agentKind, deliveryConfig: deliveryConfig,
            savedPanes: savedPanes, savedTerminalSessions: savedTerminalSessions,
            projectProfile: projectProfile
        )
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
