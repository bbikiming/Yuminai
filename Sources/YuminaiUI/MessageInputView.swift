import SwiftUI

/// 채팅 입력창. ⌘+Return 전송, Esc cancel.
public struct MessageInputView: View {
    @Binding public var text: String
    public let isStreaming: Bool
    public let placeholder: String
    public let onSend: () -> Void
    public let onCancel: () -> Void

    public init(
        text: Binding<String>,
        isStreaming: Bool,
        placeholder: String = "메시지 입력 (⌘+Return)",
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
        VStack(spacing: Theme.Spacing.sm) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(Theme.Typography.chatInput)
                        .foregroundStyle(Theme.Color.labelSecondary)
                        .padding(.horizontal, Theme.Spacing.sm + 4)
                        .padding(.vertical, Theme.Spacing.sm + 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(Theme.Typography.chatInput)
                    .scrollContentBackground(.hidden)
                    .padding(Theme.Spacing.xs)
                    .frame(minHeight: 60, maxHeight: 200)
            }
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )

            HStack {
                Text(hintText)
                    .font(.caption)
                    .foregroundStyle(Theme.Color.labelSecondary)
                Spacer()
                if isStreaming {
                    Button("Cancel", action: onCancel)
                        .keyboardShortcut(.escape, modifiers: [])
                        .controlSize(.small)
                }
                Button("Send", action: triggerSend)
                    .keyboardShortcut(.return, modifiers: .command)
                    .controlSize(.small)
                    .disabled(isStreaming || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Theme.Spacing.md)
    }

    private var hintText: String {
        isStreaming ? "스트리밍 중… Esc로 취소" : "⌘+Return 전송"
    }

    private func triggerSend() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }
        onSend()
    }
}
