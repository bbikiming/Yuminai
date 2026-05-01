import SwiftUI

/// CLI 친화 플랫 버튼.
public struct FlatButton: View {
    public enum Variant: Sendable { case primary, secondary, ghost, destructive, accent }
    public enum Size: Sendable { case small, regular }

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
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon).font(.system(size: iconSize))
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
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .stroke(border, lineWidth: Theme.Stroke.hairline)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
        .buttonStyle(.plain)
    }

    private var font: Font {
        size == .small ? Theme.Typography.small : Theme.Typography.label
    }
    private var iconSize: CGFloat { size == .small ? 9 : 11 }
    private var hPadding: CGFloat { size == .small ? Theme.Spacing.md : Theme.Spacing.lg }
    private var vPadding: CGFloat { size == .small ? 3 : Theme.Spacing.sm }

    private var bg: SwiftUI.Color {
        switch variant {
        case .primary, .accent: return Theme.Color.accent
        case .secondary: return Theme.Color.bgPanel
        case .ghost: return .clear
        case .destructive: return Theme.Color.error.opacity(0.10)
        }
    }
    private var fg: SwiftUI.Color {
        switch variant {
        case .primary, .accent: return .white
        case .destructive: return Theme.Color.error
        case .ghost: return Theme.Color.textSecondary
        default: return Theme.Color.text
        }
    }
    private var border: SwiftUI.Color {
        switch variant {
        case .primary, .accent: return Theme.Color.accent
        case .ghost: return .clear
        case .destructive: return Theme.Color.error.opacity(0.30)
        default: return Theme.Color.border
        }
    }
}

/// 플랫 텍스트 입력. SecureField 옵션.
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
        .padding(.vertical, Theme.Spacing.sm + 1)
        .background(Theme.Color.bgInput)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .stroke(Theme.Color.border, lineWidth: Theme.Stroke.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }
}

/// 플랫 form section — 헤더 + 카드 형식.
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
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .textCase(.uppercase)
                    .padding(.horizontal, Theme.Spacing.xs)
            }
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(Theme.Spacing.lg)
            .background(Theme.Color.bgPanel)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(Theme.Color.border, lineWidth: Theme.Stroke.hairline)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

            if let footer {
                Text(footer)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(.horizontal, Theme.Spacing.xs)
            }
        }
    }
}

/// 한 form row (label + control).
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

/// 가는 가로 구분선.
public struct FlatHDivider: View {
    public init() {}
    public var body: some View {
        Rectangle().fill(Theme.Color.border).frame(height: Theme.Stroke.hairline)
    }
}

/// 가는 세로 구분선.
public struct FlatVDivider: View {
    public init() {}
    public var body: some View {
        Rectangle().fill(Theme.Color.border).frame(width: Theme.Stroke.hairline)
    }
}

/// 플랫 토글 — 라벨 우측에 작은 토글.
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
