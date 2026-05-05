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
                .accessibilityHidden(true)

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
        // ADR-071 Phase 4 — VoiceOver: 사용자 메시지임을 명시
        .accessibilityElement(children: .combine)
        .accessibilityLabel("내 메시지")
        .accessibilityValue(displayContent)
    }

    private var displayContent: String {
        message.content.isEmpty ? "(empty)" : message.content
    }
}

// MARK: - Assistant — 박스 없음

public struct AssistantMessageBlock: View {
    public let message: Message
    public let label: String
    @State private var showAttributionDetail: Bool = false

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
            // **ADR-115 P1-2** — attribution footer (참고 자료/프로필)
            if let attribution = message.attribution, !attribution.isEmpty {
                attributionFooter(attribution)
            }
        }
        .padding(.horizontal, Theme.Layout.contentPaddingH)
        .padding(.vertical, Theme.Spacing.md)
        // ADR-071 Phase 4 — VoiceOver: 에이전트 응답임을 명시
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) 답장")
        .accessibilityValue(displayContent)
    }

    private var displayContent: String {
        message.content.isEmpty ? "(empty)" : message.content
    }

    /// **ADR-115 P1-2** — 참고 자료/프로필 attribution footer.
    /// 작고 회색 텍스트 + disclosure 토글.
    @ViewBuilder
    private func attributionFooter(_ attribution: MessageAttribution) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showAttributionDetail.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showAttributionDetail ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .medium))
                    Text(attribution.displaySummary)
                        .font(Theme.Typography.caption)
                        .lineLimit(1)
                }
                .foregroundStyle(Theme.Color.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("참고 정보 \(showAttributionDetail ? "숨기기" : "보기")")

            if showAttributionDetail {
                VStack(alignment: .leading, spacing: 2) {
                    if !attribution.attachedLibraryItems.isEmpty {
                        Label {
                            Text(attribution.attachedLibraryItems.joined(separator: ", "))
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Color.textTertiary)
                        } icon: {
                            Image(systemName: "books.vertical")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.Color.textTertiary)
                        }
                    }
                    if let profile = attribution.profileSnapshotSummary, !profile.isEmpty {
                        Label {
                            Text(profile)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Color.textTertiary)
                        } icon: {
                            Image(systemName: "person.circle")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.Color.textTertiary)
                        }
                    }
                }
                .padding(.leading, Theme.Spacing.md)
            }
        }
    }
}

// MARK: - Theme extension for caption typography
private extension Theme.Typography {
    static var caption: Font { .system(size: 10) }
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
                .accessibilityHidden(true)
            Text(message.content)
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.toolText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.Layout.contentPaddingH)
        .padding(.vertical, 3)
        // ADR-071 Phase 4 — VoiceOver: 도구 호출임을 명시
        .accessibilityElement(children: .combine)
        .accessibilityLabel("도구 호출")
        .accessibilityValue(message.content)
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
            // ADR-071 Phase 4 — VoiceOver: 시스템 안내임을 명시
            .accessibilityElement(children: .combine)
            .accessibilityLabel("시스템 안내")
            .accessibilityValue(message.content)
    }
}
