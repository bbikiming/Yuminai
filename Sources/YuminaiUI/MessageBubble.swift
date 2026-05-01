import SwiftUI
import YuminaiCore

/// CLI 스타일 메시지 row. 박스/배경 없이 prefix 마커 + role 라벨 + 본문만.
public struct MessageBubble: View {
    public let message: Message

    public init(message: Message) {
        self.message = message
    }

    public var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.lg) {
            Text(prefix)
                .font(Theme.Typography.bodyEmphasis)
                .foregroundStyle(prefixColor)
                .frame(width: 12, alignment: .leading)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(roleLabel)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Text(displayContent)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Color.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var prefix: String {
        switch message.role {
        case .user: return ">"
        case .assistant: return "·"
        case .tool: return "○"
        case .system: return "—"
        }
    }

    private var prefixColor: SwiftUI.Color {
        switch message.role {
        case .user: return Theme.Color.rolePrefixUser
        case .assistant: return Theme.Color.rolePrefixAssistant
        case .tool: return Theme.Color.rolePrefixTool
        case .system: return Theme.Color.rolePrefixSystem
        }
    }

    private var roleLabel: String {
        switch message.role {
        case .user: return "you"
        case .assistant: return "claude"
        case .tool: return "tool"
        case .system: return "system"
        }
    }

    private var displayContent: String {
        message.content.isEmpty ? "(empty)" : message.content
    }
}
