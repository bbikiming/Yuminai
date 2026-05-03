import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-086 Phase 4** — 봇 목록 섹션 (등록된 봇 추가/편집/삭제).
struct TelegramBotListSection: View {
    @Environment(AppModel.self) private var appModel
    @State private var showAddBot: Bool = false
    @State private var editingBotId: UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("등록된 봇")
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer()
                FlatButton("새 봇 추가", variant: .secondary) {
                    showAddBot = true
                }
            }
            if appModel.preferences.telegramBots.isEmpty {
                EmptyStateHint(
                    icon: "person.crop.square.filled.and.at.rectangle",
                    title: "등록된 봇이 없어요",
                    message: "새 봇을 추가하면 여러 봇으로 다양한 그룹을 운영할 수 있어요."
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(appModel.preferences.telegramBots) { bot in
                            botRow(bot)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showAddBot) {
            TelegramBotEditSheet(existing: nil) { config in
                Task {
                    await appModel.addTelegramBot(config)
                    showAddBot = false
                }
            } onCancel: {
                showAddBot = false
            }
        }
        .sheet(item: Binding(
            get: { editingBotId.flatMap { id in appModel.preferences.telegramBots.first { $0.id == id } } },
            set: { _ in editingBotId = nil }
        )) { bot in
            TelegramBotEditSheet(existing: bot) { config in
                Task {
                    await appModel.updateTelegramBot(config)
                    editingBotId = nil
                }
            } onCancel: {
                editingBotId = nil
            }
        }
    }

    private func botRow(_ bot: TelegramBotConfig) -> some View {
        let groupName = bot.groupId.flatMap { gid in
            appModel.preferences.telegramBotGroups.first { $0.id == gid }?.displayName
        }
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: bot.iconName)
                .font(.system(size: 16))
                .foregroundStyle(Theme.Color.folderColor(for: bot.colorName))
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(bot.displayName)
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Color.text)
                    if !bot.enabled {
                        Text("비활성")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textTertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.Color.surface)
                            .clipShape(Capsule())
                    }
                    if let groupName {
                        Text(groupName)
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.Color.accent.opacity(0.10))
                            .clipShape(Capsule())
                    }
                }
                if !bot.username.isEmpty {
                    Text("@\(bot.username)")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .textSelection(.enabled)
                }
                if !bot.notes.isEmpty {
                    Text(bot.notes)
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textTertiary)
                        .lineLimit(2)
                }
                Text("Keychain: \(bot.keychainKey)")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            Spacer()
            Button("편집") { editingBotId = bot.id }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Color.accent)
                .accessibilityLabel("\(bot.displayName) 봇 편집")
            Button("삭제", role: .destructive) {
                Task { await appModel.removeTelegramBot(bot.id) }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Color.danger)
            .accessibilityLabel("\(bot.displayName) 봇 삭제")
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .accessibilityElement(children: .contain)
    }
}
