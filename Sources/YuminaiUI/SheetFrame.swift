import SwiftUI

/// **ADR-073 Phase 1** — 반응형 sheet frame modifier.
///
/// 배경: macOS sheet는 부모 윈도우보다 클 수 없음. 그러나 sheet 컨텐츠가
/// `.frame(width: X, height: Y)`로 고정되면 작은 윈도우에서 sheet가 잘림
/// (top/bottom/sides가 viewport 밖으로).
///
/// 해결: 모든 sheet의 outer frame을 `.yuminaiSheetFrame(...)`로 통일.
/// - `minWidth`/`minHeight`: 작은 모니터(960×640)에서도 표시 가능한 절대 최소
/// - `idealWidth`/`idealHeight`: 충분한 화면에서의 권장 크기
/// - `maxWidth` cap: 너무 큰 모니터에서 sheet가 과도하게 늘어나는 것 방지
/// - 기본 ScrollView wrap: 컨텐츠가 sheet height 초과 시 스크롤로 처리
///
/// 근거:
/// - Apple HIG "Sheets" (https://developer.apple.com/design/human-interface-guidelines/sheets):
///   "Make sure a sheet looks good and works well at every size people might choose."
/// - WCAG 2.2 SC 1.4.10 Reflow (AA): 컨텐츠는 viewport에 맞게 reflow되어야 함.
/// - WCAG 2.2 SC 2.4.11 Focus Not Obscured (AA, NEW): focus된 element는 가려지면 안 됨.
public struct YuminaiSheetFrameModifier: ViewModifier {
    public let idealWidth: CGFloat
    public let idealHeight: CGFloat
    public let wrapInScrollView: Bool
    /// 절대 최소 너비 — 매우 작은 sheet (440px)에서는 360, 큰 sheet에서도 360.
    /// 사용자 보조 모니터(960px) 기준 sheet가 화면을 다 차지해도 괜찮음.
    public static let absoluteMinWidth: CGFloat = 360
    /// 절대 최소 높이 — 컨텐츠가 짧은 sheet (rename 220px)는 그대로, 큰 sheet도 240부터 가능.
    public static let absoluteMinHeight: CGFloat = 240

    public init(
        idealWidth: CGFloat,
        idealHeight: CGFloat,
        wrapInScrollView: Bool
    ) {
        self.idealWidth = idealWidth
        self.idealHeight = idealHeight
        self.wrapInScrollView = wrapInScrollView
    }

    public func body(content: Content) -> some View {
        Group {
            if wrapInScrollView {
                ScrollView(.vertical, showsIndicators: true) {
                    content
                }
                .scrollContentBackground(.hidden)
            } else {
                content
            }
        }
        .frame(
            minWidth: min(idealWidth, Self.absoluteMinWidth),
            idealWidth: idealWidth,
            maxWidth: idealWidth,
            minHeight: min(idealHeight, Self.absoluteMinHeight),
            idealHeight: idealHeight,
            maxHeight: idealHeight
        )
    }
}

public extension View {
    /// **ADR-073** — 반응형 sheet frame.
    ///
    /// 기존 `.frame(width: X, height: Y)`를 대체. 작은 화면에서도 잘리지 않음.
    /// - 큰 화면: `idealWidth × idealHeight`로 표시
    /// - 작은 화면: `minWidth × minHeight`까지 축소 + 컨텐츠 ScrollView로 스크롤
    ///
    /// - Parameters:
    ///   - width: 충분한 화면에서의 권장 너비 (기존 `.frame(width:)` 값)
    ///   - height: 충분한 화면에서의 권장 높이 (기존 `.frame(height:)` 값)
    ///   - wrapInScrollView: 컨텐츠를 ScrollView로 감쌀지. 이미 ScrollView가 있는 sheet (RoutingDecisionLogSheet 등)는 false.
    func yuminaiSheetFrame(
        width: CGFloat,
        height: CGFloat,
        wrapInScrollView: Bool = true
    ) -> some View {
        modifier(YuminaiSheetFrameModifier(
            idealWidth: width,
            idealHeight: height,
            wrapInScrollView: wrapInScrollView
        ))
    }

    /// **ADR-073** — 너비만 지정 (rename, picker 등 짧은 sheet).
    func yuminaiSheetFrame(width: CGFloat) -> some View {
        self.frame(
            minWidth: min(width, YuminaiSheetFrameModifier.absoluteMinWidth),
            idealWidth: width,
            maxWidth: width
        )
    }
}
