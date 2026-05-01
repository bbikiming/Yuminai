import SwiftUI
import YuminaiCore
import YuminaiUI

/// 루트 view v3 + 반응형.
///
/// Layout 규칙: `Theme.Layout.mode(for:)` (LayoutMode enum). 명세: `docs/design/60_UI_DESIGN_SPEC.md`.
struct RootView: View {
    @Environment(AppModel.self) private var appModel

    /// 사용자가 마지막으로 toggle한 상태 — 영속.
    @AppStorage("yuminai.sidebar.userVisible") private var sidebarUserVisible: Bool = true
    @AppStorage("yuminai.inspector.userVisible") private var inspectorUserVisible: Bool = false

    /// compact 모드에서 overlay popup 표시 여부 (영속 X).
    @State private var sidebarOverlayShown: Bool = false

    /// 윈도우 너비 추적.
    @State private var windowSize: CGSize = .zero

    var layoutMode: LayoutMode { Theme.Layout.mode(for: windowSize.width) }

    /// inline sidebar가 보이는지 (overlay 모드는 별개).
    var sidebarInlineVisible: Bool {
        !layoutMode.sidebarIsOverlay && sidebarUserVisible
    }

    /// inspector가 보이는지 (mode가 허용해야 함).
    var inspectorVisible: Bool {
        layoutMode.allowsInspector && inspectorUserVisible
    }

    var body: some View {
        @Bindable var bindable = appModel

        GeometryReader { geo in
            ZStack(alignment: .leading) {
                mainLayer
                if layoutMode.sidebarIsOverlay && sidebarOverlayShown {
                    overlayBackdrop
                    overlaySidebar
                }
                quickSwitchHotkeys  // ⌘1~9 invisible buttons
                helpHotkey  // ⌘? invisible
            }
            .onAppear {
                windowSize = geo.size
                appModel.showInspector = inspectorVisible  // legacy sync
            }
            .onChange(of: geo.size) { _, newSize in
                handleSizeChange(newSize)
            }
        }
        .frame(minWidth: Theme.Layout.minWindowWidth, minHeight: Theme.Layout.minWindowHeight)
        .background(Theme.Color.bg)
        .sheet(isPresented: $bindable.showCreateWorkspaceSheet) {
            CreateWorkspaceSheet(
                onCreate: { ws in Task { await appModel.createWorkspace(ws) } },
                onCancel: { appModel.showCreateWorkspaceSheet = false }
            )
        }
        .sheet(isPresented: $bindable.showUsageDashboard) {
            UsageDashboard(
                currentSessionUsage: appModel.currentSessionUsage,
                allTimeUsage: appModel.allTimeUsage,
                activeModel: appModel.activeSettings.model,
                onClose: { appModel.showUsageDashboard = false }
            )
        }
        .sheet(isPresented: $bindable.showDisambigSheet) {
            WikiDisambiguationSheet(
                originalName: appModel.disambigOriginalName,
                candidates: appModel.disambigCandidates,
                onSelect: { path in Task { await appModel.selectDisambigCandidate(path) } },
                onCancel: { appModel.showDisambigSheet = false }
            )
        }
        .sheet(isPresented: $bindable.showCreateNoteSheet) {
            CreateNoteSheet(
                onCreate: { filename, title, folder in
                    Task { await appModel.createNote(filename: filename, title: title, folder: folder) }
                },
                onCancel: { appModel.showCreateNoteSheet = false }
            )
        }
        .sheet(isPresented: $bindable.showShortcutHelp) {
            ShortcutHelpSheet(onClose: { appModel.showShortcutHelp = false })
        }
        .sheet(item: $bindable.renameSheetPane) { pane in
            PaneRenameSheet(
                pane: pane,
                onApply: { newName in
                    appModel.renamePane(pane.id, to: newName)
                    appModel.renameSheetPane = nil
                },
                onCancel: { appModel.renameSheetPane = nil }
            )
        }
        .sheet(isPresented: $bindable.showDeliverySheet) {
            if let id = appModel.deliverySheetTargetWorkspaceId,
               let ws = appModel.workspaces.first(where: { $0.id == id }) {
                WorkspaceDeliverySheet(
                    workspaceName: ws.name,
                    draft: ws.deliveryConfig,
                    onApply: { config in
                        Task {
                            await appModel.updateDeliveryConfig(config)
                            appModel.showDeliverySheet = false
                        }
                    },
                    onCancel: { appModel.showDeliverySheet = false }
                )
            } else {
                Text("워크스페이스를 찾을 수 없어요")
                    .padding()
            }
        }
        .alert(
            "잠깐, 문제가 생겼어요",
            isPresented: Binding(
                get: { appModel.error != nil },
                set: { if !$0 { appModel.error = nil } }
            ),
            presenting: appModel.error
        ) { _ in
            Button("알겠어요") { appModel.error = nil }
        } message: { error in
            Text(error)
        }
        .onChange(of: appModel.selectedWorkspaceId) { _, newValue in
            Task { await appModel.selectWorkspace(newValue) }
        }
    }

    // MARK: - Layers

    private var mainLayer: some View {
        @Bindable var bindable = appModel

        return HStack(spacing: 0) {
            if sidebarInlineVisible {
                sidebar
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            ChatPane(
                onToggleSidebar: toggleSidebar,
                onToggleInspector: toggleInspector,
                inspectorAllowed: layoutMode.allowsInspector,
                inspectorVisible: inspectorVisible,
                layoutModeBadge: layoutModeBadge
            )

            if inspectorVisible {
                InspectorPanel(
                    tab: $bindable.inspectorTab,
                    usage: appModel.currentSessionUsage,
                    activeSettings: appModel.activeSettings,
                    workspacePath: currentWorkspacePath,
                    recentTools: recentToolNames,
                    vaultConfigured: appModel.isVaultConfigured,
                    vaultRoot: appModel.vaultRootURL,
                    vaultTree: appModel.vaultTree,
                    noteSearchQuery: Binding(
                        get: { appModel.noteSearchQuery },
                        set: { appModel.updateSearchQuery($0) }
                    ),
                    fullTextEnabled: Binding(
                        get: { appModel.noteFullTextEnabled },
                        set: { appModel.toggleFullTextSearch($0) }
                    ),
                    fullTextHits: appModel.noteFullTextHits,
                    selectedNote: appModel.selectedNote,
                    isEditing: appModel.isEditingNote,
                    editingDraft: $bindable.editingDraft,
                    isDirty: appModel.noteIsDirty,
                    externalChangeDetected: appModel.externalChangeDetected,
                    splitMode: $bindable.editorSplitMode,
                    favoriteNotePaths: appModel.favoriteNotePaths,
                    recentNotePaths: appModel.recentNotePaths,
                    onToggleFavorite: { path in appModel.toggleFavorite(path) },
                    onCreateNote: { appModel.showCreateNoteSheet = true },
                    onDeleteNote: { path in Task { await appModel.deleteNote(at: path) } },
                    noteResolver: { name in
                        AppModel.notePreviewBody(name: name, vaultRoot: appModel.vaultRootURL)
                    },
                    onSelectNote: { path in Task { await appModel.selectNote(at: path) } },
                    onClearSelectedNote: { appModel.clearSelectedNote() },
                    onOpenInObsidian: { appModel.openCurrentNoteInObsidian() },
                    onOpenSettings: openAppSettings,
                    onWikiLink: { name in Task { await appModel.openNoteByName(name) } },
                    onStartEditing: { appModel.startEditingNote() },
                    onSave: { Task { await appModel.saveNote() } },
                    onDiscardEdits: { appModel.discardEdits() },
                    onReloadNote: { Task { await appModel.reloadNoteFromDisk() } },
                    pendingChanges: appModel.pendingChanges,
                    pendingDiff: appModel.pendingDiff,
                    onAcceptAllChanges: { Task { await appModel.acceptAllChanges() } },
                    onRejectAllChanges: { Task { await appModel.rejectAllChanges() } },
                    onRejectChange: { file in Task { await appModel.rejectPaths([file.path]) } },
                    onOpenChangeInEditor: { file in appModel.openFileInExternalEditor(file.path) },
                    readChangedFile: { file in appModel.readWorkspaceFile(file.path) },
                    onSaveChangedFile: { file, contents in appModel.writeWorkspaceFile(file.path, contents: contents) },
                    deliveryResults: appModel.deliveryResults,
                    isDeliveryRunning: appModel.isDeliveryRunning,
                    deliveryConfig: appModel.currentWorkspace?.deliveryConfig ?? .disabled,
                    onRunBuild: { Task { await appModel.runDelivery(kind: .build) } },
                    onRunTest: { Task { await appModel.runDelivery(kind: .test) } },
                    onRunLint: { Task { await appModel.runDelivery(kind: .lint) } },
                    onClearDelivery: { appModel.clearDeliveryResults() },
                    onConfigureDelivery: {
                        appModel.deliverySheetTargetWorkspaceId = appModel.selectedWorkspaceId
                        appModel.showDeliverySheet = true
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    private var sidebar: some View {
        SidebarView(
            workspaces: appModel.workspaces,
            selectedId: Binding(
                get: { appModel.selectedWorkspaceId },
                set: { appModel.selectedWorkspaceId = $0 }
            ),
            telegramBoundId: appModel.preferences.telegramBoundWorkspaceId,
            telegramAvailable: appModel.preferences.telegramEnabled
                && appModel.telegramTokenStatus == .set
                && appModel.preferences.telegramChatId != nil,
            onCreate: {
                appModel.showCreateWorkspaceSheet = true
                if layoutMode.sidebarIsOverlay { sidebarOverlayShown = false }
            },
            onDelete: { ws in Task { await appModel.deleteWorkspace(ws) } },
            onCollapse: toggleSidebar,
            onSearch: { /* ⌘P palette — v0.2 */ },
            onOpenSettings: openAppSettings,
            onToggleTelegramBind: { ws in
                Task {
                    let isBound = appModel.preferences.telegramBoundWorkspaceId == ws.id
                    await appModel.bindTelegramWorkspace(isBound ? nil : ws.id)
                }
            },
            onConfigureDelivery: { ws in
                appModel.deliverySheetTargetWorkspaceId = ws.id
                appModel.showDeliverySheet = true
            },
            userName: "yuminai",
            updateAvailable: false
        )
    }

    private var overlayBackdrop: some View {
        Color.black.opacity(0.35)
            .ignoresSafeArea()
            .transition(.opacity)
            .onTapGesture {
                withAnimation(Theme.Animation.panelToggle) {
                    sidebarOverlayShown = false
                }
            }
    }

    private var overlaySidebar: some View {
        sidebar
            .background(Theme.Color.bgSidebar)
            .shadow(color: .black.opacity(0.4), radius: 8, x: 4, y: 0)
            .transition(.move(edge: .leading))
    }

    /// ⌘? — 단축키 도움말 sheet.
    private var helpHotkey: some View {
        Button("") { appModel.showShortcutHelp = true }
            .keyboardShortcut("/", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }

    /// ⌘1~9: 워크스페이스 빠른 전환. invisible button을 layout에 두면 macOS가 단축키 처리.
    private var quickSwitchHotkeys: some View {
        ZStack {
            ForEach(0..<min(9, appModel.workspaces.count), id: \.self) { idx in
                Button("") {
                    appModel.selectedWorkspaceId = appModel.workspaces[idx].id
                }
                .keyboardShortcut(KeyEquivalent(Character("\(idx + 1)")), modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
        }
        .frame(width: 0, height: 0)
    }

    /// compact/medium 모드에서 toolbar에 작게 표시.
    private var layoutModeBadge: String? {
        switch layoutMode {
        case .compact: return "compact"
        case .medium: return "medium"
        case .regular, .wide: return nil
        }
    }

    // MARK: - Actions

    private func toggleSidebar() {
        withAnimation(Theme.Animation.panelToggle) {
            if layoutMode.sidebarIsOverlay {
                sidebarOverlayShown.toggle()
            } else {
                sidebarUserVisible.toggle()
            }
        }
    }

    private func toggleInspector() {
        guard layoutMode.allowsInspector else { return }
        withAnimation(Theme.Animation.panelToggle) {
            inspectorUserVisible.toggle()
            appModel.showInspector = inspectorUserVisible
        }
    }

    private func handleSizeChange(_ newSize: CGSize) {
        let oldMode = Theme.Layout.mode(for: windowSize.width)
        windowSize = newSize
        let newMode = Theme.Layout.mode(for: newSize.width)

        if oldMode != newMode {
            // mode 변경 시 정리:
            // - overlay 모드 빠져나오면 overlay popup 자동 닫음
            if !newMode.sidebarIsOverlay && sidebarOverlayShown {
                sidebarOverlayShown = false
            }
            // - inspector 자동 sync (effective 변경)
            appModel.showInspector = newMode.allowsInspector && inspectorUserVisible
        }
    }

    @Environment(\.openSettings) private var openSettingsAction

    private func openAppSettings() {
        openSettingsAction()
    }

    private var currentWorkspacePath: String? {
        appModel.workspaces.first { $0.id == appModel.selectedWorkspaceId }?.directoryPath
    }

    private var recentToolNames: [String] {
        appModel.messages
            .filter { $0.role == .tool }
            .map(\.content)
            .map { String($0.prefix(80)) }
    }
}

/// Toolbar / ChatView / StatusBar / Composer.
struct ChatPane: View {
    @Environment(AppModel.self) private var appModel
    let onToggleSidebar: () -> Void
    let onToggleInspector: () -> Void
    let inspectorAllowed: Bool
    let inspectorVisible: Bool
    let layoutModeBadge: String?

    var body: some View {
        @Bindable var bindable = appModel

        VStack(spacing: 0) {
            ChatToolbar(
                workspaceName: currentWorkspaceName,
                workspacePath: currentWorkspacePath,
                workspaces: appModel.workspaces,
                selectedWorkspaceId: appModel.selectedWorkspaceId,
                isStreaming: appModel.isStreaming,
                inspectorVisible: inspectorVisible,
                inspectorAllowed: inspectorAllowed,
                layoutBadge: layoutModeBadge,
                activeAgent: currentAgentKind,
                codexAvailable: appModel.codexAvailable,
                terminalVisible: appModel.showTerminalPane,
                previewVisible: appModel.showPreviewPane,
                commandsVisible: appModel.showCommandRunnerPane,
                onToggleSidebar: onToggleSidebar,
                onToggleInspector: onToggleInspector,
                onToggleTerminal: { appModel.showTerminalPane.toggle() },
                onTogglePreview: { appModel.showPreviewPane.toggle() },
                onToggleCommands: { appModel.showCommandRunnerPane.toggle() },
                onShowDashboard: { appModel.showUsageDashboard = true },
                onShowShortcutHelp: { appModel.showShortcutHelp = true },
                onSelectWorkspace: { id in appModel.selectedWorkspaceId = id },
                onCreateWorkspace: { appModel.showCreateWorkspaceSheet = true },
                onSelectAgent: { kind in
                    Task { await appModel.setActiveAgentKind(kind) }
                }
            )

            if appModel.selectedWorkspaceId == nil {
                EmptyWorkspaceView()
            } else {
                if appModel.agentChainActive {
                    HStack(spacing: 6) {
                        Image(systemName: "link.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Color.accent)
                        Text("Agent chain 활성")
                            .font(Theme.Typography.small.weight(.medium))
                            .foregroundStyle(Theme.Color.text)
                        Text("hop \(appModel.agentChainHops) / \(appModel.preferences.agentChainMaxHops)")
                            .font(Theme.Typography.monoSmall)
                            .foregroundStyle(Theme.Color.textSecondary)
                        Spacer()
                        Button {
                            appModel.agentChainHops = 0
                            appModel.agentChainVisited.removeAll()
                            appModel.cancelStream()
                        } label: {
                            Text("중단")
                                .font(Theme.Typography.small)
                        }
                        .buttonStyle(.plain)
                        .help("chain 중단 + 현재 응답 cancel")
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(Theme.Color.accentMuted)
                    .overlay(alignment: .bottom) { FlatHDivider() }
                }
                if !appModel.agentPanes.isEmpty {
                    PaneTabBar(
                        panes: appModel.agentPanes,
                        activePaneId: appModel.activePaneId,
                        codexAvailable: appModel.codexAvailable,
                        splitMode: $bindable.paneSplitMode,
                        onSelect: { id in Task { await appModel.setActivePane(id) } },
                        onClose: { id in Task { await appModel.removePane(id) } },
                        onAdd: { kind in Task { await appModel.addPane(agentKind: kind) } },
                        onRename: { pane in appModel.renameSheetPane = pane },
                        onPromoteToPrimary: { id in appModel.promotePaneToPrimary(id) }
                    )
                }
                if appModel.showPreviewPane {
                    HSplitView {
                        chatColumnWithOptionalTerminal
                            .frame(minWidth: 360)
                        previewPaneSection
                            .frame(minWidth: 280)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    chatColumnWithOptionalTerminal
                        .frame(maxHeight: .infinity)
                }

                ChatStatusBar(
                    usage: appModel.currentSessionUsage,
                    contextWindow: appModel.currentContextWindow,
                    isStreaming: appModel.isStreaming
                )

                Composer(
                    text: $bindable.inputText,
                    model: $bindable.activeSettings.model,
                    permissionMode: $bindable.activeSettings.permissionMode,
                    effortLevel: $bindable.activeSettings.effortLevel,
                    isStreaming: appModel.isStreaming,
                    attachedFiles: appModel.attachedFiles,
                    onRemoveAttachment: { url in appModel.removeAttachment(url) },
                    onClearAttachments: { appModel.clearAttachments() },
                    onSend: {
                        Task {
                            // mention dispatch 시도 — 매칭되면 sendMessage가 그 안에서 호출됨
                            let dispatched = await appModel.tryDispatchMention()
                            if !dispatched {
                                await appModel.sendMessage()
                            }
                        }
                    },
                    onStop: { appModel.cancelStream() },
                    onSettingsApply: { newSettings in
                        Task { await appModel.updateActiveSettings(newSettings) }
                    },
                    onAttach: { appModel.openAttachmentPicker() },
                    onAttachNote: appModel.isVaultConfigured
                        ? { appModel.showNotePicker.toggle() }
                        : nil,
                    mentionSuggestions: mentionSuggestions,
                    agentChainEnabled: appModel.preferences.agentChainEnabled
                )
                .popover(isPresented: $bindable.showNotePicker, arrowEdge: .top) {
                    NotePickerPopover(
                        vaultTree: appModel.vaultTree,
                        query: $bindable.notePickerQuery,
                        onSelectPath: { path in appModel.attachNoteByPath(path) },
                        onClose: { appModel.showNotePicker = false }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.bg)
    }

    private var currentWorkspaceName: String {
        appModel.workspaces.first { $0.id == appModel.selectedWorkspaceId }?.name ?? "yuminai"
    }

    private var currentWorkspacePath: String? {
        appModel.workspaces.first { $0.id == appModel.selectedWorkspaceId }?.directoryPath
    }

    private var currentAgentKind: AgentKind {
        appModel.workspaces.first { $0.id == appModel.selectedWorkspaceId }?.agentKind ?? .default
    }

    /// chat 영역 — split mode에 따라 1 pane (active) 또는 2 panes (active + secondary).
    @ViewBuilder
    private var chatArea: some View {
        let activeView = ChatView(
            messages: appModel.messages,
            assistantLabel: appModel.activePane?.displayName ?? "Claude"
        )

        // secondary pane (active 외 첫 번째) 찾기
        let secondary: AgentPane? = appModel.agentPanes.first { $0.id != appModel.activePaneId }

        if appModel.paneSplitMode != .single, let secondary {
            let secondaryMessages = appModel.paneMessages[secondary.id] ?? []
            let secondaryView = SecondaryPaneView(
                pane: secondary,
                messages: secondaryMessages,
                isStreaming: appModel.isStreaming && appModel.activePaneId == secondary.id,
                onActivate: { Task { await appModel.setActivePane(secondary.id) } },
                onSend: { text in Task { await appModel.sendToPane(secondary.id, text: text) } }
            )

            switch appModel.paneSplitMode {
            case .horizontal:
                HSplitView {
                    activeView
                        .frame(minWidth: 280)
                    secondaryView
                        .frame(minWidth: 240)
                }
            case .vertical:
                VSplitView {
                    activeView
                        .frame(minHeight: 200)
                    secondaryView
                        .frame(minHeight: 160)
                }
            case .single:
                activeView
            }
        } else {
            activeView
        }
    }

    private var mentionSuggestions: [MentionSuggestion] {
        // 같은 agent kind가 여러 개일 수 있어 customName 우선, 없으면 shortLabel
        var seen = Set<String>()
        var result: [MentionSuggestion] = []
        for pane in appModel.agentPanes {
            // 1) customName이 있으면 그것을 handle로
            if let custom = pane.customName, !custom.isEmpty {
                let handle = custom.lowercased()
                    .replacingOccurrences(of: " ", with: "_")
                if seen.insert(handle).inserted {
                    result.append(MentionSuggestion(
                        handle: handle,
                        displayName: pane.displayName,
                        agentKindLabel: pane.agentKind.displayName,
                        isPrimary: pane.role == .primary
                    ))
                }
            }
            // 2) shortLabel은 항상 (첫 번째 agent kind만)
            let kindHandle = pane.agentKind.shortLabel
            if seen.insert(kindHandle).inserted {
                result.append(MentionSuggestion(
                    handle: kindHandle,
                    displayName: pane.displayName,
                    agentKindLabel: pane.agentKind.displayName,
                    isPrimary: pane.role == .primary
                ))
            }
        }
        return result
    }

    @ViewBuilder
    private var chatColumnWithOptionalTerminal: some View {
        let path = currentWorkspacePath
        if appModel.showTerminalPane && appModel.showCommandRunnerPane, let path {
            VSplitView {
                chatArea.frame(minHeight: 160)
                terminalPaneSection(path: path).frame(minHeight: 100, idealHeight: 180)
                commandRunnerSection(path: path).frame(minHeight: 100, idealHeight: 180)
            }
        } else if appModel.showTerminalPane, let path {
            VSplitView {
                chatArea.frame(minHeight: 200)
                terminalPaneSection(path: path).frame(minHeight: 120, idealHeight: 220)
            }
        } else if appModel.showCommandRunnerPane, let path {
            VSplitView {
                chatArea.frame(minHeight: 200)
                commandRunnerSection(path: path).frame(minHeight: 120, idealHeight: 220)
            }
        } else {
            chatArea
        }
    }

    private func commandRunnerSection(path: String) -> some View {
        CommandRunnerPane(
            workingDirectory: path,
            blocks: appModel.commandBlocks,
            isRunning: appModel.isCommandRunning,
            onRun: { cmd in Task { await appModel.runCommand(cmd) } },
            onClear: { appModel.clearCommandBlocks() },
            onClose: { appModel.showCommandRunnerPane = false }
        )
    }

    @ViewBuilder
    private var previewPaneSection: some View {
        @Bindable var bindable = appModel
        PreviewPane(
            urlText: $bindable.previewURLText,
            onClose: { appModel.showPreviewPane = false },
            suggestions: appModel.devServerSuggestions
        )
        .task(id: appModel.selectedWorkspaceId) {
            await appModel.refreshDevServerSuggestions()
        }
    }

    @State private var terminalReloadTrigger: UUID = UUID()

    private func terminalPaneSection(path: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Color.textSecondary)
                Text("터미널")
                    .font(Theme.Typography.small.weight(.medium))
                    .foregroundStyle(Theme.Color.textSecondary)
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(Theme.Typography.monoSmall)
                    .foregroundStyle(Theme.Color.textTertiary)
                HelpHint(
                    "워크스페이스 디렉토리에서 시작된 zsh 세션이에요. agent가 만든 변경을 git status로 확인하거나, 테스트를 직접 실행할 때 사용하세요. ‘새로 시작’으로 reset 가능해요.",
                    title: "터미널 사용법",
                    placement: .bottom
                )
                Spacer()
                Button {
                    terminalReloadTrigger = UUID()  // 새 SwiftTerm view spawn → 새 zsh
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .buttonStyle(.plain)
                .help("터미널 새로 시작 (새 zsh 세션)")
                Button {
                    appModel.showTerminalPane = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .buttonStyle(.plain)
                .help("터미널 닫기")
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Theme.Color.surface)
            .overlay(alignment: .bottom) { FlatHDivider() }

            TerminalPane(workingDirectory: path)
                .id(terminalReloadTrigger)  // trigger 변경 시 view 재생성 → 새 zsh
        }
    }
}

struct EmptyWorkspaceView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Theme.Color.textTertiary)
            VStack(spacing: 6) {
                Text("어떤 작업으로 시작할까요?")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
                Text("워크스페이스 하나를 만들면 Claude/Codex가 그 폴더에서 함께 일해요.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            HStack(spacing: 8) {
                FlatButton("+ 새 워크스페이스 만들기", variant: .primary, size: .large) {
                    appModel.showCreateWorkspaceSheet = true
                }
                .keyboardShortcut("n", modifiers: .command)
                FlatButton("도움말", variant: .secondary, size: .large) {
                    appModel.showShortcutHelp = true
                }
            }
            Text("⌘N · ⌘/")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)

            // 시작 가이드 — 주요 단축키 / 기능 한 눈에
            VStack(alignment: .leading, spacing: 4) {
                quickTipRow(icon: "rectangle.split.2x1", text: "탭바 ‘+’로 Codex pane 추가, split 아이콘으로 동시에 두 pane 보기")
                quickTipRow(icon: "arrowshape.turn.up.right", text: "Composer 우측 ‘위임’ 버튼으로 다른 pane에 자동 라우팅")
                quickTipRow(icon: "terminal", text: "⌘⌥T 터미널, ⌘⌥I Inspector(컨텍스트·노트·변경+Delivery)")
                quickTipRow(icon: "paperplane", text: "사이드바 우클릭 → 텔레그램 연결 / Delivery 자동화 설정")
            }
            .padding(.top, Theme.Spacing.lg)
            .frame(maxWidth: 480)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.bg)
    }

    private func quickTipRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(Theme.Color.accent)
                .frame(width: 16, alignment: .center)
            Text(text)
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
            Spacer()
        }
    }
}
