import SwiftUI
import YuminaiCore
import YuminaiUI

/// Split layout에서 secondary pane 표시 (ADR-032 U4).
///
/// active pane 외의 pane을 read-only로 보여주고, 클릭 시 active로 전환할 수 있게 함.
/// Composer는 active pane만 — secondary는 messages만 보임.
struct SecondaryPaneView: View {
    let pane: AgentPane
    let messages: [Message]
    let onActivate: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            FlatHDivider()
            ChatView(
                messages: messages,
                emptyStateText: "이 pane은 아직 대화가 없어요.\n탭을 눌러 활성화하세요.",
                assistantLabel: pane.displayName
            )
            .frame(maxHeight: .infinity)
        }
        .background(Theme.Color.bg.opacity(0.95))
        .overlay(alignment: .leading) { FlatVDivider() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: pane.agentKind.icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Color.textSecondary)
            Text(pane.displayName)
                .font(Theme.Typography.small.weight(.medium))
                .foregroundStyle(Theme.Color.text)
            if pane.role == .primary {
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Theme.Color.accent)
            }
            Spacer()
            Text("보조")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.Color.surfaceHi)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            Button(action: onActivate) {
                Image(systemName: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .buttonStyle(.plain)
            .help("이 pane으로 전환")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Color.surface)
    }
}
