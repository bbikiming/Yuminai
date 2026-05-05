import Foundation
import SwiftUI
import AppKit
import os
import YuminaiCore
import YuminaiClaudeAdapter
import YuminaiPersistence
import YuminaiTelegram
import YuminaiObsidian
import YuminaiUI
import YuminaiHarness

/// 앱 전역 상태 + DI 컨테이너. SwiftUI Environment로 주입된다.
@MainActor
@Observable
public final class AppModel {

    // MARK: 의존성
    let workspaceStore: any WorkspaceStore
    let sessionStore: any SessionStore
    let keychainStore: any KeychainStore
    let preferencesStore: any AppPreferencesStore
    let claudeAdapter: any ClaudeAdapter
    /// codex CLI 어댑터 — workspace.agentKind == .codex일 때 사용 (ADR-026).
    /// nil이면 codex 미설치/미설정 — UI에서 선택 disabled.
    let codexAdapter: (any ClaudeAdapter)?
    /// **ADR-053** — ChildClaudeProcess (1회성 ephemeral) — decomposition / rehearsal / parallel 격리 호출.
    /// nil이면 mock으로 fallback (테스트/preview).
    let childProcess: (any ChildClaudeProcess)?

    // MARK: 상태
    public var preferences: AppPreferences
    public var workspaces: [Workspace] = []
    public var selectedWorkspaceId: UUID?
    public var currentSession: Session?
    public var messages: [Message] = []
    public var inputText: String = ""
    /// ADR-042 R1.H7 — composer가 다음 render에 inputText에 prepend할 prefix queue.
    /// 사용자 입력 mutation race 방지 — 외부(share/imports/mention/auto-chain)는 이 큐에 쌓고,
    /// Composer가 onChange로 consume하면 자동 클리어. 사용자 textfield cursor jump/stale 위험 제거.
    public var pendingComposerPrefix: String?
    public var isStreaming: Bool = false
    public var error: String?

    public var anthropicKeyStatus: SecretStatus = .notSet
    public var telegramTokenStatus: SecretStatus = .notSet
    public var cokacdirBots: [CokacdirBot] = []
    public var cokacdirChatLabels: [Int64: CokacdirChatLabel] = [:]
    public var cokacdirImportError: String?
    public var showCokacdirImportSheet: Bool = false
    /// **ADR-100** — cokacdir import 라우팅 모드.
    /// `.legacy`: Settings에서 호출 (기존 단일 봇 슬롯 채움). `.hub`: Telegram Hub에서 호출 (multi-bot 모델에 추가).
    public enum CokacdirImportMode: Sendable { case legacy, hub }
    public var cokacdirImportMode: CokacdirImportMode = .legacy

    public var showCreateWorkspaceSheet: Bool = false
    /// **ADR-106** — 사용자 프로필 편집 sheet.
    public var showUserProfileSheet: Bool = false
    /// **ADR-089** — 새 ad-hoc 대화 세션 생성 sheet.
    public var showNewChatSessionSheet: Bool = false
    public var showUsageDashboard: Bool = false
    public var showInspector: Bool = false
    /// **ADR-076 Phase 4** — 폴더 이름 입력/변경 sheet.
    /// `folderRenameTargetId`가 nil이면 새 폴더 생성, 있으면 해당 폴더 이름 변경.
    public var showFolderRenameSheet: Bool = false
    public var folderRenameTargetId: UUID?
    /// **ADR-078 Phase 3** — 워크스페이스 fuzzy search sheet (⌘P).
    public var showWorkspaceSearchSheet: Bool = false
    /// **ADR-078 Phase 4** — 태그 생성/편집 sheet.
    /// `tagEditTargetId`가 nil이면 새 태그 생성, 있으면 해당 태그 편집.
    public var showTagEditSheet: Bool = false
    public var tagEditTargetId: UUID?
    /// **ADR-079 Phase 4** — Git status 캐시 (현재 워크스페이스).
    public var gitBranch: String?
    public var gitDirtyStats: DirtyStats?
    /// **ADR-081 Phase 1** — upstream sync status (ahead/behind).
    public var gitUpstream: UpstreamStatus?
    /// **ADR-079 Phase 5** — Git commit sheet (메시지 입력).
    public var showGitCommitSheet: Bool = false
    /// **ADR-079 Phase 4** — Git branch picker popover.
    public var showGitBranchPicker: Bool = false
    /// **ADR-081 Phase 4** — Git stash sheet.
    public var showGitStashSheet: Bool = false
    /// **ADR-081 Phase 1** — push/pull 진행 중 (UI 비활성화용).
    public var gitOperationInProgress: Bool = false
    /// **ADR-082 Phase 1** — Git diff viewer sheet.
    public var showGitDiffSheet: Bool = false
    /// **ADR-082 Phase 2** — GitHub PR review sheet.
    public var showGitHubPRSheet: Bool = false
    /// **ADR-082 Phase 4** — Git rebase sheet.
    public var showGitRebaseSheet: Bool = false
    /// **ADR-083 Phase 1** — Conflict resolution sheet.
    public var showGitConflictSheet: Bool = false
    /// **ADR-083 Phase 2** — Cherry-pick sheet.
    public var showGitCherryPickSheet: Bool = false
    /// **ADR-084** — 텔레그램 고도화 설정 sheet.
    public var showTelegramAdvancedSheet: Bool = false
    /// **ADR-086 Phase 1** — 텔레그램 health snapshot (사이드바 pill용 + sheet).
    public var telegramHealth: TelegramHealthSnapshot = TelegramHealthSnapshot()
    /// **ADR-086 Phase 1** — Error log viewer sheet.
    public var showTelegramErrorLogSheet: Bool = false
    /// **ADR-086 Phase 4** — Multi-bot manager sheet.
    /// - Note: Deprecated 진행 중. 새 진입점은 `showTelegramHubSheet` (ADR-092).
    public var showTelegramBotManagerSheet: Bool = false
    /// **ADR-092 Phase 1** — Telegram Hub sheet (4-tab: Bots / Bindings / Commands / Activity).
    public var showTelegramHubSheet: Bool = false
    /// **ADR-093 Phase 2** — Offline queue depth (5초 주기 폴링, BotStatusDock 표시용).
    public var telegramQueueDepth: Int = 0

    // MARK: - ADR-097 — Telegram Artifact Viewer

    /// **ADR-097** — diff/log artifact 컨텐츠를 UUID로 저장하는 store.
    public let telegramArtifactStore: TelegramArtifactStore = TelegramArtifactStore()
    /// **ADR-097** — artifact viewer sheet 표시 여부.
    public var showTelegramArtifactSheet: Bool = false
    /// **ADR-097** — 현재 viewer에 표시할 artifact UUID.
    public var artifactSheetId: UUID? = nil

    // MARK: - ADR-097 — macOS Notification Permission

    /// **ADR-097** — macOS 알림 권한 상태 (앱 시작 시 확인, 사용자 요청 후 갱신).
    public var macOSNotificationStatus: MacOSNotificationPermission.Status = .notDetermined

    // 활성 세션 설정 (toolbar에서 즉시 변경 가능)
    public var activeSettings: SessionSettings = .default

    // 사용량 (실시간 갱신)
    public var currentSessionUsage: UsageStats = .zero
    public var allTimeUsage: UsageStats = .zero
    public var lastCostDelta: Double = 0

    // 첨부파일 — sendMessage 시 prompt 앞에 `@<path>` 형식으로 prepend
    public var attachedFiles: [URL] = []

    public var inspectorTab: InspectorTab = .context

    // ADR-042 R3.6 — ObsidianVaultCoordinator 추출 (state-only minimal). AppModel facade.
    public let vault: ObsidianVaultCoordinator = ObsidianVaultCoordinator()

    public var obsidianVault: ObsidianVault? {
        get { vault.vault }
        set { vault.vault = newValue }
    }
    public var vaultTree: [VaultNode] {
        get { vault.tree }
        set { vault.tree = newValue }
    }
    public var selectedNote: Note? {
        get { vault.selectedNote }
        set { vault.selectedNote = newValue }
    }
    public var noteSearchQuery: String {
        get { vault.searchQuery }
        set { vault.searchQuery = newValue }
    }
    public var noteFullTextEnabled: Bool {
        get { vault.fullTextEnabled }
        set { vault.fullTextEnabled = newValue }
    }
    public var noteFullTextHits: [SearchHit] {
        get { vault.fullTextHits }
        set { vault.fullTextHits = newValue }
    }
    public var isEditingNote: Bool {
        get { vault.isEditing }
        set { vault.isEditing = newValue }
    }
    public var editingDraft: String {
        get { vault.editingDraft }
        set { vault.editingDraft = newValue }
    }
    public var noteIsDirty: Bool { vault.noteIsDirty }
    public var externalChangeDetected: Bool {
        get { vault.externalChangeDetected }
        set { vault.externalChangeDetected = newValue }
    }
    public var showNotePicker: Bool {
        get { vault.showNotePicker }
        set { vault.showNotePicker = newValue }
    }
    public var notePickerQuery: String {
        get { vault.notePickerQuery }
        set { vault.notePickerQuery = newValue }
    }
    public var disambigCandidates: [VaultNode] {
        get { vault.disambigCandidates }
        set { vault.disambigCandidates = newValue }
    }
    public var disambigOriginalName: String {
        get { vault.disambigOriginalName }
        set { vault.disambigOriginalName = newValue }
    }
    public var showDisambigSheet: Bool {
        get { vault.showDisambigSheet }
        set { vault.showDisambigSheet = newValue }
    }
    public var editorSplitMode: EditorSplitMode = .editor

    public var showCreateNoteSheet: Bool {
        get { vault.showCreateNoteSheet }
        set { vault.showCreateNoteSheet = newValue }
    }
    public var favoriteNotePaths: Set<String> {
        get { vault.favorites }
        set { vault.favorites = newValue }
    }
    public var recentNotePaths: [String] {
        get { vault.recents }
        set { vault.recents = newValue }
    }

    // 도움말 sheet (C1)
    public var showShortcutHelp: Bool = false

    // ADR-042 R3.1 — TerminalSessionCoordinator 추출. AppModel은 facade 유지 (호출자 변경 X).
    public let terminals: TerminalSessionCoordinator = TerminalSessionCoordinator()

    // Facade pass-throughs — 기존 호출자 (RootView 등) 변경 없이 동작
    public var showTerminalPane: Bool {
        get { terminals.showPane }
        set { terminals.showPane = newValue }
    }
    public var terminalSessions: [TerminalSession] {
        get { terminals.sessions }
        set { terminals.sessions = newValue }
    }
    public var activeTerminalSessionId: UUID? {
        get { terminals.activeSessionId }
        set { terminals.activeSessionId = newValue }
    }
    public var terminalRenameTargetId: UUID? {
        get { terminals.renameTargetId }
        set { terminals.renameTargetId = newValue }
    }
    public var terminalSplitEnabled: Bool {
        get { terminals.splitEnabled }
        set { terminals.splitEnabled = newValue }
    }
    public var secondaryTerminalSessionId: UUID? {
        get { terminals.secondarySessionId }
        set { terminals.secondarySessionId = newValue }
    }

    // Preview pane (ADR-034 A4 + ADR-036 C1 live ping)
    public var showPreviewPane: Bool = false
    public var previewURLText: String = ""
    /// Detected dev server suggestions with live ping results.
    public var devServerSuggestions: [DevServerDetector.Suggestion] = []
    private var lastDevServerRefresh: Date = .distantPast

    // Command Runner Pane (ADR-036 C4 Warp-style block UX 단순화)
    // ADR-042 R3.3 — CommandRunnerCoordinator 추출. AppModel facade.
    public let commands: CommandRunnerCoordinator = CommandRunnerCoordinator()

    public var showCommandRunnerPane: Bool {
        get { commands.showPane }
        set { commands.showPane = newValue }
    }
    public var commandBlocks: [CommandRunner.CommandResult] {
        get { commands.blocks }
        set { commands.blocks = newValue }
    }
    public var isCommandRunning: Bool {
        get { commands.isRunning }
        set { commands.isRunning = newValue }
    }

    // ADR-042 R3.2 — WorkspaceFileManager 추출. AppModel은 facade 유지 (호출자 변경 X).
    public let files: WorkspaceFileManager = WorkspaceFileManager()

    // Facade pass-throughs
    public var workspaceFileTree: [FileNode] {
        get { files.tree }
        set { files.tree = newValue }
    }
    public var openFileTabs: [FileTab] {
        get { files.openTabs }
        set { files.openTabs = newValue }
    }
    public var activeFileTabId: UUID? {
        get { files.activeTabId }
        set { files.activeTabId = newValue }
    }
    public var showFileSearchSheet: Bool {
        get { files.showSearchSheet }
        set { files.showSearchSheet = newValue }
    }
    public var fileNameSheetIntent: FileNameSheetIntent? {
        get { files.nameSheetIntent }
        set { files.nameSheetIntent = newValue }
    }
    public var fileDeleteConfirmation: FileDeleteConfirmation? {
        get { files.deleteConfirmation }
        set { files.deleteConfirmation = newValue }
    }
    /// ADR-049 — ProjectProfile 편집 sheet 대상 워크스페이스 id (nil이면 닫힘)
    public var editingProjectProfileForWorkspaceId: UUID?
    /// ADR-051 — ⌘K Command Palette 표시 여부
    public var showCommandPalette: Bool = false
    /// ADR-051 — Walk-through view 대상 task id (nil이면 닫힘)
    public var walkthroughTaskId: UUID?
    /// ADR-051 — Harness 도움말 sheet
    public var showHarnessHelp: Bool = false
    /// ADR-052 — Routing Decision Log viewer sheet
    public var showRoutingLog: Bool = false
    /// **ADR-061 Phase 1** — SwiftUI Charts dashboard sheet
    public var showChartsDashboard: Bool = false
    /// **ADR-068 Phase 2** — About sheet
    public var showAbout: Bool = false
    /// **ADR-068 Phase 3** — Splash screen visible
    public var showSplash: Bool = true
    /// 첫 실행 여부 (UserDefaults)
    public var isFirstLaunch: Bool = {
        let key = "yuminai.firstLaunchCompleted"
        let prev = UserDefaults.standard.bool(forKey: key)
        if !prev {
            UserDefaults.standard.set(true, forKey: key)
            return true
        }
        return false
    }()
    /// **ADR-062 Phase 6** — Telegram usage dashboard sheet
    public var showTelegramUsageDashboard: Bool = false
    /// **ADR-062 Phase 3** — Chat binding audit log viewer sheet
    public var showChatBindingAuditLog: Bool = false
    /// **ADR-104** — 첫 실행 setup wizard sheet 표시 여부.
    public var showSetupWizard: Bool = false
    /// **ADR-104** — 각 도구의 설치 상태 캐시.
    public var setupToolStatus: [SetupTool: SetupChecker.InstallStatus] = [:]
    /// **ADR-104** — 설치 상태 검사 actor.
    public let setupChecker: SetupChecker = SetupChecker()
    /// ADR-052 — Walk-through rehearsal sheet 대상 task id (nil이면 닫힘)
    public var rehearsalTaskId: UUID?
    public var selectedFilePaths: Set<String> {
        get { files.selectedPaths }
        set { files.selectedPaths = newValue }
    }
    public var inlineRenameTargetPath: String? {
        get { files.inlineRenamePath }
        set { files.inlineRenamePath = newValue }
    }
    public var activeFileTab: FileTab? { files.activeTab }
    /// active tab의 path (legacy alias — ADR-042 R3.2 정리에도 호환을 위해 유지)
    public var selectedFilePath: String? { files.activeTab?.path }
    public var selectedFileContents: String? { files.activeTab?.savedContents }
    public var isEditingWorkspaceFile: Bool { files.activeTab?.isEditing ?? false }
    public var workspaceFileDraft: String {
        get { files.activeDraft }
        set { files.activeDraft = newValue }
    }
    public var isWorkspaceFileDirty: Bool { files.activeTab?.isDirty ?? false }

    // Delivery sheet (ADR-029 phase B)
    public var showDeliverySheet: Bool = false
    public var deliverySheetTargetWorkspaceId: UUID?

    // Pane rename sheet (ADR-032 U3)
    public var renameSheetPane: AgentPane?

    // Multi-pane split layout (ADR-032 U4)
    public var paneSplitMode: PaneSplitMode = .single

    // Agent chain state (ADR-034 A1) — coord facade
    public var agentChainHops: Int {
        get { panes.chainHops }
        set { panes.chainHops = newValue }
    }
    public var agentChainVisited: Set<UUID> {
        get { panes.chainVisited }
        set { panes.chainVisited = newValue }
    }
    public var agentChainActive: Bool { panes.chainActive }

    // Diff review state (ADR-027 phase A2/A3)
    public var pendingChanges: [ChangedFile] = []
    public var pendingDiff: String = ""
    public var hasPendingChanges: Bool { !pendingChanges.isEmpty }

    // Delivery loop state (ADR-029 phase B)
    // ADR-042 R3.5 — DeliveryCoordinator 추출. AppModel facade.
    public let delivery: DeliveryCoordinator = DeliveryCoordinator()

    public var deliveryResults: [DeliveryResult] {
        get { delivery.results }
        set { delivery.results = newValue }
    }
    public var isDeliveryRunning: Bool {
        get { delivery.isRunning }
        set { delivery.isRunning = newValue }
    }
    /// 다음 sendMessage에서 prompt 앞에 prepend할 실패 컨텍스트 (delivery로 위임).
    public var pendingFailureFeedback: String {
        get { delivery.pendingFailureFeedback }
        set { delivery.pendingFailureFeedback = newValue }
    }

    // ADR-042 R3.4 — AgentPaneCoordinator 추출 (state holder만, lifecycle/streaming 잔존)
    public let panes: AgentPaneCoordinator = AgentPaneCoordinator()

    /// ADR-047 Phase 2 — Harness 오케스트레이션 (다중 모델 컨텍스트 통합).
    /// 현재 Phase는 SharedConversationLog 기록 + 추천 모델 reads. 자동 routing은 Phase 3+.
    /// 호출자 변경 0건 — 기존 multi-pane이 그대로 동작 + harness는 추가 기능.
    public let harness: HarnessOrchestrator = HarnessOrchestrator()

    /// ADR-052 — Routing decision log store. App launch 시 recent N days 로드.
    /// applyHarnessAutoRoutingIfNeeded 호출 후 record append.
    public let routingLogStore: RoutingDecisionLogStore = RoutingDecisionLogStore()
    /// ADR-052 — recent routing decisions cache (UI 직접 binding용).
    /// `routingLogStore.cached()`와 sync 유지 — async refresh 후 setter.
    public var routingDecisions: [RoutingDecisionRecord] = []

    /// ADR-052 — Rehearsal store. task별 snapshot/run 영속.
    public let rehearsalStore: RehearsalStore = RehearsalStore()
    /// task id → in-memory rehearsal runs (UI 직접 binding용).
    public var rehearsalsByTask: [UUID: [RehearsalRun]] = [:]

    /// ADR-052 — Cost tracker (main / decomposition / rehearsal 분리).
    /// Aider architect_coder.py + Cline SubagentRunStats 패턴.
    public let costTracker: CostTracker = CostTracker()

    /// **ADR-055 #5** — Routing learning store (cancel된 keyword를 mute, 사용자 정의 keyword 추가).
    public let routingLearningStore: RoutingLearningStore = RoutingLearningStore()
    /// in-memory snapshot (UI binding용)
    public var routingLearningSnapshot: RoutingLearningStore.Snapshot = RoutingLearningStore.Snapshot(
        mutedKeywords: [],
        cancelCounts: [:],
        customKeywords: [:]
    )

    /// ADR-054 — 진행 중인 ChildClaudeProcess (decomposition/rehearsal/parallel) progress.
    /// UI가 spinner/badge 표시. 완료/실패 시 자동 prune (3초 후).
    public var activeChildProcesses: [ChildProcessProgress] = []

    /// ADR-052 — Command Palette pin/recent store (VSCode/Raycast 패턴).
    public let palettePinStore: PalettePinStore = PalettePinStore()
    /// in-memory cache (UI binding) — async store에서 snapshot으로 sync
    public var palettePinnedIds: [String] = []
    public var paletteRecentIds: [String] = []

    public var agentPanes: [AgentPane] {
        get { panes.panes }
        set { panes.panes = newValue }
    }
    public var activePaneId: UUID? {
        get { panes.activeId }
        set { panes.activeId = newValue }
    }
    /// pane별 보존 상태 (비활성 pane의 conversation 유지) — coord facade.
    /// active pane의 state는 self.messages / self.activeSettings / self.currentSessionUsage / currentClaudeSession에 직접 보유.
    public var paneMessages: [UUID: [Message]] {
        get { panes.messages }
        set { panes.messages = newValue }
    }
    public var paneSettings: [UUID: SessionSettings] {
        get { panes.settings }
        set { panes.settings = newValue }
    }
    public var paneUsage: [UUID: UsageStats] {
        get { panes.usage }
        set { panes.usage = newValue }
    }
    private var paneSessions: [UUID: any ClaudeStreamSession] = [:]

    public var activePane: AgentPane? {
        panes.activePane
    }

    private var vaultWatcher: VaultWatcher?
    private var watcherTask: Task<Void, Never>?
    private var fullTextSearchTask: Task<Void, Never>?

    // MARK: 내부
    private var streamConsumeTask: Task<Void, Never>?
    private var currentClaudeSession: (any ClaudeStreamSession)?
    private var telegramBot: (any TelegramClient)?
    private var alertDispatcher: TelegramAlertDispatcher?
    private var commandPump: TelegramCommandPump?
    private var sessionBridge: TelegramSessionBridge?
    private let checkpointManager = CheckpointManager()
    private let deliveryRunner = DeliveryRunner()
    /// **ADR-115 P1-2** — 다음 assistant 메시지에 붙일 attribution. sendMessage 시 캡처 → 응답 도착 시 소비.
    private var pendingAttribution: MessageAttribution?

    private let logger = Logger(subsystem: "com.yuminai", category: "AppModel")

    public init(
        workspaceStore: any WorkspaceStore,
        sessionStore: any SessionStore,
        keychainStore: any KeychainStore,
        preferencesStore: any AppPreferencesStore,
        claudeAdapter: any ClaudeAdapter,
        codexAdapter: (any ClaudeAdapter)? = nil,
        childProcess: (any ChildClaudeProcess)? = nil,
        preferences: AppPreferences
    ) {
        self.workspaceStore = workspaceStore
        self.sessionStore = sessionStore
        self.keychainStore = keychainStore
        self.preferencesStore = preferencesStore
        self.claudeAdapter = claudeAdapter
        self.codexAdapter = codexAdapter
        self.childProcess = childProcess
        self.preferences = preferences
        self.activeSettings = preferences.defaultSessionSettings
        self.showInspector = preferences.showInspectorByDefault
    }

    /// 워크스페이스의 agentKind에 맞는 어댑터 선택. codex 어댑터가 nil이면 claude로 fallback.
    public func adapter(for workspace: Workspace) -> any ClaudeAdapter {
        switch workspace.agentKind {
        case .claude: return claudeAdapter
        case .codex:  return codexAdapter ?? claudeAdapter
        }
    }

    /// 활성 워크스페이스의 어댑터.
    public var activeAdapter: any ClaudeAdapter {
        if let id = selectedWorkspaceId, let ws = workspaces.first(where: { $0.id == id }) {
            return adapter(for: ws)
        }
        return claudeAdapter
    }

    /// codex 어댑터 설정 + 워크스페이스에 codex 디렉토리 존재 여부.
    public var codexAvailable: Bool {
        codexAdapter != nil
            && FileManager.default.isExecutableFile(atPath: preferences.codexBinaryPath)
    }

    /// 활성 워크스페이스의 agent kind 변경 + 즉시 세션 재spawn.
    /// **ADR-087 Phase 1** — agent 전환 시 그 agent의 last-used settings로 자동 swap.
    /// 현재 settings는 이전 agent의 perAgentSettings에 저장 → 다음에 돌아와도 유지.
    public func setActiveAgentKind(_ kind: AgentKind) async {
        guard let id = selectedWorkspaceId,
              let workspace = workspaces.first(where: { $0.id == id }),
              workspace.agentKind != kind
        else { return }

        // ADR-087 Phase 1 — 현재 agent의 settings를 perAgentSettings에 보존
        // (다음에 그 agent로 돌아오면 같은 model/mode/effort로 복원)
        var newPerAgentSettings = workspace.perAgentSettings
        newPerAgentSettings[workspace.agentKind] = activeSettings

        // store에 영속 (agentKind + perAgentSettings 동시 업데이트)
        let updated = workspace
            .with(agentKind: kind)
            .with(perAgentSettings: newPerAgentSettings)
        do {
            try await workspaceStore.update(updated)
            if let idx = workspaces.firstIndex(where: { $0.id == id }) {
                workspaces[idx] = updated
            }
        } catch {
            self.error = "에이전트 변경 저장 실패: \(error.localizedDescription)"
            return
        }

        // ADR-087 Phase 1 — 새 agent의 last-used settings로 swap
        // (없으면 default — sonnet/default/medium)
        let newSettings = updated.settings(for: kind)
        activeSettings = newSettings
        await claudeAdapter.updateSettings(newSettings)

        // 현재 세션 종료 후 재spawn
        let prev = currentClaudeSession
        let prevAdapter = activeAdapter  // 변경 전 어댑터로 terminate
        streamConsumeTask?.cancel()
        streamConsumeTask = nil
        if let prev {
            await prevAdapter.terminate(prev)
        }
        currentClaudeSession = nil
        isStreaming = false

        do {
            let newAdapter = adapter(for: updated)
            let newSession = try await newAdapter.spawn(in: updated)
            currentClaudeSession = newSession
            let captured = newSession
            streamConsumeTask = Task { [weak self] in
                await self?.consumeStream(captured)
            }
        } catch {
            self.error = "에이전트 시작 실패: \(error.localizedDescription)"
        }
    }

    // MARK: - bootstrap

    public func bootstrap() async {
        await claudeAdapter.updateSettings(activeSettings)
        await refreshWorkspaces()
        await refreshSecretStatuses()
        await activateTelegramIfReady()
        await setupObsidianVault()
        // **ADR-098 P0-4** — macOS 알림 카테고리 등록 (HITL Approve/Reject 버튼)
        MacOSNotificationSender.registerCategories()
        // ADR-052 — routing decision log + palette pin/recent 로드
        await loadRoutingDecisionLog()
        await loadPalettePins()
        // ADR-055 #5 — routing learning snapshot 로드
        // ADR-061 Phase 3 — 자동 unmute (마지막 mute로부터 30일 지난 keyword)
        let unmuted = await routingLearningStore.performAutoUnmute()
        if !unmuted.isEmpty {
            harness.appendSystem("🤖 학습: 30일 이상 사용 안 된 mute keyword \(unmuted.count)개 자동 해제 — \(unmuted.joined(separator: ", "))")
        }
        routingLearningSnapshot = await routingLearningStore.snapshot()
        // ADR-060 Phase 1 — workspace daily cost 복원 (앱 재시작 보존)
        await loadPersistedDailyCosts()
        // ADR-062 Phase 6 — Telegram usage snapshot 로드
        await loadTelegramUsage()
        // ADR-104 — onboarding 완료 + setup 미완료 시 setup wizard 자동 표시
        if preferences.hasCompletedOnboarding && !preferences.hasCompletedSetup {
            await refreshSetupStatus()
            showSetupWizard = true
        }
    }

    // MARK: - Obsidian Vault

    public func setupObsidianVault() async {
        // 이전 watcher 정리
        watcherTask?.cancel()
        watcherTask = nil
        vaultWatcher?.stop()
        vaultWatcher = nil

        guard let path = preferences.obsidianVaultPath, !path.isEmpty else {
            obsidianVault = nil
            vaultTree = []
            selectedNote = nil
            favoriteNotePaths = []
            recentNotePaths = []
            return
        }
        let expanded = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        let vault = ObsidianVault(rootURL: url)
        obsidianVault = vault
        loadFavorites()
        await loadVaultTree()

        // file watcher 시작
        let watcher = VaultWatcher(rootURL: url)
        vaultWatcher = watcher
        watcher.start()

        let stream = watcher.changes
        watcherTask = Task { [weak self] in
            for await changes in stream {
                await self?.handleVaultChanges(changes)
            }
        }
    }

    private func handleVaultChanges(_ changes: Set<String>) async {
        // B7: 변경 path 캐시 무효화
        if let vault = obsidianVault {
            await vault.invalidateCache(paths: changes)
        }
        await loadVaultTree()
        // 현재 보고 있는 노트가 변경됐다면
        if let current = selectedNote, changes.contains(current.path) {
            if isEditingNote && noteIsDirty {
                externalChangeDetected = true
            } else {
                await selectNote(at: current.path)
            }
        }
    }

    public var vaultRootURL: URL? {
        obsidianVault?.rootURL
    }

    public func loadVaultTree() async {
        guard let vault = obsidianVault else {
            vaultTree = []
            return
        }
        do {
            vaultTree = try await vault.tree()
        } catch {
            self.error = error.localizedDescription
            vaultTree = []
        }
    }

    public func selectNote(at path: String) async {
        guard let vault = obsidianVault else { return }
        do {
            let note = try await vault.read(path)
            selectedNote = note
            editingDraft = note.body
            externalChangeDetected = false
            isEditingNote = false
            pushRecent(path)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Recents (C3)

    private func pushRecent(_ path: String) {
        recentNotePaths.removeAll { $0 == path }
        recentNotePaths.insert(path, at: 0)
        if recentNotePaths.count > 10 {
            recentNotePaths = Array(recentNotePaths.prefix(10))
        }
    }

    // MARK: - Favorites (C2)

    public func toggleFavorite(_ path: String) {
        if favoriteNotePaths.contains(path) {
            favoriteNotePaths.remove(path)
        } else {
            favoriteNotePaths.insert(path)
        }
        persistFavorites()
    }

    public func isFavorite(_ path: String) -> Bool {
        favoriteNotePaths.contains(path)
    }

    private func persistFavorites() {
        let key = "yuminai.favorites.\(preferences.obsidianVaultPath ?? "")"
        UserDefaults.standard.set(Array(favoriteNotePaths), forKey: key)
    }

    private func loadFavorites() {
        let key = "yuminai.favorites.\(preferences.obsidianVaultPath ?? "")"
        if let arr = UserDefaults.standard.array(forKey: key) as? [String] {
            favoriteNotePaths = Set(arr)
        }
    }

    public func clearSelectedNote() {
        selectedNote = nil
        isEditingNote = false
        editingDraft = ""
        externalChangeDetected = false
    }

    /// Wiki link 클릭 시 page 이름으로 노트 검색. 다수 매칭 시 disambig sheet.
    public func openNoteByName(_ name: String) async {
        guard let vault = obsidianVault else { return }
        do {
            let candidates = try await vault.findNotesByName(name)
            switch candidates.count {
            case 0:
                self.error = "‘\(name)’ 노트를 찾을 수 없어요"
            case 1:
                if case .note(_, let path, _) = candidates[0] {
                    inspectorTab = .notes
                    await selectNote(at: path)
                }
            default:
                disambigCandidates = candidates
                disambigOriginalName = name
                showDisambigSheet = true
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func selectDisambigCandidate(_ path: String) async {
        showDisambigSheet = false
        inspectorTab = .notes
        await selectNote(at: path)
    }

    /// MarkdownViewer가 호출 — 노트 임베드 미리보기 본문 head 반환.
    /// vaultRoot를 명시적으로 받음 (nonisolated, sync 호출 가능).
    public static func notePreviewBody(name: String, vaultRoot: URL?) -> String? {
        guard let root = vaultRoot else { return nil }
        let allFiles = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let q = name.lowercased()
        for url in allFiles where url.pathExtension.lowercased() == "md" {
            let n = url.deletingPathExtension().lastPathComponent.lowercased()
            if n == q {
                return try? String(contentsOf: url, encoding: .utf8)
            }
        }
        return nil
    }

    private static func flattenForSearch(_ node: VaultNode) -> [VaultNode] {
        switch node {
        case .note: return [node]
        case .folder(_, _, let children): return children.flatMap(Self.flattenForSearch)
        }
    }

    // MARK: - 본문 검색

    public func runFullTextSearch() async {
        guard let vault = obsidianVault else {
            noteFullTextHits = []
            return
        }
        guard !noteSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            noteFullTextHits = []
            return
        }
        do {
            noteFullTextHits = try await vault.searchFullText(noteSearchQuery, limit: 50)
        } catch {
            noteFullTextHits = []
        }
    }

    public func updateSearchQuery(_ q: String) {
        noteSearchQuery = q
        if noteFullTextEnabled {
            fullTextSearchTask?.cancel()
            fullTextSearchTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                await self?.runFullTextSearch()
            }
        }
    }

    public func toggleFullTextSearch(_ enabled: Bool) {
        noteFullTextEnabled = enabled
        if enabled {
            Task { await runFullTextSearch() }
        } else {
            noteFullTextHits = []
        }
    }

    // MARK: - 편집 모드

    public func startEditingNote() {
        guard let note = selectedNote else { return }
        editingDraft = note.body
        isEditingNote = true
    }

    public func saveNote() async {
        guard let vault = obsidianVault, let note = selectedNote else { return }
        do {
            try await vault.write(note.path, content: editingDraft)
            // selectedNote도 갱신
            let updated = Note(
                path: note.path,
                title: note.title,
                body: editingDraft,
                frontmatter: note.frontmatter,
                lastModified: Date()
            )
            selectedNote = updated
            externalChangeDetected = false
        } catch {
            self.error = "저장 실패: \(error.localizedDescription)"
        }
    }

    public func discardEdits() {
        guard let note = selectedNote else {
            isEditingNote = false
            editingDraft = ""
            return
        }
        editingDraft = note.body
        isEditingNote = false
    }

    public func reloadNoteFromDisk() async {
        guard let path = selectedNote?.path else { return }
        await selectNote(at: path)
    }

    // MARK: - @note 첨부

    public func attachNoteByPath(_ relativePath: String) {
        guard let root = obsidianVault?.rootURL else { return }
        let url = root.appending(path: relativePath)
        if !attachedFiles.contains(url) {
            attachedFiles.append(url)
        }
    }

    // MARK: - 노트 CRUD (B5)

    public func createNote(filename: String, title: String?, folder: String) async {
        guard let vault = obsidianVault else { return }
        let safeName = filename.hasSuffix(".md") ? filename : "\(filename).md"
        let folderPath = folder.trimmingCharacters(in: .init(charactersIn: "/ "))
        let relPath = folderPath.isEmpty ? safeName : "\(folderPath)/\(safeName)"
        do {
            let note = try await vault.createNote(at: relPath, title: title)
            await loadVaultTree()
            inspectorTab = .notes
            selectedNote = note
            editingDraft = note.body
            isEditingNote = true  // 즉시 편집 모드
            showCreateNoteSheet = false
            pushRecent(relPath)
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func deleteNote(at path: String) async {
        guard let vault = obsidianVault else { return }
        do {
            try await vault.deleteNote(at: path)
            await loadVaultTree()
            if selectedNote?.path == path {
                clearSelectedNote()
            }
            recentNotePaths.removeAll { $0 == path }
            favoriteNotePaths.remove(path)
            persistFavorites()
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func openCurrentNoteInObsidian() {
        guard let vault = obsidianVault, let note = selectedNote else { return }
        vault.openInObsidian(relativePath: note.path)
    }

    public var isVaultConfigured: Bool {
        obsidianVault != nil
    }

    public func refreshWorkspaces() async {
        do {
            workspaces = try await workspaceStore.list()
            if selectedWorkspaceId == nil {
                selectedWorkspaceId = workspaces.first?.id
                if let first = workspaces.first {
                    await selectWorkspace(first.id)
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func refreshSecretStatuses() async {
        anthropicKeyStatus = await secretStatus(for: KeychainKey.anthropicAPIKey)
        telegramTokenStatus = await secretStatus(for: KeychainKey.telegramBotToken)
    }

    private func secretStatus(for key: String) async -> SecretStatus {
        do {
            return try await keychainStore.get(key) != nil ? .set : .notSet
        } catch {
            return .error(error.localizedDescription)
        }
    }

    // MARK: - workspace

    public func createWorkspace(_ workspace: Workspace) async {
        do {
            try await workspaceStore.create(workspace)
            await refreshWorkspaces()
            selectedWorkspaceId = workspace.id
            await selectWorkspace(workspace.id)
            showCreateWorkspaceSheet = false
            // ADR-106 — 새 워크스페이스에 USER_PROFILE.md 즉시 주입
            await syncUserProfileTo(workspaceURL: URL(fileURLWithPath: workspace.directoryPath))
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func deleteWorkspace(_ workspace: Workspace) async {
        do {
            try await workspaceStore.delete(workspace.id)
            if selectedWorkspaceId == workspace.id {
                await teardownCurrentSession()
                selectedWorkspaceId = nil
            }
            // ADR-076 — 삭제된 워크스페이스를 핀/폴더에서도 제거 (orphan 방지)
            preferences.pinnedWorkspaceIds.removeAll { $0 == workspace.id }
            for idx in preferences.workspaceFolders.indices {
                preferences.workspaceFolders[idx].workspaceIds.removeAll { $0 == workspace.id }
            }
            // ADR-078 Phase 4 — Tag assignment에서도 제거
            preferences.tagAssignments.removeAllAssignments(for: workspace.id)
            await savePreferences()
            await refreshWorkspaces()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - ADR-076 Phase 2 — Pin + Folder management

    /// 워크스페이스가 핀되어 있는지.
    public func isPinned(_ workspaceId: UUID) -> Bool {
        preferences.pinnedWorkspaceIds.contains(workspaceId)
    }

    /// 핀 토글 (이미 핀이면 해제, 아니면 추가).
    public func togglePin(_ workspaceId: UUID) async {
        if let idx = preferences.pinnedWorkspaceIds.firstIndex(of: workspaceId) {
            preferences.pinnedWorkspaceIds.remove(at: idx)
        } else {
            preferences.pinnedWorkspaceIds.append(workspaceId)
        }
        await savePreferences()
    }

    /// 워크스페이스가 속한 폴더 (없으면 nil).
    public func folder(containing workspaceId: UUID) -> WorkspaceFolder? {
        preferences.workspaceFolders.first { $0.workspaceIds.contains(workspaceId) }
    }

    /// 새 폴더 생성. 이름은 사용자가 입력.
    public func createFolder(name: String, iconName: String = "folder.fill", colorName: String = "accent") async -> UUID {
        let folder = WorkspaceFolder(name: name, iconName: iconName, colorName: colorName)
        preferences.workspaceFolders.append(folder)
        await savePreferences()
        return folder.id
    }

    /// 폴더 이름 변경.
    public func renameFolder(id: UUID, to newName: String) async {
        guard let idx = preferences.workspaceFolders.firstIndex(where: { $0.id == id }) else {
            return
        }
        preferences.workspaceFolders[idx].name = newName
        await savePreferences()
    }

    /// **ADR-077 Phase 2** — 폴더 편집 (이름 + 아이콘 + 색상 한 번에).
    public func updateFolder(id: UUID, name: String, iconName: String, colorName: String) async {
        guard let idx = preferences.workspaceFolders.firstIndex(where: { $0.id == id }) else {
            return
        }
        preferences.workspaceFolders[idx].name = name
        preferences.workspaceFolders[idx].iconName = iconName
        preferences.workspaceFolders[idx].colorName = colorName
        await savePreferences()
    }

    // MARK: - ADR-077 Phase 4 — Pin reorder

    /// 핀 그룹에서 워크스페이스 위치 이동 (drag reorder 또는 menu).
    /// - Parameter offset: +1 = 아래로, -1 = 위로
    public func reorderPin(_ workspaceId: UUID, offset: Int) async {
        guard let currentIdx = preferences.pinnedWorkspaceIds.firstIndex(of: workspaceId) else { return }
        let newIdx = max(0, min(preferences.pinnedWorkspaceIds.count - 1, currentIdx + offset))
        guard newIdx != currentIdx else { return }
        let item = preferences.pinnedWorkspaceIds.remove(at: currentIdx)
        preferences.pinnedWorkspaceIds.insert(item, at: newIdx)
        await savePreferences()
    }

    // MARK: - ADR-077 Phase 3 — Smart folders

    /// Smart folder 활성/비활성 토글.
    public func toggleSmartFolder(_ kind: SmartFolderKind) async {
        if preferences.enabledSmartFolders.contains(kind) {
            preferences.enabledSmartFolders.remove(kind)
        } else {
            preferences.enabledSmartFolders.insert(kind)
        }
        await savePreferences()
    }

    /// 특정 smart folder에 부합하는 워크스페이스 IDs (현재 시점 계산).
    public func workspaceIds(in smartFolder: SmartFolderKind) -> [UUID] {
        switch smartFolder {
        case .recentWeek:
            return workspaces
                .filter { SmartFolderEvaluator.isRecent(lastOpenedAt: $0.lastOpenedAt) }
                .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
                .map { $0.id }
        case .telegramBound:
            return workspaces
                .filter {
                    SmartFolderEvaluator.isTelegramBound(
                        workspaceId: $0.id,
                        boundId: preferences.telegramBoundWorkspaceId,
                        chatBindings: preferences.telegramChatBindings
                    )
                }
                .map { $0.id }
        case .archived:
            return workspaces.filter { $0.isArchived }.map { $0.id }
        }
    }

    /// **ADR-077 Phase 4** — Pin 그룹에서 specific index로 이동 (drag-to-position).
    public func movePin(_ workspaceId: UUID, to targetIndex: Int) async {
        guard let currentIdx = preferences.pinnedWorkspaceIds.firstIndex(of: workspaceId) else { return }
        let item = preferences.pinnedWorkspaceIds.remove(at: currentIdx)
        let clampedIdx = max(0, min(preferences.pinnedWorkspaceIds.count, targetIndex))
        preferences.pinnedWorkspaceIds.insert(item, at: clampedIdx)
        await savePreferences()
    }

    // MARK: - ADR-078 Phase 2 — Folder reorder

    /// 폴더 자체 순서 변경 (drag 또는 menu).
    public func moveFolder(_ folderId: UUID, to targetIndex: Int) async {
        guard let currentIdx = preferences.workspaceFolders.firstIndex(where: { $0.id == folderId }) else { return }
        let item = preferences.workspaceFolders.remove(at: currentIdx)
        // remove 후 인덱스 보정 (앞쪽이 비워졌으니 -1)
        let adjustedTarget = currentIdx < targetIndex ? targetIndex - 1 : targetIndex
        let clampedIdx = max(0, min(preferences.workspaceFolders.count, adjustedTarget))
        preferences.workspaceFolders.insert(item, at: clampedIdx)
        await savePreferences()
    }

    /// 폴더 1칸 위/아래 이동 (context menu).
    public func reorderFolder(_ folderId: UUID, offset: Int) async {
        guard let currentIdx = preferences.workspaceFolders.firstIndex(where: { $0.id == folderId }) else { return }
        let newIdx = max(0, min(preferences.workspaceFolders.count - 1, currentIdx + offset))
        guard newIdx != currentIdx else { return }
        let item = preferences.workspaceFolders.remove(at: currentIdx)
        preferences.workspaceFolders.insert(item, at: newIdx)
        await savePreferences()
    }

    // MARK: - ADR-078 Phase 4 — Tag CRUD + assignment + filter

    /// 새 태그 생성. 이미 같은 이름이 있으면 기존 ID 반환 (idempotent).
    public func createTag(name: String, colorName: String = "blue") async -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let existing = preferences.workspaceTags.first(where: { $0.name == trimmed }) {
            return existing.id
        }
        let tag = WorkspaceTag(name: trimmed, colorName: colorName)
        preferences.workspaceTags.append(tag)
        await savePreferences()
        return tag.id
    }

    /// 태그 이름/색상 변경.
    public func updateTag(id: UUID, name: String, colorName: String) async {
        guard let idx = preferences.workspaceTags.firstIndex(where: { $0.id == id }) else { return }
        preferences.workspaceTags[idx].name = name.trimmingCharacters(in: .whitespaces)
        preferences.workspaceTags[idx].colorName = colorName
        await savePreferences()
    }

    /// 태그 삭제 (모든 워크스페이스에서 해당 태그도 자동 제거).
    public func deleteTag(id: UUID) async {
        preferences.workspaceTags.removeAll { $0.id == id }
        preferences.tagAssignments.removeTagEverywhere(id)
        preferences.activeTagFilters.remove(id)
        await savePreferences()
    }

    /// 워크스페이스에 태그 추가/제거 (toggle).
    public func toggleTag(_ tagId: UUID, on workspaceId: UUID) async {
        let current = preferences.tagAssignments.tags(for: workspaceId)
        if current.contains(tagId) {
            preferences.tagAssignments.remove(tag: tagId, from: workspaceId)
        } else {
            preferences.tagAssignments.add(tag: tagId, to: workspaceId)
        }
        await savePreferences()
    }

    /// 사이드바 tag 필터 토글 (활성화된 tag intersection으로 워크스페이스 필터링).
    public func toggleTagFilter(_ tagId: UUID) async {
        if preferences.activeTagFilters.contains(tagId) {
            preferences.activeTagFilters.remove(tagId)
        } else {
            preferences.activeTagFilters.insert(tagId)
        }
        await savePreferences()
    }

    /// 모든 tag 필터 해제.
    public func clearTagFilters() async {
        preferences.activeTagFilters.removeAll()
        await savePreferences()
    }

    /// 활성 tag 필터에 부합하는 워크스페이스 ID set.
    /// 빈 필터 = 전체 통과 (nil 반환).
    public func filteredWorkspaceIds() -> Set<UUID>? {
        guard !preferences.activeTagFilters.isEmpty else { return nil }
        // intersection: 활성된 tag 모두 가진 워크스페이스
        var result: Set<UUID>?
        for tagId in preferences.activeTagFilters {
            let wsIds = Set(preferences.tagAssignments.workspaces(withTag: tagId))
            if let existing = result {
                result = existing.intersection(wsIds)
            } else {
                result = wsIds
            }
        }
        return result ?? []
    }

    // MARK: - ADR-078 Phase 5 — Workspace import/export

    /// 현재 상태로 archive 생성 (export 직전 호출).
    public func makeArchive() -> WorkspaceArchive {
        WorkspaceArchive(
            workspaces: workspaces,
            folders: preferences.workspaceFolders,
            pinnedWorkspaceIds: preferences.pinnedWorkspaceIds,
            tags: preferences.workspaceTags,
            tagAssignments: preferences.tagAssignments,
            enabledSmartFolders: preferences.enabledSmartFolders
        )
    }

    /// Archive를 import (사용자가 strategy 선택).
    public func importArchive(_ archive: WorkspaceArchive, strategy: WorkspaceImportStrategy) async -> WorkspaceImportResult {
        var result = WorkspaceImportResult()

        // 기존 이름 → ID lookup
        let existingByName: [String: UUID] = Dictionary(workspaces.map { ($0.name, $0.id) }, uniquingKeysWith: { a, _ in a })

        // ID 재매핑 (mergeAll 또는 replaceExisting 일 때 새 UUID 사용)
        var idRemap: [UUID: UUID] = [:]

        for ws in archive.workspaces {
            if let existingId = existingByName[ws.name] {
                switch strategy {
                case .skipExisting:
                    idRemap[ws.id] = existingId
                    result.workspacesSkipped += 1
                case .replaceExisting:
                    do {
                        try await workspaceStore.delete(existingId)
                        let newWs = Workspace(
                            id: ws.id,
                            name: ws.name,
                            directoryPath: ws.directoryPath,
                            createdAt: ws.createdAt,
                            lastOpenedAt: ws.lastOpenedAt,
                            harnessTemplate: ws.harnessTemplate,
                            isArchived: ws.isArchived,
                            agentKind: ws.agentKind,
                            deliveryConfig: ws.deliveryConfig,
                            savedPanes: ws.savedPanes,
                            savedTerminalSessions: ws.savedTerminalSessions,
                            projectProfile: ws.projectProfile,
                            savedConversationLog: ws.savedConversationLog,
                            savedTasks: ws.savedTasks
                        )
                        try await workspaceStore.create(newWs)
                        idRemap[ws.id] = ws.id
                        result.workspacesReplaced += 1
                    } catch {
                        result.workspacesSkipped += 1
                    }
                case .mergeAll:
                    let newId = UUID()
                    let renamed = Workspace(
                        id: newId,
                        name: "\(ws.name) (가져옴)",
                        directoryPath: ws.directoryPath,
                        createdAt: ws.createdAt,
                        lastOpenedAt: ws.lastOpenedAt,
                        harnessTemplate: ws.harnessTemplate,
                        isArchived: ws.isArchived,
                        agentKind: ws.agentKind,
                        deliveryConfig: ws.deliveryConfig,
                        savedPanes: ws.savedPanes,
                        savedTerminalSessions: ws.savedTerminalSessions,
                        projectProfile: ws.projectProfile,
                        savedConversationLog: ws.savedConversationLog,
                        savedTasks: ws.savedTasks
                    )
                    do {
                        try await workspaceStore.create(renamed)
                        idRemap[ws.id] = newId
                        result.workspacesAdded += 1
                    } catch {
                        result.workspacesSkipped += 1
                    }
                }
            } else {
                // 새 워크스페이스 — ID 그대로
                do {
                    try await workspaceStore.create(ws)
                    idRemap[ws.id] = ws.id
                    result.workspacesAdded += 1
                } catch {
                    result.workspacesSkipped += 1
                }
            }
        }

        // 폴더 import (워크스페이스 ID 재매핑 적용)
        for archiveFolder in archive.folders {
            // 같은 이름의 폴더가 이미 있으면 skip (folder는 항상 안전)
            if preferences.workspaceFolders.contains(where: { $0.name == archiveFolder.name }) {
                continue
            }
            let remappedIds = archiveFolder.workspaceIds.compactMap { idRemap[$0] }
            let newFolder = WorkspaceFolder(
                id: UUID(),
                name: archiveFolder.name,
                workspaceIds: remappedIds,
                isExpanded: archiveFolder.isExpanded,
                iconName: archiveFolder.iconName,
                colorName: archiveFolder.colorName
            )
            preferences.workspaceFolders.append(newFolder)
            result.foldersAdded += 1
        }

        // 핀 import (재매핑된 ID, 기존과 중복은 제외)
        let existingPins = Set(preferences.pinnedWorkspaceIds)
        for pinId in archive.pinnedWorkspaceIds {
            if let remapped = idRemap[pinId], !existingPins.contains(remapped) {
                preferences.pinnedWorkspaceIds.append(remapped)
            }
        }

        // 태그 import (이름 중복 = 같은 태그로 간주, mergeAll)
        var tagIdRemap: [UUID: UUID] = [:]
        for archiveTag in archive.tags {
            if let existing = preferences.workspaceTags.first(where: { $0.name == archiveTag.name }) {
                tagIdRemap[archiveTag.id] = existing.id
            } else {
                let newTag = WorkspaceTag(
                    id: UUID(),
                    name: archiveTag.name,
                    colorName: archiveTag.colorName
                )
                preferences.workspaceTags.append(newTag)
                tagIdRemap[archiveTag.id] = newTag.id
                result.tagsAdded += 1
            }
        }

        // 태그 assignment 재매핑 + import
        for (oldWsId, oldTagIds) in archive.tagAssignments.workspaceToTags {
            guard let newWsId = idRemap[oldWsId] else { continue }
            for oldTagId in oldTagIds {
                if let newTagId = tagIdRemap[oldTagId] {
                    preferences.tagAssignments.add(tag: newTagId, to: newWsId)
                }
            }
        }

        // Smart folder 활성화 union
        preferences.enabledSmartFolders.formUnion(archive.enabledSmartFolders)

        await savePreferences()
        await refreshWorkspaces()
        return result
    }

    /// 사용자에게 export 위치 선택 dialog 표시 + 파일 저장.
    public func exportArchiveToFile() async {
        let archive = makeArchive()
        do {
            let data = try archive.toJSON()
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "yuminai-workspaces-\(Self.exportTimestamp()).yuminai.json"
            panel.title = "워크스페이스 백업 저장"
            panel.message = "워크스페이스 + 폴더 + 핀 + 태그 메타데이터를 JSON으로 저장합니다."
            if panel.runModal() == .OK, let url = panel.url {
                try data.write(to: url)
                self.error = "백업 저장 완료: \(url.lastPathComponent)"  // 토스트 자리
            }
        } catch {
            self.error = "백업 저장 실패: \(error.localizedDescription)"
        }
    }

    /// 사용자에게 import file 선택 dialog 표시 + import (default strategy: skipExisting).
    public func importArchiveFromFile(strategy: WorkspaceImportStrategy = .skipExisting) async {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Yuminai 백업 가져오기"
        panel.message = "이전에 저장한 .yuminai.json 파일을 선택하세요."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let archive = try WorkspaceArchive.fromJSON(data)
            let result = await importArchive(archive, strategy: strategy)
            self.error = "가져오기 완료: \(result.summary)"
        } catch {
            self.error = "가져오기 실패: \(error.localizedDescription)"
        }
    }

    // MARK: - ADR-079 Phase 1 — Smart filter + Workspace duplicate

    /// 현재 active tag filter + folder를 named smart filter로 저장.
    public func saveCurrentAsSmartFilter(name: String, folderId: UUID? = nil, colorName: String = "accent") async -> UUID {
        let filter = SmartFilter(
            name: name.trimmingCharacters(in: .whitespaces),
            tagIds: preferences.activeTagFilters,
            folderId: folderId,
            colorName: colorName
        )
        preferences.smartFilters.append(filter)
        await savePreferences()
        return filter.id
    }

    /// Smart filter 적용 (tag 활성화 + folder 자동 expand).
    public func applySmartFilter(_ filterId: UUID) async {
        guard let filter = preferences.smartFilters.first(where: { $0.id == filterId }) else { return }
        preferences.activeTagFilters = filter.tagIds
        if let folderId = filter.folderId,
           let idx = preferences.workspaceFolders.firstIndex(where: { $0.id == folderId }) {
            preferences.workspaceFolders[idx].isExpanded = true
        }
        await savePreferences()
    }

    /// Smart filter 삭제.
    public func deleteSmartFilter(_ filterId: UUID) async {
        preferences.smartFilters.removeAll { $0.id == filterId }
        await savePreferences()
    }

    /// 워크스페이스 복제 (새 UUID, "(복사본)" suffix). 폴더/태그 assignment도 같이 복제.
    public func duplicateWorkspace(_ workspaceId: UUID) async {
        guard let original = workspaces.first(where: { $0.id == workspaceId }) else { return }
        let newWs = Workspace(
            id: UUID(),
            name: "\(original.name) (복사본)",
            directoryPath: original.directoryPath,
            createdAt: Date(),
            lastOpenedAt: nil,
            harnessTemplate: original.harnessTemplate,
            isArchived: false,
            agentKind: original.agentKind,
            deliveryConfig: original.deliveryConfig,
            savedPanes: [],  // 새 세션 (이전 채팅 X)
            savedTerminalSessions: [],
            projectProfile: original.projectProfile,
            savedConversationLog: [],
            savedTasks: []
        )
        do {
            try await workspaceStore.create(newWs)
            // 같은 폴더에 추가
            if let folder = preferences.workspaceFolders.first(where: { $0.workspaceIds.contains(workspaceId) }),
               let idx = preferences.workspaceFolders.firstIndex(where: { $0.id == folder.id }) {
                preferences.workspaceFolders[idx].workspaceIds.append(newWs.id)
            }
            // 같은 태그 적용
            let tagIds = preferences.tagAssignments.tags(for: workspaceId)
            for tagId in tagIds {
                preferences.tagAssignments.add(tag: tagId, to: newWs.id)
            }
            await savePreferences()
            await refreshWorkspaces()
            // 자동 선택
            await selectWorkspace(newWs.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - ADR-079 Phase 4-5 — Git integration (Claude Code 패턴 단순화)

    /// 현재 워크스페이스의 Git status를 새로 fetch (workspace 선택 시 + commit 후 호출).
    public func refreshGitStatus() async {
        guard let ws = workspaces.first(where: { $0.id == selectedWorkspaceId }) else {
            gitBranch = nil
            gitDirtyStats = nil
            return
        }
        let url = URL(fileURLWithPath: ws.directoryPath)
        let runner = GitRunner(workspaceURL: url)
        guard await runner.isRepository() else {
            gitBranch = nil
            gitDirtyStats = nil
            return
        }
        let manager = GitBranchManager(runner: runner)
        do {
            self.gitBranch = try await manager.currentBranch()
            self.gitDirtyStats = try await manager.dirtyStats()
            self.gitUpstream = try? await manager.upstreamStatus()
        } catch {
            self.gitBranch = nil
            self.gitDirtyStats = nil
            self.gitUpstream = nil
        }
    }

    /// 현재 워크스페이스의 GitBranchManager를 생성 (현재 워크스페이스가 git repo가 아니면 nil).
    public func makeGitManager() async -> GitBranchManager? {
        guard let ws = workspaces.first(where: { $0.id == selectedWorkspaceId }) else { return nil }
        let url = URL(fileURLWithPath: ws.directoryPath)
        let runner = GitRunner(workspaceURL: url)
        guard await runner.isRepository() else { return nil }
        return GitBranchManager(runner: runner)
    }

    /// 브랜치 전환.
    public func switchGitBranch(_ name: String) async {
        guard let manager = await makeGitManager() else { return }
        do {
            try await manager.switchBranch(name)
            await refreshGitStatus()
        } catch {
            self.error = "브랜치 전환 실패: \(error.localizedDescription)"
        }
    }

    /// 새 브랜치 생성.
    public func createGitBranch(_ name: String) async {
        guard let manager = await makeGitManager() else { return }
        do {
            try await manager.createBranch(name)
            await refreshGitStatus()
        } catch {
            self.error = "브랜치 생성 실패: \(error.localizedDescription)"
        }
    }

    /// 현재 변경사항 commit (auto-stage all + Co-Authored-By).
    public func commitChanges(message: String) async {
        guard let manager = await makeGitManager() else { return }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalMessage = trimmed.isEmpty
            ? AutoCommitMessageGenerator.generate(stats: gitDirtyStats ?? DirtyStats(modified: 0, added: 0, deleted: 0, untracked: 0))
            : trimmed
        do {
            let sha = try await manager.commitAll(message: finalMessage)
            self.error = "✓ 커밋 완료: \(sha) — \(finalMessage)"
            await refreshGitStatus()
        } catch {
            self.error = "커밋 실패: \(error.localizedDescription)"
        }
    }

    /// 현재 워크스페이스 브랜치 목록 (UI에서 사용).
    public func gitBranches() async -> [BranchInfo] {
        guard let manager = await makeGitManager() else { return [] }
        return (try? await manager.localBranches()) ?? []
    }

    // MARK: - ADR-081 Phase 1 — Push/Pull/Fetch

    /// fetch + status 갱신 (사용자 manual trigger 또는 commit 후 자동).
    public func gitFetch() async {
        guard let manager = await makeGitManager() else { return }
        gitOperationInProgress = true
        defer { gitOperationInProgress = false }
        do {
            try await manager.fetch()
            await refreshGitStatus()
        } catch {
            self.error = "Git fetch 실패: \(error.localizedDescription)"
        }
    }

    /// pull (rebase 모드, dirty면 throw).
    public func gitPull() async {
        guard let manager = await makeGitManager() else { return }
        gitOperationInProgress = true
        defer { gitOperationInProgress = false }
        do {
            try await manager.pull(rebase: true)
            await refreshGitStatus()
            self.error = "✓ Pull 완료"
        } catch {
            self.error = "Pull 실패: \(error.localizedDescription)"
        }
    }

    /// push (upstream 없으면 자동 -u).
    public func gitPush(force: Bool = false) async {
        guard let manager = await makeGitManager() else { return }
        gitOperationInProgress = true
        defer { gitOperationInProgress = false }
        do {
            try await manager.push(force: force)
            await refreshGitStatus()
            self.error = "✓ Push 완료"
        } catch {
            self.error = "Push 실패: \(error.localizedDescription)"
        }
    }

    // MARK: - ADR-081 Phase 4 — Stash

    public func gitStashes() async -> [StashInfo] {
        guard let manager = await makeGitManager() else { return [] }
        return (try? await manager.stashes()) ?? []
    }

    public func gitCreateStash(message: String) async {
        guard let manager = await makeGitManager() else { return }
        do {
            try await manager.createStash(message: message)
            await refreshGitStatus()
            self.error = "✓ Stash 저장됨"
        } catch {
            self.error = "Stash 실패: \(error.localizedDescription)"
        }
    }

    public func gitApplyStash(_ ref: String) async {
        guard let manager = await makeGitManager() else { return }
        do {
            try await manager.applyStash(ref)
            await refreshGitStatus()
        } catch {
            self.error = "Stash 적용 실패: \(error.localizedDescription)"
        }
    }

    public func gitPopStash(_ ref: String) async {
        guard let manager = await makeGitManager() else { return }
        do {
            try await manager.popStash(ref)
            await refreshGitStatus()
        } catch {
            self.error = "Stash pop 실패: \(error.localizedDescription)"
        }
    }

    public func gitDropStash(_ ref: String) async {
        guard let manager = await makeGitManager() else { return }
        do {
            try await manager.dropStash(ref)
        } catch {
            self.error = "Stash 삭제 실패: \(error.localizedDescription)"
        }
    }

    // MARK: - ADR-081 Phase 2 — AI-generated commit message

    /// 현재 git diff를 Claude에 보내 commit message 생성.
    /// `ChildClaudeProcess` 활용 — 격리 호출, costTracker 자동 추적.
    public func generateCommitMessageWithAI() async -> String? {
        guard let ws = workspaces.first(where: { $0.id == selectedWorkspaceId }) else { return nil }
        let url = URL(fileURLWithPath: ws.directoryPath)
        let runner = GitRunner(workspaceURL: url)
        guard await runner.isRepository() else { return nil }
        let diff = (try? await runner.diff()) ?? ""
        // diff가 너무 크면 truncate (token cost 방지)
        let truncated = String(diff.prefix(8000))
        guard !truncated.isEmpty else { return nil }
        guard let child = childProcess else { return nil }

        let prompt = """
        You are a Git commit message generator following Conventional Commits style.
        Read this diff and produce ONE concise Korean commit message (≤ 72 chars title).

        Format:
        - Use prefix: feat: / fix: / chore: / refactor: / docs: / test:
        - Title in Korean, ≤ 72 chars
        - NO body, NO multi-line, NO Co-Authored-By footer (system adds it)
        - Output ONLY the title line, nothing else

        Diff:
        ```
        \(truncated)
        ```
        """
        do {
            let output = try await child.runOnce(
                prompt: prompt,
                in: ws,
                agent: ws.agentKind,
                purpose: .rehearsal,  // 격리 호출 (메인 conversation 안 건드림)
                timeoutSeconds: 30,
                overrideSettings: nil
            )
            let message = output.resultText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\n")
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return message.isEmpty ? nil : message
        } catch {
            self.error = "AI 메시지 생성 실패: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - ADR-081 Phase 3 — GitHub PR creation

    /// 현재 워크스페이스의 GitHub gh runner.
    public func makeGitHubRunner() async -> GitHubCLIRunner? {
        guard let ws = workspaces.first(where: { $0.id == selectedWorkspaceId }) else { return nil }
        let url = URL(fileURLWithPath: ws.directoryPath)
        return GitHubCLIRunner(
            workspaceURL: url,
            runner: GitHubCLIRunner.makeRunWithCwd(url)
        )
    }

    /// Push + PR 생성 (Claude Code 패턴 — 한 번에).
    public func createPullRequest(title: String, body: String?, draft: Bool = false) async {
        gitOperationInProgress = true
        defer { gitOperationInProgress = false }
        // 1. Push 먼저
        guard let manager = await makeGitManager() else {
            self.error = "Git 저장소가 아니에요"
            return
        }
        do {
            try await manager.push(force: false)
        } catch {
            self.error = "Push 실패: \(error.localizedDescription)"
            return
        }
        // 2. PR 생성
        guard let gh = await makeGitHubRunner() else {
            self.error = "gh CLI를 찾을 수 없어요"
            return
        }
        do {
            let url = try await gh.createPullRequest(title: title, body: body, draft: draft)
            self.error = "✓ PR 생성됨: \(url)"
            // 사용자가 URL을 클릭하기 쉽게 — 자동으로 brower 안 열기 (privacy)
        } catch {
            self.error = "PR 생성 실패: \(error.localizedDescription)"
        }
    }

    /// 현재 브랜치에 이미 PR이 있는지 확인.
    public func existingPRForCurrentBranch() async -> String? {
        guard let gh = await makeGitHubRunner() else { return nil }
        return try? await gh.existingPullRequest()
    }

    // MARK: - ADR-082 Phase 2 — PR review

    public func loadPullRequestDetails() async -> PullRequestDetails? {
        guard let gh = await makeGitHubRunner() else { return nil }
        return try? await gh.pullRequestDetails()
    }

    // MARK: - ADR-082 Phase 3 — GitHub Actions

    public func loadRecentWorkflowRuns(limit: Int = 5) async -> [WorkflowRun] {
        guard let gh = await makeGitHubRunner() else { return [] }
        return (try? await gh.recentWorkflowRuns(limit: limit)) ?? []
    }

    /// 시스템 default browser로 URL 열기 (Apple HIG 표준).
    public func openInBrowser(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - ADR-082 Phase 4 — Rebase

    public func gitRecentCommits(limit: Int) async -> [CommitInfo] {
        guard let manager = await makeGitManager() else { return [] }
        return (try? await manager.recentCommits(limit: limit)) ?? []
    }

    public func gitRebase(count: Int, actions: [String: RebaseAction]) async {
        guard let manager = await makeGitManager() else { return }
        gitOperationInProgress = true
        defer { gitOperationInProgress = false }
        do {
            try await manager.rebase(count: count, actions: actions)
            await refreshGitStatus()
            self.error = "✓ Rebase 완료"
        } catch {
            self.error = "Rebase 실패: \(error.localizedDescription) — `git rebase --abort`로 취소 가능"
        }
    }

    public func gitRebaseAbort() async {
        guard let manager = await makeGitManager() else { return }
        do {
            try await manager.rebaseAbort()
            await refreshGitStatus()
        } catch {
            self.error = "Rebase abort 실패: \(error.localizedDescription)"
        }
    }

    // MARK: - ADR-082 Phase 5 — CodeOwners

    // MARK: - ADR-083 Phase 1 — Conflict resolution

    public func gitConflictedFiles() async -> [String] {
        guard let manager = await makeGitManager() else { return [] }
        return (try? await manager.conflictedFiles()) ?? []
    }

    public func gitConflictBlocks(in path: String) async -> [ConflictBlock] {
        guard let manager = await makeGitManager() else { return [] }
        return (try? await manager.conflictBlocks(in: path)) ?? []
    }

    public func gitResolveConflict(path: String, strategy: ConflictResolution) async {
        guard let manager = await makeGitManager() else { return }
        do {
            try await manager.resolveConflict(path: path, strategy: strategy)
            await refreshGitStatus()
            self.error = "✓ 충돌 해결: \(path) (\(strategy.displayName))"
        } catch {
            self.error = "충돌 해결 실패: \(error.localizedDescription)"
        }
    }

    public func gitMergeAbort() async {
        guard let manager = await makeGitManager() else { return }
        do {
            try await manager.mergeAbort()
            await refreshGitStatus()
            self.error = "✓ Merge 취소됨"
        } catch {
            self.error = "Merge abort 실패: \(error.localizedDescription)"
        }
    }

    // MARK: - ADR-083 Phase 2 — Cherry-pick

    public func gitCommitsOnBranch(_ branch: String, limit: Int = 30) async -> [CommitInfo] {
        guard let manager = await makeGitManager() else { return [] }
        return (try? await manager.commitsOnBranch(branch, limit: limit)) ?? []
    }

    public func gitCherryPick(_ sha: String) async {
        guard let manager = await makeGitManager() else { return }
        do {
            try await manager.cherryPick(sha)
            await refreshGitStatus()
            self.error = "✓ Cherry-pick 완료: \(sha)"
        } catch {
            self.error = "Cherry-pick 실패: \(error.localizedDescription) — 충돌 발생 시 충돌 해결 sheet 사용"
        }
    }

    // MARK: - ADR-083 Phase 3 — PR comment

    public func commentOnCurrentPR(body: String) async {
        guard let gh = await makeGitHubRunner() else { return }
        do {
            try await gh.commentOnPullRequest(body: body)
            self.error = "✓ PR 코멘트 추가됨"
        } catch {
            self.error = "PR 코멘트 실패: \(error.localizedDescription)"
        }
    }

    // MARK: - ADR-083 Phase 4 — Workflow re-run + Repo insights

    public func rerunWorkflow(runId: Int, failedOnly: Bool = false) async {
        guard let gh = await makeGitHubRunner() else { return }
        do {
            try await gh.rerunWorkflow(runId: runId, failedOnly: failedOnly)
            self.error = "✓ Workflow 재실행 시작"
        } catch {
            self.error = "Workflow 재실행 실패: \(error.localizedDescription)"
        }
    }

    public func loadTopContributors(limit: Int = 5) async -> [Contributor] {
        guard let gh = await makeGitHubRunner() else { return [] }
        return (try? await gh.topContributors(limit: limit)) ?? []
    }

    public func loadRepoInfo() async -> RepoInfo? {
        guard let gh = await makeGitHubRunner() else { return nil }
        return try? await gh.repoInfo()
    }

    /// 변경된 파일들의 suggested reviewers (`.github/CODEOWNERS` 기반).
    public func suggestedReviewers() async -> Set<String> {
        guard let ws = workspaces.first(where: { $0.id == selectedWorkspaceId }) else { return [] }
        let url = URL(fileURLWithPath: ws.directoryPath)
        let runner = GitRunner(workspaceURL: url)
        guard await runner.isRepository() else { return [] }
        let manager = GitBranchManager(runner: runner)
        let changedFiles = (try? await runner.changedFiles()) ?? []
        let paths = changedFiles.map { $0.path }
        return (try? await manager.suggestedReviewers(for: paths)) ?? []
    }

    private static func exportTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: Date())
    }

    /// 폴더 삭제 (안의 워크스페이스는 uncategorized로 이동, 삭제 X).
    public func deleteFolder(id: UUID) async {
        preferences.workspaceFolders.removeAll { $0.id == id }
        await savePreferences()
    }

    /// 폴더 expand/collapse 토글.
    public func toggleFolderExpansion(id: UUID) async {
        guard let idx = preferences.workspaceFolders.firstIndex(where: { $0.id == id }) else {
            return
        }
        preferences.workspaceFolders[idx].isExpanded.toggle()
        await savePreferences()
    }

    /// 워크스페이스를 폴더로 이동 (기존 폴더에서 자동 제거 후 새 폴더에 추가).
    /// folderId가 nil이면 모든 폴더에서 제거 (uncategorized로).
    public func moveWorkspace(_ workspaceId: UUID, toFolder folderId: UUID?) async {
        // 기존 모든 폴더에서 제거
        for idx in preferences.workspaceFolders.indices {
            preferences.workspaceFolders[idx].workspaceIds.removeAll { $0 == workspaceId }
        }
        // 새 폴더에 추가 (folderId가 있으면)
        if let folderId,
           let idx = preferences.workspaceFolders.firstIndex(where: { $0.id == folderId }) {
            preferences.workspaceFolders[idx].workspaceIds.append(workspaceId)
        }
        await savePreferences()
    }

    public func selectWorkspace(_ id: UUID?) async {
        await teardownCurrentSession()
        guard let id, let workspace = workspaces.first(where: { $0.id == id }) else {
            return
        }
        await startSession(in: workspace)
        // ADR-079 Phase 4 — 워크스페이스 진입 시 git status 자동 fetch
        await refreshGitStatus()
    }

    private func startSession(in workspace: Workspace) async {
        do {
            let session = Session(workspaceId: workspace.id)
            try await sessionStore.create(session)
            currentSession = session
            messages = []
            currentSessionUsage = .zero

            let agentAdapter = adapter(for: workspace)
            let claudeSession = try await agentAdapter.spawn(in: workspace)
            currentClaudeSession = claudeSession

            let captured = claudeSession
            streamConsumeTask = Task { [weak self] in
                await self?.consumeStream(captured)
            }

            // 멀티-pane: workspace 활성화 시 default primary pane 1개 자동 생성 (ADR-030)
            ensurePrimaryPane(for: workspace, session: claudeSession)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Multi-pane (ADR-030, M1 phase C)

    /// workspace 선택 시 호출 — savedPanes가 있으면 복원, 없으면 default primary 1개 자동 등록.
    /// 기존에 spawn한 session/messages를 primary(또는 첫 saved) pane state로 wrap.
    /// **session/messages는 영속 X** — pane 메타만 복원, conversation은 fresh.
    private func ensurePrimaryPane(for workspace: Workspace, session: any ClaudeStreamSession) {
        clearPaneState()

        if !workspace.savedPanes.isEmpty {
            // 영속된 panes 복원
            agentPanes = workspace.savedPanes
            // primary가 없으면 첫 pane을 promote
            if !agentPanes.contains(where: { $0.role == .primary }), let first = agentPanes.first {
                agentPanes[0] = first.with(role: .primary)
            }
            // active = 첫 primary (또는 첫 pane)
            let primary = agentPanes.first(where: { $0.role == .primary }) ?? agentPanes[0]
            activePaneId = primary.id
            paneSessions[primary.id] = session
            paneMessages[primary.id] = []
            paneSettings[primary.id] = primary.settings
            paneUsage[primary.id] = .zero
            // 다른 panes는 lazy spawn (setActivePane이 처리)
            for pane in agentPanes where pane.id != primary.id {
                paneMessages[pane.id] = []
                paneSettings[pane.id] = pane.settings
                paneUsage[pane.id] = .zero
            }
            // active pane의 settings를 activeSettings에 반영 (toolbar picker가 보여줘야 함)
            activeSettings = primary.settings
        } else {
            // 신규 워크스페이스 — default primary 1개
            let primary = AgentPane(
                agentKind: workspace.agentKind,
                settings: activeSettings,
                role: .primary
            )
            agentPanes = [primary]
            activePaneId = primary.id
            paneSessions[primary.id] = session
            paneMessages[primary.id] = []
            paneSettings[primary.id] = activeSettings
            paneUsage[primary.id] = .zero
            persistCurrentPanes()
        }
    }

    /// 워크스페이스 전환 시 영속된 터미널 세션 복원 (ADR-041 T13).
    /// activity는 .idle로 리셋, hasUnreadOutput=false. process는 SwiftTerm view spawn 시 새로.
    public func restoreTerminalSessionsFromWorkspace() {
        guard let workspace = currentWorkspace else {
            terminals.clearAll()
            return
        }
        terminals.restore(from: workspace.savedTerminalSessions)
    }

    /// ADR-043 R4 — 워크스페이스 전환 시 모든 cleanup/restore을 한 함수로 응집.
    /// 이전: RootView .task(id:)에서 closeAllFileTabs + refreshWorkspaceFileTree +
    ///       restoreTerminalSessionsFromWorkspace 분산 호출 + .onChange로 selectWorkspace 별도.
    /// 이후: 단일 진입점 — 순서/race 명확. 호출자는 RootView.onChange만.
    public func transitionToWorkspace(_ id: UUID?) async {
        // 1) 이전 workspace의 stale 파일 tab 정리 (dirty 보존)
        closeAllFileTabs()
        // 2) workspace 활성화 (없으면 noop)
        if id != selectedWorkspaceId {
            selectedWorkspaceId = id
        }
        // 3) 새 workspace의 file tree + terminal session 복원
        await refreshWorkspaceFileTree()
        restoreTerminalSessionsFromWorkspace()
        // 4) ADR-050 Phase 6 — harness conversation log + tasks 영속 복원
        if let workspace = currentWorkspace {
            harness.conversationLog = workspace.savedConversationLog
            harness.tasks = workspace.savedTasks
            // ADR-087 Phase 1 — workspace 전환 시 그 workspace의 (현재 agent용) settings로 swap
            // 새 workspace가 last-used가 다른 model이면 Composer가 즉시 반영
            let workspaceSettings = workspace.settings(for: workspace.agentKind)
            if workspaceSettings != activeSettings {
                activeSettings = workspaceSettings
                await claudeAdapter.updateSettings(workspaceSettings)
                if let codex = codexAdapter {
                    await codex.updateSettings(workspaceSettings)
                }
            }
        } else {
            harness.resetForWorkspace()
        }
        // 향후 추가: dev server suggestions refresh, mention scope reset 등
    }

    /// ADR-051 — Command Palette actions builder. caller (RootView)가 sheet에 전달.
    /// 새 action 추가는 여기서 — 워크스페이스/모델/task/harness/sheet 카테고리.
    /// **ADR-052** — actionId (stable string ID) 추가, pin/recent 추적용.
    public func buildCommandPaletteActions() -> [PaletteAction] {
        var actions: [PaletteAction] = []

        // Workspace switching
        for workspace in workspaces {
            actions.append(PaletteAction(
                actionId: "workspace.switch.\(workspace.id.uuidString)",
                category: "Workspace",
                title: "활성: \(workspace.name)",
                subtitle: workspace.directoryPath,
                icon: "folder",
                shortcut: nil,
                perform: { [weak self] in
                    Task { await self?.transitionToWorkspace(workspace.id) }
                }
            ))
        }

        // Model switching (active workspace의 panes)
        for pane in agentPanes {
            actions.append(PaletteAction(
                actionId: "model.switch.\(pane.agentKind.rawValue)",
                category: "Model",
                title: "전환: \(pane.agentKind.shortLabel)",
                subtitle: "활성 pane을 \(pane.agentKind.shortLabel)으로",
                icon: pane.agentKind == .codex ? "chevron.left.forwardslash.chevron.right" : "c.circle",
                shortcut: nil,
                perform: { [weak self] in
                    Task { _ = await self?.switchToPaneOfKind(pane.agentKind) }
                }
            ))
        }

        // Harness routing toggle
        actions.append(PaletteAction(
            actionId: "harness.toggle.routing",
            category: "Harness",
            title: preferences.harnessAutoRoutingEnabled ? "자동 routing 끄기" : "자동 routing 켜기",
            subtitle: "사용자 입력 keyword 기반 모델 자동 전환",
            icon: "arrow.left.arrow.right.circle",
            shortcut: nil,
            perform: { [weak self] in
                Task { @MainActor in
                    self?.preferences.harnessAutoRoutingEnabled.toggle()
                    await self?.savePreferences()
                }
            }
        ))

        // Inline mode toggle
        actions.append(PaletteAction(
            actionId: "harness.toggle.inlineMode",
            category: "Harness",
            title: preferences.harnessInlineModeEnabled ? "Inline mode 끄기 (multi-pane으로)" : "Inline mode 켜기 (단일 timeline)",
            subtitle: "메인 chat area를 Harness 통합 view로 교체",
            icon: "sparkles.rectangle.stack",
            shortcut: nil,
            perform: { [weak self] in
                Task { @MainActor in
                    self?.preferences.harnessInlineModeEnabled.toggle()
                    await self?.savePreferences()
                }
            }
        ))

        // ADR-052 — multi-agent parallel toggle
        actions.append(PaletteAction(
            actionId: "harness.toggle.parallel",
            category: "Harness",
            title: preferences.multiAgentParallelEnabled ? "병렬 실행 끄기" : "병렬 실행 켜기 (실험적)",
            subtitle: "TaskGraph의 dependency-free task를 두 pane에서 동시 실행 (BSP barrier)",
            icon: "rectangle.split.2x1",
            shortcut: nil,
            perform: { [weak self] in
                Task { @MainActor in
                    self?.preferences.multiAgentParallelEnabled.toggle()
                    await self?.savePreferences()
                }
            }
        ))

        // Decompose
        if !inputText.isEmpty {
            actions.append(PaletteAction(
                actionId: "harness.decompose.input",
                category: "Harness",
                title: "현재 입력 분해 (/decompose)",
                subtitle: "‘\(String(inputText.prefix(40)))…’를 sub-task로 분해",
                icon: "list.bullet.indent",
                shortcut: nil,
                perform: { [weak self] in
                    guard let self else { return }
                    let text = self.inputText
                    Task { _ = await self.decomposeUserTask(text) }
                }
            ))
        }

        // Run ready tasks
        for task in harness.readyTasks {
            actions.append(PaletteAction(
                actionId: "task.run.\(task.id.uuidString)",
                category: "Task",
                title: "▶ \(task.title)",
                subtitle: task.description,
                icon: "play.circle",
                shortcut: nil,
                perform: { [weak self] in
                    Task { await self?.runHarnessTask(task.id) }
                }
            ))
        }

        // ADR-052 — Parallel run all ready tasks
        if preferences.multiAgentParallelEnabled && harness.readyTasks.count >= 2 {
            actions.append(PaletteAction(
                actionId: "task.run.parallelAll",
                category: "Task",
                title: "▶▶ 모든 ready task 병렬 실행",
                subtitle: "\(harness.readyTasks.count)개 task — 두 pane에서 동시 (BSP barrier)",
                icon: "play.rectangle.on.rectangle",
                shortcut: nil,
                perform: { [weak self] in
                    Task { await self?.runReadyTasksInParallel() }
                }
            ))
        }

        // Sheets
        actions.append(PaletteAction(
            actionId: "sheet.harness.help",
            category: "Sheet",
            title: "Harness 도움말 (사용성)",
            subtitle: "단축키 / 명령 / 패턴 / FAQ — 친절한 cheatsheet",
            icon: "lightbulb",
            shortcut: nil,
            perform: { [weak self] in
                self?.presentExclusiveSheet { $0.showHarnessHelp = true }
            }
        ))
        actions.append(PaletteAction(
            actionId: "sheet.shortcut.help",
            category: "Sheet",
            title: "단축키 도움말",
            subtitle: "모든 단축키 리스트",
            icon: "questionmark.circle",
            shortcut: "⌘/",
            perform: { [weak self] in
                self?.presentExclusiveSheet { $0.showShortcutHelp = true }
            }
        ))
        actions.append(PaletteAction(
            actionId: "sheet.file.search",
            category: "Sheet",
            title: "파일 검색",
            subtitle: "워크스페이스 파일 fuzzy 검색",
            icon: "doc.text.magnifyingglass",
            shortcut: "⌘P",
            perform: { [weak self] in
                self?.presentExclusiveSheet { $0.showFileSearchSheet = true }
            }
        ))
        actions.append(PaletteAction(
            actionId: "sheet.usage.dashboard",
            category: "Sheet",
            title: "사용량 대시보드",
            subtitle: "전체 token/cost 통계",
            icon: "chart.bar",
            shortcut: "⌘D",
            perform: { [weak self] in
                self?.presentExclusiveSheet { $0.showUsageDashboard = true }
            }
        ))
        // ADR-052 — Routing decision log viewer
        actions.append(PaletteAction(
            actionId: "sheet.routing.log",
            category: "Sheet",
            title: "Routing Decision Log",
            subtitle: "자동 routing 결정 회고 + counterfactual",
            icon: "arrow.triangle.branch",
            shortcut: nil,
            perform: { [weak self] in
                self?.presentExclusiveSheet { $0.showRoutingLog = true }
            }
        ))
        // ADR-061 Phase 1 — Charts Dashboard 진입
        actions.append(PaletteAction(
            actionId: "sheet.charts.dashboard",
            category: "Sheet",
            title: "Charts Dashboard",
            subtitle: "8개 chart로 cost / cache / routing 시각화",
            icon: "chart.line.uptrend.xyaxis",
            shortcut: nil,
            perform: { [weak self] in
                self?.presentExclusiveSheet { $0.showChartsDashboard = true }
            }
        ))
        // ADR-062 Phase 6 — Telegram Usage Dashboard
        actions.append(PaletteAction(
            actionId: "sheet.telegram.usage",
            category: "Sheet",
            title: "Telegram 사용 통계",
            subtitle: "외부 turn / 토큰 / chat / 명령 빈도 시각화",
            icon: "paperplane.circle.fill",
            shortcut: nil,
            perform: { [weak self] in
                self?.presentExclusiveSheet { $0.showTelegramUsageDashboard = true }
            }
        ))
        // ADR-068 Phase 2 — About sheet
        actions.append(PaletteAction(
            actionId: "sheet.about",
            category: "Sheet",
            title: "About Yuminai",
            subtitle: "버전 + 로고 + ADR 통계 + credits",
            icon: "info.circle",
            shortcut: nil,
            perform: { [weak self] in
                self?.presentExclusiveSheet { $0.showAbout = true }
            }
        ))
        // ADR-062 Phase 3 — Chat Binding Audit Log Viewer
        actions.append(PaletteAction(
            actionId: "sheet.chat.audit",
            category: "Sheet",
            title: "Chat Binding Audit Log",
            subtitle: "bind/unbind/rebind 이력 회고",
            icon: "doc.text.magnifyingglass",
            shortcut: nil,
            perform: { [weak self] in
                self?.presentExclusiveSheet { $0.showChatBindingAuditLog = true }
            }
        ))

        return actions
    }

    // MARK: - ADR-052 Palette pin helpers

    /// 사용자 액션 실행 — recent 기록 + perform 호출.
    public func performPaletteAction(_ action: PaletteAction) async {
        if !action.actionId.isEmpty {
            await palettePinStore.recordUse(action.actionId)
            paletteRecentIds = await palettePinStore.recentIds(limit: 8)
        }
        action.perform()
    }

    /// Pin toggle.
    public func togglePalettePin(_ actionId: String) async {
        await palettePinStore.togglePin(actionId)
        let snap = await palettePinStore.snapshot()
        palettePinnedIds = snap.pinnedIds
    }

    /// 앱 시작 시 호출 — store에서 snapshot 로드.
    public func loadPalettePins() async {
        let snap = await palettePinStore.snapshot()
        palettePinnedIds = snap.pinnedIds
        paletteRecentIds = await palettePinStore.recentIds(limit: 8)
    }

    // MARK: - ADR-052 Multi-agent parallel execution

    /// **ADR-052** — TaskGraph의 ready task들을 두 pane에서 동시 실행.
    ///
    /// **출처/근거**:
    /// - LangGraph Pregel BSP superstep
    ///   (https://github.com/langchain-ai/langgraph/blob/main/libs/langgraph/langgraph/pregel/_loop.py)
    /// - CrewAI `Task(async_execution=True)` + `_execute_tasks()` futures barrier
    ///   (https://github.com/crewAIInc/crewAI/blob/main/lib/crewai/src/crewai/crew.py:1441-1510)
    /// - Cognition Devin "Don't Build Multi-Agents" — 병렬은 fragile, dependency-free한 task만
    ///   (https://cognition.ai/blog/dont-build-multi-agents)
    ///
    /// **알고리즘** (BSP barrier merge):
    /// 1. ready tasks 중 처음 2개 picking (현재 max 2 panes)
    /// 2. pane 부족 시 Cognition 권고 — serial fallback
    /// 3. 동시 dispatch (Task.detached + group)
    /// 4. 양쪽 완료 대기 (barrier)
    /// 5. 한 쪽 실패 시 — 다른 쪽 pause + user prompt (silent kill 금지, Devin coordinator pattern)
    ///
    /// **현재 단계 minimal**: 실제 동시 LLM 호출은 향후 ChildClaudeProcess 인프라와 통합 예정.
    /// Phase 1: dispatch logic + UI/state + cost estimate 표시 + warn user.
    public func runReadyTasksInParallel() async {
        guard preferences.multiAgentParallelEnabled else {
            error = "병렬 실행 비활성 — Settings에서 multi-agent parallel을 켜주세요."
            return
        }
        let ready = harness.readyTasks
        guard ready.count >= 2 else {
            error = "병렬 실행에는 ready task가 2개 이상 필요해요. 현재 \(ready.count)개."
            return
        }
        guard agentPanes.count >= 2 else {
            error = "병렬 실행에는 pane이 2개 이상 필요해요. + 버튼으로 pane을 추가하세요."
            return
        }

        // Cognition 권고: 비용 honesty — 사전 알림
        let estimatedDoubleSpend = "예상 비용: 단일 실행 대비 ~2x 토큰, ~1.5x wall-clock"
        harness.appendSystem("⚡ 병렬 실행 시작 — \(ready.prefix(2).count)개 task. \(estimatedDoubleSpend)")

        // ready 첫 2개를 pane 0, pane 1에 dispatch
        let pickedTasks = Array(ready.prefix(2))
        let pickedPanes = Array(agentPanes.prefix(2))

        // disjoint 검사 — 같은 키워드/언어를 다루면 conflict 위험 (CrewAI validate_async_task 패턴)
        // 단순 검사: title overlap
        let firstWords = Set(pickedTasks[0].title.lowercased().split(separator: " ").map(String.init))
        let secondWords = Set(pickedTasks[1].title.lowercased().split(separator: " ").map(String.init))
        let overlap = firstWords.intersection(secondWords)
        if overlap.count > 2 {
            harness.appendSystem("⚠ 병렬 task가 같은 키워드 \(overlap)를 공유 — 충돌 위험. 그래도 진행하시려면 다시 실행하세요.")
            return
        }

        // ADR-053 — BSP barrier: 두 task 동시 dispatch
        // - 첫 task: 메인 active session (기존 runHarnessTask)
        // - 둘째 task: ChildClaudeProcess로 격리된 동시 호출
        for (idx, task) in pickedTasks.enumerated() {
            let pane = pickedPanes[idx]
            harness.updateTaskStatus(task.id, .running)
            harness.appendSystem("[Pane \(idx + 1) (\(pane.agentKind.shortLabel))] task ‘\(task.title)’ 할당")
        }
        persistCurrentHarnessState()

        let primary = pickedTasks[0]
        let secondary = pickedTasks[1]
        let secondaryPane = pickedPanes[1]
        guard let workspace = currentWorkspace else { return }

        // ADR-053 — childProcess가 있으면 BSP barrier로 동시 dispatch
        if let child = childProcess {
            harness.appendSystem("⚡ BSP barrier dispatch — Pane 1 = active session, Pane 2 = child process (\(secondaryPane.agentKind.shortLabel))")

            // ADR-054 — UI progress 등록
            let progressId = registerChildProcess(
                purpose: .parallel,
                agent: secondaryPane.agentKind,
                context: "Pane 2 ‘\(secondary.title)’ 병렬"
            )

            // ADR-057 Critical Fix 1 — 외부 turn이면 plan-mode 적용
            let childSettings = effectiveChildSettings()

            // async let으로 두 호출 동시 진행 (LangGraph BSP superstep 패턴)
            async let primaryDone: Void = runHarnessTask(primary.id)
            async let secondaryOutput: ChildProcessOutput = {
                let prompt = """
                # 병렬 task 호출 (Multi-agent BSP, ADR-053)

                당신은 \(secondaryPane.agentKind.shortLabel) 모델로 호출되었습니다.
                동시에 다른 pane에서 별개 task가 진행 중이며, 두 결과는 barrier에서 합쳐집니다.

                ## Task
                - 제목: \(secondary.title)
                - 설명: \(secondary.description)

                위 task를 수행하고 결과를 응답해주세요. 다른 task의 결과를 기다릴 필요는 없습니다.
                """
                do {
                    return try await child.runOnce(
                        prompt: prompt,
                        in: workspace,
                        agent: secondaryPane.agentKind,
                        purpose: .parallel,
                        timeoutSeconds: 180,
                        overrideSettings: childSettings
                    )
                } catch {
                    // 실패 시 빈 output 반환 (caller가 handle)
                    return ChildProcessOutput(
                        resultText: "[FAILED] \(error.localizedDescription)",
                        inputTokens: 0,
                        outputTokens: 0,
                        costUSD: 0,
                        durationMs: 0,
                        exitCode: 1
                    )
                }
            }()

            // BSP barrier — 양쪽 await
            _ = await primaryDone
            let result = await secondaryOutput

            // Pane 2 결과를 SharedLog + task에 반영
            if result.exitCode == 0 {
                completeChildProcess(progressId, status: .completed)
                harness.updateTaskStatus(secondary.id, .completed, output: result.resultText)
                costTracker.add(.parallel, usd: result.costUSD)
                // ADR-059 Phase 1 — cache 효과 누적
                costTracker.addCacheStats(
                    read: result.cacheReadTokens,
                    creation: result.cacheCreationTokens,
                    uncachedInput: result.inputTokens
                )
                harness.appendAgent(
                    result.resultText,
                    agentKind: secondaryPane.agentKind,
                    taskId: secondary.id,
                    tokenCount: result.outputTokens
                )
                harness.appendSystem("✓ Pane 2 (\(secondaryPane.agentKind.shortLabel)) 완료 — \(result.durationMs)ms, $\(String(format: "%.4f", result.costUSD))")
                // ADR-055 HIGH 3 — Telegram forward
                notifyBoundBridgeChildProcessResult(
                    purpose: .parallel,
                    agent: secondaryPane.agentKind,
                    resultText: "[Pane 2 — \(secondary.title)]\n\n\(result.resultText)",
                    durationMs: result.durationMs,
                    costUSD: result.costUSD,
                    success: true
                )
            } else {
                completeChildProcess(progressId, status: .failed)
                harness.updateTaskStatus(secondary.id, .failed, output: result.resultText)
                // Devin coordinator 권고: 한 쪽 실패 시 다른 쪽 pause + user prompt (silent kill 금지)
                harness.appendSystem("⚠ Pane 2 실패 — Pane 1 결과는 보존. user 검토 후 결정")
                error = "병렬 실행 중 Pane 2 실패: \(result.resultText.prefix(200))"
                notifyBoundBridgeChildProcessResult(
                    purpose: .parallel,
                    agent: secondaryPane.agentKind,
                    resultText: "Pane 2 실패: \(result.resultText.prefix(300))",
                    durationMs: result.durationMs,
                    costUSD: 0,
                    success: false
                )
            }
            persistCurrentHarnessState()
        } else {
            // childProcess 미주입 fallback — 첫 task만 dispatch + 안내
            await runHarnessTask(primary.id)
            harness.appendSystem("✓ Pane 1 dispatch 완료. Pane 2 동시 실행은 childProcess 미주입으로 비활성. (production 빌드에서 활성화)")
        }
    }

    /// ADR-053 — CostTracker.Bucket에 parallel 추가가 안 됐으면 routing으로 fallback.
    /// (Bucket enum 확장은 ADR-053 doc 참조)

    // MARK: - ADR-054 ChildProcess progress helpers

    /// ChildClaudeProcess 시작 시 등록 — UI에 spinner 표시.
    /// **ADR-055 HIGH 3** — bound workspace이면 Telegram bridge에도 시작 알림 forward.
    @discardableResult
    public func registerChildProcess(
        purpose: ChildProcessPurpose,
        agent: AgentKind,
        context: String
    ) -> UUID {
        let progress = ChildProcessProgress(
            purpose: purpose,
            agentRaw: agent.rawValue,
            purposeContext: context,
            status: .running
        )
        activeChildProcesses.append(progress)
        // ADR-055 HIGH 3 — bound workspace은 Telegram에 시작 알림
        if let bridge = sessionBridge,
           let bound = preferences.telegramBoundWorkspaceId,
           selectedWorkspaceId == bound {
            let p = purpose.rawValue
            let a = agent.shortLabel
            let ctx = context
            Task { await bridge.notifyChildProcessStart(purpose: p, agent: a, context: ctx) }
        }
        return progress.id
    }

    /// ChildClaudeProcess 완료 시 status update + 3초 후 prune.
    public func completeChildProcess(_ id: UUID, status: ChildProcessProgress.Status) {
        guard let idx = activeChildProcesses.firstIndex(where: { $0.id == id }) else { return }
        activeChildProcesses[idx].status = status
        // 3초 후 자동 prune (사용자가 결과 확인할 시간)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run {
                self?.activeChildProcesses.removeAll { $0.id == id }
            }
        }
    }

    /// **ADR-061 Phase 4** — binding audit log 추가 + UI cache 갱신.
    public func recordBindingAudit(
        chatId: Int64,
        userId: Int64,
        action: ChatBindingAuditEntry.Action,
        workspaceId: UUID?,
        workspaceName: String?
    ) async {
        let entry = ChatBindingAuditEntry(
            chatId: chatId,
            userId: userId,
            action: action,
            workspaceId: workspaceId,
            workspaceName: workspaceName
        )
        await chatBindingAuditLog.record(entry)
        chatBindingAuditEntries = await chatBindingAuditLog.recent(limit: 50)
    }

    /// **ADR-060 Phase 5** — chat bindings 변경 시 다른 chat에 알림 push.
    /// 멀티 chat 환경에서 한 chat이 binding 변경하면 다른 chat 사용자에게도 인지.
    /// excludingChatId는 변경한 사용자 자신 (이미 응답 받음).
    public func notifyOtherChatsOfBindingChange(
        excludingChatId: Int64,
        action: String,
        workspaceName: String,
        chatId: Int64
    ) async {
        // bound chats 중 excluding 외 모든 chat에 push
        let chats = preferences.telegramChatBindings.compactMap { (key, _) -> Int64? in
            guard let id = Int64(key), id != excludingChatId else { return nil }
            return id
        }
        guard !chats.isEmpty, let bridge = sessionBridge else { return }
        let msg = "🔔 다른 chat에서 binding 변경: chat \(chatId)\(action == "bind" ? "이 ‘\(workspaceName)’에 연결됨" : "이 unbind됨")"
        for cid in chats {
            // bridge.sendNotice는 requestChatId 사용 → 직접 client 호출이 필요하나
            // 단순화: bridge에 임시 setRequestChatId 후 sendNotice → 이전 값 복원
            await bridge.setRequestChatId(cid)
            await bridge.sendNotice(msg)
            await bridge.setRequestChatId(nil)
        }
    }

    /// **ADR-059 Phase 4** — bound bridge에 ready task ▶ 버튼 push.
    /// /tasks 명령 처리 후 router가 호출.
    public func notifyBoundBridgeTaskButtons() {
        guard let bridge = sessionBridge,
              let bound = preferences.telegramBoundWorkspaceId,
              selectedWorkspaceId == bound
        else { return }
        let ready = harness.readyTasks.map { (id: $0.id, title: $0.title) }
        guard !ready.isEmpty else { return }
        Task { await bridge.sendTaskButtons(ready) }
    }

    /// **ADR-055 HIGH 3** — ChildProcess 결과를 Telegram에 forward (bound workspace만).
    /// 호출자: decomposeUserTask / launchRehearsal / runReadyTasksInParallel 완료 후.
    public func notifyBoundBridgeChildProcessResult(
        purpose: ChildProcessPurpose,
        agent: AgentKind,
        resultText: String,
        durationMs: Int,
        costUSD: Double,
        success: Bool
    ) {
        guard let bridge = sessionBridge,
              let bound = preferences.telegramBoundWorkspaceId,
              selectedWorkspaceId == bound
        else { return }
        let p = purpose.rawValue
        let a = agent.shortLabel
        Task {
            await bridge.notifyChildProcessComplete(
                purpose: p,
                agent: a,
                resultText: resultText,
                durationMs: durationMs,
                costUSD: costUSD,
                success: success
            )
        }
    }

    /// ADR-050 Phase 6 — TaskGraph "▶ 실행" 액션. ready task를 active pane에 dispatch.
    /// 1. task.assignedAgent로 pane 전환 (있으면)
    /// 2. handoff prompt + task description을 inputText로 prepend
    /// 3. status를 .running으로 변경
    /// 4. sendMessage 호출 — 사용자에게 실행 사실 표시
    public func runHarnessTask(_ taskId: UUID) async {
        guard let task = harness.tasks.first(where: { $0.id == taskId }) else { return }
        guard task.isReady(allTasks: harness.tasks) else {
            self.error = "task ‘\(task.title)’의 의존성이 아직 완료되지 않았어요."
            return
        }
        // 추천 agent로 pane 전환 (있으면)
        if let agent = task.assignedAgent,
           let pane = agentPanes.first(where: { $0.agentKind == agent }) {
            await setActivePane(pane.id)
        }
        // status running으로 변경
        harness.updateTaskStatus(taskId, .running)
        persistCurrentHarnessState()
        // task description을 input으로 + handoff prompt
        let projectProfile = currentWorkspace?.projectProfile
        let handoff = harness.buildHandoffPrompt(
            targetModel: task.assignedAgent ?? .claude,
            currentTaskId: taskId,
            projectProfile: projectProfile
        )
        let taskInstruction = "[작업 시작 — \(task.title)]\n\n\(task.description)"
        let body = handoff.promptText + "\n\n---\n\n" + taskInstruction
        inputText = body
        await sendMessage()
    }

    /// ADR-050 Phase 6 — Harness conversationLog + tasks 영속.
    /// 자동 호출: appendUser/Agent/System, addTask/updateTaskStatus/removeTask 등 변경 시.
    public func persistCurrentHarnessState() {
        guard let workspace = currentWorkspace else { return }
        let updated = workspace.with(
            savedConversationLog: harness.conversationLog,
            savedTasks: harness.tasks
        )
        if let idx = workspaces.firstIndex(where: { $0.id == workspace.id }) {
            workspaces[idx] = updated
        }
        chainPersistTask(updated)
    }

    /// 현재 terminalSessions를 workspace에 영속 (ADR-041 T13).
    /// activity/hasUnreadOutput는 Codable 제외 (영속 X). label/cwd/createdAt만 보존.
    public func persistCurrentTerminalSessions() {
        guard let workspace = currentWorkspace else { return }
        let updated = workspace.with(savedTerminalSessions: terminalSessions)
        if let idx = workspaces.firstIndex(where: { $0.id == workspace.id }) {
            workspaces[idx] = updated
        }
        chainPersistTask(updated)
    }

    /// 현재 agentPanes를 workspace.savedPanes로 영속 (자동 호출).
    private func persistCurrentPanes() {
        guard let workspace = currentWorkspace else { return }
        let updated = workspace.with(savedPanes: agentPanes)
        if let idx = workspaces.firstIndex(where: { $0.id == workspace.id }) {
            workspaces[idx] = updated
        }
        chainPersistTask(updated)
    }

    /// ADR-043 R4 — Workspace persist 직렬화 (race 방지).
    /// 이전 persist task await 후 새 update 발행 → write order 보장 (last-write-wins by call time).
    private var pendingPersistTask: Task<Void, Never>?
    private func chainPersistTask(_ workspace: Workspace) {
        let store = workspaceStore
        let previous = pendingPersistTask
        pendingPersistTask = Task {
            await previous?.value  // 이전 write 완료 대기 (직렬화)
            try? await store.update(workspace)
        }
    }

    private func clearPaneState() {
        agentPanes = []
        activePaneId = nil
        paneSessions.removeAll()
        paneMessages.removeAll()
        paneSettings.removeAll()
        paneUsage.removeAll()
    }

    /// active pane 전환 — 현재 state를 보존하고 대상 pane state로 swap.
    public func setActivePane(_ paneId: UUID) async {
        guard let workspace = currentWorkspace,
              activePaneId != paneId,
              let target = agentPanes.first(where: { $0.id == paneId }) else { return }

        // 1) 현재 pane 상태 보존
        if let currentId = activePaneId {
            paneMessages[currentId] = messages
            paneSettings[currentId] = activeSettings
            paneUsage[currentId] = currentSessionUsage
            // session은 이미 paneSessions[currentId]에 보관됨 (spawn 시 등록)
        }

        // 2) stream consume task 취소 (새 pane 것으로 재시작)
        streamConsumeTask?.cancel()
        streamConsumeTask = nil
        isStreaming = false

        // 3) 대상 pane state 로드
        activePaneId = paneId
        messages = paneMessages[paneId] ?? []
        activeSettings = paneSettings[paneId] ?? target.settings
        currentSessionUsage = paneUsage[paneId] ?? .zero

        // 4) session: 있으면 재사용, 없으면 spawn
        if let session = paneSessions[paneId] {
            currentClaudeSession = session
            let captured = session
            streamConsumeTask = Task { [weak self] in
                await self?.consumeStream(captured)
            }
        } else {
            // pane 첫 활성화 — 새 session spawn (workspace.agentKind를 pane.agentKind로 임시 override)
            let paneWorkspace = workspace.with(agentKind: target.agentKind)
            do {
                let agentAd = adapter(for: paneWorkspace)
                let session = try await agentAd.spawn(in: workspace)
                paneSessions[paneId] = session
                currentClaudeSession = session
                let captured = session
                streamConsumeTask = Task { [weak self] in
                    await self?.consumeStream(captured)
                }
            } catch {
                self.error = "pane session 시작 실패: \(error.localizedDescription)"
            }
        }
    }

    /// 새 pane 추가 — workspace에 같은 agent kind 여러 개 가능.
    public func addPane(agentKind: AgentKind) async {
        guard currentWorkspace != nil else { return }
        let role: PaneRole = agentPanes.contains(where: { $0.role == .primary }) ? .secondary : .primary
        let newPane = AgentPane(
            agentKind: agentKind,
            settings: activeSettings,
            role: role
        )
        agentPanes.append(newPane)
        paneMessages[newPane.id] = []
        paneSettings[newPane.id] = activeSettings
        paneUsage[newPane.id] = .zero
        persistCurrentPanes()
        // session은 setActivePane에서 lazy spawn
        await setActivePane(newPane.id)
    }

    /// pane 제거 — 마지막 pane은 close 불가 (워크스페이스에 항상 1개 이상).
    public func removePane(_ paneId: UUID) async {
        guard agentPanes.count > 1,
              let workspace = currentWorkspace,
              let pane = agentPanes.first(where: { $0.id == paneId }) else { return }

        // session terminate
        if let session = paneSessions[paneId] {
            let paneWorkspace = workspace.with(agentKind: pane.agentKind)
            let ad = adapter(for: paneWorkspace)
            await ad.terminate(session)
        }

        // state 정리
        paneSessions.removeValue(forKey: paneId)
        paneMessages.removeValue(forKey: paneId)
        paneSettings.removeValue(forKey: paneId)
        paneUsage.removeValue(forKey: paneId)
        agentPanes.removeAll { $0.id == paneId }

        // active 변경
        if activePaneId == paneId {
            activePaneId = nil  // setActivePane이 swap 처리
            if let first = agentPanes.first {
                await setActivePane(first.id)
            }
        }

        // primary가 사라졌으면 첫 pane을 promote
        if !agentPanes.contains(where: { $0.role == .primary }), let first = agentPanes.first {
            if let idx = agentPanes.firstIndex(where: { $0.id == first.id }) {
                agentPanes[idx] = first.with(role: .primary)
            }
        }
        persistCurrentPanes()
    }

    /// pane custom 이름 변경.
    public func renamePane(_ paneId: UUID, to name: String?) {
        guard let idx = agentPanes.firstIndex(where: { $0.id == paneId }) else { return }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        agentPanes[idx] = agentPanes[idx].with(customName: (trimmed?.isEmpty ?? true) ? nil : trimmed)
        persistCurrentPanes()
    }

    /// pane을 primary로 promote (다른 primary는 secondary로 demote).
    public func promotePaneToPrimary(_ paneId: UUID) {
        for idx in agentPanes.indices {
            if agentPanes[idx].id == paneId {
                agentPanes[idx] = agentPanes[idx].with(role: .primary)
            } else if agentPanes[idx].role == .primary {
                agentPanes[idx] = agentPanes[idx].with(role: .secondary)
            }
        }
        persistCurrentPanes()
    }

    // MARK: - Inter-agent message dispatch (ADR-031, T2)

    private let mentionParser = MentionParser()

    /// `@<agent>` mention 매칭 — pane을 찾아서 반환. 없으면 nil.
    /// 우선순위: customName 정확/부분 매칭 → agentKind ("@claude"/"@codex") → 매칭 실패
    public func resolveMentionTarget(_ rawTarget: String) -> AgentPane? {
        let normalized = MentionParser.normalizedTarget(rawTarget)
        guard !normalized.isEmpty else { return nil }

        // 1) customName 정확 매칭 (case-insensitive)
        if let exact = agentPanes.first(where: { ($0.customName?.lowercased() ?? "") == normalized }) {
            return exact
        }
        // 2) customName 부분 매칭
        if let partial = agentPanes.first(where: {
            ($0.customName?.lowercased() ?? "").contains(normalized)
        }) {
            return partial
        }
        // 3) agentKind shortLabel ("claude"/"codex")
        if let kindMatch = agentPanes.first(where: { $0.agentKind.shortLabel == normalized }) {
            return kindMatch
        }
        // 4) agentKind displayName 부분 매칭 ("Claude" → "claude")
        if let displayMatch = agentPanes.first(where: {
            $0.agentKind.displayName.lowercased().contains(normalized)
        }) {
            return displayMatch
        }
        // 5) "me" → active pane (no-op, 그냥 자기 자신)
        if normalized == "me", let activeId = activePaneId {
            return agentPanes.first { $0.id == activeId }
        }
        return nil
    }

    /// 현재 inputText에서 mention 추출 후 적절한 pane에 dispatch.
    /// mention이 없거나 매칭 실패면 일반 sendMessage 흐름.
    /// leading + inline 모두 인식 (ADR-034 A2).
    /// - Returns: dispatch 됐으면 true (호출자가 일반 send 흐름 skip)
    public func tryDispatchMention() async -> Bool {
        guard let mention = mentionParser.parseAny(inputText) else { return false }
        guard let target = resolveMentionTarget(mention.target) else {
            // 매칭 실패 — UX 안내
            self.error = "‘\(mention.target)’ 매칭되는 pane이 없어요. 사용 가능: \(agentPanes.map { "@\($0.agentKind.shortLabel)" }.joined(separator: ", "))"
            return false
        }
        // body로 inputText 교체 + 대상 pane 활성화 + send
        inputText = mention.body
        if target.id != activePaneId {
            await setActivePane(target.id)
        }
        // 사용자 시작 turn — chain 초기화
        agentChainHops = 0
        agentChainVisited.removeAll()
        if let activeId = activePaneId { agentChainVisited.insert(activeId) }
        await sendMessage()
        return true
    }

    /// agent 응답 본문에 `@<other>` mention이 있고 chain이 enabled + max hops 미만이면 자동 dispatch.
    /// `handle(.completed)` 후에 호출.
    /// **안전 장치**: max hops / 같은 pane 재방문 / 자기 자신 mention 모두 차단.
    func tryAutoChainDispatch() async {
        guard preferences.agentChainEnabled,
              preferences.agentChainMaxHops > 0,
              agentChainHops < preferences.agentChainMaxHops
        else { return }

        // 마지막 assistant 메시지 본문 검사 (자연어 안의 mention도 인식)
        guard let lastAssistant = messages.last(where: { $0.role == .assistant }),
              let mention = mentionParser.parseAny(lastAssistant.content)
        else { return }

        guard let target = resolveMentionTarget(mention.target) else { return }
        // 자기 자신 또는 이미 방문한 pane은 skip
        if target.id == activePaneId { return }
        if agentChainVisited.contains(target.id) {
            logger.info("agent chain — \(target.displayName) 이미 방문, chain 종료")
            return
        }

        agentChainHops += 1
        agentChainVisited.insert(target.id)
        logger.info("agent chain hop \(self.agentChainHops): → \(target.displayName)")

        // 대상 pane 활성화 + body로 input + send (자동)
        if target.id != activePaneId {
            await setActivePane(target.id)
        }
        inputText = mention.body
        await sendMessage()
    }

    /// 활성 세션 설정 변경. 활성 어댑터에 반영하고, 활성 워크스페이스가 있으면 새 세션을
    /// 즉시 시작 (메시지 로그는 UI에 보존, 다음 사용자 입력부터 새 설정 적용).
    public func updateActiveSettings(_ newSettings: SessionSettings) async {
        activeSettings = newSettings
        // 양 어댑터 모두에 적용 — agent 전환해도 일관
        await claudeAdapter.updateSettings(newSettings)
        if let codex = codexAdapter {
            await codex.updateSettings(newSettings)
        }

        guard let id = selectedWorkspaceId,
              let workspace = workspaces.first(where: { $0.id == id }) else {
            return
        }

        // ADR-087 Phase 1 — 현재 agent의 perAgentSettings에 즉시 영속
        var newPerAgentSettings = workspace.perAgentSettings
        newPerAgentSettings[workspace.agentKind] = newSettings
        let workspaceWithPerAgent = workspace.with(perAgentSettings: newPerAgentSettings)
        do {
            try await workspaceStore.update(workspaceWithPerAgent)
            if let idx = workspaces.firstIndex(where: { $0.id == id }) {
                workspaces[idx] = workspaceWithPerAgent
            }
        } catch {
            // perAgentSettings 영속 실패는 critical 아님 (다음 setActiveAgentKind 시 다시 try)
        }

        let activeAd = adapter(for: workspaceWithPerAgent)
        streamConsumeTask?.cancel()
        streamConsumeTask = nil
        if let claudeSession = currentClaudeSession {
            await activeAd.terminate(claudeSession)
        }
        currentClaudeSession = nil
        isStreaming = false

        do {
            let claudeSession = try await activeAd.spawn(in: workspaceWithPerAgent)
            currentClaudeSession = claudeSession
            let captured = claudeSession
            streamConsumeTask = Task { [weak self] in
                await self?.consumeStream(captured)
            }
        } catch {
            self.error = "설정 적용을 위한 재시작 실패: \(error.localizedDescription)"
        }
    }

    /// 현재 활성 모델의 컨텍스트 윈도우 크기.
    public var currentContextWindow: Int {
        activeSettings.model.contextWindowTokens
    }

    /// 컨텍스트 사용 비율 (0.0 ~ 1.0).
    public var currentContextUsage: Double {
        currentSessionUsage.contextUsage(maxTokens: currentContextWindow)
    }

    private func consumeStream(_ session: any ClaudeStreamSession) async {
        do {
            for try await event in session.events {
                handle(event)
            }
        } catch is CancellationError {
            // 정상 cancel
        } catch {
            self.error = "Stream 에러: \(error.localizedDescription)"
        }
        isStreaming = false
    }

    /// ADR-049 Phase 4 — 사용자 큰 task를 LLM 호출로 sub-task 분해.
    /// **비용 명시**: ephemeral Claude session 1개 spawn → JSON 응답 → terminate. 토큰 비용 발생.
    /// 실패 시 (LLM JSON 깨짐, session spawn 실패 등) 0 반환 + error message.
    /// 성공 시 harness.tasks에 추가 + count 반환.
    ///
    /// **ADR-053 — ChildClaudeProcess로 진짜 격리**:
    /// - 별도 process spawn (`claude -p ...`) — 메인 conversation 0 영향
    /// - Aider architect_coder.py + Cline SubagentRunner.ts 패턴 적용
    /// - 결과는 단일 String + UsageDelta로 반환 → JSON parse → harness.tasks에 합류
    /// - 비용은 CostTracker.decomposition bucket에 정확히 add (estimate 아닌 actual)
    /// - childProcess가 nil이면 ADR-052 fallback (active session으로 호출 + estimate)
    @discardableResult
    public func decomposeUserTask(_ userRequest: String) async -> Int {
        guard let workspace = currentWorkspace else {
            self.error = "워크스페이스를 먼저 선택하세요."
            return 0
        }
        let prompt = TaskDecomposer.buildPrompt(
            userRequest: userRequest,
            projectProfile: workspace.projectProfile
        )

        // ADR-053 — childProcess가 있으면 진짜 격리된 호출, 없으면 fallback
        if let child = childProcess {
            harness.appendSystem("📋 Task 분해 호출 (격리된 child process — 메인 cache 0 영향)")
            // ADR-054 — UI progress 등록
            let progressId = registerChildProcess(
                purpose: .decomposition,
                agent: workspace.agentKind,
                context: "‘\(userRequest.prefix(40))…’ 분해"
            )
            // ADR-057 Critical Fix 1 — 외부 turn이면 plan-mode 적용된 settings로 호출 (보안 hole 방지)
            let childSettings = effectiveChildSettings()
            do {
                let output = try await child.runOnce(
                    prompt: prompt,
                    in: workspace,
                    agent: workspace.agentKind,
                    purpose: .decomposition,
                    timeoutSeconds: 60,
                    overrideSettings: childSettings
                )
                completeChildProcess(progressId, status: .completed)
                // 정확한 cost 추적
                costTracker.add(.decomposition, usd: output.costUSD)
                // ADR-058 Phase 1 + ADR-059 Phase 1 + ADR-060 Phase 4 — cache 효과 누적 추적
                costTracker.addCacheStats(
                    read: output.cacheReadTokens,
                    creation: output.cacheCreationTokens,
                    uncachedInput: output.inputTokens
                )
                // ADR-060 Phase 4 + ADR-061 Phase 2 — hourly trend 누적 (workspace별 분리)
                let trendStore = dailyCostStore
                let read = output.cacheReadTokens
                let uncached = output.inputTokens
                let wsId = workspace.id
                Task { await trendStore.addCacheSample(read: read, uncachedInput: uncached, workspaceId: wsId) }
                let cachePct = Int(output.cacheHitRatio * 100)
                let cacheNote = output.cacheReadTokens > 0 ? " · cache hit \(cachePct)% (\(output.cacheReadTokens) tok)" : ""
                harness.appendSystem("✓ 분해 완료 (\(output.durationMs)ms, $\(String(format: "%.4f", output.costUSD))\(cacheNote))")
                // JSON parse → harness.tasks 추가
                let parsed = TaskDecomposer.parseTasks(jsonResponse: output.resultText)
                guard !parsed.isEmpty else {
                    self.error = "분해 응답이 JSON으로 파싱되지 않았어요. 응답: \(output.resultText.prefix(200))"
                    return 0
                }
                for task in parsed {
                    harness.tasks.append(task)
                }
                self.error = "✓ 작업 \(parsed.count)개로 분해됨 (격리 호출, $\(String(format: "%.4f", output.costUSD)))"
                persistCurrentHarnessState()
                // ADR-055 HIGH 3 — Telegram에 결과 forward
                let summary = "\(parsed.count)개 sub-task로 분해:\n" +
                    parsed.enumerated().map { "  \($0.offset + 1). \($0.element.title)" }.joined(separator: "\n")
                notifyBoundBridgeChildProcessResult(
                    purpose: .decomposition,
                    agent: workspace.agentKind,
                    resultText: summary,
                    durationMs: output.durationMs,
                    costUSD: output.costUSD,
                    success: true
                )
                return parsed.count
            } catch {
                completeChildProcess(progressId, status: .failed)
                self.error = "Decomposition 호출 실패: \(error.localizedDescription)"
                notifyBoundBridgeChildProcessResult(
                    purpose: .decomposition,
                    agent: workspace.agentKind,
                    resultText: "실패: \(error.localizedDescription)",
                    durationMs: 0,
                    costUSD: 0,
                    success: false
                )
                return 0
            }
        }

        // ADR-052 fallback — active session으로 호출 (childProcess 미주입 시)
        let ephemeralWrapped = """
        <ephemeral-decomposition cache-control="off">
        다음 호출은 task 분해 전용 ephemeral 작업입니다. 응답 후 메인 conversation은 영향받지 않습니다.

        \(prompt)
        </ephemeral-decomposition>
        """
        guard let claudeSession = currentClaudeSession else {
            self.error = "활성 세션이 없어요. pane 활성화 후 재시도."
            return 0
        }
        let estimatedTokens = ephemeralWrapped.utf8.count / 4
        let estimatedCost = CostTracker.estimateCostUSD(inputTokens: estimatedTokens, outputTokens: 500)
        costTracker.add(.decomposition, usd: estimatedCost)
        harness.appendSystem("📋 Task 분해 호출 (fallback: active session, ~$\(String(format: "%.4f", estimatedCost)))")
        do {
            try await claudeSession.send(ephemeralWrapped)
        } catch {
            self.error = "Decomposition 전송 실패: \(error.localizedDescription)"
            return 0
        }
        markPendingDecomposition()
        return -1  // -1 = "응답 대기 중"
    }

    /// 다음 agent 응답이 decomposition JSON일 거라고 표시 — .completed 시 parse 시도.
    private var pendingDecomposition: Bool = false
    private func markPendingDecomposition() {
        pendingDecomposition = true
    }

    /// .completed 시 호출 — pendingDecomposition이면 마지막 agent 메시지를 JSON으로 parse 시도.
    /// 성공하면 harness.tasks에 추가, 실패하면 silent (사용자가 보긴 함).
    private func tryParseDecompositionResult() {
        guard pendingDecomposition else { return }
        pendingDecomposition = false
        // 마지막 agent entry 가져오기
        guard let lastAgent = harness.conversationLog.reversed().first(where: { $0.role == .agent }) else {
            return
        }
        let parsed = TaskDecomposer.parseTasks(jsonResponse: lastAgent.content)
        guard !parsed.isEmpty else {
            self.error = "작업 분해 응답이 JSON으로 파싱되지 않았어요. 사용자 메시지로 표시됨."
            return
        }
        // harness.tasks에 추가
        for task in parsed {
            harness.tasks.append(task)
        }
        self.error = "✓ 작업 \(parsed.count)개로 분해됨 — Inspector ‘작업’ 탭에서 확인."
    }

    /// ADR-049 — ProjectProfile 저장 (워크스페이스 SwiftData persist + cache 업데이트).
    public func updateProjectProfile(workspaceId: UUID, profile: ProjectProfile) async {
        guard let workspace = workspaces.first(where: { $0.id == workspaceId }) else { return }
        let updated = workspace.with(projectProfile: profile)
        if let idx = workspaces.firstIndex(where: { $0.id == workspaceId }) {
            workspaces[idx] = updated
        }
        chainPersistTask(updated)
        // 활성 워크스페이스라면 사용자에게 안내 — 다음 spawn부터 적용됨
        if workspaceId == selectedWorkspaceId {
            error = "프로젝트 프로필 저장됨. 다음 pane spawn (또는 새 세션) 부터 system prompt에 반영됩니다."
        }
    }

    /// ADR-048 Phase 3.C — kind와 일치하는 pane으로 전환. 없으면 false.
    public func switchToPaneOfKind(_ kind: AgentKind) async -> Bool {
        guard let target = agentPanes.first(where: { $0.agentKind == kind }) else { return false }
        await setActivePane(target.id)
        return true
    }

    /// ADR-051 — pending routing decision (countdown 중인 routing).
    /// view가 banner로 표시 + 사용자 cancel 가능.
    public var pendingRouting: PendingRouting?

    public struct PendingRouting: Equatable, Sendable {
        public let from: AgentKind
        public let to: AgentKind
        public let reason: String
        public let estimatedHandoffTokens: Int
        public let secondsRemaining: Int
    }

    /// ADR-048 Phase 3 — Harness 자동 routing. 사용자 입력 → 추천 agent → 다른 pane이면 자동 전환.
    /// ADR-050 — XAI 원칙: routing 이유 (matched keyword) SharedLog에 기록.
    /// ADR-051 — countdown intervention (preferences.harnessRoutingCountdownSeconds > 0 시).
    /// ADR-052 — RoutingDecisionLog에 record 영속 (LangSmith/Langfuse 패턴).
    /// returns: routing이 발생했으면 generated handoff prompt (caller가 inputText에 prepend), 아니면 nil.
    /// **side effect**: pane 전환 + SharedLog 기록 + RoutingDecisionLog append. inputText는 caller 책임.
    public func applyHarnessAutoRoutingIfNeeded(userText: String) async -> String? {
        guard preferences.harnessAutoRoutingEnabled else { return nil }
        // ADR-055 #5 — 사용자 학습 결과 반영 (mute + custom keyword)
        let classification = ModelCapabilityMatrix.classifyTaskKind(
            userText,
            mutedKeywords: routingLearningSnapshot.mutedKeywords,
            customKeywords: routingLearningSnapshot.customKeywords
        )
        // ADR-058 Phase 2 — keyword matched 시 use 카운트 (ratio 계산용)
        if let kw = classification.matchedKeyword {
            await routingLearningStore.recordUse(keyword: kw)
            routingLearningSnapshot = await routingLearningStore.snapshot()
        }
        let recommended = ModelCapabilityMatrix.recommend(for: classification.kind)
        guard let workspace = currentWorkspace else { return nil }
        let currentKind = workspace.agentKind
        // skipped 케이스도 record 생성 (decision history 완전성)
        guard recommended != currentKind else {
            await appendRoutingDecision(
                userText: userText,
                workspace: workspace,
                classification: classification,
                recommended: recommended,
                currentKind: currentKind,
                outcome: .skipped,
                estimatedHandoffTokens: 0
            )
            return nil
        }
        guard let targetPane = agentPanes.first(where: { $0.agentKind == recommended }) else {
            await appendRoutingDecision(
                userText: userText,
                workspace: workspace,
                classification: classification,
                recommended: recommended,
                currentKind: currentKind,
                outcome: .failed,
                estimatedHandoffTokens: 0
            )
            return nil
        }
        let handoff = harness.buildHandoffPrompt(
            targetModel: recommended,
            projectProfile: workspace.projectProfile
        )
        let reason = classification.matchedKeyword.map { "‘\($0)’ keyword 감지 → \(classification.kind.rawValue)" } ?? "keyword 일반"

        // ADR-051 — countdown intervention
        let countdown = preferences.harnessRoutingCountdownSeconds
        if countdown > 0 {
            // banner 표시 + N초 sleep (사용자가 그 사이 cancelPendingRouting 호출 가능)
            for remaining in stride(from: countdown, through: 1, by: -1) {
                pendingRouting = PendingRouting(
                    from: currentKind,
                    to: recommended,
                    reason: reason,
                    estimatedHandoffTokens: handoff.estimatedTokens,
                    secondsRemaining: remaining
                )
                try? await Task.sleep(for: .seconds(1))
                // 사용자가 cancel하면 pendingRouting이 nil
                if pendingRouting == nil {
                    harness.appendSystem("🚫 자동 routing 취소됨 (사용자 개입) — 현재 \(currentKind.shortLabel) 유지")
                    await appendRoutingDecision(
                        userText: userText,
                        workspace: workspace,
                        classification: classification,
                        recommended: recommended,
                        currentKind: currentKind,
                        outcome: .cancelled,
                        estimatedHandoffTokens: handoff.estimatedTokens
                    )
                    // ADR-055 #5 — cancel된 keyword 학습 (3회 이상 cancel되면 자동 mute)
                    if let kw = classification.matchedKeyword {
                        await routingLearningStore.recordCancel(keyword: kw)
                        routingLearningSnapshot = await routingLearningStore.snapshot()
                        // 사용자에게 학습 알림
                        let count = routingLearningSnapshot.cancelCounts[kw] ?? 0
                        if routingLearningSnapshot.mutedKeywords.contains(kw) {
                            harness.appendSystem("🤖 학습: ‘\(kw)’ keyword가 \(count)회 cancel됨 → 앞으로 자동 routing 안 함 (Settings에서 unmute 가능)")
                        } else if count >= 2 {
                            let remain = RoutingLearningStore.muteThreshold - count
                            harness.appendSystem("🤖 학습 진행: ‘\(kw)’가 \(count)회 cancel됨 (\(remain)회 더면 자동 mute)")
                        }
                    }
                    return nil
                }
            }
            pendingRouting = nil
        }

        await setActivePane(targetPane.id)
        harness.appendSystem("🔀 자동 routing: \(currentKind.shortLabel) → \(recommended.shortLabel)\n  사유: \(reason)\n  handoff: ~\(handoff.estimatedTokens) tokens")
        await appendRoutingDecision(
            userText: userText,
            workspace: workspace,
            classification: classification,
            recommended: recommended,
            currentKind: currentKind,
            outcome: .applied,
            estimatedHandoffTokens: handoff.estimatedTokens
        )
        return handoff.promptText + "\n\n---\n\n"
    }

    /// ADR-052 — RoutingDecisionLog에 record append.
    /// 모든 routing 시도 (applied/cancelled/skipped/failed) 기록 — observability + counterfactual 분석.
    private func appendRoutingDecision(
        userText: String,
        workspace: Workspace,
        classification: (kind: TaskKind, matchedKeyword: String?),
        recommended: AgentKind,
        currentKind: AgentKind,
        outcome: RoutingDecisionRecord.Outcome,
        estimatedHandoffTokens: Int
    ) async {
        let primaryLanguage = workspace.projectProfile.primaryLanguage.rawValue
        let fingerprint = RoutingDecisionRecord.computeFingerprint(
            taskKind: classification.kind.rawValue,
            languageHint: primaryLanguage,
            promptLength: userText.count
        )
        let reasonCodes = buildReasonCodes(
            kind: classification.kind,
            keyword: classification.matchedKeyword,
            outcome: outcome
        )
        let reasonSummary: String
        if let keyword = classification.matchedKeyword {
            reasonSummary = "‘\(keyword)’ keyword → \(classification.kind.rawValue) → \(recommended.shortLabel)"
        } else {
            reasonSummary = "기본 분류 → \(recommended.shortLabel)"
        }
        // 후보 모델 — 현재는 이분 분류 (claude vs codex). score는 binary.
        let allCandidates: [AgentKind] = [.claude, .codex]
        let candidates = allCandidates.map { agent in
            RoutingDecisionRecord.Candidate(
                agentRaw: agent.rawValue,
                score: agent == recommended ? 1.0 : 0.5,
                reasonCodes: agent == recommended ? reasonCodes : ["not_recommended_for_\(classification.kind.rawValue)"]
            )
        }
        let redacted = String(userText.prefix(80))
        let raw = preferences.routingLogRawPrompts ? userText : nil

        let record = RoutingDecisionRecord(
            workspaceId: workspace.id,
            workspaceName: workspace.name,
            taskKindRaw: classification.kind.rawValue,
            matchedKeyword: classification.matchedKeyword,
            taskFingerprint: fingerprint,
            candidates: candidates,
            selectedAgentRaw: recommended.rawValue,
            previousAgentRaw: currentKind.rawValue,
            reasonSummary: reasonSummary,
            reasonCodes: reasonCodes,
            outcome: outcome,
            estimatedHandoffTokens: estimatedHandoffTokens,
            redactedPrompt: redacted,
            rawPrompt: raw
        )
        await routingLogStore.append(record)
        // UI cache update (head insertion — 최신부터)
        routingDecisions.insert(record, at: 0)
        // memory cap
        if routingDecisions.count > 500 {
            routingDecisions = Array(routingDecisions.prefix(500))
        }
    }

    private func buildReasonCodes(
        kind: TaskKind,
        keyword: String?,
        outcome: RoutingDecisionRecord.Outcome
    ) -> [String] {
        var codes: [String] = []
        codes.append("kind_\(kind.rawValue)")
        if keyword != nil { codes.append("keyword_match") } else { codes.append("default_kind") }
        codes.append("outcome_\(outcome.rawValue)")
        return codes
    }

    /// ADR-052 — 앱 시작 시 routing log 로드. AppModel.bootstrap 등에서 호출.
    public func loadRoutingDecisionLog() async {
        let days = preferences.routingLogRetentionDays
        let records = await routingLogStore.loadRecent(days: days)
        routingDecisions = records
    }

    /// ADR-052 — Routing log JSON export (사용자가 ShareLink 또는 Save panel로 활용).
    /// privacy: preferences.routingLogRawPrompts=false면 redacted (raw prompts 제거).
    public func exportRoutingLog() async {
        let includeRaw = preferences.routingLogRawPrompts
        guard let data = await routingLogStore.exportJSON(includeRawPrompts: includeRaw) else {
            error = "Routing log export 실패 — 빈 로그 또는 인코딩 오류"
            return
        }
        // macOS NSSavePanel — main actor에서 실행
        await MainActor.run {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "yuminai-routing-log-\(Date().formatted(.iso8601.day().month().year())).json"
            if panel.runModal() == .OK, let url = panel.url {
                try? data.write(to: url)
                error = "Routing log 저장됨: \(url.lastPathComponent)"
            }
        }
    }

    /// ADR-052 — Routing log in-memory cache 비우기 (disk file은 유지).
    /// disk 정리는 사용자가 직접 ~/Library/Application Support/Yuminai/routing-log/ 에서.
    public func clearRoutingLogMemory() async {
        routingDecisions = []
        // disk 파일 자체 삭제는 사용자 신중한 결정 필요 — 별도 액션으로 분리
    }

    // MARK: - ADR-052 Rehearsal helpers

    /// ADR-052 — task의 rehearsal 결과 list (UI 표시용).
    public func rehearsals(forTaskId id: UUID) -> [RehearsalRun] {
        rehearsalsByTask[id] ?? []
    }

    /// ADR-052 + ADR-053 — task에 대한 rehearsal launch (다른 모델로 재실행).
    /// 1. 현재 task 상태로 snapshot 저장
    /// 2. RehearsalRun pending 상태로 record 추가
    /// 3. ChildClaudeProcess로 격리된 호출 → 결과 + cost를 RehearsalRun에 update
    /// 4. cost는 별도 rehearsal bucket에 누적
    public func launchRehearsal(taskId: UUID, agent: AgentKind) async {
        guard let task = harness.tasks.first(where: { $0.id == taskId }) else {
            error = "Rehearsal: task를 찾을 수 없음"
            return
        }
        guard let workspace = currentWorkspace else { return }

        // 1. snapshot 저장
        let entries = harness.conversationLog.filter { entry in
            if !task.entryRefs.isEmpty { return task.entryRefs.contains(entry.id) }
            return entry.timestamp >= task.createdAt
        }
        let settingsSummary = TaskSnapshot.SettingsSummary(
            modelLabel: activeSettings.model.displayName,
            mode: activeSettings.effortLevel.rawValue,
            permissionMode: activeSettings.permissionMode.rawValue
        )
        let snapshot = TaskSnapshot(
            taskId: taskId,
            taskTitle: task.title,
            taskDescription: task.description,
            originalAgentRaw: (task.assignedAgent ?? workspace.agentKind).rawValue,
            originalSettings: settingsSummary,
            projectContextSummary: workspace.projectProfile.systemContextSummary(),
            entries: entries,
            originalOutput: task.output
        )
        await rehearsalStore.saveSnapshot(snapshot)

        // 2. Run pending record
        let runId = UUID()
        let estimatedTokens = entries.reduce(0) { $0 + $1.content.utf8.count / 4 }
        let estimatedCostUSD = CostTracker.estimateCostUSD(inputTokens: estimatedTokens, outputTokens: 1000)
        var run = RehearsalRun(
            id: runId,
            snapshotId: snapshot.id,
            taskId: taskId,
            replayAgentRaw: agent.rawValue,
            status: .pending,
            estimatedCostUSD: estimatedCostUSD
        )
        await rehearsalStore.saveRun(run)
        var existing = rehearsalsByTask[taskId] ?? []
        existing.insert(run, at: 0)
        rehearsalsByTask[taskId] = existing

        // 3. ADR-053 — ChildClaudeProcess로 격리된 호출 (있으면)
        guard let child = childProcess else {
            // childProcess 미주입 시 fallback: stub 결과
            run.status = .completed
            run.completedAt = Date()
            run.durationMs = 0
            run.resultText = "[리허설 stub] childProcess 미주입 — production app에서만 진짜 호출. 원본: \(task.output ?? task.description)"
            await rehearsalStore.saveRun(run)
            if let idx = rehearsalsByTask[taskId]?.firstIndex(where: { $0.id == runId }) {
                rehearsalsByTask[taskId]?[idx] = run
            }
            error = "리허설 stub (childProcess 미주입). Production 빌드에선 실제 LLM 호출."
            return
        }

        // running 표시
        run.status = .running
        await rehearsalStore.saveRun(run)
        if let idx = rehearsalsByTask[taskId]?.firstIndex(where: { $0.id == runId }) {
            rehearsalsByTask[taskId]?[idx] = run
        }

        // ADR-054 — UI progress 등록
        let progressId = registerChildProcess(
            purpose: .rehearsal,
            agent: agent,
            context: "‘\(task.title)’ 리허설 (\(agent.shortLabel))"
        )

        // rehearsal prompt — task 컨텍스트 + 원본 결과 비교 요청
        let rehearsalPrompt = buildRehearsalPrompt(
            task: task,
            entries: entries,
            originalAgent: snapshot.originalAgentRaw,
            replayAgent: agent
        )

        // ADR-057 Critical Fix 1 — 외부 turn이면 plan-mode 적용
        let childSettings = effectiveChildSettings()
        do {
            let output = try await child.runOnce(
                prompt: rehearsalPrompt,
                in: workspace,
                agent: agent,
                purpose: .rehearsal,
                timeoutSeconds: 120,
                overrideSettings: childSettings
            )
            completeChildProcess(progressId, status: .completed)
            costTracker.add(.rehearsal, usd: output.costUSD)
            run.status = .completed
            run.completedAt = Date()
            run.durationMs = output.durationMs
            run.resultText = output.resultText
            await rehearsalStore.saveRun(run)
            if let idx = rehearsalsByTask[taskId]?.firstIndex(where: { $0.id == runId }) {
                rehearsalsByTask[taskId]?[idx] = run
            }
            // ADR-059 Phase 1 — cache 효과 누적
            costTracker.addCacheStats(
                read: output.cacheReadTokens,
                creation: output.cacheCreationTokens,
                uncachedInput: output.inputTokens
            )
            error = "✓ 리허설 완료: \(agent.shortLabel) (\(output.durationMs)ms, $\(String(format: "%.4f", output.costUSD)))"
            // ADR-055 HIGH 3 — Telegram forward
            notifyBoundBridgeChildProcessResult(
                purpose: .rehearsal,
                agent: agent,
                resultText: "[\(task.title)] 리허설 결과:\n\n\(output.resultText)",
                durationMs: output.durationMs,
                costUSD: output.costUSD,
                success: true
            )
        } catch {
            completeChildProcess(progressId, status: .failed)
            run.status = .failed
            run.completedAt = Date()
            run.errorMessage = error.localizedDescription
            await rehearsalStore.saveRun(run)
            if let idx = rehearsalsByTask[taskId]?.firstIndex(where: { $0.id == runId }) {
                rehearsalsByTask[taskId]?[idx] = run
            }
            self.error = "리허설 실패: \(error.localizedDescription)"
            notifyBoundBridgeChildProcessResult(
                purpose: .rehearsal,
                agent: agent,
                resultText: "리허설 실패: \(error.localizedDescription)",
                durationMs: 0,
                costUSD: 0,
                success: false
            )
        }
    }

    /// ADR-053 — Rehearsal prompt builder. 원본 task description + 컨텍스트 entries.
    private func buildRehearsalPrompt(
        task: HarnessTask,
        entries: [ConversationEntry],
        originalAgent: String,
        replayAgent: AgentKind
    ) -> String {
        let recentContext = entries.suffix(3).map { entry -> String in
            let role = entry.role == .user ? "사용자" : "[\(entry.agentKind?.shortLabel ?? "?")]"
            return "- \(role): \(entry.content.prefix(200))"
        }.joined(separator: "\n")

        return """
        # Rehearsal — 다른 모델 비교 호출

        당신은 \(replayAgent.shortLabel) 모델로 호출되었습니다.
        원래 이 task는 \(originalAgent) 모델이 처리했고, 결과를 비교하기 위한 재실행입니다.
        production conversation에는 영향 없는 1회성 호출입니다.

        ## Task
        - 제목: \(task.title)
        - 설명: \(task.description)

        ## 최근 컨텍스트 (참고)
        \(recentContext)

        ## 요청
        위 task에 대한 당신의 접근 방식과 결과를 보여주세요. 코드를 작성하라면 코드를, 분석을 요청받으면 분석을.
        \(replayAgent.shortLabel)의 강점을 살려 응답해주세요.
        """
    }

    /// ADR-052 — 앱 시작 또는 워크스페이스 전환 시 rehearsal cache load (현재 task들에 대해서만).
    public func loadRehearsalsForCurrentTasks() async {
        for task in harness.tasks {
            let runs = await rehearsalStore.loadRuns(taskId: task.id)
            if !runs.isEmpty {
                rehearsalsByTask[task.id] = runs
            }
        }
    }

    /// ADR-051 — 사용자가 routing countdown 중 취소.
    public func cancelPendingRouting() {
        pendingRouting = nil
    }

    /// ADR-047 Phase 2 — turn 단위 agent 응답 누적 buffer.
    /// .text chunk 마다 누적하고 .completed 시 SharedLog에 단일 entry로 기록.
    private var harnessAgentBuffer: String = ""

    private func handle(_ event: ClaudeEvent) {
        switch event {
        case .text(let text):
            appendMessage(role: .assistant, content: text)
            // ADR-047 Phase 2 — agent 응답을 turn 단위로 buffer (.completed에서 flush)
            harnessAgentBuffer.append(text)
        case .toolCall(let name, _):
            appendMessage(role: .tool, content: "Tool: \(name)")
        case .toolResult(let success, let output):
            let head = String(output.prefix(200))
            appendMessage(role: .tool, content: "Tool \(success ? "OK" : "FAIL"): \(head)")
        case .statusChange:
            break
        case .usage(let delta):
            let stats = UsageStats(
                inputTokens: delta.inputTokens,
                outputTokens: delta.outputTokens,
                cacheCreationTokens: delta.cacheCreationTokens,
                cacheReadTokens: delta.cacheReadTokens,
                costUSD: delta.costUSD ?? 0,
                messageCount: 0
            )
            currentSessionUsage.add(stats)
            allTimeUsage.add(stats)
            if let cost = delta.costUSD, cost > 0 {
                lastCostDelta = cost
                // ADR-052 — Cost를 적절한 bucket으로 라우팅
                // pendingDecomposition이면 decomposition bucket, 아니면 main
                if pendingDecomposition {
                    // decomposition bucket은 decomposeUserTask에서 estimate를 이미 add 했으므로
                    // 여기서는 차이만 보정 (실제 cost - estimate 차이를 + 또는 -)
                    // 단순화: 추가 add 없이 estimate를 유지 (실제 추적은 main allTimeUsage에 통합)
                    // → 향후 ChildClaudeProcess 분리 시 별도 process의 usage를 직접 추적
                } else {
                    costTracker.add(.main, usd: cost)
                }
                // ADR-056 Phase 4 — daily cost 누적 (자정 reset)
                accumulateDailyCost(cost)
            }
        case .completed(let exitCode):
            isStreaming = false
            // ADR-047 Phase 2 — turn 끝났으면 buffer를 SharedLog에 agent entry로 기록
            if !harnessAgentBuffer.isEmpty {
                let agentKind = currentWorkspace?.agentKind ?? .claude
                harness.appendAgent(
                    harnessAgentBuffer,
                    agentKind: agentKind,
                    tokenCount: currentSessionUsage.outputTokens
                )
                harnessAgentBuffer = ""
                // ADR-050 Phase 6 — turn 종료 시 harness state 영속
                persistCurrentHarnessState()
            }
            // ADR-049 Phase 4 — pending decomposition 응답 자동 parse
            tryParseDecompositionResult()
            // ADR-056 Phase 3 — 컨텍스트 70%+ 자동 push (하루 1회 cap)
            maybeAutoPushContextWarning()
            let workspaceName = workspaces.first { $0.id == selectedWorkspaceId }?.name ?? "?"
            let category: AlertCategory = exitCode == 0 ? .workComplete : .workFailed
            let costStr = String(format: "$%.4f", currentSessionUsage.costUSD)
            let summary = "Workspace: \(workspaceName) (exit \(exitCode), \(costStr))"
            // ADR-045 R1.H2 — bound workspace는 sessionBridge가 더 풍부한 완료 메시지 보냄.
            // 중복 알림 방지: bound면 alertDispatcher skip (bridge가 처리), 아니면 dispatcher만.
            let isBoundWorkspace = preferences.telegramBoundWorkspaceId == selectedWorkspaceId
            if !isBoundWorkspace {
                let dispatcher = alertDispatcher
                Task {
                    await dispatcher?.dispatch(category: category, message: summary)
                }
            } else if isExternalTurn {
                // ADR-055 HIGH 4 — 외부 turn cost를 정확히 추적 (delta only).
                let delta = currentSessionUsage.costUSD - externalTurnStartCostSnapshot
                if delta > 0 {
                    externalTurnTotalCostUSD += delta
                }
                // ADR-062 Phase 6 — chat-specific 통계도 record
                if let bridge = sessionBridge,
                   let bound = preferences.telegramBoundWorkspaceId,
                   selectedWorkspaceId == bound {
                    let chatId = preferences.telegramChatId ?? 0
                    let store = telegramUsageStore
                    let inputTok = currentSessionUsage.inputTokens
                    let outputTok = currentSessionUsage.outputTokens
                    Task { @MainActor in
                        await self.recordTelegramTurnComplete(
                            chatId: chatId,
                            costUSD: delta,
                            inputTokens: inputTok,
                            outputTokens: outputTok
                        )
                    }
                    _ = bridge  // suppress warning
                }
                externalTurnStartCostSnapshot = currentSessionUsage.costUSD
                isExternalTurn = false  // turn 종료
            }
            // Checkpoint 종료 + 변경 캡처 + Delivery loop 자동 실행 (ADR-029)
            if let workspace = currentWorkspace {
                let cm = checkpointManager
                let runner = deliveryRunner
                Task { @MainActor in
                    if let snap = await cm.endTurn(workspace: workspace) {
                        self.pendingChanges = snap.changedFiles
                        self.pendingDiff = snap.diff
                    }
                    // Delivery auto-run only if exit==0 + autoRunOnTurnComplete
                    if exitCode == 0 {
                        await self.maybeRunDelivery(workspace: workspace, runner: runner)
                    }
                    // Agent chain (ADR-034 A1) — 응답에 @mention 있으면 자동 dispatch
                    if exitCode == 0 {
                        await self.tryAutoChainDispatch()
                    } else {
                        // 실패 시 chain 종료
                        self.agentChainHops = 0
                        self.agentChainVisited.removeAll()
                    }
                }
            }
        }
        forwardToBridgeIfBound(event)
    }

    private func maybeRunDelivery(workspace: Workspace, runner: DeliveryRunner) async {
        let cfg = workspace.deliveryConfig
        guard cfg.autoRunOnTurnComplete, cfg.hasAnyCommand else { return }

        isDeliveryRunning = true
        let results = await runner.runIfConfigured(workspace: workspace, trigger: .turnComplete)
        isDeliveryRunning = false

        // ADR-042 R3.5 — DeliveryCoordinator로 위임 (cap 일관성)
        delivery.appendResults(results)

        // 실패 + autoFeedFailureToAgent → 다음 turn에 prepend
        if cfg.autoFeedFailureToAgent,
           let firstFailure = results.first(where: { !$0.success }) {
            pendingFailureFeedback = firstFailure.failurePromptPrefix()
        }

        // Telegram bridge에도 결과 알림
        if let bridge = sessionBridge,
           let bound = preferences.telegramBoundWorkspaceId,
           workspace.id == bound {
            for r in results {
                let icon = r.success ? "✅" : "❌"
                let msg = "\(icon) \(r.kind.label) — exit \(r.exitCode), \(r.durationMs)ms"
                Task { await bridge.sendNotice(msg) }
            }
        }
    }

    // MARK: - Diff review actions (ADR-027 phase A2/A3)

    public func acceptAllChanges() async {
        await checkpointManager.acceptAll()
        pendingChanges = []
        pendingDiff = ""
    }

    public func rejectAllChanges() async {
        guard let workspace = currentWorkspace else { return }
        do {
            try await checkpointManager.rejectAll(workspace: workspace)
            pendingChanges = []
            pendingDiff = ""
        } catch {
            self.error = "변경 원복 실패: \(error.localizedDescription)"
        }
    }

    public func rejectPaths(_ paths: [String]) async {
        guard let workspace = currentWorkspace else { return }
        do {
            try await checkpointManager.rejectPaths(paths, workspace: workspace)
            pendingChanges = await checkpointManager.pendingChanges
            pendingDiff = (await checkpointManager.snapshot)?.diff ?? ""
        } catch {
            self.error = "일부 변경 원복 실패: \(error.localizedDescription)"
        }
    }

    // MARK: - 파일 시스템 facade — WorkspaceFileManager로 위임 (ADR-042 R3.2)

    public func refreshWorkspaceFileTree() async {
        await files.refresh(workspace: currentWorkspace)
        if let err = files.lastError { self.error = err; files.lastError = nil }
    }

    public func selectWorkspaceFile(_ relativePath: String) async {
        await files.selectFile(relativePath)
        if let err = files.lastError { self.error = err; files.lastError = nil }
    }

    public func setActiveFileTab(_ tabId: UUID) { files.setActiveTab(tabId) }
    public func closeFileTab(_ tabId: UUID) {
        files.closeTab(tabId)
        if let err = files.lastError { self.error = err; files.lastError = nil }
    }
    public func closeAllFileTabs() { files.closeAllNonDirtyTabs() }
    public func selectAdjacentFileTab(offset: Int) { files.selectAdjacentTab(offset: offset) }
    public func closeActiveFileTab() { files.closeActiveTab() }
    public func startEditingWorkspaceFile() { files.startEditing() }
    public func saveWorkspaceFile() async {
        await files.save()
        if let err = files.lastError { self.error = err; files.lastError = nil }
    }
    public func discardWorkspaceFileEdits() { files.discardEdits() }

    public func createWorkspaceFile(at relativePath: String) async {
        await files.createFile(at: relativePath)
        if let err = files.lastError { self.error = err; files.lastError = nil }
    }
    public func createWorkspaceFolder(at relativePath: String) async {
        await files.createFolder(at: relativePath)
        if let err = files.lastError { self.error = err; files.lastError = nil }
    }
    public func renameWorkspaceNode(at relativePath: String, to newName: String) async {
        await files.renameNode(at: relativePath, to: newName)
        if let err = files.lastError { self.error = err; files.lastError = nil }
    }
    public func commitFileNameIntent(_ intent: FileNameSheetIntent, name: String) async {
        await files.commitNameIntent(intent, name: name)
        if let err = files.lastError { self.error = err; files.lastError = nil }
    }
    public func deleteWorkspaceNode(at relativePath: String, moveToTrash: Bool = true) async {
        await files.deleteNode(at: relativePath, moveToTrash: moveToTrash)
        if let err = files.lastError { self.error = err; files.lastError = nil }
    }
    public func moveWorkspaceNode(at relativePath: String, to newRelativePath: String) async {
        await files.moveNode(at: relativePath, to: newRelativePath)
        if let err = files.lastError { self.error = err; files.lastError = nil }
    }
    public func deleteSelectedWorkspaceNodes(moveToTrash: Bool = true) async {
        await files.deleteSelected(moveToTrash: moveToTrash)
        if let err = files.lastError { self.error = err; files.lastError = nil }
    }
    public func toggleFileSelection(_ path: String) { files.toggleSelection(path) }
    public func clearFileSelection() { files.clearSelection() }
    public func beginInlineRename(_ path: String) { files.beginInlineRename(path) }
    public func cancelInlineRename() { files.cancelInlineRename() }
    public func commitInlineRename(_ path: String, newName: String) async {
        await files.commitInlineRename(path, newName: newName)
        if let err = files.lastError { self.error = err; files.lastError = nil }
    }

    /// rename 후 imports 업데이트를 agent에게 위임 — 활성 chat에 prompt prepend (ADR-040 F5).
    /// LSP 통합 없이 agent가 grep + 수정 수행하도록 자연어 위임.
    public func askAgentToUpdateImports(oldPath: String, newPath: String) {
        let prompt = """
        파일 이름이 변경됐어요. imports/refs 업데이트가 필요할 수 있어요.

        - 이전: `\(oldPath)`
        - 새 경로: `\(newPath)`

        프로젝트 전체에서 `\(oldPath)`를 참조하는 import / require / include 등을 찾아서 새 경로로 업데이트해주세요. 실제 파일 변경 전에 영향 범위를 먼저 보여주세요.

        """
        // ADR-042 R1.H7 — 사용자 input mutation 대신 안전한 큐에 enqueue
        enqueueComposerPrefix(prompt)
    }

    // ADR-042 R3.2 — Tab sync helpers는 WorkspaceFileManager 내부로 이동

    // MARK: - 다중 터미널 lifecycle (ADR-040 T1) — facade가 TerminalSessionCoordinator로 위임 (ADR-042 R3.1)

    public func createTerminalSession(label: String? = nil) {
        guard let workspace = currentWorkspace else { return }
        terminals.createSession(workingDirectory: workspace.directoryPath, label: label)
        persistCurrentTerminalSessions()
    }

    public func setActiveTerminalSession(_ id: UUID) {
        terminals.setActive(id)
    }

    public func closeTerminalSession(_ id: UUID) {
        terminals.close(id)
        persistCurrentTerminalSessions()
    }

    public func closeActiveTerminalSession() {
        terminals.closeActive()
        persistCurrentTerminalSessions()
    }

    /// NSOpenPanel folder picker로 cwd 변경 — UI dialog는 facade가 책임 (coord는 pure logic).
    public func requestTerminalDirectoryChange(_ id: UUID) {
        guard let session = terminalSessions.first(where: { $0.id == id }) else { return }
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: session.workingDirectory)
        panel.title = "터미널 디렉토리 변경"
        panel.message = "‘\(session.label)’ 세션의 새 작업 디렉토리를 선택하세요"
        if panel.runModal() == .OK, let url = panel.url {
            changeTerminalDirectory(id, to: url.path)
        }
        #endif
    }

    public func changeTerminalDirectory(_ id: UUID, to newPath: String) {
        terminals.changeDirectory(id, to: newPath)
        persistCurrentTerminalSessions()
    }

    public func updateTerminalActivity(_ id: UUID, _ activity: TerminalSession.Activity) {
        terminals.updateActivity(id, activity)
    }

    public func markTerminalSessionRead(_ id: UUID) {
        terminals.markRead(id)
    }

    public func renameTerminalSession(_ id: UUID, to newLabel: String) {
        terminals.rename(id, to: newLabel)
        persistCurrentTerminalSessions()
    }

    public func toggleTerminalSplit() {
        guard let workspace = currentWorkspace else {
            terminals.splitEnabled.toggle()
            return
        }
        terminals.toggleSplit(workingDirectory: workspace.directoryPath)
    }

    public func setSecondaryTerminalSession(_ id: UUID) {
        terminals.setSecondary(id)
    }

    public func selectAdjacentTerminalSession(offset: Int) {
        terminals.selectAdjacent(offset: offset)
    }

    public func toggleTerminalPane() {
        guard let workspace = currentWorkspace else {
            terminals.showPane.toggle()
            return
        }
        terminals.togglePane(workingDirectory: workspace.directoryPath)
    }

    // MARK: - Command Runner facade — CommandRunnerCoordinator로 위임 (ADR-042 R3.3)

    public func copyCommandBlockOutput(_ text: String) {
        commands.copyOutput(text)
    }

    public func shareCommandBlockToAgent(_ block: CommandRunner.CommandResult) {
        let prefix = commands.buildShareToAgentPrefix(block)
        enqueueComposerPrefix(prefix)
    }

    public func runCommand(_ command: String) async {
        guard let workspace = currentWorkspace else { return }
        let workingDir = URL(fileURLWithPath: workspace.directoryPath)
        await commands.run(command, in: workingDir)
        if let err = commands.lastError { self.error = err; commands.lastError = nil }
    }

    /// **ADR-098 P1-1** — Telegram `/run` 진입점. 명령 실행 후 결과를 build log artifact로
    /// 자동 forwarding한다 (store + formatter + `yuminai://log/<uuid>` 딥링크).
    ///
    /// 결과는 `commands.blocks` 마지막 entry에서 추출 — 동일 command를 동시에 실행하면
    /// 두 번째가 첫 번째 결과를 가로채지 않도록 실행 전 카운트를 기준점으로 둔다.
    ///
    /// **ADR-114 P0-1** — `chatId`가 있으면 해당 chat에 bind된 워크스페이스에서 실행한다.
    /// `telegramBotChatBindings`에서 `chatId` 매칭 binding → `activeWorkspaceId`로 조회.
    /// binding 없거나 chatId nil → `currentWorkspace` fallback (legacy 동작 유지).
    public func runCommandFromTelegram(_ command: String, chatId: Int64? = nil) async {
        // ADR-114 P0-1 — chat-specific workspace lookup
        let workspace: Workspace?
        if let chatId,
           let binding = preferences.telegramBotChatBindings.first(where: { $0.chatId == chatId }),
           let wsId = binding.activeWorkspaceId,
           let bound = workspaces.first(where: { $0.id == wsId }) {
            workspace = bound
        } else {
            workspace = currentWorkspace  // fallback: legacy 동작
        }
        guard let workspace else { return }
        let workingDir = URL(fileURLWithPath: workspace.directoryPath)
        let baselineCount = commands.blocks.count
        await commands.run(command, in: workingDir)
        if let err = commands.lastError { self.error = err; commands.lastError = nil }

        // 새로 추가된 block 중 같은 command를 가진 가장 최근 entry를 찾는다.
        let blocks = commands.blocks
        guard blocks.count > baselineCount else { return }
        let candidate = blocks[baselineCount...].last { $0.command == command } ?? blocks.last
        guard let block = candidate else { return }

        let title = String(command.prefix(80))
        let elapsed = TimeInterval(block.durationMs) / 1000.0
        let combined: String
        if block.stderr.isEmpty {
            combined = block.stdout
        } else if block.stdout.isEmpty {
            combined = block.stderr
        } else {
            combined = block.stdout + "\n\n--- stderr ---\n" + block.stderr
        }
        let logBody = combined.isEmpty ? "(no output)\nexit code: \(block.exitCode)" : combined

        if let bridge = sessionBridge {
            await bridge.notifyLogArtifact(
                log: logBody,
                title: title,
                elapsed: elapsed,
                success: block.success
            )
        } else {
            await sendBuildLogToTelegram(
                log: logBody,
                title: title,
                elapsed: elapsed,
                success: block.success
            )
        }
    }

    public func clearCommandBlocks() {
        commands.clear()
    }

    /// Dev server suggestions 로드 + live ping (ADR-036 C1).
    /// debounce — 30초 이내 재호출은 cache 반환.
    public func refreshDevServerSuggestions() async {
        guard let workspace = currentWorkspace else { return }
        let now = Date()
        if now.timeIntervalSince(lastDevServerRefresh) < 30 && !devServerSuggestions.isEmpty {
            return
        }
        let detector = DevServerDetector(workspacePath: workspace.directoryPath)
        let suggestions = detector.detect()
        // background ping
        let pinged = await DevServerDetector.pingAll(suggestions)
        devServerSuggestions = pinged
        lastDevServerRefresh = now
    }

    /// secondary pane에 텍스트를 직접 보내기 (ADR-035 B4 dual-Composer).
    /// 자동으로 그 pane을 활성화 + input swap + sendMessage.
    public func sendToPane(_ paneId: UUID, text: String) async {
        guard agentPanes.contains(where: { $0.id == paneId }) else { return }
        if activePaneId != paneId {
            await setActivePane(paneId)
        }
        inputText = text
        await sendMessage()
    }

    /// 워크스페이스의 파일 본문 read (inline editor용, ADR-036 C3).
    public func readWorkspaceFile(_ relativePath: String) -> String? {
        guard let workspace = currentWorkspace else { return nil }
        let url = URL(fileURLWithPath: workspace.directoryPath).appending(path: relativePath)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// 워크스페이스의 파일 본문 write (inline editor save).
    public func writeWorkspaceFile(_ relativePath: String, contents: String) {
        guard let workspace = currentWorkspace else { return }
        let url = URL(fileURLWithPath: workspace.directoryPath).appending(path: relativePath)
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            // diff 새로고침
            Task {
                if let workspace = self.currentWorkspace {
                    let runner = GitRunner(workspaceURL: URL(fileURLWithPath: workspace.directoryPath))
                    if let snap = await self.checkpointManager.snapshot {
                        let updated = try? await runner.diff()
                        await MainActor.run {
                            if let updated {
                                self.pendingDiff = updated
                            }
                            // changedFiles도 갱신
                            Task {
                                if let files = try? await runner.changedFiles() {
                                    await MainActor.run { self.pendingChanges = files }
                                }
                            }
                            _ = snap
                        }
                    }
                }
            }
        } catch {
            self.error = "파일 저장 실패: \(error.localizedDescription)"
        }
    }

    /// 외부 IDE에서 파일 열기 (system default — 보통 Xcode/VSCode/etc) — ADR-035 B2.
    public func openFileInExternalEditor(_ relativePath: String) {
        guard let workspace = currentWorkspace else { return }
        let fullURL = URL(fileURLWithPath: workspace.directoryPath).appending(path: relativePath)
        guard FileManager.default.fileExists(atPath: fullURL.path) else {
            self.error = "파일을 찾을 수 없어요: \(relativePath)"
            return
        }
        NSWorkspace.shared.open(fullURL)
    }

    // MARK: - Delivery actions (ADR-029 phase B)

    /// 사용자가 수동으로 build/test/lint 실행.
    public func runDelivery(kind: DeliveryResult.Kind) async {
        guard let workspace = currentWorkspace else { return }
        let cfg = workspace.deliveryConfig
        let cmd: String?
        switch kind {
        case .build: cmd = cfg.buildCommand
        case .test: cmd = cfg.testCommand
        case .lint: cmd = cfg.lintCommand
        }
        guard let command = cmd?.trimmingCharacters(in: .whitespaces), !command.isEmpty else {
            self.error = "\(kind.label) 명령이 설정되지 않았어요. 워크스페이스 설정에서 추가하세요."
            return
        }
        isDeliveryRunning = true
        let result = await deliveryRunner.runOnce(workspace: workspace, kind: kind, command: command)
        isDeliveryRunning = false
        delivery.appendResult(result)
    }

    public func clearDeliveryResults() {
        delivery.clear()
    }

    /// Workspace의 deliveryConfig 갱신 + 영속.
    public func updateDeliveryConfig(_ config: DeliveryConfig) async {
        guard let workspace = currentWorkspace else { return }
        let updated = workspace.with(deliveryConfig: config)
        do {
            try await workspaceStore.update(updated)
            if let idx = workspaces.firstIndex(where: { $0.id == updated.id }) {
                workspaces[idx] = updated
            }
            await deliveryRunner.resetAttempts(for: updated.id)
        } catch {
            self.error = "Delivery 설정 저장 실패: \(error.localizedDescription)"
        }
    }

    private func forwardToBridgeIfBound(_ event: ClaudeEvent) {
        guard let bridge = sessionBridge,
              let bound = preferences.telegramBoundWorkspaceId,
              selectedWorkspaceId == bound
        else { return }
        // ADR-057 Critical Fix 6 — workspace switching 도중 stale event 차단.
        // 이벤트 발행 시점의 workspace id를 캡처 → consume 시점에 여전히 같은지 확인.
        // (사용자가 workspace 빠르게 switching하면 이전 workspace의 이벤트가 새 chat에 forward 가능)
        let capturedWorkspace = bound
        Task {
            // consume 시점에도 여전히 bound + active가 같은지 재확인 (race 차단)
            let stillBound = await MainActor.run { self.preferences.telegramBoundWorkspaceId == capturedWorkspace && self.selectedWorkspaceId == capturedWorkspace }
            guard stillBound else { return }
            await bridge.consume(event: event)
        }
    }

    private func appendMessage(role: Message.Role, content: String) {
        guard let session = currentSession else { return }
        // **ADR-115 P1-2** — assistant 응답에 attribution 첨부 (1회 소비).
        let attribution: MessageAttribution?
        if role == .assistant {
            attribution = pendingAttribution
            pendingAttribution = nil
        } else {
            attribution = nil
        }
        let msg = Message(sessionId: session.id, role: role, content: content, attribution: attribution)
        messages.append(msg)
        let store = sessionStore
        Task { try? await store.append(msg) }
    }

    private func teardownCurrentSession() async {
        streamConsumeTask?.cancel()
        streamConsumeTask = nil

        // 모든 secondary pane sessions terminate (active pane은 별도)
        if let workspace = currentWorkspace {
            for pane in agentPanes {
                if let session = paneSessions[pane.id], pane.id != activePaneId {
                    let paneWorkspace = workspace.with(agentKind: pane.agentKind)
                    let ad = adapter(for: paneWorkspace)
                    await ad.terminate(session)
                }
            }
        }

        if let claudeSession = currentClaudeSession {
            await activeAdapter.terminate(claudeSession)
        }
        currentClaudeSession = nil
        currentSession = nil
        messages = []
        isStreaming = false

        // pane state 정리 — workspace 전환 시 새 primary pane이 다시 생성됨
        clearPaneState()
    }

    // MARK: - chat

    // MARK: - Composer prefix queue (ADR-042 R1.H7)

    // MARK: - ADR-104 — Setup Wizard

    /// 모든 도구의 설치 상태를 재검사하고 `setupToolStatus`를 갱신.
    public func refreshSetupStatus() async {
        let result = await setupChecker.checkAll()
        setupToolStatus = result
    }

    /// Setup wizard를 명시적으로 열기 (Help 메뉴 등에서 사용).
    public func openSetupWizard() {
        Task { await refreshSetupStatus() }
        presentExclusiveSheet { $0.showSetupWizard = true }
    }

    /// Setup wizard 닫기.
    /// - Parameter markCompleted: true이면 `hasCompletedSetup = true`로 저장. false이면 다음 실행 시 다시 표시.
    ///
    /// **ADR-115 P1-3** — 완료 시 프로필이 비어 있으면 300ms 후 프로필 sheet를 자동으로 표시한다.
    /// 애니메이션 완료 후 열어야 자연스럽게 나타난다.
    public func dismissSetupWizard(markCompleted: Bool) {
        showSetupWizard = false
        if markCompleted {
            preferences.hasCompletedSetup = true
            Task { await savePreferences() }
            // ADR-115 P1-3 — 프로필 미입력이면 setup 닫힘 후 프로필 sheet 자동 유도
            if preferences.userProfile.isEmpty {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000)  // 0.3s — sheet 닫힘 애니메이션 대기
                    self.showUserProfileSheet = true
                }
            }
        }
    }

    // MARK: - Sheet mutual exclusion (ADR-042 R5.A)

    /// 모든 sheet/alert state를 한 번에 닫음 — 새 sheet 열기 전에 호출.
    /// SwiftUI는 같은 view에 여러 sheet binding이 동시 true가 되면 동작 미정 — 이 helper로 강제 mutual exclusion.
    public func dismissAllSheets() {
        showCreateWorkspaceSheet = false
        showUsageDashboard = false
        showDisambigSheet = false
        showCreateNoteSheet = false
        showShortcutHelp = false
        showFileSearchSheet = false
        showDeliverySheet = false
        fileNameSheetIntent = nil
        fileDeleteConfirmation = nil
        renameSheetPane = nil
        terminalRenameTargetId = nil
        editingProjectProfileForWorkspaceId = nil
        showCommandPalette = false
        walkthroughTaskId = nil
        showHarnessHelp = false
        showRoutingLog = false
        rehearsalTaskId = nil
        showChartsDashboard = false
        showTelegramUsageDashboard = false
        showChatBindingAuditLog = false
        showAbout = false
        // ADR-076 + ADR-078 Phase 3 + Phase 4
        showFolderRenameSheet = false
        folderRenameTargetId = nil
        showWorkspaceSearchSheet = false
        showTagEditSheet = false
        tagEditTargetId = nil
        // ADR-079 Phase 4-5 + ADR-081 Phase 4 + ADR-082 Phase 1-2
        showGitCommitSheet = false
        showGitBranchPicker = false
        showGitStashSheet = false
        showGitDiffSheet = false
        showGitHubPRSheet = false
        showGitRebaseSheet = false
        // ADR-083
        showGitConflictSheet = false
        showGitCherryPickSheet = false
        // ADR-084 + ADR-086
        showTelegramAdvancedSheet = false
        showTelegramErrorLogSheet = false
        showTelegramBotManagerSheet = false
        // ADR-092
        showTelegramHubSheet = false
        // ADR-089
        showNewChatSessionSheet = false
        // ADR-104
        showSetupWizard = false
    }

    /// 새 sheet/alert을 열기 전에 다른 sheet 모두 닫고 setter 실행.
    /// 사용 예: `appModel.presentExclusiveSheet { $0.showFileSearchSheet = true }`
    public func presentExclusiveSheet(_ setter: (AppModel) -> Void) {
        dismissAllSheets()
        setter(self)
    }

    /// 외부 caller가 composer에 prefix 삽입을 요청할 때 사용. 사용자 입력은 절대 직접 mutation 하지 않음.
    /// Composer view가 onChange(of: pendingComposerPrefix)로 consume하고 즉시 nil 클리어.
    /// 누적 호출 시 새 prefix가 기존 큐 위에 다시 prepend (가장 최근 액션이 가장 위).
    public func enqueueComposerPrefix(_ prefix: String) {
        if let existing = pendingComposerPrefix {
            pendingComposerPrefix = prefix + existing
        } else {
            pendingComposerPrefix = prefix
        }
    }

    /// Composer가 consume 후 호출. State 클리어.
    public func consumeComposerPrefix() -> String? {
        defer { pendingComposerPrefix = nil }
        return pendingComposerPrefix
    }

    /// ADR-042 R1.H2 — sendMessage 직전 토큰 size 추정 (UTF-8 byte / 4 ≈ token).
    /// 50KB 초과면 사용자 confirmation 요청 (return false면 send 취소).
    public func warnIfOversizedPrompt(_ body: String) -> Bool {
        let estimatedTokens = body.utf8.count / 4
        if estimatedTokens > 50_000 {
            self.error = "메시지가 매우 큽니다 (~\(estimatedTokens / 1000)K 토큰). 컨텍스트 윈도우를 빠르게 소모해요. 첨부 파일/명령 결과 share를 줄이세요."
            return false
        }
        return true
    }

    public func sendMessage() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAttachments = !attachedFiles.isEmpty
        guard (!trimmed.isEmpty || hasAttachments),
              !isStreaming else { return }

        // ADR-048 Phase 3 — 자동 routing 검사 (활성 pane이 바뀔 수 있으므로 session 캡처 전에)
        if let handoffPrefix = await applyHarnessAutoRoutingIfNeeded(userText: trimmed) {
            // pane 전환됐으므로 이전 inputText에 handoff prepend
            inputText = handoffPrefix + inputText
        }

        // session 재캡처 (routing 후 바뀐 active pane 기준)
        guard let session = currentSession,
              let claudeSession = currentClaudeSession else { return }

        // ADR-048 — routing이 inputText에 handoff prefix를 추가했을 수 있으므로 재trim
        let effectiveInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        // ADR-111 — 라이브러리 항목 prepend (첨부된 라이브러리 자료를 메시지 앞에 삽입)
        let libraryPreamble: String
        // ADR-115 P1-2 — attribution 캡처 (클리어 전에)
        let libraryItemNames = attachedLibraryItems.map(\.displayName)
        if !attachedLibraryItems.isEmpty {
            let sections = attachedLibraryItems.map { item in
                "--- 첨부 자료: \(item.displayName) ---\n\(item.content.trimmingCharacters(in: .whitespacesAndNewlines))\n---"
            }.joined(separator: "\n\n")
            libraryPreamble = "\(sections)\n\n"
        } else {
            libraryPreamble = ""
        }
        attachedLibraryItems = []  // 송신 후 자동 클리어

        // ADR-115 P1-2 — 사용자 프로필 스냅샷 요약 캡처
        let profileSummary: String? = {
            guard !preferences.userProfile.isEmpty else { return nil }
            let job = preferences.userProfile.jobTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let goal = preferences.userProfile.primaryGoal.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = [job, goal].filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }()

        // attribution은 라이브러리나 프로필이 하나라도 있을 때만 생성
        if !libraryItemNames.isEmpty || profileSummary != nil {
            pendingAttribution = MessageAttribution(
                attachedLibraryItems: libraryItemNames,
                profileSnapshotSummary: profileSummary
            )
        } else {
            pendingAttribution = nil
        }

        // 첨부 prepend — Claude Code의 @ mention 구문
        let attachmentPreamble: String
        if hasAttachments {
            let mentions = attachedFiles.map { "@\($0.path)" }.joined(separator: "\n")
            attachmentPreamble = "다음 파일이 첨부됐어요:\n\(mentions)\n\n"
        } else {
            attachmentPreamble = ""
        }

        // Delivery 실패 feedback이 대기 중이면 user prompt 앞에 prepend (소극적 fix loop)
        let failurePrefix = pendingFailureFeedback
        if !failurePrefix.isEmpty {
            pendingFailureFeedback = ""
        }

        // ADR-111 — libraryPreamble은 다른 preamble보다 앞에 위치 (LLM이 자료를 먼저 참고)
        let bodyForUser = effectiveInput.isEmpty
            ? (failurePrefix + libraryPreamble + attachmentPreamble).trimmingCharacters(in: .whitespacesAndNewlines)
            : failurePrefix + libraryPreamble + attachmentPreamble + effectiveInput

        let userMsg = Message(sessionId: session.id, role: .user, content: bodyForUser)
        messages.append(userMsg)
        try? await sessionStore.append(userMsg)
        currentSessionUsage.messageCount += 1
        allTimeUsage.messageCount += 1

        // ADR-047 Phase 2 — SharedConversationLog에 user entry 기록 (다중 모델 컨텍스트 보존용)
        let attachmentPaths = attachedFiles.map(\.path)
        harness.appendUser(bodyForUser, attachments: attachmentPaths)

        inputText = ""
        attachedFiles = []  // 송신 후 자동 클리어
        isStreaming = true

        // bound 워크스페이스에서 보낸 turn이면 bridge에게 시작 알림
        if let bridge = sessionBridge,
           let bound = preferences.telegramBoundWorkspaceId,
           selectedWorkspaceId == bound {
            let preview = bodyForUser
            Task { await bridge.notifyTurnStart(userText: preview) }
        }

        // Checkpoint 시작 — git 저장소면 HEAD SHA 기록
        if let workspace = currentWorkspace {
            let cm = checkpointManager
            Task { await cm.beginTurn(workspace: workspace) }
        }

        do {
            try await claudeSession.send(bodyForUser)
        } catch {
            self.error = "전송 실패: \(error.localizedDescription)"
            isStreaming = false
        }
    }

    /// 활성 워크스페이스 — checkpoint/diff 등에서 사용.
    public var currentWorkspace: Workspace? {
        guard let id = selectedWorkspaceId else { return nil }
        return workspaces.first { $0.id == id }
    }

    // MARK: - 첨부

    public func openAttachmentPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Claude가 함께 살펴볼 파일이나 폴더를 선택하세요. 여러 개 선택할 수 있어요."
        panel.prompt = "첨부"
        if panel.runModal() == .OK {
            for url in panel.urls where !attachedFiles.contains(url) {
                // ADR-042 R1.H5 — 디렉토리 또는 1MB+ 파일 첨부 시 사용자 confirmation
                // (CLI가 @<path>를 inline expand하므로 node_modules 같은 큰 디렉토리는 토큰 폭발 위험)
                if shouldConfirmAttachment(url: url) {
                    if !confirmLargeAttachment(url: url) { continue }
                }
                attachedFiles.append(url)
            }
        }
    }

    /// 첨부 size sniff. directory 또는 1MB+ 파일이면 true.
    private func shouldConfirmAttachment(url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return false }
        if isDir.boolValue { return true }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int, size > 1_000_000 {
            return true
        }
        return false
    }

    /// NSAlert로 사용자 확인. 사용자 OK = true, 취소 = false.
    private func confirmLargeAttachment(url: URL) -> Bool {
        #if canImport(AppKit)
        let alert = NSAlert()
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if isDir.boolValue {
            alert.messageText = "‘\(url.lastPathComponent)’ 폴더를 첨부할까요?"
            alert.informativeText = "Claude Code는 폴더 안의 모든 파일을 읽으려고 시도해요. node_modules, .git, build 결과물 같은 큰 폴더는 컨텍스트를 매우 빠르게 소진합니다.\n\n진짜로 첨부하려면 ‘첨부’를, 아니면 ‘취소’를 눌러주세요."
            alert.alertStyle = .warning
        } else {
            let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
            let mb = Double((attrs[.size] as? Int) ?? 0) / (1024 * 1024)
            alert.messageText = "‘\(url.lastPathComponent)’ 파일이 큽니다 (~\(String(format: "%.1f", mb))MB)"
            alert.informativeText = "이 파일을 inline으로 첨부하면 컨텍스트의 큰 부분을 차지합니다. 정말 필요한 부분만 직접 인용하는 게 보통 더 좋아요."
            alert.alertStyle = .informational
        }
        alert.addButton(withTitle: "첨부")
        alert.addButton(withTitle: "취소")
        return alert.runModal() == .alertFirstButtonReturn
        #else
        return true
        #endif
    }

    public func removeAttachment(_ url: URL) {
        attachedFiles.removeAll { $0 == url }
    }

    public func clearAttachments() {
        attachedFiles.removeAll()
    }

    public func cancelStream() {
        streamConsumeTask?.cancel()
        if let claudeSession = currentClaudeSession {
            let adapter = activeAdapter
            Task { await adapter.terminate(claudeSession) }
        }
        isStreaming = false
        // ADR-055 HIGH 2 — 진행 중인 ChildProcess도 모두 kill
        // (decomposition / rehearsal / parallel 격리 호출이 cancel 안 되던 문제 수정)
        if let child = childProcess {
            Task { await child.cancelAll() }
        }
        // 진행 중 progress badge들도 cancelled로 (UI 즉시 반응)
        for idx in activeChildProcesses.indices where activeChildProcesses[idx].status == .running || activeChildProcesses[idx].status == .starting {
            activeChildProcesses[idx].status = .failed
        }
        // ADR-057 Critical Fix 3 — pending decomposition flag도 reset
        // (cancel 후 다음 turn에서 잘못된 메시지를 분해 결과로 parse 시도하는 bug 방지)
        pendingDecomposition = false
        // ADR-057 Critical Fix 6 보호: streaming buffer/agent buffer도 깨끗이
        harnessAgentBuffer = ""
    }

    // MARK: - secrets

    public func saveAnthropicKey(_ value: String) async {
        do {
            try await keychainStore.set(value, for: KeychainKey.anthropicAPIKey)
            anthropicKeyStatus = .set
        } catch {
            anthropicKeyStatus = .error(error.localizedDescription)
        }
    }

    public func clearAnthropicKey() async {
        try? await keychainStore.remove(KeychainKey.anthropicAPIKey)
        anthropicKeyStatus = .notSet
    }

    public func saveTelegramToken(_ value: String) async {
        do {
            try await keychainStore.set(value, for: KeychainKey.telegramBotToken)
            telegramTokenStatus = .set
            await activateTelegramIfReady()
        } catch {
            telegramTokenStatus = .error(error.localizedDescription)
        }
    }

    public func clearTelegramToken() async {
        try? await keychainStore.remove(KeychainKey.telegramBotToken)
        telegramTokenStatus = .notSet
        await deactivateTelegram()
    }

    public func savePreferences() async {
        do {
            try await preferencesStore.save(preferences)
        } catch {
            self.error = "Preferences 저장 실패: \(error.localizedDescription)"
        }
        await activateTelegramIfReady()
        await setupObsidianVault()
    }

    // MARK: - ADR-106 — 사용자 프로필

    /// 프로필 갱신 + 모든 워크스페이스의 .harness/rules/USER_PROFILE.md + CLAUDE.md 자동 동기화.
    /// ADR-108: 3-pronged 주입 전략
    ///   1) system prompt — adapter의 userProfileProvider가 다음 spawn 시 자동 반영
    ///   2) .harness/rules/USER_PROFILE.md — 기존 방식 유지
    ///   3) <workspace>/CLAUDE.md marker 동기화 — Claude Code 자동 읽기
    public func updateUserProfile(_ profile: UserProfile) async {
        preferences.userProfile = profile
        await savePreferences()
        // 모든 워크스페이스에 프로필 파일 동기화
        for workspace in workspaces {
            let wsURL = URL(fileURLWithPath: workspace.directoryPath)
            await syncUserProfileTo(workspaceURL: wsURL)
            await syncUserProfileToCLAUDEMd(workspaceURL: wsURL)
        }
    }

    /// 프로필 이미지 선택 (NSOpenPanel). 선택된 파일을 앱 지원 디렉토리에 복사 후 경로 반환.
    @MainActor
    public func selectUserProfileImage() async -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "프로필 사진을 선택하세요"
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        do {
            let fm = FileManager.default
            let supportDir = try fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("Yuminai", isDirectory: true)
            try fm.createDirectory(at: supportDir, withIntermediateDirectories: true)
            let ext = url.pathExtension
            let destURL = supportDir.appendingPathComponent("profile-image.\(ext)")
            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            try fm.copyItem(at: url, to: destURL)
            return destURL.path
        } catch {
            self.error = "프로필 사진 복사 실패: \(error.localizedDescription)"
            return nil
        }
    }

    /// 단일 워크스페이스에 USER_PROFILE.md 작성/갱신.
    /// .harness 디렉토리가 없으면 skip (해당 워크스페이스는 하네스 미사용).
    private func syncUserProfileTo(workspaceURL: URL) async {
        let layout = HarnessLayout(workspaceURL: workspaceURL)
        let fm = FileManager.default
        guard fm.fileExists(atPath: layout.harnessURL.path) else { return }
        let fileURL = layout.rulesURL.appendingPathComponent("USER_PROFILE.md")
        do {
            try fm.createDirectory(at: layout.rulesURL, withIntermediateDirectories: true)
            let content = preferences.userProfile.renderHarnessRules()
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            logger.error("USER_PROFILE.md 동기화 실패 (\(workspaceURL.lastPathComponent)): \(error.localizedDescription)")
        }
    }

    /// ADR-108 — 단일 워크스페이스의 CLAUDE.md에 Yuminai 프로필 섹션을 동기화.
    /// Claude Code는 <workspace>/CLAUDE.md를 자동으로 읽으므로 (Anthropic 공식),
    /// begin/end marker 사이만 갱신해 사용자 자체 내용은 보존한다.
    /// 워크스페이스 디렉토리가 없으면 skip.
    private func syncUserProfileToCLAUDEMd(workspaceURL: URL) async {
        let fm = FileManager.default
        guard fm.fileExists(atPath: workspaceURL.path) else { return }

        let mdURL = workspaceURL.appendingPathComponent("CLAUDE.md")
        let existing = try? String(contentsOf: mdURL, encoding: .utf8)

        let profileSection: String
        if preferences.userProfile.isEmpty {
            // 프로필 비어있으면 marker 블록 제거
            profileSection = ""
        } else {
            profileSection = preferences.userProfile.renderForCLAUDEMd()
        }

        let merged = CLAUDEMdMerger.merge(existing: existing, profileSection: profileSection)

        do {
            try merged.write(to: mdURL, atomically: true, encoding: .utf8)
        } catch {
            logger.error("CLAUDE.md 동기화 실패 (\(workspaceURL.lastPathComponent)): \(error.localizedDescription)")
        }
    }

    // MARK: - ADR-109 — 커뮤니티 자료 적용

    /// 커뮤니티 자료를 현재 워크스페이스에 적용한다.
    ///
    /// - `category == .claudeMd`: rawURL 다운로드 → CLAUDE.md에 마커 블록으로 삽입
    /// - `category == .skill`: `.harness/skills/<resource.id>.md`에 저장
    /// - `category == .template`: GitHub 안내 메시지 반환 (다운로드 없음)
    ///
    /// 사용자가 명시적으로 [적용] 버튼을 누를 때만 호출된다 (자동 다운로드 없음).
    /// 다운로드 전에 UI에서 URL과 내용을 먼저 표시한다.
    public func applyCommunityResource(
        _ resource: CommunityResource,
        to workspaceURL: URL
    ) async -> Result<String, Error> {
        switch resource.category {
        case .template:
            return .success("GitHub 리포지토리를 직접 클론하거나 다운로드하세요.")

        case .claudeMd, .styleGuide, .workflow, .architecture, .promptPattern, .rules,
             .webFramework, .mobileFramework, .graphics3D, .backend, .database, .devops:
            guard let rawURL = resource.rawURL else {
                return .failure(CommunityResourceError.noRawURL)
            }
            return await downloadAndAppendToCLAUDEMd(rawURL: rawURL, resource: resource, workspaceURL: workspaceURL)

        case .skill, .mcp:
            guard let rawURL = resource.rawURL else {
                return .failure(CommunityResourceError.noRawURL)
            }
            return await downloadAndSaveSkill(rawURL: rawURL, resource: resource, workspaceURL: workspaceURL)
        }
    }

    private func downloadAndAppendToCLAUDEMd(
        rawURL: URL,
        resource: CommunityResource,
        workspaceURL: URL
    ) async -> Result<String, Error> {
        do {
            let content = try await downloadRawContent(from: rawURL)
            let mdURL = workspaceURL.appendingPathComponent("CLAUDE.md")
            let existing = try? String(contentsOf: mdURL, encoding: .utf8)

            let beginMarker = "<!-- BEGIN COMMUNITY: \(resource.id) -->"
            let endMarker = "<!-- END COMMUNITY: \(resource.id) -->"

            // 이미 적용된 경우 기존 블록 교체
            let block = "\(beginMarker)\n\(content.trimmingCharacters(in: .whitespacesAndNewlines))\n\(endMarker)"

            let merged: String
            if let existing {
                if existing.contains(beginMarker) {
                    // 기존 블록 교체
                    let pattern = "\(NSRegularExpression.escapedPattern(for: beginMarker)).*?\(NSRegularExpression.escapedPattern(for: endMarker))"
                    if let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) {
                        let range = NSRange(existing.startIndex..., in: existing)
                        merged = regex.stringByReplacingMatches(in: existing, range: range, withTemplate: block)
                    } else {
                        merged = existing + "\n\n" + block
                    }
                } else {
                    let separator = existing.hasSuffix("\n\n") ? "" : existing.hasSuffix("\n") ? "\n" : "\n\n"
                    merged = existing + separator + block
                }
            } else {
                merged = block
            }

            try merged.write(to: mdURL, atomically: true, encoding: .utf8)
            return .success("\(resource.displayName)를 CLAUDE.md에 추가했어요.")
        } catch {
            logger.error("커뮤니티 자료 CLAUDE.md 적용 실패: \(error.localizedDescription)")
            return .failure(error)
        }
    }

    private func downloadAndSaveSkill(
        rawURL: URL,
        resource: CommunityResource,
        workspaceURL: URL
    ) async -> Result<String, Error> {
        do {
            let content = try await downloadRawContent(from: rawURL)
            let layout = HarnessLayout(workspaceURL: workspaceURL)
            let fm = FileManager.default
            let skillsURL = layout.harnessURL.appendingPathComponent("skills", isDirectory: true)
            try fm.createDirectory(at: skillsURL, withIntermediateDirectories: true)
            let fileURL = skillsURL.appendingPathComponent("\(resource.id).md")
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return .success("\(resource.displayName) Skill을 .harness/skills/에 저장했어요.")
        } catch {
            logger.error("커뮤니티 자료 Skill 저장 실패: \(error.localizedDescription)")
            return .failure(error)
        }
    }

    /// URL에서 원본 텍스트를 다운로드한다.
    /// - timeout: 60s (큰 파일 대비 ADR-111).
    /// - 에러: CommunityResourceError (네트워크 / HTTP 4xx / HTTP 5xx / encoding).
    private func downloadRawContent(from url: URL) async throws -> String {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60
        let session = URLSession(configuration: config)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw CommunityResourceError.networkError(error)
        }
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw CommunityResourceError.httpErrorWithURL(url, httpResponse.statusCode)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw CommunityResourceError.invalidEncoding
        }
        return text
    }

    // MARK: - ADR-111 라이브러리 관리

    /// 라이브러리 디렉토리 URL: `~/Library/Application Support/Yuminai/library/`
    private var libraryDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Yuminai/library", isDirectory: true)
    }

    /// 라이브러리 항목의 디스크 URL.
    private func libraryFileURL(for id: UUID) -> URL {
        libraryDirectoryURL.appendingPathComponent("\(id.uuidString).md")
    }

    /// 라이브러리 디렉토리를 생성한다 (없으면).
    private func ensureLibraryDirectory() throws {
        let fm = FileManager.default
        let dir = libraryDirectoryURL
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// 커뮤니티 자료 다운로드 → 라이브러리 추가.
    /// 다운로드 실패 시 명확한 에러 (URL + status + suggestion).
    public func addToLibraryFromCommunity(_ resource: CommunityResource) async -> Result<ResourceLibraryItem, Error> {
        guard let rawURL = resource.rawURL else {
            return .failure(LibraryItemError.noRawURL)
        }

        let content: String
        do {
            content = try await downloadRawContent(from: rawURL)
        } catch let err as CommunityResourceError {
            return .failure(err)
        } catch {
            return .failure(LibraryItemError.networkError(rawURL, error))
        }

        // 이미 라이브러리에 있으면 기존 항목 반환 (중복 방지)
        if let existing = preferences.libraryItems.first(where: { item in
            if case .community(let rid, _) = item.source { return rid == resource.id }
            return false
        }) {
            return .success(existing)
        }

        let item = ResourceLibraryItem(
            displayName: resource.displayName,
            category: resource.category,
            source: .community(resourceId: resource.id, originalURL: rawURL),
            content: content,
            tags: resource.tags
        )

        do {
            try ensureLibraryDirectory()
            let fileURL = libraryFileURL(for: item.id)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            return .failure(LibraryItemError.diskWriteError(libraryDirectoryURL, error))
        }

        preferences = { var p = preferences; p.libraryItems.append(item); return p }()
        await savePreferences()
        logger.info("라이브러리에 추가: \(item.displayName) [\(item.id)]")
        return .success(item)
    }

    /// **ADR-113** — 스택 번들의 모든 자료를 라이브러리에 추가.
    ///
    /// 번들의 `resourceIds`를 순회하며 `CommunityCatalog.curated`에서 자료를 찾아 다운로드한다.
    /// rawURL이 없거나 다운로드 실패한 자료는 건너뛰고 로그를 남긴다.
    /// - Returns: 성공적으로 추가된 항목 배열 (부분 성공 허용).
    public func addBundleToLibrary(_ bundle: StackBundle) async -> [ResourceLibraryItem] {
        let all = CommunityCatalog.curated
        var added: [ResourceLibraryItem] = []

        for resourceId in bundle.resourceIds {
            guard let resource = all.first(where: { $0.id == resourceId }) else {
                logger.warning("번들 자료 미발견: \(resourceId) [\(bundle.displayName)]")
                continue
            }
            guard resource.rawURL != nil else {
                logger.info("번들 자료 rawURL 없음 (건너뜀): \(resource.displayName)")
                continue
            }
            let result = await addToLibraryFromCommunity(resource)
            switch result {
            case .success(let item):
                added.append(item)
            case .failure(let err):
                logger.error("번들 자료 추가 실패: \(resource.displayName) — \(err.localizedDescription)")
            }
        }

        logger.info("번들 추가 완료: \(bundle.displayName) — \(added.count)/\(bundle.resourceIds.count)개 추가")
        return added
    }

    /// 사용자 직접 URL → 라이브러리 추가.
    public func addToLibraryFromURL(
        _ url: URL,
        displayName: String,
        category: CommunityResource.Category
    ) async -> Result<ResourceLibraryItem, Error> {
        let content: String
        do {
            content = try await downloadRawContent(from: url)
        } catch let err as CommunityResourceError {
            return .failure(err)
        } catch {
            return .failure(LibraryItemError.networkError(url, error))
        }

        let item = ResourceLibraryItem(
            displayName: displayName.isEmpty ? (url.lastPathComponent.isEmpty ? "자료" : url.lastPathComponent) : displayName,
            category: category,
            source: .userImport(originalURL: url),
            content: content,
            tags: []
        )

        do {
            try ensureLibraryDirectory()
            try content.write(to: libraryFileURL(for: item.id), atomically: true, encoding: .utf8)
        } catch {
            return .failure(LibraryItemError.diskWriteError(libraryDirectoryURL, error))
        }

        preferences = { var p = preferences; p.libraryItems.append(item); return p }()
        await savePreferences()
        return .success(item)
    }

    /// 사용자 직접 텍스트 입력 → 라이브러리 추가.
    public func addToLibraryFromText(
        _ content: String,
        displayName: String,
        category: CommunityResource.Category,
        tags: [String]
    ) async -> ResourceLibraryItem {
        let item = ResourceLibraryItem(
            displayName: displayName.isEmpty ? "사용자 자료" : displayName,
            category: category,
            source: .userText,
            content: content,
            tags: tags
        )

        if let _ = try? ensureLibraryDirectory() {}
        try? content.write(to: libraryFileURL(for: item.id), atomically: true, encoding: .utf8)

        preferences = { var p = preferences; p.libraryItems.append(item); return p }()
        await savePreferences()
        return item
    }

    /// 라이브러리 항목 삭제 (디스크 + preferences).
    public func removeLibraryItem(_ id: UUID) async {
        let fileURL = libraryFileURL(for: id)
        try? FileManager.default.removeItem(at: fileURL)
        preferences = { var p = preferences; p.libraryItems.removeAll { $0.id == id }; return p }()
        await savePreferences()
    }

    /// 라이브러리 항목 수정 (displayName / notes / tags).
    public func updateLibraryItem(_ item: ResourceLibraryItem) async {
        preferences = { var p = preferences
            if let idx = p.libraryItems.firstIndex(where: { $0.id == item.id }) {
                p.libraryItems[idx] = item
            }
            return p
        }()
        await savePreferences()
    }

    /// 라이브러리 항목 → 메시지 첨부용 파일 URL.
    /// 파일이 디스크에 없으면 재생성 후 반환.
    public func attachmentURL(for libraryItem: ResourceLibraryItem) async -> URL? {
        let fileURL = libraryFileURL(for: libraryItem.id)
        let fm = FileManager.default
        if !fm.fileExists(atPath: fileURL.path) {
            // 재생성 시도
            do {
                try ensureLibraryDirectory()
                try libraryItem.content.write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                logger.error("라이브러리 첨부 파일 생성 실패: \(error.localizedDescription)")
                return nil
            }
        }
        return fileURL
    }

    /// 특정 CommunityResource가 이미 라이브러리에 있는지 확인.
    public func isInLibrary(_ resource: CommunityResource) -> Bool {
        preferences.libraryItems.contains { item in
            if case .community(let rid, _) = item.source { return rid == resource.id }
            return false
        }
    }

    // MARK: - ADR-111 라이브러리 첨부파일

    /// 현재 Composer에 첨부된 라이브러리 항목 목록.
    public var attachedLibraryItems: [ResourceLibraryItem] = []

    /// 라이브러리 항목을 Composer에 첨부.
    public func attachLibraryItem(_ item: ResourceLibraryItem) {
        guard !attachedLibraryItems.contains(item) else { return }
        attachedLibraryItems.append(item)
    }

    /// Composer에서 라이브러리 항목 첨부 제거.
    public func removeLibraryItemAttachment(_ item: ResourceLibraryItem) {
        attachedLibraryItems.removeAll { $0.id == item.id }
    }

    /// Composer 라이브러리 첨부 전체 제거.
    public func clearLibraryItemAttachments() {
        attachedLibraryItems = []
    }

    /// ADR-111 — 라이브러리 sheet 표시 여부.
    public var showLibrarySheet: Bool = false

    /// ADR-112 — 카탈로그 전체 탐색 sheet 표시 여부.
    public var showCatalogSheet: Bool = false

    /// **ADR-113** — 스택 번들 카탈로그 sheet 표시 여부.
    public var showBundleCatalogSheet: Bool = false

    /// **ADR-116** — GitHub 검색 sheet 표시 여부.
    public var showGitHubSearchSheet: Bool = false

    /// ADR-111 — 라이브러리 picker popover 표시 여부 (Composer 안).
    public var showLibraryPickerPopover: Bool = false

    public func selectClaudeBinary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Claude CLI 실행 파일을 선택하세요"
        if panel.runModal() == .OK, let url = panel.url {
            preferences.claudeBinaryPath = url.path
            Task { await savePreferences() }
        }
    }

    public func selectCodexBinary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Codex CLI 실행 파일을 선택하세요"
        if panel.runModal() == .OK, let url = panel.url {
            preferences.codexBinaryPath = url.path
            Task { await savePreferences() }
        }
    }

    // MARK: - telegram

    public func sendTelegramTest() async {
        guard let bot = telegramBot, let chatId = preferences.telegramChatId else {
            self.error = "Telegram 미설정"
            return
        }
        do {
            _ = try await bot.send("[YUMINAI TEST] 연결 성공", to: chatId)
        } catch {
            self.error = "Telegram 테스트 실패: \(error.localizedDescription)"
        }
    }

    // MARK: - ADR-099 P1-1/P1-2/P1-3 — Artifact + Formatter + LargePayload wire-up

    /// diff를 formatter로 포맷 → artifact store 저장 → LargePayloadSender로 발송.
    ///
    /// `TelegramSendHelper.sendDiffPreview`의 AppModel 진입점.
    /// - Returns: 저장된 artifact UUID (nil이면 Telegram 미설정)
    @discardableResult
    public func sendDiffPreviewToTelegram(
        diff: String,
        files: Int,
        added: Int,
        removed: Int,
        workspace: String?,
        chatId: Int64? = nil
    ) async -> UUID? {
        guard let bot = telegramBot else { return nil }
        let targetChatId = chatId ?? preferences.telegramChatId
        guard let targetChatId else { return nil }
        do {
            return try await TelegramSendHelper.sendDiffPreview(
                diff: diff,
                files: files,
                added: added,
                removed: removed,
                workspace: workspace,
                to: targetChatId,
                store: telegramArtifactStore,
                client: bot
            )
        } catch {
            logger.error("sendDiffPreviewToTelegram 실패: \(error.localizedDescription)")
            return nil
        }
    }

    /// build/test log를 formatter로 포맷 → artifact store 저장 → LargePayloadSender로 발송.
    ///
    /// `TelegramSendHelper.sendBuildLog`의 AppModel 진입점.
    /// - Returns: 저장된 artifact UUID (nil이면 Telegram 미설정)
    @discardableResult
    public func sendBuildLogToTelegram(
        log: String,
        title: String,
        elapsed: TimeInterval,
        success: Bool,
        chatId: Int64? = nil
    ) async -> UUID? {
        guard let bot = telegramBot else { return nil }
        let targetChatId = chatId ?? preferences.telegramChatId
        guard let targetChatId else { return nil }
        // ADR-115 P1-1 — 현재 워크스페이스 이름을 prefix로 전달
        let wsName: String? = currentWorkspace?.name
        do {
            return try await TelegramSendHelper.sendBuildLog(
                log: log,
                title: title,
                elapsed: elapsed,
                success: success,
                to: targetChatId,
                workspaceName: wsName,
                store: telegramArtifactStore,
                client: bot
            )
        } catch {
            logger.error("sendBuildLogToTelegram 실패: \(error.localizedDescription)")
            return nil
        }
    }

    private func activateTelegramIfReady() async {
        await deactivateTelegram()
        guard preferences.telegramEnabled, let chatId = preferences.telegramChatId else {
            return
        }
        let token: String?
        do {
            token = try await keychainStore.get(KeychainKey.telegramBotToken)
        } catch {
            logger.error("Telegram token 읽기 실패: \(error.localizedDescription)")
            return
        }
        guard let token else { return }

        let bot = LiveTelegramBot(
            token: token,
            allowedUserIds: Set(preferences.telegramAllowedUserIds)
        )
        telegramBot = bot
        alertDispatcher = TelegramAlertDispatcher(
            client: bot,
            policy: preferences.telegramAlertPolicy,
            chatId: chatId
        )
        sessionBridge = await makeSessionBridge(client: bot, chatId: chatId)
        // ADR-098 P1-1 — bridge에 artifact store 주입 → diff/log 발송이 store + deep link 경로로 라우팅.
        await sessionBridge?.setArtifactStore(telegramArtifactStore)
        let router = YuminaiCommandRouter(appModel: self)
        let pump = TelegramCommandPump(client: bot, router: router)
        commandPump = pump
        do {
            try await pump.start()
            logger.info("Telegram 활성화: chatId=\(chatId)")
        } catch {
            logger.error("Telegram pump 시작 실패: \(error.localizedDescription)")
        }
        // ADR-086 Phase 1 — health snapshot observer (사이드바 pill 실시간 업데이트)
        Task { [weak self] in
            for await snapshot in await bot.healthMonitor.snapshots() {
                await MainActor.run {
                    self?.telegramHealth = snapshot
                }
            }
        }
        // ADR-093 Phase 2 — offline queue depth 5초 주기 폴링 (BotStatusDock 표시용)
        setupTelegramQueueDepthPolling()
        // ADR-094 Phase 3 — HITL coordinator 초기화 + AsyncStream 구독
        setupTelegramHITLCoordinator()
        // ADR-095 Phase 4 + ADR-098 P0-3 — deliveryChannelProvider 주입
        // (NotificationPolicyMatrix + quiet hours + deviceState 정책이 실제 alarmRouting에 반영됨)
        // 클로저는 @Sendable nonisolated이므로 MainActor.assumeIsolated로 main actor 상태에 접근.
        // TelegramAlertDispatcher.dispatch()는 항상 async context에서 호출되며,
        // dispatch 시점에 main actor 접근을 보장하는 형태로 future refactor 가능.
        if let dispatcher = alertDispatcher {
            await dispatcher.updateDeliveryChannelProvider { [weak self] kind in
                MainActor.assumeIsolated {
                    self?.currentDeliveryChannel(for: kind) ?? .telegramOnly
                }
            }
        }
    }

    /// **ADR-093 Phase 2** — Queue depth 5초 주기 폴링 Task.
    private func setupTelegramQueueDepthPolling() {
        Task { [weak self] in
            while !Task.isCancelled {
                if let depth = await self?.telegramOfflineQueueDepth() {
                    await MainActor.run {
                        self?.telegramQueueDepth = depth
                    }
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    // MARK: - ADR-086 Phase 1 — Telegram error log access

    public func telegramRecentErrors(limit: Int = 20) async -> [TelegramErrorEntry] {
        guard let bot = telegramBot as? LiveTelegramBot else { return [] }
        return await bot.errorLog.recent(limit: limit)
    }

    public func telegramErrorStats() async -> [TelegramErrorEntry.Category: Int] {
        guard let bot = telegramBot as? LiveTelegramBot else { return [:] }
        return await bot.errorLog.statsByCategory()
    }

    public func telegramClearErrorLog() async {
        guard let bot = telegramBot as? LiveTelegramBot else { return }
        await bot.errorLog.clear()
    }

    // MARK: - ADR-093 Phase 2 — Queue depth + chat activity

    /// Offline queue에 대기 중인 메시지 수 반환.
    public func telegramOfflineQueueDepth() async -> Int {
        guard let bot = telegramBot as? LiveTelegramBot else { return 0 }
        return await bot.offlineQueue.count()
    }

    /// 최근 활동 chat 목록 (chatId + lastUsedAt). BotStatusDock / ChatContextCard 표시용.
    public func telegramRecentChatActivity() async -> [(Int64, Date)] {
        let snapshot = await telegramUsageStore.snapshot()
        return snapshot.chatStats.values
            .sorted { $0.lastUsedAt > $1.lastUsedAt }
            .map { ($0.chatId, $0.lastUsedAt) }
    }

    // MARK: - ADR-086 Phase 4 — Multi-bot management

    /// 새 봇 추가 (token은 keychain에 별도 저장).
    public func addTelegramBot(_ config: TelegramBotConfig) async {
        // 중복 ID 방지
        guard !preferences.telegramBots.contains(where: { $0.id == config.id }) else { return }
        preferences.telegramBots.append(config)
        await savePreferences()
    }

    /// 봇 설정 update.
    public func updateTelegramBot(_ config: TelegramBotConfig) async {
        guard let idx = preferences.telegramBots.firstIndex(where: { $0.id == config.id }) else { return }
        preferences.telegramBots[idx] = config
        await savePreferences()
    }

    /// 봇 제거 (관련 binding 도 cascade delete).
    /// (그룹 멤버십은 TelegramBotConfig.groupId로 관리되므로 별도 cascade 불필요)
    public func removeTelegramBot(_ id: UUID) async {
        preferences.telegramBots.removeAll { $0.id == id }
        preferences.telegramBotChatBindings.removeAll { $0.botId == id }
        await savePreferences()
    }

    /// 봇을 그룹에 할당 또는 그룹에서 제거 (groupId nil = 그룹 없음).
    public func assignBot(_ botId: UUID, toGroup groupId: UUID?) async {
        guard let idx = preferences.telegramBots.firstIndex(where: { $0.id == botId }) else { return }
        preferences.telegramBots[idx].groupId = groupId
        await savePreferences()
    }

    /// 그룹 add.
    public func addTelegramBotGroup(_ group: TelegramBotGroup) async {
        guard !preferences.telegramBotGroups.contains(where: { $0.id == group.id }) else { return }
        preferences.telegramBotGroups.append(group)
        await savePreferences()
    }

    public func updateTelegramBotGroup(_ group: TelegramBotGroup) async {
        guard let idx = preferences.telegramBotGroups.firstIndex(where: { $0.id == group.id }) else { return }
        preferences.telegramBotGroups[idx] = group
        await savePreferences()
    }

    public func removeTelegramBotGroup(_ id: UUID) async {
        preferences.telegramBotGroups.removeAll { $0.id == id }
        await savePreferences()
    }

    /// Chat binding upsert (botId + chatId 조합으로 unique).
    public func upsertBotChatBinding(_ binding: BotChatBinding) async {
        if let idx = preferences.telegramBotChatBindings.firstIndex(where: {
            $0.botId == binding.botId && $0.chatId == binding.chatId
        }) {
            preferences.telegramBotChatBindings[idx] = binding
        } else {
            preferences.telegramBotChatBindings.append(binding)
        }
        await savePreferences()
    }

    public func removeBotChatBinding(_ id: UUID) async {
        preferences.telegramBotChatBindings.removeAll { $0.id == id }
        await savePreferences()
    }

    // MARK: - ADR-089 ChatSession (ad-hoc 대화) management

    /// 새 ad-hoc 대화 세션 생성 + 자동 활성화.
    /// - Parameters:
    ///   - title: 세션 제목 (예: "버그 디버깅", "리팩토링 아이디어")
    ///   - workspaceId: 어느 워크스페이스 폴더에서 실행할지. **ADR-091** — nil이면 자유 대화.
    ///   - agentKind: Claude or Codex
    ///   - settings: model + permissionMode + effort
    /// - Returns: 생성된 ChatSession id (이미 active로 설정됨).
    @discardableResult
    public func createChatSession(
        title: String,
        workspaceId: UUID? = nil,
        agentKind: AgentKind = .default,
        settings: SessionSettings = .default
    ) async -> UUID {
        let session = ChatSession(
            title: title,
            workspaceId: workspaceId,
            agentKind: agentKind,
            settings: settings
        )
        preferences.chatSessions.append(session)
        preferences.activeChatSessionId = session.id
        await savePreferences()
        return session.id
    }

    /// ChatSession 활성화 (사이드바에서 클릭).
    /// 활성화하면 그 session의 workspaceId로 transition + agentKind/settings도 swap.
    public func activateChatSession(_ id: UUID) async {
        guard let session = preferences.chatSessions.first(where: { $0.id == id }) else { return }
        preferences.activeChatSessionId = id

        // 1) workspace 전환 (필요 시) — ADR-091: workspaceId가 nil이면 자유 대화 → 전환 안 함
        if let wsId = session.workspaceId, selectedWorkspaceId != wsId {
            await transitionToWorkspace(wsId)
        }

        // 2) agent + settings 적용 (워크스페이스가 있을 때만 — 자유 대화는 settings만 메모리에 유지)
        if session.workspaceId != nil {
            if agentKindForActiveWorkspace != session.agentKind {
                await setActiveAgentKind(session.agentKind)
            }
            if activeSettings != session.settings {
                await updateActiveSettings(session.settings)
            }
        } else {
            // 자유 대화: activeSettings만 갱신 (cwd 없으므로 어댑터 spawn은 chat 모드)
            if activeSettings != session.settings {
                activeSettings = session.settings
                await claudeAdapter.updateSettings(session.settings)
            }
        }

        // 3) lastActiveAt 갱신
        if let idx = preferences.chatSessions.firstIndex(where: { $0.id == id }) {
            preferences.chatSessions[idx].lastActiveAt = Date()
        }
        await savePreferences()
    }

    /// **ADR-091** — 자유 대화에 워크스페이스 attach (또는 detach 시 nil).
    /// attach 시 그 workspace로 transition + agent settings 적용.
    public func attachChatSessionToWorkspace(_ sessionId: UUID, workspaceId: UUID?) async {
        guard let idx = preferences.chatSessions.firstIndex(where: { $0.id == sessionId }) else { return }
        preferences.chatSessions[idx].workspaceId = workspaceId
        preferences.chatSessions[idx].lastActiveAt = Date()
        await savePreferences()
        // 활성 세션이면 즉시 전환
        if preferences.activeChatSessionId == sessionId {
            await activateChatSession(sessionId)
        }
    }

    /// ChatSession 활성 해제 — 워크스페이스 main 대화로 복귀.
    public func deactivateChatSession() async {
        preferences.activeChatSessionId = nil
        await savePreferences()
    }

    /// ChatSession 제목 변경.
    public func renameChatSession(_ id: UUID, to newTitle: String) async {
        guard let idx = preferences.chatSessions.firstIndex(where: { $0.id == id }) else { return }
        preferences.chatSessions[idx].title = newTitle
        await savePreferences()
    }

    /// ChatSession 삭제 (영구).
    public func deleteChatSession(_ id: UUID) async {
        preferences.chatSessions.removeAll { $0.id == id }
        if preferences.activeChatSessionId == id {
            preferences.activeChatSessionId = nil
        }
        await savePreferences()
    }

    /// ChatSession archive 토글 (목록에서 숨김 — 영구 삭제 ≠ archive).
    public func toggleChatSessionArchive(_ id: UUID) async {
        guard let idx = preferences.chatSessions.firstIndex(where: { $0.id == id }) else { return }
        preferences.chatSessions[idx].isArchived.toggle()
        await savePreferences()
    }

    /// 현재 active ChatSession (없으면 nil).
    public var activeChatSession: ChatSession? {
        guard let id = preferences.activeChatSessionId else { return nil }
        return preferences.chatSessions.first { $0.id == id }
    }

    /// 활성 워크스페이스의 agent kind helper (활성 chat session 또는 workspace에서).
    private var agentKindForActiveWorkspace: AgentKind {
        if let session = activeChatSession {
            return session.agentKind
        }
        return workspaces.first { $0.id == selectedWorkspaceId }?.agentKind ?? .default
    }

    /// 최근 활성순으로 정렬된 chat sessions (archived 제외, 옵션으로 포함).
    public func recentChatSessions(includeArchived: Bool = false) -> [ChatSession] {
        let filtered = includeArchived
            ? preferences.chatSessions
            : preferences.chatSessions.filter { !$0.isArchived }
        return filtered.sorted { $0.lastActiveAt > $1.lastActiveAt }
    }

    /// bound workspace가 있을 때만 bridge 생성. 없으면 nil.
    /// **ADR-114-B** — bridge 생성 시 HITL 자동 취소 콜백을 함께 주입한다.
    /// HITL이 reject/timeout/cancelled로 끝나면 bridge가 콜백을 통해
    /// `cancelBoundTurn()`을 트리거 → 사용자가 `/cancel`을 직접 입력할 필요 없음.
    private func makeSessionBridge(client: any TelegramClient, chatId: Int64) async -> TelegramSessionBridge? {
        guard let boundId = preferences.telegramBoundWorkspaceId,
              let workspace = workspaces.first(where: { $0.id == boundId })
        else { return nil }
        let config = TelegramSessionBridge.Configuration(
            chatId: chatId,
            workspaceName: workspace.name,
            forwardAssistant: preferences.telegramForwardAssistant,
            forwardToolCalls: preferences.telegramForwardToolCalls
        )
        let bridge = TelegramSessionBridge(client: client, configuration: config)
        // ADR-114-B — 자동 취소 콜백: HITL reject/timeout/cancelled 시 호출됨.
        let cancelCallback: TelegramSessionBridge.HITLCancelCallback = { [weak self] in
            _ = await self?.cancelBoundTurn()
        }
        await bridge.setOnHITLCancelRequired(cancelCallback)
        return bridge
    }

    // MARK: - cokacdir bot import (ADR-024)

    /// cokacdir bot_settings.json + group_chat 로그를 읽어 봇 목록 + chat label을 로드.
    /// SettingsView "cokacdir에서 가져오기" 버튼이 호출.
    /// **ADR-100** — `mode`로 import 후 라우팅 분기. `.legacy`(default)는 단일 봇 슬롯, `.hub`는 multi-bot.
    /// `presentSheet`: true이면 RootView의 sheet를 띄움 (Settings 진입). false이면 데이터만 로드 (Hub처럼 자체 sheet를 띄우는 호출자용).
    public func loadCokacdirBots(mode: CokacdirImportMode = .legacy, presentSheet: Bool = true) async {
        cokacdirImportError = nil
        cokacdirChatLabels = [:]
        cokacdirImportMode = mode
        let path = AppPreferences.defaultCokacdirBotSettingsPath()
        let importer = CokacdirImporter(botSettingsPath: path)
        do {
            let bots = try await importer.loadBots()
            cokacdirBots = bots
            // chat label은 봇 목록 로드 후 background로 enrich
            let inspector = CokacdirChatInspector()
            var labels: [Int64: CokacdirChatLabel] = [:]
            for bot in bots {
                for chatId in bot.suggestedChatIds where labels[chatId] == nil {
                    labels[chatId] = await inspector.label(for: chatId, ownerUserId: bot.ownerUserId)
                }
            }
            cokacdirChatLabels = labels
            if presentSheet { showCokacdirImportSheet = true }
        } catch {
            cokacdirImportError = error.localizedDescription
            if presentSheet { showCokacdirImportSheet = true }
        }
    }

    /// **ADR-100** — cokacdir 봇을 Telegram Hub의 multi-bot 모델 (`preferences.telegramBots`)에 추가.
    /// 토큰은 봇별 keychain key (`telegram.bot.<botHash>`)에 저장.
    /// `chatId`가 nil이 아니면 binding도 함께 생성 (활성 워크스페이스 미지정).
    public func addBotFromCokacdirToHub(_ bot: CokacdirBot, chatId: Int64?) async {
        // 중복 체크 (같은 username의 봇이 이미 multi-bot 목록에 있으면 스킵)
        if !bot.username.isEmpty, preferences.telegramBots.contains(where: { $0.username == bot.username }) {
            cokacdirImportError = "봇 @\(bot.username)이 이미 Telegram Hub에 등록되어 있어요."
            return
        }
        let keychainKey = "telegram.bot.\(bot.botHash)"
        do {
            try await keychainStore.set(bot.token, for: keychainKey)
            let config = TelegramBotConfig(
                id: UUID(),
                displayName: bot.displayName,
                username: bot.username,
                keychainKey: keychainKey,
                groupId: nil,
                allowedUserIds: bot.ownerUserId != 0 ? [bot.ownerUserId] : [],
                enabled: true,
                iconName: "paperplane.circle.fill",
                colorName: "accent",
                notes: "cokacdir에서 가져옴 (botHash: \(bot.botHash.prefix(8))…)"
            )
            await addTelegramBot(config)
            // chatId 있으면 binding도 추가
            if let chatId {
                let binding = BotChatBinding(
                    id: UUID(),
                    botId: config.id,
                    chatId: chatId,
                    activeWorkspaceId: nil,
                    allowedWorkspaceIds: [],
                    nickname: ""
                )
                await upsertBotChatBinding(binding)
            }
            showCokacdirImportSheet = false
            cokacdirImportError = nil
        } catch {
            cokacdirImportError = "Hub에 봇 추가 실패: \(error.localizedDescription)"
        }
    }

    /// 선택한 cokacdir 봇의 토큰을 keychain에 저장 + chatId/허용 user 자동 설정.
    public func applyCokacdirBot(_ bot: CokacdirBot, chatId: Int64) async {
        // ADR-046 M5 — cokacdir 프로세스가 동시 실행 중이면 같은 토큰 polling 충돌 → 메시지 절반씩 분산
        // pgrep으로 검출 후 사용자에게 경고 (사용자 결정에 따라 진행 또는 취소)
        if isCokacdirRunning() {
            let alert = NSAlert()
            alert.messageText = "cokacdir이 실행 중이에요"
            alert.informativeText = "cokacdir 프로세스가 같은 텔레그램 토큰으로 polling하면 메시지가 절반씩 분산됩니다 (Telegram getUpdates는 first-poll-wins).\n\nYuminai에서 사용하기 전에 cokacdir을 종료해주세요."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "그래도 진행")
            alert.addButton(withTitle: "취소")
            if alert.runModal() != .alertFirstButtonReturn {
                cokacdirImportError = "사용자 취소: cokacdir 종료 후 다시 시도하세요."
                return
            }
        }
        do {
            try await keychainStore.set(bot.token, for: KeychainKey.telegramBotToken)
            telegramTokenStatus = .set
            preferences.telegramChatId = chatId
            preferences.telegramSourceLabel = bot.displayName
            // 봇 owner를 허용 user로 자동 추가 (없으면)
            if !preferences.telegramAllowedUserIds.contains(bot.ownerUserId) {
                preferences.telegramAllowedUserIds.append(bot.ownerUserId)
            }
            preferences.telegramEnabled = true
            await savePreferences()
            showCokacdirImportSheet = false
        } catch {
            cokacdirImportError = "토큰 저장 실패: \(error.localizedDescription)"
        }
    }

    /// ADR-046 M5 — pgrep으로 cokacdir 프로세스 검출.
    /// 실패 시 false (충돌 가능성 무시) — 사용성이 우선.
    private func isCokacdirRunning() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "cokacdir"]  // exact match
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            // pgrep은 매치 발견 시 exit 0, 없으면 1
            return process.terminationStatus == 0
        } catch {
            // pgrep 실행 실패 (권한/path 문제) — 검출 포기
            return false
        }
    }

    private func deactivateTelegram() async {
        if let pump = commandPump {
            await pump.stop()
        }
        if let bridge = sessionBridge {
            await bridge.reset()
        }
        commandPump = nil
        alertDispatcher = nil
        sessionBridge = nil
        telegramBot = nil
    }

    // MARK: - Telegram session control (ADR-025)

    /// bound 워크스페이스 이름 (UI/Router에서 사용).
    public var boundWorkspaceName: String? {
        guard let id = preferences.telegramBoundWorkspaceId else { return nil }
        return workspaces.first { $0.id == id }?.name
    }

    /// 워크스페이스를 텔레그램 제어 대상으로 설정. nil이면 해제.
    /// ADR-045 R2.H3 — defaultChatId 인자: bind 호출한 chat을 자동으로 응답 default chat으로.
    /// Telegram 봇이 활성화돼 있으면 bridge를 즉시 갱신.
    public func bindTelegramWorkspace(_ id: UUID?, defaultChatId: Int64? = nil) async {
        preferences.telegramBoundWorkspaceId = id
        // bind 호출한 chat을 default response chat으로 (multi-chat 시 가장 자연스러움)
        if let defaultChatId, id != nil {
            preferences.telegramChatId = defaultChatId
        }
        await savePreferences()

        // bridge 재구성
        if let bot = telegramBot, let chatId = preferences.telegramChatId {
            if let bridge = sessionBridge {
                await bridge.reset()
            }
            sessionBridge = await makeSessionBridge(client: bot, chatId: chatId)
            // ADR-098 P1-1 — 재구성된 bridge에도 artifact store 주입 유지.
            await sessionBridge?.setArtifactStore(telegramArtifactStore)
            if let bridge = sessionBridge, let name = boundWorkspaceName {
                await bridge.sendNotice("✓ 텔레그램 연결됨 — 워크스페이스 ‘\(name)’")
            } else if id == nil {
                await sessionBridge?.sendNotice("연결 해제됨")
            }
        }
    }

    /// ADR-045 R2.H3 — bridge에 외부 request chat_id 설정 (multi-chat).
    public func setBridgeRequestChatId(_ chatId: Int64) async {
        await sessionBridge?.setRequestChatId(chatId)
    }

    /// ADR-046 — 외부 turn 시작 시 plan-mode 강제 (preferences.telegramRemoteRequiresPlan=true 시).
    /// 반환: 복원할 원래 설정 (nil이면 강제 안 함). caller가 turn 종료 후 scheduleSettingsRestore 호출.
    public func applyRemotePlanModeIfNeeded() -> SessionSettings? {
        guard preferences.telegramRemoteRequiresPlan else { return nil }
        let original = activeSettings
        guard original.permissionMode != .plan else { return nil }  // 이미 plan
        // plan mode로 1 turn 강제
        var planned = original
        planned.permissionMode = .plan
        activeSettings = planned
        // bridge에 사용자 안내
        let bridgeRef = sessionBridge
        Task {
            await bridgeRef?.sendNotice("🛡 외부 turn — Plan 모드로 실행됩니다. 결과 확인 후 ‘진행해 줘’로 승인하세요.\n(설정에서 `telegramRemoteRequiresPlan` 끄면 비활성화)")
        }
        return original
    }

    /// 외부 turn 종료 후 settings 복원 (turn 1개 후).
    public func scheduleSettingsRestore(_ original: SessionSettings) async {
        // 다음 .completed 이벤트 후 복원 — 단순화: 짧은 delay 후 복원 (race 가능성 낮음)
        // 더 정확한 방법: turn id 추적 후 정확히 그 turn 끝에서 복원. v2.0+에서 검토.
        Task { @MainActor in
            // 활성 turn이 끝날 때까지 대기 (max 5분)
            let start = Date()
            while isStreaming, Date().timeIntervalSince(start) < 300 {
                try? await Task.sleep(for: .milliseconds(500))
            }
            // 복원
            self.activeSettings = original
        }
    }

    /// ADR-045 R2.H5 — 외부 turn 카운터 (cost 가시화용).
    /// hour 단위로 reset되지 않고 누적 — /status에서 표시.
    public var externalTurnCount: Int = 0
    public var externalTurnTotalCostUSD: Double = 0
    /// **ADR-055 HIGH 4** — 외부 turn 시작 시점의 cost snapshot (over-counting 방지).
    public var externalTurnStartCostSnapshot: Double = 0
    /// **ADR-055 HIGH 4** — 현재 turn이 외부(Telegram)에서 시작됐는지.
    public var isExternalTurn: Bool = false
    /// **ADR-056 Phase 4** — daily cost 누적 (자정 reset). dailyBudgetUSD 도달 시 외부 차단.
    public var todayCostUSD: Double = 0
    public var todayCostDate: Date = Date()
    /// **ADR-059 Phase 5** — workspace별 today cost (자정 reset).
    /// **ADR-060 Phase 1** — disk persist 추가 (앱 재시작 후에도 유지).
    public var workspaceTodayCostUSD: [UUID: Double] = [:]
    /// **ADR-060 Phase 1 + 4** — workspace cost + cache trend disk store.
    public let dailyCostStore: DailyCostStore = DailyCostStore()
    /// **ADR-061 Phase 1** — UI binding용 cache trend snapshot (charts dashboard).
    public var cacheTrendSnapshot: [CacheHitSample] = []
    /// **ADR-061 Phase 4** — chat binding audit log (NDJSON disk persist).
    public let chatBindingAuditLog: ChatBindingAuditLog = ChatBindingAuditLog()
    /// **ADR-061 Phase 4** — UI binding용 cache
    public var chatBindingAuditEntries: [ChatBindingAuditEntry] = []
    /// **ADR-062 Phase 6** — Telegram 사용 통계 store (사용자 신규 요청).
    public let telegramUsageStore: TelegramUsageStore = TelegramUsageStore()
    /// UI binding용 snapshot
    public var telegramUsageSnapshot: TelegramUsageStore.Snapshot = TelegramUsageStore.Snapshot(
        chatStats: [:], commandStats: [:], hourlyBuckets: []
    )
    /// **ADR-056 Phase 3** — 컨텍스트 70% 자동 push 알림 cap (하루 1회).
    /// 마지막 push 일자 — 같은 날에 두 번 push 안 함.
    public var lastContextWarnDate: Date?

    /// **ADR-057 Critical Fix 1** — ChildProcess 호출용 effective settings.
    /// 외부 turn (isExternalTurn) + telegramRemoteRequiresPlan이면 plan-mode 적용.
    /// 그렇지 않으면 active settings 사용.
    /// → 외부 사용자가 /decompose /rehearse 보낼 때 plan-mode 우회 차단 (보안 hole 수정).
    public func effectiveChildSettings() -> SessionSettings {
        var settings = activeSettings
        if isExternalTurn && preferences.telegramRemoteRequiresPlan && settings.permissionMode != .plan {
            settings.permissionMode = .plan
        }
        return settings
    }

    /// **ADR-056 Phase 5** — Routing learning UI helpers (Settings panel용).
    public func unmuteKeyword(_ keyword: String) async {
        await routingLearningStore.setMuted(keyword, muted: false)
        routingLearningSnapshot = await routingLearningStore.snapshot()
    }

    public func addCustomRoutingKeyword(_ keyword: String, taskKind: String) async {
        await routingLearningStore.addCustomKeyword(keyword, for: taskKind)
        routingLearningSnapshot = await routingLearningStore.snapshot()
    }

    public func removeCustomRoutingKeyword(_ keyword: String, taskKind: String) async {
        await routingLearningStore.removeCustomKeyword(keyword, for: taskKind)
        routingLearningSnapshot = await routingLearningStore.snapshot()
    }

    /// **ADR-056 Phase 4** — daily cost 누적. 날짜 바뀌면 reset.
    /// **ADR-059 Phase 5** — workspace별 cost도 누적 (selectedWorkspaceId 기준).
    /// **ADR-060 Phase 1** — disk store에도 누적 (앱 재시작 보존).
    public func accumulateDailyCost(_ cost: Double) {
        let cal = Calendar.current
        if !cal.isDate(todayCostDate, inSameDayAs: Date()) {
            // 새 날짜 — global + workspace 모두 reset
            todayCostUSD = 0
            workspaceTodayCostUSD.removeAll()
            todayCostDate = Date()
        }
        todayCostUSD += cost
        // ADR-059 Phase 5 + ADR-060 Phase 1 — workspace별 누적 + disk persist
        if let wsId = selectedWorkspaceId {
            workspaceTodayCostUSD[wsId, default: 0.0] += cost
            // disk persist (background)
            let store = dailyCostStore
            Task { await store.addCost(workspaceId: wsId, usd: cost) }
        }
    }

    /// **ADR-060 Phase 1** — bootstrap에서 disk store cost 복원 (앱 재시작 후에도 budget 유지).
    /// **ADR-061 Phase 1** — cacheTrend snapshot도 캐싱 (UI binding).
    public func loadPersistedDailyCosts() async {
        let snap = await dailyCostStore.snapshot()
        let cal = Calendar.current
        for (wsId, ws) in snap.workspaceCosts {
            if cal.isDate(ws.date, inSameDayAs: Date()) {
                workspaceTodayCostUSD[wsId] = ws.costUSD
            }
        }
        cacheTrendSnapshot = snap.cacheTrend
    }

    /// **ADR-061 Phase 1** — cache trend snapshot 갱신 (Charts dashboard 열기 직전).
    public func refreshCacheTrendSnapshot() async {
        let snap = await dailyCostStore.snapshot()
        cacheTrendSnapshot = snap.cacheTrend
    }

    /// **ADR-056 Phase 4 + ADR-059 Phase 5** — budget cap 도달 여부.
    /// workspace별 cap이 있으면 그것 우선, 없으면 global dailyBudgetUSD.
    public func isDailyBudgetExhausted() -> Bool {
        // ADR-059 Phase 5 — workspace별 cap 우선
        if let wsId = selectedWorkspaceId,
           let wsCap = preferences.workspaceDailyBudgetsUSD[wsId] {
            let wsCost = workspaceTodayCostUSD[wsId] ?? 0
            if wsCost >= wsCap { return true }
        }
        // global cap fallback
        guard let cap = preferences.dailyBudgetUSD else { return false }
        return todayCostUSD >= cap
    }

    /// **ADR-057 Critical Fix 4** — atomic check + reserve (race 방지).
    /// 외부 turn 시작 시 호출 → 동시 turn 2개가 둘 다 cap check 통과하는 race 차단.
    /// reserve를 미리 추가 (estimated min cost) → 두 번째 turn은 reserve 포함 합계로 cap check.
    /// turn 종료 시 actual cost로 보정 (reserve 차감 + actual 추가).
    /// **MainActor 보장** — 동시 호출 시에도 직렬화됨 (struct flag 단순 + atomic).
    public func tryReserveDailyBudget(estimatedMinCostUSD: Double = 0.001) -> Bool {
        guard preferences.dailyBudgetUSD != nil else { return true }  // cap 없으면 통과
        // ADR-058 Phase 6 — 자정 reset push (lazy check)
        maybeBudgetResetPush()
        // 날짜 reset check
        let cal = Calendar.current
        if !cal.isDate(todayCostDate, inSameDayAs: Date()) {
            todayCostUSD = 0
            todayCostDate = Date()
        }
        // 이미 cap 도달
        if isDailyBudgetExhausted() { return false }
        // reserve를 미리 추가 (race 방지) — 동시 turn 2개면 두 번째는 누적된 reserve 포함 합계로 check
        accumulateDailyCost(estimatedMinCostUSD)
        return !isDailyBudgetExhausted()
    }

    /// **ADR-056 Phase 3** — 컨텍스트 70%+ 시 Telegram 자동 push (하루 1회).
    /// **ADR-058 Phase 5** — autoNewSessionContextThreshold 도달 시 자동 새 세션 옵션.
    /// completed 이벤트 후 호출.
    public func maybeAutoPushContextWarning() {
        let pct = currentContextUsage
        // ADR-058 Phase 5 — 자동 새 세션 (사용자 명시 활성 시만)
        if let autoThresh = preferences.autoNewSessionContextThreshold, pct >= autoThresh {
            harness.appendSystem("🔄 자동 새 세션 시작 — 컨텍스트 \(Int(pct * 100))% ≥ \(Int(autoThresh * 100))% (Settings에서 비활성 가능)")
            // 사용자에게 알림 + 새 session spawn (active pane 재spawn)
            if let bridge = sessionBridge {
                let msg = "🔄 컨텍스트 \(Int(pct * 100))% — 자동으로 새 세션 시작합니다."
                Task { await bridge.sendNotice(msg) }
            }
            // active pane session 재시작 (현재 messages는 새 session으로 안 가져감 — clean start)
            Task { @MainActor in
                if let paneId = activePaneId {
                    await setActivePane(paneId)  // re-spawn
                }
            }
            return
        }
        // 70% 일반 push (하루 1회)
        guard pct >= 0.70 else { return }
        let cal = Calendar.current
        if let last = lastContextWarnDate, cal.isDate(last, inSameDayAs: Date()) {
            return
        }
        guard let bridge = sessionBridge else { return }
        let pctInt = Int(pct * 100)
        let model = activeSettings.model.displayName
        let msg = "⚠ 컨텍스트 \(pctInt)% (\(model)) — 새 세션 시작 권장.\n• PC에서 새 세션 만들기\n• Settings에서 ‘자동 새 세션’ 옵션 활성 가능 (ADR-058)"
        Task { await bridge.sendNotice(msg) }
        lastContextWarnDate = Date()
    }

    /// **ADR-058 Phase 6** — 자정 reset push.
    /// 어제 budget cap 도달 → 오늘 reset 됐으면 사용자에게 알림.
    /// turn 시작 시 호출 (lazy check).
    public var lastBudgetResetPushDate: Date?
    public func maybeBudgetResetPush() {
        guard preferences.dailyBudgetUSD != nil else { return }
        let cal = Calendar.current
        // 오늘 이미 push 했으면 skip
        if let last = lastBudgetResetPushDate, cal.isDate(last, inSameDayAs: Date()) {
            return
        }
        // todayCostDate가 어제 이전 + 어제 cap 도달했었으면 push
        // 단순화: todayCostDate가 어제 이전이면 무조건 reset 안내 (cap 도달 여부 무관)
        if !cal.isDate(todayCostDate, inSameDayAs: Date()) {
            // reset 발생 — push
            if let bridge = sessionBridge {
                let cap = preferences.dailyBudgetUSD ?? 0
                let msg = "🌅 오늘 budget reset 됐어요. cap: $\(String(format: "%.4f", cap))/일. 외부 turn 가능."
                Task { await bridge.sendNotice(msg) }
            }
            lastBudgetResetPushDate = Date()
        }
    }

    public func incrementExternalTurnCount() {
        externalTurnCount += 1
        // ADR-055 HIGH 4 — turn 시작 시 cost snapshot
        externalTurnStartCostSnapshot = currentSessionUsage.costUSD
        isExternalTurn = true
    }

    /// **ADR-062 Phase 6** — Telegram turn 시작/종료 시 usage store 기록 helper.
    /// **ADR-063 Phase 5** — workspaceId 전달 (chat별 workspace 분포 분석).
    public func recordTelegramTurnStart(chatId: Int64) async {
        let wsId = selectedWorkspaceId
        await telegramUsageStore.recordTurnStart(chatId: chatId, workspaceId: wsId)
        telegramUsageSnapshot = await telegramUsageStore.snapshot()
    }

    public func recordTelegramTurnComplete(chatId: Int64, costUSD: Double, inputTokens: Int, outputTokens: Int) async {
        await telegramUsageStore.recordTurnComplete(
            chatId: chatId,
            costUSD: costUSD,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
        telegramUsageSnapshot = await telegramUsageStore.snapshot()
        // ADR-067 Phase 3 — anomaly auto-alert (cooldown 1h)
        await maybeAnomalyAlert()
    }

    public func recordTelegramCommand(_ command: String) async {
        await telegramUsageStore.recordCommand(command)
        telegramUsageSnapshot = await telegramUsageStore.snapshot()
    }

    /// bootstrap에서 호출.
    public func loadTelegramUsage() async {
        telegramUsageSnapshot = await telegramUsageStore.snapshot()
        telegramDailyBuckets = await telegramUsageStore.dailyAggregation()
    }

    /// **ADR-063 Phase 2** — daily aggregation cache (UI binding).
    public var telegramDailyBuckets: [DailyUsageBucket] = []

    /// **ADR-062 Phase 6** — Telegram 통계 초기화.
    public func clearTelegramUsage() async {
        await telegramUsageStore.clear()
        telegramUsageSnapshot = await telegramUsageStore.snapshot()
    }

    /// **ADR-067 Phase 3** — anomaly auto-alert (turn 종료 시 호출).
    /// 누적 hourly cost가 anomaly threshold 초과면 Telegram bridge로 push.
    /// 같은 anomaly type은 1시간 내 1회만 (alert spam 방지).
    public var lastAnomalyAlertAt: Date?
    public func maybeAnomalyAlert() async {
        // bound bridge 있어야 alert 가능
        guard let bridge = sessionBridge else { return }
        // 1시간 cooldown
        if let last = lastAnomalyAlertAt, Date().timeIntervalSince(last) < 3600 {
            return
        }
        let costs = telegramUsageSnapshot.hourlyBuckets.map(\.costUSD)
        guard costs.count >= 3 else { return }
        let threshold = preferences.anomalyZScoreThreshold
        let anomalies = UsageForecaster.detectAnomalies(costs, threshold: threshold)
        // 가장 최근 sample이 anomaly인지 (마지막 index)
        let lastIdx = costs.count - 1
        guard let recentAnomaly = anomalies.first(where: { $0.index == lastIdx }) else {
            return
        }
        let direction = recentAnomaly.direction == .high ? "🚨 spike" : "🔻 drop"
        let msg = """
        \(direction) anomaly 감지!
          · 최근 1시간 cost: $\(String(format: "%.4f", recentAnomaly.value))
          · z-score: \(String(format: "%.2f", recentAnomaly.zScore)) (threshold \(String(format: "%.1f", threshold)))
          · /cost로 자세히 확인
        """
        Task { await bridge.sendNotice(msg) }
        lastAnomalyAlertAt = Date()
    }

    /// **ADR-062 Phase 6** — chatId → workspace name (UI 라벨용).
    public func telegramChatIdToWorkspaceName() -> [String: String] {
        var result: [String: String] = [:]
        for (chatKey, wsId) in preferences.telegramChatBindings {
            if let ws = workspaces.first(where: { $0.id == wsId }) {
                result[chatKey] = ws.name
            }
        }
        return result
    }

    /// /status 명령에 응답할 텍스트 생성. ADR-045 R2.H5 — 외부 turn 비용 + context % 가시화.
    public func telegramStatusSnapshot() -> String {
        let bound = boundWorkspaceName ?? "없음"
        let active = workspaces.first { $0.id == selectedWorkspaceId }?.name ?? "없음"
        let streamingTag = isStreaming ? "응답 중" : "대기 중"
        let ctxPct = Int(currentContextUsage * 100)
        let ctxWarn = ctxPct >= 70 ? " ⚠" : ""
        let costStr = String(format: "$%.4f", currentSessionUsage.costUSD)
        let externalCostStr = String(format: "$%.4f", externalTurnTotalCostUSD)
        var lines = [
            "현재 상태:",
            "  · 연결된 워크스페이스: \(bound)",
            "  · 활성 워크스페이스: \(active)",
            "  · Claude: \(streamingTag)",
            "  · 모델: \(activeSettings.model.displayName)",
            "  · 컨텍스트: \(ctxPct)%\(ctxWarn)",
            "  · 현재 세션 비용: \(costStr)",
            "  · 외부 turn 횟수: \(externalTurnCount) (누적 \(externalCostStr))"
        ]
        if ctxPct >= 70 {
            lines.append("")
            lines.append("⚠ 컨텍스트가 70%를 넘어 새 세션을 시작하는 것이 좋아요.")
        }
        return lines.joined(separator: "\n")
    }

    /// bound 세션의 진행 중 turn 중단. 중단됐으면 true.
    public func cancelBoundTurn() async -> Bool {
        guard isStreaming,
              let bound = preferences.telegramBoundWorkspaceId,
              selectedWorkspaceId == bound
        else { return false }
        cancelStream()
        if let bridge = sessionBridge {
            await bridge.notifyCancelled()
        }
        return true
    }

    // MARK: - ADR-094 Phase 3 — TelegramCommand management

    /// 커맨드 목록 전체 교체.
    public func updateTelegramCommands(_ commands: [TelegramCommand]) async {
        preferences.telegramCommands = commands
        await savePreferences()
    }

    /// 커맨드 추가 (중복 ID 방지).
    public func addTelegramCommand(_ command: TelegramCommand) async {
        guard !preferences.telegramCommands.contains(where: { $0.id == command.id }) else { return }
        preferences.telegramCommands.append(command)
        await savePreferences()
    }

    /// 커맨드 업데이트.
    public func updateTelegramCommand(_ command: TelegramCommand) async {
        guard let idx = preferences.telegramCommands.firstIndex(where: { $0.id == command.id }) else { return }
        preferences.telegramCommands[idx] = command
        await savePreferences()
    }

    /// 커맨드 제거.
    public func removeTelegramCommand(id: UUID) async {
        preferences.telegramCommands.removeAll { $0.id == id }
        await savePreferences()
    }

    /// **ADR-094 Phase 3** — enabled 커맨드를 BotFather에 동기화.
    /// - Returns: `.success(등록수)` 또는 `.failure(error)`
    public func syncTelegramCommandsToBotFather() async -> Result<Int, any Error> {
        guard let bot = telegramBot else {
            return .failure(NSError(domain: "AppModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "봇이 활성화되어 있지 않습니다"]))
        }

        let enabled = preferences.telegramCommands.filter { $0.enabled && $0.isValidTrigger && $0.isValidDescription }
        let pairs = enabled.map { (command: $0.apiCommand, description: $0.description) }

        do {
            try await bot.setMyCommands(pairs)
            return .success(pairs.count)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - ADR-094 Phase 3 — HITL Coordinator

    /// **ADR-094 Phase 3** — HITL pending requests (UI 표시용).
    public var hitlPendingRequests: [TelegramHITLCoordinator.Request] = []
    /// **ADR-094 Phase 3** — HITLApprovalSheet 표시 여부.
    public var showHITLSheet: Bool = false

    /// **ADR-094 Phase 3** — HITL coordinator (봇 시작 시 생성).
    var hitlCoordinator: TelegramHITLCoordinator? = nil

    /// **ADR-094 Phase 3** — HITL coordinator 초기화 + AsyncStream 구독.
    /// `setupTelegram()` 완료 후 호출.
    func setupTelegramHITLCoordinator() {
        let coordinator = TelegramHITLCoordinator()
        hitlCoordinator = coordinator

        // **ADR-098 P0-1** — HITL coordinator를 sessionBridge에 주입해 destructive action 차단 흐름 활성화.
        let timeoutSecs = preferences.hitlTimeoutSeconds
        Task { [weak self] in
            await self?.sessionBridge?.setHITLCoordinator(coordinator, timeoutSeconds: timeoutSecs)
        }

        Task { [weak self] in
            let stream = await coordinator.requestStream()
            for await request in stream {
                let requests = await coordinator.pendingRequests()
                await MainActor.run {
                    self?.hitlPendingRequests = requests
                    if !requests.isEmpty {
                        self?.showHITLSheet = true
                    }
                }
                // Telegram inline button 메시지 전송 + ADR-099 P1-4: messageId 저장
                if let self, let chatId = self.preferences.telegramChatId {
                    let approveData = TelegramHITLCallbackHandler.HITLAction.approve.callbackData(for: request.id)
                    let rejectData = TelegramHITLCallbackHandler.HITLAction.reject.callbackData(for: request.id)
                    let buttons = [[
                        InlineButton(text: "✅ Approve", callbackData: approveData),
                        InlineButton(text: "❌ Reject", callbackData: rejectData)
                    ]]
                    let text = "⚠️ HITL 승인 필요\n\n**Action:** `\(request.action)`\n**Timeout:** \(request.timeoutSeconds)s"
                    if let sent = try? await self.telegramBot?.sendWithKeyboard(text, to: chatId, buttons: buttons) {
                        // ADR-099 P1-4 — messageId를 coordinator에 등록 (응답 후 edit용)
                        await coordinator.setTelegramMessageId(sent.messageId, chatId: chatId, for: request.id)
                    }
                }
                // **ADR-098 P0-4** — macOS UserNotification 동시 발송 (HITL actionable)
                try? await MacOSNotificationSender.sendHITL(
                    requestId: request.id,
                    action: request.action,
                    workspaceName: request.workspace
                )
            }
        }
    }

    /// **ADR-094 Phase 3 / ADR-099 P1-4** — 외부에서 HITL 응답 주입 (데스크탑 UI 또는 Telegram callback).
    /// 응답 후 텔레그램 메시지를 editMessageText로 자동 갱신 (승인/거절/timeout/cancelled 상태 표시).
    public func respondToHITL(id: UUID, response: TelegramHITLCoordinator.HITLResponse) async {
        // ADR-099 P1-4 — respond 전에 pending request에서 messageId/chatId 조회
        let pendingBefore = await hitlCoordinator?.pendingRequests() ?? []
        let matchedRequest = pendingBefore.first { $0.id == id }

        await hitlCoordinator?.respond(id: id, response: response)
        let requests = await hitlCoordinator?.pendingRequests() ?? []
        hitlPendingRequests = requests
        if requests.isEmpty {
            showHITLSheet = false
        }

        // ADR-099 P1-4 — HITL 응답 후 텔레그램 메시지 자동 edit
        if let req = matchedRequest,
           let msgId = req.telegramMessageId,
           let chatId = req.telegramChatId,
           let bot = telegramBot {
            await TelegramSendHelper.editHITLMessage(
                response: response,
                originalAction: req.action,
                messageId: msgId,
                chatId: chatId,
                client: bot
            )
        }

        // **ADR-115 P0-3** — reject/timeout/cancelled 시 Claude 프로세스 자동 중단.
        // Telegram 경로: bridge.consume(event:)의 onHITLCancelRequired 콜백이 cancelBoundTurn()을
        // 이미 호출하므로 여기서는 desktop-only 시나리오(bridge 없음)를 보완한다.
        // bridge가 있는 경우 cancelBoundTurn()은 자체 notifyCancelled()를 보내므로
        // 중복 알림 없이 프로세스만 추가 중단 시도한다.
        switch response {
        case .rejected, .timeout, .cancelled:
            // bridge가 없으면(desktop 단독 흐름) cancelStream()을 직접 호출해야 한다.
            // bridge가 있으면 onHITLCancelRequired 콜백이 이미 cancelBoundTurn()을 불렀으므로
            // cancelStream()은 중복 호출이지만 idempotent하므로 안전하다.
            if !isStreaming {
                break  // 이미 중단됨
            }
            cancelStream()
            // bridge가 없는 경우(desktop 단독)에만 별도 notice 불필요.
            // bridge가 있는 경우 cancelBoundTurn()→notifyCancelled() 메시지가 이미 발송됨.
        case .approved:
            break
        }
    }

    // MARK: - ADR-095 Phase 4 — Multi-device 알림 정책 + Quiet Hours

    /// **ADR-095 Phase 4** — 현재 디바이스 상태.
    /// `desktopActive` (기본) → `desktopIdle` (5분 무입력) → `desktopOff` (명시적 설정).
    public var deviceState: DeviceState = .desktopActive

    /// **ADR-095 Phase 4** — idle timer task.
    private var idleTimer: Task<Void, Never>?

    /// **ADR-095 Phase 4** — 마지막 사용자 입력 시각.
    private var lastInputAt: Date = .now

    /// **ADR-095 Phase 4** — 사용자 입력 감지 (메시지 전송, UI 조작 등).
    public func recordUserInput() {
        lastInputAt = Date.now
        if deviceState == .desktopIdle {
            deviceState = .desktopActive
        }
        resetIdleTimer()
    }

    /// **ADR-095 Phase 4** — 5분 무입력 타이머 시작.
    public func setupDeviceStateMonitor() {
        resetIdleTimer()

        // macOS 수면 알림 구독
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.deviceState = .desktopIdle
        }
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.deviceState = .desktopActive
            self?.resetIdleTimer()
        }
    }

    private func resetIdleTimer() {
        idleTimer?.cancel()
        idleTimer = Task { [weak self] in
            do {
                // 5분 = 300초
                try await Task.sleep(nanoseconds: 300_000_000_000)
                await MainActor.run {
                    guard let self, self.deviceState == .desktopActive else { return }
                    self.deviceState = .desktopIdle
                }
            } catch {
                // 취소됨 — 정상
            }
        }
    }

    /// **ADR-095 Phase 4** — Quiet hours + 디바이스 상태를 고려한 실제 전달 채널 반환.
    ///
    /// 1. notificationPolicy.channel(for:in:) 기본값 조회
    /// 2. quiet hours 범위이면 `generalAlert`, `taskCompleteSuccess` → `suppressed`로 격하
    public func currentDeliveryChannel(for kind: NotificationKind) -> DeliveryChannel {
        let baseChannel = preferences.notificationPolicy.channel(for: kind, in: deviceState)

        // Quiet hours 격하 체크
        if isInQuietHours() {
            switch kind {
            case .generalAlert, .taskCompleteSuccess:
                return .suppressed
            default:
                break
            }
        }

        return baseChannel
    }

    /// **ADR-095 Phase 4** — 현재 시각이 quiet hours 범위에 있는지 확인.
    private func isInQuietHours() -> Bool {
        guard let start = preferences.quietHoursStart,
              let end = preferences.quietHoursEnd else { return false }

        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())

        if start <= end {
            // 예: 9~17시 (낮)
            return hour >= start && hour < end
        } else {
            // 예: 22~8시 (자정 걸침)
            return hour >= start || hour < end
        }
    }

    // MARK: - ADR-096 — Deep link 핸들러

    /// **ADR-096** — `yuminai://` deep link 수신 시 라우팅.
    ///
    /// `.onOpenURL` 핸들러에서 호출 — `TelegramDeepLink.parse(url)` 결과를 액션에 매핑.
    public func handleDeepLink(_ link: TelegramDeepLink) async {
        switch link {
        case .diff(let id):
            // ADR-097 — artifact viewer sheet로 라우팅
            NSApp.activate(ignoringOtherApps: true)
            artifactSheetId = id
            showTelegramArtifactSheet = true
            logger.info("[DeepLink] diff \(id) — artifact viewer sheet 표시")

        case .log(let id):
            // ADR-097 — artifact viewer sheet로 라우팅
            NSApp.activate(ignoringOtherApps: true)
            artifactSheetId = id
            showTelegramArtifactSheet = true
            logger.info("[DeepLink] log \(id) — artifact viewer sheet 표시")

        case .workspace(let id):
            NSApp.activate(ignoringOtherApps: true)
            await transitionToWorkspace(id)

        case .chat:
            NSApp.activate(ignoringOtherApps: true)
            showTelegramHubSheet = true

        case .approve(let requestId):
            await respondToHITL(id: requestId, response: .approved(by: "deeplink"))

        case .reject(let requestId):
            await respondToHITL(id: requestId, response: .rejected(by: "deeplink"))
        }
    }

    // MARK: - ADR-096 — Notification Policy 편집 메서드

    /// **ADR-096** — 알림 정책 매트릭스 업데이트 + persist.
    public func updateNotificationPolicy(_ matrix: NotificationPolicyMatrix) async {
        preferences = { var p = preferences; p.notificationPolicy = matrix; return p }()
        await savePreferences()
    }

    /// **ADR-096** — Quiet hours 업데이트 + persist.
    public func updateQuietHours(start: Int?, end: Int?) async {
        preferences = { var p = preferences; p.quietHoursStart = start; p.quietHoursEnd = end; return p }()
        await savePreferences()
    }

    /// **ADR-096** — HITL 타임아웃 업데이트 + persist.
    public func updateHITLTimeout(_ seconds: Int) async {
        preferences = { var p = preferences; p.hitlTimeoutSeconds = seconds; return p }()
        await savePreferences()
    }

    /// **ADR-096** — diff 미리보기 라인 한도 업데이트 + persist.
    public func updateDiffPreviewLineLimit(_ limit: Int) async {
        preferences = { var p = preferences; p.diffPreviewLineLimit = limit; return p }()
        await savePreferences()
    }

    /// **ADR-096** — 알림 정책 매트릭스를 default로 재설정 + persist.
    public func resetNotificationPolicyToDefault() async {
        preferences = { var p = preferences; p.notificationPolicy = .default; return p }()
        await savePreferences()
    }

    // MARK: - ADR-097 — macOS Notification Permission

    /// **ADR-097** — 앱 시작 시 macOS 알림 권한 상태 확인.
    public func setupNotificationStatusCheck() async {
        macOSNotificationStatus = await MacOSNotificationPermission.currentStatus()
    }

    /// **ADR-097** — 사용자 요청에 의한 macOS 알림 권한 요청.
    public func requestMacOSNotificationPermission() async {
        macOSNotificationStatus = await MacOSNotificationPermission.requestPermission()
    }
}
