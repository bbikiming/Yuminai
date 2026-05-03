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

    public init(
        id: UUID = UUID(),
        name: String,
        workspaceIds: [UUID] = [],
        isExpanded: Bool = true,
        iconName: String = "folder.fill"
    ) {
        self.id = id
        self.name = name
        self.workspaceIds = workspaceIds
        self.isExpanded = isExpanded
        self.iconName = iconName
    }

    // MARK: - Codable backward-compat

    /// Codable backward-compat: 기존 JSON에 isExpanded/iconName 없을 수 있음.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.workspaceIds = try c.decodeIfPresent([UUID].self, forKey: .workspaceIds) ?? []
        self.isExpanded = try c.decodeIfPresent(Bool.self, forKey: .isExpanded) ?? true
        self.iconName = try c.decodeIfPresent(String.self, forKey: .iconName) ?? "folder.fill"
    }
}
