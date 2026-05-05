import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-118** — GitHub 검색 Sheet (카드 UI 고도화 + 정렬/필터).
///
/// GitHub Search API를 통해 리포지토리 또는 코드 파일(CLAUDE.md 등)을 검색하고
/// 검색 결과를 라이브러리에 직접 추가할 수 있다.
///
/// 변경 사항 (ADR-116 → ADR-118):
/// - 리포 카드 디자인 시스템 적용 (LibraryItemCard 패턴 차용)
/// - 정렬: 스타 많은 순 / 최근 갱신순 / 이름순
/// - 언어 필터: 검색 결과 unique 언어 추출, client-side 필터
/// - 빈 상태 / 검색 전 상태 hint + 추천 키워드 chips
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
            if mode == .repository && !repoResults.isEmpty {
                filterSortBar
                Divider()
            }
            resultArea
        }
        .frame(minWidth: 720, minHeight: 580)
        .background(Theme.Color.bg)
        .sheet(isPresented: $showPATSheet) {
            GitHubPATSheet()
                .environment(appModel)
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
        .background(hasPAT ? Theme.Color.success.opacity(0.08) : Color.orange.opacity(0.08))
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
                            languageFilter = nil
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
    }

    private var canSearch: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - 정렬/필터 바 (ADR-118)

    private var filterSortBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // 결과 수
            Text("\(displayedRepoResults.count)개")
                .font(Theme.Typography.micro.weight(.semibold))
                .foregroundStyle(Theme.Color.textSecondary)

            if repoResults.count != displayedRepoResults.count {
                Text("/ \(repoResults.count)개 중")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
            }

            Spacer()

            // 언어 필터 Picker
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

            // 정렬 Picker
            Picker("정렬", selection: $sortOrder) {
                ForEach(SortOrder.allCases) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .font(Theme.Typography.small)
            .frame(maxWidth: 130)

            // 필터 해제
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
        } else if isSearching {
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

    // MARK: - Idle 상태 (검색 전, 추천 키워드 chips)

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
            // 추천 키워드 chips
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
            // 다른 추천어 chips
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
            }
            .padding(Theme.Spacing.lg)
        }
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

    // MARK: - 리포 카드 (ADR-118 polished design)

    private func repoCard(_ repo: GitHubSearchClient.GitHubRepoResult) -> some View {
        let itemId = "repo-\(repo.id)"
        let isAdding = addingIds.contains(itemId)
        let isAdded = addedIds.contains(itemId)
        let addError = addErrors[itemId]

        return VStack(alignment: .leading, spacing: 0) {
            // 헤더: 아이콘 + 제목 + 메타
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                // 36×36 아이콘 박스
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .fill(Theme.Color.accent.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Color.accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    // 리포 이름
                    Text(repo.fullName)
                        .font(Theme.Typography.body.weight(.semibold))
                        .foregroundStyle(Theme.Color.text)
                        .lineLimit(1)

                    // 메타: ⭐ stars · 언어 · 갱신일
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

                // 브랜치 배지
                Text(repo.defaultBranch)
                    .font(Theme.Typography.micro.weight(.medium))
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.Color.surfaceHi)
                    .clipShape(Capsule())
            }
            .padding(Theme.Spacing.md)

            // 설명
            if let desc = repo.description, !desc.isEmpty {
                Text(desc)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(2)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.sm)
            }

            // 추가 오류 배지
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

            // 액션 버튼 행
            HStack(spacing: Theme.Spacing.sm) {
                // GitHub 열기 (secondary)
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

                Spacer()

                // 추가 상태
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
            // 헤더: 아이콘 + 경로 + 리포 + 스타
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                // 36×36 파일 아이콘 박스
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

            // 액션 버튼 행
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

    // MARK: - 검색 액션

    private func performSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }

        // ADR-119 — 코드 검색은 PAT 없이 차단
        if mode == .code && appModel.githubPATStatus != .set {
            searchError = "코드 검색은 GitHub PAT가 필요해요. 위 배너에서 토큰을 설정해 주세요."
            return
        }

        isSearching = true
        searchError = nil
        languageFilter = nil

        Task {
            // ADR-119 — Keychain에서 PAT 로드 후 client 생성
            let pat = await appModel.loadGitHubPAT()
            let client = GitHubSearchClient(token: pat)

            do {
                switch mode {
                case .repository:
                    let results = try await client.searchRepositories(query: q, perPage: 30)
                    repoResults = results
                    codeResults = []
                case .code:
                    let results = try await client.searchCode(query: q, perPage: 30)
                    codeResults = results
                    repoResults = []
                }
            } catch GitHubSearchClient.SearchError.unauthorized {
                // ADR-119 — 401 처리: PAT 재설정 안내
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

    // MARK: - 헬퍼

    private func starsDisplay(_ stars: Int) -> String {
        if stars >= 10000 { return "\(stars / 1000)k" }
        if stars >= 1000 { return String(format: "%.1fk", Double(stars) / 1000.0) }
        return "\(stars)"
    }

    private func relativeDate(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 60 { return "방금 전" }
        if diff < 3600 { return "\(Int(diff / 60))분 전" }
        if diff < 86400 { return "\(Int(diff / 3600))시간 전" }
        if diff < 86400 * 7 { return "\(Int(diff / 86400))일 전" }
        if diff < 86400 * 30 { return "\(Int(diff / 86400))일 전" }
        if diff < 86400 * 365 { return "\(Int(diff / (86400 * 30)))개월 전" }
        return "\(Int(diff / (86400 * 365)))년 전"
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
        // macOS에서는 LazyVGrid로 flex-wrap 효과
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
