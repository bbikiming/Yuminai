import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-092 Phase 1** — Telegram Hub Bots 탭.
///
/// `TelegramBotListSection` + `TelegramBotGroupSection`을 VStack으로 묶어
/// 봇 목록과 그룹을 한 화면에서 볼 수 있게 한다.
struct TelegramHubBotsTab: View {
    var body: some View {
        VStack(spacing: 0) {
            TelegramBotListSection()
            Divider()
                .padding(.vertical, Theme.Spacing.md)
            TelegramBotGroupSection()
        }
    }
}
