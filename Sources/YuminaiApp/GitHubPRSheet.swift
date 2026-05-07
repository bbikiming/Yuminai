import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-082 Phase 2-3** — GitHub PR review + Actions status sheet.
///
/// 표시 항목:
/// - PR meta (number / title / state badge / author / branches)
/// - Status checks (PR check rollup)
/// - Comments (간단한 list)
/// - Recent workflow runs (Actions, current branch)
/// - 1-click "브라우저에서 열기"
struct GitHubPRSheet: View {
    @Environment(AppModel.self) private var appModel
    @State private var pr: PullRequestDetails?
    @State private var workflowRuns: [WorkflowRun] = []
    @State private var contributors: [Contributor] = []
    @State private var repoInfo: RepoInfo?
    @State private var loading: Bool = true
    @State private var errorMessage: String?
    /// **ADR-083 Phase 3** — PR comment 입력.
    @State private var commentDraft: String = ""
    @State private var postingComment: Bool = false

    var body: some View {
        YuminaiSheet(width: 720, height: 640) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if loading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .frame(maxHeight: .infinity)
                } else if let pr {
                    prContent(pr)
                } else {
                    EmptyStateHint(
                        icon: "questionmark.circle",
                        title: "PR 없음",
                        message: errorMessage ?? "현재 브랜치에 GitHub PR이 없어요. ‘PR 만들기’로 새로 만들 수 있어요."
                    )
                    .frame(maxHeight: .infinity)
                }
            }
            .padding(Theme.Spacing.xl)
        } footer: {
            HStack {
                if let pr {
                    Button {
                        appModel.openInBrowser(pr.url)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 11))
                            Text("브라우저에서 열기")
                                .font(Theme.Typography.small.weight(.medium))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Color.accent)
                    .accessibilityLabel("PR 브라우저에서 열기")
                }
                Spacer()
                Button {
                    Task { await reload() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                        Text("새로고침")
                            .font(Theme.Typography.small)
                    }
                }
                .buttonStyle(.plain)
                FlatButton("닫기", variant: .secondary) {
                    appModel.showGitHubPRSheet = false
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .task { await reload() }
        .overlay(alignment: .topTrailing) {
            SheetCloseButton { appModel.showGitHubPRSheet = false }
        }
    }

    @ViewBuilder
    private func prContent(_ pr: PullRequestDetails) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                prHeader(pr)
                checksSection(pr)
                if !workflowRuns.isEmpty {
                    workflowSection
                }
                if let comments = pr.comments, !comments.isEmpty {
                    commentsSection(comments)
                }
                if let body = pr.body, !body.isEmpty {
                    bodySection(body)
                }
                // ADR-083 Phase 4 — Repo insights
                if let info = repoInfo {
                    repoInsightsCard(info)
                }
                if !contributors.isEmpty {
                    contributorsSection
                }
                // ADR-083 Phase 3 — Comment composer
                commentComposer
            }
        }
    }

    private func prHeader(_ pr: PullRequestDetails) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                statePill(pr)
                Text("#\(pr.number)")
                    .font(Theme.Typography.monoSmall)
                    .foregroundStyle(Theme.Color.textTertiary)
                Spacer()
                if let decision = pr.reviewDecision {
                    reviewDecisionBadge(decision)
                }
            }
            Text(pr.title)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Color.text)
            HStack(spacing: 6) {
                Image(systemName: "person.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.Color.textTertiary)
                    .accessibilityHidden(true)
                Text(pr.author.login)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                Text("·")
                    .foregroundStyle(Theme.Color.textTertiary)
                Text("\(pr.headRefName) → \(pr.baseRefName)")
                    .font(Theme.Typography.monoSmall)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
    }

    private func statePill(_ pr: PullRequestDetails) -> some View {
        let color: Color = {
            switch pr.state {
            case "OPEN": return pr.isDraft ? Theme.Color.textSecondary : Theme.Color.success
            case "MERGED": return .purple
            case "CLOSED": return Theme.Color.danger
            default: return Theme.Color.textSecondary
            }
        }()
        return Text(pr.stateDisplay)
            .font(Theme.Typography.micro.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color)
            .clipShape(Capsule())
            .accessibilityLabel("PR 상태 \(pr.stateDisplay)")
    }

    private func reviewDecisionBadge(_ decision: String) -> some View {
        let (label, color, icon): (String, Color, String) = {
            switch decision {
            case "APPROVED": return ("승인됨", Theme.Color.success, "checkmark.seal.fill")
            case "CHANGES_REQUESTED": return ("변경 요청", .orange, "exclamationmark.triangle.fill")
            case "REVIEW_REQUIRED": return ("리뷰 필요", Theme.Color.textSecondary, "clock.fill")
            default: return (decision, Theme.Color.textSecondary, "questionmark.circle")
            }
        }()
        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(label)
                .font(Theme.Typography.micro.weight(.medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
        .accessibilityLabel("리뷰 상태 \(label)")
    }

    private func checksSection(_ pr: PullRequestDetails) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Status checks")
            HStack(spacing: 16) {
                checkStatBlock("✓ 통과",
                               value: "\(pr.statusCheckRollup?.filter { $0.conclusion == "SUCCESS" }.count ?? 0)",
                               color: Theme.Color.success)
                if pr.failedChecks > 0 {
                    checkStatBlock("✗ 실패",
                                   value: "\(pr.failedChecks)",
                                   color: Theme.Color.danger)
                }
                if pr.pendingChecks > 0 {
                    checkStatBlock("⋯ 진행 중",
                                   value: "\(pr.pendingChecks)",
                                   color: .orange)
                }
                Spacer()
                Image(systemName: pr.allChecksPass && pr.pendingChecks == 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(pr.allChecksPass && pr.pendingChecks == 0 ? Theme.Color.success : .orange)
                    .accessibilityHidden(true)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        }
    }

    private func checkStatBlock(_ label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
            Text(value)
                .font(Theme.Typography.title)
                .foregroundStyle(color)
        }
    }

    private var workflowSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("최근 GitHub Actions 실행")
            VStack(spacing: 4) {
                ForEach(workflowRuns) { run in
                    workflowRow(run)
                }
            }
        }
    }

    private func workflowRow(_ run: WorkflowRun) -> some View {
        let color: Color = {
            if run.isSuccess { return Theme.Color.success }
            if run.isFailure { return Theme.Color.danger }
            if run.isInProgress { return .orange }
            return Theme.Color.textSecondary
        }()
        let icon: String = {
            if run.isSuccess { return "checkmark.circle.fill" }
            if run.isFailure { return "xmark.circle.fill" }
            if run.isInProgress { return "circle.dotted" }
            return "questionmark.circle"
        }()
        return HStack(spacing: 8) {
            Button {
                appModel.openInBrowser(run.url)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                        .foregroundStyle(color)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(run.workflowName)
                            .font(Theme.Typography.small.weight(.medium))
                            .foregroundStyle(Theme.Color.text)
                        Text(run.displayTitle)
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(run.displayStatus)
                        .font(Theme.Typography.micro.weight(.medium))
                        .foregroundStyle(color)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.Color.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(run.workflowName), \(run.displayStatus)")
            .accessibilityHint("브라우저에서 workflow 결과 열기")
            // ADR-083 Phase 4 — Workflow re-run (failed만 표시)
            if run.isFailure {
                Button {
                    Task {
                        await appModel.rerunWorkflow(runId: run.databaseId, failedOnly: true)
                        await reload()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Color.accent)
                }
                .buttonStyle(.plain)
                .help("실패한 job 재실행")
                .accessibilityLabel("Workflow 재실행")
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 6)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    // MARK: - ADR-083 Phase 4 — Repo insights card

    private func repoInsightsCard(_ info: RepoInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("저장소 정보")
            HStack(spacing: 16) {
                statBadge(icon: "star.fill", value: "\(info.stargazerCount)", label: "Stars", color: .yellow)
                statBadge(icon: "tuningfork", value: "\(info.forkCount)", label: "Forks", color: .blue)
                statBadge(icon: "exclamationmark.circle", value: "\(info.openIssuesCount)", label: "Issues", color: .orange)
                Spacer()
                Button {
                    appModel.openInBrowser(info.url)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 9))
                        Text(info.nameWithOwner)
                            .font(Theme.Typography.micro)
                    }
                    .foregroundStyle(Theme.Color.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("저장소 \(info.nameWithOwner) 브라우저에서 열기")
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        }
    }

    private func statBadge(icon: String, value: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)
            Text(value)
                .font(Theme.Typography.small.weight(.semibold))
                .foregroundStyle(Theme.Color.text)
            Text(label)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }

    private var contributorsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Top contributors")
            VStack(spacing: 2) {
                ForEach(contributors) { contributor in
                    HStack(spacing: 8) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Color.textSecondary)
                            .accessibilityHidden(true)
                        Text(contributor.login)
                            .font(Theme.Typography.small)
                            .foregroundStyle(Theme.Color.text)
                        Spacer()
                        Text("\(contributor.contributions) commits")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, 4)
                    .background(Theme.Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
            }
        }
    }

    // MARK: - ADR-083 Phase 3 — Comment composer

    private var commentComposer: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("코멘트 추가")
            TextEditor(text: $commentDraft)
                .font(Theme.Typography.small)
                .padding(8)
                .background(Theme.Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .stroke(Theme.Color.borderSubtle, lineWidth: 1)
                )
                .frame(height: 80)
                .accessibilityLabel("PR 코멘트")
            HStack {
                Text("markdown 가능")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                Spacer()
                Button {
                    Task {
                        postingComment = true
                        defer { postingComment = false }
                        await appModel.commentOnCurrentPR(body: commentDraft)
                        commentDraft = ""
                        await reload()
                    }
                } label: {
                    HStack(spacing: 4) {
                        if postingComment {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 10))
                        }
                        Text(postingComment ? "전송 중…" : "코멘트 게시")
                            .font(Theme.Typography.small.weight(.medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.Color.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
                .buttonStyle(.plain)
                .disabled(commentDraft.trimmingCharacters(in: .whitespaces).isEmpty || postingComment)
                .accessibilityLabel("PR 코멘트 게시")
            }
        }
    }

    private func commentsSection(_ comments: [PullRequestDetails.PRComment]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("코멘트 (\(comments.count))")
            VStack(spacing: 4) {
                ForEach(Array(comments.prefix(5).enumerated()), id: \.offset) { _, comment in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "person.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Color.textSecondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(comment.author.login)
                                .font(Theme.Typography.small.weight(.medium))
                                .foregroundStyle(Theme.Color.text)
                            Text(comment.body)
                                .font(Theme.Typography.small)
                                .foregroundStyle(Theme.Color.textSecondary)
                                .lineLimit(3)
                        }
                        Spacer()
                    }
                    .padding(Theme.Spacing.sm)
                    .background(Theme.Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
                if comments.count > 5 {
                    Text("… 그리고 \(comments.count - 5)개 더 (브라우저에서 보기)")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
            }
        }
    }

    private func bodySection(_ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("PR 본문")
            Text(body.prefix(500) + (body.count > 500 ? "…" : ""))
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
                .padding(Theme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.micro)
            .foregroundStyle(Theme.Color.textTertiary)
            .textCase(.uppercase)
            .tracking(0.6)
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        async let prTask = appModel.loadPullRequestDetails()
        async let workflowsTask = appModel.loadRecentWorkflowRuns(limit: 5)
        async let repoTask = appModel.loadRepoInfo()
        async let contributorsTask = appModel.loadTopContributors(limit: 5)
        pr = await prTask
        workflowRuns = await workflowsTask
        repoInfo = await repoTask
        contributors = await contributorsTask
        if pr == nil {
            errorMessage = "gh CLI가 설치돼 있지 않거나 인증이 필요해요."
        }
    }
}
