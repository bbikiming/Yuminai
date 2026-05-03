import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-086 Phase 4** — Multi-bot 관리 sheet.
///
/// 3개 섹션:
/// 1. **봇 목록**: 등록된 봇들 (이름/username/그룹/상태) + 추가/편집/삭제
/// 2. **그룹 관리**: 봇을 묶을 그룹 (응답 모드/budget override)
/// 3. **Chat ↔ Workspace 매핑**: 봇별 chat이 어떤 워크스페이스로 연결되는지
///
/// 사용 시나리오:
/// - 시나리오 A: 1봇 × N워크스페이스 (한 봇으로 여러 프로젝트 — chat별 workspace 다름)
/// - 시나리오 B: N봇 × M그룹 (팀별 봇 격리 + 그룹별 정책)
struct TelegramBotManagerSheet: View {
    @Environment(AppModel.self) private var appModel
    @State private var section: Section = .bots
    @State private var editingBotId: UUID? = nil
    @State private var editingGroupId: UUID? = nil
    @State private var editingBindingId: UUID? = nil
    @State private var showAddBot: Bool = false
    @State private var showAddGroup: Bool = false
    @State private var showAddBinding: Bool = false

    enum Section: String, CaseIterable, Identifiable {
        case bots = "봇 목록"
        case groups = "그룹"
        case bindings = "Chat ↔ Workspace"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .bots: return "person.crop.square.filled.and.at.rectangle"
            case .groups: return "rectangle.3.group.fill"
            case .bindings: return "link.circle.fill"
            }
        }
    }

    var body: some View {
        YuminaiSheet(width: 760, height: 620) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                segmentedNav
                Divider()
                contentArea
            }
            .padding(Theme.Spacing.xl)
        } footer: {
            HStack {
                Text(footerSummary)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                Spacer()
                FlatButton("닫기", variant: .primary) {
                    appModel.showTelegramBotManagerSheet = false
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "person.3.fill")
                    .foregroundStyle(Theme.Color.accent)
                    .accessibilityHidden(true)
                Text("Multi-Bot 관리")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
            }
            Text("여러 텔레그램 봇을 그룹으로 운영하거나, 한 봇으로 여러 워크스페이스를 오갈 수 있게 설정하세요.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var segmentedNav: some View {
        Picker("Section", selection: $section) {
            ForEach(Section.allCases) { sec in
                Label(sec.rawValue, systemImage: sec.icon).tag(sec)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var footerSummary: String {
        let bots = appModel.preferences.telegramBots.count
        let groups = appModel.preferences.telegramBotGroups.count
        let bindings = appModel.preferences.telegramBotChatBindings.count
        return "봇 \(bots)개 · 그룹 \(groups)개 · 매핑 \(bindings)개"
    }

    @ViewBuilder
    private var contentArea: some View {
        switch section {
        case .bots: botList
        case .groups: groupList
        case .bindings: bindingList
        }
    }

    // MARK: - 봇 목록

    private var botList: some View {
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
            BotEditSheet(existing: nil) { config in
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
            BotEditSheet(existing: bot) { config in
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
            Button("삭제", role: .destructive) {
                Task { await appModel.removeTelegramBot(bot.id) }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Color.danger)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    // MARK: - 그룹

    private var groupList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("봇 그룹")
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer()
                FlatButton("새 그룹", variant: .secondary) {
                    showAddGroup = true
                }
            }
            if appModel.preferences.telegramBotGroups.isEmpty {
                EmptyStateHint(
                    icon: "rectangle.3.group.fill",
                    title: "그룹이 없어요",
                    message: "그룹을 만들면 여러 봇에 공통 응답 모드/budget을 적용할 수 있어요."
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(appModel.preferences.telegramBotGroups) { group in
                            groupRow(group)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showAddGroup) {
            GroupEditSheet(existing: nil) { group in
                Task {
                    await appModel.addTelegramBotGroup(group)
                    showAddGroup = false
                }
            } onCancel: {
                showAddGroup = false
            }
        }
        .sheet(item: Binding(
            get: { editingGroupId.flatMap { id in appModel.preferences.telegramBotGroups.first { $0.id == id } } },
            set: { _ in editingGroupId = nil }
        )) { group in
            GroupEditSheet(existing: group) { updated in
                Task {
                    await appModel.updateTelegramBotGroup(updated)
                    editingGroupId = nil
                }
            } onCancel: {
                editingGroupId = nil
            }
        }
    }

    private func groupRow(_ group: TelegramBotGroup) -> some View {
        let memberCount = appModel.preferences.telegramBots.filter { $0.groupId == group.id }.count
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: group.iconName)
                .font(.system(size: 16))
                .foregroundStyle(Theme.Color.folderColor(for: group.colorName))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(group.displayName)
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Color.text)
                    Text("봇 \(memberCount)개")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
                if let mode = group.responseModeOverride {
                    Text("응답 모드 override: \(mode.displayName)")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                if group.budgetOverride != nil {
                    Text("Budget override 설정됨")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
            Spacer()
            Button("편집") { editingGroupId = group.id }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Color.accent)
            Button("삭제", role: .destructive) {
                Task { await appModel.removeTelegramBotGroup(group.id) }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Color.danger)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    // MARK: - Chat ↔ Workspace 매핑

    private var bindingList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Chat ↔ Workspace 매핑")
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer()
                FlatButton("매핑 추가", variant: .secondary) {
                    showAddBinding = true
                }
            }
            Text("같은 봇 안에서 chat별 다른 워크스페이스를 연결할 수 있어요. 사용자는 채팅창에서 `/switch` 명령으로 워크스페이스를 바꿀 수 있어요.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if appModel.preferences.telegramBotChatBindings.isEmpty {
                EmptyStateHint(
                    icon: "link.circle.fill",
                    title: "매핑이 없어요",
                    message: "Chat과 워크스페이스를 연결하면 봇 응답이 해당 워크스페이스로 자동 라우팅돼요."
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
            BindingEditSheet(
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
            BindingEditSheet(
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
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(bot?.displayName ?? "(삭제된 봇)")
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Color.text)
                    Text("Chat: \(binding.chatId)")
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
                    Text("워크스페이스 미연결")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.warning)
                }
                if !binding.allowedWorkspaceIds.isEmpty {
                    Text("허용: \(binding.allowedWorkspaceIds.count)개 워크스페이스")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
            }
            Spacer()
            Button("편집") { editingBindingId = binding.id }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Color.accent)
            Button("삭제", role: .destructive) {
                Task { await appModel.removeBotChatBinding(binding.id) }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Color.danger)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }
}

// MARK: - Bot edit sheet

private struct BotEditSheet: View {
    let existing: TelegramBotConfig?
    let onSave: (TelegramBotConfig) -> Void
    let onCancel: () -> Void

    @State private var displayName: String
    @State private var username: String
    @State private var keychainKey: String
    @State private var notes: String
    @State private var enabled: Bool
    @State private var allowedUserIdsText: String
    @State private var iconName: String
    @State private var colorName: String

    init(
        existing: TelegramBotConfig?,
        onSave: @escaping (TelegramBotConfig) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.existing = existing
        self.onSave = onSave
        self.onCancel = onCancel
        _displayName = State(initialValue: existing?.displayName ?? "")
        _username = State(initialValue: existing?.username ?? "")
        _keychainKey = State(initialValue: existing?.keychainKey ?? "telegram.bot.token")
        _notes = State(initialValue: existing?.notes ?? "")
        _enabled = State(initialValue: existing?.enabled ?? true)
        _allowedUserIdsText = State(initialValue: existing?.allowedUserIds.map(String.init).joined(separator: ", ") ?? "")
        _iconName = State(initialValue: existing?.iconName ?? "paperplane.circle.fill")
        _colorName = State(initialValue: existing?.colorName ?? "accent")
    }

    var body: some View {
        YuminaiSheet(width: 520, height: 480) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text(existing == nil ? "새 봇 추가" : "봇 편집")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
                Form {
                    Section {
                        TextField("표시 이름", text: $displayName)
                        TextField("Username (예: my_bot)", text: $username)
                            .autocorrectionDisabled()
                        TextField("Keychain key", text: $keychainKey)
                            .help("이 봇 token을 keychain에 어떤 key로 저장할지")
                            .autocorrectionDisabled()
                    } header: {
                        Text("기본")
                    }
                    Section {
                        Toggle("활성", isOn: $enabled)
                        TextField("허용 user IDs (콤마 구분)", text: $allowedUserIdsText)
                            .help("비어있으면 모든 사용자 허용 (위험)")
                            .autocorrectionDisabled()
                    } header: {
                        Text("권한")
                    }
                    Section {
                        TextField("아이콘 (SF Symbol)", text: $iconName)
                            .autocorrectionDisabled()
                        TextField("색상 (semantic name)", text: $colorName)
                            .autocorrectionDisabled()
                        TextField("메모 (선택)", text: $notes, axis: .vertical)
                            .lineLimit(2...4)
                    } header: {
                        Text("외형 + 메모")
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
                    let allowedIds = parseAllowedIds()
                    let config = TelegramBotConfig(
                        id: existing?.id ?? UUID(),
                        displayName: displayName.isEmpty ? "이름 없음" : displayName,
                        username: username,
                        keychainKey: keychainKey.isEmpty ? "telegram.bot.token" : keychainKey,
                        groupId: existing?.groupId,
                        allowedUserIds: allowedIds,
                        enabled: enabled,
                        iconName: iconName.isEmpty ? "paperplane.circle.fill" : iconName,
                        colorName: colorName.isEmpty ? "accent" : colorName,
                        notes: notes
                    )
                    onSave(config)
                }
            }
        }
    }

    private func parseAllowedIds() -> [Int64] {
        allowedUserIdsText
            .split(separator: ",")
            .compactMap { Int64($0.trimmingCharacters(in: .whitespaces)) }
    }
}

// MARK: - Group edit sheet

private struct GroupEditSheet: View {
    let existing: TelegramBotGroup?
    let onSave: (TelegramBotGroup) -> Void
    let onCancel: () -> Void

    @State private var displayName: String
    @State private var iconName: String
    @State private var colorName: String
    @State private var responseModeOverride: TelegramResponseMode?
    @State private var hasResponseModeOverride: Bool

    init(
        existing: TelegramBotGroup?,
        onSave: @escaping (TelegramBotGroup) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.existing = existing
        self.onSave = onSave
        self.onCancel = onCancel
        _displayName = State(initialValue: existing?.displayName ?? "")
        _iconName = State(initialValue: existing?.iconName ?? "folder.badge.person.crop")
        _colorName = State(initialValue: existing?.colorName ?? "accent")
        _responseModeOverride = State(initialValue: existing?.responseModeOverride)
        _hasResponseModeOverride = State(initialValue: existing?.responseModeOverride != nil)
    }

    var body: some View {
        YuminaiSheet(width: 520, height: 420) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text(existing == nil ? "새 그룹" : "그룹 편집")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
                Form {
                    Section {
                        TextField("표시 이름", text: $displayName)
                        TextField("아이콘 (SF Symbol)", text: $iconName)
                            .autocorrectionDisabled()
                        TextField("색상 (semantic name)", text: $colorName)
                            .autocorrectionDisabled()
                    } header: {
                        Text("기본")
                    }
                    Section {
                        Toggle("응답 모드 override", isOn: $hasResponseModeOverride)
                        if hasResponseModeOverride {
                            Picker("응답 모드", selection: Binding(
                                get: { responseModeOverride ?? .standard },
                                set: { responseModeOverride = $0 }
                            )) {
                                ForEach(TelegramResponseMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                        }
                    } header: {
                        Text("Override (선택)")
                    } footer: {
                        Text("그룹 안 모든 봇에 적용됩니다 (개별 봇 설정보다 우선).")
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
                    let group = TelegramBotGroup(
                        id: existing?.id ?? UUID(),
                        displayName: displayName.isEmpty ? "이름 없음" : displayName,
                        iconName: iconName.isEmpty ? "folder.badge.person.crop" : iconName,
                        colorName: colorName.isEmpty ? "accent" : colorName,
                        responseModeOverride: hasResponseModeOverride ? responseModeOverride : nil,
                        budgetOverride: existing?.budgetOverride,
                        sharedSkillIds: existing?.sharedSkillIds ?? []
                    )
                    onSave(group)
                }
            }
        }
    }
}

// MARK: - Binding edit sheet

private struct BindingEditSheet: View {
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
