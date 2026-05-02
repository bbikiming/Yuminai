import Foundation
import SwiftUI
import os
import YuminaiCore
import YuminaiClaudeAdapter
import YuminaiPersistence
import YuminaiTelegram
import YuminaiObsidian
import YuminaiUI

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

    public var showCreateWorkspaceSheet: Bool = false
    public var showUsageDashboard: Bool = false
    public var showInspector: Bool = false

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

    private let logger = Logger(subsystem: "com.yuminai", category: "AppModel")

    public init(
        workspaceStore: any WorkspaceStore,
        sessionStore: any SessionStore,
        keychainStore: any KeychainStore,
        preferencesStore: any AppPreferencesStore,
        claudeAdapter: any ClaudeAdapter,
        codexAdapter: (any ClaudeAdapter)? = nil,
        preferences: AppPreferences
    ) {
        self.workspaceStore = workspaceStore
        self.sessionStore = sessionStore
        self.keychainStore = keychainStore
        self.preferencesStore = preferencesStore
        self.claudeAdapter = claudeAdapter
        self.codexAdapter = codexAdapter
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
    public func setActiveAgentKind(_ kind: AgentKind) async {
        guard let id = selectedWorkspaceId,
              let workspace = workspaces.first(where: { $0.id == id }),
              workspace.agentKind != kind
        else { return }

        // store에 영속
        let updated = workspace.with(agentKind: kind)
        do {
            try await workspaceStore.update(updated)
            if let idx = workspaces.firstIndex(where: { $0.id == id }) {
                workspaces[idx] = updated
            }
        } catch {
            self.error = "에이전트 변경 저장 실패: \(error.localizedDescription)"
            return
        }

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
            await refreshWorkspaces()
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func selectWorkspace(_ id: UUID?) async {
        await teardownCurrentSession()
        guard let id, let workspace = workspaces.first(where: { $0.id == id }) else {
            return
        }
        await startSession(in: workspace)
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
        // 향후 추가: dev server suggestions refresh, mention scope reset 등
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

        let activeAd = adapter(for: workspace)
        streamConsumeTask?.cancel()
        streamConsumeTask = nil
        if let claudeSession = currentClaudeSession {
            await activeAd.terminate(claudeSession)
        }
        currentClaudeSession = nil
        isStreaming = false

        do {
            let claudeSession = try await activeAd.spawn(in: workspace)
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

    private func handle(_ event: ClaudeEvent) {
        switch event {
        case .text(let text):
            appendMessage(role: .assistant, content: text)
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
            }
        case .completed(let exitCode):
            isStreaming = false
            let workspaceName = workspaces.first { $0.id == selectedWorkspaceId }?.name ?? "?"
            let category: AlertCategory = exitCode == 0 ? .workComplete : .workFailed
            let costStr = String(format: "$%.4f", currentSessionUsage.costUSD)
            let summary = "Workspace: \(workspaceName) (exit \(exitCode), \(costStr))"
            let dispatcher = alertDispatcher
            Task {
                await dispatcher?.dispatch(category: category, message: summary)
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
        Task { await bridge.consume(event: event) }
    }

    private func appendMessage(role: Message.Role, content: String) {
        guard let session = currentSession else { return }
        let msg = Message(sessionId: session.id, role: role, content: content)
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
              let session = currentSession,
              let claudeSession = currentClaudeSession,
              !isStreaming else { return }

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

        let bodyForUser = trimmed.isEmpty
            ? (failurePrefix + attachmentPreamble).trimmingCharacters(in: .whitespacesAndNewlines)
            : failurePrefix + attachmentPreamble + trimmed

        let userMsg = Message(sessionId: session.id, role: .user, content: bodyForUser)
        messages.append(userMsg)
        try? await sessionStore.append(userMsg)
        currentSessionUsage.messageCount += 1
        allTimeUsage.messageCount += 1

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
        sessionBridge = makeSessionBridge(client: bot, chatId: chatId)
        let router = YuminaiCommandRouter(appModel: self)
        let pump = TelegramCommandPump(client: bot, router: router)
        commandPump = pump
        do {
            try await pump.start()
            logger.info("Telegram 활성화: chatId=\(chatId)")
        } catch {
            logger.error("Telegram pump 시작 실패: \(error.localizedDescription)")
        }
    }

    /// bound workspace가 있을 때만 bridge 생성. 없으면 nil.
    private func makeSessionBridge(client: any TelegramClient, chatId: Int64) -> TelegramSessionBridge? {
        guard let boundId = preferences.telegramBoundWorkspaceId,
              let workspace = workspaces.first(where: { $0.id == boundId })
        else { return nil }
        let config = TelegramSessionBridge.Configuration(
            chatId: chatId,
            workspaceName: workspace.name,
            forwardAssistant: preferences.telegramForwardAssistant,
            forwardToolCalls: preferences.telegramForwardToolCalls
        )
        return TelegramSessionBridge(client: client, configuration: config)
    }

    // MARK: - cokacdir bot import (ADR-024)

    /// cokacdir bot_settings.json + group_chat 로그를 읽어 봇 목록 + chat label을 로드.
    /// SettingsView "cokacdir에서 가져오기" 버튼이 호출.
    public func loadCokacdirBots() async {
        cokacdirImportError = nil
        cokacdirChatLabels = [:]
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
            showCokacdirImportSheet = true
        } catch {
            cokacdirImportError = error.localizedDescription
            showCokacdirImportSheet = true
        }
    }

    /// 선택한 cokacdir 봇의 토큰을 keychain에 저장 + chatId/허용 user 자동 설정.
    public func applyCokacdirBot(_ bot: CokacdirBot, chatId: Int64) async {
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
    /// Telegram 봇이 활성화돼 있으면 bridge를 즉시 갱신.
    public func bindTelegramWorkspace(_ id: UUID?) async {
        preferences.telegramBoundWorkspaceId = id
        await savePreferences()

        // bridge 재구성
        if let bot = telegramBot, let chatId = preferences.telegramChatId {
            if let bridge = sessionBridge {
                await bridge.reset()
            }
            sessionBridge = makeSessionBridge(client: bot, chatId: chatId)
            if let bridge = sessionBridge, let name = boundWorkspaceName {
                await bridge.sendNotice("✓ 텔레그램 연결됨 — 워크스페이스 ‘\(name)’")
            } else if id == nil {
                await sessionBridge?.sendNotice("연결 해제됨")
            }
        }
    }

    /// /status 명령에 응답할 텍스트 생성.
    public func telegramStatusSnapshot() -> String {
        let bound = boundWorkspaceName ?? "없음"
        let active = workspaces.first { $0.id == selectedWorkspaceId }?.name ?? "없음"
        let streamingTag = isStreaming ? "응답 중" : "대기 중"
        let lines = [
            "현재 상태:",
            "  · 연결된 워크스페이스: \(bound)",
            "  · 활성 워크스페이스: \(active)",
            "  · Claude: \(streamingTag)",
            "  · 모델: \(activeSettings.model.displayName)",
            "  · 컨텍스트: \(Int(currentContextUsage * 100))%"
        ]
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
}
