import SwiftUI

/// **ADR-072 Phase 3** — Focus indicator 강화 (WCAG 2.2 SC 2.4.7 + 2.4.11).
///
/// 근거 자료:
/// - **WCAG 2.2 SC 2.4.7 Focus Visible** (AA): 키보드 focus는 항상 시각적으로 표시되어야 함.
///   https://www.w3.org/TR/WCAG22/#focus-visible
/// - **WCAG 2.2 SC 2.4.11 Focus Not Obscured** (AA, NEW in 2.2):
///   focus된 element는 다른 콘텐츠에 가려져선 안 됨.
///   https://www.w3.org/TR/WCAG22/#focus-not-obscured-minimum
/// - **WCAG 2.2 SC 2.4.13 Focus Appearance** (AAA):
///   focus indicator는 ≥ 3:1 contrast ratio + ≥ 2px outline.
///   https://www.w3.org/TR/WCAG22/#focus-appearance
///
/// macOS 기본 focus ring은 시스템 accent color 기반 — 일관성 있지만 일부 custom
/// 컨트롤(IconButton 등)에서는 동작하지 않을 수 있음. 본 modifier는 명시적
/// Brand cyan ring을 추가해 모든 컨트롤에 일관된 focus appearance 보장.
public struct YuminaiFocusModifier: ViewModifier {
    /// 현재 focused 상태 (외부에서 @FocusState 등으로 전달).
    public let isFocused: Bool
    /// Focus ring 색상 (default: brand accent).
    public let color: Color
    /// Focus ring 두께 (WCAG 2.4.13 권고: ≥ 2px).
    public let lineWidth: CGFloat
    /// Focus ring 반경 (corner radius).
    public let cornerRadius: CGFloat

    public init(
        isFocused: Bool,
        color: Color = Theme.Color.focusRing,
        lineWidth: CGFloat = 2,
        cornerRadius: CGFloat = Theme.Radius.sm
    ) {
        self.isFocused = isFocused
        self.color = color
        self.lineWidth = lineWidth
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(isFocused ? color : .clear, lineWidth: lineWidth)
                    .padding(-2)  // outline은 element 외부에 (focus-not-obscured 대비)
            )
            .animation(.easeOut(duration: 0.1), value: isFocused)
    }
}

public extension View {
    /// **ADR-072 Phase 3** — 키보드 focus 시 강조 ring 표시.
    /// WCAG 2.2 SC 2.4.7 (Focus Visible) AA + SC 2.4.13 (Focus Appearance) AAA 권고 충족.
    func yuminaiFocusRing(
        _ isFocused: Bool,
        color: Color = Theme.Color.focusRing,
        cornerRadius: CGFloat = Theme.Radius.sm
    ) -> some View {
        modifier(YuminaiFocusModifier(
            isFocused: isFocused,
            color: color,
            cornerRadius: cornerRadius
        ))
    }
}
