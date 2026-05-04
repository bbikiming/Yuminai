import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-086 Phase 4 / ADR-101 / ADR-102** — 대화방 → 작업 폴더 연결 섹션.
///
/// ADR-102: ScrollView+VStack → LazyVStack 카드 (nested scroll 회피, 다른 섹션과 일관 스타일).
struct TelegramBotBindingSection: View {
    @Environment(AppModel.self) private var appModel
    @State private var showAddBinding: Bool = false
    @State private var editingBindingId: UUID? = nil
    @State private var confirmDeleteBindingId: UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("대화방 → 작업 폴더 연결")
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer()
                FlatButton("연결 추가", icon: "plus", variant: .secondary) {
                    showAddBinding = true
                }
            }
            Text("같은 봇 안에서 대화방별 다른 작업 폴더를 연결할 수 있어요. /switch 명령으로 작업 폴더를 바꿀 수 있어요.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if appModel.preferences.telegramBotChatBindings.isEmpty {
                EmptyStateHint(
                    icon: "link.circle.fill",
                    title: "연결이 없어요",
                    message: "대화방과 작업 폴더를 연결하면 봇 응답이 해당 작업 폴더로 자동으로 전달돼요."
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.lg)
            } else {
                LazyVStack(spacing: Theme.Spacing.sm) {
                    ForEach(appModel.preferences.telegramBotChatBindings) { binding in
                        bindingCard(binding)
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
        .confirmationDialog(
            "이 연결을 삭제할까요?",
            isPresented: Binding(
                get: { confirmDeleteBindingId != nil },
                set: { if !$0 { confirmDeleteBindingId = nil } }
            ),
            titleVisibility: .visible,
            presenting: confirmDeleteBindingId
        ) { id in
            Button("삭제", role: .destructive) {
                Task { await appModel.removeBotChatBinding(id) }
                confirmDeleteBindingId = nil
            }
            Button("취소", role: .cancel) {
                confirmDeleteBindingId = nil
            }
        } message: { _ in
            Text("이 대화방과 작업 폴더의 연결만 사라집니다. 봇과 작업 폴더 자체는 유지돼요.")
        }
    }

    private func bindingCard(_ binding: BotChatBinding) -> some View {
        let bot = appModel.preferences.telegramBots.first { $0.id == binding.botId }
        let workspace = binding.activeWorkspaceId.flatMap { id in
            appModel.workspaces.first { $0.id == id }
        }
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .center, spacing: Theme.Spacing.sm + 2) {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.Color.accent)
                    .frame(width: 32, height: 32)
                    .background(Theme.Color.accentMuted)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(bot?.displayName ?? "(삭제된 봇)")
                            .font(Theme.Typography.body.weight(.semibold))
                            .foregroundStyle(bot == nil ? Theme.Color.warning : Theme.Color.text)
                        ChatTypeBadge(chatId: binding.chatId)
                    }
                    HStack(spacing: 6) {
                        Text("대화방: \(binding.chatId)")
                            .font(Theme.Typography.small)
                            .foregroundStyle(Theme.Color.textSecondary)
                            .textSelection(.enabled)
                        if let workspace {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.Color.textTertiary)
                            Text(workspace.name)
                                .font(Theme.Typography.small)
                                .foregroundStyle(Theme.Color.text)
                        } else {
                            Text("· 작업 폴더 미연결")
                                .font(Theme.Typography.small)
                                .foregroundStyle(Theme.Color.warning)
                        }
                    }
                }

                Spacer()

                HStack(spacing: 4) {
                    Button {
                        editingBindingId = binding.id
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 28, height: 28)
                            .foregroundStyle(Theme.Color.accent)
                            .background(Theme.Color.accentMuted)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    }
                    .buttonStyle(.plain)
                    .help("이 연결 편집")
                    .accessibilityLabel("대화방 \(binding.chatId) 연결 편집")

                    Button {
                        confirmDeleteBindingId = binding.id
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 28, height: 28)
                            .foregroundStyle(Theme.Color.danger)
                            .background(Theme.Color.danger.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    }
                    .buttonStyle(.plain)
                    .help("이 연결 삭제")
                    .accessibilityLabel("대화방 \(binding.chatId) 연결 삭제")
                }
            }

            if !binding.nickname.isEmpty || !binding.allowedWorkspaceIds.isEmpty {
                ExpandableInfoSection(label: "자세히 보기", labelIcon: "info.circle") {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        if !binding.nickname.isEmpty {
                            infoLine(label: "별명", value: binding.nickname)
                        }
                        if !binding.allowedWorkspaceIds.isEmpty {
                            infoLine(
                                label: "전환 가능한 작업 폴더",
                                value: "\(binding.allowedWorkspaceIds.count)개 지정"
                            )
                        }
                    }
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Theme.Color.borderSubtle, lineWidth: 0.5)
        )
        .contextMenu {
            Button {
                editingBindingId = binding.id
            } label: {
                Label("편집", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                confirmDeleteBindingId = binding.id
            } label: {
                Label("삭제", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func infoLine(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text("\(label):")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
            Text(value)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }
}
