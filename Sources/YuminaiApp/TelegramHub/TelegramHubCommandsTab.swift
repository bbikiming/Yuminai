import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-092 Phase 1** — Telegram Hub Commands 탭 (Phase 3 placeholder).
///
/// Phase 3 (ADR-094)에서 구현 예정:
/// - 봇 커맨드 등록 (/start, /switch, /help, custom)
/// - BotFather command menu 동기화
/// - HITL 커맨드 트리거 설정
struct TelegramHubCommandsTab: View {
    var body: some View {
        AnimatedEmptyState(
            icon: "terminal.fill",
            iconTint: Theme.Color.textTertiary,
            title: "커맨드 관리",
            message: "곧 출시될 예정 — Phase 3 (ADR-094)\n\n봇 커맨드 등록, BotFather 동기화, HITL 트리거 설정 등을 여기서 관리하게 될 예정이에요."
        )
    }
}
