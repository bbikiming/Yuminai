import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-079 Phase 4 + ADR-081 Phase 1, 3, 4** — Branch picker + Push/Pull/PR/Stash 통합.
struct GitBranchPickerSheetWrapper: View {
    @Environment(AppModel.self) private var appModel
    @State private var branches: [BranchInfo] = []
    @State private var loading: Bool = true
    @State private var prTitle: String = ""
    @State private var prBody: String = ""
    @State private var showPRComposer: Bool = false
    @State private var creatingPR: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if loading {
                ProgressView()
                    .frame(width: 380, height: 200)
            } else if showPRComposer {
                prComposer
            } else {
                mainContent
            }
        }
        .frame(width: 380)
        .frame(maxHeight: showPRComposer ? 460 : 540)
        .background(Theme.Color.bg)
        .task {
            branches = await appModel.gitBranches()
            loading = false
        }
    }

    // MARK: - Main content

    private var mainContent: some View {
        VStack(spacing: 0) {
            // ADR-081 Phase 1 — upstream sync status indicator
            if let upstream = appModel.gitUpstream {
                upstreamBadge(upstream)
            }
            // ADR-081 Phase 1 — Push/Pull/Fetch action row
            remoteActionRow
            FlatHDivider()
            // Branches list
            GitBranchPickerPopover(
                branches: branches,
                currentBranch: appModel.gitBranch ?? "unknown",
                onSwitch: { name in
                    Task { await appModel.switchGitBranch(name) }
                },
                onCreateBranch: { name in
                    Task { await appModel.createGitBranch(name) }
                },
                onClose: { appModel.showGitBranchPicker = false }
            )
            FlatHDivider()
            // ADR-081 Phase 3-4 — Stash/PR action row
            secondaryActionRow
        }
    }

    private func upstreamBadge(_ upstream: UpstreamStatus) -> some View {
        HStack(spacing: 6) {
            Image(systemName: upstream.isInSync ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(upstream.isInSync ? Theme.Color.success : Theme.Color.warning)
            Text(upstream.isInSync ? "원격과 동기화됨" : upstream.summary)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textSecondary)
            Spacer()
            Text(upstream.upstreamName)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 6)
        .background(Theme.Color.surface)
    }

    private var remoteActionRow: some View {
        HStack(spacing: 4) {
            actionButton("Pull", icon: "arrow.down.circle", color: Theme.Color.accent) {
                Task { await appModel.gitPull() }
            }
            actionButton("Push", icon: "arrow.up.circle", color: Theme.Color.accent) {
                Task { await appModel.gitPush() }
            }
            actionButton("Fetch", icon: "arrow.triangle.2.circlepath", color: Theme.Color.textSecondary) {
                Task { await appModel.gitFetch() }
            }
        }
        .padding(Theme.Spacing.sm)
        .disabled(appModel.gitOperationInProgress)
    }

    private var secondaryActionRow: some View {
        HStack(spacing: 4) {
            actionButton("Stash", icon: "tray.full", color: Theme.Color.textSecondary) {
                appModel.showGitBranchPicker = false
                appModel.showGitStashSheet = true
            }
            actionButton("PR 만들기", icon: "arrow.up.right.square", color: Theme.Color.accent) {
                prTitle = "feat: \(appModel.gitBranch ?? "")"
                prBody = ""
                withAnimation { showPRComposer = true }
            }
        }
        .padding(Theme.Spacing.sm)
        .disabled(appModel.gitOperationInProgress)
    }

    private func actionButton(_ label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(label)
                    .font(Theme.Typography.small.weight(.medium))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(color.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - PR composer (ADR-081 Phase 3)

    private var prComposer: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Button {
                    withAnimation { showPRComposer = false }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11))
                    Text("뒤로")
                        .font(Theme.Typography.small)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Color.textSecondary)
                Spacer()
                Text("Pull Request 만들기")
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.Color.text)
                Spacer()
                Spacer().frame(width: 50)  // visual balance
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.md)

            VStack(alignment: .leading, spacing: 4) {
                Text("제목")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .textCase(.uppercase)
                FlatTextField("예: feat: 사용자 인증 추가", text: $prTitle)
            }
            .padding(.horizontal, Theme.Spacing.md)

            VStack(alignment: .leading, spacing: 4) {
                Text("본문 (markdown 가능)")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .textCase(.uppercase)
                TextEditor(text: $prBody)
                    .font(Theme.Typography.small)
                    .padding(8)
                    .background(Theme.Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.sm)
                            .stroke(Theme.Color.borderSubtle, lineWidth: 1)
                    )
                    .frame(maxHeight: 160)
            }
            .padding(.horizontal, Theme.Spacing.md)

            Spacer(minLength: 0)
            Divider()
            HStack {
                Text("⚠ Push가 자동 실행됩니다.")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                Spacer()
                Button("취소") {
                    withAnimation { showPRComposer = false }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                Button {
                    Task {
                        creatingPR = true
                        defer { creatingPR = false }
                        await appModel.createPullRequest(title: prTitle, body: prBody.isEmpty ? nil : prBody)
                        appModel.showGitBranchPicker = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        if creatingPR {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.up.right.square.fill")
                                .font(.system(size: 11))
                        }
                        Text(creatingPR ? "만드는 중…" : "PR 만들기")
                            .font(Theme.Typography.small.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Theme.Color.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
                .buttonStyle(.plain)
                .disabled(prTitle.trimmingCharacters(in: .whitespaces).isEmpty || creatingPR)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.md)
        }
    }
}
