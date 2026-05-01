import SwiftUI
import YuminaiTelegram
import YuminaiUI

/// cokacdir bot_settings.json에서 봇을 골라 토큰/chat id를 import.
struct CokacdirImportSheet: View {
    let bots: [CokacdirBot]
    let error: String?
    let onSelect: (CokacdirBot, Int64) -> Void
    let onCancel: () -> Void

    @State private var selectedBotId: String?
    @State private var manualChatIdText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            header

            if let error {
                errorBox(error)
            } else if bots.isEmpty {
                emptyBox
            } else {
                botList
                if let bot = selectedBot {
                    chatPicker(for: bot)
                }
            }

            Divider()

            HStack {
                if let bot = selectedBot {
                    Text("‘\(bot.displayName)’의 토큰을 Yuminai keychain에 저장해요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Spacer()
                }
                Spacer()
                FlatButton("취소", variant: .secondary, action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])
                FlatButton("가져오기", variant: .primary, action: applySelection)
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(selectedChatId == nil || selectedBot == nil)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 540)
        .background(Theme.Color.bg)
    }

    // MARK: - subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("cokacdir에서 봇 가져오기")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Color.text)
            Text("bot_settings.json에서 발견한 봇 중 하나를 골라주세요.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }

    private func errorBox(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("가져올 수 없어요")
                    .font(.callout.weight(.medium))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Theme.Color.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private var emptyBox: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 24))
                .foregroundStyle(Theme.Color.textTertiary)
            Text("등록된 봇이 없어요.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Color.text)
            Text("cokacdir에서 먼저 봇을 추가하세요.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var botList: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(bots) { bot in
                    BotRow(
                        bot: bot,
                        selected: bot.id == selectedBotId,
                        onTap: {
                            selectedBotId = bot.id
                            manualChatIdText = ""
                        }
                    )
                }
            }
        }
        .frame(maxHeight: 220)
    }

    @ViewBuilder
    private func chatPicker(for bot: CokacdirBot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Chat ID 선택")
                .font(Theme.Typography.small.weight(.semibold))
                .foregroundStyle(Theme.Color.textSecondary)

            if !bot.suggestedChatIds.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 6)], spacing: 6) {
                    ForEach(bot.suggestedChatIds, id: \.self) { id in
                        ChatChip(
                            id: id,
                            isOwner: id == bot.ownerUserId,
                            selected: manualChatIdText == String(id),
                            onTap: { manualChatIdText = String(id) }
                        )
                    }
                }
            }

            HStack(spacing: 8) {
                Text("직접 입력")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                TextField("Telegram chat id (숫자)", text: $manualChatIdText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
            }
        }
    }

    // MARK: - state

    private var selectedBot: CokacdirBot? {
        bots.first { $0.id == selectedBotId }
    }

    private var selectedChatId: Int64? {
        Int64(manualChatIdText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func applySelection() {
        guard let bot = selectedBot, let chatId = selectedChatId else { return }
        onSelect(bot, chatId)
    }
}

// MARK: - Rows

private struct BotRow: View {
    let bot: CokacdirBot
    let selected: Bool
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Theme.Color.accent : Theme.Color.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(bot.displayName)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Color.text)
                    HStack(spacing: 6) {
                        if !bot.username.isEmpty {
                            Text(bot.handle)
                                .font(Theme.Typography.small)
                                .foregroundStyle(Theme.Color.textSecondary)
                        }
                        if !bot.suggestedChatIds.isEmpty {
                            Text("·")
                                .foregroundStyle(Theme.Color.textTertiary)
                            Text("\(bot.suggestedChatIds.count)개 chat 후보")
                                .font(Theme.Typography.small)
                                .foregroundStyle(Theme.Color.textTertiary)
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm + 2)
            .background(selected ? Theme.Color.accentMuted : (hovering ? Theme.Color.surfaceHi : Theme.Color.surface))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(selected ? Theme.Color.accent : Theme.Color.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct ChatChip: View {
    let id: Int64
    let isOwner: Bool
    let selected: Bool
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: isOwner ? "person.fill" : (id < 0 ? "person.3.fill" : "person.fill"))
                    .font(.system(size: 10))
                    .foregroundStyle(selected ? Theme.Color.accent : Theme.Color.textSecondary)
                Text(String(id))
                    .font(Theme.Typography.monoSmall)
                    .foregroundStyle(selected ? Theme.Color.text : Theme.Color.textSecondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(selected ? Theme.Color.accentMuted : (hovering ? Theme.Color.surfaceHi : Theme.Color.surface))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .stroke(selected ? Theme.Color.accent : Theme.Color.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(isOwner ? "내 1:1 채팅" : (id < 0 ? "그룹/채널" : "1:1 채팅"))
    }
}
