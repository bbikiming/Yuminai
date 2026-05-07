import SwiftUI

/// **ADR-131** — 모든 sheet 우상단 X 버튼 공용 컴포넌트.
///
/// ## 배경
/// 50개 sheet 파일 중 SheetHeader를 사용하는 곳(1개)을 제외하면
/// X 버튼이 없거나, 제각각 구현되어 UX 일관성이 없었다.
///
/// ## 사용 패턴
///
/// ### overlay 스타일 (기본 — sheet 자체 헤더 없는 경우)
/// ```swift
/// var body: some View {
///     YuminaiSheet(...) { content }
///     .overlay(alignment: .topTrailing) {
///         SheetCloseButton { dismiss() }
///     }
/// }
/// ```
///
/// ### inline 스타일 (헤더 row 안 inline)
/// ```swift
/// SheetCloseButton(style: .inline) { dismiss() }
/// ```
///
/// ## 디자인 토큰
/// - xmark.circle.fill + symbolRenderingMode(.hierarchical)
/// - 18pt (overlay) / 16pt (inline)
/// - Theme.Color.textSecondary
/// - ⎋ Escape 키 shortcut (sheet 1개당 1개 한정)
/// - accessibilityLabel "닫기"
public struct SheetCloseButton: View {
    public let action: () -> Void
    public let style: Style

    public enum Style: Sendable {
        /// 우상단 floating overlay — sheet 자체 헤더 없는 경우 ZStack/overlay로 사용.
        case overlay
        /// 헤더 row 안 inline — 헤더 구성 시 맨 끝 아이템으로 사용.
        case inline
    }

    public init(style: Style = .overlay, action: @escaping () -> Void) {
        self.style = style
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: style == .overlay ? 18 : 16, weight: .regular))
                .foregroundStyle(Theme.Color.textSecondary)
                .symbolRenderingMode(.hierarchical)
                .padding(style == .overlay ? 14 : 0)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("닫기")
        .accessibilityLabel("닫기")
    }
}
