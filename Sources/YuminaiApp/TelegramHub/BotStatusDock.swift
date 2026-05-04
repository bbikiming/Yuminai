import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-093 Phase 2** — 상시 표시 봇 상태 Dock 위젯 (YuminaiApp 레벨).
///
/// `TelegramHealthPill`(ADR-086)을 대체. SidebarView 하단에 배치.
/// SidebarView는 `BotStatusDockView` (YuminaiUI, stateless)를 렌더링.
/// 이 struct는 `AppModel`을 읽어 필요한 데이터를 추출 후 `BotStatusDockView`에 전달.
///
/// 단일 클릭 → popover (봇 상태 + 최근 에러 3건).
/// 더블 클릭 → `appModel.showTelegramHubSheet = true`.
@MainActor
struct BotStatusDock: View {
    @Environment(AppModel.self) private var appModel
    @State private var showPopover = false
    @State private var recentErrors: [TelegramErrorEntry] = []

    var body: some View {
        BotStatusDockView(
            health: appModel.telegramHealth,
            queueDepth: appModel.telegramQueueDepth,
            botCount: appModel.preferences.telegramBots.count,
            firstBotUsername: appModel.preferences.telegramBots.first(where: { $0.enabled })?.username,
            showPopover: $showPopover,
            onOpenHub: {
                showPopover = false
                appModel.showTelegramHubSheet = true
            },
            onOpenErrorLog: {
                showPopover = false
                appModel.showTelegramErrorLogSheet = true
            },
            recentErrors: recentErrors
        )
        .onAppear { loadErrors() }
        .onChange(of: appModel.telegramHealth) { _, _ in loadErrors() }
    }

    private func loadErrors() {
        Task {
            recentErrors = await appModel.telegramRecentErrors(limit: 3)
        }
    }
}
