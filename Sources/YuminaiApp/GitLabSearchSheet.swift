import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-133** — GitLab 검색 Sheet.
///
/// GitHubSearchSheet 패턴을 따르며, GitLab REST API v4를 사용한다.
/// projects / snippets 두 가지 검색 타입을 지원하고, self-hosted 호스트 URL을 표시한다.
struct GitLabSearchSheet: View {

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    // MARK: - 검색 모드

    enum SearchMode: String, CaseIterable, Identifiable {
        case projects = "프로젝트"
        case snippets = "스니펫"
        var id: String { rawValue }
    }

    // MARK: - 상태

    @State private var query: String = ""
    @State private var mode: SearchMode = .projects
    @State private var projectResults: [GitLabSearchClient.GitLabProjectResult] = []
    @State private var snippetResults: [GitLabSearchClient.GitLabSnippetResult] = []
    @State private var isSearching: Bool = false
    @State private var searchError: String? = nil
    @State private var addingIds: Set<Int> = []
    @State private var addedIds: Set<Int> = []

    @State private var searchTask: Task<Void, Never>? = nil
    @State private var currentPage: Int = 1
    @State private var totalCount: Int = 0
    @State private var hasMore: Bool = false
    @State private var isLoadingMore: Bool = false

    @State private var showPATSheet: Bool = false

    private var hostDisplayName: String {
        let host = appModel.preferences.gitlabHostURL
        return host.isEmpty ? "GitLab.com" : host
    }

    private var hostURL: URL {
        URL(string: appModel.preferences.gitlabHostURL) ?? URL(string: "https://gitlab.com")!
    }

    // MARK: - 뷰

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            Divider()
            searchBar
            if !appModel.preferences.hasGitLabPAT {
                patBanner
            }
            Divider()
            resultList
        }
        .yuminaiSheetFrame(width: 720, height: 520, wrapInScrollView: false)
        .background(Theme.Color.bg)
        .sheet(isPresented: $showPATSheet) {
            GitLabPATSheet()
                .environment(appModel)
        }
    }

    // MARK: - 헤더

    private var headerRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Color.gitlab)
            VStack(alignment: .leading, spacing: 1) {
                Text("GitLab 검색")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Color.text)
                Text(hostDisplayName)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            Spacer()
            Button {
                showPATSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: appModel.preferences.hasGitLabPAT ? "key.fill" : "key")
                        .font(.system(size: 11, weight: .semibold))
                    Text(appModel.preferences.hasGitLabPAT ? "PAT 설정됨" : "PAT 설정")
                        .font(Theme.Typography.small.weight(.medium))
                }
                .foregroundStyle(appModel.preferences.hasGitLabPAT ? Theme.Color.success : Theme.Color.gitlab)
            }
            .buttonStyle(.plain)

            SheetCloseButton(style: .inline) { dismiss() }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.Color.surface)
    }

    // MARK: - 검색 바

    private var searchBar: some View {
        HStack(spacing: Theme.Spacing.md) {
            Picker("검색 타입", selection: $mode) {
                ForEach(SearchMode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Color.textTertiary)
                TextField("GitLab 프로젝트 또는 스니펫 검색…", text: $query)
                    .textFieldStyle(.plain)
                    .font(Theme.Typography.body)
                    .onSubmit { startSearch() }
                if isSearching {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                } else if !query.isEmpty {
                    Button {
                        query = ""
                        projectResults = []
                        snippetResults = []
                        totalCount = 0
                        hasMore = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 7)
            .background(Theme.Color.surfaceHi)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

            Button("검색") { startSearch() }
                .buttonStyle(.plain)
                .font(Theme.Typography.body.weight(.semibold))
                .foregroundStyle(Theme.Color.accent)
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
    }

    // MARK: - PAT 배너

    private var patBanner: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Color.gitlab)
            Text("GitLab PAT를 설정하면 더 많은 결과와 높은 rate limit을 사용할 수 있어요.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
            Spacer()
            Button("PAT 설정") {
                showPATSheet = true
            }
            .buttonStyle(.plain)
            .font(Theme.Typography.small.weight(.semibold))
            .foregroundStyle(Theme.Color.gitlab)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Color.gitlab.opacity(0.07))
    }

    // MARK: - 결과 목록

    @ViewBuilder
    private var resultList: some View {
        if let error = searchError {
            errorView(error)
        } else if mode == .projects {
            projectList
        } else {
            snippetList
        }
    }

    private var projectList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if projectResults.isEmpty && !isSearching {
                    emptyState
                } else {
                    ForEach(projectResults) { project in
                        projectCard(project)
                        Divider().padding(.leading, Theme.Spacing.lg)
                    }

                    if hasMore {
                        loadMoreButton
                    }

                    if !projectResults.isEmpty {
                        Text("\(projectResults.count) / \(totalCount)개")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textTertiary)
                            .padding(Theme.Spacing.md)
                    }
                }
            }
        }
    }

    private var snippetList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if snippetResults.isEmpty && !isSearching {
                    emptyState
                } else {
                    ForEach(snippetResults) { snippet in
                        snippetCard(snippet)
                        Divider().padding(.leading, Theme.Spacing.lg)
                    }

                    if hasMore {
                        loadMoreButton
                    }
                }
            }
        }
    }

    // MARK: - 카드

    private func projectCard(_ project: GitLabSearchClient.GitLabProjectResult) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: "folder.fill")
                .font(.system(size: 20))
                .foregroundStyle(Theme.Color.gitlab.opacity(0.8))
                .frame(width: 36, height: 36)
                .background(Theme.Color.gitlab.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

            VStack(alignment: .leading, spacing: 4) {
                Text(project.pathWithNamespace)
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.Color.text)
                    .lineLimit(1)
                if let desc = project.description, !desc.isEmpty {
                    Text(desc)
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .lineLimit(2)
                }
                HStack(spacing: Theme.Spacing.md) {
                    Label(project.starsDisplay, systemImage: "star.fill")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                    if let updatedAt = project.updatedAt {
                        Text(relativeDate(updatedAt))
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                }
            }

            Spacer()

            VStack(spacing: Theme.Spacing.xs) {
                Button {
                    NSWorkspace.shared.open(project.webURL)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .buttonStyle(.plain)

                addToLibraryButton(id: project.id, name: project.name, url: project.webURL)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .contentShape(Rectangle())
    }

    private func snippetCard(_ snippet: GitLabSearchClient.GitLabSnippetResult) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 20))
                .foregroundStyle(Theme.Color.gitlab.opacity(0.8))
                .frame(width: 36, height: 36)
                .background(Theme.Color.gitlab.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

            VStack(alignment: .leading, spacing: 4) {
                Text(snippet.title)
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.Color.text)
                    .lineLimit(1)
                Text(snippet.fileName)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                if let desc = snippet.description, !desc.isEmpty {
                    Text(desc)
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                NSWorkspace.shared.open(snippet.webURL)
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .contentShape(Rectangle())
    }

    private func addToLibraryButton(id: Int, name: String, url: URL) -> some View {
        let isAdded = addedIds.contains(id)
        let isAdding = addingIds.contains(id)

        return Button {
            Task { await addToLibrary(id: id, name: name, url: url) }
        } label: {
            if isAdding {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isAdded ? Theme.Color.success : Theme.Color.accent)
            }
        }
        .buttonStyle(.plain)
        .disabled(isAdded || isAdding)
        .help(isAdded ? "라이브러리에 추가됨" : "라이브러리에 추가")
    }

    // MARK: - 빈 상태 / 오류 / 더 보기

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 36))
                .foregroundStyle(Theme.Color.textTertiary)
            Text(query.isEmpty ? "GitLab 프로젝트나 스니펫을 검색하세요" : "검색 결과가 없어요")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(Theme.Color.danger)
            Text(message)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var loadMoreButton: some View {
        Button {
            Task { await loadMore() }
        } label: {
            HStack(spacing: 4) {
                if isLoadingMore {
                    ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                }
                Text(isLoadingMore ? "로드 중…" : "더 보기")
                    .font(Theme.Typography.small.weight(.medium))
            }
            .foregroundStyle(Theme.Color.accent)
        }
        .buttonStyle(.plain)
        .padding(Theme.Spacing.md)
    }

    // MARK: - 검색 로직

    private func startSearch() {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }

        projectResults = []
        snippetResults = []
        currentPage = 1
        totalCount = 0
        hasMore = false
        searchError = nil
        isSearching = true

        searchTask = Task {
            await performSearch(query: q, page: 1, append: false)
            await MainActor.run { isSearching = false }
        }
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        let nextPage = currentPage + 1
        await performSearch(query: query, page: nextPage, append: true)
        await MainActor.run {
            currentPage = nextPage
            isLoadingMore = false
        }
    }

    private func performSearch(query: String, page: Int, append: Bool) async {
        let token = await appModel.loadGitLabPAT()
        let client = GitLabSearchClient(hostURL: hostURL, token: token)

        do {
            if mode == .projects {
                let page = try await client.searchProjects(query: query, perPage: 20, page: page)
                await MainActor.run {
                    if append {
                        projectResults += page.items
                    } else {
                        projectResults = page.items
                    }
                    totalCount = page.totalCount
                    hasMore = page.hasMore
                }
            } else {
                let page = try await client.searchSnippets(query: query, perPage: 20, page: page)
                await MainActor.run {
                    if append {
                        snippetResults += page.items
                    } else {
                        snippetResults = page.items
                    }
                    totalCount = page.totalCount
                    hasMore = page.hasMore
                }
            }
        } catch is CancellationError {
            // 취소된 경우 무시
        } catch let error as GitLabSearchClient.SearchError {
            await MainActor.run {
                searchError = error.errorDescription ?? "알 수 없는 오류가 발생했어요."
            }
        } catch {
            await MainActor.run {
                searchError = error.localizedDescription
            }
        }
    }

    private func addToLibrary(id: Int, name: String, url: URL) async {
        addingIds.insert(id)
        defer { addingIds.remove(id) }

        let item = ResourceLibraryItem(
            displayName: name,
            category: .gitlabCI,
            source: .userImport(originalURL: url),
            content: "",
            tags: ["gitlab"],
            notes: ""
        )
        await MainActor.run {
            appModel.preferences = {
                var p = appModel.preferences
                p.libraryItems.append(item)
                return p
            }()
            Task { await appModel.savePreferences() }
            addedIds.insert(id)
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 86400 { return "오늘" }
        let days = Int(interval / 86400)
        if days < 30 { return "\(days)일 전" }
        let months = days / 30
        if months < 12 { return "\(months)개월 전" }
        return "\(months / 12)년 전"
    }
}
