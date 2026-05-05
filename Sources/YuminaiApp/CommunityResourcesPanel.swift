import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-109** — 커뮤니티 자료 탐색·적용 패널.
///
/// UserProfileSheet의 "커뮤니티 자료" 섹션에서 렌더링된다.
/// - 카테고리 필터 (전체 / CLAUDE.md / Skill / 템플릿)
/// - 자료 카드 리스트 (이름, 스타, 설명, 태그, GitHub/적용 버튼)
/// - 사용자 정의 URL 직접 추가
struct CommunityResourcesPanel: View {

    @Environment(AppModel.self) private var appModel

    // MARK: - 상태

    @State private var selectedCategory: FilterCategory = .all
    @State private var customURL: String = ""
    @State private var applyResult: ApplyResult? = nil
    @State private var applyingId: UUID? = nil
    @State private var showCustomURLField: Bool = false

    // MARK: - 타입

    enum FilterCategory: String, CaseIterable, Identifiable {
        case all       = "전체"
        case claudeMd  = "CLAUDE.md"
        case skill     = "Skill"
        case template  = "템플릿"
        var id: String { rawValue }
    }

    enum ApplyResult {
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
            }
            Text("GitHub에서 검증된 CLAUDE.md 가이드와 Claude Skill을 현재 워크스페이스에 적용할 수 있어요.")
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

            // 적용 버튼 (rawURL 있고 template 아닌 경우만)
            if resource.rawURL != nil && resource.category != .template {
                applyButton(resource)
            }
        }
    }

    @ViewBuilder
    private func applyButton(_ resource: CommunityResource) -> some View {
        let isApplying = applyingId == resource.id

        // 적용 결과 인라인 표시
        if case .success(let msg) = applyResult, applyingId == resource.id {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.success)
                Text(msg)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.success)
            }
        } else if case .failure(let msg) = applyResult, applyingId == resource.id {
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.danger)
                Text(msg)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.danger)
            }
        } else {
            Button {
                Task { await applyResource(resource) }
            } label: {
                HStack(spacing: 4) {
                    if isApplying {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 11, height: 11)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    Text(isApplying ? "적용 중…" : "워크스페이스에 적용")
                        .font(Theme.Typography.small.weight(.medium))
                }
                .foregroundStyle(isApplying ? Theme.Color.textSecondary : .white)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 6)
                .background(isApplying ? Theme.Color.surfaceHi : Theme.Color.accent)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            }
            .buttonStyle(.plain)
            .disabled(isApplying || !hasWorkspace)
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
                    Text("직접 URL 입력")
                        .font(Theme.Typography.small.weight(.medium))
                        .foregroundStyle(Theme.Color.accent)
                }
            }
            .buttonStyle(.plain)

            if showCustomURLField {
                GroupBox {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("GitHub Raw URL 또는 리포지토리 URL을 입력하세요.")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textSecondary)

                        PolishedInputField(
                            label: "URL",
                            placeholder: "https://raw.githubusercontent.com/…/CLAUDE.md",
                            helperText: "입력한 URL에서 파일을 다운로드해 워크스페이스 CLAUDE.md에 추가해요.",
                            text: $customURL
                        )

                        HStack {
                            Spacer()
                            Button("적용") {
                                Task { await applyCustomURL() }
                            }
                            .font(Theme.Typography.small.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, 6)
                            .background(isValidCustomURL ? Theme.Color.accent : Theme.Color.surfaceHi)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                            .disabled(!isValidCustomURL || !hasWorkspace)
                        }
                    }
                }
                .groupBoxStyle(.automatic)
            }
        }
    }

    // MARK: - 헬퍼

    private var hasWorkspace: Bool {
        appModel.selectedWorkspaceId != nil &&
        appModel.workspaces.first(where: { $0.id == appModel.selectedWorkspaceId }) != nil
    }

    private var isValidCustomURL: Bool {
        guard let url = URL(string: customURL.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return url.scheme == "https" && url.host != nil
    }

    private func applyResource(_ resource: CommunityResource) async {
        guard let ws = appModel.workspaces.first(where: { $0.id == appModel.selectedWorkspaceId }) else { return }
        applyingId = resource.id
        applyResult = nil

        let wsURL = URL(fileURLWithPath: ws.directoryPath)
        let result = await appModel.applyCommunityResource(resource, to: wsURL)

        switch result {
        case .success(let msg):
            applyResult = .success(msg)
        case .failure(let err):
            applyResult = .failure(err.localizedDescription)
        }

        // 3초 후 결과 메시지 사라짐
        try? await Task.sleep(for: .seconds(3))
        if applyingId == resource.id {
            applyResult = nil
            applyingId = nil
        }
    }

    private func applyCustomURL() async {
        let urlString = customURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: urlString),
              let ws = appModel.workspaces.first(where: { $0.id == appModel.selectedWorkspaceId }) else { return }

        let tempResource = CommunityResource(
            category: .claudeMd,
            displayName: "사용자 정의 자료",
            author: url.host ?? "unknown",
            summary: "사용자가 직접 입력한 URL에서 가져온 자료",
            starsApprox: 0,
            repoURL: url,
            rawURL: url,
            tags: ["custom"]
        )

        let wsURL = URL(fileURLWithPath: ws.directoryPath)
        let result = await appModel.applyCommunityResource(tempResource, to: wsURL)

        switch result {
        case .success:
            customURL = ""
            showCustomURLField = false
        case .failure(let err):
            applyResult = .failure(err.localizedDescription)
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
