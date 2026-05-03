import SwiftUI

/// Yuminai 공용 flat 컴포넌트 v3.
///
/// 디자인 명세: docs/design/60_UI_DESIGN_SPEC.md
/// 핵심 변화 (v2→v3):
/// - Sans-serif 본문 폰트 사용
/// - Border 강조 줄임 (focus/active만)
/// - SendButton/IconButton variant 추가

// MARK: - Interaction modifiers

/// 모든 버튼 공용 — press 시 0.97 scale + 80ms ease.
public struct PressedScaleStyle: ButtonStyle {
    public let scale: CGFloat
    public init(scale: CGFloat = 0.97) { self.scale = scale }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// Primary CTA 전용 — hover scale 1.02 + press 0.97.
public struct PrimaryButtonStyle: ButtonStyle {
    @State private var hovering = false
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(scaleValue(pressed: configuration.isPressed))
            .brightness(hovering && !configuration.isPressed ? 0.04 : 0)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 }
    }

    private func scaleValue(pressed: Bool) -> CGFloat {
        if pressed { return 0.97 }
        if hovering { return 1.02 }
        return 1.0
    }
}

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

    @State private var hovering = false

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
            .background(hovering ? bgHover : bg)
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(border, lineWidth: borderWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .animation(.easeOut(duration: 0.10), value: hovering)
        }
        .buttonStyle(variant == .primary ? AnyButtonStyle(PrimaryButtonStyle()) : AnyButtonStyle(PressedScaleStyle()))
        .onHover { hovering = $0 }
    }

    private var bgHover: SwiftUI.Color {
        switch variant {
        case .primary: return Theme.Color.accentHover
        case .secondary: return Theme.Color.surfaceHi
        case .ghost: return Theme.Color.surfaceHi
        case .destructive: return Theme.Color.danger.opacity(0.18)
        case .accentSubtle: return Theme.Color.accentMuted
        }
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

/// **ADR-070 Phase 5** — IconButton hover 시 즉시 표시할 풍부한 안내 정보.
public struct ToolbarHoverInfo: Sendable, Equatable {
    public let title: String
    public let body: String
    public let shortcut: String?

    public init(title: String, body: String, shortcut: String? = nil) {
        self.title = title
        self.body = body
        self.shortcut = shortcut
    }
}

public struct IconButton: View {
    let icon: String
    let size: CGFloat
    let action: () -> Void
    var help: String?
    /// **ADR-070 Phase 5** — 풍부한 hover popover (제목 + 본문 + 단축키).
    /// 지정 시 macOS 기본 .help() (1.5초 delay) 대신 즉각적인 popover로 안내.
    var detailedHelp: ToolbarHoverInfo?
    /// **ADR-072 Phase 5** — macOS Voice Control 동의어 (accessibilityInputLabels).
    /// 사용자가 다양한 한국어 표현으로 음성 호출 가능. 예: ["보내기", "전송", "송신"]
    var voiceLabels: [String]

    public init(
        _ icon: String,
        size: CGFloat = 14,
        help: String? = nil,
        detailedHelp: ToolbarHoverInfo? = nil,
        voiceLabels: [String] = [],
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.size = size
        self.help = help
        self.detailedHelp = detailedHelp
        self.voiceLabels = voiceLabels
        self.action = action
    }

    @State private var hovering = false
    @State private var showPopover = false
    /// hover 시작 시간 — 짧은 delay 후 popover 표시.
    @State private var hoverTask: Task<Void, Never>?
    /// **ADR-072 Phase 3** — 키보드 focus 추적 (focus ring 표시용).
    @FocusState private var focused: Bool

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
                .animation(.easeOut(duration: 0.10), value: hovering)
        }
        .buttonStyle(PressedScaleStyle(scale: 0.92))
        .focused($focused)
        // ADR-072 Phase 3 — WCAG 2.4.7 / 2.4.13 — visible focus ring
        .yuminaiFocusRing(focused)
        .onHover { isHovering in
            hovering = isHovering
            handleHoverChange(isHovering)
        }
        .help(help ?? "")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            if let info = detailedHelp {
                hoverPopoverContent(info)
            }
        }
        // ADR-071 Phase 2 — VoiceOver: detailedHelp.title 우선, fallback help
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(detailedHelp?.body ?? "")
        // ADR-072 Phase 5 — macOS Voice Control 동의어
        // 사용자가 다양한 한국어 표현으로 호출 가능 (Apple HIG: "align with words people say")
        .accessibilityInputLabels(voiceLabels.isEmpty ? [accessibilityText] : voiceLabels)
    }

    /// ADR-071 Phase 2 — VoiceOver용 raw label.
    /// 우선순위: detailedHelp.title → help → "버튼".
    private var accessibilityText: String {
        if let info = detailedHelp {
            if let shortcut = info.shortcut {
                return "\(info.title), 단축키 \(shortcut)"
            }
            return info.title
        }
        return help ?? "버튼"
    }

    private func handleHoverChange(_ isHovering: Bool) {
        guard detailedHelp != nil else { return }
        hoverTask?.cancel()
        if isHovering {
            // 짧은 delay (400ms) 후 popover — 빠른 hover 통과 시 표시 안 됨
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                if !Task.isCancelled && hovering {
                    showPopover = true
                }
            }
        } else {
            showPopover = false
        }
    }

    @ViewBuilder
    private func hoverPopoverContent(_ info: ToolbarHoverInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(info.title)
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.Color.text)
                Spacer()
                if let shortcut = info.shortcut {
                    Text(shortcut)
                        .font(Theme.Typography.monoSmall)
                        .foregroundStyle(Theme.Color.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.Color.surfaceHi)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            Text(info.body)
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.md)
        .frame(width: 260, alignment: .leading)
        .background(Theme.Color.bg)
    }
}

/// AnyButtonStyle wrapper — variant 선택용.
public struct AnyButtonStyle: ButtonStyle {
    private let _makeBody: (Configuration) -> AnyView
    public init<S: ButtonStyle>(_ style: S) {
        self._makeBody = { config in AnyView(style.makeBody(configuration: config)) }
    }
    public func makeBody(configuration: Configuration) -> some View {
        _makeBody(configuration)
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

    @State private var hovering = false

    public var body: some View {
        if isStreaming {
            Button(action: onStop) {
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11, weight: .medium))
                    Text("중단")
                        .font(Theme.Typography.label)
                    Text("esc")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.danger.opacity(0.6))
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .foregroundStyle(Theme.Color.danger)
                .background(hovering ? Theme.Color.danger.opacity(0.10) : .clear)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(Theme.Color.danger.opacity(0.4), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .animation(.easeOut(duration: 0.10), value: hovering)
            }
            .buttonStyle(PressedScaleStyle())
            .onHover { hovering = $0 }
            .keyboardShortcut(.escape, modifiers: [])
            .help("응답을 중단합니다 (Esc)")
            // ADR-071 Phase 4 — VoiceOver
            .accessibilityLabel("응답 중단")
            .accessibilityHint("에이전트가 작성 중인 응답을 중단합니다. 단축키 Escape.")
            // ADR-072 Phase 5 — Voice Control 동의어
            .accessibilityInputLabels(["중단", "정지", "스톱", "응답 중단", "취소"])
        } else {
            Button(action: onSend) {
                HStack(spacing: 6) {
                    Text("보내기")
                        .font(Theme.Typography.label)
                    Text("⌘↵")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .foregroundStyle(.white)
                .background(
                    isEnabled
                        ? (hovering ? Theme.Color.accentHover : Theme.Color.accent)
                        : Theme.Color.surfaceHi,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.md)
                )
                .animation(.easeOut(duration: 0.10), value: hovering)
            }
            .buttonStyle(PrimaryButtonStyle())
            .onHover { hovering = $0 }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1.0 : 0.5)
            .help("메시지를 보냅니다 (⌘ Return)")
            // ADR-071 Phase 4 — VoiceOver
            .accessibilityLabel("메시지 보내기")
            .accessibilityHint(isEnabled ? "메시지를 에이전트에게 전송합니다. 단축키 Command Return." : "메시지를 입력하면 활성화됩니다.")
            // ADR-072 Phase 5 — Voice Control 동의어
            .accessibilityInputLabels(["보내기", "전송", "송신", "메시지 전송", "send"])
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
