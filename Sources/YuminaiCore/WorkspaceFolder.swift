import Foundation

/// **ADR-076 Phase 1** — 워크스페이스 폴더 (Codex CLI 스타일 그룹화).
///
/// ## 설계 결정
/// - **flat hierarchy**: 폴더는 1단계만 (중첩 폴더 X). NN/g 연구상 2단계 이상 폴더는
///   사용자 mental model 부담 ↑ + navigation overhead ↑.
/// - **mutually exclusive**: 한 워크스페이스는 0~1개 폴더에만 속함. 멀티 폴더는
///   복잡도 ↑ vs UX 이득 적음 (Apple Finder, Codex CLI 모두 single folder pattern).
/// - **pinned + folder coexistence**: 핀된 워크스페이스도 폴더에 속할 수 있음.
///   사이드바에서 "핀" 그룹에 표시되고, 폴더에서도 표시되어 두 경로로 접근 가능.
///
/// ## 근거
/// - **Apple HIG "Sidebars"**: "Group related items together for easier navigation"
/// - **NN/g "Hierarchical Information Architecture"**: 평면 구조가 깊은 nested보다 유리
/// - **Codex CLI**: project 폴더로 grouping (단일 레벨)
public struct WorkspaceFolder: Sendable, Codable, Hashable, Identifiable {
    public let id: UUID
    /// 폴더 이름 (사용자 정의).
    public var name: String
    /// 이 폴더에 속한 워크스페이스 ID 순서.
    /// Set 대신 Array — 사용자가 폴더 안에서 순서 정렬 가능.
    public var workspaceIds: [UUID]
    /// 사용자가 폴더를 펼쳤는지 (사이드바에서). default true (펼쳐짐).
    public var isExpanded: Bool
    /// **선택적 SF Symbol icon** — folder.fill (default).
    /// 사용자가 변경 가능 (folder/folder.badge.gearshape/folder.badge.questionmark 등).
    public var iconName: String
    /// **ADR-077 Phase 2** — 폴더 색상 (semantic name, e.g., "accent", "blue", "purple").
    /// Theme.Color에서 lookup. nil이면 default accent.
    public var colorName: String

    public init(
        id: UUID = UUID(),
        name: String,
        workspaceIds: [UUID] = [],
        isExpanded: Bool = true,
        iconName: String = "folder.fill",
        colorName: String = "accent"
    ) {
        self.id = id
        self.name = name
        self.workspaceIds = workspaceIds
        self.isExpanded = isExpanded
        self.iconName = iconName
        self.colorName = colorName
    }

    // MARK: - Codable backward-compat

    /// Codable backward-compat: 기존 JSON에 isExpanded/iconName/colorName 없을 수 있음.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.workspaceIds = try c.decodeIfPresent([UUID].self, forKey: .workspaceIds) ?? []
        self.isExpanded = try c.decodeIfPresent(Bool.self, forKey: .isExpanded) ?? true
        self.iconName = try c.decodeIfPresent(String.self, forKey: .iconName) ?? "folder.fill"
        self.colorName = try c.decodeIfPresent(String.self, forKey: .colorName) ?? "accent"
    }
}

// MARK: - Folder customization presets (ADR-077 Phase 2)

/// **ADR-077 Phase 2** — 폴더 색상 preset (8개).
/// 사용자 선택 가능. semantic naming → 다크/라이트 모드 모두 자동 대응.
public enum FolderColorPreset: String, Sendable, CaseIterable, Hashable, Identifiable {
    case accent       // brand cyan (default)
    case blue
    case purple
    case pink
    case red
    case orange
    case yellow
    case green
    case teal
    case gray

    public var id: String { rawValue }

    /// 한국어 라벨 (사용자 표시).
    public var displayName: String {
        switch self {
        case .accent: return "기본"
        case .blue:   return "파란색"
        case .purple: return "보라색"
        case .pink:   return "분홍색"
        case .red:    return "빨간색"
        case .orange: return "주황색"
        case .yellow: return "노란색"
        case .green:  return "초록색"
        case .teal:   return "청록색"
        case .gray:   return "회색"
        }
    }
}

/// **ADR-077 Phase 2** — 폴더 SF Symbol 아이콘 preset (10개).
/// 사용자가 폴더 의미에 맞게 선택 (예: ⚙ = 설정 그룹, 📚 = 학습 자료 등).
public enum FolderIconPreset: String, Sendable, CaseIterable, Hashable, Identifiable {
    case folderFill = "folder.fill"
    case folderBadgeGearshape = "folder.badge.gearshape"
    case folderBadgeQuestionmark = "folder.badge.questionmark"
    case folderBadgePerson = "folder.badge.person.crop"
    case briefcase = "briefcase.fill"
    case archivebox = "archivebox.fill"
    case star = "star.fill"
    case bolt = "bolt.fill"
    case heart = "heart.fill"
    case bookmark = "bookmark.fill"
    case flag = "flag.fill"
    case tag = "tag.fill"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .folderFill:               return "기본 폴더"
        case .folderBadgeGearshape:     return "설정 폴더"
        case .folderBadgeQuestionmark:  return "질문 폴더"
        case .folderBadgePerson:        return "사람 폴더"
        case .briefcase:                return "업무"
        case .archivebox:               return "보관함"
        case .star:                     return "별표"
        case .bolt:                     return "전기"
        case .heart:                    return "하트"
        case .bookmark:                 return "북마크"
        case .flag:                     return "플래그"
        case .tag:                      return "태그"
        }
    }
}

