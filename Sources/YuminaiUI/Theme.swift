import SwiftUI
import AppKit

/// Yuminai 디자인 토큰 v3.
///
/// 명세: `docs/design/60_UI_DESIGN_SPEC.md` (codex review 반영본).
/// 핵심 변화:
/// - Sans-serif 본문 + Mono는 code/stats 한정 (P1)
/// - Warm 톤 다크 (R > B by 3-4) — 사이드바 vs 본문 미세 분리 (codex #4)
/// - textTertiary 대비 ↑ (#807a76 on #1a1817 = 3.4:1, 11px+ 한정) (codex #5)
/// - 박스 단색 차로 구분, border는 focus/active 한정 (P2)
public enum Theme {

    // MARK: - Color

    public enum Color {
        // Surfaces — warm 다크, 4단 hierarchy
        public static let bgSidebar = hex(dark: 0x161514, light: 0xeeebe6)
        public static let bg = hex(dark: 0x1a1817, light: 0xf6f3ee)
        public static let surface = hex(dark: 0x211f1d, light: 0xfffefb)
        public static let surfaceHi = hex(dark: 0x2a2724, light: 0xe8e4dd)
        public static let elevated = hex(dark: 0x322e2a, light: 0xddd7cf)
        public static let inlineCode = hex(dark: 0x2a2724, light: 0xe8e4dd)

        // Borders — 거의 사용 안 함, focus/active 신호용
        public static let borderSubtle = hex(dark: 0x2c2926, light: 0xddd7cf)
        public static let border = hex(dark: 0x3d3834, light: 0xc8c1b9)
        public static let borderStrong = hex(dark: 0x504a44, light: 0xa8a098)
        public static let focusRing = hex(dark: 0xcc785c, light: 0xcc785c)

        // Text — 대비 ↑ (codex #5)
        public static let text = hex(dark: 0xf0eeec, light: 0x1a1817)
        public static let textSecondary = hex(dark: 0xa8a3a0, light: 0x5a5552)
        public static let textTertiary = hex(dark: 0x807a76, light: 0x7a7470)
        public static let textDisabled = hex(dark: 0x5a5552, light: 0x9a948f)

        // Accent — Claude orange
        public static let accent = SwiftUI.Color(red: 0.80, green: 0.47, blue: 0.36)        // #cc785c
        public static let accentHover = SwiftUI.Color(red: 0.84, green: 0.54, blue: 0.44)   // #d68a70
        public static let accentMuted = hex(dark: 0x2a2018, light: 0xfde8d8)
        public static let accentBorder = SwiftUI.Color(red: 0.80, green: 0.47, blue: 0.36).opacity(0.40)

        // Status — 절제
        public static let success = SwiftUI.Color(red: 0.56, green: 0.79, blue: 0.60)       // #8fc999
        public static let warning = SwiftUI.Color(red: 0.83, green: 0.72, blue: 0.42)
        public static let danger = SwiftUI.Color(red: 0.85, green: 0.45, blue: 0.45)        // #d97373
        public static let liveDot = SwiftUI.Color(red: 0.91, green: 0.36, blue: 0.29)       // #e85d4a

        // Diff
        public static let diffPlus = success
        public static let diffMinus = danger

        // Message role
        public static let userBg = accentMuted
        public static let userText = text
        public static let userAccent = accent
        public static let assistantText = text
        public static let toolText = textSecondary

        // Helper: dark/light hex
        private static func hex(dark: UInt32, light: UInt32) -> SwiftUI.Color {
            SwiftUI.Color(
                light: SwiftUI.Color(rgb: light),
                dark: SwiftUI.Color(rgb: dark)
            )
        }
    }

    // MARK: - Typography

    public enum Typography {
        // Sans (본문)
        public static let display = Font.system(size: 22, weight: .semibold, design: .default)
        public static let title = Font.system(size: 17, weight: .semibold, design: .default)
        public static let body = Font.system(size: 14, weight: .regular, design: .default)
        public static let bodyEmphasis = Font.system(size: 14, weight: .medium, design: .default)
        public static let label = Font.system(size: 13, weight: .medium, design: .default)
        public static let small = Font.system(size: 12, weight: .regular, design: .default)
        public static let micro = Font.system(size: 11, weight: .medium, design: .default)

        // Mono (code, stats, breadcrumb path)
        public static let mono = Font.system(size: 13, weight: .regular, design: .monospaced)
        public static let monoSmall = Font.system(size: 12, weight: .medium, design: .monospaced)
        public static let monoStat = Font.system(size: 18, weight: .semibold, design: .monospaced)

        // Code block
        public static let codeBlock = Font.system(size: 12, weight: .regular, design: .monospaced)
    }

    // MARK: - Spacing — 4의 배수, 여유롭게

    public enum Spacing {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
        public static let xxxl: CGFloat = 48
    }

    // MARK: - Radius — 둥근 톤

    public enum Radius {
        public static let none: CGFloat = 0
        public static let sm: CGFloat = 4
        public static let md: CGFloat = 6
        public static let lg: CGFloat = 8
        public static let xl: CGFloat = 12
        public static let pill: CGFloat = 999
    }

    public enum Stroke {
        public static let hairline: CGFloat = 1
        public static let bar: CGFloat = 2  // selected sidebar item 좌측 bar
    }

    // MARK: - Layout

    public enum Layout {
        public static let sidebarWidth: CGFloat = 280
        public static let sidebarMinWidth: CGFloat = 220
        public static let sidebarMaxWidth: CGFloat = 360
        public static let sidebarPadding: CGFloat = 12
        public static let sidebarItemPadH: CGFloat = 10
        public static let sidebarItemPadV: CGFloat = 7
        public static let sidebarItemHeight: CGFloat = 32
        public static let sidebarIconSize: CGFloat = 14
        public static let sidebarDotSize: CGFloat = 7
        public static let sidebarGroupHeaderTop: CGFloat = 20

        public static let toolbarHeight: CGFloat = 44
        public static let statusBarHeight: CGFloat = 28

        public static let inspectorWidth: CGFloat = 300
        public static let inspectorMinWidth: CGFloat = 240
        public static let inspectorMaxWidth: CGFloat = 420

        public static let contentMaxWidth: CGFloat = 820
        public static let contentPaddingH: CGFloat = 32
        public static let contentPaddingV: CGFloat = 24

        public static let composerMinHeight: CGFloat = 104
        public static let composerMaxHeight: CGFloat = 320
        public static let composerPadding: CGFloat = 16
        public static let composerOuterPadding: CGFloat = 20

        public static let sheetWidth: CGFloat = 580
    }

    // MARK: - Animation

    public enum Animation {
        public static let stateChange: SwiftUI.Animation = .easeOut(duration: 0.12)
        public static let panelToggle: SwiftUI.Animation = .easeInOut(duration: 0.18)
        public static let pulseDuration: Double = 1.5
    }
}

// MARK: - Color helpers

public extension Color {
    /// 다크/라이트 자동 전환.
    init(light: Color, dark: Color) {
        self.init(NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.aqua, .darkAqua]) {
            case .darkAqua: return NSColor(dark)
            default: return NSColor(light)
            }
        })
    }

    /// 0xRRGGBB UInt32 → Color.
    init(rgb: UInt32) {
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}

// MARK: - Modifiers

/// 메시지 영역의 풀 너비 안에서 contentMaxWidth로 가운데 정렬.
public struct CenteredContent: ViewModifier {
    public init() {}
    public func body(content: Content) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            content
                .frame(maxWidth: Theme.Layout.contentMaxWidth, alignment: .leading)
            Spacer(minLength: 0)
        }
    }
}

public extension View {
    func centeredContent() -> some View {
        modifier(CenteredContent())
    }
}

/// Selected sidebar item 좌측 2px accent vertical bar (non-color marker).
public struct SelectedBar: ViewModifier {
    public let isVisible: Bool
    public init(_ isVisible: Bool) { self.isVisible = isVisible }

    public func body(content: Content) -> some View {
        content.overlay(alignment: .leading) {
            if isVisible {
                Rectangle()
                    .fill(Theme.Color.accent)
                    .frame(width: Theme.Stroke.bar)
            }
        }
    }
}

public extension View {
    func selectedBar(_ isVisible: Bool) -> some View {
        modifier(SelectedBar(isVisible))
    }
}
