import SwiftUI
import YuminaiCore
import YuminaiUI

/// Split layout에서 secondary pane 표시 (ADR-032 U4 + ADR-035 B4 dual-Composer).
///
/// active pane 외의 pane을 chat + 자체 Composer로 표시.
/// Composer 입력은 SecondaryPaneView 자체 @State로 보관.
/// Send 시 자동으로 setActivePane(이 pane) → input swap → sendMessage 흐름.
/// 즉 사용자는 양쪽에서 동시 입력하다가 send 누르면 그 pane으로 자동 전환되어 처리됨.
struct SecondaryPaneView: View {
    let pane: AgentPane
    let messages: [Message]
    let isStreaming: Bool
    let onActivate: () -> Void
    let onSend: (String) -> Void

    @State private var draft: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            FlatHDivider()
            ChatView(
                messages: messages,
                emptyStateText: "이 pane은 아직 대화가 없어요.\n아래 입력창에 보내거나 탭으로 활성화하세요.",
                assistantLabel: pane.displayName
            )
            .frame(maxHeight: .infinity)
            FlatHDivider()
            secondaryComposer
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
            if isStreaming {
                HStack(spacing: 3) {
                    PulseDot(color: Theme.Color.liveDot, size: 5)
                    Text("응답 중")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.liveDot)
                }
                .padding(.leading, 4)
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
            .help("이 pane으로 전환 (focus만)")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Color.surface)
    }

    private var secondaryComposer: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    Text("\(pane.displayName)에게 보내기 — 보내면 이 pane이 자동 활성화돼요")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textTertiary)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm + 2)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $draft)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Color.text)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, Theme.Spacing.md - 4)
                    .padding(.vertical, Theme.Spacing.sm - 4)
                    .frame(minHeight: 48, maxHeight: 120)
                    .focused($inputFocused)
            }
            HStack {
                Spacer()
                Button {
                    sendNow()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 10))
                        Text("보내기")
                            .font(Theme.Typography.small)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(canSend ? Theme.Color.accent : Theme.Color.surfaceHi)
                    .foregroundStyle(canSend ? .white : Theme.Color.textTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: .command)
                .help("⌘Return — 이 pane으로 보내기 (자동 활성)")
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
        }
        .background(Theme.Color.surface.opacity(0.4))
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming
    }

    private func sendNow() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSend(trimmed)
        draft = ""
    }
}
