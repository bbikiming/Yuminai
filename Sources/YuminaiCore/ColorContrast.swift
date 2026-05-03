import Foundation

// MARK: - WCAG 2.2 Color Contrast (ADR-072 Phase 2)
//
// 근거 자료:
// 1. **W3C WCAG 2.2** (https://www.w3.org/TR/WCAG22/) — 공식 권고 (2023-10-05)
//    - SC 1.4.3 Contrast (Minimum) AA: normal text 4.5:1, large text 3:1
//    - SC 1.4.6 Contrast (Enhanced) AAA: normal text 7:1, large text 4.5:1
//    - SC 1.4.11 Non-text Contrast AA: UI components 3:1
//
// 2. **WCAG 2.2 Relative Luminance 정의**
//    https://www.w3.org/TR/WCAG22/#dfn-relative-luminance
//    L = 0.2126 * R + 0.7152 * G + 0.0722 * B
//    where R, G, B are linearized sRGB values
//
// 3. **Contrast Ratio 공식**
//    https://www.w3.org/TR/WCAG22/#dfn-contrast-ratio
//    contrast = (L1 + 0.05) / (L2 + 0.05)  where L1 > L2
//    Range: 1:1 (no contrast) ~ 21:1 (max, black/white)
//
// 4. **APCA (WCAG 3.0 draft) 비교 메모**
//    Andrew Somers의 Advanced Perceptual Contrast Algorithm은 다크 모드에 더 정확하지만
//    아직 W3C Working Draft 단계 (2024). 본 모듈은 WCAG 2.2 공식을 따르되,
//    APCA가 권고화되면 별도 ADR로 추가 검토.
//
// 5. **Apple Human Interface Guidelines — Color**
//    https://developer.apple.com/design/human-interface-guidelines/color
//    "Use sufficient color contrast" — WCAG 2.x 권고를 명시 채택.

/// WCAG 준수 레벨.
public enum WCAGLevel: String, Sendable, CaseIterable {
    /// 최소 권고 (대부분의 사용자에게 충분).
    case aa = "AA"
    /// 강화된 권고 (시각 저하 사용자 친화).
    case aaa = "AAA"
}

/// WCAG에서 분류하는 텍스트 크기.
/// **Large text** = 18pt 이상 OR 14pt 이상 bold (W3C SC 1.4.3 정의).
public enum WCAGTextSize: String, Sendable, CaseIterable {
    case normal
    case large

    /// 해당 크기에 적용되는 contrast threshold.
    public func threshold(for level: WCAGLevel) -> Double {
        switch (self, level) {
        case (.normal, .aa):  return 4.5
        case (.normal, .aaa): return 7.0
        case (.large, .aa):   return 3.0
        case (.large, .aaa):  return 4.5
        }
    }
}

/// Color contrast 감사 결과.
public struct ContrastResult: Sendable, Equatable {
    /// 계산된 contrast ratio (1.0 ~ 21.0).
    public let ratio: Double
    /// 정규화된 표시값 (소수 둘째 자리).
    public var displayRatio: String {
        String(format: "%.2f:1", ratio)
    }
    /// AA 통과 여부 (normal text).
    public var passesAANormal: Bool { ratio >= 4.5 }
    /// AA 통과 여부 (large text).
    public var passesAALarge: Bool { ratio >= 3.0 }
    /// AAA 통과 여부 (normal text).
    public var passesAAANormal: Bool { ratio >= 7.0 }
    /// AAA 통과 여부 (large text).
    public var passesAAALarge: Bool { ratio >= 4.5 }
    /// Non-text contrast 통과 여부 (UI components, SC 1.4.11).
    public var passesNonText: Bool { ratio >= 3.0 }

    /// 기본 init — ratio만 받고 모든 pass 여부 자동 계산.
    public init(ratio: Double) {
        self.ratio = ratio
    }

    /// 가장 심한 등급 (사용자에게 한 줄 요약).
    public var worstLevel: String {
        if !passesNonText { return "비텍스트도 미충족 (3:1 미만)" }
        if !passesAALarge { return "큰 텍스트만 가능 (3:1 ~ 4.5:1)" }
        if !passesAANormal { return "AA 미충족 — 보통 텍스트 부적합" }
        if !passesAAANormal { return "AA 충족 (normal 4.5:1 ~)" }
        return "AAA 충족 (normal 7:1 ~)"
    }
}

/// **WCAG 2.2 Color Contrast 계산** — 모든 함수는 pure (테스트 가능).
public enum WCAGContrast {

    /// 단일 sRGB 채널값 (0~1)을 WCAG 정의 linear 공간으로 변환.
    /// 공식: https://www.w3.org/TR/WCAG22/#dfn-relative-luminance
    ///   if c <= 0.03928: c / 12.92
    ///   else: ((c + 0.055) / 1.055) ^ 2.4
    public static func linearize(_ channel: Double) -> Double {
        if channel <= 0.03928 {
            return channel / 12.92
        }
        return pow((channel + 0.055) / 1.055, 2.4)
    }

    /// sRGB 색상 (0~255 정수)에서 relative luminance 계산.
    /// L = 0.2126 * Rlin + 0.7152 * Glin + 0.0722 * Blin
    /// Range: 0.0 (black) ~ 1.0 (white)
    public static func relativeLuminance(r: Int, g: Int, b: Int) -> Double {
        let rLin = linearize(Double(r) / 255.0)
        let gLin = linearize(Double(g) / 255.0)
        let bLin = linearize(Double(b) / 255.0)
        return 0.2126 * rLin + 0.7152 * gLin + 0.0722 * bLin
    }

    /// 16진수 색상 (0xRRGGBB)에서 relative luminance.
    public static func relativeLuminance(rgb: UInt32) -> Double {
        let r = Int((rgb >> 16) & 0xFF)
        let g = Int((rgb >> 8) & 0xFF)
        let b = Int(rgb & 0xFF)
        return relativeLuminance(r: r, g: g, b: b)
    }

    /// 두 색상 간 contrast ratio.
    /// 공식: (L_brighter + 0.05) / (L_darker + 0.05)
    /// Range: 1.0 (동일 색) ~ 21.0 (black ↔ white)
    public static func contrastRatio(_ rgb1: UInt32, _ rgb2: UInt32) -> Double {
        let l1 = relativeLuminance(rgb: rgb1)
        let l2 = relativeLuminance(rgb: rgb2)
        let brighter = max(l1, l2)
        let darker = min(l1, l2)
        return (brighter + 0.05) / (darker + 0.05)
    }

    /// 두 색상 간 ContrastResult 감사.
    public static func audit(foreground: UInt32, background: UInt32) -> ContrastResult {
        let ratio = contrastRatio(foreground, background)
        return ContrastResult(ratio: ratio)
    }
}

// MARK: - Theme color audit (ADR-072 Phase 2)

/// Theme.Color 값의 dark/light 변형. 감사 대상.
public struct ThemeColorPair: Sendable, Equatable, Identifiable {
    public let id: String  // "text on bg" 등 unique
    public let foregroundName: String
    public let backgroundName: String
    public let foregroundDark: UInt32
    public let backgroundDark: UInt32
    public let foregroundLight: UInt32
    public let backgroundLight: UInt32
    /// 사용 컨텍스트 ("body text", "small caption", "icon" 등) — UX 라이팅 친화.
    public let usageContext: String
    /// 텍스트인지 / UI 컴포넌트인지.
    public let isText: Bool
    /// large text(18pt+ or 14pt+ bold)인지 normal인지.
    public let isLarge: Bool

    public init(
        id: String,
        foregroundName: String,
        backgroundName: String,
        foregroundDark: UInt32,
        backgroundDark: UInt32,
        foregroundLight: UInt32,
        backgroundLight: UInt32,
        usageContext: String,
        isText: Bool = true,
        isLarge: Bool = false
    ) {
        self.id = id
        self.foregroundName = foregroundName
        self.backgroundName = backgroundName
        self.foregroundDark = foregroundDark
        self.backgroundDark = backgroundDark
        self.foregroundLight = foregroundLight
        self.backgroundLight = backgroundLight
        self.usageContext = usageContext
        self.isText = isText
        self.isLarge = isLarge
    }

    /// 다크 모드 contrast 감사.
    public func darkResult() -> ContrastResult {
        WCAGContrast.audit(foreground: foregroundDark, background: backgroundDark)
    }

    /// 라이트 모드 contrast 감사.
    public func lightResult() -> ContrastResult {
        WCAGContrast.audit(foreground: foregroundLight, background: backgroundLight)
    }

    /// 적용 threshold (텍스트/크기에 따라).
    public var aaThreshold: Double {
        if !isText { return 3.0 }  // SC 1.4.11
        return isLarge ? 3.0 : 4.5  // SC 1.4.3
    }

    public var aaaThreshold: Double {
        if !isText { return 4.5 }  // best practice
        return isLarge ? 4.5 : 7.0  // SC 1.4.6
    }

    /// 다크 모드 통과 여부 (AA).
    public func passesDarkAA() -> Bool {
        darkResult().ratio >= aaThreshold
    }

    /// 라이트 모드 통과 여부 (AA).
    public func passesLightAA() -> Bool {
        lightResult().ratio >= aaThreshold
    }
}
