import Foundation

/// **ADR-089 + ADR-091** — Ad-hoc 대화 세션. 워크스페이스(프로젝트)와 별개의 가벼운 conversation 단위.
///
/// ## 워크스페이스 vs ChatSession
///
/// | | Workspace (프로젝트) | ChatSession (대화) |
/// |-|---------------------|-------------------|
/// | **목적** | 장기 프로젝트 관리 | Ad-hoc 질문/자유 대화 |
/// | **저장** | 폴더 + 설정 + 영구 history | 제목 + (옵션 workspace) + messages |
/// | **수명** | 사용자가 명시적 삭제 전까지 | 사용자가 닫을 때까지 |
///
/// ## ADR-091 변경: workspaceId 옵션화
///
/// 자유 대화 (workspaceId == nil) — 경로/도구 없는 순수 LLM Q&A.
/// 사용자가 나중에 `attachToWorkspace(id:)`로 워크스페이스 지정 가능.
public struct ChatSession: Sendable, Identifiable, Hashable, Codable {
    public let id: UUID
    public var title: String
    /// 어느 워크스페이스 폴더에서 실행될지 (cwd 결정).
    /// **ADR-091** — nil이면 **자유 대화** (경로 미지정, 순수 Q&A 모드).
    /// 나중에 사용자가 워크스페이스로 attach 가능.
    public var workspaceId: UUID?
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
        workspaceId: UUID? = nil,
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
        // ADR-091 — 옛 영속(workspaceId 필수)도 디코드 + 신규는 옵션
        self.workspaceId = try c.decodeIfPresent(UUID.self, forKey: .workspaceId)
        self.agentKind = try c.decodeIfPresent(AgentKind.self, forKey: .agentKind) ?? .default
        self.settings = try c.decodeIfPresent(SessionSettings.self, forKey: .settings) ?? .default
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.lastActiveAt = try c.decodeIfPresent(Date.self, forKey: .lastActiveAt) ?? Date()
        self.savedMessages = try c.decodeIfPresent([Message].self, forKey: .savedMessages) ?? []
        self.isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }

    /// **ADR-091** — 자유 대화 여부 (workspaceId == nil).
    public var isFreeChat: Bool { workspaceId == nil }

    /// 표시용 부제: 어느 workspace (또는 자유 대화) + agent + model.
    /// Caller가 workspace name을 lookup해서 전달 (이 struct는 ID만 보유).
    public func subtitle(workspaceName: String?) -> String {
        let modelLabel = agentKind == .claude ? settings.model.displayName : settings.codexModel.displayName
        let location = workspaceName ?? "자유 대화 (경로 미지정)"
        return "\(location) · \(agentKind.displayName) \(modelLabel)"
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

    /// **ADR-091** — 자유 대화를 워크스페이스에 attach (또는 detach 시 nil).
    public func with(workspaceId: UUID?) -> ChatSession {
        var copy = self
        copy.workspaceId = workspaceId
        copy.lastActiveAt = Date()
        return copy
    }
}

/// **ADR-091** — 새 ChatSession 생성 시 source 모드.
///
/// 사용자가 NewChatSessionSheet에서 라디오로 1개 선택:
/// - `.existingWorkspace`: 기존 워크스페이스 선택 → 그 폴더에서 작업
/// - `.newWorkspace`: 새 워크스페이스 inline 생성 → 새 폴더에서 작업
/// - `.freeChat`: 워크스페이스 없는 자유 대화 → 나중에 attach 가능
public enum ChatSessionSource: String, Sendable, Codable, CaseIterable, Identifiable {
    case existingWorkspace
    case newWorkspace
    case freeChat

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .existingWorkspace: return "기존 워크스페이스"
        case .newWorkspace: return "새 워크스페이스"
        case .freeChat: return "자유 대화"
        }
    }

    public var subtitle: String {
        switch self {
        case .existingWorkspace: return "이미 만든 프로젝트 폴더에서 작업"
        case .newWorkspace: return "새 폴더를 만들어 시작 (inline)"
        case .freeChat: return "경로 없이 순수 Q&A — 나중에 워크스페이스로 옮길 수 있어요"
        }
    }

    public var icon: String {
        switch self {
        case .existingWorkspace: return "folder.fill"
        case .newWorkspace: return "folder.badge.plus"
        case .freeChat: return "bubble.left.and.bubble.right.fill"
        }
    }
}
