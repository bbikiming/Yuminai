import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-113** — 스택 번들 카탈로그 Sheet.
///
/// 사용자가 새 프로젝트를 시작할 때 검증된 "스택 조합"을 한 번에 라이브러리에 추가할 수 있다.
/// 예: "Next.js + Tailwind + Supabase 풀스택" → 관련 자료 5개 한번에 추가.
///
/// ```
/// ┌──────────────────┬──────────────────────────────────────────┐
/// │ 풀스택 웹  (3)   │  🌐 풀스택 웹                            │
/// │ 모바일 앱  (2)   │  ┌────────────────────────────────────┐  │
/// │ 3D 인터랙 (1)   │  │ Next.js 풀스택 모던 웹              │  │
/// │ AI 앱     (1)   │  │ nextjs · tailwind · supabase        │  │
/// │ 데이터    (1)   │  │ [번들 모두 추가 — 5개]              │  │
/// │ 백엔드    (1)   │  └────────────────────────────────────┘  │
/// └──────────────────┴──────────────────────────────────────────┘
/// ```
struct BundleCatalogSheet: View {

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    // MARK: - 상태

    @State private var selectedCategory: StackBundle.BundleCategory? = nil
    @State private var searchQuery: String = ""
    @State private var addingBundleId: UUID? = nil
    @State private var addResults: [UUID: BundleAddResult] = [:]

    // MARK: - 타입

    enum BundleAddResult {
        case success(Int)   // 추가된 자료 수
        case partial(Int, Int) // 추가된 수, 전체 수
    }

    // MARK: - 필터된 번들

    private var filteredBundles: [StackBundle] {
        var bundles = StackBundleCatalog.curated

        if let cat = selectedCategory {
            bundles = bundles.filter { $0.category == cat }
        }

        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            bundles = bundles.filter { bundle in
                bundle.displayName.lowercased().contains(q) ||
                bundle.summary.lowercased().contains(q) ||
                bundle.stackTags.contains { $0.lowercased().contains(q) } ||
                bundle.category.displayName.lowercased().contains(q)
            }
        }

        return bundles
    }

    /// 현재 필터 기준 카테고리별 그룹
    private var groupedBundles: [(StackBundle.BundleCategory, [StackBundle])] {
        if let cat = selectedCategory {
            let items = filteredBundles.filter { $0.category == cat }
            return items.isEmpty ? [] : [(cat, items)]
        }

        return StackBundle.BundleCategory.allCases.compactMap { cat in
            let items = filteredBundles.filter { $0.category == cat }
            return items.isEmpty ? nil : (cat, items)
        }
    }

    // MARK: - 뷰

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            contentArea
        }
        .frame(minWidth: 900, minHeight: 620)
    }

    // MARK: - 사이드바

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 헤더
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Color.accent)
                Text("스택 번들")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Color.text)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.sm)

            Divider().padding(.bottom, Theme.Spacing.xs)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    sidebarRow(nil, label: "전체 번들", icon: "rectangle.stack.fill", count: StackBundleCatalog.curated.count, tint: Theme.Color.accent)

                    Divider()
                        .padding(.vertical, Theme.Spacing.xs)
                        .padding(.horizontal, Theme.Spacing.md)

                    ForEach(StackBundle.BundleCategory.allCases) { cat in
                        sidebarRow(
                            cat,
                            label: cat.displayName,
                            icon: cat.icon,
                            count: StackBundleCatalog.bundles(for: cat).count,
                            tint: categoryColor(cat)
                        )
                    }
                }
            }

            Spacer()

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                Text("\(StackBundleCatalog.curated.count)개 스택 번들")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                Text("번들 1개 = 자료 4-6개 묶음")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
        }
        .frame(width: 200)
        .background(Theme.Color.surfaceHi)
    }

    private func sidebarRow(
        _ category: StackBundle.BundleCategory?,
        label: String,
        icon: String,
        count: Int,
        tint: Color
    ) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                selectedCategory = category
            }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? tint : Theme.Color.textSecondary)
                    .frame(width: 16)
                Text(label)
                    .font(Theme.Typography.small.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.Color.text : Theme.Color.textSecondary)
                Spacer()
                if count > 0 {
                    // ADR-116 — Capsule 배지로 일관
                    Text("\(count)")
                        .font(Theme.Typography.micro.weight(.medium))
                        .foregroundStyle(isSelected ? tint : Theme.Color.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isSelected ? tint.opacity(0.15) : Theme.Color.surfaceHi)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm - 1)
            .background(isSelected ? tint.opacity(0.12) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 콘텐츠 영역

    private var contentArea: some View {
        VStack(spacing: 0) {
            toolbarRow
            Divider()
            if filteredBundles.isEmpty {
                emptyState
            } else {
                bundleScrollView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var toolbarRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Color.textTertiary)
                TextField("번들 검색 (이름, 기술 태그)…", text: $searchQuery)
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

            SheetCloseButton(style: .inline) { dismiss() }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.Color.surface)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(Theme.Color.textTertiary)
            Text("검색 결과가 없어요")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bundleScrollView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl, pinnedViews: [.sectionHeaders]) {
                ForEach(groupedBundles, id: \.0) { cat, bundles in
                    Section {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: Theme.Spacing.md),
                                GridItem(.flexible(), spacing: Theme.Spacing.md),
                            ],
                            spacing: Theme.Spacing.md
                        ) {
                            ForEach(bundles) { bundle in
                                bundleCard(bundle)
                            }
                        }
                    } header: {
                        categoryHeader(cat, count: bundles.count)
                    }
                }
            }
            .padding(Theme.Spacing.lg)
        }
    }

    // MARK: - 카테고리 헤더 (ADR-116 — 라운딩 + 배지 일관성)

    private func categoryHeader(_ category: StackBundle.BundleCategory, count: Int) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: category.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(categoryColor(category))
            Text(category.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Color.text)
            Spacer()
            // 카운트 Capsule 배지 — 일관 적용
            Text("\(count)")
                .font(Theme.Typography.micro.weight(.semibold))
                .foregroundStyle(categoryColor(category))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(categoryColor(category).opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.md)
        .background(Theme.Color.bg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Theme.Color.borderSubtle, lineWidth: 0.5)
        )
    }

    // MARK: - 번들 카드

    private func bundleCard(_ bundle: StackBundle) -> some View {
        let isAdding = addingBundleId == bundle.id
        let result = addResults[bundle.id]

        return GroupBox {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                // 헤더
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: bundle.category.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(categoryColor(bundle.category))
                            if bundle.officialBadge {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.blue)
                            }
                        }
                        Text(bundle.displayName)
                            .font(Theme.Typography.body.weight(.semibold))
                            .foregroundStyle(Theme.Color.text)
                            .lineLimit(2)
                    }
                    Spacer()
                    // 자료 수 배지
                    Text(bundle.resourceCountDisplay)
                        .font(Theme.Typography.micro.weight(.medium))
                        .foregroundStyle(categoryColor(bundle.category))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(categoryColor(bundle.category).opacity(0.12))
                        .clipShape(Capsule())
                }

                // 요약
                Text(bundle.summary)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                // 스택 태그 chips
                stackTagChips(bundle.stackTags)

                // 추천 대상 + 시간
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Theme.Color.textTertiary)
                        Text(bundle.recommendedFor)
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textTertiary)
                            .lineLimit(2)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Theme.Color.textTertiary)
                        Text("셋업 시간: \(bundle.estimatedSetupTime)")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                }

                Divider()

                // 액션
                HStack(spacing: Theme.Spacing.xs) {
                    // 포함된 자료 목록 표시
                    let resolved = bundle.resolvedResources
                    Text("\(resolved.filter { $0.rawURL != nil }.count)개 자료 포함")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)

                    Spacer()

                    bundleAddButton(bundle, isAdding: isAdding, result: result)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .groupBoxStyle(.automatic)
    }

    @ViewBuilder
    private func bundleAddButton(_ bundle: StackBundle, isAdding: Bool, result: BundleAddResult?) -> some View {
        if let result {
            switch result {
            case .success(let count):
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Color.success)
                    Text("\(count)개 추가됨")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.success)
                }
            case .partial(let added, let total):
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text("\(added)/\(total)개 추가됨")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(.orange)
                }
            }
        } else {
            Button {
                Task { await addBundle(bundle) }
            } label: {
                HStack(spacing: 3) {
                    if isAdding {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 10, height: 10)
                    } else {
                        Image(systemName: "rectangle.stack.badge.plus")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    Text(isAdding ? "추가 중" : "번들 모두 추가")
                        .font(Theme.Typography.micro.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(isAdding ? Theme.Color.surfaceHi : categoryColor(bundle.category))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isAdding)
        }
    }

    // MARK: - 스택 태그 chips

    private func stackTagChips(_ tags: [String]) -> some View {
        HStack(spacing: 4) {
            ForEach(tags.prefix(5), id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.Color.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.Color.surfaceHi)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Theme.Color.borderSubtle, lineWidth: 0.5)
                    )
            }
            if tags.count > 5 {
                Text("+\(tags.count - 5)")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
        }
    }

    // MARK: - 헬퍼

    private func addBundle(_ bundle: StackBundle) async {
        addingBundleId = bundle.id

        let added = await appModel.addBundleToLibrary(bundle)
        let total = bundle.resolvedResources.filter { $0.rawURL != nil }.count

        let result: BundleAddResult = added.count == total
            ? .success(added.count)
            : .partial(added.count, total)

        addResults = addResults.merging([bundle.id: result]) { _, new in new }

        try? await Task.sleep(for: .seconds(4))
        if addingBundleId == bundle.id {
            addingBundleId = nil
        }
    }

    private func categoryColor(_ category: StackBundle.BundleCategory) -> Color {
        switch category {
        case .fullstackWeb:   return .blue
        case .mobileApp:      return .pink
        case .interactive3D:  return .purple
        case .aiApp:          return Theme.Color.accent
        case .dataApp:        return .orange
        case .backendInfra:   return Theme.Color.success
        }
    }
}
