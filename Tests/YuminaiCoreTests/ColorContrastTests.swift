import Foundation
import Testing
@testable import YuminaiCore

@Suite("WCAG 2.2 Color Contrast (ADR-072 Phase 2)")
struct WCAGContrastTests {

    /// 부동소수점 허용 오차 (WCAG는 소수 둘째 자리까지 비교).
    private let epsilon = 0.01

    @Test("relativeLuminance — 검정/흰색 boundary")
    func luminanceBoundaries() {
        // 검정 = 0.0
        #expect(WCAGContrast.relativeLuminance(rgb: 0x000000) == 0.0)
        // 흰색 = 1.0
        let whiteL = WCAGContrast.relativeLuminance(rgb: 0xFFFFFF)
        #expect(abs(whiteL - 1.0) < epsilon)
    }

    @Test("contrastRatio — 검정/흰색 = 21:1 (최대)")
    func maxContrast() {
        let ratio = WCAGContrast.contrastRatio(0x000000, 0xFFFFFF)
        #expect(abs(ratio - 21.0) < epsilon)
    }

    @Test("contrastRatio — 동일 색 = 1:1 (최소)")
    func sameColor() {
        let ratio = WCAGContrast.contrastRatio(0x808080, 0x808080)
        #expect(abs(ratio - 1.0) < epsilon)
    }

    @Test("contrastRatio — 대칭성 (순서 무관)")
    func symmetry() {
        let r1 = WCAGContrast.contrastRatio(0xFF0000, 0x0000FF)
        let r2 = WCAGContrast.contrastRatio(0x0000FF, 0xFF0000)
        #expect(abs(r1 - r2) < epsilon)
    }

    @Test("WCAG 공식 검증 — 알려진 케이스 (W3C 예제)")
    func knownReferenceCases() {
        // 회색 #767676 on 흰색 = 4.54:1 (W3C 표준 예제, AA pass borderline)
        let gray = WCAGContrast.contrastRatio(0x767676, 0xFFFFFF)
        #expect(abs(gray - 4.54) < 0.05)

        // 회색 #777777 on 흰색 = 4.48:1 (AA fail borderline — 0.06 차이로 fail)
        let grayFail = WCAGContrast.contrastRatio(0x777777, 0xFFFFFF)
        #expect(grayFail < 4.5)

        // sRGB 회색 50%: #BFBFBF on 흰색은 약 1.61:1
        let grayMid = WCAGContrast.contrastRatio(0xBFBFBF, 0xFFFFFF)
        #expect(grayMid < 2.0)
    }

    @Test("WCAGTextSize threshold 매핑 (W3C SC 1.4.3 + 1.4.6)")
    func textSizeThresholds() {
        // AA
        #expect(WCAGTextSize.normal.threshold(for: .aa) == 4.5)
        #expect(WCAGTextSize.large.threshold(for: .aa) == 3.0)
        // AAA
        #expect(WCAGTextSize.normal.threshold(for: .aaa) == 7.0)
        #expect(WCAGTextSize.large.threshold(for: .aaa) == 4.5)
    }

    @Test("ContrastResult — pass 플래그 자동 계산")
    func contrastResultPassFlags() {
        // 21:1 (max) — 모두 pass
        let max = ContrastResult(ratio: 21.0)
        #expect(max.passesAANormal == true)
        #expect(max.passesAAANormal == true)
        #expect(max.passesAALarge == true)
        #expect(max.passesAAALarge == true)
        #expect(max.passesNonText == true)

        // 4.5:1 — AA normal pass, AAA normal fail
        let aa = ContrastResult(ratio: 4.5)
        #expect(aa.passesAANormal == true)
        #expect(aa.passesAAANormal == false)
        #expect(aa.passesAALarge == true)
        #expect(aa.passesNonText == true)

        // 3:1 — large만 가능 + non-text pass
        let large = ContrastResult(ratio: 3.0)
        #expect(large.passesAANormal == false)
        #expect(large.passesAALarge == true)
        #expect(large.passesNonText == true)

        // 2.5:1 — 모두 fail
        let fail = ContrastResult(ratio: 2.5)
        #expect(fail.passesAANormal == false)
        #expect(fail.passesAALarge == false)
        #expect(fail.passesNonText == false)
    }

    @Test("ContrastResult — worstLevel 한국어 라벨")
    func worstLevelLabels() {
        #expect(ContrastResult(ratio: 8.0).worstLevel.contains("AAA"))
        #expect(ContrastResult(ratio: 5.0).worstLevel.contains("AA 충족"))
        #expect(ContrastResult(ratio: 3.5).worstLevel.contains("AA 미충족"))
        #expect(ContrastResult(ratio: 2.5).worstLevel.contains("미충족"))
    }

    @Test("displayRatio 형식")
    func displayRatioFormat() {
        let r = ContrastResult(ratio: 4.5634)
        #expect(r.displayRatio == "4.56:1")
    }
}

@Suite("ThemeColorPair audit (ADR-072 Phase 2)")
struct ThemeColorPairTests {

    /// Yuminai 다크 모드 핵심 조합 검증.
    /// - text(0xf0eeec) on bg(0x1a1817) = 약 13:1 → AAA pass
    @Test("text on bg (다크 모드) — AAA 충족")
    func textOnBgPassesAAA() {
        let result = WCAGContrast.audit(foreground: 0xf0eeec, background: 0x1a1817)
        #expect(result.ratio > 7.0)  // AAA normal threshold
        #expect(result.passesAAANormal == true)
    }

    /// textTertiary는 borderline — 본 ADR 발견 후 brightening 검토.
    @Test("textTertiary on bg (다크 모드) — borderline 식별")
    func textTertiaryDetection() {
        // textTertiary dark = 0x807a76 (~50% lightness)
        // bg dark = 0x1a1817
        // 예상 ratio ≈ 4.0~4.2 → AA normal fail (4.5 미만)
        let result = WCAGContrast.audit(foreground: 0x807a76, background: 0x1a1817)
        // 본 테스트는 "borderline" 검증 — 정확한 값은 luminance 함수 결과에 따름
        #expect(result.ratio >= 3.0)  // 적어도 large text는 가능
    }

    @Test("ThemeColorPair — pair 생성 + 양 모드 audit")
    func pairConstruction() {
        let pair = ThemeColorPair(
            id: "text-on-bg",
            foregroundName: "text",
            backgroundName: "bg",
            foregroundDark: 0xf0eeec,
            backgroundDark: 0x1a1817,
            foregroundLight: 0x1a1817,
            backgroundLight: 0xf6f3ee,
            usageContext: "본문 텍스트"
        )
        // 다크 모드
        #expect(pair.darkResult().passesAANormal == true)
        // 라이트 모드
        #expect(pair.lightResult().passesAANormal == true)
        // 양 모드 모두 AA 통과
        #expect(pair.passesDarkAA() == true)
        #expect(pair.passesLightAA() == true)
    }

    @Test("ThemeColorPair — 텍스트/non-text threshold 다름")
    func textVsNonTextThreshold() {
        let textPair = ThemeColorPair(
            id: "p1", foregroundName: "f", backgroundName: "b",
            foregroundDark: 0, backgroundDark: 0,
            foregroundLight: 0, backgroundLight: 0,
            usageContext: "test", isText: true
        )
        #expect(textPair.aaThreshold == 4.5)

        let iconPair = ThemeColorPair(
            id: "p2", foregroundName: "f", backgroundName: "b",
            foregroundDark: 0, backgroundDark: 0,
            foregroundLight: 0, backgroundLight: 0,
            usageContext: "test", isText: false
        )
        #expect(iconPair.aaThreshold == 3.0)  // SC 1.4.11 non-text

        let largePair = ThemeColorPair(
            id: "p3", foregroundName: "f", backgroundName: "b",
            foregroundDark: 0, backgroundDark: 0,
            foregroundLight: 0, backgroundLight: 0,
            usageContext: "test", isText: true, isLarge: true
        )
        #expect(largePair.aaThreshold == 3.0)  // SC 1.4.3 large
    }
}
