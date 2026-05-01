import SwiftUI
import YuminaiCore

/// 한 메시지를 화면에 표시. user는 우측 정렬 + 강조 색, assistant는 좌측 정렬.
public struct MessageBubble: View {
    public let message: Message

    public init(message: Message) {
        self.message = message
    }

    public var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            if message.role == .user {
                Spacer(minLength: Theme.Spacing.xxl)
            }

            VStack(alignment: alignment, spacing: Theme.Spacing.xs) {
                Text(roleLabel)
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Color.labelSecondary)

                Text(displayContent)
                    .font(Theme.Typography.chatMessage)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
                    .padding(Theme.Spacing.md)
                    .background(background)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
            .frame(maxWidth: 720, alignment: .leading)

            if message.role != .user {
                Spacer(minLength: Theme.Spacing.xxl)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    private var alignment: HorizontalAlignment {
        message.role == .user ? .trailing : .leading
    }

    private var roleLabel: String {
        switch message.role {
        case .user: return "You"
        case .assistant: return "Claude"
        case .system: return "System"
        case .tool: return "Tool"
        }
    }

    private var displayContent: String {
        message.content.isEmpty ? "(empty)" : message.content
    }

    private var background: Color {
        switch message.role {
        case .user: return Theme.Color.accent.opacity(0.18)
        case .assistant: return Color(NSColor.controlBackgroundColor)
        case .system: return Color(NSColor.windowBackgroundColor)
        case .tool: return Theme.Color.success.opacity(0.10)
        }
    }
}
