import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-081 Phase 4** — Git stash 관리 sheet (간단한 list + apply/pop/drop).
struct GitStashSheet: View {
    @Environment(AppModel.self) private var appModel
    @State private var stashes: [StashInfo] = []
    @State private var loading: Bool = true
    @State private var newStashMessage: String = ""

    var body: some View {
        YuminaiSheet(width: 540, height: 480) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                createSection
                Divider()
                if loading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .frame(height: 100)
                } else if stashes.isEmpty {
                    EmptyStateHint(
                        icon: "tray",
                        title: "저장된 stash 없음",
                        message: "현재 작업 중인 변경사항을 잠시 보관하려면 위 입력에 메시지를 적고 ‘새 stash 만들기’를 누르세요."
                    )
                } else {
                    stashList
                }
            }
            .padding(Theme.Spacing.xl)
        } footer: {
            HStack {
                Spacer()
                FlatButton("닫기", variant: .secondary) {
                    appModel.showGitStashSheet = false
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .task { await reload() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "tray.full.fill")
                    .foregroundStyle(Theme.Color.accent)
                    .accessibilityHidden(true)
                Text("Git Stash 관리")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
            }
            Text("작업 중인 변경사항을 잠시 보관하거나 다시 적용해요. 브랜치 전환 전에 유용합니다.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var createSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("새 stash 만들기")
            HStack(spacing: 8) {
                FlatTextField("메시지 (선택)", text: $newStashMessage)
                    .accessibilityLabel("Stash 메시지")
                Button {
                    Task {
                        await appModel.gitCreateStash(message: newStashMessage)
                        newStashMessage = ""
                        await reload()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 11))
                        Text("새 stash")
                            .font(Theme.Typography.small.weight(.medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.Color.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("새 stash 만들기")
            }
        }
    }

    private var stashList: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("저장된 stash (\(stashes.count)개)")
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(stashes) { stash in
                        stashRow(stash)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func stashRow(_ stash: StashInfo) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(stash.message)
                    .font(Theme.Typography.body.weight(.medium))
                    .foregroundStyle(Theme.Color.text)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(stash.ref)
                        .font(Theme.Typography.monoSmall)
                        .foregroundStyle(Theme.Color.textTertiary)
                    Text("·")
                        .foregroundStyle(Theme.Color.textTertiary)
                    Text(stash.shortSha)
                        .font(Theme.Typography.monoSmall)
                        .foregroundStyle(Theme.Color.textTertiary)
                    Text("·")
                        .foregroundStyle(Theme.Color.textTertiary)
                    Text(stash.relativeDate)
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
            }
            Spacer()
            actionButton("적용", icon: "arrow.down.doc") {
                Task {
                    await appModel.gitApplyStash(stash.ref)
                    await reload()
                }
            }
            actionButton("Pop", icon: "arrow.up.doc.on.clipboard") {
                Task {
                    await appModel.gitPopStash(stash.ref)
                    await reload()
                }
            }
            actionButton("삭제", icon: "trash", destructive: true) {
                Task {
                    await appModel.gitDropStash(stash.ref)
                    await reload()
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 8)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stash \(stash.ref): \(stash.message), \(stash.relativeDate)")
    }

    private func actionButton(_ label: String, icon: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                Text(label)
                    .font(Theme.Typography.micro)
            }
            .foregroundStyle(destructive ? Theme.Color.danger : Theme.Color.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Theme.Color.surfaceHi)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
        stashes = await appModel.gitStashes()
        loading = false
    }
}
