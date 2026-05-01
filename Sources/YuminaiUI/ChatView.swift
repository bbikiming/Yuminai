import SwiftUI
import YuminaiCore

/// 메시지 리스트 + 입력창. 메시지 도착 시 자동 스크롤.
public struct ChatView: View {
    public let messages: [Message]
    @Binding public var inputText: String
    public let isStreaming: Bool
    public let emptyStateText: String
    public let onSend: () -> Void
    public let onCancel: () -> Void

    public init(
        messages: [Message],
        inputText: Binding<String>,
        isStreaming: Bool,
        emptyStateText: String = "메시지를 입력해 시작하세요.",
        onSend: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.messages = messages
        self._inputText = inputText
        self.isStreaming = isStreaming
        self.emptyStateText = emptyStateText
        self.onSend = onSend
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 0) {
            messageList
            Divider()
            MessageInputView(
                text: $inputText,
                isStreaming: isStreaming,
                onSend: onSend,
                onCancel: onCancel
            )
        }
    }

    @ViewBuilder
    private var messageList: some View {
        if messages.isEmpty {
            VStack(spacing: Theme.Spacing.md) {
                Spacer()
                Text(emptyStateText)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Color.labelSecondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.md) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.vertical, Theme.Spacing.md)
                }
                .onChange(of: messages.last?.id) { _, _ in
                    guard let last = messages.last else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onAppear {
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}
