import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-112** — 자료 카탈로그 전체 탐색 Sheet.
///
/// 카테고리별로 큐레이션 자료를 카드 형태로 탐색한다.
/// macOS Settings 스타일의 좌측 사이드바 + 우측 그리드 레이아웃.
///
/// ```
/// ┌───────────────┬────────────────────────────────────┐
/// │ 전체 (28)     │  📄 CLAUDE.md (5)                  │
/// │ ⭐ 공식 (8)   │  ┌──────────────┐ ┌──────────────┐  │
/// │ ─────────     │  │ 자료 1       │ │ 자료 2       │  │
/// │ 📄 CLAUDE.md  │  └──────────────┘ └──────────────┘  │
/// │ 🛠 Skill      │                                     │
/// │ ...           │  🔌 MCP 서버 (3)                    │
/// └───────────────┴────────────────────────────────────┘
/// ```
struct CatalogSheet: View {

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    // MARK: - 상태

    @State private var selectedSidebar: SidebarItem = .all
    @State private var searchQuery: String = ""
    @State private var sortOrder: SortOrder = .recommended
    @State private var addingId: UUID? = nil
    @State private var addResults: [UUID: AddResult] = [:]

    // MARK: - 타입

    enum SidebarItem: Hashable {
        case all
        case official
        case korean
        case category(CommunityResource.Category)

        var displayName: String {
            switch self {
            case .all:              return "전체"
            case .official:         return "공식 자료"
            case .korean:           return "한국어"
            case .category(let c):  return c.displayName
            }
        }

        var icon: String {
            switch self {
            case .all:              return "square.grid.2x2.fill"
            case .official:         return "checkmark.seal.fill"
            case .korean:           return "globe"
            case .category(let c):  return c.icon
            }
        }
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case recommended = "추천도"
        case stars       = "스타 수"
        var id: String { rawValue }
    }

    enum AddResult {
        case success
        case failure(String)
    }

    // MARK: - 필터된 자료

    private var filteredResources: [CommunityResource] {
        var resources: [CommunityResource]

        switch selectedSidebar {
        case .all:
            resources = CommunityCatalog.curated
        case .official:
            resources = CommunityCatalog.officialResources
        case .korean:
            resources = CommunityCatalog.resources(for: .korean)
        case .category(let cat):
            resources = CommunityCatalog.resources(for: cat)
        }

        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            resources = resources.filter { r in
                r.displayName.lowercased().contains(q) ||
                r.summary.lowercased().contains(q) ||
                r.author.lowercased().contains(q) ||
                r.tags.contains { $0.lowercased().contains(q) }
            }
        }

        switch sortOrder {
        case .recommended:
            return resources.sorted { $0.recommendedRank > $1.recommendedRank }
        case .stars:
            return resources.sorted { $0.starsApprox > $1.starsApprox }
        }
    }

    /// 현재 필터 기준 카테고리별로 그룹화된 자료
    private var groupedResources: [(CommunityResource.Category, [CommunityResource])] {
        // 그룹화는 '전체' 사이드바일 때만 적용, 카테고리 선택 시 단일 그룹
        if case .category = selectedSidebar {
            if filteredResources.isEmpty { return [] }
            return [(filteredResources[0].category, filteredResources)]
        }

        var groups: [(CommunityResource.Category, [CommunityResource])] = []
        let orderedCategories = CommunityResource.Category.allCases.sorted { $0.categoryRank < $1.categoryRank }

        for cat in orderedCategories {
            let items = filteredResources.filter { $0.category == cat }
            if !items.isEmpty {
                groups.append((cat, items))
            }
        }
        return groups
    }

    // MARK: - 뷰

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            contentArea
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    // MARK: - 사이드바

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 헤더
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Color.accent)
                Text("자료 카탈로그")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Color.text)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.sm)

            Divider().padding(.bottom, Theme.Spacing.xs)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // 특별 필터
                    sidebarRow(.all, count: CommunityCatalog.curated.count)
                    sidebarRow(.official, count: CommunityCatalog.officialResources.count)
                    sidebarRow(.korean, count: CommunityCatalog.resources(for: .korean).count)

                    Divider()
                        .padding(.vertical, Theme.Spacing.xs)
                        .padding(.horizontal, Theme.Spacing.md)

                    // 카테고리 (정렬 순)
                    ForEach(CommunityResource.Category.allCases.sorted { $0.categoryRank < $1.categoryRank }, id: \.self) { cat in
                        sidebarRow(.category(cat), count: CommunityCatalog.resources(for: cat).count)
                    }
                }
            }

            Spacer()

            Divider()

            // 통계
            VStack(alignment: .leading, spacing: 2) {
                Text("\(CommunityCatalog.curated.count)개 큐레이션 자료")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                Text("\(CommunityCatalog.officialResources.count)개 공식 자료")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
        }
        .frame(width: 200)
        .background(Theme.Color.surfaceHi)
    }

    private func sidebarRow(_ item: SidebarItem, count: Int) -> some View {
        let isSelected = selectedSidebar == item
        let tint = sidebarTint(item)

        return Button {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                selectedSidebar = item
            }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: item.icon)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? tint : Theme.Color.textSecondary)
                    .frame(width: 16)
                Text(item.displayName)
                    .font(Theme.Typography.small.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.Color.text : Theme.Color.textSecondary)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(isSelected ? tint : Theme.Color.textTertiary)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm - 1)
            .background(isSelected ? tint.opacity(0.12) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sidebarTint(_ item: SidebarItem) -> Color {
        switch item {
        case .all:              return Theme.Color.accent
        case .official:         return .blue
        case .korean:           return .red
        case .category(let c):  return categoryColor(c)
        }
    }

    // MARK: - 콘텐츠 영역

    private var contentArea: some View {
        VStack(spacing: 0) {
            toolbarRow
            Divider()
            if filteredResources.isEmpty {
                emptyState
            } else {
                resourceScrollView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var toolbarRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // 검색
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Color.textTertiary)
                TextField("자료 검색 (이름, 태그, 작성자)…", text: $searchQuery)
                    .font(Theme.Typography.small)
                    .textFieldStyle(.plain)
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 5)
            .background(Theme.Color.surfaceHi)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .frame(maxWidth: 300)

            Spacer()

            // 정렬
            Picker("정렬", selection: $sortOrder) {
                ForEach(SortOrder.allCases) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .pickerStyle(.menu)
            .font(Theme.Typography.small)
            .frame(maxWidth: 100)

            SheetCloseButton(style: .inline) { dismiss() }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.Color.surface)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(Theme.Color.textTertiary)
            Text("검색 결과가 없어요")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resourceScrollView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl, pinnedViews: [.sectionHeaders]) {
                ForEach(groupedResources, id: \.0) { cat, resources in
                    Section {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: Theme.Spacing.md),
                                GridItem(.flexible(), spacing: Theme.Spacing.md),
                            ],
                            spacing: Theme.Spacing.md
                        ) {
                            ForEach(resources) { resource in
                                catalogCard(resource)
                            }
                        }
                    } header: {
                        categoryHeader(cat, count: resources.count)
                    }
                }
            }
            .padding(Theme.Spacing.lg)
        }
    }

    // MARK: - 카테고리 헤더

    private func categoryHeader(_ category: CommunityResource.Category, count: Int) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: category.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(categoryColor(category))
            Text(category.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Color.text)
            Text("(\(count))")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textTertiary)
            Spacer()
        }
        .padding(.vertical, Theme.Spacing.xs)
        .padding(.horizontal, 2)
        .background(Theme.Color.bg)
    }

    // MARK: - 자료 카드

    private func catalogCard(_ resource: CommunityResource) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                // 헤더
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            if resource.officialBadge {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.blue)
                            }
                            Text(resource.displayName)
                                .font(Theme.Typography.small.weight(.semibold))
                                .foregroundStyle(Theme.Color.text)
                                .lineLimit(2)
                        }
                        HStack(spacing: 4) {
                            Text("by \(resource.author)")
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Color.textTertiary)
                            Text("·")
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Color.textTertiary)
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.yellow)
                            Text(resource.starsDisplay)
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Color.textSecondary)
                            Text(resource.language.flag)
                                .font(.system(size: 9))
                        }
                    }
                    Spacer()
                }

                // 요약 (2줄 제한)
                Text(resource.summary)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                // 사용 사례
                if let useCase = resource.useCase {
                    HStack(spacing: 3) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.yellow)
                        Text(useCase)
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textSecondary)
                            .lineLimit(2)
                            .italic()
                    }
                }

                Spacer(minLength: 0)

                Divider()

                // 액션 행
                HStack(spacing: Theme.Spacing.xs) {
                    Link(destination: resource.repoURL) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 10, weight: .semibold))
                            Text("GitHub")
                                .font(Theme.Typography.micro.weight(.medium))
                        }
                        .foregroundStyle(Theme.Color.accent)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    cardAddButton(resource)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .groupBoxStyle(.automatic)
    }

    @ViewBuilder
    private func cardAddButton(_ resource: CommunityResource) -> some View {
        let isAdding = addingId == resource.id
        let isInLibrary = appModel.isInLibrary(resource)

        if let result = addResults[resource.id], addingId != resource.id {
            switch result {
            case .success:
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Color.success)
                    Text("추가됨")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.success)
                }
            case .failure:
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Color.danger)
            }
        } else if isInLibrary {
            HStack(spacing: 3) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Color.success)
                Text("추가됨")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.success)
            }
        } else if resource.category != .template, resource.rawURL != nil {
            Button {
                Task { await addCard(resource) }
            } label: {
                HStack(spacing: 3) {
                    if isAdding {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 10, height: 10)
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    Text(isAdding ? "추가 중" : "추가")
                        .font(Theme.Typography.micro.weight(.medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isAdding ? Theme.Color.surfaceHi : Theme.Color.accent)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isAdding)
        }
    }

    // MARK: - 헬퍼

    private func addCard(_ resource: CommunityResource) async {
        addingId = resource.id

        let result = await appModel.addToLibraryFromCommunity(resource)

        switch result {
        case .success:
            addResults = addResults.merging([resource.id: .success]) { _, new in new }
        case .failure(let err):
            addResults = addResults.merging([resource.id: .failure(err.localizedDescription)]) { _, new in new }
        }

        try? await Task.sleep(for: .seconds(3))
        if addingId == resource.id {
            addingId = nil
        }
    }

    private func categoryColor(_ category: CommunityResource.Category) -> Color {
        category.swiftUIColor
    }
}
