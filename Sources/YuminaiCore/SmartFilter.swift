import Foundation

/// **ADR-079 Phase 1** — 저장된 검색 (smart filter).
///
/// 사용자가 자주 쓰는 tag 조합 + folder 조건을 이름으로 저장하여 1-click 활성화.
///
/// ## 예시
/// - "긴급 iOS 작업" = tags(긴급, iOS)
/// - "ClientA 일정" = folder(ClientA), tags(일정)
///
/// ## 근거
/// - **macOS Finder Smart Folders**: 검색 조건 저장 패턴
/// - **JetBrains "Scopes"**: 자주 쓰는 필터 named-save
/// - **NN/g "Recognition rather than Recall"** (Heuristic 6): 조건 저장 = recall 부담 ↓
public struct SmartFilter: Sendable, Codable, Hashable, Identifiable {
    public let id: UUID
    public var name: String
    /// 활성화될 tag IDs (intersection 적용).
    public var tagIds: Set<UUID>
    /// 활성화될 folder ID (옵션, nil = 무관).
    public var folderId: UUID?
    /// SF Symbol 아이콘 (default: "line.3.horizontal.decrease.circle").
    public var iconName: String
    /// 색상 (folder palette 공유).
    public var colorName: String

    public init(
        id: UUID = UUID(),
        name: String,
        tagIds: Set<UUID> = [],
        folderId: UUID? = nil,
        iconName: String = "line.3.horizontal.decrease.circle",
        colorName: String = "accent"
    ) {
        self.id = id
        self.name = name
        self.tagIds = tagIds
        self.folderId = folderId
        self.iconName = iconName
        self.colorName = colorName
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.tagIds = try c.decodeIfPresent(Set<UUID>.self, forKey: .tagIds) ?? []
        self.folderId = try c.decodeIfPresent(UUID.self, forKey: .folderId)
        self.iconName = try c.decodeIfPresent(String.self, forKey: .iconName) ?? "line.3.horizontal.decrease.circle"
        self.colorName = try c.decodeIfPresent(String.self, forKey: .colorName) ?? "accent"
    }
}
