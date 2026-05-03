import Foundation

/// 사용자 작업 단위. 보통 하나의 git 워크트리 또는 디렉토리에 1:1 대응.
///
/// 영속 표현은 `YuminaiPersistence.WorkspaceModel`이며, 이 struct는 actor 경계를 안전히
/// 넘기는 도메인 표현이다.
public struct Workspace: Sendable, Identifiable, Hashable, Codable {
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
    /// ADR-050 Phase 6 — Harness ConversationLog + TaskGraph 영속.
    /// 워크스페이스 reload 시 단일 timeline 복원.
    public let savedConversationLog: [ConversationEntry]
    public let savedTasks: [HarnessTask]
    /// **ADR-087 Phase 1** — Agent별 세션 설정 (model/permissionMode/effortLevel).
    /// agent 전환 시 그 agent의 last-used 설정으로 swap.
    /// 비어있는 agent는 SessionSettings.default 사용 (sonnet/default/medium).
    public let perAgentSettings: [AgentKind: SessionSettings]

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
        projectProfile: ProjectProfile = .empty,
        savedConversationLog: [ConversationEntry] = [],
        savedTasks: [HarnessTask] = [],
        perAgentSettings: [AgentKind: SessionSettings] = [:]
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
        self.savedConversationLog = savedConversationLog
        self.savedTasks = savedTasks
        self.perAgentSettings = perAgentSettings
    }

    /// **ADR-087 Phase 1** — backward-compat 디코더 (perAgentSettings 누락 시 빈 dict).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.directoryPath = try c.decode(String.self, forKey: .directoryPath)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.lastOpenedAt = try c.decodeIfPresent(Date.self, forKey: .lastOpenedAt)
        self.harnessTemplate = try c.decodeIfPresent(HarnessTemplateName.self, forKey: .harnessTemplate)
        self.isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        self.agentKind = try c.decodeIfPresent(AgentKind.self, forKey: .agentKind) ?? .default
        self.deliveryConfig = try c.decodeIfPresent(DeliveryConfig.self, forKey: .deliveryConfig) ?? .disabled
        self.savedPanes = try c.decodeIfPresent([AgentPane].self, forKey: .savedPanes) ?? []
        self.savedTerminalSessions = try c.decodeIfPresent([TerminalSession].self, forKey: .savedTerminalSessions) ?? []
        self.projectProfile = try c.decodeIfPresent(ProjectProfile.self, forKey: .projectProfile) ?? .empty
        self.savedConversationLog = try c.decodeIfPresent([ConversationEntry].self, forKey: .savedConversationLog) ?? []
        self.savedTasks = try c.decodeIfPresent([HarnessTask].self, forKey: .savedTasks) ?? []
        self.perAgentSettings = try c.decodeIfPresent([AgentKind: SessionSettings].self, forKey: .perAgentSettings) ?? [:]
    }

    /// agentKind만 다른 새 인스턴스 반환 (불변성 유지).
    public func with(agentKind: AgentKind) -> Workspace {
        Workspace(
            id: id, name: name, directoryPath: directoryPath, createdAt: createdAt,
            lastOpenedAt: lastOpenedAt, harnessTemplate: harnessTemplate,
            isArchived: isArchived, agentKind: agentKind, deliveryConfig: deliveryConfig,
            savedPanes: savedPanes, savedTerminalSessions: savedTerminalSessions,
            projectProfile: projectProfile,
            savedConversationLog: savedConversationLog, savedTasks: savedTasks,
            perAgentSettings: perAgentSettings
        )
    }

    public func with(deliveryConfig: DeliveryConfig) -> Workspace {
        Workspace(
            id: id, name: name, directoryPath: directoryPath, createdAt: createdAt,
            lastOpenedAt: lastOpenedAt, harnessTemplate: harnessTemplate,
            isArchived: isArchived, agentKind: agentKind, deliveryConfig: deliveryConfig,
            savedPanes: savedPanes, savedTerminalSessions: savedTerminalSessions,
            projectProfile: projectProfile,
            savedConversationLog: savedConversationLog, savedTasks: savedTasks,
            perAgentSettings: perAgentSettings
        )
    }

    public func with(savedPanes: [AgentPane]) -> Workspace {
        Workspace(
            id: id, name: name, directoryPath: directoryPath, createdAt: createdAt,
            lastOpenedAt: lastOpenedAt, harnessTemplate: harnessTemplate,
            isArchived: isArchived, agentKind: agentKind, deliveryConfig: deliveryConfig,
            savedPanes: savedPanes, savedTerminalSessions: savedTerminalSessions,
            projectProfile: projectProfile,
            savedConversationLog: savedConversationLog, savedTasks: savedTasks,
            perAgentSettings: perAgentSettings
        )
    }

    public func with(savedTerminalSessions: [TerminalSession]) -> Workspace {
        Workspace(
            id: id, name: name, directoryPath: directoryPath, createdAt: createdAt,
            lastOpenedAt: lastOpenedAt, harnessTemplate: harnessTemplate,
            isArchived: isArchived, agentKind: agentKind, deliveryConfig: deliveryConfig,
            savedPanes: savedPanes, savedTerminalSessions: savedTerminalSessions,
            projectProfile: projectProfile,
            savedConversationLog: savedConversationLog, savedTasks: savedTasks,
            perAgentSettings: perAgentSettings
        )
    }

    public func with(projectProfile: ProjectProfile) -> Workspace {
        Workspace(
            id: id, name: name, directoryPath: directoryPath, createdAt: createdAt,
            lastOpenedAt: lastOpenedAt, harnessTemplate: harnessTemplate,
            isArchived: isArchived, agentKind: agentKind, deliveryConfig: deliveryConfig,
            savedPanes: savedPanes, savedTerminalSessions: savedTerminalSessions,
            projectProfile: projectProfile,
            savedConversationLog: savedConversationLog, savedTasks: savedTasks,
            perAgentSettings: perAgentSettings
        )
    }

    public func with(savedConversationLog: [ConversationEntry], savedTasks: [HarnessTask]) -> Workspace {
        Workspace(
            id: id, name: name, directoryPath: directoryPath, createdAt: createdAt,
            lastOpenedAt: lastOpenedAt, harnessTemplate: harnessTemplate,
            isArchived: isArchived, agentKind: agentKind, deliveryConfig: deliveryConfig,
            savedPanes: savedPanes, savedTerminalSessions: savedTerminalSessions,
            projectProfile: projectProfile,
            savedConversationLog: savedConversationLog, savedTasks: savedTasks,
            perAgentSettings: perAgentSettings
        )
    }

    /// **ADR-087 Phase 1** — agent별 settings 갱신.
    public func with(perAgentSettings: [AgentKind: SessionSettings]) -> Workspace {
        Workspace(
            id: id, name: name, directoryPath: directoryPath, createdAt: createdAt,
            lastOpenedAt: lastOpenedAt, harnessTemplate: harnessTemplate,
            isArchived: isArchived, agentKind: agentKind, deliveryConfig: deliveryConfig,
            savedPanes: savedPanes, savedTerminalSessions: savedTerminalSessions,
            projectProfile: projectProfile,
            savedConversationLog: savedConversationLog, savedTasks: savedTasks,
            perAgentSettings: perAgentSettings
        )
    }

    /// **ADR-087 Phase 1** — 특정 agent의 effective settings (없으면 default).
    public func settings(for kind: AgentKind) -> SessionSettings {
        perAgentSettings[kind] ?? .default
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
