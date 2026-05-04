import SwiftUI
import YuminaiCore

/// **ADR-086 Phase 1** — 사이드바에 표시할 텔레그램 connection status pill.
///
/// 클릭 시 error log sheet 열기. health 상태에 따라 색상/icon 변화:
/// - idle: 회색 (Telegram 비활성)
/// - healthy: green checkmark
/// - degraded: orange exclamation
/// - failed: red xmark
///
/// - Note: **ADR-093 Phase 2 — Deprecated**. `BotStatusDockView`로 대체.
///   SidebarView에서 더 이상 직접 사용되지 않음. 외부 사용처가 남아있는 동안 유지.
@available(*, deprecated, renamed: "BotStatusDockView", message: "Use BotStatusDockView (ADR-093). TelegramHealthPill is superseded by BotStatusDock.")
public struct TelegramHealthPill: View {
    public let snapshot: TelegramHealthSnapshot
    public let onTap: () -> Void

    public init(snapshot: TelegramHealthSnapshot, onTap: @escaping () -> Void) {
        self.snapshot = snapshot
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: snapshot.state.iconName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(color)
                Text(label)
                    .font(Theme.Typography.micro.weight(.medium))
                    .foregroundStyle(color)
                if snapshot.consecutiveFailures > 0 && snapshot.state == .degraded {
                    Text("\(snapshot.consecutiveFailures)")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(color)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.10))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(color.opacity(0.30), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .accessibilityLabel("텔레그램 \(snapshot.state.displayName)")
        .accessibilityHint(tooltip)
    }

    private var color: Color {
        switch snapshot.state {
        case .idle: return Theme.Color.textTertiary
        case .healthy: return Theme.Color.success
        case .degraded: return .orange
        case .failed: return Theme.Color.danger
        }
    }

    private var label: String {
        switch snapshot.state {
        case .idle: return "텔레그램"
        case .healthy: return "정상"
        case .degraded: return "재시도"
        case .failed: return "실패"
        }
    }

    private var tooltip: String {
        switch snapshot.state {
        case .idle: return "텔레그램이 비활성. 설정에서 활성화하세요."
        case .healthy:
            return "텔레그램 정상 (\(snapshot.totalUpdatesProcessed)회 처리). 클릭으로 에러 로그 보기."
        case .degraded:
            return "일시 오류 — 자동 재시도 중. 마지막 오류: \(snapshot.lastErrorMessage ?? "?")"
        case .failed:
            return "영구 실패 — \(snapshot.lastErrorMessage ?? "?"). 클릭으로 에러 상세."
        }
    }
}
