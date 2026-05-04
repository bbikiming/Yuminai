import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-092 Phase 1 / ADR-093 Phase 2** — Telegram Hub Bindings 탭.
///
/// Phase 1: `TelegramBotBindingSection` 단순 wrapper.
/// Phase 2: `LazyVGrid(2-column)` of `ChatContextCard`로 교체.
/// binding이 없으면 `AnimatedEmptyState`.
@MainActor
struct TelegramHubBindingsTab: View {
    @Environment(AppModel.self) private var appModel
    @State private var editingBinding: BotChatBinding? = nil

    private let gridColumns = [
        GridItem(.flexible(), spacing: Theme.Spacing.md),
        GridItem(.flexible(), spacing: Theme.Spacing.md)
    ]

    var body: some View {
        if appModel.preferences.telegramBotChatBindings.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: Theme.Spacing.md) {
                    ForEach(appModel.preferences.telegramBotChatBindings) { binding in
                        ChatContextCard(
                            binding: binding,
                            onEdit: { editingBinding = binding },
                            onDisable: { toggleBinding(binding) }
                        )
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .sheet(item: $editingBinding) { binding in
                TelegramBotBindingEditSheet(
                    existing: binding,
                    bots: appModel.preferences.telegramBots,
                    workspaces: appModel.workspaces,
                    onSave: { updated in
                        Task { await appModel.upsertBotChatBinding(updated) }
                        editingBinding = nil
                    },
                    onCancel: { editingBinding = nil }
                )
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        AnimatedEmptyState(
            icon: "link.badge.plus",
            iconTint: Theme.Color.accent,
            title: "연결 없음",
            message: "아직 대화방 → 작업 폴더 연결이 없어요.\n\n봇 온보딩 3단계에서 연결을 추가하거나,\n봇 목록 탭에서 봇을 선택해 직접 추가할 수 있어요."
        ) {
            FlatButton("봇 추가하기", icon: "plus.circle.fill", variant: .secondary) {
                appModel.showTelegramHubSheet = true
            }
        }
        .padding(Theme.Spacing.xl)
    }

    // MARK: - Actions

    private func toggleBinding(_ binding: BotChatBinding) {
        guard let idx = appModel.preferences.telegramBotChatBindings.firstIndex(
            where: { $0.id == binding.id }
        ) else { return }
        var updated = binding
        if updated.activeWorkspaceId != nil {
            updated = BotChatBinding(
                id: updated.id,
                botId: updated.botId,
                chatId: updated.chatId,
                activeWorkspaceId: nil,
                allowedWorkspaceIds: updated.allowedWorkspaceIds,
                nickname: updated.nickname
            )
        }
        // 활성화는 워크스페이스 선택이 필요하므로 edit sheet으로
        if binding.activeWorkspaceId != nil {
            appModel.preferences.telegramBotChatBindings[idx] = updated
            Task { await appModel.savePreferences() }
        } else {
            editingBinding = binding
        }
    }
}
