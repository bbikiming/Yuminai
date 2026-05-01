import Foundation
import Testing
@testable import YuminaiUI

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
