import Foundation

/// **ADR-089** — Ad-hoc 대화 세션. 워크스페이스(프로젝트)와 별개의 가벼운 conversation 단위.
///
/// ## 워크스페이스 vs ChatSession
///
/// | | Workspace (프로젝트) | ChatSession (대화) |
/// |-|---------------------|-------------------|
/// | **목적** | 장기 프로젝트 관리 | Ad-hoc 질문/실험 |
/// | **저장** | 폴더 + 설정 + 영구 history | 제목 + workspace 참조 + messages |
/// | **agent 설정** | per-agent settings 영속 | 자체 settings 보유 |
/// | **수명** | 사용자가 명시적 삭제 전까지 | 사용자가 닫을 때까지 (또는 archive) |
/// | **사이드바** | 좌측 main panel | "대화" section (workspaces 아래) |
///
/// ## 만들기
///
/// 사용자가 "+ 새 대화" 클릭 → `NewChatSessionSheet` → 라디오로 워크스페이스 **반드시** 1개 선택
/// → ChatSession 생성. workspaceId는 그 chat이 어느 폴더에서 실행될지를 결정 (cwd).
public struct ChatSession: Sendable, Identifiable, Hashable, Codable {
    public let id: UUID
    public var title: String
    /// 어느 워크스페이스 폴더에서 실행될지 (cwd 결정).
    public let workspaceId: UUID
    /// 이 세션 전용 agent 설정 (Claude/Codex).
    public var agentKind: AgentKind
    /// 이 세션의 model + permissionMode + effort.
    public var settings: SessionSettings
    public let createdAt: Date
    /// 마지막 활성 시각 — 사이드바 정렬용.
    public var lastActiveAt: Date
    /// 대화 history (영속). 메시지 1개당 ~수 KB이므로 단일 ChatSession은 수십 KB 수준.
    public var savedMessages: [Message]
    /// **archived** — 최근 목록에서 숨김 (영구 삭제 ≠ archive).
    public var isArchived: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        workspaceId: UUID,
        agentKind: AgentKind = .default,
        settings: SessionSettings = .default,
        createdAt: Date = Date(),
        lastActiveAt: Date = Date(),
        savedMessages: [Message] = [],
        isArchived: Bool = false
    ) {
        self.id = id
        self.title = title
        self.workspaceId = workspaceId
        self.agentKind = agentKind
        self.settings = settings
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt
        self.savedMessages = savedMessages
        self.isArchived = isArchived
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.workspaceId = try c.decode(UUID.self, forKey: .workspaceId)
        self.agentKind = try c.decodeIfPresent(AgentKind.self, forKey: .agentKind) ?? .default
        self.settings = try c.decodeIfPresent(SessionSettings.self, forKey: .settings) ?? .default
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.lastActiveAt = try c.decodeIfPresent(Date.self, forKey: .lastActiveAt) ?? Date()
        self.savedMessages = try c.decodeIfPresent([Message].self, forKey: .savedMessages) ?? []
        self.isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }

    /// 표시용 부제: 어느 workspace + agent + model.
    /// Caller가 workspace name을 lookup해서 전달 (이 struct는 ID만 보유).
    public func subtitle(workspaceName: String) -> String {
        let modelLabel = agentKind == .claude ? settings.model.displayName : settings.codexModel.displayName
        return "\(workspaceName) · \(agentKind.displayName) \(modelLabel)"
    }

    /// 메시지 1개 추가 + lastActiveAt 갱신 (immutable copy).
    public func appending(_ message: Message) -> ChatSession {
        var copy = self
        copy.savedMessages.append(message)
        copy.lastActiveAt = Date()
        return copy
    }

    public func with(title: String) -> ChatSession {
        var copy = self
        copy.title = title
        return copy
    }

    public func with(isArchived: Bool) -> ChatSession {
        var copy = self
        copy.isArchived = isArchived
        return copy
    }

    public func with(agentKind: AgentKind, settings: SessionSettings) -> ChatSession {
        var copy = self
        copy.agentKind = agentKind
        copy.settings = settings
        copy.lastActiveAt = Date()
        return copy
    }
}
