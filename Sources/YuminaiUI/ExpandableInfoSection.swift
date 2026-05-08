import SwiftUI

/// **ADR-101** — 점진 정보 노출 재사용 컴포넌트.
///
/// 기본적으로 접힌 상태로 시작하며, chevron 클릭 시 추가 정보를 spring 애니메이션으로 펼친다.
/// `TelegramBotListSection`, `TelegramBotGroupSection`, `TelegramBotBindingSection`
/// 등 행(row) 내부의 부가 정보 영역에 통일적으로 사용한다.
///
/// ## 사용 예
/// ```swift
/// ExpandableInfoSection(label: "자세히 보기") {
///     VStack(alignment: .leading) {
///         Text("keychainKey: \(bot.keychainKey)")
///         Text("허용 \(bot.allowedUserIds.count)명")
///     }
/// }
/// ```
public struct ExpandableInfoSection<Content: View>: View {
    public let label: String
    public let labelIcon: String?
    public let content: () -> Content

    @State private var isExpanded: Bool = false

    public init(
        label: String,
        labelIcon: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.label = label
        self.labelIcon = labelIcon
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 4) {
                    if let labelIcon {
                        Image(systemName: labelIcon)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.Color.textTertiary)
                            .accessibilityHidden(true)
                    }
                    Text(label)
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.Color.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.spring(response: 0.30, dampingFraction: 0.85), value: isExpanded)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .padding(.top, Theme.Spacing.xs)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isExpanded)
    }

    private func toggle() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isExpanded.toggle()
        }
    }
}

// MARK: - ChatTypeBadge

/// chat id 부호에 따라 "1:1 대화" / "그룹 채팅" 배지를 표시.
public struct ChatTypeBadge: View {
    public let chatId: Int64

    public init(chatId: Int64) {
        self.chatId = chatId
    }

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: chatId < 0 ? "person.3.fill" : "person.crop.circle.fill")
                .font(.system(size: 8))
                .accessibilityHidden(true)
            Text(chatId < 0 ? "그룹 채팅" : "1:1 대화")
                .font(Theme.Typography.micro)
        }
        .foregroundStyle(chatId < 0 ? Theme.Color.warningStrong : Theme.Color.accent)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background((chatId < 0 ? Theme.Color.warningStrong : Theme.Color.accent).opacity(0.10))
        .clipShape(Capsule())
        .accessibilityLabel(chatId < 0 ? "그룹 채팅" : "1:1 대화")
    }
}

// MARK: - DuplicateBadge

/// 이미 등록된 봇임을 나타내는 배지 (회색 capsule + checkmark.shield).
public struct DuplicateBadge: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 9))
                .accessibilityHidden(true)
            Text("이미 등록됨")
                .font(Theme.Typography.micro)
        }
        .foregroundStyle(Theme.Color.textTertiary)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(Theme.Color.surfaceHi)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.Color.borderSubtle, lineWidth: 0.5))
        .accessibilityLabel("이미 등록된 봇")
    }
}
