import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-079 Phase 4** — Git 브랜치 picker popover.
///
/// Toolbar branch indicator 클릭 시 표시. 브랜치 목록 + 새 브랜치 만들기.
struct GitBranchPickerPopover: View {
    let branches: [BranchInfo]
    let currentBranch: String
    let onSwitch: (String) -> Void
    let onCreateBranch: (String) -> Void
    let onClose: () -> Void

    @State private var newBranchName: String = ""
    @State private var showNewBranchInput: Bool = false
    @FocusState private var newBranchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            FlatHDivider()
            branchList
            FlatHDivider()
            footer
        }
        .frame(width: 320, height: showNewBranchInput ? 380 : 340)
        .background(Theme.Color.bg)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Color.accent)
            Text("브랜치")
                .font(Theme.Typography.body.weight(.semibold))
                .foregroundStyle(Theme.Color.text)
            Spacer()
            Text("\(branches.count)개")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
        }
        .padding(Theme.Spacing.md)
    }

    private var branchList: some View {
        ScrollView {
            VStack(spacing: 1) {
                ForEach(branches) { branch in
                    branchRow(branch)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func branchRow(_ branch: BranchInfo) -> some View {
        Button {
            if !branch.isCurrent {
                onSwitch(branch.name)
                onClose()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: branch.isCurrent ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(branch.isCurrent ? Theme.Color.accent : Theme.Color.textTertiary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(branch.name)
                        .font(Theme.Typography.monoSmall)
                        .foregroundStyle(branch.isCurrent ? Theme.Color.text : Theme.Color.textSecondary)
                    Text(branch.lastCommitRelative)
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 6)
            .background(branch.isCurrent ? Theme.Color.accentMuted : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(branch.name)\(branch.isCurrent ? ", 현재 브랜치" : "")")
        .accessibilityHint(branch.isCurrent ? "" : "탭하여 이 브랜치로 전환")
    }

    private var footer: some View {
        VStack(spacing: 0) {
            if showNewBranchInput {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Theme.Color.accent)
                        .accessibilityHidden(true)
                    TextField("새 브랜치 이름 (예: feature/auth)", text: $newBranchName)
                        .textFieldStyle(.plain)
                        .font(Theme.Typography.monoSmall)
                        .focused($newBranchFocused)
                        .onSubmit { commitNewBranch() }
                        .accessibilityLabel("새 브랜치 이름")
                    Button("만들기") {
                        commitNewBranch()
                    }
                    .disabled(newBranchName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(Theme.Spacing.md)
            } else {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        showNewBranchInput = true
                        newBranchFocused = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                            .foregroundStyle(Theme.Color.accent)
                        Text("새 브랜치 만들기")
                            .font(Theme.Typography.small.weight(.medium))
                            .foregroundStyle(Theme.Color.text)
                        Spacer()
                    }
                    .padding(Theme.Spacing.md)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("새 브랜치 만들기")
            }
        }
    }

    private func commitNewBranch() {
        let trimmed = newBranchName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onCreateBranch(trimmed)
        newBranchName = ""
        showNewBranchInput = false
        onClose()
    }
}
