import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-122** — GitHub 검색 Sheet (안정성 강화 + 크롤링 + 히스토리 + 즐겨찾기).
///
/// 변경 사항 (ADR-118/119 → ADR-122):
/// - Task cancellation: 검색어 변경 시 이전 Task 취소
/// - Pagination: [더 보기] 버튼으로 다음 페이지 fetch
/// - Rate limit 배너: API 한도 실시간 표시
/// - 검색 히스토리: TextField 포커스 시 최근 5개 dropdown
/// - 즐겨찾기: 검색 후 ⭐ 버튼, 헤더에 즐겨찾기 목록
/// - Crawl 버튼: 리포 카드에서 전체 파일 자동 수집
/// - 추천 검색: 사이드바 chip
struct GitHubSearchSheet: View {

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    // MARK: - 검색 모드

    enum SearchMode: String, CaseIterable, Identifiable {
        case repository = "리포지토리"
        case code       = "코드 파일"
        var id: String { rawValue }
    }

    // MARK: - 정렬 옵션 (ADR-118)

    enum SortOrder: String, CaseIterable, Identifiable {
        case stars     = "스타 많은 순"
        case updatedAt = "최근 갱신순"
        case name      = "이름순"
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

    // 정렬/필터 상태 (ADR-118)
    @State private var sortOrder: SortOrder = .stars
    @State private var languageFilter: String? = nil

    // ADR-122 — Task cancellation
    @State private var searchTask: Task<Void, Never>? = nil
    // ADR-122 — Pagination
    @State private var currentPage: Int = 1
    @State private var totalCount: Int = 0
    @State private var hasMore: Bool = false
    @State private var isLoadingMore: Bool = false
    // ADR-122 — Rate limit 표시
    @State private var rateLimit: GitHubSearchClient.GitHubRateLimit? = nil
    // ADR-122 — History dropdown
    @State private var showHistoryDropdown: Bool = false
    // ADR-122 — Favorites sheet
    @State private var showFavoritesSheet: Bool = false
    // ADR-122 — Crawling
    @State private var crawlingIds: Set<String> = []
    @State private var crawlErrors: [String: String] = [:]

    /// **ADR-119** — PAT sheet 표시 여부 (로컬 상태로 제어).
    @State private var showPATSheet: Bool = false

    // MARK: - 추천 키워드

    private let suggestedKeywords = [
        "CLAUDE.md tdd", "react cursorrules", "swift claude",
        "python rules", "nextjs cursorrules", "cursor rules"
    ]

    // MARK: - computed: 정렬+필터 적용된 결과

    /// client-side 정렬 + 언어 필터를 적용한 최종 리포 목록.
    var displayedRepoResults: [GitHubSearchClient.GitHubRepoResult] {
        var filtered = repoResults
        if let lang = languageFilter {
            filtered = filtered.filter { $0.language == lang }
        }
        switch sortOrder {
        case .stars:
            filtered.sort { $0.stars > $1.stars }
        case .updatedAt:
            filtered.sort { lhs, rhs in
                let lhsDate = lhs.updatedAt ?? .distantPast
                let rhsDate = rhs.updatedAt ?? .distantPast
                return lhsDate > rhsDate
            }
        case .name:
            filtered.sort { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
        }
        return filtered
    }

    /// 검색 결과에서 unique 언어 목록 추출 (nil 제외, 알파벳 정렬).
    var availableLanguages: [String] {
        let langs = repoResults.compactMap { $0.language }
        return Array(Set(langs)).sorted()
    }

    /// 언어 필터 활성 여부.
    var hasActiveFilter: Bool { languageFilter != nil }

    // MARK: - 뷰

    var body: some View {
        VStack(spacing: 0) {
            toolbarRow
            Divider()
            searchControls
            // ADR-119 — 코드 검색 모드에서 PAT 상태 표시
            if mode == .code {
                patStatusBanner
                Divider()
            }
            // ADR-122 — Rate limit 배너
            if let rl = rateLimit {
                rateLimitBanner(rl)
                Divider()
            }
            if mode == .repository && !repoResults.isEmpty {
                filterSortBar
                Divider()
            }
            resultArea
        }
        .yuminaiSheetFrame(width: 720, height: 580, wrapInScrollView: false)
        .background(Theme.Color.bg)
        .sheet(isPresented: $showPATSheet) {
            GitHubPATSheet()
                .environment(appModel)
        }
        .sheet(isPresented: $showFavoritesSheet) {
            favoritesSheet
        }
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
            // ADR-122 — 즐겨찾기 버튼
            Button {
                showFavoritesSheet = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("즐겨찾기")
                        .font(Theme.Typography.small.weight(.medium))
                }
                .foregroundStyle(.yellow)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 4)
                .background(Theme.Color.favoriteStar.opacity(0.12))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("저장된 검색어")

            SheetCloseButton(style: .inline) { dismiss() }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.Color.surface)
    }

    // MARK: - ADR-119 PAT 상태 배너

    @ViewBuilder
    private var patStatusBanner: some View {
        let hasPAT = appModel.githubPATStatus == .set
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: hasPAT ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(hasPAT ? Theme.Color.success : .orange)

            if hasPAT {
                Text("토큰 설정됨 — 코드 검색이 활성화되어 있어요.")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer()
                Button("재설정") {
                    showPATSheet = true
                }
                .font(Theme.Typography.micro.weight(.semibold))
                .foregroundStyle(Theme.Color.accent)
                .buttonStyle(.plain)
                Button("삭제") {
                    Task { await appModel.removeGitHubPAT() }
                }
                .font(Theme.Typography.micro.weight(.semibold))
                .foregroundStyle(Theme.Color.danger)
                .buttonStyle(.plain)
            } else {
                Text("코드 검색을 사용하려면 GitHub Personal Access Token이 필요해요.")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer()
                Button("PAT 설정") {
                    showPATSheet = true
                }
                .font(Theme.Typography.small.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 4)
                .background(Theme.Color.accent)
                .clipShape(Capsule())
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(hasPAT ? Theme.Color.success.opacity(0.08) : Theme.Color.warningStrong.opacity(0.08))
    }

    // MARK: - ADR-122 Rate Limit 배너

    private func rateLimitBanner(_ rl: GitHubSearchClient.GitHubRateLimit) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: rl.isLimited ? "exclamationmark.triangle.fill" : "gauge")
                .font(.system(size: 12))
                .foregroundStyle(rl.isLimited ? Theme.Color.danger : Theme.Color.textTertiary)
            Text(rl.displayText)
                .font(Theme.Typography.micro)
                .foregroundStyle(rl.isLimited ? Theme.Color.danger : Theme.Color.textTertiary)
            if rl.remaining < rl.limit / 4 || rl.isLimited {
                Text("·")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                Text(rl.resetDisplayText)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, 5)
        .background(rl.isLimited ? Theme.Color.danger.opacity(0.06) : Theme.Color.surface)
    }

    // MARK: - 검색 컨트롤

    private var searchControls: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                // 검색 입력 + 히스토리 dropdown
                ZStack(alignment: .topLeading) {
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
                        .onTapGesture {
                            if !appModel.preferences.githubSearchHistory.isEmpty {
                                showHistoryDropdown = true
                            }
                        }

                        if !query.isEmpty {
                            Button {
                                query = ""
                                repoResults = []
                                codeResults = []
                                searchError = nil
                                languageFilter = nil
                                showHistoryDropdown = false
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

                    // 히스토리 dropdown (ADR-126: 전체 삭제 버튼 추가)
                    if showHistoryDropdown && !appModel.preferences.githubSearchHistory.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Divider()
                            ForEach(appModel.preferences.githubSearchHistory.prefix(5)) { entry in
                                Button {
                                    query = entry.query
                                    mode = entry.mode == .repositories ? .repository : .code
                                    showHistoryDropdown = false
                                    performSearch()
                                } label: {
                                    HStack(spacing: Theme.Spacing.sm) {
                                        Image(systemName: "clock")
                                            .font(.system(size: 10))
                                            .foregroundStyle(Theme.Color.textTertiary)
                                        Text(entry.query)
                                            .font(Theme.Typography.small)
                                            .foregroundStyle(Theme.Color.text)
                                        Spacer()
                                        Text(entry.mode == .repositories ? "리포" : "코드")
                                            .font(Theme.Typography.micro)
                                            .foregroundStyle(Theme.Color.textTertiary)
                                    }
                                    .padding(.horizontal, Theme.Spacing.md)
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                                .background(Theme.Color.surface)
                                if entry.id != appModel.preferences.githubSearchHistory.prefix(5).last?.id {
                                    Divider()
                                }
                            }
                            Divider()
                            Button {
                                appModel.clearSearchHistory()
                                showHistoryDropdown = false
                            } label: {
                                HStack(spacing: Theme.Spacing.sm) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.Color.danger)
                                    Text("전체 삭제")
                                        .font(Theme.Typography.small.weight(.medium))
                                        .foregroundStyle(Theme.Color.danger)
                                    Spacer()
                                }
                                .padding(.horizontal, Theme.Spacing.md)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            .background(Theme.Color.surface)
                        }
                        .background(Theme.Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                .stroke(Theme.Color.surfaceHi, lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                        .offset(y: 36)
                        .zIndex(10)
                    }
                }
                .frame(maxWidth: .infinity)

                // ADR-122 — 취소 버튼 (검색 중일 때)
                if isSearching {
                    Button {
                        searchTask?.cancel()
                    } label: {
                        Text("취소")
                            .font(Theme.Typography.body.weight(.medium))
                            .foregroundStyle(Theme.Color.textSecondary)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, 7)
                            .background(Theme.Color.surfaceHi)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        performSearch()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12, weight: .semibold))
                            Text("검색")
                                .font(Theme.Typography.body.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, 7)
                        .background(canSearch ? Theme.Color.accent : Theme.Color.surfaceHi)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSearch)
                }
            }

            // 검색 모드 선택
            Picker("검색 모드", selection: $mode) {
                ForEach(SearchMode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)
            .onChange(of: mode) { _, _ in
                languageFilter = nil
                sortOrder = .stars
            }

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
        .contentShape(Rectangle())
        .onTapGesture { showHistoryDropdown = false }
    }

    private var canSearch: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - 정렬/필터 바 (ADR-118 / ADR-126)

    private var filterSortBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("\(displayedRepoResults.count)개")
                .font(Theme.Typography.micro.weight(.semibold))
                .foregroundStyle(Theme.Color.textSecondary)

            if repoResults.count != displayedRepoResults.count {
                Text("/ \(repoResults.count)개 중")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
            }

            if totalCount > repoResults.count {
                Text("· 총 \(totalCount)개")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
            }

            Spacer()

            // ADR-126 — 현재 검색어 즐겨찾기 토글
            let isFavorited = appModel.preferences.githubSearchFavorites
                .contains { $0.query == query.trimmingCharacters(in: .whitespacesAndNewlines)
                    && $0.mode == (mode == .repository ? .repositories : .code) }

            Button {
                let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
                if isFavorited {
                    if let fav = appModel.preferences.githubSearchFavorites.first(where: {
                        $0.query == q && $0.mode == (mode == .repository ? .repositories : .code)
                    }) {
                        appModel.removeSearchFavorite(fav)
                    }
                } else {
                    appModel.saveSearchAsFavorite(
                        query: q,
                        mode: mode == .repository ? .repositories : .code,
                        label: q
                    )
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: isFavorited ? "star.fill" : "star")
                        .font(.system(size: 11, weight: .semibold))
                    Text(isFavorited ? "즐겨찾기 해제" : "즐겨찾기")
                        .font(Theme.Typography.micro.weight(.medium))
                }
                .foregroundStyle(isFavorited ? .yellow : Theme.Color.textSecondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(isFavorited ? Theme.Color.favoriteStar.opacity(0.12) : Theme.Color.surfaceHi)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(isFavorited ? "즐겨찾기에서 제거" : "이 검색어를 즐겨찾기에 추가")

            if !availableLanguages.isEmpty {
                Picker("언어", selection: $languageFilter) {
                    Text("전체 언어").tag(String?.none)
                    ForEach(availableLanguages, id: \.self) { lang in
                        Text(lang).tag(String?.some(lang))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .font(Theme.Typography.small)
                .frame(maxWidth: 130)
            }

            Picker("정렬", selection: $sortOrder) {
                ForEach(SortOrder.allCases) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .font(Theme.Typography.small)
            .frame(maxWidth: 130)

            if hasActiveFilter {
                Button {
                    languageFilter = nil
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                        Text("필터 해제")
                            .font(Theme.Typography.micro.weight(.medium))
                    }
                    .foregroundStyle(Theme.Color.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, 7)
        .background(Theme.Color.surface)
    }

    // MARK: - 결과 영역

    @ViewBuilder
    private var resultArea: some View {
        if let errorMsg = searchError {
            errorState(errorMsg)
        } else if isSearching && repoResults.isEmpty && codeResults.isEmpty {
            loadingState
        } else if mode == .repository && !repoResults.isEmpty {
            repoResultList
        } else if mode == .code && !codeResults.isEmpty {
            codeResultList
        } else if !query.isEmpty && !isSearching {
            emptyState
        } else {
            idleState
        }
    }

    // MARK: - Idle 상태

    private var idleState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            Image(systemName: "archivebox.circle")
                .font(.system(size: 52, weight: .ultraLight))
                .foregroundStyle(Theme.Color.textTertiary)
            VStack(spacing: Theme.Spacing.xs) {
                Text("GitHub에서 커뮤니티 자료 검색")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Color.textSecondary)
                Text("검색창에 키워드를 입력하거나 아래 추천 키워드를 눌러 시작하세요.")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: Theme.Spacing.sm) {
                Text("추천 검색어")
                    .font(Theme.Typography.micro.weight(.semibold))
                    .foregroundStyle(Theme.Color.textTertiary)
                FlexWrapChips(keywords: suggestedKeywords) { keyword in
                    query = keyword
                    performSearch()
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.lg)
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
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            Image(systemName: "doc.questionmark.fill")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(Theme.Color.textTertiary)
            VStack(spacing: Theme.Spacing.xs) {
                Text("검색 결과가 없어요")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Color.textSecondary)
                Text("'\(query)'로 결과를 찾지 못했어요. 다른 키워드로 다시 시도해 보세요.")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .multilineTextAlignment(.center)
            }
            FlexWrapChips(keywords: suggestedKeywords.filter { $0 != query }) { keyword in
                query = keyword
                performSearch()
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.lg)
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
                ForEach(displayedRepoResults) { repo in
                    repoCard(repo)
                }
                if displayedRepoResults.isEmpty && hasActiveFilter {
                    emptyFilterState
                }
                // ADR-122 — 더 보기 버튼
                if hasMore {
                    loadMoreButton
                }
            }
            .padding(Theme.Spacing.lg)
        }
    }

    // ADR-122 — 더 보기 버튼
    private var loadMoreButton: some View {
        Button {
            loadMoreResults()
        } label: {
            HStack(spacing: 6) {
                if isLoadingMore {
                    ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                    Text("불러오는 중…")
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 13))
                    Text("더 보기 (다음 30개)")
                }
            }
            .font(Theme.Typography.small.weight(.semibold))
            .foregroundStyle(Theme.Color.accent)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Color.accentMuted.opacity(0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isLoadingMore)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var emptyFilterState: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 28, weight: .ultraLight))
                .foregroundStyle(Theme.Color.textTertiary)
            Text("선택한 언어의 결과가 없어요.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textTertiary)
            Button("필터 해제") {
                languageFilter = nil
            }
            .font(Theme.Typography.small.weight(.medium))
            .foregroundStyle(Theme.Color.accent)
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
    }

    // MARK: - 리포 카드

    private func repoCard(_ repo: GitHubSearchClient.GitHubRepoResult) -> some View {
        let itemId = "repo-\(repo.id)"
        let isAdding = addingIds.contains(itemId)
        let isAdded = addedIds.contains(itemId)
        let addError = addErrors[itemId]
        let isCrawling = crawlingIds.contains(itemId)
        let crawlError = crawlErrors[itemId]

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .fill(Theme.Color.accent.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Color.accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(repo.fullName)
                        .font(Theme.Typography.body.weight(.semibold))
                        .foregroundStyle(Theme.Color.text)
                        .lineLimit(1)

                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.yellow)
                        Text(repo.starsDisplay)
                            .font(Theme.Typography.micro.monospacedDigit())
                            .foregroundStyle(Theme.Color.textSecondary)
                        if let lang = repo.language {
                            Text("·")
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Color.textTertiary)
                            Text(lang)
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Color.textTertiary)
                        }
                        if let updatedAt = repo.updatedAt {
                            Text("·")
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Color.textTertiary)
                            Text(relativeDate(updatedAt))
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Color.textTertiary)
                                .help(absoluteDate(updatedAt))
                        }
                    }
                }

                Spacer()

                Text(repo.defaultBranch)
                    .font(Theme.Typography.micro.weight(.medium))
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.Color.surfaceHi)
                    .clipShape(Capsule())
            }
            .padding(Theme.Spacing.md)

            if let desc = repo.description, !desc.isEmpty {
                Text(desc)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(2)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.sm)
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
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.sm)
            }

            if let crawlMsg = crawlError {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Color.danger)
                    Text(crawlMsg)
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.danger)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.sm)
            }

            Divider()

            HStack(spacing: Theme.Spacing.sm) {
                Link(destination: repo.url) {
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

                // ADR-122 — 전체 크롤링 버튼
                Button {
                    Task { await crawlRepo(repo, itemId: itemId) }
                } label: {
                    HStack(spacing: 3) {
                        if isCrawling {
                            ProgressView().scaleEffect(0.6).frame(width: 10, height: 10)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        Text(isCrawling ? "수집 중…" : "전체 크롤링")
                            .font(Theme.Typography.small.weight(.medium))
                    }
                    .foregroundStyle(isCrawling ? Theme.Color.textSecondary : Theme.Color.accent)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 5)
                    .background(Theme.Color.accentMuted.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
                .buttonStyle(.plain)
                .disabled(isCrawling)

                Spacer()

                if isAdded {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Color.success)
                        Text("라이브러리에 있음")
                            .font(Theme.Typography.micro.weight(.medium))
                            .foregroundStyle(Theme.Color.success)
                    }
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 5)
                    .background(Theme.Color.success.opacity(0.10))
                    .clipShape(Capsule())
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
                        .padding(.vertical, 5)
                        .background(isAdding ? Theme.Color.surfaceHi : Theme.Color.accent)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isAdding)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
        }
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Theme.Color.surfaceHi, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
    }

    // MARK: - 코드 파일 결과 목록

    private var codeResultList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.md) {
                ForEach(codeResults) { file in
                    codeCard(file)
                }
                if hasMore {
                    loadMoreButton
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

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .fill(Theme.Color.accent.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Color.accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(file.repoFullName)
                        .font(Theme.Typography.body.weight(.semibold))
                        .foregroundStyle(Theme.Color.text)
                        .lineLimit(1)
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
            .padding(Theme.Spacing.md)

            if let errorMsg = addError {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Color.danger)
                    Text(errorMsg)
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.danger)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.sm)
            }

            Divider()

            HStack(spacing: Theme.Spacing.sm) {
                Link(destination: file.htmlURL) {
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

                if isAdded {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Color.success)
                        Text("라이브러리에 있음")
                            .font(Theme.Typography.micro.weight(.medium))
                            .foregroundStyle(Theme.Color.success)
                    }
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 5)
                    .background(Theme.Color.success.opacity(0.10))
                    .clipShape(Capsule())
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
                        .padding(.vertical, 5)
                        .background(isAdding ? Theme.Color.surfaceHi : Theme.Color.accent)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isAdding)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
        }
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Theme.Color.surfaceHi, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
    }

    // MARK: - 즐겨찾기 Sheet (ADR-122 / ADR-126)

    private var favoritesSheet: some View {
        let currentQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentMode: GitHubSearchHistoryEntry.Mode = mode == .repository ? .repositories : .code
        let canAddCurrent = !currentQuery.isEmpty
            && !appModel.preferences.githubSearchFavorites.contains(where: {
                $0.query == currentQuery && $0.mode == currentMode
            })

        return VStack(spacing: 0) {
            HStack {
                Image(systemName: "star.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.yellow)
                Text("즐겨찾기")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Color.text)
                Spacer()

                // ADR-126 — 현재 검색어 즐겨찾기에 추가
                if canAddCurrent {
                    Button {
                        appModel.saveSearchAsFavorite(
                            query: currentQuery,
                            mode: currentMode,
                            label: currentQuery
                        )
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 11))
                            Text("현재 검색어 추가")
                                .font(Theme.Typography.micro.weight(.medium))
                        }
                        .foregroundStyle(Theme.Color.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Theme.Color.accentMuted.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("'\(currentQuery)' 검색어를 즐겨찾기에 추가")
                }

                Button {
                    showFavoritesSheet = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Color.surface)

            Divider()

            if appModel.preferences.githubSearchFavorites.isEmpty {
                VStack(spacing: Theme.Spacing.md) {
                    Spacer()
                    Image(systemName: "star.slash")
                        .font(.system(size: 36, weight: .ultraLight))
                        .foregroundStyle(Theme.Color.textTertiary)
                    Text("즐겨찾기가 없어요")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textTertiary)
                    if !currentQuery.isEmpty {
                        Button {
                            appModel.saveSearchAsFavorite(
                                query: currentQuery,
                                mode: currentMode,
                                label: currentQuery
                            )
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 11))
                                Text("'\(currentQuery)' 추가하기")
                                    .font(Theme.Typography.small.weight(.medium))
                            }
                            .foregroundStyle(.yellow)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, 6)
                            .background(Theme.Color.favoriteStar.opacity(0.10))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(appModel.preferences.githubSearchFavorites) { fav in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fav.label)
                                    .font(Theme.Typography.body.weight(.medium))
                                    .foregroundStyle(Theme.Color.text)
                                Text(fav.query)
                                    .font(Theme.Typography.micro)
                                    .foregroundStyle(Theme.Color.textTertiary)
                            }
                            Spacer()
                            Text(fav.mode == .repositories ? "리포" : "코드")
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Color.textTertiary)
                            Button {
                                query = fav.query
                                mode = fav.mode == .repositories ? .repository : .code
                                showFavoritesSheet = false
                                performSearch()
                            } label: {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.Color.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .onDelete { indexSet in
                        for idx in indexSet {
                            let fav = appModel.preferences.githubSearchFavorites[idx]
                            appModel.removeSearchFavorite(fav)
                        }
                    }
                }
            }
        }
        .yuminaiSheetFrame(width: 380, height: 300, wrapInScrollView: false)
        .background(Theme.Color.bg)
    }

    // MARK: - 검색 액션

    private func performSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }

        if mode == .code && appModel.githubPATStatus != .set {
            searchError = "코드 검색은 GitHub PAT가 필요해요. 위 배너에서 토큰을 설정해 주세요."
            return
        }

        // ADR-122 — 이전 검색 Task 취소
        searchTask?.cancel()

        isSearching = true
        searchError = nil
        languageFilter = nil
        currentPage = 1
        totalCount = 0
        hasMore = false
        repoResults = []
        codeResults = []
        showHistoryDropdown = false

        searchTask = Task {
            let pat = await appModel.loadGitHubPAT()
            let client = GitHubSearchClient(token: pat)

            do {
                switch mode {
                case .repository:
                    let page = try await client.searchRepositories(query: q, perPage: 30, page: 1)
                    repoResults = page.items
                    totalCount = page.totalCount
                    hasMore = page.hasMore
                    currentPage = 1
                    // Rate limit 업데이트
                    rateLimit = await client.currentRateLimit()
                    // 히스토리 추가
                    appModel.addSearchHistory(query: q, mode: .repositories, resultCount: page.totalCount)
                case .code:
                    let page = try await client.searchCode(query: q, perPage: 30, page: 1)
                    codeResults = page.items
                    totalCount = page.totalCount
                    hasMore = page.hasMore
                    currentPage = 1
                    rateLimit = await client.currentRateLimit()
                    appModel.addSearchHistory(query: q, mode: .code, resultCount: page.totalCount)
                }
            } catch GitHubSearchClient.SearchError.cancelled {
                // 취소됨 — 조용히 처리
            } catch GitHubSearchClient.SearchError.unauthorized {
                searchError = "토큰이 만료됐거나 권한이 없어요. 위 배너에서 PAT를 재설정해 주세요."
                await appModel.removeGitHubPAT()
            } catch let error as GitHubSearchClient.SearchError {
                searchError = error.localizedDescription
            } catch {
                searchError = error.localizedDescription
            }
            isSearching = false
        }
    }

    // ADR-122 — 페이지 추가 로드
    private func loadMoreResults() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, hasMore, !isLoadingMore else { return }

        isLoadingMore = true
        let nextPage = currentPage + 1

        Task {
            let pat = await appModel.loadGitHubPAT()
            let client = GitHubSearchClient(token: pat)

            do {
                switch mode {
                case .repository:
                    let page = try await client.searchRepositories(query: q, perPage: 30, page: nextPage)
                    repoResults = repoResults + page.items  // immutable append
                    hasMore = page.hasMore
                    currentPage = nextPage
                    rateLimit = await client.currentRateLimit()
                case .code:
                    let page = try await client.searchCode(query: q, perPage: 30, page: nextPage)
                    codeResults = codeResults + page.items  // immutable append
                    hasMore = page.hasMore
                    currentPage = nextPage
                    rateLimit = await client.currentRateLimit()
                }
            } catch GitHubSearchClient.SearchError.cancelled {
                // 취소됨 — 조용히 처리 (기존 결과 유지)
            } catch GitHubSearchClient.SearchError.unauthorized {
                // ADR-125 P0-3 — 2페이지+ 401도 사용자에게 알림 (1페이지와 동일 처리)
                searchError = "토큰이 만료됐거나 권한이 없어요. 위 배너에서 PAT를 재설정해 주세요."
                await appModel.removeGitHubPAT()
            } catch {
                // 추가 로드 실패 — searchError에 표시 (기존 결과는 유지)
                searchError = error.localizedDescription
            }
            isLoadingMore = false
        }
    }

    // MARK: - 라이브러리 추가

    private func addRepoToLibrary(_ repo: GitHubSearchClient.GitHubRepoResult, itemId: String) async {
        addingIds.insert(itemId)
        addErrors.removeValue(forKey: itemId)

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

    // ADR-122 — 전체 크롤링
    private func crawlRepo(_ repo: GitHubSearchClient.GitHubRepoResult, itemId: String) async {
        crawlingIds.insert(itemId)
        crawlErrors.removeValue(forKey: itemId)

        let parts = repo.fullName.split(separator: "/")
        guard parts.count == 2 else {
            crawlErrors[itemId] = "리포지토리 이름 형식이 올바르지 않아요."
            crawlingIds.remove(itemId)
            return
        }
        let owner = String(parts[0])
        let repoName = String(parts[1])

        let pat = await appModel.loadGitHubPAT()
        let client = GitHubSearchClient(token: pat)
        let crawler = GitHubCrawler(client: client)

        do {
            let result = try await crawler.crawlRepository(owner: owner, repo: repoName, branch: repo.defaultBranch)
            if result.files.isEmpty {
                crawlErrors[itemId] = "수집할 파일이 없어요."
            } else {
                // ADR-125 P0-4 — 성공/실패 집계 후 부분 실패 UX 표시
                var successCount = 0
                var failCount = 0
                for file in result.files {
                    let addResult = await appModel.addToLibraryFromURL(
                        file.downloadURL,
                        displayName: "\(repo.fullName) — \(file.path)",
                        category: file.category
                    )
                    if case .success = addResult {
                        successCount += 1
                    } else {
                        failCount += 1
                    }
                }
                if successCount > 0 {
                    addedIds.insert(itemId)
                }
                if failCount > 0 {
                    let total = successCount + failCount
                    crawlErrors[itemId] = "\(successCount)/\(total) 추가, \(failCount)개 다운로드 실패"
                }
            }
        } catch {
            crawlErrors[itemId] = "크롤링 실패: \(error.localizedDescription)"
        }

        crawlingIds.remove(itemId)
    }

    // MARK: - 헬퍼

    private func starsDisplay(_ stars: Int) -> String {
        if stars >= 10000 { return "\(stars / 1000)k" }
        if stars >= 1000 { return String(format: "%.1fk", Double(stars) / 1000.0) }
        return "\(stars)"
    }

    // ADR-125 P0-2 — RelativeTime helper로 대체 (dead branch 수정).
    private func relativeDate(_ date: Date) -> String {
        RelativeTime.format(date)
    }

    private func absoluteDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }
}

// MARK: - FlexWrap Chips (추천 키워드)

/// 추천 키워드를 감싸는 flex-wrap 스타일 chip 뷰.
private struct FlexWrapChips: View {
    let keywords: [String]
    let onTap: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 220))], spacing: 6) {
            ForEach(keywords, id: \.self) { kw in
                Button {
                    onTap(kw)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 9, weight: .medium))
                        Text(kw)
                            .font(Theme.Typography.micro.weight(.medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Theme.Color.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(Theme.Color.accentMuted.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.sm)
                            .stroke(Theme.Color.accent.opacity(0.25), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
