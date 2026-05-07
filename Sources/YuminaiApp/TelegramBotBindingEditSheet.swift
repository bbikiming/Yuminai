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
                Text(existing == nil ? "새 연결 설정" : "연결 설정 편집")
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
                        TextField("대화방 번호", text: $chatIdText)
                            .autocorrectionDisabled()
                            .help("텔레그램 그룹이면 음수 (예: -100123456789), 1:1 대화면 양수 (예: 123456789)")
                        TextField("별명 (선택)", text: $nickname)
                    } header: {
                        Text("대화방 정보")
                    }
                    Section {
                        Picker("어느 폴더에서 작업할지", selection: $activeWorkspaceId) {
                            Text("미연결").tag(UUID?.none)
                            ForEach(workspaces) { ws in
                                Text(ws.name).tag(UUID?.some(ws.id))
                            }
                        }
                    } header: {
                        Text("작업 폴더")
                    } footer: {
                        Text("이 대화방에서 들어온 메시지는 선택한 작업 폴더로 자동 전달됩니다.")
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
                        Text("/switch 허용 작업 폴더 (선택)")
                    } footer: {
                        Text("비워두면 모든 작업 폴더로 /switch 가능. 선택 시 해당 폴더만 허용.")
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
                .disabled(!isFormValid)
            }
        }
        .overlay(alignment: .topTrailing) {
            SheetCloseButton(action: onCancel)
        }
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        TelegramBotValidator.isBindingFormValid(
            selectedBotId: selectedBotId,
            chatIdText: chatIdText
        )
    }
}
