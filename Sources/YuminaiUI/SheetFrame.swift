import SwiftUI
import AppKit

/// **ADR-073 + ADR-074** — 반응형 sheet frame modifier.
///
/// ## 진화 단계
///
/// **ADR-073**: 모든 sheet의 fixed `.frame(width:height:)`를 min/ideal/max로 대체 →
///   작은 윈도우에서 잘림 일부 완화.
///
/// **ADR-074** (본 버전): 부모 윈도우 크기를 동적으로 추적하여 진정한 반응형 구현.
///   - 큰 화면: 컨텐츠가 sheet 안에 fit → 스크롤 없음
///   - 작은 화면: ScrollView 활성 + footer 고정 (잘리지 않음 보장)
///   - 부모 윈도우 < idealSize: sheet가 부모의 ~85% 크기로 축소
///
/// ## 근거
/// - **Apple HIG "Sheets"** (https://developer.apple.com/design/human-interface-guidelines/sheets):
///   - "Make sure a sheet looks good and works well at every size people might choose"
///   - "Make essential controls reachable" — footer 고정 권고
/// - **WCAG 2.2 SC 1.4.10 Reflow** (AA): 컨텐츠는 viewport에 맞게 reflow
/// - **WCAG 2.2 SC 2.4.11 Focus Not Obscured** (AA, NEW): footer 잘림 방지
/// - **NSWindow screen API**: parent window의 visibleFrame으로 화면 가용 영역 확인
///
/// ## 구조
/// ```
/// YuminaiSheet {
///     content     ← ScrollView가 자동으로 감싸지만 컨텐츠가 작으면 스크롤 안 보임
/// } footer: {
///     buttons     ← 항상 하단에 고정. 절대 잘리지 않음
/// }
/// ```
public struct YuminaiSheetFrameModifier: ViewModifier {
    public let idealWidth: CGFloat
    public let idealHeight: CGFloat
    public let wrapInScrollView: Bool
    /// 절대 최소 너비 — 보조 모니터(960×640) 기준.
    public static let absoluteMinWidth: CGFloat = 360
    /// 절대 최소 높이.
    public static let absoluteMinHeight: CGFloat = 240
    /// 부모 윈도우의 % — sheet가 이만큼 차지 가능 (잘림 방지).
    public static let maxOfParentRatio: CGFloat = 0.92

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
        // ADR-074 — GeometryReader로 부모(NSWindow) 크기 감지하여 sheet가 잘리지 않게.
        WindowSizeReader { windowSize in
            let availableWidth = max(Self.absoluteMinWidth, windowSize.width * Self.maxOfParentRatio)
            let availableHeight = max(Self.absoluteMinHeight, windowSize.height * Self.maxOfParentRatio)
            let resolvedWidth = min(idealWidth, availableWidth)
            let resolvedHeight = min(idealHeight, availableHeight)

            Group {
                if wrapInScrollView {
                    // ADR-074 Phase 3 — ScrollView지만 컨텐츠가 fit되면 스크롤 indicator 안 보임
                    ScrollView(.vertical, showsIndicators: true) {
                        content
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollContentBackground(.hidden)
                } else {
                    content
                }
            }
            .frame(
                width: resolvedWidth,
                height: resolvedHeight
            )
        }
    }
}

/// **ADR-074** — NSWindow 크기를 추적하는 helper view.
/// SwiftUI의 GeometryReader는 부모 view의 크기만 알 수 있어 sheet 같은 modal에선
/// 부모 윈도우 크기를 직접 측정해야 함.
struct WindowSizeReader<Content: View>: View {
    @ViewBuilder let content: (CGSize) -> Content
    @State private var windowSize: CGSize = CGSize(width: 1280, height: 800)

    init(@ViewBuilder content: @escaping (CGSize) -> Content) {
        self.content = content
    }

    var body: some View {
        content(windowSize)
            .background(WindowAccessor { window in
                guard let screenFrame = window?.screen?.visibleFrame else { return }
                // sheet는 부모 윈도우의 visible frame 안에 있으므로
                // window.frame이 아닌 parent.contentView.frame을 사용해야 함.
                // 단, sheet 자체도 NSWindow이므로 parentWindow.frame 사용.
                if let parent = window?.parent {
                    windowSize = parent.frame.size
                } else {
                    // sheet가 아직 attach 전 — fallback to screen visibleFrame * 0.9
                    windowSize = CGSize(
                        width: screenFrame.width * 0.9,
                        height: screenFrame.height * 0.9
                    )
                }
            })
    }
}

/// **ADR-074** — NSViewRepresentable로 NSWindow에 접근하는 헬퍼.
struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { [weak view] in
            callback(view?.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            callback(nsView?.window)
        }
    }
}

public extension View {
    /// **ADR-073 + ADR-074** — 반응형 sheet frame.
    ///
    /// - 큰 화면: `idealWidth × idealHeight`로 표시 (스크롤 없음)
    /// - 작은 화면: 부모 윈도우의 ~92%까지 자동 축소
    /// - 컨텐츠가 sheet 높이 초과 시 ScrollView로 스크롤
    ///
    /// - Parameters:
    ///   - width: 충분한 화면에서의 권장 너비
    ///   - height: 충분한 화면에서의 권장 높이
    ///   - wrapInScrollView: 컨텐츠를 ScrollView로 감쌀지. 이미 ScrollView가 있는 sheet는 false.
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
        WindowSizeReader { windowSize in
            let availableWidth = max(YuminaiSheetFrameModifier.absoluteMinWidth, windowSize.width * YuminaiSheetFrameModifier.maxOfParentRatio)
            self.frame(width: min(width, availableWidth))
        }
    }
}

// MARK: - YuminaiSheet (ADR-074 Phase 4 — Footer pinning)

/// **ADR-074 Phase 4** — Sheet container with pinned footer.
///
/// **문제**: 단일 ScrollView 안에 footer를 넣으면, 작은 화면에서 footer까지
/// 스크롤되어야 보임. 사용자가 "취소"/"만들기" 버튼을 못 보고 sheet를 닫는 등
/// UX 문제 발생.
///
/// **해결** (Apple HIG 권고): footer를 ScrollView 밖에 분리, VStack 하단 고정.
/// 컨텐츠가 길어지면 컨텐츠만 스크롤되고 footer는 항상 보임.
///
/// 사용법:
/// ```swift
/// YuminaiSheet(width: 580, height: 640) {
///     header
///     formContent     // 길어지면 스크롤됨
/// } footer: {
///     HStack {
///         FlatButton("취소", action: onCancel)
///         FlatButton("만들기", variant: .primary, action: onCreate)
///     }
/// }
/// ```
public struct YuminaiSheet<Content: View, Footer: View>: View {
    let idealWidth: CGFloat
    let idealHeight: CGFloat
    let content: Content
    let footer: Footer

    public init(
        width: CGFloat,
        height: CGFloat,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.idealWidth = width
        self.idealHeight = height
        self.content = content()
        self.footer = footer()
    }

    public var body: some View {
        WindowSizeReader { windowSize in
            let availableWidth = max(
                YuminaiSheetFrameModifier.absoluteMinWidth,
                windowSize.width * YuminaiSheetFrameModifier.maxOfParentRatio
            )
            let availableHeight = max(
                YuminaiSheetFrameModifier.absoluteMinHeight,
                windowSize.height * YuminaiSheetFrameModifier.maxOfParentRatio
            )
            let resolvedWidth = min(idealWidth, availableWidth)
            let resolvedHeight = min(idealHeight, availableHeight)

            VStack(spacing: 0) {
                // ADR-074 Phase 3 — 컨텐츠가 fit되면 스크롤 indicator 안 보이고
                // 컨텐츠가 더 크면 스크롤로 처리. footer는 분리되어 있어 절대 잘리지 않음.
                ScrollView(.vertical, showsIndicators: true) {
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollContentBackground(.hidden)

                // ADR-074 Phase 4 — footer 고정 (ScrollView 밖)
                Divider()
                footer
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(Theme.Color.surface)
            }
            .frame(width: resolvedWidth, height: resolvedHeight)
            .background(Theme.Color.bg)
        }
    }
}
