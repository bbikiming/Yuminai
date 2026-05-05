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

    /// **ADR-120** — Sheet 컨텍스트에서 사용 시 헤더를 숨겨 이중 헤더 방지.
    /// `CommunityResourcesSheet`는 SheetHeader를 직접 제공하므로 false로 설정.
    var showHeader: Bool = true

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
            if showHeader {
                headerSection
            }
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

    // MARK: - 자료 카드 (ADR-119 — LibraryItemCard 패턴 통일)

    private func resourceCard(_ resource: CommunityResource) -> some View {
        let color = badgeColor(resource.category)
        return VStack(alignment: .leading, spacing: 0) {
            // 헤더: 44×44 아이콘 박스 + 제목 + 메타 행
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                // 44×44 카테고리 아이콘 박스
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .fill(color.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: resource.category.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(color)
                }

                VStack(alignment: .leading, spacing: 4) {
                    // 제목 + 공식 배지
                    HStack(spacing: 6) {
                        Text(resource.displayName)
                            .font(Theme.Typography.body.weight(.semibold))
                            .foregroundStyle(Theme.Color.text)
                            .lineLimit(2)
                        if resource.officialBadge {
                            officialBadgeView
                        }
                    }
                    // 메타 행: 카테고리 배지 · ⭐ stars · 언어
                    HStack(spacing: Theme.Spacing.xs) {
                        categoryBadge(resource.category)
                        Text("·")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textTertiary)
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.yellow)
                        Text(resource.starsDisplay)
                            .font(Theme.Typography.micro.monospacedDigit())
                            .foregroundStyle(Theme.Color.textSecondary)
                        Text("·")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textTertiary)
                        Text(resource.language.flag)
                            .font(.system(size: 10))
                        Text("·")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textTertiary)
                        Text("by \(resource.author)")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                }

                Spacer()
            }
            .padding(Theme.Spacing.md)

            // 설명 (lineLimit 2)
            if !resource.summary.isEmpty {
                Text(resource.summary)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(2)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.sm)
            }

            // 태그 chips (최대 4개 + +N)
            if !resource.tags.isEmpty {
                resourceTagChips(resource.tags)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.sm)
            }

            // 사용 사례 행 (있을 때만, divider 포함)
            if let useCase = resource.useCase {
                Divider()
                    .padding(.horizontal, Theme.Spacing.md)
                HStack(spacing: 4) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.Color.textTertiary)
                    Text("사용 사례: \(useCase)")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                        .lineLimit(1)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 5)
            }

            Divider()

            // 액션 버튼 행
            HStack(spacing: Theme.Spacing.sm) {
                // GitHub 열기 (secondary)
                Link(destination: resource.repoURL) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 11, weight: .semibold))
                        Text("GitHub 열기")
                            .font(Theme.Typography.small.weight(.medium))
                    }
                    .foregroundStyle(Theme.Color.accent)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 5)
                    .background(Theme.Color.accentMuted.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
                .buttonStyle(.plain)

                Spacer()

                // 라이브러리에 추가 (primary)
                if resource.rawURL != nil && resource.category != .template {
                    addToLibraryButton(resource)
                } else if resource.category != .template {
                    Text("직접 URL 입력 후 추가 가능")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
        }
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(
                    resource.officialBadge ? Theme.Color.accent.opacity(0.35) : Theme.Color.surfaceHi,
                    lineWidth: resource.officialBadge ? 1.5 : 1
                )
        )
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
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
        HStack(spacing: 3) {
            Image(systemName: category.icon)
                .font(.system(size: 9, weight: .semibold))
            Text(category.displayName)
                .font(Theme.Typography.micro.weight(.medium))
        }
        .foregroundStyle(badgeColor(category))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
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

    private func resourceTagChips(_ tags: [String]) -> some View {
        let maxVisible = 4
        return HStack(spacing: 4) {
            ForEach(tags.prefix(maxVisible), id: \.self) { tag in
                Text("#\(tag)")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.Color.surfaceHi)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            }
            if tags.count > maxVisible {
                Text("+\(tags.count - maxVisible)")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Theme.Color.surfaceHi)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            }
        }
    }

    private func actionButtons(_ resource: CommunityResource) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
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
            // ADR-119 — 이미 추가된 경우: success 배지 (Capsule, GitHubSearchSheet 패턴 통일)
            HStack(spacing: 3) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.success)
                Text("라이브러리에 추가됨")
                    .font(Theme.Typography.micro.weight(.medium))
                    .foregroundStyle(Theme.Color.success)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 5)
            .background(Theme.Color.success.opacity(0.10))
            .clipShape(Capsule())
        } else {
            Button {
                Task { await addResourceToLibrary(resource) }
            } label: {
                HStack(spacing: 3) {
                    if isAdding {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 10, height: 10)
                    } else {
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    Text(isAdding ? "추가 중…" : "라이브러리에 추가")
                        .font(Theme.Typography.small.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(isAdding ? Theme.Color.surfaceHi : Theme.Color.accent)
                .clipShape(Capsule())
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

