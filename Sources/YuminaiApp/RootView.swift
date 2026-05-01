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
                onToggleSidebar: onToggleSidebar,
                onToggleInspector: onToggleInspector,
                onToggleTerminal: { appModel.showTerminalPane.toggle() },
                onShowDashboard: { appModel.showUsageDashboard = true },
                onSelectWorkspace: { id in appModel.selectedWorkspaceId = id },
                onCreateWorkspace: { appModel.showCreateWorkspaceSheet = true },
                onSelectAgent: { kind in
                    Task { await appModel.setActiveAgentKind(kind) }
                }
            )

            if appModel.selectedWorkspaceId == nil {
                EmptyWorkspaceView()
            } else {
                if appModel.showTerminalPane, let path = currentWorkspacePath {
                    VSplitView {
                        ChatView(messages: appModel.messages)
                            .frame(minHeight: 200)
                        terminalPaneSection(path: path)
                            .frame(minHeight: 120, idealHeight: 220)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ChatView(messages: appModel.messages)
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
                    onSend: { Task { await appModel.sendMessage() } },
                    onStop: { appModel.cancelStream() },
                    onSettingsApply: { newSettings in
                        Task { await appModel.updateActiveSettings(newSettings) }
                    },
                    onAttach: { appModel.openAttachmentPicker() },
                    onAttachNote: appModel.isVaultConfigured
                        ? { appModel.showNotePicker.toggle() }
                        : nil
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
                Spacer()
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
            FlatButton("+ 새 워크스페이스 만들기", variant: .primary, size: .large) {
                appModel.showCreateWorkspaceSheet = true
            }
            .keyboardShortcut("n", modifiers: .command)
            Text("⌘N")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)

            // 시작 가이드 — 주요 단축키 / 기능 한 눈에
            VStack(alignment: .leading, spacing: 4) {
                quickTipRow(icon: "command", text: "⌘1~9 워크스페이스 빠른 전환, ⌘/ 단축키 도움말")
                quickTipRow(icon: "terminal", text: "⌘⌥T 터미널 패널, ⌘⌥I Inspector(컨텍스트·노트·변경)")
                quickTipRow(icon: "paperplane", text: "Settings → 텔레그램에서 cokacdir 봇 가져오기 / 양방향 제어")
            }
            .padding(.top, Theme.Spacing.lg)
            .frame(maxWidth: 460)

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
