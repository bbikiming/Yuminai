import Foundation

/// 워크스페이스 안의 단일 에이전트 패널 (ADR-030, M1 multi-pane).
///
/// **참조**: AutoGen `AgentTool` 패턴 + Aider Architect/Editor 2-LLM 내부 구조.
///
/// 한 워크스페이스에 N개의 pane이 존재할 수 있고, 각각:
/// - 자체 `agentKind` (Claude/Codex)
/// - 자체 `settings` (model/permissionMode/effortLevel)
/// - 자체 session (live ClaudeStreamSession + messages history)
/// - 자체 conversation context (세션 ID로 격리)
///
/// 같은 워크스페이스 디렉토리를 공유하므로 file system이 협업 매개체가 된다.
/// `role: .primary` 패널 1개가 Telegram bridge의 forward 대상.
public struct AgentPane: Sendable, Identifiable, Equatable, Hashable {
    public let id: UUID
    public var agentKind: AgentKind
    public var settings: SessionSettings
    public var role: PaneRole
    /// 사용자 친화 라벨 — nil이면 agentKind.displayName 사용.
    /// 같은 workspace에 같은 agentKind가 여러 개일 때 (예: "Claude (설계)", "Claude (검토)") 유용.
    public var customName: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        agentKind: AgentKind = .claude,
        settings: SessionSettings = .default,
        role: PaneRole = .secondary,
        customName: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.agentKind = agentKind
        self.settings = settings
        self.role = role
        self.customName = customName
        self.createdAt = createdAt
    }

    /// UI에 표시할 이름.
    public var displayName: String {
        if let custom = customName, !custom.isEmpty { return custom }
        return agentKind.displayName
    }

    /// agentKind만 다른 새 인스턴스 (immutability).
    public func with(agentKind: AgentKind) -> AgentPane {
        AgentPane(
            id: id,
            agentKind: agentKind,
            settings: settings,
            role: role,
            customName: customName,
            createdAt: createdAt
        )
    }

    public func with(settings: SessionSettings) -> AgentPane {
        AgentPane(
            id: id,
            agentKind: agentKind,
            settings: settings,
            role: role,
            customName: customName,
            createdAt: createdAt
        )
    }

    public func with(role: PaneRole) -> AgentPane {
        AgentPane(
            id: id,
            agentKind: agentKind,
            settings: settings,
            role: role,
            customName: customName,
            createdAt: createdAt
        )
    }

    public func with(customName: String?) -> AgentPane {
        AgentPane(
            id: id,
            agentKind: agentKind,
            settings: settings,
            role: role,
            customName: customName,
            createdAt: createdAt
        )
    }
}

/// 워크스페이스 안의 pane 역할.
///
/// `.primary` — Telegram bridge target (워크스페이스당 1개). 사용자가 명시적 변경 가능.
/// `.secondary` — 보조 pane. 인터-에이전트 메시지(`@codex`, ADR-030 후속) 대상이 될 수 있음.
public enum PaneRole: String, Sendable, Codable, Equatable, CaseIterable {
    case primary
    case secondary

    public var label: String {
        switch self {
        case .primary: return "기본"
        case .secondary: return "보조"
        }
    }

    public var icon: String {
        switch self {
        case .primary: return "star.fill"
        case .secondary: return "circle"
        }
    }
}
