import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-112** — 커뮤니티 자료 탐색·라이브러리 추가 패널.
///
/// UserProfileSheet의 "커뮤니티 자료" 섹션에서 렌더링된다.
///
/// ADR-112 개선:
/// - 카테고리 필터 9개 (Capsule chip)
/// - 검색 TextField (이름 + 설명 + 태그)
/// - 정렬: 추천도 / 스타 수
/// - 자료 카드: 공식 배지, 언어 indicator, 사용 사례, 라이브러리 추가 여부
/// - 사용자 정의 URL 직접 추가
struct CommunityResourcesPanel: View {

    @Environment(AppModel.self) private var appModel

    // MARK: - 상태

    @State private var selectedCategory: FilterCategory = .all
    @State private var searchQuery: String = ""
    @State private var sortOrder: SortOrder = .recommended
    @State private var customURL: String = ""
    @State private var addResult: AddResult? = nil
    @State private var addingId: UUID? = nil
    @State private var showCustomURLField: Bool = false

    // MARK: - 타입

    enum FilterCategory: String, CaseIterable, Identifiable {
        case all           = "전체"
        case claudeMd      = "CLAUDE.md"
        case skill         = "Skill"
        case template      = "템플릿"
        case styleGuide    = "디자인 가이드"
        case workflow      = "워크플로우"
        case architecture  = "시스템 설계"
        case promptPattern = "프롬프트 패턴"
        case rules         = "에디터 규칙"
        case mcp           = "MCP 서버"
        // ADR-113 신규
        case webFramework    = "웹 프레임워크"
        case mobileFramework = "모바일 프레임워크"
        case graphics3D      = "3D 그래픽스"
        case backend         = "백엔드"
        case database        = "데이터베이스"
        case devops          = "DevOps"
        var id: String { rawValue }

        var coreCategory: CommunityResource.Category? {
            switch self {
            case .all:             return nil
            case .claudeMd:        return .claudeMd
            case .skill:           return .skill
            case .template:        return .template
            case .styleGuide:      return .styleGuide
            case .workflow:        return .workflow
            case .architecture:    return .architecture
            case .promptPattern:   return .promptPattern
            case .rules:           return .rules
            case .mcp:             return .mcp
            case .webFramework:    return .webFramework
            case .mobileFramework: return .mobileFramework
            case .graphics3D:      return .graphics3D
            case .backend:         return .backend
            case .database:        return .database
            case .devops:          return .devops
            }
        }
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case recommended = "추천도"
        case stars       = "스타 수"
        var id: String { rawValue }
    }

    enum AddResult {
        case success(String)
        case failure(String)
    }

    // MARK: - 필터된 자료

    private var filteredResources: [CommunityResource] {
        var resources = CommunityCatalog.curated

        // 카테고리 필터
        if let cat = selectedCategory.coreCategory {
            resources = resources.filter { $0.category == cat }
        }

        // 검색 필터
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            resources = resources.filter { r in
                r.displayName.lowercased().contains(q) ||
                r.summary.lowercased().contains(q) ||
                r.tags.contains { $0.lowercased().contains(q) } ||
                r.author.lowercased().contains(q)
            }
        }

        // 정렬
        switch sortOrder {
        case .recommended:
            resources = resources.sorted { $0.recommendedRank > $1.recommendedRank }
        case .stars:
            resources = resources.sorted { $0.starsApprox > $1.starsApprox }
        }

        return resources
    }

    // MARK: - 뷰

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            headerSection
            searchAndSort
            filterBar
            resourceList
            customURLSection
        }
    }

    // MARK: - 헤더

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "cube.box.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Color.accent)
                Text("커뮤니티 자료")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Color.text)
                Spacer()
                // 스택 번들 카탈로그
                Button {
                    appModel.showBundleCatalogSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle.stack.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("스택 번들")
                            .font(Theme.Typography.small.weight(.medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.Color.accent)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                // ADR-116 — GitHub 검색 버튼
                Button {
                    appModel.showGitHubSearchSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("GitHub 검색")
                            .font(Theme.Typography.small.weight(.medium))
                    }
                    .foregroundStyle(Theme.Color.accent)
                }
                .buttonStyle(.plain)

                // 카탈로그 전체 보기
                Button {
                    appModel.showCatalogSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("전체 카탈로그")
                            .font(Theme.Typography.small.weight(.medium))
                    }
                    .foregroundStyle(Theme.Color.accent)
                }
                .buttonStyle(.plain)

                // 라이브러리 바로 열기
                Button {
                    appModel.showLibrarySheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("라이브러리 보기")
                            .font(Theme.Typography.small.weight(.medium))
                    }
                    .foregroundStyle(Theme.Color.accent)
                }
                .buttonStyle(.plain)
            }
            Text("GitHub에서 검증된 CLAUDE.md, Skills, MCP 서버 설정 등을 라이브러리에 추가하세요. 대화창에서 자료를 첨부해 Claude에게 전달할 수 있어요.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 검색 + 정렬

    private var searchAndSort: some View {
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
            .padding(.vertical, 6)
            .background(Theme.Color.surfaceHi)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

            // 정렬
            Picker("정렬", selection: $sortOrder) {
                ForEach(SortOrder.allCases) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .pickerStyle(.menu)
            .font(Theme.Typography.small)
            .frame(maxWidth: 100)
        }
    }

    // MARK: - 카테고리 필터

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(FilterCategory.allCases) { cat in
                    filterChip(cat)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private func filterChip(_ category: FilterCategory) -> some View {
        let isSelected = selectedCategory == category
        let count = category.coreCategory.map { cat in
            CommunityCatalog.resources(for: cat).count
        } ?? CommunityCatalog.curated.count

        return Button {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                selectedCategory = category
            }
        } label: {
            HStack(spacing: 4) {
                Text(category.rawValue)
                    .font(Theme.Typography.small.weight(isSelected ? .semibold : .regular))
                if isSelected {
                    Text("\(count)")
                        .font(Theme.Typography.micro.weight(.semibold))
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : Theme.Color.textTertiary)
                }
            }
            .foregroundStyle(isSelected ? .white : Theme.Color.text)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? chipColor(category) : Theme.Color.surfaceHi)
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : Theme.Color.borderSubtle, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func chipColor(_ category: FilterCategory) -> Color {
        switch category {
        case .all:             return Theme.Color.accent
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

    // MARK: - 자료 목록

    private var resourceList: some View {
        VStack(spacing: Theme.Spacing.md) {
            if filteredResources.isEmpty {
                emptyState
            } else {
                ForEach(filteredResources) { resource in
                    resourceCard(resource)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .ultraLight))
                .foregroundStyle(Theme.Color.textTertiary)
            Text("검색 결과가 없어요")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, Theme.Spacing.xl)
    }

    // MARK: - 자료 카드

    private func resourceCard(_ resource: CommunityResource) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                // 헤더 행: 이름 + 배지들 + 카테고리
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(resource.displayName)
                                .font(Theme.Typography.body.weight(.semibold))
                                .foregroundStyle(Theme.Color.text)
                            // 공식 배지
                            if resource.officialBadge {
                                officialBadgeView
                            }
                        }
                        HStack(spacing: Theme.Spacing.xs) {
                            Text("by \(resource.author)")
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Color.textTertiary)
                            Text("·")
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Color.textTertiary)
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.yellow)
                            Text(resource.starsDisplay)
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Color.textSecondary)
                            Text("·")
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Color.textTertiary)
                            // 언어 indicator
                            Text(resource.language.flag)
                                .font(.system(size: 10))
                        }
                    }
                    Spacer()
                    categoryBadge(resource.category)
                }

                // 요약
                Text(resource.summary)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // 사용 사례
                if let useCase = resource.useCase {
                    HStack(spacing: 4) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.yellow)
                        Text(useCase)
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textSecondary)
                            .italic()
                    }
                }

                // 태그
                if !resource.tags.isEmpty {
                    tagChips(resource.tags)
                }

                Divider()

                // 액션 버튼
                actionButtons(resource)
            }
        }
        .groupBoxStyle(.automatic)
    }

    private var officialBadgeView: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 9, weight: .semibold))
            Text("공식")
                .font(Theme.Typography.micro.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.blue.opacity(0.85))
        .clipShape(Capsule())
    }

    private func categoryBadge(_ category: CommunityResource.Category) -> some View {
        HStack(spacing: 4) {
            Image(systemName: category.icon)
                .font(.system(size: 10, weight: .semibold))
            Text(category.displayName)
                .font(Theme.Typography.micro.weight(.medium))
        }
        .foregroundStyle(badgeColor(category))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(badgeColor(category).opacity(0.12))
        .clipShape(Capsule())
    }

    private func badgeColor(_ category: CommunityResource.Category) -> Color {
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

    private func tagChips(_ tags: [String]) -> some View {
        FlowLayout(spacing: 4) {
            ForEach(tags, id: \.self) { tag in
                Text("#\(tag)")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.Color.surfaceHi)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            }
        }
    }

    private func actionButtons(_ resource: CommunityResource) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            // GitHub에서 보기
            Link(destination: resource.repoURL) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11, weight: .semibold))
                    Text("GitHub에서 보기")
                        .font(Theme.Typography.small.weight(.medium))
                }
                .foregroundStyle(Theme.Color.accent)
            }
            .buttonStyle(.plain)

            Spacer()

            // 라이브러리에 추가 (rawURL 있고 template 아닌 경우만)
            if resource.rawURL != nil && resource.category != .template {
                addToLibraryButton(resource)
            } else if resource.category != .template {
                Text("직접 URL 입력 후 추가 가능")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
        }
    }

    @ViewBuilder
    private func addToLibraryButton(_ resource: CommunityResource) -> some View {
        let isAdding = addingId == resource.id
        let isAlreadyInLibrary = appModel.isInLibrary(resource)

        if case .success(let msg) = addResult, addingId == resource.id {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.success)
                Text(msg)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.success)
            }
        } else if case .failure(let msg) = addResult, addingId == resource.id {
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.danger)
                Text(msg)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.danger)
            }
        } else if isAlreadyInLibrary {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.success)
                Text("라이브러리에 추가됨")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.success)
            }
        } else {
            Button {
                Task { await addResourceToLibrary(resource) }
            } label: {
                HStack(spacing: 4) {
                    if isAdding {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 11, height: 11)
                    } else {
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    Text(isAdding ? "추가 중…" : "라이브러리에 추가")
                        .font(Theme.Typography.small.weight(.medium))
                }
                .foregroundStyle(isAdding ? Theme.Color.textSecondary : .white)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 6)
                .background(isAdding ? Theme.Color.surfaceHi : Theme.Color.accent)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            }
            .buttonStyle(.plain)
            .disabled(isAdding)
        }
    }

    // MARK: - 사용자 정의 URL 섹션

    private var customURLSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    showCustomURLField.toggle()
                }
            } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: showCustomURLField ? "chevron.down" : "plus.circle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.Color.accent)
                    Text("직접 URL로 라이브러리에 추가")
                        .font(Theme.Typography.small.weight(.medium))
                        .foregroundStyle(Theme.Color.accent)
                }
            }
            .buttonStyle(.plain)

            if showCustomURLField {
                GroupBox {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("GitHub Raw URL 또는 텍스트 파일 URL을 입력하면 라이브러리에 추가됩니다.")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textSecondary)

                        PolishedInputField(
                            label: "URL",
                            placeholder: "https://raw.githubusercontent.com/…/CLAUDE.md",
                            helperText: "입력한 URL에서 파일을 다운로드해 라이브러리에 저장해요. 대화창에서 첨부해 사용할 수 있어요.",
                            text: $customURL
                        )

                        HStack {
                            Spacer()
                            Button("라이브러리에 추가") {
                                Task { await addCustomURLToLibrary() }
                            }
                            .font(Theme.Typography.small.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, 6)
                            .background(isValidCustomURL ? Theme.Color.accent : Theme.Color.surfaceHi)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                            .disabled(!isValidCustomURL)
                        }
                    }
                }
                .groupBoxStyle(.automatic)
            }
        }
    }

    // MARK: - 헬퍼

    private var isValidCustomURL: Bool {
        guard let url = URL(string: customURL.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return url.scheme == "https" && url.host != nil
    }

    private func addResourceToLibrary(_ resource: CommunityResource) async {
        addingId = resource.id
        addResult = nil

        let result = await appModel.addToLibraryFromCommunity(resource)

        switch result {
        case .success:
            addResult = .success("라이브러리에 추가됐어요!")
        case .failure(let err):
            addResult = .failure(err.localizedDescription)
        }

        // 3초 후 결과 메시지 사라짐
        try? await Task.sleep(for: .seconds(3))
        if addingId == resource.id {
            addResult = nil
            addingId = nil
        }
    }

    private func addCustomURLToLibrary() async {
        let urlString = customURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: urlString) else { return }

        let name = url.lastPathComponent.isEmpty ? "사용자 자료" : url.lastPathComponent
        let result = await appModel.addToLibraryFromURL(url, displayName: name, category: .claudeMd)

        switch result {
        case .success:
            customURL = ""
            showCustomURLField = false
        case .failure(let err):
            addResult = .failure(err.localizedDescription)
        }
    }
}

// MARK: - FlowLayout (태그 chip 줄바꿈용)

/// 자동 줄바꿈 HStack. 태그 chip처럼 크기가 다양한 요소 나열에 사용.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = proposal.width ?? 320
        var height: CGFloat = 0
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                height += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: width, height: max(height, 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
