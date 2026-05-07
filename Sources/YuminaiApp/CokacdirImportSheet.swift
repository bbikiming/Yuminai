import SwiftUI
import YuminaiCore
import YuminaiTelegram
import YuminaiUI

/// **ADR-100 / ADR-101** — cokacdir bot_settings.json에서 봇을 골라 토큰/chat id를 import.
struct CokacdirImportSheet: View {
    let bots: [CokacdirBot]
    let chatLabels: [Int64: CokacdirChatLabel]
    let error: String?
    /// **ADR-100** — `.legacy`(Settings 진입)는 단일 봇 슬롯, `.hub`는 multi-bot 모델로 추가.
    let mode: AppModel.CokacdirImportMode
    /// 현재 등록된 봇 목록 — 중복 체크용 (ADR-101).
    let existingBots: [TelegramBotConfig]
    let onSelect: (CokacdirBot, Int64) -> Void
    let onCancel: () -> Void

    @State private var selectedBotId: String?
    @State private var manualChatIdText: String = ""

    // MARK: - Validation

    private var isDuplicate: Bool {
        guard let bot = selectedBot else { return false }
        return !TelegramBotValidator.isUsernameAvailable(bot.username, in: existingBots)
    }

    private var isFormValid: Bool {
        guard let bot = selectedBot, selectedChatId != nil else { return false }
        return !isDuplicate && !bot.username.isEmpty || selectedChatId != nil && !isDuplicate
    }

    // More precise: valid = bot selected + chatId valid + not duplicate
    private var canImport: Bool {
        selectedBot != nil && selectedChatId != nil && !isDuplicate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            header

            if let error {
                errorBox(error)
            } else if bots.isEmpty {
                emptyBox
            } else {
                botList

                // 중복 봇 선택 시 경고
                if isDuplicate {
                    InfoCallout(tone: .warning) {
                        Text(TelegramHubFriendlyText.duplicateBotCallout)
                            .font(Theme.Typography.small)
                            .foregroundStyle(Theme.Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let bot = selectedBot, !isDuplicate {
                    chatPicker(for: bot)
                }
            }

            Divider()

            HStack {
                if let bot = selectedBot {
                    Text("’\(bot.displayName)’의 봇 토큰을 macOS 비밀번호 저장소에 저장해요.")
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
                    .disabled(!canImport)
            }
        }
        .padding(Theme.Spacing.xl)
        // ADR-073 — 너비만 반응형 (높이는 컨텐츠 기반).
        .yuminaiSheetFrame(width: 540)
        .background(Theme.Color.bg)
        .overlay(alignment: .topTrailing) {
            SheetCloseButton(action: onCancel)
        }
    }

    // MARK: - subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("cokacdir에서 봇 가져오기")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
                if mode == .hub {
                    Text("여러 봇 목록")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.Color.accentMuted)
                        .clipShape(Capsule())
                }
            }
            Text(mode == .hub
                ? "선택한 봇이 Telegram Hub의 봇 목록에 추가돼요. 대화방 번호가 있으면 연결 설정도 함께 생성돼요."
                : "bot_settings.json에서 발견한 봇 중 하나를 골라주세요. (단일 봇 슬롯 — 설정 호환 모드)")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
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
                    let alreadyRegistered = !TelegramBotValidator.isUsernameAvailable(
                        bot.username, in: existingBots
                    )
                    BotRow(
                        bot: bot,
                        selected: bot.id == selectedBotId,
                        alreadyRegistered: alreadyRegistered,
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
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("대화방 선택")
                .font(Theme.Typography.small.weight(.semibold))
                .foregroundStyle(Theme.Color.textSecondary)

            // ADR-101 — 대화방 종류 안내 callout
            InfoCallout(tone: .info) {
                Text(TelegramHubFriendlyText.chatTypeCalloutBody)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !bot.suggestedChatIds.isEmpty {
                VStack(spacing: 4) {
                    ForEach(bot.suggestedChatIds, id: \.self) { id in
                        ChatRow(
                            id: id,
                            label: chatLabels[id],
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
                TextField("대화방 번호 (숫자)", text: $manualChatIdText)
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
    /// ADR-101 — 이미 Hub에 등록된 봇이면 true.
    let alreadyRegistered: Bool
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(
                        alreadyRegistered
                        ? Theme.Color.textTertiary
                        : (selected ? Theme.Color.accent : Theme.Color.textTertiary)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(bot.displayName)
                            .font(Theme.Typography.body)
                            .foregroundStyle(alreadyRegistered ? Theme.Color.textSecondary : Theme.Color.text)
                        // ADR-101 — 이미 등록됨 배지
                        if alreadyRegistered {
                            DuplicateBadge()
                        }
                    }
                    HStack(spacing: 6) {
                        if !bot.username.isEmpty {
                            Text(bot.handle)
                                .font(Theme.Typography.small)
                                .foregroundStyle(Theme.Color.textSecondary)
                        }
                        if !bot.suggestedChatIds.isEmpty {
                            Text("·")
                                .foregroundStyle(Theme.Color.textTertiary)
                            Text("\(bot.suggestedChatIds.count)개 대화방 후보")
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

private struct ChatRow: View {
    let id: Int64
    let label: CokacdirChatLabel?
    let isOwner: Bool
    let selected: Bool
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 12))
                    .foregroundStyle(selected ? Theme.Color.accent : iconTint)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayTitle)
                        .font(Theme.Typography.body)
                        .foregroundStyle(selected ? Theme.Color.text : Theme.Color.text)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(String(id))
                            .font(Theme.Typography.monoSmall)
                            .foregroundStyle(Theme.Color.textTertiary)
                        if let label, !label.participantNames.isEmpty, label.kind == .group {
                            Text("·")
                                .foregroundStyle(Theme.Color.textTertiary)
                            Text("\(label.participantNames.count)명 활동")
                                .font(Theme.Typography.small)
                                .foregroundStyle(Theme.Color.textTertiary)
                        }
                    }
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Color.accent)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
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

    private var iconName: String {
        guard let kind = label?.kind else {
            return id < 0 ? "person.3.fill" : "person.fill"
        }
        switch kind {
        case .directWithOwner: return "person.crop.circle.fill"
        case .directOther: return "person.crop.circle"
        case .group: return "person.3.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private var iconTint: SwiftUI.Color {
        guard let kind = label?.kind else {
            return Theme.Color.textSecondary
        }
        switch kind {
        case .directWithOwner: return Theme.Color.accent
        case .group: return .orange
        default: return Theme.Color.textSecondary
        }
    }

    private var displayTitle: String {
        if let label {
            return label.title
        }
        if isOwner { return "내 1:1 채팅" }
        return id < 0 ? "그룹 채팅" : "1:1 채팅"
    }
}
