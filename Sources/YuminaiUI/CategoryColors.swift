import SwiftUI
import YuminaiCore

/// **ADR-126** — CommunityResource.Category 별 SwiftUI Color 매핑.
///
/// LibrarySheet / CatalogSheet / CommunityResourcesPanel / LibraryPickerPopover
/// 4곳에 100% 복제되어 있던 16-case switch를 한 곳으로 통합한다.
///
/// 사용법:
/// ```swift
/// let color = item.category.swiftUIColor
/// ```
public extension CommunityResource.Category {

    /// 카테고리에 대응하는 SwiftUI `Color`.
    ///
    /// - `Theme.Color.accent` — CLAUDE.md
    /// - `Theme.Color.success` — template, backend
    /// - named SwiftUI colors — 나머지 12 케이스
    var swiftUIColor: Color {
        switch self {
        case .claudeMd:        return Theme.Color.accent
        case .skill:           return .orange
        case .template:        return Theme.Color.success
        case .styleGuide:      return .purple
        case .workflow:        return .blue
        case .architecture:    return .indigo
        case .promptPattern:   return .teal
        case .rules:           return .red
        case .mcp:             return .cyan
        case .webFramework:    return .blue
        case .mobileFramework: return .pink
        case .graphics3D:      return .purple
        case .backend:         return Theme.Color.success
        case .database:        return .orange
        case .devops:          return .gray
        }
    }
}
