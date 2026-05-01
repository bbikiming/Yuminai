import SwiftUI

/// 채팅 입력창. CLI 룩 — `>` prompt + 평평한 입력.
public struct MessageInputView: View {
    @Binding public var text: String
    public let isStreaming: Bool
    public let placeholder: String
    public let onSend: () -> Void
    public let onCancel: () -> Void

    public init(
        text: Binding<String>,
        isStreaming: Bool,
        placeholder: String = "메시지 입력 — ⌘+Return 전송",
        onSend: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._text = text
        self.isStreaming = isStreaming
        self.placeholder = placeholder
        self.onSend = onSend
        self.onCancel = onCancel
    }

    public var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Text(">")
                .font(Theme.Typography.bodyEmphasis)
                .foregroundStyle(Theme.Color.accent)
                .padding(.top, 8)

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Color.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(Theme.Typography.body)
                    .scrollContentBackground(.hidden)
                    .padding(2)
                    .frame(minHeight: 60, maxHeight: 200)
            }
            .background(Theme.Color.bgInput)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .stroke(Theme.Color.border, lineWidth: Theme.Stroke.hairline)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

            VStack(spacing: 4) {
                if isStreaming {
                    FlatButton("cancel", variant: .destructive, size: .small) {
                        onCancel()
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                }
                FlatButton(isStreaming ? "..." : "send",
                           variant: isStreaming ? .ghost : .primary,
                           size: .small) {
                    triggerSend()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isStreaming || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Text("⌘↵")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Color.bg)
    }

    private func triggerSend() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }
        onSend()
    }
}
