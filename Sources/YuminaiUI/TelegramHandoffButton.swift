import SwiftUI
import YuminaiCore

/// **ADR-151** — 텔레그램 핸드오프 버튼.
///
/// Composer footer, ChatToolbar, ChatSessionRow context menu에서 재사용.
/// - `isAvailable`: 봇 활성화 + binding 있을 때만 enabled
/// - disabled 시: 툴팁 "텔레그램 봇을 먼저 연결하세요"
/// - enabled 시: 툴팁 "현재 세션을 텔레그램으로 이어서 작업하기"
public struct TelegramHandoffButton: View {
    /// 봇이 활성화돼 있고 binding이 존재할 때 true.
    public let isAvailable: Bool
    /// 버튼 탭 콜백.
    public let onTap: () -> Void

    public init(isAvailable: Bool, onTap: @escaping () -> Void) {
        self.isAvailable = isAvailable
        self.onTap = onTap
    }

    @State private var hovering = false

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.system(size: 12, weight: .medium))
                Text("텔레그램으로")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isAvailable
                ? (hovering ? Color.accentColor : Color.accentColor.opacity(0.8))
                : Color.secondary
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isAvailable
                        ? (hovering ? Color.accentColor.opacity(0.18) : Color.accentColor.opacity(0.10))
                        : Color.secondary.opacity(0.08)
                    )
            )
            .animation(.easeOut(duration: 0.12), value: hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .help(isAvailable
            ? "현재 세션을 텔레그램으로 이어서 작업하기"
            : "텔레그램 봇을 먼저 연결하세요 (설정 → Telegram Hub)"
        )
        .accessibilityLabel(isAvailable
            ? "텔레그램으로 이어서 작업하기"
            : "텔레그램 봇 연결 필요"
        )
        .onHover { hovering = $0 }
    }
}

/// Toolbar 전용 아이콘 전용 버전 (compact, 텍스트 없음).
public struct TelegramHandoffIconButton: View {
    public let isAvailable: Bool
    public let onTap: () -> Void

    public init(isAvailable: Bool, onTap: @escaping () -> Void) {
        self.isAvailable = isAvailable
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isAvailable ? Color.accentColor : Color.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .help(isAvailable
            ? "텔레그램으로 이어서 (현재 세션 핸드오프)"
            : "텔레그램 봇 연결 필요"
        )
        .accessibilityLabel("텔레그램 핸드오프")
    }
}
