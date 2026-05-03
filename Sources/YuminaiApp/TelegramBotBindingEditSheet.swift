import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-086 Phase 4** — Chat ↔ Workspace 매핑 편집/추가 sheet.
struct TelegramBotBindingEditSheet: View {
    let existing: BotChatBinding?
    let bots: [TelegramBotConfig]
    let workspaces: [Workspace]
    let onSave: (BotChatBinding) -> Void
    let onCancel: () -> Void

    @State private var selectedBotId: UUID?
    @State private var chatIdText: String
    @State private var nickname: String
    @State private var activeWorkspaceId: UUID?
    @State private var allowedWorkspaceIds: Set<UUID>

    init(
        existing: BotChatBinding?,
        bots: [TelegramBotConfig],
        workspaces: [Workspace],
        onSave: @escaping (BotChatBinding) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.existing = existing
        self.bots = bots
        self.workspaces = workspaces
        self.onSave = onSave
        self.onCancel = onCancel
        _selectedBotId = State(initialValue: existing?.botId ?? bots.first?.id)
        _chatIdText = State(initialValue: existing.map { String($0.chatId) } ?? "")
        _nickname = State(initialValue: existing?.nickname ?? "")
        _activeWorkspaceId = State(initialValue: existing?.activeWorkspaceId)
        _allowedWorkspaceIds = State(initialValue: existing?.allowedWorkspaceIds ?? [])
    }

    var body: some View {
        YuminaiSheet(width: 540, height: 520) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text(existing == nil ? "새 매핑" : "매핑 편집")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
                Form {
                    Section {
                        Picker("봇", selection: $selectedBotId) {
                            Text("선택 안 함").tag(UUID?.none)
                            ForEach(bots) { bot in
                                Text(bot.displayName).tag(UUID?.some(bot.id))
                            }
                        }
                        TextField("Chat ID", text: $chatIdText)
                            .autocorrectionDisabled()
                        TextField("Nickname (선택)", text: $nickname)
                    } header: {
                        Text("Source")
                    }
                    Section {
                        Picker("활성 워크스페이스", selection: $activeWorkspaceId) {
                            Text("미연결").tag(UUID?.none)
                            ForEach(workspaces) { ws in
                                Text(ws.name).tag(UUID?.some(ws.id))
                            }
                        }
                    } header: {
                        Text("Workspace")
                    } footer: {
                        Text("이 chat에서 들어온 메시지는 활성 워크스페이스로 라우팅됩니다.")
                            .font(Theme.Typography.micro)
                    }
                    Section {
                        ForEach(workspaces) { ws in
                            Toggle(ws.name, isOn: Binding(
                                get: { allowedWorkspaceIds.contains(ws.id) },
                                set: { isOn in
                                    if isOn { allowedWorkspaceIds.insert(ws.id) }
                                    else { allowedWorkspaceIds.remove(ws.id) }
                                }
                            ))
                        }
                    } header: {
                        Text("/switch 허용 목록 (선택)")
                    } footer: {
                        Text("비어있으면 모든 워크스페이스로 /switch 가능. 제한하면 목록만 허용.")
                            .font(Theme.Typography.micro)
                    }
                }
                .formStyle(.grouped)
            }
            .padding(Theme.Spacing.lg)
        } footer: {
            HStack {
                Spacer()
                FlatButton("취소", variant: .secondary, action: onCancel)
                FlatButton("저장", variant: .primary) {
                    guard let botId = selectedBotId, let chatId = Int64(chatIdText.trimmingCharacters(in: .whitespaces)) else {
                        return
                    }
                    let binding = BotChatBinding(
                        id: existing?.id ?? UUID(),
                        botId: botId,
                        chatId: chatId,
                        activeWorkspaceId: activeWorkspaceId,
                        allowedWorkspaceIds: allowedWorkspaceIds,
                        nickname: nickname
                    )
                    onSave(binding)
                }
                .disabled(selectedBotId == nil || Int64(chatIdText.trimmingCharacters(in: .whitespaces)) == nil)
            }
        }
    }
}
