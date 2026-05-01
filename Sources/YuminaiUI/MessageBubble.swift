import SwiftUI
import YuminaiCore

/// 메시지 한 row. role에 따라 user는 박스 + 좌측 accent bar, assistant/tool은 박스 없는 본문.
public struct MessageBubble: View {
    public let message: Message
    public let assistantLabel: String

    public init(message: Message, assistantLabel: String = "Claude") {
        self.message = message
        self.assistantLabel = assistantLabel
    }

    public var body: some View {
        switch message.role {
        case .user:
            UserMessageBlock(message: message)
        case .assistant:
            AssistantMessageBlock(message: message, label: assistantLabel)
        case .tool:
            ToolMessageBlock(message: message)
        case .system:
            SystemMessageBlock(message: message)
        }
    }
}

// MARK: - User

public struct UserMessageBlock: View {
    public let message: Message
    public init(message: Message) { self.message = message }

    public var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(Theme.Color.userAccent)
                .frame(width: Theme.Stroke.bar)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayContent)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Color.userText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
        }
        .background(Theme.Color.userBg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .padding(.horizontal, Theme.Layout.contentPaddingH)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var displayContent: String {
        message.content.isEmpty ? "(empty)" : message.content
    }
}

// MARK: - Assistant — 박스 없음

public struct AssistantMessageBlock: View {
    public let message: Message
    public let label: String
    public init(message: Message, label: String = "Claude") {
        self.message = message
        self.label = label
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
                .textCase(.uppercase)
                .tracking(0.6)
            Text(displayContent)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Color.assistantText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.Layout.contentPaddingH)
        .padding(.vertical, Theme.Spacing.md)
    }

    private var displayContent: String {
        message.content.isEmpty ? "(empty)" : message.content
    }
}

// MARK: - Tool — inline subtle

public struct ToolMessageBlock: View {
    public let message: Message
    public init(message: Message) { self.message = message }

    public var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(Theme.Color.success)
                .padding(.top, 6)
            Text(message.content)
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.toolText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.Layout.contentPaddingH)
        .padding(.vertical, 3)
    }
}

// MARK: - System — 옅게

public struct SystemMessageBlock: View {
    public let message: Message
    public init(message: Message) { self.message = message }

    public var body: some View {
        Text(message.content)
            .font(Theme.Typography.small)
            .foregroundStyle(Theme.Color.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, Theme.Layout.contentPaddingH)
            .padding(.vertical, Theme.Spacing.xs)
    }
}
