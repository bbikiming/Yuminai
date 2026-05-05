import SwiftUI

/// **ADR-120** — 모든 sheet 공용 헤더 컴포넌트.
///
/// ## 배경
/// CommunityResourcesSheet에서 이중 헤더 문제(Sheet wrapper 헤더 + Panel 자체 헤더)가
/// 발견됨. 아울러 시트마다 헤더 패딩·폰트·닫기 버튼 스타일이 제각각이었다.
///
/// ## 표준 패턴
/// - 좌측: 아이콘 + 제목 (`title2.weight(.semibold)`)
/// - 중앙 trailing: 옵셔널 액션 영역 (버튼 그룹 등)
/// - 우측 끝: X 닫기 버튼
/// - padding: `Theme.Spacing.lg horizontal`, `.md vertical`
/// - background: `Theme.Color.surface`
/// - 하단 Divider 포함
///
/// ## 사용 예
/// ```swift
/// SheetHeader(icon: "cube.box.fill", title: "커뮤니티 자료", onClose: { dismiss() }) {
///     Button("스택 번들") { ... }
/// }
/// ```
public struct SheetHeader<Trailing: View>: View {

    public let icon: String
    public let title: String
    public let subtitle: String?
    public let onClose: () -> Void
    @ViewBuilder public let trailing: () -> Trailing

    public init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        onClose: @escaping () -> Void,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.onClose = onClose
        self.trailing = trailing
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Color.accent)

                if let subtitle = subtitle {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.Color.text)
                        Text(subtitle)
                            .font(Theme.Typography.small)
                            .foregroundStyle(Theme.Color.textSecondary)
                            .lineLimit(1)
                    }
                } else {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Color.text)
                }

                Spacer()

                trailing()

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .buttonStyle(.plain)
                .help("닫기")
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.Color.surface)

            Divider()
        }
    }
}

/// `SheetHeader` without trailing actions (EmptyView variant).
public extension SheetHeader where Trailing == EmptyView {
    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        onClose: @escaping () -> Void
    ) {
        self.init(
            icon: icon,
            title: title,
            subtitle: subtitle,
            onClose: onClose,
            trailing: { EmptyView() }
        )
    }
}
