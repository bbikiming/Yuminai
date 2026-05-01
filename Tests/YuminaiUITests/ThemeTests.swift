import Foundation
import Testing
@testable import YuminaiUI

@Suite("LayoutMode breakpoints")
struct LayoutModeTests {
    @Test("breakpoint 경계에서 정확히 분기한다")
    func boundaries() {
        // compact: < 760
        #expect(Theme.Layout.mode(for: 0) == .compact)
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

    @Test("compact + medium은 inspector를 허용하지 않는다")
    func inspectorAllowance() {
        #expect(LayoutMode.compact.allowsInspector == false)
        #expect(LayoutMode.medium.allowsInspector == false)
        #expect(LayoutMode.regular.allowsInspector == true)
        #expect(LayoutMode.wide.allowsInspector == true)
    }

    @Test("compact 모드에서만 sidebar가 overlay")
    func sidebarOverlayMode() {
        #expect(LayoutMode.compact.sidebarIsOverlay == true)
        #expect(LayoutMode.medium.sidebarIsOverlay == false)
        #expect(LayoutMode.regular.sidebarIsOverlay == false)
        #expect(LayoutMode.wide.sidebarIsOverlay == false)
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
