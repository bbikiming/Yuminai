import SwiftUI
import YuminaiCore

/// **ADR-111** — 라이브러리 항목 선택 Popover.
///
/// Composer의 "라이브러리" 버튼을 클릭하면 표시된다.
/// - 검색 TextField + 카테고리 필터
/// - 항목 리스트 (이름 + 카테고리 배지 + 바이트 크기)
/// - 항목 클릭 시 onSelect 콜백 → Composer에 첨부
public struct LibraryPickerPopover: View {

    /// 표시할 라이브러리 항목 전체 목록.
    public let items: [YuminaiCore.ResourceLibraryItem]
    /// 이미 첨부된 항목 (중복 방지).
    public let attachedItems: [YuminaiCore.ResourceLibraryItem]
    /// 항목 선택 시 콜백.
    public let onSelect: (YuminaiCore.ResourceLibraryItem) -> Void
    /// 팝오버 닫기 콜백.
    public let onClose: () -> Void

    public init(
        items: [YuminaiCore.ResourceLibraryItem],
        attachedItems: [YuminaiCore.ResourceLibraryItem] = [],
        onSelect: @escaping (YuminaiCore.ResourceLibraryItem) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.items = items
        self.attachedItems = attachedItems
        self.onSelect = onSelect
        self.onClose = onClose
    }

    @State private var query: String = ""
    @State private var selectedCategory: FilterCategory = .all

    enum FilterCategory: String, CaseIterable, Identifiable {
        case all      = "전체"
        case claudeMd = "CLAUDE.md"
        case skill    = "Skill"
        case template = "템플릿"
        var id: String { rawValue }

        var coreCategory: CommunityResource.Category? {
            switch self {
            case .all: return nil
            case .claudeMd: return .claudeMd
            case .skill: return .skill
            case .template: return .template
            }
        }
    }

    private var filteredItems: [YuminaiCore.ResourceLibraryItem] {
        items.filter { item in
            let categoryMatch: Bool
            if let cat = selectedCategory.coreCategory {
                categoryMatch = item.category == cat
            } else {
                categoryMatch = true
            }
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let searchMatch = q.isEmpty ||
                item.displayName.lowercased().contains(q) ||
                item.tags.contains { $0.lowercased().contains(q) }
            return categoryMatch && searchMatch
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 헤더
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Color.accent)
                Text("라이브러리 첨부")
                    .font(Theme.Typography.small.weight(.semibold))
                    .foregroundStyle(Theme.Color.text)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.sm)

            // 검색
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Color.textTertiary)
                TextField("자료 검색…", text: $query)
                    .font(Theme.Typography.small)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 5)
            .background(Theme.Color.surfaceHi)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .padding(.horizontal, Theme.Spacing.md)

            // 카테고리 필터
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(FilterCategory.allCases) { cat in
                        filterChip(cat)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 6)
            }

            Divider()

            // 항목 목록
            if filteredItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredItems) { item in
                            itemRow(item)
                        }
                    }
                }
                .frame(maxHeight: 280)
            }

            Divider()

            // 푸터 — 라이브러리가 비면 안내
            if items.isEmpty {
                Text("라이브러리가 비어있어요. 커뮤니티 자료 탭에서 자료를 추가하세요.")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
            } else {
                Text("클릭하면 메시지에 첨부됩니다")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, 6)
            }
        }
        .frame(width: 320)
        .background(Theme.Color.surface)
    }

    // MARK: - 카테고리 chip

    private func filterChip(_ category: FilterCategory) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            withAnimation(.easeOut(duration: 0.1)) {
                selectedCategory = category
            }
        } label: {
            Text(category.rawValue)
                .font(Theme.Typography.micro.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : Theme.Color.text)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isSelected ? Theme.Color.accent : Theme.Color.surfaceHi)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 항목 행

    private func itemRow(_ item: YuminaiCore.ResourceLibraryItem) -> some View {
        let isAttached = attachedItems.contains(item)

        return Button {
            if !isAttached {
                onSelect(item)
                onClose()
            }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: item.category.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(categoryColor(item.category))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.displayName)
                        .font(Theme.Typography.small)
                        .foregroundStyle(isAttached ? Theme.Color.textTertiary : Theme.Color.text)
                        .lineLimit(1)
                    Text(item.byteSizeDisplay + " · " + item.category.displayName)
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }

                Spacer()

                if isAttached {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Color.success)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isAttached)
        .background(isAttached ? Theme.Color.surfaceHi.opacity(0.5) : .clear)
    }

    // MARK: - 빈 상태

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "books.vertical")
                .font(.system(size: 28, weight: .ultraLight))
                .foregroundStyle(Theme.Color.textTertiary)
            Text(query.isEmpty ? "라이브러리가 비어있어요" : "검색 결과가 없어요")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
    }

    private func categoryColor(_ category: CommunityResource.Category) -> Color {
        switch category {
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
