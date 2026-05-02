import SwiftUI
import AppKit
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

    /// ADR-042 R5.B — F2 키 NSEvent local monitor (active file tab의 inline rename 시작).
    /// SwiftUI .onKeyPress가 F2를 직접 지원하지 않아 NSEvent로 우회.
    @State private var f2Monitor: Any?

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
                fileSearchHotkey  // ⌘P invisible
                fileTabHotkeys  // ⌘⌥W close (ADR-042 R2.H8) + ⌘⇧[/⌘⇧] tab nav
                terminalSessionHotkeys  // ⌃⇧T/⌃⇧W/⌃Tab/⌃⇧Tab (ADR-040)
            }
            .onAppear {
                windowSize = geo.size
                appModel.showInspector = inspectorVisible  // legacy sync
                installF2Monitor()
            }
            .onDisappear { removeF2Monitor() }
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
                costSnapshot: appModel.costTracker.snapshot(),
                externalTurnCount: appModel.externalTurnCount,
                externalTurnCostUSD: appModel.externalTurnTotalCostUSD,
                cumulativeCacheHitRatio: appModel.costTracker.cumulativeCacheHitRatio,
                totalCacheReadTokens: appModel.costTracker.totalCacheReadTokens,
                totalCacheCreationTokens: appModel.costTracker.totalCacheCreationTokens,
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
        .sheet(isPresented: $bindable.showFileSearchSheet) {
            FileSearchSheet(
                allFiles: appModel.workspaceFileTree,
                onSelect: { path in
                    Task {
                        await appModel.selectWorkspaceFile(path)
                        appModel.showFileSearchSheet = false
                    }
                },
                onCancel: { appModel.showFileSearchSheet = false }
            )
        }
        .sheet(item: $bindable.fileNameSheetIntent) { intent in
            FileNameSheet(
                intent: intent,
                onSubmit: { name in
                    Task { await appModel.commitFileNameIntent(intent, name: name) }
                    appModel.fileNameSheetIntent = nil
                },
                onCancel: { appModel.fileNameSheetIntent = nil }
            )
        }
        .alert(item: $bindable.fileDeleteConfirmation) { confirmation in
            Alert(
                title: Text(confirmation.title),
                message: Text(confirmation.message),
                primaryButton: .destructive(Text("휴지통으로 이동")) {
                    Task { await appModel.deleteWorkspaceNode(at: confirmation.path, moveToTrash: true) }
                    appModel.fileDeleteConfirmation = nil
                },
                secondaryButton: .cancel(Text("취소")) {
                    appModel.fileDeleteConfirmation = nil
                }
            )
        }
        .sheet(item: terminalRenameBinding) { session in
            TerminalRenameSheet(
                session: session,
                onSubmit: { newLabel in
                    appModel.renameTerminalSession(session.id, to: newLabel)
                    appModel.terminalRenameTargetId = nil
                },
                onCancel: { appModel.terminalRenameTargetId = nil }
            )
        }
        .sheet(item: editProjectProfileBinding) { workspace in
            EditProjectProfileSheet(
                workspace: workspace,
                onSave: { profile in
                    Task { await appModel.updateProjectProfile(workspaceId: workspace.id, profile: profile) }
                    appModel.editingProjectProfileForWorkspaceId = nil
                },
                onCancel: { appModel.editingProjectProfileForWorkspaceId = nil }
            )
        }
        // ADR-051 + ADR-052 — ⌘K Command Palette (pin/recent 지원)
        .sheet(isPresented: $bindable.showCommandPalette) {
            CommandPaletteSheet(
                actions: appModel.buildCommandPaletteActions(),
                pinnedIds: appModel.palettePinnedIds,
                recentIds: appModel.paletteRecentIds,
                onPerform: { action in
                    appModel.showCommandPalette = false
                    Task { await appModel.performPaletteAction(action) }
                },
                onTogglePin: { actionId in
                    Task { await appModel.togglePalettePin(actionId) }
                },
                onCancel: { appModel.showCommandPalette = false }
            )
        }
        // ADR-051 — Walk-through view (완료 task step-by-step)
        .sheet(item: walkthroughBinding) { task in
            WalkthroughSheet(
                task: task,
                allEntries: appModel.harness.conversationLog,
                onClose: { appModel.walkthroughTaskId = nil }
            )
        }
        // ADR-051 — Harness 도움말
        .sheet(isPresented: $bindable.showHarnessHelp) {
            HarnessHelpSheet(onClose: { appModel.showHarnessHelp = false })
        }
        // ADR-052 — Routing Decision Log viewer
        .sheet(isPresented: $bindable.showRoutingLog) {
            RoutingDecisionLogSheet(
                decisions: appModel.routingDecisions,
                onClose: { appModel.showRoutingLog = false },
                onExport: {
                    Task { await appModel.exportRoutingLog() }
                },
                onClear: {
                    Task { await appModel.clearRoutingLogMemory() }
                }
            )
        }
        // ADR-061 Phase 1 — SwiftUI Charts dashboard (8 charts)
        .sheet(isPresented: $bindable.showChartsDashboard) {
            ChartsDashboard(
                costSnapshot: appModel.costTracker.snapshot(),
                cacheTrend: appModel.cacheTrendSnapshot,
                routingDecisions: appModel.routingDecisions,
                workspaceCosts: appModel.workspaceTodayCostUSD.compactMap { (id, cost) in
                    guard let ws = appModel.workspaces.first(where: { $0.id == id }) else { return nil }
                    return (workspaceName: ws.name, costUSD: cost)
                },
                currentSessionUsage: appModel.currentSessionUsage,
                workspaceNames: Dictionary(uniqueKeysWithValues: appModel.workspaces.map { ($0.id, $0.name) }),
                onClose: { appModel.showChartsDashboard = false }
            )
            .task { await appModel.refreshCacheTrendSnapshot() }
        }
        // ADR-062 Phase 6 — Telegram Usage Dashboard (사용자 신규 요청)
        .sheet(isPresented: $bindable.showTelegramUsageDashboard) {
            TelegramUsageDashboard(
                snapshot: appModel.telegramUsageSnapshot,
                chatIdToWorkspaceName: appModel.telegramChatIdToWorkspaceName(),
                onClose: { appModel.showTelegramUsageDashboard = false },
                onClearStats: { Task { await appModel.clearTelegramUsage() } }
            )
            .task { await appModel.loadTelegramUsage() }
        }
        // ADR-062 Phase 3 — Chat Binding Audit Log Viewer
        .sheet(isPresented: $bindable.showChatBindingAuditLog) {
            ChatBindingAuditLogSheet(
                entries: appModel.chatBindingAuditEntries,
                onClose: { appModel.showChatBindingAuditLog = false }
            )
            .task {
                appModel.chatBindingAuditEntries = await appModel.chatBindingAuditLog.recent(limit: 100)
            }
        }
        // ADR-052 — Walk-through rehearsal sheet (다른 모델로 재실행)
        .sheet(item: rehearsalBinding) { task in
            RehearsalSheet(
                task: task,
                allEntries: appModel.harness.conversationLog,
                rehearsals: appModel.rehearsals(forTaskId: task.id),
                onLaunch: { agent in
                    Task { await appModel.launchRehearsal(taskId: task.id, agent: agent) }
                },
                onClose: { appModel.rehearsalTaskId = nil }
            )
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
                    },
                    workspaceFileTree: appModel.workspaceFileTree,
                    openFileTabs: appModel.openFileTabs,
                    activeFileTabId: appModel.activeFileTabId,
                    selectedFilePath: appModel.selectedFilePath,
                    selectedFileContents: appModel.selectedFileContents,
                    isEditingFile: appModel.isEditingWorkspaceFile,
                    fileDraft: Binding(
                        get: { appModel.workspaceFileDraft },
                        set: { appModel.workspaceFileDraft = $0 }
                    ),
                    isFileDirty: appModel.isWorkspaceFileDirty,
                    onSelectFile: { path in Task { await appModel.selectWorkspaceFile(path) } },
                    onSelectFileTab: { id in appModel.setActiveFileTab(id) },
                    onCloseFileTab: { id in appModel.closeFileTab(id) },
                    onStartEditingFile: { appModel.startEditingWorkspaceFile() },
                    onSaveFile: { Task { await appModel.saveWorkspaceFile() } },
                    onDiscardFileEdits: { appModel.discardWorkspaceFileEdits() },
                    onRefreshFileTree: { Task { await appModel.refreshWorkspaceFileTree() } },
                    onOpenFileInExternalEditor: { path in appModel.openFileInExternalEditor(path) },
                    onShowFileSearch: { appModel.presentExclusiveSheet { $0.showFileSearchSheet = true } },
                    onRequestCreateFile: { parent in
                        appModel.fileNameSheetIntent = .newFile(parent: parent)
                    },
                    onRequestCreateFolder: { parent in
                        appModel.fileNameSheetIntent = .newFolder(parent: parent)
                    },
                    onRequestRename: { path, isFolder in
                        appModel.fileNameSheetIntent = .rename(path: path, isFolder: isFolder)
                    },
                    onRequestDelete: { path, isFolder in
                        appModel.fileDeleteConfirmation = FileDeleteConfirmation(
                            path: path, isFolder: isFolder
                        )
                    },
                    selectedFilePaths: appModel.selectedFilePaths,
                    onToggleFileSelection: { path in appModel.toggleFileSelection(path) },
                    onClearFileSelection: { appModel.clearFileSelection() },
                    onBulkDeleteFiles: { Task { await appModel.deleteSelectedWorkspaceNodes() } },
                    inlineRenamePath: appModel.inlineRenameTargetPath,
                    onBeginInlineRename: { path in appModel.beginInlineRename(path) },
                    onCommitInlineRename: { path, name in
                        Task { await appModel.commitInlineRename(path, newName: name) }
                    },
                    onCancelInlineRename: { appModel.cancelInlineRename() },
                    onAskAgentToUpdateImports: { oldPath, newPath in
                        appModel.askAgentToUpdateImports(oldPath: oldPath, newPath: newPath)
                    },
                    onMoveFile: { oldPath, newPath in
                        Task { await appModel.moveWorkspaceNode(at: oldPath, to: newPath) }
                    },
                    // ADR-049 Phase 5 — Harness UI integration
                    harnessTabEnabled: appModel.preferences.harnessUIEnabled,
                    harnessEntries: appModel.harness.conversationLog,
                    harnessEstimatedTokens: appModel.harness.estimatedTotalTokens,
                    harnessAgentCounts: appModel.harness.agentResponseCounts,
                    harnessSessionCostUSD: appModel.currentSessionUsage.costUSD,
                    harnessTasks: appModel.harness.tasks,
                    onHarnessUpdateTaskStatus: { id, status in
                        appModel.harness.updateTaskStatus(id, status)
                    },
                    onHarnessRemoveTask: { id in appModel.harness.removeTask(id) },
                    onHarnessAddTask: {
                        appModel.harness.addTask(
                            title: "새 작업",
                            description: "수동 추가된 작업 — 편집하세요",
                            assignedAgent: appModel.currentWorkspace?.agentKind
                        )
                    },
                    onHarnessRunTask: { id in Task { await appModel.runHarnessTask(id) } },
                    onHarnessShowWalkthrough: { id in
                        appModel.presentExclusiveSheet { $0.walkthroughTaskId = id }
                    },
                    onHarnessShowHelp: {
                        appModel.presentExclusiveSheet { $0.showHarnessHelp = true }
                    },
                    onHarnessShowRehearsal: { id in
                        appModel.presentExclusiveSheet { $0.rehearsalTaskId = id }
                    },
                    onHarnessShowRoutingLog: {
                        appModel.presentExclusiveSheet { $0.showRoutingLog = true }
                    }
                )
                .task(id: appModel.selectedWorkspaceId) {
                    // ADR-043 R4 — 단일 transition 함수로 응집 (race/순서 명확)
                    await appModel.transitionToWorkspace(appModel.selectedWorkspaceId)
                }
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
            onEditProjectProfile: { ws in
                appModel.presentExclusiveSheet { $0.editingProjectProfileForWorkspaceId = ws.id }
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

    /// ⌘P — 파일 검색 (Cmd+P palette) sheet.
    private var fileSearchHotkey: some View {
        ZStack {
            Button {
                appModel.presentExclusiveSheet { $0.showFileSearchSheet = true }
            } label: { EmptyView() }
                .keyboardShortcut("p", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
                .disabled(appModel.currentWorkspace == nil)
            // ADR-051 — ⌘K Command Palette
            Button {
                appModel.presentExclusiveSheet { $0.showCommandPalette = true }
            } label: { EmptyView() }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    /// ADR-051 — Walk-through sheet binding (task id ↔ HarnessTask).
    private var walkthroughBinding: Binding<HarnessTask?> {
        Binding(
            get: {
                guard let id = appModel.walkthroughTaskId else { return nil }
                return appModel.harness.tasks.first { $0.id == id }
            },
            set: { newValue in
                appModel.walkthroughTaskId = newValue?.id
            }
        )
    }

    /// ADR-052 — Rehearsal sheet binding (task id ↔ HarnessTask).
    private var rehearsalBinding: Binding<HarnessTask?> {
        Binding(
            get: {
                guard let id = appModel.rehearsalTaskId else { return nil }
                return appModel.harness.tasks.first { $0.id == id }
            },
            set: { newValue in
                appModel.rehearsalTaskId = newValue?.id
            }
        )
    }

    /// ADR-049 — ProjectProfile 편집 sheet binding (workspace id ↔ Workspace).
    private var editProjectProfileBinding: Binding<Workspace?> {
        Binding(
            get: {
                guard let id = appModel.editingProjectProfileForWorkspaceId else { return nil }
                return appModel.workspaces.first { $0.id == id }
            },
            set: { newValue in
                appModel.editingProjectProfileForWorkspaceId = newValue?.id
            }
        )
    }

    /// 터미널 라벨 변경 sheet binding helper (Identifiable item ↔ optional UUID 매핑).
    private var terminalRenameBinding: Binding<TerminalSession?> {
        Binding(
            get: {
                guard let id = appModel.terminalRenameTargetId else { return nil }
                return appModel.terminalSessions.first { $0.id == id }
            },
            set: { newValue in
                appModel.terminalRenameTargetId = newValue?.id
            }
        )
    }

    /// 다중 터미널 단축키 (ADR-040 T9):
    /// - ⌃⇧T 새 세션 / ⌃⇧W 활성 세션 닫기
    /// - ⌃Tab 다음 / ⌃⇧Tab 이전
    private var terminalSessionHotkeys: some View {
        ZStack {
            Button {
                if !appModel.showTerminalPane { appModel.showTerminalPane = true }
                appModel.createTerminalSession()
            } label: { EmptyView() }
                .keyboardShortcut("t", modifiers: [.control, .shift])
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
                .disabled(appModel.currentWorkspace == nil)

            Button {
                appModel.closeActiveTerminalSession()
            } label: { EmptyView() }
                .keyboardShortcut("w", modifiers: [.control, .shift])
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
                .disabled(appModel.activeTerminalSessionId == nil)

            Button {
                appModel.selectAdjacentTerminalSession(offset: 1)
            } label: { EmptyView() }
                .keyboardShortcut(.tab, modifiers: [.control])
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
                .disabled(appModel.terminalSessions.count < 2)

            Button {
                appModel.selectAdjacentTerminalSession(offset: -1)
            } label: { EmptyView() }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
                .disabled(appModel.terminalSessions.count < 2)
        }
    }

    /// ⌘W = active tab close / ⌘⇧] = 다음 tab / ⌘⇧[ = 이전 tab (ADR-038 R2).
    private var fileTabHotkeys: some View {
        ZStack {
            // ADR-042 R2.H8 — ⌘W는 macOS 표준 (윈도우 close)에 양보.
            // file tab close = ⌘⌥W (Option 추가) — VSCode와 동일 패턴은 아니지만 SwiftUI의
            // standard close 충돌 방지가 우선. 사용자에겐 ShortcutHelpSheet에 명시.
            Button {
                appModel.closeActiveFileTab()
            } label: { EmptyView() }
                .keyboardShortcut("w", modifiers: [.command, .option])
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
                .disabled(appModel.activeFileTabId == nil)

            Button {
                appModel.selectAdjacentFileTab(offset: 1)
            } label: { EmptyView() }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
                .disabled(appModel.openFileTabs.count < 2)

            Button {
                appModel.selectAdjacentFileTab(offset: -1)
            } label: { EmptyView() }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
                .disabled(appModel.openFileTabs.count < 2)
        }
    }

    private var helpHotkey: some View {
        Button("") { appModel.presentExclusiveSheet { $0.showShortcutHelp = true } }
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

    /// ADR-042 R5.B — NSEvent local monitor 설치 (F2 키).
    /// active file tab이 있고 inline rename 중이 아니면 inline rename 시작.
    private func installF2Monitor() {
        guard f2Monitor == nil else { return }
        f2Monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // F2 = keyCode 120 on macOS
            guard event.keyCode == 120 else { return event }
            // sheet/alert 열려있으면 무시 (텍스트 입력 방해 방지)
            guard appModel.fileNameSheetIntent == nil,
                  appModel.fileDeleteConfirmation == nil,
                  !appModel.showFileSearchSheet,
                  !appModel.showShortcutHelp else {
                return event
            }
            // 인라인 rename 진행 중이면 무시
            guard appModel.inlineRenameTargetPath == nil else { return event }
            // 활성 파일이 없으면 무시
            guard let path = appModel.activeFileTab?.path else { return event }
            appModel.beginInlineRename(path)
            return nil  // 이벤트 소비 (다른 핸들러 차단)
        }
    }

    private func removeF2Monitor() {
        if let monitor = f2Monitor {
            NSEvent.removeMonitor(monitor)
            f2Monitor = nil
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
                onToggleTerminal: { appModel.toggleTerminalPane() },
                onTogglePreview: { appModel.showPreviewPane.toggle() },
                onToggleCommands: { appModel.showCommandRunnerPane.toggle() },
                onShowDashboard: { appModel.showUsageDashboard = true },
                onShowShortcutHelp: { appModel.presentExclusiveSheet { $0.showShortcutHelp = true } },
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
                // ADR-051 — Routing intervention banner (3초 cancel window)
                if let pending = appModel.pendingRouting {
                    routingInterventionBanner(pending: pending)
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
                // ADR-042 R1.H7 — pendingComposerPrefix 큐 consume.
                // 외부(share/imports/auto-chain)가 enqueue하면 여기서 안전하게 inputText에 prepend.
                // 사용자 입력은 절대 race되지 않음 (큐 consume 시점에만 합쳐짐).
                .onChange(of: appModel.pendingComposerPrefix) { _, newValue in
                    guard let prefix = newValue else { return }
                    appModel.inputText = prefix + appModel.inputText
                    appModel.pendingComposerPrefix = nil
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
        VStack(spacing: 0) {
            // ADR-054 — 진행 중인 ChildProcess (decomposition/rehearsal/parallel) badge
            ChildProcessBadge(processes: appModel.activeChildProcesses)
            // ADR-051 — Inline mode: 메인 chat을 통째로 HarnessConversationView로 교체
            if appModel.preferences.harnessInlineModeEnabled {
                HarnessConversationView(
                    entries: appModel.harness.conversationLog,
                    estimatedTotalTokens: appModel.harness.estimatedTotalTokens,
                    agentResponseCounts: appModel.harness.agentResponseCounts,
                    sessionCostUSD: appModel.currentSessionUsage.costUSD,
                    onShowHelp: { appModel.presentExclusiveSheet { $0.showHarnessHelp = true } }
                )
            } else {
                traditionalChatArea
            }
        }
    }

    @ViewBuilder
    private var traditionalChatArea: some View {
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
        let cfg = appModel.currentWorkspace?.deliveryConfig ?? .disabled
        let quick = QuickCommand.defaults(
            test: cfg.testCommand,
            build: cfg.buildCommand,
            lint: cfg.lintCommand,
            custom: cfg.customQuickCommands
        )
        return CommandRunnerPane(
            workingDirectory: path,
            blocks: appModel.commandBlocks,
            isRunning: appModel.isCommandRunning,
            quickCommands: quick,
            onRun: { cmd in Task { await appModel.runCommand(cmd) } },
            onClear: { appModel.clearCommandBlocks() },
            onClose: { appModel.showCommandRunnerPane = false },
            onCopyOutput: { text in appModel.copyCommandBlockOutput(text) },
            onShareToAgent: { block in appModel.shareCommandBlockToAgent(block) }
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

    @State private var terminalReloadTriggers: [UUID: UUID] = [:]

    private func terminalPaneSection(path: String) -> some View {
        VStack(spacing: 0) {
            terminalHeader(path: path)
            if !appModel.terminalSessions.isEmpty {
                terminalSessionTabBar
                FlatHDivider()
            }
            terminalActiveSessionContent(path: path)
        }
    }

    private func terminalHeader(path: String) -> some View {
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
                "워크스페이스 디렉토리에서 시작된 zsh 세션이에요. ⌃⇧T로 새 세션 추가, ⌃Tab으로 세션 전환, 라벨 더블클릭으로 이름 변경, 이름 옆 ↻로 reset.",
                title: "다중 터미널 (ADR-040)",
                placement: .bottom
            )
            Spacer()
            Button {
                appModel.createTerminalSession()
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .buttonStyle(.plain)
            .help("새 터미널 세션 (⌃⇧T)")
            Button {
                appModel.toggleTerminalSplit()
            } label: {
                Image(systemName: appModel.terminalSplitEnabled ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(appModel.terminalSplitEnabled ? Theme.Color.accent : Theme.Color.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(appModel.terminalSessions.count < 1)
            .help("좌우 split 토글 (T14)")
            Button {
                if let id = appModel.activeTerminalSessionId {
                    terminalReloadTriggers[id] = UUID()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(appModel.activeTerminalSessionId == nil)
            .help("활성 세션 새로 시작")
            Button {
                appModel.showTerminalPane = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .buttonStyle(.plain)
            .help("터미널 pane 닫기")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Color.surface)
        .overlay(alignment: .bottom) { FlatHDivider() }
    }

    @ViewBuilder
    private var terminalSessionTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 1) {
                ForEach(appModel.terminalSessions) { session in
                    TerminalSessionTabButton(
                        session: session,
                        isActive: session.id == appModel.activeTerminalSessionId,
                        onSelect: { appModel.setActiveTerminalSession(session.id) },
                        onClose: { appModel.closeTerminalSession(session.id) },
                        onRequestRename: { appModel.terminalRenameTargetId = session.id },
                        onRequestChangeDirectory: { appModel.requestTerminalDirectoryChange(session.id) }
                    )
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 2)
        }
        .background(Theme.Color.surface)
    }

    @ViewBuilder
    private func terminalActiveSessionContent(path: String) -> some View {
        if appModel.terminalSessions.isEmpty {
            EmptyStateHint(
                icon: "terminal",
                title: "활성 터미널 세션이 없어요",
                message: "위 ‘+’ 버튼이나 ⌃⇧T로 새 세션을 만드세요."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if appModel.terminalSplitEnabled,
                  let secondaryId = appModel.secondaryTerminalSessionId,
                  appModel.terminalSessions.contains(where: { $0.id == secondaryId }),
                  appModel.terminalSessions.count >= 2 {
            // Split 모드 — 좌우 dual-pane (T14) + ADR-042 R2.H12: badge로 primary/secondary 구분
            HSplitView {
                splitPaneContainer(
                    activeId: appModel.activeTerminalSessionId,
                    label: "Primary",
                    isPrimary: true
                )
                .frame(minWidth: 200)
                splitPaneContainer(
                    activeId: secondaryId,
                    label: "Secondary",
                    isPrimary: false
                )
                .frame(minWidth: 200)
            }
        } else {
            terminalSessionsZStack(activeId: appModel.activeTerminalSessionId)
        }
    }

    /// ADR-042 R2.H12 — split mode 시 각 pane을 badge + accent border로 구분.
    /// Primary는 accent border (사용자가 ⌃Tab으로 전환하는 대상), secondary는 borderSubtle.
    @ViewBuilder
    private func splitPaneContainer(activeId: UUID?, label: String, isPrimary: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(label)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(isPrimary ? Theme.Color.accent : Theme.Color.textTertiary)
                if let activeId, let session = appModel.terminalSessions.first(where: { $0.id == activeId }) {
                    Text("· \(session.label)")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.Color.surface.opacity(0.4))
            terminalSessionsZStack(activeId: activeId)
        }
        .overlay(
            Rectangle()
                .stroke(isPrimary ? Theme.Color.accent.opacity(0.6) : Theme.Color.borderSubtle, lineWidth: 1)
        )
    }

    /// 모든 세션을 ZStack에 두고 active만 visible — 비활성 세션도 PTY data 흐름 유지
    /// (활동 감지 + 백그라운드 작업 표시를 위해 필수). Split 모드에서는 두 ZStack이 각 active를 가리킴.
    @ViewBuilder
    private func terminalSessionsZStack(activeId: UUID?) -> some View {
        ZStack {
            ForEach(appModel.terminalSessions) { session in
                let isActive = session.id == activeId
                let trigger = terminalReloadTriggers[session.id] ?? session.id
                TerminalPane(
                    workingDirectory: session.workingDirectory,
                    onActivityChanged: { activity in
                        appModel.updateTerminalActivity(session.id, activity)
                    }
                )
                .id(trigger)
                .opacity(isActive ? 1 : 0)
                .allowsHitTesting(isActive)
            }
        }
    }

    /// ADR-051 — Routing intervention banner (3초 cancel window).
    /// 사용자가 자동 routing 결정에 개입할 수 있는 짧은 윈도우 — 신뢰 UX (XAI + intervention 원칙).
    fileprivate func routingInterventionBanner(pending: AppModel.PendingRouting) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.left.arrow.right.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("자동 routing 예정 — \(pending.from.shortLabel) → \(pending.to.shortLabel)")
                    .font(Theme.Typography.small.weight(.medium))
                    .foregroundStyle(Theme.Color.text)
                Text("\(pending.reason) · ~\(pending.estimatedHandoffTokens) tokens handoff · \(pending.secondsRemaining)초 후 진행")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
            Button("취소 (현재 모델 유지)") {
                appModel.cancelPendingRouting()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .stroke(Color.orange, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Color.orange.opacity(0.12))
        .overlay(alignment: .bottom) { FlatHDivider() }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// 터미널 세션 탭 버튼 — FileTabButton 패턴 + 활동 indicator + pulse 애니메이션 (ADR-041 T10).
///
/// **상태 표시**:
/// - `.idle`: 회색 terminal 아이콘
/// - `.running` (활성 세션): 녹색 점 + pulse (작업 중) — ADR-042 R2.H11: 활성 세션만 pulse
/// - `.running` (비활성 세션): 정적 녹색 점 (시각 노이즈 감소)
/// - `.completedRecently`: 녹색 체크 (방금 완료, 3초 후 idle)
/// - `hasUnreadOutput` (비활성 세션): 주황 dot — "이 세션에 새 출력 있어요"
/// - `accessibilityDisplayShouldReduceMotion=true` 시 모든 pulse 비활성화 (정적 dot)
private struct TerminalSessionTabButton: View {
    let session: TerminalSession
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onRequestRename: () -> Void
    let onRequestChangeDirectory: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var pulse = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                activityIcon
                Text(session.label)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(isActive ? Theme.Color.text : Theme.Color.textSecondary)
                    .lineLimit(1)
                if session.hasUnreadOutput && !isActive {
                    // ADR-043 R4 — 5pt → 7pt + white border (가시성 ↑, 주변 시야 인지 강화)
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1))
                        .help("새 출력이 있어요 — 클릭해서 확인")
                }
                if hovering || isActive {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("세션 닫기")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(isActive ? Theme.Color.bg : (hovering ? Theme.Color.surfaceHi : Color.clear))
            .overlay(alignment: .bottom) {
                if isActive {
                    Rectangle()
                        .fill(Theme.Color.accent)
                        .frame(height: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("이름 변경", action: onRequestRename)
            Button("디렉토리 변경…", action: onRequestChangeDirectory)
            Divider()
            Button(role: .destructive, action: onClose) {
                Label("세션 닫기", systemImage: "xmark")
            }
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { onRequestRename() }
        )
        .onAppear { pulse = true }
        .help(activityHelp)
    }

    @ViewBuilder
    private var activityIcon: some View {
        switch session.activity {
        case .idle:
            Image(systemName: "terminal")
                .font(.system(size: 9))
                .foregroundStyle(isActive ? Theme.Color.accent : Theme.Color.textTertiary)
        case .running:
            // ADR-042 R2.H11 — 활성 세션만 pulse (시각 노이즈 감소).
            // 비활성 세션 + reduceMotion 시 정적 dot — 작업 중인 것은 알리되 산만하지 않게.
            let shouldPulse = isActive && !reduceMotion
            ZStack {
                if shouldPulse {
                    Circle()
                        .fill(Color.green.opacity(0.25))
                        .frame(width: 12, height: 12)
                        .scaleEffect(pulse ? 1.4 : 0.8)
                        .opacity(pulse ? 0 : 0.8)
                        .animation(
                            .easeInOut(duration: 1.4).repeatForever(autoreverses: false),
                            value: pulse
                        )
                }
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
            }
            .frame(width: 12, height: 12)
        case .completedRecently:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.green)
                .transition(.scale.combined(with: .opacity))
        }
    }

    private var activityHelp: String {
        switch session.activity {
        case .idle: return "유휴 — 명령 대기 중"
        case .running: return "작업 중 — PTY 출력 흐르는 중"
        case .completedRecently: return "방금 완료"
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
                    appModel.presentExclusiveSheet { $0.showShortcutHelp = true }
                }
            }
            Text("⌘N 새 워크스페이스 · ⌘/ 단축키 도움말")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)

            // ADR-042 R2.H9 — 시작 가이드 + v0.9+/v1.2+ 추가된 단축키 발견성 확보
            VStack(alignment: .leading, spacing: 4) {
                quickTipRow(icon: "rectangle.split.2x1", text: "탭바 ‘+’로 Codex pane 추가, split 아이콘으로 동시에 두 pane 보기")
                quickTipRow(icon: "arrowshape.turn.up.right", text: "Composer 우측 ‘위임’ 버튼으로 다른 pane에 자동 라우팅")
                quickTipRow(icon: "doc.text.magnifyingglass", text: "⌘P 파일 빠른 검색 (Cmd+P) — 트리에서 찾지 말고 이름으로 점프")
                quickTipRow(icon: "terminal", text: "⌃⇧T 새 터미널 세션 / ⌃Tab 세션 전환 / ⌃⇧W 닫기")
                quickTipRow(icon: "rectangle.stack", text: "⌘⌥T SwiftTerm 터미널, ⌘⌥I Inspector(컨텍스트·노트·변경+Delivery)")
                quickTipRow(icon: "hand.tap", text: "트리에서 Cmd+클릭 다중 선택, 파일을 폴더에 drag-drop으로 이동")
                quickTipRow(icon: "paperplane", text: "사이드바 우클릭 → 텔레그램 연결 / Delivery 자동화 설정")
            }
            .padding(.top, Theme.Spacing.lg)
            .frame(maxWidth: 540)

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
