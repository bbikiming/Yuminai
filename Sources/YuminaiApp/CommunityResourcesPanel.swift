import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-109 + ADR-111** — 커뮤니티 자료 탐색·라이브러리 추가 패널.
///
/// UserProfileSheet의 "커뮤니티 자료" 섹션에서 렌더링된다.
/// - 카테고리 필터 (전체 / CLAUDE.md / Skill / 템플릿)
/// - 자료 카드 리스트 (이름, 스타, 설명, 태그, GitHub/라이브러리 추가 버튼)
/// - 사용자 정의 URL 직접 추가
/// - ADR-111: [워크스페이스에 적용] → [라이브러리에 추가] 변경
struct CommunityResourcesPanel: View {

    @Environment(AppModel.self) private var appModel

    // MARK: - 상태

    @State private var selectedCategory: FilterCategory = .all
    @State private var customURL: String = ""
    @State private var addResult: AddResult? = nil
    @State private var addingId: UUID? = nil
    @State private var showCustomURLField: Bool = false

    // MARK: - 타입

    enum FilterCategory: String, CaseIterable, Identifiable {
        case all       = "전체"
        case claudeMd  = "CLAUDE.md"
        case skill     = "Skill"
        case template  = "템플릿"
        var id: String { rawValue }
    }

    enum AddResult {
        case success(String)
        case failure(String)
    }

    // MARK: - 뷰

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            headerSection
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
                // ADR-111 — 라이브러리 바로 열기
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
            Text("GitHub에서 검증된 CLAUDE.md 가이드와 Claude Skill을 라이브러리에 추가하세요. 대화창에서 자료를 첨부해 Claude에게 전달할 수 있어요.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
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
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                selectedCategory = category
            }
        } label: {
            Text(category.rawValue)
                .font(Theme.Typography.small.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : Theme.Color.text)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? Theme.Color.accent : Theme.Color.surfaceHi)
                )
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.clear : Theme.Color.borderSubtle, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 자료 목록

    private var filteredResources: [CommunityResource] {
        switch selectedCategory {
        case .all:      return CommunityCatalog.curated
        case .claudeMd: return CommunityCatalog.resources(for: .claudeMd)
        case .skill:    return CommunityCatalog.resources(for: .skill)
        case .template: return CommunityCatalog.resources(for: .template)
        }
    }

    private var resourceList: some View {
        VStack(spacing: Theme.Spacing.md) {
            if filteredResources.isEmpty {
                Text("해당 카테고리 자료가 없어요.")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Theme.Spacing.xl)
            } else {
                ForEach(filteredResources) { resource in
                    resourceCard(resource)
                }
            }
        }
    }

    // MARK: - 자료 카드

    private func resourceCard(_ resource: CommunityResource) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                // 헤더 행: 이름 + 스타 + 카테고리 배지
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(resource.displayName)
                            .font(Theme.Typography.body.weight(.semibold))
                            .foregroundStyle(Theme.Color.text)
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
        case .claudeMd:  return Theme.Color.accent
        case .skill:     return .orange
        case .template:  return Theme.Color.success
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

            // ADR-111 — 라이브러리에 추가 (rawURL 있고 template 아닌 경우만)
            if resource.rawURL != nil && resource.category != .template {
                addToLibraryButton(resource)
            } else if resource.category != .template {
                // rawURL 없으면 "직접 추가" 힌트
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

        // 결과 인라인 표시
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
            // 이미 추가된 경우 — 비활성 표시
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
