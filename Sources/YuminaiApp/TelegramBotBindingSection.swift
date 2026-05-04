import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-086 Phase 4** — Chat ↔ Workspace 매핑 섹션 (매핑 추가/편집/삭제).
struct TelegramBotBindingSection: View {
    @Environment(AppModel.self) private var appModel
    @State private var showAddBinding: Bool = false
    @State private var editingBindingId: UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("대화방 → 작업 폴더 연결")
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer()
                FlatButton("연결 추가", variant: .secondary) {
                    showAddBinding = true
                }
            }
            Text("같은 봇 안에서 대화방별 다른 작업 폴더를 연결할 수 있어요. `/switch` 명령으로 작업 폴더를 바꿀 수 있어요.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if appModel.preferences.telegramBotChatBindings.isEmpty {
                EmptyStateHint(
                    icon: "link.circle.fill",
                    title: "연결이 없어요",
                    message: "대화방과 작업 폴더를 연결하면 봇 응답이 해당 작업 폴더로 자동으로 전달돼요."
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(appModel.preferences.telegramBotChatBindings) { binding in
                            bindingRow(binding)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showAddBinding) {
            TelegramBotBindingEditSheet(
                existing: nil,
                bots: appModel.preferences.telegramBots,
                workspaces: appModel.workspaces
            ) { binding in
                Task {
                    await appModel.upsertBotChatBinding(binding)
                    showAddBinding = false
                }
            } onCancel: {
                showAddBinding = false
            }
        }
        .sheet(item: Binding(
            get: { editingBindingId.flatMap { id in appModel.preferences.telegramBotChatBindings.first { $0.id == id } } },
            set: { _ in editingBindingId = nil }
        )) { binding in
            TelegramBotBindingEditSheet(
                existing: binding,
                bots: appModel.preferences.telegramBots,
                workspaces: appModel.workspaces
            ) { updated in
                Task {
                    await appModel.upsertBotChatBinding(updated)
                    editingBindingId = nil
                }
            } onCancel: {
                editingBindingId = nil
            }
        }
    }

    private func bindingRow(_ binding: BotChatBinding) -> some View {
        let bot = appModel.preferences.telegramBots.first { $0.id == binding.botId }
        let workspace = binding.activeWorkspaceId.flatMap { id in
            appModel.workspaces.first { $0.id == id }
        }
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "link")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Color.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(bot?.displayName ?? "(삭제된 봇)")
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Color.text)
                    Text("대화방 번호: \(binding.chatId)")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                if !binding.nickname.isEmpty {
                    Text(binding.nickname)
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
                if let workspace {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Color.textTertiary)
                        Text(workspace.name)
                            .font(Theme.Typography.small)
                            .foregroundStyle(Theme.Color.text)
                    }
                } else {
                    Text("작업 폴더 미연결")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.warning)
                }
                if !binding.allowedWorkspaceIds.isEmpty {
                    Text("허용: \(binding.allowedWorkspaceIds.count)개 작업 폴더")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
            }
            Spacer()
            Button("편집") { editingBindingId = binding.id }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Color.accent)
                .accessibilityLabel("Chat \(binding.chatId) 매핑 편집")
            Button("삭제", role: .destructive) {
                Task { await appModel.removeBotChatBinding(binding.id) }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Color.danger)
            .accessibilityLabel("Chat \(binding.chatId) 매핑 삭제")
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .accessibilityElement(children: .contain)
    }
}
