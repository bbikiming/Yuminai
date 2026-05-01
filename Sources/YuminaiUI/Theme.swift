import SwiftUI
import AppKit

/// Yuminai 디자인 토큰 v3 + Brand layer.
///
/// 명세: `docs/design/60_UI_DESIGN_SPEC.md` + `70_BRANDING_AND_INTERACTION.md`.
/// 변화:
/// - `Theme.Brand` 신규: 자전거 팀 ar2r 컬러 (codex 조사 결과 비공개 → fallback navy + orange-red 사용)
/// - `Theme.Color.accent` 등은 Brand로 위임 → ar2r 정확한 hex 받으면 Brand만 교체하면 전체 반영
public enum Theme {

    // MARK: - Brand (AG2R La Mondiale 자전거 팀 시그니처 시안)

    /// 사용자 확인: 강조색 = 밝은 하늘색 (AG2R 시그니처 시안 톤)
    /// AG2R 저지의 시그니처 cyan을 디지털 다크 모드용으로 보정.
    public enum Brand {
        /// chrome accent (지금은 잘 안 쓰임 — 차후 about/splash 화면용)
        public static let primary = SwiftUI.Color(rgb: 0x0E2A47)
        public static let primaryDark = SwiftUI.Color(rgb: 0x0A1F36)
        public static let primaryLight = SwiftUI.Color(rgb: 0x1A3F5E)

        /// Bright Cyan/Sky — CTA, active state, link, streaming, selected
        public static let accent = SwiftUI.Color(rgb: 0x22C8E0)
        public static let accentDeep = SwiftUI.Color(rgb: 0x0FA8C0)
        public static let accentMuted = SwiftUI.Color.adaptive(light: SwiftUI.Color(rgb: 0xD4F2F8), dark: SwiftUI.Color(rgb: 0x0A2128))
        public static let accentBorder = SwiftUI.Color(rgb: 0x22C8E0).opacity(0.45)

        /// White — 본문/대비
        public static let contrast = SwiftUI.Color.white
    }

    // MARK: - Color

    public enum Color {
        // Surfaces — warm 다크, 4단 hierarchy
        public static let bgSidebar = hex(dark: 0x161514, light: 0xeeebe6)
        public static let bg = hex(dark: 0x1a1817, light: 0xf6f3ee)
        public static let surface = hex(dark: 0x211f1d, light: 0xfffefb)
        public static let surfaceHi = hex(dark: 0x2a2724, light: 0xe8e4dd)
        public static let elevated = hex(dark: 0x322e2a, light: 0xddd7cf)
        public static let inlineCode = hex(dark: 0x2a2724, light: 0xe8e4dd)

        // Borders — focus/active 한정
        public static let borderSubtle = hex(dark: 0x2c2926, light: 0xddd7cf)
        public static let border = hex(dark: 0x3d3834, light: 0xc8c1b9)
        public static let borderStrong = hex(dark: 0x504a44, light: 0xa8a098)
        public static let focusRing = Brand.accent

        // Text — 대비 ↑
        public static let text = hex(dark: 0xf0eeec, light: 0x1a1817)
        public static let textSecondary = hex(dark: 0xa8a3a0, light: 0x5a5552)
        public static let textTertiary = hex(dark: 0x807a76, light: 0x7a7470)
        public static let textDisabled = hex(dark: 0x5a5552, light: 0x9a948f)

        // Accent — Brand로 위임
        public static let accent = Brand.accent
        public static let accentHover = Brand.accentDeep
        public static let accentMuted = Brand.accentMuted
        public static let accentBorder = Brand.accentBorder

        // Status
        public static let success = SwiftUI.Color(rgb: 0x8fc999)
        public static let warning = SwiftUI.Color(rgb: 0xd4b86a)
        public static let danger = SwiftUI.Color(rgb: 0xd97373)
        public static let liveDot = Brand.accent  // streaming = brand accent (통합)

        // Diff
        public static let diffPlus = success
        public static let diffMinus = danger

        // Message role
        public static let userBg = Brand.accentMuted
        public static let userText = text
        public static let userAccent = Brand.accent
        public static let assistantText = text
        public static let toolText = textSecondary

        // Helper: dark/light hex
        private static func hex(dark: UInt32, light: UInt32) -> SwiftUI.Color {
            SwiftUI.Color.adaptive(
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

        // MARK: - Responsive breakpoints

        /// 최소 윈도우 너비 — 그 이하로는 macOS가 리사이즈 거부.
        public static let minWindowWidth: CGFloat = 600
        public static let minWindowHeight: CGFloat = 480

        /// chat 본문 최소 너비 (sidebar/inspector 들어와도 chat이 이 이하면 layout 적응).
        public static let minChatWidth: CGFloat = 520

        /// 모드 분기점.
        public static let breakpointCompact: CGFloat = 760     // 미만 = compact
        public static let breakpointMedium: CGFloat = 1080     // 미만 = medium (inspector 강제 숨김)
        public static let breakpointWide: CGFloat = 1440       // 미만 = regular, 이상 = wide

        /// `width`에 해당하는 layout mode.
        public static func mode(for width: CGFloat) -> LayoutMode {
            if width < breakpointCompact { return .compact }
            if width < breakpointMedium { return .medium }
            if width < breakpointWide { return .regular }
            return .wide
        }
    }

    // MARK: - Animation

    public enum Animation {
        public static let stateChange: SwiftUI.Animation = .easeOut(duration: 0.12)
        public static let panelToggle: SwiftUI.Animation = .easeInOut(duration: 0.18)
        public static let pulseDuration: Double = 1.5
    }
}

/// 반응형 layout 모드 — 윈도우 너비에 따라 결정.
public enum LayoutMode: Sendable, Equatable {
    case compact   // < 760: sidebar overlay only, inspector 강제 hidden
    case medium    // 760~1080: sidebar inline, inspector 강제 hidden
    case regular   // 1080~1440: sidebar inline, inspector 옵션
    case wide      // ≥ 1440: 모두 inline 가능

    /// inspector를 사용자가 켤 수 있는 모드인지.
    public var allowsInspector: Bool {
        switch self {
        case .compact, .medium: return false
        case .regular, .wide: return true
        }
    }

    /// sidebar가 inline이 아니라 overlay 모드인지.
    public var sidebarIsOverlay: Bool {
        self == .compact
    }
}

// MARK: - Color helpers

public extension Color {
    /// 다크/라이트 자동 전환. (우리 namespace — MarkdownUI의 동명 init과 충돌 회피)
    static func adaptive(light: Color, dark: Color) -> Color {
        Color(NSColor(name: nil) { appearance in
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
