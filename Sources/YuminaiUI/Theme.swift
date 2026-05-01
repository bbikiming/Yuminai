import SwiftUI
import AppKit

/// Yuminai 디자인 토큰 — Claude Code CLI 룩을 SwiftUI로 이식한 플랫 시스템.
///
/// macOS 네이티브 룩(material/glass/시스템 색)을 의도적으로 우회하고 명시적 hex 색을 사용한다.
/// 모든 텍스트는 monospaced를 기본으로 한다.
public enum Theme {
    public enum Color {
        // Surfaces (light → dark 어두움)
        public static let bg = adaptive(light: 0.98, dark: 0.07)
        public static let bgChrome = adaptive(light: 0.96, dark: 0.10)
        public static let bgPanel = adaptive(light: 1.00, dark: 0.13)
        public static let bgInput = adaptive(light: 1.00, dark: 0.05)
        public static let bgHover = adaptive(light: 0.94, dark: 0.16)
        public static let bgSelected = adaptive(light: 0.90, dark: 0.20)

        // Borders
        public static let border = adaptive(light: 0.86, dark: 0.20)
        public static let borderSubtle = adaptive(light: 0.92, dark: 0.16)
        public static let borderStrong = adaptive(light: 0.70, dark: 0.32)

        // Text
        public static let text = adaptive(light: 0.10, dark: 0.92)
        public static let textSecondary = adaptive(light: 0.40, dark: 0.62)
        public static let textTertiary = adaptive(light: 0.55, dark: 0.40)

        // Claude orange (#d97757 톤)
        public static let accent = SwiftUI.Color(red: 0.85, green: 0.46, blue: 0.34)
        public static let accentMuted = SwiftUI.Color(
            light: SwiftUI.Color(red: 0.97, green: 0.91, blue: 0.86),
            dark: SwiftUI.Color(red: 0.23, green: 0.15, blue: 0.13)
        )
        public static let accentBorder = SwiftUI.Color(red: 0.85, green: 0.46, blue: 0.34).opacity(0.45)

        // Status (낮은 채도)
        public static let success = SwiftUI.Color(red: 0.49, green: 0.72, blue: 0.56)
        public static let warning = SwiftUI.Color(red: 0.83, green: 0.72, blue: 0.42)
        public static let error = SwiftUI.Color(red: 0.85, green: 0.45, blue: 0.45)

        // Role tints — 메시지 prefix 색
        public static let rolePrefixUser = accent
        public static let rolePrefixAssistant = adaptive(light: 0.10, dark: 0.92)
        public static let rolePrefixTool = success
        public static let rolePrefixSystem = textTertiary

        // Helper: dark/light 자동 전환
        private static func adaptive(light: Double, dark: Double) -> SwiftUI.Color {
            SwiftUI.Color(
                light: SwiftUI.Color(white: light),
                dark: SwiftUI.Color(white: dark)
            )
        }
    }

    /// 모든 폰트 monospace 기본. 라벨/통계는 더 작은 사이즈.
    public enum Typography {
        public static let body = Font.system(size: 13, design: .monospaced)
        public static let bodyEmphasis = Font.system(size: 13, design: .monospaced).weight(.medium)
        public static let small = Font.system(size: 11, design: .monospaced)
        public static let micro = Font.system(size: 10, design: .monospaced)
        public static let label = Font.system(size: 11, design: .monospaced).weight(.medium)
        public static let title = Font.system(size: 15, design: .monospaced).weight(.semibold)
        public static let codeBlock = Font.system(size: 12, design: .monospaced)
        public static let statBig = Font.system(size: 18, design: .monospaced).weight(.semibold)
    }

    /// 정수 단위 — Claude Code 스타일은 빡빡한 정보 밀도.
    public enum Spacing {
        public static let xs: CGFloat = 2
        public static let sm: CGFloat = 4
        public static let md: CGFloat = 8
        public static let lg: CGFloat = 12
        public static let xl: CGFloat = 16
        public static let xxl: CGFloat = 24
    }

    /// 거의 직각. 액센트만 살짝 둥글게.
    public enum Radius {
        public static let none: CGFloat = 0
        public static let xs: CGFloat = 2
        public static let sm: CGFloat = 3
        public static let md: CGFloat = 4
        public static let pill: CGFloat = 999
    }

    public enum Stroke {
        public static let hairline: CGFloat = 1
    }

    public enum Layout {
        public static let sidebarWidth: CGFloat = 220
        public static let inspectorWidth: CGFloat = 280
        public static let toolbarHeight: CGFloat = 36
        public static let statusBarHeight: CGFloat = 28
        public static let messageMaxWidth: CGFloat = 920
    }
}

// MARK: - Color helpers

public extension Color {
    /// 다크/라이트 자동 전환 색.
    init(light: Color, dark: Color) {
        self.init(NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.aqua, .darkAqua]) {
            case .darkAqua: return NSColor(dark)
            default: return NSColor(light)
            }
        })
    }
}

// MARK: - Modifiers

/// chrome (toolbar/status bar/inspector) 영역의 단색 배경 + 옵션 border.
public struct FlatChrome: ViewModifier {
    public enum Edge { case top, bottom, leading, trailing }
    public let borderEdges: [Edge]

    public init(borderEdges: [Edge] = []) {
        self.borderEdges = borderEdges
    }

    public func body(content: Content) -> some View {
        content
            .background(Theme.Color.bgChrome)
            .overlay(alignment: .top) {
                if borderEdges.contains(.top) { divider }
            }
            .overlay(alignment: .bottom) {
                if borderEdges.contains(.bottom) { divider }
            }
            .overlay(alignment: .leading) {
                if borderEdges.contains(.leading) { vDivider }
            }
            .overlay(alignment: .trailing) {
                if borderEdges.contains(.trailing) { vDivider }
            }
    }

    private var divider: some View {
        Rectangle().fill(Theme.Color.border).frame(height: Theme.Stroke.hairline)
    }
    private var vDivider: some View {
        Rectangle().fill(Theme.Color.border).frame(width: Theme.Stroke.hairline)
    }
}

public extension View {
    func flatChrome(borders: [FlatChrome.Edge] = []) -> some View {
        modifier(FlatChrome(borderEdges: borders))
    }
}
