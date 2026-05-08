import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-082 Phase 4** — Interactive rebase 단순화 sheet.
///
/// 마지막 N개 commit을 가져와 사용자가 각 commit별 action 선택 (pick/reword/squash/fixup/drop).
/// 충돌 발생 시 외부 도구 안내.
struct GitRebaseSheet: View {
    @Environment(AppModel.self) private var appModel
    @State private var commits: [CommitInfo] = []
    @State private var commitCount: Int = 5
    @State private var actions: [String: RebaseAction] = [:]
    @State private var loading: Bool = true
    @State private var inProgress: Bool = false

    var body: some View {
        YuminaiSheet(width: 720, height: 580) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                countPicker
                Divider()
                if loading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .frame(maxHeight: .infinity)
                } else if commits.isEmpty {
                    EmptyStateHint(
                        icon: "questionmark.folder",
                        title: "Commit 없음",
                        message: "rebase 대상이 없어요. git 저장소인지 확인하세요."
                    )
                } else {
                    commitList
                }
                warningBanner
            }
            .padding(Theme.Spacing.xl)
        } footer: {
            HStack {
                Spacer()
                FlatButton("취소", variant: .secondary) {
                    appModel.showGitRebaseSheet = false
                }
                .keyboardShortcut(.escape, modifiers: [])
                FlatButton("Rebase 시작", icon: "arrow.triangle.2.circlepath", variant: .primary) {
                    Task {
                        inProgress = true
                        defer { inProgress = false }
                        await appModel.gitRebase(count: commitCount, actions: actions)
                        appModel.showGitRebaseSheet = false
                    }
                }
                .disabled(actions.values.allSatisfy { $0 == .pick } || inProgress)
            }
        }
        .task { await reload() }
        .onChange(of: commitCount) { _, _ in
            Task { await reload() }
        }
        .overlay(alignment: .topTrailing) {
            SheetCloseButton { appModel.showGitRebaseSheet = false }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Theme.Color.accent)
                    .accessibilityHidden(true)
                Text("Interactive Rebase")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
            }
            Text("최근 commit history를 정리합니다. 이미 push한 commit은 force push가 필요해요.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }

    private var countPicker: some View {
        HStack(spacing: 12) {
            Text("대상 commit 수")
                .font(Theme.Typography.small.weight(.medium))
                .foregroundStyle(Theme.Color.text)
            Stepper("\(commitCount)개", value: $commitCount, in: 1...20)
                .labelsHidden()
            Text("(HEAD~\(commitCount))")
                .font(Theme.Typography.monoSmall)
                .foregroundStyle(Theme.Color.textTertiary)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rebase 대상 commit 수: \(commitCount)")
    }

    private var commitList: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(commits) { commit in
                    commitRow(commit)
                }
            }
        }
    }

    private func commitRow(_ commit: CommitInfo) -> some View {
        let action = actions[commit.shortSha] ?? .pick
        return HStack(spacing: 8) {
            Picker("", selection: Binding(
                get: { actions[commit.shortSha] ?? .pick },
                set: { actions[commit.shortSha] = $0 }
            )) {
                ForEach(RebaseAction.allCases) { a in
                    Label(a.displayName, systemImage: a.iconName).tag(a)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 160)
            .accessibilityLabel("\(commit.shortSha) action")

            VStack(alignment: .leading, spacing: 1) {
                Text(commit.message)
                    .font(Theme.Typography.body)
                    .foregroundStyle(action == .drop ? Theme.Color.textTertiary : Theme.Color.text)
                    .strikethrough(action == .drop)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(commit.shortSha)
                        .font(Theme.Typography.monoSmall)
                        .foregroundStyle(Theme.Color.textTertiary)
                    Text("·")
                        .foregroundStyle(Theme.Color.textTertiary)
                    Text(commit.authorName)
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                    Text("·")
                        .foregroundStyle(Theme.Color.textTertiary)
                    Text(commit.relativeDate)
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 6)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(commit.message), \(action.displayName)")
    }

    @ViewBuilder
    private var warningBanner: some View {
        let hasDrop = actions.values.contains(.drop)
        let hasSquash = actions.values.contains { $0 == .squash || $0 == .fixup }
        if hasDrop || hasSquash {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Color.warningStrong)
                    .accessibilityHidden(true)
                Text(hasDrop
                     ? "삭제 액션이 있어요. history가 영구적으로 변경됩니다."
                     : "병합 액션은 commit message가 합쳐집니다. 충돌 시 외부 도구로 해결하세요.")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer()
            }
            .padding(Theme.Spacing.sm)
            .background(Theme.Color.warningStrong.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        commits = await appModel.gitRecentCommits(limit: commitCount)
        // default = 모두 pick
        actions = Dictionary(uniqueKeysWithValues: commits.map { ($0.shortSha, RebaseAction.pick) })
    }
}
