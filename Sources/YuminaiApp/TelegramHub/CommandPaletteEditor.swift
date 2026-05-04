import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-094 Phase 3** — Commands 탭 본문. BotFather에 등록할 커맨드 목록 편집 + 동기화.
///
/// ## 디자인 (ADR-092 §4.5)
/// - LazyVStack of CommandRow
/// - [+ New Command] 버튼 → `CommandEditSheet`
/// - [Sync to BotFather] → `appModel.syncTelegramCommandsToBotFather()` 호출
/// - 동기화 결과 banner ("✅ 7개 명령 등록됨" / "❌ 실패: ...")
struct CommandPaletteEditor: View {
    @Environment(AppModel.self) private var appModel
    @State private var showAddSheet: Bool = false
    @State private var editingCommand: TelegramCommand? = nil
    @State private var syncResult: SyncBannerState? = nil
    @State private var isSyncing: Bool = false

    enum SyncBannerState {
        case success(Int)
        case failure(String)

        var message: String {
            switch self {
            case .success(let count): return "✅ \(count)개 명령 등록됨"
            case .failure(let err): return "❌ 실패: \(err)"
            }
        }

        var isSuccess: Bool {
            if case .success = self { return true }
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            toolbar

            if let banner = syncResult {
                syncBanner(banner)
            }

            commandList
        }
        .sheet(isPresented: $showAddSheet) {
            CommandEditSheet(existing: nil) { newCmd in
                Task { await appModel.addTelegramCommand(newCmd) }
                showAddSheet = false
            } onCancel: {
                showAddSheet = false
            }
        }
        .sheet(item: $editingCommand) { cmd in
            CommandEditSheet(existing: cmd) { updated in
                Task { await appModel.updateTelegramCommand(updated) }
                editingCommand = nil
            } onCancel: {
                editingCommand = nil
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Text("Commands")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Color.text)
            Spacer()
            FlatButton("새 커맨드", icon: "plus", variant: .secondary) {
                showAddSheet = true
            }
        }
    }

    // MARK: - Sync Banner

    private func syncBanner(_ state: SyncBannerState) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(state.message)
                .font(Theme.Typography.small)
                .foregroundStyle(state.isSuccess ? Theme.Color.accent : .red)
            Spacer()
            Button {
                withAnimation { syncResult = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            state.isSuccess
            ? Theme.Color.accent.opacity(0.08)
            : Color.red.opacity(0.08)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Command List

    private var commandList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if appModel.preferences.telegramCommands.isEmpty {
                emptyState
            } else {
                commandRows
            }

            Divider().padding(.vertical, Theme.Spacing.sm)

            syncButton
        }
    }

    private var commandRows: some View {
        LazyVStack(alignment: .leading, spacing: 1) {
            ForEach(appModel.preferences.telegramCommands) { cmd in
                CommandRow(
                    command: cmd,
                    onEdit: { editingCommand = cmd },
                    onToggleEnabled: { newValue in
                        Task {
                            let updated = TelegramCommand(
                                id: cmd.id,
                                trigger: cmd.trigger,
                                description: cmd.description,
                                permission: cmd.permission,
                                requiresHITL: cmd.requiresHITL,
                                enabled: newValue
                            )
                            await appModel.updateTelegramCommand(updated)
                        }
                    },
                    onDelete: {
                        Task { await appModel.removeTelegramCommand(id: cmd.id) }
                    }
                )
                if cmd.id != appModel.preferences.telegramCommands.last?.id {
                    Divider().padding(.leading, Theme.Spacing.md)
                }
            }
        }
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Theme.Color.border, lineWidth: 0.5)
        )
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.Color.textTertiary)
                Text("커맨드 없음. [새 커맨드]로 추가하세요.")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            .padding(.vertical, Theme.Spacing.xl)
            Spacer()
        }
    }

    private var syncButton: some View {
        HStack {
            Spacer()
            if isSyncing {
                HStack(spacing: Theme.Spacing.xs) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("BotFather 동기화 중...")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            } else {
                FlatButton("BotFather에 동기화", icon: "arrow.triangle.2.circlepath", variant: .primary) {
                    performSync()
                }
            }
        }
    }

    // MARK: - Sync action

    private func performSync() {
        isSyncing = true
        withAnimation { syncResult = nil }
        Task {
            let syncOutcome = await appModel.syncTelegramCommandsToBotFather()
            await MainActor.run {
                isSyncing = false
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    switch syncOutcome {
                    case .success(let count):
                        syncResult = .success(count)
                    case .failure(let error):
                        syncResult = .failure(error.localizedDescription)
                    }
                }
            }
        }
    }
}

// MARK: - CommandRow

private struct CommandRow: View {
    let command: TelegramCommand
    let onEdit: () -> Void
    let onToggleEnabled: (Bool) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Trigger
            Text(command.trigger)
                .font(Theme.Typography.codeBlock)
                .foregroundStyle(command.enabled ? Theme.Color.accent : Theme.Color.textTertiary)
                .frame(width: 110, alignment: .leading)

            // Description
            Text(command.description)
                .font(Theme.Typography.small)
                .foregroundStyle(command.enabled ? Theme.Color.text : Theme.Color.textTertiary)
                .lineLimit(1)

            Spacer()

            // Permission badge
            Text(command.permission.displayLabel)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Theme.Color.border, lineWidth: 0.5)
                )

            // HITL badge
            if command.requiresHITL {
                Text("HITL")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            // Enabled toggle
            Toggle("", isOn: Binding(
                get: { command.enabled },
                set: { onToggleEnabled($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .scaleEffect(0.8)

            // Edit button
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .buttonStyle(.plain)
            .help("편집")

            // Delete button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            .buttonStyle(.plain)
            .help("삭제")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .contentShape(Rectangle())
    }
}
