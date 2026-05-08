import SwiftUI

/// 사용성 도움말 컴포넌트 (ADR-029 part 1).
///
/// 두 가지 패턴 제공:
/// - **HelpHint** — i 아이콘 + 클릭/호버로 popover (복잡/긴 안내)
/// - **InlineHint** — 항상 보이는 작은 안내 텍스트 (간단/짧은 안내)
/// - **EmptyStateHint** — 빈 상태 영역 친화 안내 (centered, icon + 본문)
///
/// 모든 텍스트는 한국어 친화 + 모든 색은 Theme 토큰.

// MARK: - HelpHint (i 아이콘 + popover)

public struct HelpHint: View {
    public let title: String?
    public let message: String
    public let placement: HelpHintPlacement

    @State private var showPopover = false

    public init(
        _ message: String,
        title: String? = nil,
        placement: HelpHintPlacement = .auto
    ) {
        self.title = title
        self.message = message
        self.placement = placement
    }

    public var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(showPopover ? Theme.Color.accent : Theme.Color.textTertiary)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .help(title ?? "도움말")
        .popover(isPresented: $showPopover, arrowEdge: placement.arrowEdge) {
            popoverContent
        }
        // ADR-071 Phase 2 — VoiceOver: 도움말 버튼임을 명시 + 내용 읽기
        .accessibilityLabel(title.map { "\($0) 도움말" } ?? "도움말")
        .accessibilityHint(message)
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.Color.text)
            }
            Text(message)
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: 320, alignment: .leading)
        .background(Theme.Color.bg)
    }
}

public enum HelpHintPlacement: Sendable {
    case auto, top, bottom, leading, trailing

    var arrowEdge: Edge {
        switch self {
        case .auto, .top: return .top
        case .bottom: return .bottom
        case .leading: return .leading
        case .trailing: return .trailing
        }
    }
}

// MARK: - InlineHint (상시 노출 — 짧은 안내)

public struct InlineHint: View {
    public let icon: String?
    public let text: String
    public let kind: Kind

    public init(_ text: String, icon: String? = "lightbulb", kind: Kind = .info) {
        self.icon = icon
        self.text = text
        self.kind = kind
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(kind.color)
                    .frame(width: 12, alignment: .center)
                    .padding(.top, 1)
            }
            Text(text)
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 6)
        .background(kind.background)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    public enum Kind: Sendable {
        case info, success, warning, tip

        var color: SwiftUI.Color {
            switch self {
            case .info: return Theme.Color.accent
            case .success: return .green
            case .warning: return .orange
            case .tip: return Theme.Color.accent
            }
        }

        var background: SwiftUI.Color {
            switch self {
            case .info, .tip: return Theme.Color.accentMuted
            case .success: return Theme.Color.gitAdded.opacity(0.10)
            case .warning: return Theme.Color.warningStrong.opacity(0.10)
            }
        }
    }
}

// MARK: - EmptyStateHint (빈 영역 안내)

public struct EmptyStateHint: View {
    public let icon: String
    public let title: String
    public let message: String?
    public let action: ActionConfig?

    public init(
        icon: String,
        title: String,
        message: String? = nil,
        action: ActionConfig? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.action = action
    }

    public struct ActionConfig {
        public let label: String
        public let perform: () -> Void

        public init(label: String, perform: @escaping () -> Void) {
            self.label = label
            self.perform = perform
        }
    }

    public var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.Color.textTertiary)
                .padding(.bottom, 4)
            Text(title)
                .font(Theme.Typography.body.weight(.medium))
                .foregroundStyle(Theme.Color.text)
            if let message {
                Text(message)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let action {
                Button(action: action.perform) {
                    Text(action.label)
                        .font(Theme.Typography.small.weight(.medium))
                }
                .padding(.top, 4)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: 280, maxHeight: .infinity)
    }
}

// MARK: - LabeledHint (LabeledContent와 함께 — i 아이콘 inline)

/// LabeledContent의 라벨 옆에 i 아이콘을 붙이고 싶을 때.
public struct LabelWithHint: View {
    public let text: String
    public let hint: String
    public let hintTitle: String?

    public init(_ text: String, hint: String, hintTitle: String? = nil) {
        self.text = text
        self.hint = hint
        self.hintTitle = hintTitle
    }

    public var body: some View {
        HStack(spacing: 4) {
            Text(text)
            HelpHint(hint, title: hintTitle, placement: .trailing)
        }
    }
}
