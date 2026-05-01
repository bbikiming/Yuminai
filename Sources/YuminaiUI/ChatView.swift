import SwiftUI
import YuminaiCore

/// 메시지 리스트만. Composer는 외부에서 별도 구성.
public struct ChatView: View {
    public let messages: [Message]
    public let emptyStateText: String

    public init(
        messages: [Message],
        emptyStateText: String = "여기서 새 작업을 시작해보세요."
    ) {
        self.messages = messages
        self.emptyStateText = emptyStateText
    }

    public var body: some View {
        if messages.isEmpty {
            EmptyChatView(text: emptyStateText)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.vertical, Theme.Spacing.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Theme.Color.bg)
                .onChange(of: messages.last?.id) { _, _ in
                    guard let last = messages.last else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
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

struct EmptyChatView: View {
    let text: String

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.Color.textTertiary)
            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Color.textSecondary)
            Text("⌘ Return 보내기 · ⌘D 사용량 · ⌘⌥I Inspector")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.bg)
    }
}
