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
    /// **ADR-119** — GitHub PAT Keychain 저장 상태 (코드 검색 인증용).
    public var githubPATStatus: SecretStatus = .notSet
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

    // ADR-128 — `private` 제거: AppModel+Obsidian.swift extension에서 cross-file 접근 필요.
    var vaultWatcher: VaultWatcher?
    var watcherTask: Task<Void, Never>?
    var fullTextSearchTask: Task<Void, Never>?

    // MARK: - ADR-111 — 라이브러리 첨부 + Sheet 표시 (AppModel+Library.swift 참조)

    /// 현재 Composer에 첨부된 라이브러리 항목 목록.
    public var attachedLibraryItems: [ResourceLibraryItem] = []
    /// ADR-111 — 라이브러리 sheet 표시 여부.
    public var showLibrarySheet: Bool = false
    /// ADR-112 — 카탈로그 전체 탐색 sheet 표시 여부.
    public var showCatalogSheet: Bool = false
    /// **ADR-113** — 스택 번들 카탈로그 sheet 표시 여부.
    public var showBundleCatalogSheet: Bool = false
    /// **ADR-116** — GitHub 검색 sheet 표시 여부.
    public var showGitHubSearchSheet: Bool = false
    /// **ADR-117** — 커뮤니티 자료 sheet 표시 여부 (사이드바 직접 진입).
    public var showCommunityResourcesSheet: Bool = false
    /// ADR-111 — 라이브러리 picker popover 표시 여부 (Composer 안).
    public var showLibraryPickerPopover: Bool = false

    // MARK: - ADR-132 — 자동 실행 (AppModel+AutoRun.swift 참조)

    /// **ADR-132** — AutoRunCoordinator (lazy — 첫 사용 시 생성).
    public let autoRunCoordinator: AutoRunCoordinator = AutoRunCoordinator()
    /// **ADR-132** — 현재 자동 실행 상태 (UI binding용).
    public var autoRunState: AutoRunCoordinator.State = .idle
    /// **ADR-132** — 자동 실행 설정 sheet 표시 여부.
    public var showAutoRunSettings: Bool = false
    /// **ADR-132** — 현재 실행 중인 turn 로그 (UI 실시간 표시용).
    public var autoRunLogs: [AutoRunTurnLog] = []
    /// **ADR-132** — AutoRunControlSheet 표시 여부.
    public var showAutoRunControlSheet: Bool = false

    // MARK: - ADR-094 Phase 3 — HITL (AppModel+HITL.swift 참조)

    /// **ADR-094 Phase 3** — HITL pending requests (UI 표시용).
    public var hitlPendingRequests: [TelegramHITLCoordinator.Request] = []
    /// **ADR-094 Phase 3** — HITLApprovalSheet 표시 여부.
    public var showHITLSheet: Bool = false
    /// **ADR-094 Phase 3** — HITL coordinator (봇 시작 시 생성).
    var hitlCoordinator: TelegramHITLCoordinator? = nil

    // MARK: - ADR-095 — Notification (AppModel+Notification.swift 참조)

    /// **ADR-095 Phase 4** — 현재 디바이스 상태.
    public var deviceState: DeviceState = .desktopActive
    /// **ADR-095 Phase 4** — idle timer task.
    var idleTimer: Task<Void, Never>?
    /// **ADR-095 Phase 4** — 마지막 사용자 입력 시각.
    var lastInputAt: Date = .now

    // MARK: - ADR-056/059/060/061/062/063/067 — Cost + Usage (AppModel+Telegram.swift 참조)

    /// ADR-045 R2.H5 — 외부 turn 카운터.
    public var externalTurnCount: Int = 0
    public var externalTurnTotalCostUSD: Double = 0
    /// **ADR-055 HIGH 4** — 외부 turn 시작 cost snapshot.
    public var externalTurnStartCostSnapshot: Double = 0
    /// **ADR-055 HIGH 4** — 현재 turn이 외부(Telegram)에서 시작됐는지.
    public var isExternalTurn: Bool = false
    /// **ADR-056 Phase 4** — daily cost 누적.
    public var todayCostUSD: Double = 0
    public var todayCostDate: Date = Date()
    /// **ADR-059 Phase 5** — workspace별 today cost.
    public var workspaceTodayCostUSD: [UUID: Double] = [:]
    /// **ADR-060 Phase 1 + 4** — workspace cost + cache trend disk store.
    public let dailyCostStore: DailyCostStore = DailyCostStore()
    /// **ADR-061 Phase 1** — cache trend snapshot (charts dashboard).
    public var cacheTrendSnapshot: [CacheHitSample] = []
    /// **ADR-061 Phase 4** — chat binding audit log.
    public let chatBindingAuditLog: ChatBindingAuditLog = ChatBindingAuditLog()
    public var chatBindingAuditEntries: [ChatBindingAuditEntry] = []
    /// **ADR-062 Phase 6** — Telegram 사용 통계 store.
    public let telegramUsageStore: TelegramUsageStore = TelegramUsageStore()
    public var telegramUsageSnapshot: TelegramUsageStore.Snapshot = TelegramUsageStore.Snapshot(
        chatStats: [:], commandStats: [:], hourlyBuckets: []
    )
    /// **ADR-056 Phase 3** — 컨텍스트 70% 자동 push 알림 cap (하루 1회).
    public var lastContextWarnDate: Date?
    /// **ADR-058 Phase 6** — 자정 reset push 마지막 날짜.
    public var lastBudgetResetPushDate: Date?
    /// **ADR-063 Phase 2** — daily aggregation cache.
    public var telegramDailyBuckets: [DailyUsageBucket] = []
    /// **ADR-067 Phase 3** — anomaly alert 마지막 시각.
    public var lastAnomalyAlertAt: Date?

    // MARK: 내부
    var streamConsumeTask: Task<Void, Never>?
    var currentClaudeSession: (any ClaudeStreamSession)?
    var telegramBot: (any TelegramClient)?
    var alertDispatcher: TelegramAlertDispatcher?
    var commandPump: TelegramCommandPump?
    var sessionBridge: TelegramSessionBridge?
    let checkpointManager = CheckpointManager()
    let deliveryRunner = DeliveryRunner()
    /// **ADR-115 P1-2** — 다음 assistant 메시지에 붙일 attribution. sendMessage 시 캡처 → 응답 도착 시 소비.
    var pendingAttribution: MessageAttribution?

    let logger = Logger(subsystem: "com.yuminai", category: "AppModel")

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

    // MARK: - Multi-pane (ADR-030, M1 phase C)

    /// workspace 선택 시 호출 — savedPanes가 있으면 복원, 없으면 default primary 1개 자동 등록.
    /// 기존에 spawn한 session/messages를 primary(또는 첫 saved) pane state로 wrap.
    /// **session/messages는 영속 X** — pane 메타만 복원, conversation은 fresh.
    // ADR-128 — `private` 제거: AppModel+Git.swift의 startSession()에서 cross-file 접근.
    func ensurePrimaryPane(for workspace: Workspace, session: any ClaudeStreamSession) {
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
            icon: "sparkles",
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

    // ADR-128 — `private` 제거: AppModel+Git.swift의 startSession()에서 cross-file 접근.
    func consumeStream(_ session: any ClaudeStreamSession) async {
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

    // ADR-128 — `private` 제거: AppModel+Workspace.swift / AppModel+Git.swift에서 cross-file 접근.
    func teardownCurrentSession() async {
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
        // ADR-111 ~ ADR-117 (ADR-125 P0-1 — 누락 sheet 추가)
        showLibrarySheet = false
        showCatalogSheet = false
        showBundleCatalogSheet = false
        showGitHubSearchSheet = false
        showCommunityResourcesSheet = false
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

}
