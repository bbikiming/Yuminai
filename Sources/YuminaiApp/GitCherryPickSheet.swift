import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-083 Phase 2** — Cherry-pick UI.
///
/// 흐름:
/// 1. 다른 브랜치 선택 (Picker)
/// 2. 해당 브랜치의 commit 목록 표시
/// 3. 1개 commit 선택 → 현재 브랜치로 cherry-pick
/// 4. 충돌 시 GitConflictSheet 안내
struct GitCherryPickSheet: View {
    @Environment(AppModel.self) private var appModel
    @State private var branches: [BranchInfo] = []
    @State private var selectedSourceBranch: String?
    @State private var commits: [CommitInfo] = []
    @State private var selectedCommit: CommitInfo?
    @State private var loading: Bool = true
    @State private var inProgress: Bool = false

    var body: some View {
        YuminaiSheet(width: 720, height: 580) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                branchPicker
                Divider()
                commitList
            }
            .padding(Theme.Spacing.xl)
        } footer: {
            HStack {
                if let selected = selectedCommit {
                    Text("선택: \(selected.shortSha) — \(selected.message.prefix(40))…")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                FlatButton("취소", variant: .secondary) {
                    appModel.showGitCherryPickSheet = false
                }
                .keyboardShortcut(.escape, modifiers: [])
                FlatButton("Cherry-pick", icon: "arrow.up.right.diamond", variant: .primary) {
                    Task {
                        guard let commit = selectedCommit else { return }
                        inProgress = true
                        defer { inProgress = false }
                        await appModel.gitCherryPick(commit.shortSha)
                        appModel.showGitCherryPickSheet = false
                    }
                }
                .disabled(selectedCommit == nil || inProgress)
            }
        }
        .task { await reloadBranches() }
        .onChange(of: selectedSourceBranch) { _, _ in
            Task { await reloadCommits() }
        }
        .overlay(alignment: .topTrailing) {
            SheetCloseButton { appModel.showGitCherryPickSheet = false }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.right.diamond.fill")
                    .foregroundStyle(Theme.Color.accent)
                    .accessibilityHidden(true)
                Text("Cherry-pick")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
            }
            Text("다른 브랜치의 commit을 현재 브랜치에 가져옵니다. 충돌 발생 시 ‘충돌 해결’ sheet 사용.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var branchPicker: some View {
        HStack(spacing: 8) {
            Text("Source 브랜치")
                .font(Theme.Typography.small.weight(.medium))
                .foregroundStyle(Theme.Color.text)
            Picker("Source", selection: Binding(
                get: { selectedSourceBranch ?? "" },
                set: { selectedSourceBranch = $0.isEmpty ? nil : $0 }
            )) {
                Text("선택하세요").tag("")
                ForEach(otherBranches) { branch in
                    Text(branch.name).tag(branch.name)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 280)
            .accessibilityLabel("Source 브랜치 선택")
            Spacer()
            if let current = appModel.gitBranch {
                Text("→ \(current)")
                    .font(Theme.Typography.monoSmall)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
    }

    /// 현재 브랜치를 제외한 브랜치들.
    private var otherBranches: [BranchInfo] {
        branches.filter { !$0.isCurrent }
    }

    @ViewBuilder
    private var commitList: some View {
        if loading {
            HStack { Spacer(); ProgressView(); Spacer() }
                .frame(maxHeight: .infinity)
        } else if selectedSourceBranch == nil {
            EmptyStateHint(
                icon: "arrow.up.left",
                title: "브랜치를 선택하세요",
                message: "위에서 cherry-pick할 commit이 있는 브랜치를 골라주세요."
            )
            .frame(maxHeight: .infinity)
        } else if commits.isEmpty {
            EmptyStateHint(
                icon: "questionmark.folder",
                title: "Commit 없음",
                message: "선택한 브랜치에 표시할 commit이 없어요."
            )
            .frame(maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Commit 목록 — 1개 선택")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .textCase(.uppercase)
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(commits) { commit in
                            commitRow(commit)
                        }
                    }
                }
            }
        }
    }

    private func commitRow(_ commit: CommitInfo) -> some View {
        let isSelected = selectedCommit?.shortSha == commit.shortSha
        return Button {
            selectedCommit = commit
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Theme.Color.accent : Theme.Color.textTertiary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(commit.message)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Color.text)
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
            .background(isSelected ? Theme.Color.accentMuted : Theme.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(commit.message), \(commit.shortSha)\(isSelected ? ", 선택됨" : "")")
    }

    private func reloadBranches() async {
        loading = true
        defer { loading = false }
        branches = await appModel.gitBranches()
    }

    private func reloadCommits() async {
        commits = []
        selectedCommit = nil
        guard let branch = selectedSourceBranch else { return }
        loading = true
        defer { loading = false }
        commits = await appModel.gitCommitsOnBranch(branch, limit: 30)
    }
}
