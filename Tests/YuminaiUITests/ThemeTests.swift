import Foundation
import Testing
@testable import YuminaiUI

@Suite("LayoutMode breakpoints")
struct LayoutModeTests {
    @Test("breakpoint 경계에서 정확히 분기한다 (ADR-070: tiny 추가)")
    func boundaries() {
        // tiny: < 600 (ADR-070 — 보조 모니터 / split-view 대응)
        #expect(Theme.Layout.mode(for: 0) == .tiny)
        #expect(Theme.Layout.mode(for: 599) == .tiny)
        // compact: 600 ~ 759
        #expect(Theme.Layout.mode(for: 600) == .compact)
        #expect(Theme.Layout.mode(for: 759) == .compact)
        // medium: 760 ~ 1079
        #expect(Theme.Layout.mode(for: 760) == .medium)
        #expect(Theme.Layout.mode(for: 1079) == .medium)
        // regular: 1080 ~ 1439
        #expect(Theme.Layout.mode(for: 1080) == .regular)
        #expect(Theme.Layout.mode(for: 1439) == .regular)
        // wide: ≥ 1440
        #expect(Theme.Layout.mode(for: 1440) == .wide)
        #expect(Theme.Layout.mode(for: 9999) == .wide)
    }

    @Test("tiny/compact/medium은 inspector를 허용하지 않는다")
    func inspectorAllowance() {
        #expect(LayoutMode.tiny.allowsInspector == false)
        #expect(LayoutMode.compact.allowsInspector == false)
        #expect(LayoutMode.medium.allowsInspector == false)
        #expect(LayoutMode.regular.allowsInspector == true)
        #expect(LayoutMode.wide.allowsInspector == true)
    }

    @Test("tiny + compact 모드에서만 sidebar가 overlay")
    func sidebarOverlayMode() {
        #expect(LayoutMode.tiny.sidebarIsOverlay == true)
        #expect(LayoutMode.compact.sidebarIsOverlay == true)
        #expect(LayoutMode.medium.sidebarIsOverlay == false)
        #expect(LayoutMode.regular.sidebarIsOverlay == false)
        #expect(LayoutMode.wide.sidebarIsOverlay == false)
    }

    @Test("tiny 모드에서만 비필수 toolbar 버튼 숨김 (ADR-070)")
    func nonEssentialToolbarHidingInTiny() {
        #expect(LayoutMode.tiny.hidesNonEssentialToolbarItems == true)
        #expect(LayoutMode.compact.hidesNonEssentialToolbarItems == false)
        #expect(LayoutMode.medium.hidesNonEssentialToolbarItems == false)
        #expect(LayoutMode.regular.hidesNonEssentialToolbarItems == false)
        #expect(LayoutMode.wide.hidesNonEssentialToolbarItems == false)
    }

    /// **ADR-080** — sidebarIsOverlay vs allowsInspector 모드 매트릭스 검증.
    /// 신규 ADR 추가 시 모드 분기가 깨지지 않게 회귀 방지.
    @Test("LayoutMode 매트릭스 — sidebar overlay × inspector 허용")
    func layoutMatrix() {
        let allModes: [LayoutMode] = [.tiny, .compact, .medium, .regular, .wide]
        for mode in allModes {
            // sidebarIsOverlay = (tiny || compact)만 true
            let expectOverlay = (mode == .tiny || mode == .compact)
            #expect(mode.sidebarIsOverlay == expectOverlay, "\(mode).sidebarIsOverlay 예상: \(expectOverlay)")

            // allowsInspector = (regular || wide)만 true
            let expectInspector = (mode == .regular || mode == .wide)
            #expect(mode.allowsInspector == expectInspector, "\(mode).allowsInspector 예상: \(expectInspector)")
        }
    }

    /// **ADR-080** — Theme.Layout 반응형 padding 함수 검증 (ADR-072 확장).
    @Test("contentPaddingH 반응형 — 작은 화면 padding 작음")
    func contentPaddingResponsive() {
        let tinyPadding = Theme.Layout.contentPaddingH(for: .tiny)
        let compactPadding = Theme.Layout.contentPaddingH(for: .compact)
        let mediumPadding = Theme.Layout.contentPaddingH(for: .medium)
        let regularPadding = Theme.Layout.contentPaddingH(for: .regular)
        let widePadding = Theme.Layout.contentPaddingH(for: .wide)

        // 단조 증가 (작은 화면일수록 padding 작음)
        #expect(tinyPadding < compactPadding)
        #expect(compactPadding < mediumPadding)
        #expect(mediumPadding < regularPadding)
        #expect(regularPadding == widePadding)  // regular/wide는 같음

        // 절대값 sanity check
        #expect(tinyPadding >= 4)
        #expect(widePadding <= 48)
    }

    @Test("composerOuterPadding 반응형 — 단조 증가")
    func composerOuterPaddingResponsive() {
        let tiny = Theme.Layout.composerOuterPadding(for: .tiny)
        let regular = Theme.Layout.composerOuterPadding(for: .regular)
        #expect(tiny < regular)
        #expect(tiny >= 4)
    }

    @Test("composerPadding 반응형")
    func composerPaddingResponsive() {
        let tiny = Theme.Layout.composerPadding(for: .tiny)
        let regular = Theme.Layout.composerPadding(for: .regular)
        #expect(tiny <= regular)
    }
}

@Suite("Settings sheet sizing (ADR-070)")
struct SettingsSheetTests {
    @Test("보조 모니터 (960×640)에서도 표시 가능한 minimum 크기")
    func subMonitorCompatibility() {
        // 960px 보조 모니터에서 settings (460px min) + window (460px min)으로 분할 가능
        #expect(Theme.Layout.settingsMinWidth <= 480)
        // 640px 높이 모니터에서 dock + menubar 빼고 표시 가능
        #expect(Theme.Layout.settingsMinHeight <= 400)
    }

    @Test("ideal은 min보다 크고 합리적 범위")
    func idealLargerThanMin() {
        #expect(Theme.Layout.settingsIdealWidth > Theme.Layout.settingsMinWidth)
        #expect(Theme.Layout.settingsIdealHeight > Theme.Layout.settingsMinHeight)
        // 일반 1280×800 노트북에서도 ideal이 화면을 넘지 않음
        #expect(Theme.Layout.settingsIdealWidth <= 800)
        #expect(Theme.Layout.settingsIdealHeight <= 700)
    }
}

@Suite("ToolbarHoverInfo (ADR-070 Phase 5)")
struct ToolbarHoverInfoTests {
    @Test("기본 init은 title + body 필수, shortcut은 옵션")
    func basicInit() {
        let info = ToolbarHoverInfo(title: "테스트", body: "본문 내용")
        #expect(info.title == "테스트")
        #expect(info.body == "본문 내용")
        #expect(info.shortcut == nil)
    }

    @Test("shortcut 지정 가능")
    func withShortcut() {
        let info = ToolbarHoverInfo(title: "단축키 있음", body: "본문", shortcut: "⌘D")
        #expect(info.shortcut == "⌘D")
    }

    @Test("Equatable 동작")
    func equality() {
        let a = ToolbarHoverInfo(title: "T", body: "B", shortcut: "⌘A")
        let b = ToolbarHoverInfo(title: "T", body: "B", shortcut: "⌘A")
        let c = ToolbarHoverInfo(title: "T", body: "B", shortcut: "⌘B")
        #expect(a == b)
        #expect(a != c)
    }
}

@Suite("Theme tokens")
struct ThemeTests {
    @Test("Spacing 토큰은 단조 증가한다")
    func spacingIsMonotonic() {
        #expect(Theme.Spacing.xs < Theme.Spacing.sm)
        #expect(Theme.Spacing.sm < Theme.Spacing.md)
        #expect(Theme.Spacing.md < Theme.Spacing.lg)
        #expect(Theme.Spacing.lg < Theme.Spacing.xl)
        #expect(Theme.Spacing.xl < Theme.Spacing.xxl)
    }

    @Test("Radius 토큰은 단조 증가한다 (none → pill)")
    func radiusIsMonotonic() {
        #expect(Theme.Radius.none < Theme.Radius.sm)
        #expect(Theme.Radius.sm < Theme.Radius.md)
        #expect(Theme.Radius.md < Theme.Radius.lg)
        #expect(Theme.Radius.lg < Theme.Radius.xl)
        #expect(Theme.Radius.xl < Theme.Radius.pill)
    }
}
