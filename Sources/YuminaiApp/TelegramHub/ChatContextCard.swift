import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-093 Phase 2** — Bindings 탭에서 chat ↔ workspace 매핑을 카드로 시각화.
///
/// 디자인:
/// ```
/// ┌────────────────────────────────────────────────┐
/// │ 💬 Chat: 12345 (Private DM)                    │
/// │ ─────────────────────────────────────────────  │
/// │ Bot:        @YuminaiBot                        │
/// │ Workspace:  Yuminai (~/Documents/.../Yuminai)  │
/// │ Whitelist:  ✅ Allowed                          │
/// │ Last msg:   "/run swift test" · 3m ago         │
/// │                                                │
/// │ [Edit Binding]  [Disable]                      │  ← hover 시만
/// └────────────────────────────────────────────────┘
/// ```
///
/// hover 시에만 [Edit Binding] / [Disable] 액션 버튼 등장 (opacity transition).
@MainActor
struct ChatContextCard: View {
    let binding: BotChatBinding
    let onEdit: () -> Void
    let onDisable: () -> Void

    @Environment(AppModel.self) private var appModel
    @State private var isHovering = false
    @State private var lastActivity: Date? = nil

    var body: some View {
        CardSection(style: .elevated) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                headerRow
                Divider()
                infoRows
                if isHovering {
                    actionRow
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .onHover { isHovering = $0 }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isHovering)
        .onAppear { loadLastActivity() }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Theme.Color.accent.opacity(0.12))
                    .frame(width: 22, height: 22)
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Color.accent)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("대화방 번호: \(binding.chatId)")
                    .font(Theme.Typography.label.weight(.semibold))
                    .foregroundStyle(Theme.Color.text)
                if !binding.nickname.isEmpty {
                    Text(binding.nickname)
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
            }
            Spacer()
            if binding.activeWorkspaceId == nil {
                Text("비활성")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.Color.surface)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Theme.Color.borderSubtle, lineWidth: 0.5))
            }
        }
    }

    // MARK: - Info rows

    private var infoRows: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            infoRow(label: "봇", value: botName)
            infoRow(label: "작업 폴더", value: workspaceName)
            infoRow(label: "허가", value: nil, custom: whitelistBadge)
            if let lastActivity {
                infoRow(label: "마지막 메시지", value: relativeTime(lastActivity))
            }
        }
    }

    @ViewBuilder
    private func infoRow(
        label: String,
        value: String?,
        custom: (some View)? = Optional<EmptyView>.none
    ) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label + ":")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textTertiary)
                .frame(width: 72, alignment: .leading)
            if let value {
                Text(value)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(2)
            }
            if let custom {
                custom
            }
        }
    }

    // Custom overload that accepts any view
    private func infoRow(label: String, value: String?, custom: some View) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label + ":")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textTertiary)
                .frame(width: 72, alignment: .leading)
            if let value {
                Text(value)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(2)
            }
            custom
        }
    }

    @ViewBuilder
    private var whitelistBadge: some View {
        if let bot = matchedBot, bot.allowedUserIds.isEmpty {
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.Color.warningStrong)
                Text("전체 허용 (주의)")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.warningStrong)
            }
        } else {
            HStack(spacing: 3) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.Color.success)
                Text("접근 허가됨")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.success)
            }
        }
    }

    // MARK: - Action row

    private var actionRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            FlatButton("편집", icon: "pencil", variant: .secondary) {
                onEdit()
            }
            FlatButton(
                binding.activeWorkspaceId != nil ? "비활성화" : "활성화",
                icon: binding.activeWorkspaceId != nil ? "pause.circle" : "play.circle",
                variant: .ghost
            ) {
                onDisable()
            }
            Spacer()
        }
        .padding(.top, Theme.Spacing.xs)
    }

    // MARK: - Computed properties

    private var matchedBot: TelegramBotConfig? {
        appModel.preferences.telegramBots.first { $0.id == binding.botId }
    }

    private var botName: String {
        if let bot = matchedBot {
            return "@\(bot.username)"
        }
        return "알 수 없는 봇"
    }

    private var workspaceName: String {
        guard let wsId = binding.activeWorkspaceId else { return "—" }
        guard let ws = appModel.workspaces.first(where: { $0.id == wsId }) else {
            return wsId.uuidString.prefix(8).description
        }
        let shortPath = ws.directoryPath.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
        return "\(ws.name) (\(shortPath))"
    }

    // MARK: - Helpers

    private func loadLastActivity() {
        Task {
            let activities = await appModel.telegramRecentChatActivity()
            if let found = activities.first(where: { $0.0 == binding.chatId }) {
                lastActivity = found.1
            }
        }
    }

    private func relativeTime(_ date: Date) -> String {
        RelativeTime.format(date)
    }
}
