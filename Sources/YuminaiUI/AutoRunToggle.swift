import SwiftUI
import YuminaiCore

/// **ADR-132** — 자동 실행 상태 표시 + 제어 토글.
///
/// Composer 영역에 추가되는 작은 버튼:
/// - idle: 회색 ⚙️ + "자동 실행"
/// - running: 초록 🟢 + "자동 실행 중 (turn N/30)"
/// - paused: 노랑 ⏸ + "일시정지"
/// - completed: 회색 ✓ + "완료"
///
/// 클릭 시 `onTap` 콜백 — Caller가 AutoRunControlSheet 열거나 pause/stop 처리.
public struct AutoRunToggle: View {

    // MARK: - Props

    public let state: AutoRunCoordinator.State
    public let maxTurns: Int
    public let onTap: () -> Void

    public init(
        state: AutoRunCoordinator.State,
        maxTurns: Int = 30,
        onTap: @escaping () -> Void
    ) {
        self.state = state
        self.maxTurns = maxTurns
        self.onTap = onTap
    }

    // MARK: - Body

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                statusIcon
                    .font(.system(size: 11))
                Text(statusLabel)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(labelColor)
                    .lineLimit(1)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(backgroundColor)
            )
            .overlay(
                Capsule()
                    .stroke(borderColor, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .help(helpText)
        .animation(.easeOut(duration: 0.2), value: stateKey)
    }

    // MARK: - 상태별 표시

    private var stateKey: String {
        switch state {
        case .idle: return "idle"
        case .running: return "running"
        case .paused: return "paused"
        case .completed: return "completed"
        case .stopped: return "stopped"
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch state {
        case .idle:
            Image(systemName: "gearshape")
                .foregroundStyle(Theme.Color.textTertiary)
        case .running:
            Circle()
                .fill(Color.green)
                .frame(width: 7, height: 7)
        case .paused:
            Image(systemName: "pause.fill")
                .foregroundStyle(Color.yellow)
        case .completed:
            Image(systemName: "checkmark")
                .foregroundStyle(Theme.Color.textTertiary)
        case .stopped:
            Image(systemName: "stop.fill")
                .foregroundStyle(Theme.Color.textTertiary)
        }
    }

    private var statusLabel: String {
        switch state {
        case .idle:
            return "자동 실행"
        case .running(_, let turn, _):
            return "자동 실행 중 (\(turn)/\(maxTurns))"
        case .paused(_, let reason):
            let short = String(reason.prefix(12))
            return "일시정지 — \(short)"
        case .completed(_, let reason, _, _):
            switch reason {
            case .stopKeyword: return "완료 ✓"
            case .userStop: return "중단됨"
            default: return "완료"
            }
        case .stopped:
            return "중단됨"
        }
    }

    private var labelColor: Color {
        switch state {
        case .idle: return Theme.Color.textSecondary
        case .running: return Color.green
        case .paused: return Color.yellow
        case .completed, .stopped: return Theme.Color.textTertiary
        }
    }

    private var backgroundColor: Color {
        switch state {
        case .idle: return Theme.Color.surfaceHi.opacity(0.4)
        case .running: return Color.green.opacity(0.08)
        case .paused: return Color.yellow.opacity(0.10)
        case .completed, .stopped: return Theme.Color.surfaceHi.opacity(0.3)
        }
    }

    private var borderColor: Color {
        switch state {
        case .idle: return Theme.Color.borderSubtle
        case .running: return Color.green.opacity(0.3)
        case .paused: return Color.yellow.opacity(0.3)
        case .completed, .stopped: return Theme.Color.borderSubtle
        }
    }

    private var helpText: String {
        switch state {
        case .idle: return "자동 실행 — 클릭해서 시작하거나 설정 변경"
        case .running: return "자동 실행 중 — 클릭해서 제어 패널 열기"
        case .paused: return "일시정지됨 — 클릭해서 재개 또는 중단"
        case .completed: return "자동 실행 완료 — 클릭해서 로그 보기"
        case .stopped: return "자동 실행 중단됨"
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Idle") {
    AutoRunToggle(state: .idle, onTap: {})
        .padding()
}

#Preview("Running") {
    AutoRunToggle(
        state: .running(runId: UUID(), turn: 5, startedAt: .now),
        maxTurns: 30,
        onTap: {}
    )
    .padding()
}

#Preview("Paused") {
    AutoRunToggle(
        state: .paused(runId: UUID(), reason: "위험 명령 감지"),
        onTap: {}
    )
    .padding()
}

#Preview("Completed") {
    AutoRunToggle(
        state: .completed(
            runId: UUID(),
            reason: .stopKeyword("작업 완료"),
            summary: "5회 실행",
            totalCost: 0.12
        ),
        onTap: {}
    )
    .padding()
}
#endif
