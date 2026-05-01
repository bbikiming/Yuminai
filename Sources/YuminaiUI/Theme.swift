import SwiftUI

/// Yuminai 디자인 토큰. 직접 `.font(.system(size: 13))` 같은 호출 대신 항상 이 토큰을 거친다.
public enum Theme {
    public enum Color {
        public static let label = SwiftUI.Color.primary
        public static let labelSecondary = SwiftUI.Color.secondary
        public static let labelTertiary = SwiftUI.Color.secondary.opacity(0.7)

        // Claude 오렌지 톤 — Claude Code CLI와 정합
        public static let accent = SwiftUI.Color(red: 0.85, green: 0.55, blue: 0.30)
        public static let accentMuted = SwiftUI.Color(red: 0.85, green: 0.55, blue: 0.30).opacity(0.18)

        public static let success = SwiftUI.Color(red: 0.30, green: 0.80, blue: 0.50)
        public static let warning = SwiftUI.Color(red: 0.95, green: 0.75, blue: 0.20)
        public static let error = SwiftUI.Color(red: 0.95, green: 0.30, blue: 0.30)

        // Chrome / surfaces
        public static let chromeBackground = SwiftUI.Color(NSColor.windowBackgroundColor)
        public static let surface = SwiftUI.Color(NSColor.controlBackgroundColor)
        public static let surfaceMuted = SwiftUI.Color(NSColor.underPageBackgroundColor)
        public static let codeBlockBackground = SwiftUI.Color(NSColor.textBackgroundColor)
        public static let dividerSubtle = SwiftUI.Color.gray.opacity(0.18)

        // Role tints
        public static let userTint = accentMuted
        public static let assistantTint = SwiftUI.Color.gray.opacity(0.10)
        public static let toolTint = SwiftUI.Color.blue.opacity(0.10)
        public static let systemTint = SwiftUI.Color.purple.opacity(0.10)
    }

    public enum Typography {
        public static let body = Font.system(.body, design: .default)
        public static let bodyMono = Font.system(.body, design: .monospaced)
        public static let chatMessage = Font.system(size: 13, design: .monospaced)
        public static let chatInput = Font.system(size: 13, design: .monospaced)
        public static let codeBlock = Font.system(size: 12, design: .monospaced)
        public static let label = Font.system(.callout, design: .default)
        public static let labelSmall = Font.system(.caption, design: .default)
        public static let toolbarLabel = Font.system(.caption, design: .monospaced).weight(.medium)
        public static let statBig = Font.system(.title3, design: .monospaced).weight(.semibold)
        public static let statLabel = Font.system(.caption2, design: .default).weight(.medium)
    }

    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
    }

    public enum Radius {
        public static let xs: CGFloat = 3
        public static let sm: CGFloat = 5
        public static let md: CGFloat = 8
        public static let lg: CGFloat = 12
        public static let pill: CGFloat = 999
    }
}

/// chrome (toolbar/status bar/inspector) 영역에 일관된 배경을 적용.
public struct ChromeBackground: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: Rectangle())
    }
}

public extension View {
    func chromeBackground() -> some View {
        modifier(ChromeBackground())
    }
}

