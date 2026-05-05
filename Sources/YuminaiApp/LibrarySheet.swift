import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-112** — 자료 라이브러리 Sheet.
///
/// macOS Settings.app 패턴: 좌측 카테고리 사이드바 + 우측 항목 리스트.
///
/// ADR-112 변경:
/// - 카테고리 사이드바 9개 (전체 포함 10개)
/// - 카테고리별 tint color
/// - 빈 카테고리 hint ("커뮤니티 자료에서 추가하세요")
/// - 검색 + 카테고리 + 출처 필터
struct LibrarySheet: View {

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    // MARK: - 상태

    @State private var selectedCategory: FilterCategory = .all
    @State private var searchQuery: String = ""
    @State private var showAddTextSheet: Bool = false
    @State private var showAddURLSheet: Bool = false
    @State private var editingItem: ResourceLibraryItem? = nil
    @State private var viewingItem: ResourceLibraryItem? = nil
    @State private var deletingItem: ResourceLibraryItem? = nil
    @State private var confirmDelete: Bool = false

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

    // MARK: - 필터된 항목

    private var filteredItems: [ResourceLibraryItem] {
        appModel.preferences.libraryItems.filter { item in
            let categoryMatch: Bool
            if let cat = selectedCategory.coreCategory {
                categoryMatch = item.category == cat
            } else {
                categoryMatch = true
            }

            let searchMatch: Bool
            let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if q.isEmpty {
                searchMatch = true
            } else {
                searchMatch = item.displayName.lowercased().contains(q) ||
                    item.tags.contains { $0.lowercased().contains(q) } ||
                    item.notes.lowercased().contains(q)
            }

            return categoryMatch && searchMatch
        }
    }

    // MARK: - 뷰

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            contentArea
        }
        .frame(minWidth: 760, minHeight: 540)
        .sheet(isPresented: $showAddTextSheet) { AddLibraryTextSheet() }
        .sheet(isPresented: $showAddURLSheet) { AddLibraryURLSheet() }
        .sheet(item: $editingItem) { item in EditLibraryItemSheet(item: item) }
        .sheet(item: $viewingItem) { item in LibraryItemContentSheet(item: item) }
        .alert("라이브러리에서 삭제", isPresented: $confirmDelete, presenting: deletingItem) { item in
            Button("삭제", role: .destructive) {
                Task { await appModel.removeLibraryItem(item.id) }
            }
            Button("취소", role: .cancel) {}
        } message: { item in
            Text("'\(item.displayName)'을(를) 라이브러리에서 삭제하시겠어요? 디스크에서도 제거됩니다.")
        }
    }

    // MARK: - 사이드바

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 헤더
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Color.accent)
                Text("자료 라이브러리")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Color.text)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.sm)

            Divider().padding(.bottom, Theme.Spacing.xs)

            // 카테고리 필터 (스크롤 가능)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(FilterCategory.allCases) { cat in
                        sidebarRow(cat)
                    }
                }
            }

            Spacer()

            Divider().padding(.top, Theme.Spacing.sm)

            // 항목 수 표시
            Text("\(appModel.preferences.libraryItems.count)개 항목")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
        }
        .frame(width: 190)
        .background(Theme.Color.surfaceHi)
    }

    private func sidebarRow(_ category: FilterCategory) -> some View {
        let isSelected = selectedCategory == category
        let count: Int = {
            if let cat = category.coreCategory {
                return appModel.preferences.libraryItems.filter { $0.category == cat }.count
            }
            return appModel.preferences.libraryItems.count
        }()

        return Button {
            withAnimation(.easeOut(duration: 0.12)) {
                selectedCategory = category
            }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: categoryIcon(category))
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? categoryTintColor(category) : Theme.Color.textSecondary)
                    .frame(width: 16)
                Text(category.rawValue)
                    .font(Theme.Typography.small.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.Color.text : Theme.Color.textSecondary)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(isSelected ? categoryTintColor(category) : Theme.Color.textTertiary)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm - 1)
            .background(isSelected ? categoryTintColor(category).opacity(0.12) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func categoryIcon(_ category: FilterCategory) -> String {
        switch category {
        case .all:             return "tray.full.fill"
        case .claudeMd:        return "doc.text.fill"
        case .skill:           return "bolt.fill"
        case .template:        return "square.grid.2x2.fill"
        case .styleGuide:      return "paintbrush.fill"
        case .workflow:        return "arrow.triangle.2.circlepath"
        case .architecture:    return "building.columns.fill"
        case .promptPattern:   return "text.bubble.fill"
        case .rules:           return "shield.fill"
        case .mcp:             return "plug.fill"
        case .webFramework:    return "globe"
        case .mobileFramework: return "iphone"
        case .graphics3D:      return "cube.fill"
        case .backend:         return "server.rack"
        case .database:        return "cylinder.fill"
        case .devops:          return "gearshape.2.fill"
        }
    }

    private func categoryTintColor(_ category: FilterCategory) -> Color {
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

    // MARK: - 콘텐츠 영역

    private var contentArea: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if filteredItems.isEmpty {
                emptyState
            } else {
                itemList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var toolbar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // 검색
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Color.textTertiary)
                TextField("자료 검색…", text: $searchQuery)
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
            .frame(maxWidth: 280)

            Spacer()

            // 추가 버튼
            Button {
                showAddURLSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.system(size: 11, weight: .semibold))
                    Text("URL로 추가")
                        .font(Theme.Typography.small.weight(.medium))
                }
                .foregroundStyle(Theme.Color.accent)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 5)
                .background(Theme.Color.accentMuted.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            }
            .buttonStyle(.plain)

            Button {
                showAddTextSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 11, weight: .semibold))
                    Text("텍스트로 추가")
                        .font(Theme.Typography.small.weight(.medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 5)
                .background(Theme.Color.accent)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            }
            .buttonStyle(.plain)

            // 닫기
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .buttonStyle(.plain)
            .help("닫기")
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.Color.surface)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "books.vertical")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(Theme.Color.textTertiary)
            Text(searchQuery.isEmpty ? "라이브러리가 비어있어요" : "검색 결과가 없어요")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.Color.textSecondary)
            if searchQuery.isEmpty {
                if selectedCategory == .all {
                    Text("커뮤니티 자료 패널에서 자료를 추가하거나,\n위 버튼으로 URL이나 텍스트를 직접 추가하세요.")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textTertiary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("'\(selectedCategory.rawValue)' 카테고리에 자료가 없어요.\n커뮤니티 자료 패널에서 이 카테고리 자료를 추가해 보세요.")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textTertiary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var itemList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.sm) {
                ForEach(filteredItems) { item in
                    itemCard(item)
                }
            }
            .padding(Theme.Spacing.lg)
        }
    }

    // MARK: - 항목 카드

    private func itemCard(_ item: ResourceLibraryItem) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                // 헤더
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Image(systemName: item.category.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(categoryColor(item.category))
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.displayName)
                            .font(Theme.Typography.body.weight(.semibold))
                            .foregroundStyle(Theme.Color.text)
                        HStack(spacing: Theme.Spacing.xs) {
                            categoryBadge(item.category)
                            Text("·")
                                .foregroundStyle(Theme.Color.textTertiary)
                            Image(systemName: item.source.iconName)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Theme.Color.textTertiary)
                            Text(item.source.displayLabel)
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Color.textTertiary)
                            Text("·")
                                .foregroundStyle(Theme.Color.textTertiary)
                            Text(item.byteSizeDisplay)
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Color.textTertiary)
                        }
                    }

                    Spacer()

                    // 추가일
                    Text(relativeDate(item.addedAt))
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }

                // 메모
                if !item.notes.isEmpty {
                    Text(item.notes)
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .lineLimit(2)
                }

                // 태그
                if !item.tags.isEmpty {
                    itemTagChips(item.tags)
                }

                Divider()

                // 액션 버튼
                HStack(spacing: Theme.Spacing.sm) {
                    Button("내용 보기") {
                        viewingItem = item
                    }
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.accent)
                    .buttonStyle(.plain)

                    Button("편집") {
                        editingItem = item
                    }
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .buttonStyle(.plain)

                    Spacer()

                    Button("삭제") {
                        deletingItem = item
                        confirmDelete = true
                    }
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.danger)
                    .buttonStyle(.plain)
                }
            }
        }
        .groupBoxStyle(.automatic)
    }

    private func categoryBadge(_ category: CommunityResource.Category) -> some View {
        HStack(spacing: 3) {
            Image(systemName: category.icon)
                .font(.system(size: 9, weight: .semibold))
            Text(category.displayName)
                .font(Theme.Typography.micro.weight(.medium))
        }
        .foregroundStyle(categoryColor(category))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(categoryColor(category).opacity(0.12))
        .clipShape(Capsule())
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

    private func itemTagChips(_ tags: [String]) -> some View {
        HStack(spacing: 4) {
            ForEach(tags.prefix(5), id: \.self) { tag in
                Text("#\(tag)")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.Color.surfaceHi)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            }
            if tags.count > 5 {
                Text("+\(tags.count - 5)")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 60 { return "방금 전" }
        if diff < 3600 { return "\(Int(diff / 60))분 전" }
        if diff < 86400 { return "\(Int(diff / 3600))시간 전" }
        if diff < 86400 * 7 { return "\(Int(diff / 86400))일 전" }
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .none
        return fmt.string(from: date)
    }
}

// MARK: - 텍스트로 추가 Sheet

struct AddLibraryTextSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String = ""
    @State private var category: CommunityResource.Category = .claudeMd
    @State private var content: String = ""
    @State private var tags: String = ""
    @State private var isSaving: Bool = false

    private var canSave: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 헤더
            HStack {
                Text("텍스트로 라이브러리에 추가")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Color.text)
                Spacer()
                Button("취소") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .padding(Theme.Spacing.lg)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    PolishedInputField(
                        label: "이름 *",
                        placeholder: "자료 이름",
                        text: $displayName
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("카테고리")
                            .font(Theme.Typography.small.weight(.medium))
                            .foregroundStyle(Theme.Color.text)
                        Picker("카테고리", selection: $category) {
                            ForEach(CommunityResource.Category.allCases) { cat in
                                Text(cat.displayName).tag(cat)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("내용 * (Markdown 지원)")
                            .font(Theme.Typography.small.weight(.medium))
                            .foregroundStyle(Theme.Color.text)
                        TextEditor(text: $content)
                            .font(Theme.Typography.mono)
                            .frame(minHeight: 200, maxHeight: 400)
                            .scrollContentBackground(.hidden)
                            .padding(Theme.Spacing.sm)
                            .background(Theme.Color.surfaceHi)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    }

                    PolishedInputField(
                        label: "태그",
                        placeholder: "swift, tdd, security (쉼표로 구분)",
                        helperText: "검색과 필터링에 사용됩니다.",
                        text: $tags
                    )
                }
                .padding(Theme.Spacing.lg)
            }

            Divider()

            HStack {
                Spacer()
                Button("추가") {
                    Task {
                        isSaving = true
                        let tagList = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        _ = await appModel.addToLibraryFromText(
                            content.trimmingCharacters(in: .whitespacesAndNewlines),
                            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                            category: category,
                            tags: tagList
                        )
                        isSaving = false
                        dismiss()
                    }
                }
                .font(Theme.Typography.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.sm)
                .background(canSave ? Theme.Color.accent : Theme.Color.surfaceHi)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .disabled(!canSave || isSaving)
            }
            .padding(Theme.Spacing.lg)
        }
        .frame(width: 560, height: 560)
        .background(Theme.Color.bg)
    }
}

// MARK: - URL로 추가 Sheet

struct AddLibraryURLSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var urlString: String = ""
    @State private var displayName: String = ""
    @State private var category: CommunityResource.Category = .claudeMd
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

    private var isValidURL: Bool {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return url.scheme == "https" && url.host != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("URL로 라이브러리에 추가")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Color.text)
                Spacer()
                Button("취소") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .padding(Theme.Spacing.lg)

            Divider()

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                PolishedInputField(
                    label: "URL *",
                    placeholder: "https://raw.githubusercontent.com/…/CLAUDE.md",
                    helperText: "GitHub Raw URL, gist URL 등 직접 다운로드 가능한 텍스트 파일 URL",
                    text: $urlString
                )

                PolishedInputField(
                    label: "이름 (선택)",
                    placeholder: "비워두면 파일명이 자동 사용됩니다",
                    text: $displayName
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("카테고리")
                        .font(Theme.Typography.small.weight(.medium))
                        .foregroundStyle(Theme.Color.text)
                    Picker("카테고리", selection: $category) {
                        ForEach(CommunityResource.Category.allCases) { cat in
                            Text(cat.displayName).tag(cat)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if let errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.Color.danger)
                        Text(errorMessage)
                            .font(Theme.Typography.small)
                            .foregroundStyle(Theme.Color.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Theme.Spacing.sm)
                    .background(Theme.Color.danger.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
            }
            .padding(Theme.Spacing.lg)

            Spacer()

            Divider()

            HStack {
                Spacer()
                Button {
                    Task {
                        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
                        isLoading = true
                        errorMessage = nil
                        let result = await appModel.addToLibraryFromURL(
                            url,
                            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                            category: category
                        )
                        isLoading = false
                        switch result {
                        case .success:
                            dismiss()
                        case .failure(let err):
                            errorMessage = err.localizedDescription
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isLoading {
                            ProgressView().scaleEffect(0.8)
                        }
                        Text(isLoading ? "다운로드 중…" : "라이브러리에 추가")
                    }
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(isValidURL && !isLoading ? Theme.Color.accent : Theme.Color.surfaceHi)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                }
                .buttonStyle(.plain)
                .disabled(!isValidURL || isLoading)
            }
            .padding(Theme.Spacing.lg)
        }
        .frame(width: 480, height: 400)
        .background(Theme.Color.bg)
    }
}

// MARK: - 내용 보기 Sheet

struct LibraryItemContentSheet: View {
    let item: ResourceLibraryItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Color.text)
                    Text("\(item.byteSizeDisplay) · \(item.source.displayLabel)")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
                Spacer()
                Button("닫기") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .padding(Theme.Spacing.lg)

            Divider()

            ScrollView {
                Text(item.content)
                    .font(Theme.Typography.mono)
                    .foregroundStyle(Theme.Color.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(Theme.Spacing.lg)
            }
        }
        .frame(width: 600, height: 500)
        .background(Theme.Color.bg)
    }
}

// MARK: - 편집 Sheet

struct EditLibraryItemSheet: View {
    let item: ResourceLibraryItem
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String
    @State private var notes: String
    @State private var tags: String
    @State private var isSaving: Bool = false

    init(item: ResourceLibraryItem) {
        self.item = item
        self._displayName = State(initialValue: item.displayName)
        self._notes = State(initialValue: item.notes)
        self._tags = State(initialValue: item.tags.joined(separator: ", "))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("자료 편집")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Color.text)
                Spacer()
                Button("취소") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .padding(Theme.Spacing.lg)

            Divider()

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                PolishedInputField(
                    label: "이름",
                    placeholder: "자료 이름",
                    text: $displayName
                )

                PolishedInputField(
                    label: "메모",
                    placeholder: "이 자료에 대한 개인 메모 (선택)",
                    text: $notes
                )

                PolishedInputField(
                    label: "태그",
                    placeholder: "swift, tdd (쉼표로 구분)",
                    text: $tags
                )
            }
            .padding(Theme.Spacing.lg)

            Spacer()

            Divider()

            HStack {
                Spacer()
                Button("저장") {
                    isSaving = true
                    let tagList = tags.split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    let updated = ResourceLibraryItem(
                        id: item.id,
                        displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? item.displayName : displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                        category: item.category,
                        source: item.source,
                        content: item.content,
                        tags: tagList,
                        addedAt: item.addedAt,
                        notes: notes
                    )
                    Task {
                        await appModel.updateLibraryItem(updated)
                        isSaving = false
                        dismiss()
                    }
                }
                .font(Theme.Typography.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Theme.Color.accent)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .disabled(isSaving)
            }
            .padding(Theme.Spacing.lg)
        }
        .frame(width: 440, height: 340)
        .background(Theme.Color.bg)
    }
}
