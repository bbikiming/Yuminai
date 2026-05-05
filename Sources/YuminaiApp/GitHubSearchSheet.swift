import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-116** — GitHub 검색 Sheet.
///
/// GitHub Search API를 통해 리포지토리 또는 코드 파일(CLAUDE.md 등)을 검색하고
/// 검색 결과를 라이브러리에 직접 추가할 수 있다.
///
/// ```
/// [검색어 TextField]
/// [리포지토리 / 코드파일 segmented]
/// ─────────────────────────────────
/// (결과 카드 목록)
/// ─ anthropics/anthropic-cookbook (⭐ 12k)
///   Anthropic 공식 쿡북
///   [GitHub 열기]  [라이브러리에 추가]
/// ```
struct GitHubSearchSheet: View {

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    // MARK: - 검색 모드

    enum SearchMode: String, CaseIterable, Identifiable {
        case repository = "리포지토리"
        case code       = "코드 파일"
        var id: String { rawValue }
    }

    // MARK: - 상태

    @State private var query: String = ""
    @State private var mode: SearchMode = .repository
    @State private var repoResults: [GitHubSearchClient.GitHubRepoResult] = []
    @State private var codeResults: [GitHubSearchClient.GitHubCodeResult] = []
    @State private var isSearching: Bool = false
    @State private var searchError: String? = nil
    @State private var addingIds: Set<String> = []
    @State private var addedIds: Set<String> = []
    @State private var addErrors: [String: String] = [:]

    private let client = GitHubSearchClient()

    // MARK: - 뷰

    var body: some View {
        VStack(spacing: 0) {
            toolbarRow
            Divider()
            searchControls
            Divider()
            resultArea
        }
        .frame(minWidth: 720, minHeight: 560)
        .background(Theme.Color.bg)
    }

    // MARK: - 툴바

    private var toolbarRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.Color.accent)
            Text("GitHub 검색")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Color.text)
            Spacer()
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

    // MARK: - 검색 컨트롤

    private var searchControls: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                // 검색 입력
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Color.textTertiary)
                    TextField(
                        mode == .repository
                            ? "리포지토리 검색 (예: claude.md tdd swift)…"
                            : "파일 검색 (예: filename:CLAUDE.md ios)…",
                        text: $query
                    )
                    .font(Theme.Typography.body)
                    .textFieldStyle(.plain)
                    .onSubmit { performSearch() }

                    if !query.isEmpty {
                        Button {
                            query = ""
                            repoResults = []
                            codeResults = []
                            searchError = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.Color.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 7)
                .background(Theme.Color.surfaceHi)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .frame(maxWidth: .infinity)

                Button {
                    performSearch()
                } label: {
                    HStack(spacing: 4) {
                        if isSearching {
                            ProgressView().scaleEffect(0.7).frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        Text(isSearching ? "검색 중…" : "검색")
                            .font(Theme.Typography.body.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, 7)
                    .background(canSearch && !isSearching ? Theme.Color.accent : Theme.Color.surfaceHi)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                }
                .buttonStyle(.plain)
                .disabled(!canSearch || isSearching)
            }

            // 검색 모드 선택
            Picker("검색 모드", selection: $mode) {
                ForEach(SearchMode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)

            // 검색 힌트
            Text(mode == .repository
                ? "GitHub 리포지토리를 키워드로 검색합니다. 결과에서 CLAUDE.md를 자동 감지해 라이브러리에 추가해요."
                : "filename:CLAUDE.md, filename:.cursorrules 등 특정 파일을 검색합니다.")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.Color.surface)
    }

    private var canSearch: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - 결과 영역

    @ViewBuilder
    private var resultArea: some View {
        if let errorMsg = searchError {
            errorState(errorMsg)
        } else if isSearching {
            loadingState
        } else if mode == .repository && !repoResults.isEmpty {
            repoResultList
        } else if mode == .code && !codeResults.isEmpty {
            codeResultList
        } else if !query.isEmpty {
            emptyState
        } else {
            idleState
        }
    }

    private var idleState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(Theme.Color.textTertiary)
            Text("GitHub에서 검색하세요")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.Color.textSecondary)
            Text("위 검색창에 키워드를 입력하고 검색 버튼을 누르거나 Return을 누르세요.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var loadingState: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
            Text("GitHub에서 검색 중…")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(Theme.Color.textTertiary)
            Text("검색 결과가 없어요")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Color.textSecondary)
            Text("다른 키워드로 다시 시도해 보세요.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32, weight: .ultraLight))
                .foregroundStyle(Theme.Color.danger)
            Text("검색 오류")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Color.danger)
            Text(message)
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
                .multilineTextAlignment(.center)
            Button("다시 시도") {
                performSearch()
            }
            .font(Theme.Typography.small.weight(.medium))
            .foregroundStyle(Theme.Color.accent)
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - 리포지토리 결과 목록

    private var repoResultList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.md) {
                ForEach(repoResults) { repo in
                    repoCard(repo)
                }
            }
            .padding(Theme.Spacing.lg)
        }
    }

    private func repoCard(_ repo: GitHubSearchClient.GitHubRepoResult) -> some View {
        let itemId = "repo-\(repo.id)"
        let isAdding = addingIds.contains(itemId)
        let isAdded = addedIds.contains(itemId)
        let addError = addErrors[itemId]

        return GroupBox {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                // 헤더
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(repo.fullName)
                            .font(Theme.Typography.body.weight(.semibold))
                            .foregroundStyle(Theme.Color.text)
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.yellow)
                            Text(repo.starsDisplay)
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Color.textSecondary)
                            if let lang = repo.language {
                                Text("·")
                                    .foregroundStyle(Theme.Color.textTertiary)
                                    .font(Theme.Typography.micro)
                                Text(lang)
                                    .font(Theme.Typography.micro)
                                    .foregroundStyle(Theme.Color.textTertiary)
                            }
                        }
                    }
                    Spacer()
                    // 기본 브랜치 배지
                    Text(repo.defaultBranch)
                        .font(Theme.Typography.micro.weight(.medium))
                        .foregroundStyle(Theme.Color.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.Color.surfaceHi)
                        .clipShape(Capsule())
                }

                // 설명
                if let desc = repo.description, !desc.isEmpty {
                    Text(desc)
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .lineLimit(2)
                }

                if let errorMsg = addError {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Color.danger)
                        Text(errorMsg)
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.danger)
                    }
                }

                Divider()

                // 액션
                HStack(spacing: Theme.Spacing.sm) {
                    Link(destination: repo.url) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 11, weight: .semibold))
                            Text("GitHub 열기")
                                .font(Theme.Typography.small.weight(.medium))
                        }
                        .foregroundStyle(Theme.Color.accent)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if isAdded {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.Color.success)
                            Text("라이브러리에 추가됨")
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Color.success)
                        }
                    } else {
                        Button {
                            Task { await addRepoToLibrary(repo, itemId: itemId) }
                        } label: {
                            HStack(spacing: 3) {
                                if isAdding {
                                    ProgressView().scaleEffect(0.6).frame(width: 10, height: 10)
                                } else {
                                    Image(systemName: "books.vertical.fill")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                Text(isAdding ? "추가 중…" : "라이브러리에 추가")
                                    .font(Theme.Typography.small.weight(.semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(isAdding ? Theme.Color.surfaceHi : Theme.Color.accent)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isAdding)
                    }
                }
            }
        }
        .groupBoxStyle(.automatic)
    }

    // MARK: - 코드 파일 결과 목록

    private var codeResultList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.md) {
                ForEach(codeResults) { file in
                    codeCard(file)
                }
            }
            .padding(Theme.Spacing.lg)
        }
    }

    private func codeCard(_ file: GitHubSearchClient.GitHubCodeResult) -> some View {
        let itemId = "code-\(file.id)"
        let isAdding = addingIds.contains(itemId)
        let isAdded = addedIds.contains(itemId)
        let addError = addErrors[itemId]

        return GroupBox {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                // 헤더
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(file.repoFullName)
                            .font(Theme.Typography.body.weight(.semibold))
                            .foregroundStyle(Theme.Color.text)
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.Color.accent)
                            Text(file.path)
                                .font(Theme.Typography.micro.weight(.medium))
                                .foregroundStyle(Theme.Color.accent)
                            if file.stars > 0 {
                                Text("·")
                                    .font(Theme.Typography.micro)
                                    .foregroundStyle(Theme.Color.textTertiary)
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.yellow)
                                Text(starsDisplay(file.stars))
                                    .font(Theme.Typography.micro)
                                    .foregroundStyle(Theme.Color.textSecondary)
                            }
                        }
                    }
                    Spacer()
                }

                if let errorMsg = addError {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Color.danger)
                        Text(errorMsg)
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.danger)
                    }
                }

                Divider()

                // 액션
                HStack(spacing: Theme.Spacing.sm) {
                    Link(destination: file.htmlURL) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 11, weight: .semibold))
                            Text("GitHub 열기")
                                .font(Theme.Typography.small.weight(.medium))
                        }
                        .foregroundStyle(Theme.Color.accent)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if isAdded {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.Color.success)
                            Text("라이브러리에 추가됨")
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Color.success)
                        }
                    } else {
                        Button {
                            Task { await addCodeToLibrary(file, itemId: itemId) }
                        } label: {
                            HStack(spacing: 3) {
                                if isAdding {
                                    ProgressView().scaleEffect(0.6).frame(width: 10, height: 10)
                                } else {
                                    Image(systemName: "books.vertical.fill")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                Text(isAdding ? "추가 중…" : "라이브러리에 추가")
                                    .font(Theme.Typography.small.weight(.semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(isAdding ? Theme.Color.surfaceHi : Theme.Color.accent)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isAdding)
                    }
                }
            }
        }
        .groupBoxStyle(.automatic)
    }

    // MARK: - 검색 액션

    private func performSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }

        isSearching = true
        searchError = nil

        Task {
            do {
                switch mode {
                case .repository:
                    let results = try await client.searchRepositories(query: q, perPage: 20)
                    repoResults = results
                    codeResults = []
                case .code:
                    let results = try await client.searchCode(query: q, perPage: 20)
                    codeResults = results
                    repoResults = []
                }
            } catch let error as GitHubSearchClient.SearchError {
                searchError = error.localizedDescription ?? "알 수 없는 오류"
            } catch {
                searchError = error.localizedDescription
            }
            isSearching = false
        }
    }

    // MARK: - 라이브러리 추가

    private func addRepoToLibrary(_ repo: GitHubSearchClient.GitHubRepoResult, itemId: String) async {
        addingIds.insert(itemId)
        addErrors.removeValue(forKey: itemId)

        // CLAUDE.md → README.md 순으로 시도
        let candidates = ["CLAUDE.md", "README.md"]
        var addedURL: URL? = nil

        for fileName in candidates {
            guard let rawURL = repo.rawURL(for: fileName) else { continue }
            let result = await appModel.addToLibraryFromURL(
                rawURL,
                displayName: "\(repo.fullName) — \(fileName)",
                category: .claudeMd
            )
            if case .success = result {
                addedURL = rawURL
                break
            }
        }

        addingIds.remove(itemId)

        if addedURL != nil {
            addedIds.insert(itemId)
        } else {
            addErrors[itemId] = "CLAUDE.md 또는 README.md를 가져올 수 없어요."
        }
    }

    private func addCodeToLibrary(_ file: GitHubSearchClient.GitHubCodeResult, itemId: String) async {
        addingIds.insert(itemId)
        addErrors.removeValue(forKey: itemId)

        let result = await appModel.addToLibraryFromURL(
            file.rawURL,
            displayName: "\(file.repoFullName) — \(file.path)",
            category: .claudeMd
        )

        addingIds.remove(itemId)

        switch result {
        case .success:
            addedIds.insert(itemId)
        case .failure(let err):
            addErrors[itemId] = err.localizedDescription
        }
    }

    // MARK: - 헬퍼

    private func starsDisplay(_ stars: Int) -> String {
        if stars >= 10000 { return "\(stars / 1000)k" }
        if stars >= 1000 { return String(format: "%.1fk", Double(stars) / 1000.0) }
        return "\(stars)"
    }
}
