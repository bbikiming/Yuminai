import SwiftUI

/// Yuminai 공용 flat 컴포넌트 v3.
///
/// 디자인 명세: docs/design/60_UI_DESIGN_SPEC.md
/// 핵심 변화 (v2→v3):
/// - Sans-serif 본문 폰트 사용
/// - Border 강조 줄임 (focus/active만)
/// - SendButton/IconButton variant 추가

// MARK: - FlatButton

public struct FlatButton: View {
    public enum Variant: Sendable { case primary, secondary, ghost, destructive, accentSubtle }
    public enum Size: Sendable { case mini, small, regular, large }

    let label: String
    let icon: String?
    let variant: Variant
    let size: Size
    let action: () -> Void

    public init(
        _ label: String,
        icon: String? = nil,
        variant: Variant = .secondary,
        size: Size = .regular,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.icon = icon
        self.variant = variant
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon).font(.system(size: iconSize, weight: .medium))
                }
                if !label.isEmpty {
                    Text(label).font(font)
                }
            }
            .padding(.horizontal, hPadding)
            .padding(.vertical, vPadding)
            .frame(minWidth: label.isEmpty ? hPadding * 2 + iconSize : nil)
            .foregroundStyle(fg)
            .background(bg)
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(border, lineWidth: borderWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius))
        }
        .buttonStyle(.plain)
    }

    private var font: Font {
        switch size {
        case .mini: return Theme.Typography.micro
        case .small: return Theme.Typography.small
        case .regular: return Theme.Typography.label
        case .large: return Theme.Typography.bodyEmphasis
        }
    }
    private var iconSize: CGFloat {
        switch size {
        case .mini: return 10
        case .small: return 11
        case .regular: return 13
        case .large: return 15
        }
    }
    private var hPadding: CGFloat {
        switch size {
        case .mini: return Theme.Spacing.sm
        case .small: return Theme.Spacing.md
        case .regular: return Theme.Spacing.lg - 2
        case .large: return Theme.Spacing.lg
        }
    }
    private var vPadding: CGFloat {
        switch size {
        case .mini: return 3
        case .small: return Theme.Spacing.xs + 1
        case .regular: return Theme.Spacing.sm
        case .large: return Theme.Spacing.md
        }
    }
    private var radius: CGFloat { size == .mini ? Theme.Radius.sm : Theme.Radius.md }

    private var bg: SwiftUI.Color {
        switch variant {
        case .primary: return Theme.Color.accent
        case .secondary: return Theme.Color.surface
        case .ghost: return .clear
        case .destructive: return .clear
        case .accentSubtle: return Theme.Color.accentMuted
        }
    }
    private var fg: SwiftUI.Color {
        switch variant {
        case .primary: return .white
        case .destructive: return Theme.Color.danger
        case .ghost: return Theme.Color.textSecondary
        case .accentSubtle: return Theme.Color.accent
        default: return Theme.Color.text
        }
    }
    private var border: SwiftUI.Color {
        switch variant {
        case .primary: return .clear
        case .ghost: return .clear
        case .destructive: return Theme.Color.danger.opacity(0.4)
        case .accentSubtle: return Theme.Color.accentBorder
        default: return Theme.Color.borderSubtle
        }
    }
    private var borderWidth: CGFloat {
        switch variant {
        case .primary, .ghost: return 0
        default: return Theme.Stroke.hairline
        }
    }
}

// MARK: - IconButton (작은 toolbar 아이콘)

public struct IconButton: View {
    let icon: String
    let size: CGFloat
    let action: () -> Void
    var help: String?

    public init(_ icon: String, size: CGFloat = 14, help: String? = nil, action: @escaping () -> Void) {
        self.icon = icon
        self.size = size
        self.help = help
        self.action = action
    }

    @State private var hovering = false

    public var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(hovering ? Theme.Color.text : Theme.Color.textSecondary)
                .frame(width: size + 14, height: size + 14)
                .background(
                    hovering ? Theme.Color.surfaceHi : Color.clear,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.sm)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help ?? "")
    }
}

// MARK: - SendButton (Composer 전용)

public struct SendButton: View {
    public let isStreaming: Bool
    public let isEnabled: Bool
    public let onSend: () -> Void
    public let onStop: () -> Void

    public init(isStreaming: Bool, isEnabled: Bool, onSend: @escaping () -> Void, onStop: @escaping () -> Void) {
        self.isStreaming = isStreaming
        self.isEnabled = isEnabled
        self.onSend = onSend
        self.onStop = onStop
    }

    public var body: some View {
        if isStreaming {
            Button(action: onStop) {
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11, weight: .medium))
                    Text("stop")
                        .font(Theme.Typography.label)
                    Text("esc")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.danger.opacity(0.6))
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .foregroundStyle(Theme.Color.danger)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(Theme.Color.danger.opacity(0.4), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        } else {
            Button(action: onSend) {
                HStack(spacing: 6) {
                    Text("send")
                        .font(Theme.Typography.label)
                    Text("⌘↵")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .foregroundStyle(.white)
                .background(
                    isEnabled ? Theme.Color.accent : Theme.Color.surfaceHi,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.md)
                )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1.0 : 0.5)
        }
    }
}

// MARK: - FlatTextField

public struct FlatTextField: View {
    @Binding var text: String
    let placeholder: String
    var isSecure: Bool = false

    public init(_ placeholder: String, text: Binding<String>, isSecure: Bool = false) {
        self.placeholder = placeholder
        self._text = text
        self.isSecure = isSecure
    }

    public var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .textFieldStyle(.plain)
        .font(Theme.Typography.body)
        .foregroundStyle(Theme.Color.text)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm + 2)
        .background(Theme.Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Theme.Color.borderSubtle, lineWidth: Theme.Stroke.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }
}

// MARK: - FlatSection / FlatRow

public struct FlatSection<Content: View>: View {
    let title: String?
    let footer: String?
    @ViewBuilder let content: () -> Content

    public init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if let title {
                Text(title)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.6)
            }
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(Theme.Spacing.lg)
            .background(Theme.Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg)
                    .stroke(Theme.Color.borderSubtle, lineWidth: Theme.Stroke.hairline)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))

            if let footer {
                Text(footer)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
        }
    }
}

public struct FlatRow<Control: View>: View {
    let label: String
    let helper: String?
    @ViewBuilder let control: () -> Control

    public init(_ label: String, helper: String? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.label = label
        self.helper = helper
        self.control = control
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: Theme.Spacing.lg) {
                Text(label)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Color.text)
                    .frame(width: 140, alignment: .leading)
                control()
                Spacer(minLength: 0)
            }
            if let helper {
                Text(helper)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(.leading, 140 + Theme.Spacing.lg)
            }
        }
        .padding(.vertical, Theme.Spacing.sm)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.Color.borderSubtle).frame(height: Theme.Stroke.hairline)
                .padding(.horizontal, -Theme.Spacing.lg)
        }
    }
}

// MARK: - Dividers

public struct FlatHDivider: View {
    public init() {}
    public var body: some View {
        Rectangle().fill(Theme.Color.borderSubtle).frame(height: Theme.Stroke.hairline)
    }
}

public struct FlatVDivider: View {
    public init() {}
    public var body: some View {
        Rectangle().fill(Theme.Color.borderSubtle).frame(width: Theme.Stroke.hairline)
    }
}

// MARK: - FlatToggle

public struct FlatToggle: View {
    let label: String
    @Binding var isOn: Bool

    public init(_ label: String, isOn: Binding<Bool>) {
        self.label = label
        self._isOn = isOn
    }

    public var body: some View {
        Toggle(isOn: $isOn) {
            Text(label).font(Theme.Typography.body).foregroundStyle(Theme.Color.text)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}

// MARK: - Streaming pulse dot

public struct PulseDot: View {
    let color: SwiftUI.Color
    let size: CGFloat
    @State private var pulsing = false

    public init(color: SwiftUI.Color = Theme.Color.accent, size: CGFloat = 6) {
        self.color = color
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(pulsing ? 0.4 : 1.0)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: Theme.Animation.pulseDuration / 2).repeatForever(autoreverses: true)
                ) {
                    pulsing = true
                }
            }
    }
}
