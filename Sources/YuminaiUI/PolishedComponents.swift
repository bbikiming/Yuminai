import SwiftUI

/// **ADR-090** — 정제된 GUI 컴포넌트 모음.
///
/// 기존 FlatComponents가 minimal·flat 스타일이라면, 이 모듈은 더 풍부한 시각 표현
/// (subtle elevation, spring animation, SF Symbol effect, gradient borders)을 제공.
///
/// 사용 가이드:
/// - 정보 그룹화: `CardSection` (rounded card + soft border + optional 헤더)
/// - 섹션 헤더: `SectionHeaderRow` (icon + title + caption + optional trailing CTA)
/// - 라디오 선택: `RadioCardButton` (큰 hit target + 강조 상태 + spring)
/// - 빈 상태: `AnimatedEmptyState` (symbol effect + 부드러운 fade-in)
/// - 행위 미러: `IconHero` (큰 icon + halo gradient)

// MARK: - CardSection

/// Sheet/패널 안의 정보 그룹을 명확히 시각적으로 분리하는 카드.
/// 기본: surface 배경 + 0.5px border + 8px corner radius.
/// 변형: `style: .elevated` (shadow), `.subtle` (border only).
public struct CardSection<Content: View>: View {
    public enum Style {
        case subtle    // border only
        case elevated  // border + shadow
        case accent    // 좌측 4px accent strip + bg
    }

    public let style: Style
    public let accentColor: Color?
    public let content: () -> Content

    public init(
        style: Style = .subtle,
        accentColor: Color? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.style = style
        self.accentColor = accentColor
        self.content = content
    }

    public var body: some View {
        content()
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Color.surface)
            .overlay(alignment: .leading) {
                if style == .accent, let accentColor {
                    Rectangle()
                        .fill(accentColor)
                        .frame(width: 3)
                        .accessibilityHidden(true)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(borderColor, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
    }

    private var borderColor: Color {
        switch style {
        case .subtle: return Theme.Color.borderSubtle
        case .elevated: return Theme.Color.borderSubtle
        case .accent: return (accentColor ?? Theme.Color.accent).opacity(0.25)
        }
    }

    private var shadowColor: Color {
        switch style {
        case .subtle, .accent: return .black.opacity(0.04)
        case .elevated: return .black.opacity(0.10)
        }
    }

    private var shadowRadius: CGFloat {
        switch style {
        case .subtle, .accent: return 2
        case .elevated: return 8
        }
    }

    private var shadowY: CGFloat {
        switch style {
        case .subtle, .accent: return 1
        case .elevated: return 3
        }
    }
}

// MARK: - SectionHeaderRow

/// 카드 위 또는 sheet 안 섹션 헤더.
///
/// - leading: SF Symbol icon (color tint)
/// - title (semibold) + caption (textTertiary, optional)
/// - trailing: 버튼 또는 badge (optional)
public struct SectionHeaderRow<Trailing: View>: View {
    public let icon: String
    public let iconColor: Color
    public let title: String
    public let caption: String?
    public let required: Bool
    public let trailing: () -> Trailing

    public init(
        icon: String,
        iconColor: Color,
        title: String,
        caption: String? = nil,
        required: Bool = false,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.caption = caption
        self.required = required
        self.trailing = trailing
    }

    public var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 22, height: 22)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            .accessibilityHidden(true)
            HStack(spacing: 4) {
                Text(title)
                    .font(Theme.Typography.label.weight(.semibold))
                    .foregroundStyle(Theme.Color.text)
                if required {
                    Text("*")
                        .font(Theme.Typography.label.weight(.bold))
                        .foregroundStyle(Theme.Color.danger)
                        .accessibilityLabel("필수 항목")
                }
            }
            if let caption {
                Text(caption)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            Spacer()
            trailing()
        }
    }
}

// MARK: - RadioCardButton

/// 라디오 선택용 큰 카드 버튼. 일반 라디오보다 hit target ↑ + 시각적 강조.
public struct RadioCardButton<Content: View>: View {
    public let isSelected: Bool
    public let accentColor: Color
    public let action: () -> Void
    public let content: () -> Content
    @State private var isHovering = false

    public init(
        isSelected: Bool,
        accentColor: Color = Theme.Color.accent,
        action: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isSelected = isSelected
        self.accentColor = accentColor
        self.action = action
        self.content = content
    }

    public var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                radioIndicator
                content()
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 10)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(borderColor, lineWidth: isSelected ? 1.5 : 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .scaleEffect(isHovering && !isSelected ? 1.005 : 1.0)
            .animation(.spring(response: 0.30, dampingFraction: 0.85), value: isSelected)
            .animation(.easeOut(duration: 0.10), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var radioIndicator: some View {
        ZStack {
            Circle()
                .stroke(isSelected ? accentColor : Theme.Color.textTertiary, lineWidth: 1.5)
                .frame(width: 16, height: 16)
            if isSelected {
                Circle()
                    .fill(accentColor)
                    .frame(width: 8, height: 8)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .accessibilityHidden(true)
    }

    private var background: Color {
        if isSelected {
            return accentColor.opacity(0.10)
        } else if isHovering {
            return Theme.Color.surfaceHi
        } else {
            return Color.clear
        }
    }

    private var borderColor: Color {
        if isSelected {
            return accentColor.opacity(0.50)
        } else if isHovering {
            return Theme.Color.borderStrong.opacity(0.5)
        } else {
            return Theme.Color.borderSubtle
        }
    }
}

// MARK: - AnimatedEmptyState

/// 빈 상태 placeholder — 큰 SF Symbol + spring fade-in + (옵션) CTA 버튼.
public struct AnimatedEmptyState<Action: View>: View {
    public let icon: String
    public let iconTint: Color
    public let title: String
    public let message: String
    public let action: () -> Action
    @State private var appeared = false

    public init(
        icon: String,
        iconTint: Color = Theme.Color.textTertiary,
        title: String,
        message: String,
        @ViewBuilder action: @escaping () -> Action = { EmptyView() }
    ) {
        self.icon = icon
        self.iconTint = iconTint
        self.title = title
        self.message = message
        self.action = action
    }

    public var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(iconTint.opacity(0.10))
                    .frame(width: 56, height: 56)
                    .scaleEffect(appeared ? 1.0 : 0.7)
                    .opacity(appeared ? 1.0 : 0.0)
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(iconTint)
                    .symbolEffect(.bounce, value: appeared)
            }
            .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text(title)
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.Color.text)
                Text(message)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(appeared ? 1.0 : 0.0)
            .offset(y: appeared ? 0 : 6)
            action()
                .opacity(appeared ? 1.0 : 0.0)
                .offset(y: appeared ? 0 : 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.xl)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.05)) {
                appeared = true
            }
        }
    }
}

// MARK: - IconHero

/// Sheet/dialog 헤더의 큰 아이콘 (color halo + symbol effect).
public struct IconHero: View {
    public let icon: String
    public let tint: Color
    public let size: CGFloat

    public init(icon: String, tint: Color = Theme.Color.accent, size: CGFloat = 44) {
        self.icon = icon
        self.tint = tint
        self.size = size
    }

    public var body: some View {
        ZStack {
            // Halo gradient
            Circle()
                .fill(
                    RadialGradient(
                        colors: [tint.opacity(0.25), tint.opacity(0.0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.7
                    )
                )
                .frame(width: size * 1.6, height: size * 1.6)
            // Icon container
            Circle()
                .fill(tint.opacity(0.15))
                .frame(width: size, height: size)
            Image(systemName: icon)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - HeaderHero

/// Sheet 상단의 큰 헤더 — IconHero + 큰 title + subtitle.
public struct HeaderHero: View {
    public let icon: String
    public let iconTint: Color
    public let title: String
    public let subtitle: String

    public init(icon: String, iconTint: Color = Theme.Color.accent, title: String, subtitle: String) {
        self.icon = icon
        self.iconTint = iconTint
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            IconHero(icon: icon, tint: iconTint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .default))
                    .foregroundStyle(Theme.Color.text)
                Text(subtitle)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }
}

// MARK: - InfoCallout

/// 안내문 callout — 정보/경고/성공 톤. Sheet 안 비교 안내 등에 사용.
public struct InfoCallout<Content: View>: View {
    public enum Tone {
        case info, warning, success, danger

        var color: Color {
            switch self {
            case .info: return Theme.Color.accent
            case .warning: return .orange
            case .success: return Theme.Color.success
            case .danger: return Theme.Color.danger
            }
        }

        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .success: return "checkmark.circle.fill"
            case .danger: return "xmark.octagon.fill"
            }
        }
    }

    public let tone: Tone
    public let content: () -> Content

    public init(tone: Tone = .info, @ViewBuilder content: @escaping () -> Content) {
        self.tone = tone
        self.content = content
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tone.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tone.color)
                .padding(.top, 1)
                .accessibilityHidden(true)
            content()
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.color.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(tone.color.opacity(0.20), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }
}
