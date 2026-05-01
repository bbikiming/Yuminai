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

    // MARK: 상태
    public var preferences: AppPreferences
    public var workspaces: [Workspace] = []
    public var selectedWorkspaceId: UUID?
    public var currentSession: Session?
    public var messages: [Message] = []
    public var inputText: String = ""
    public var isStreaming: Bool = false
    public var error: String?

    public var anthropicKeyStatus: SecretStatus = .notSet
    public var telegramTokenStatus: SecretStatus = .notSet

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

    // Obsidian Vault
    public var inspectorTab: InspectorTab = .context
    public var obsidianVault: ObsidianVault?
    public var vaultTree: [VaultNode] = []
    public var selectedNote: Note?
    public var noteSearchQuery: String = ""
    public var noteFullTextEnabled: Bool = false
    public var noteFullTextHits: [SearchHit] = []

    // 노트 편집
    public var isEditingNote: Bool = false
    public var editingDraft: String = ""
    public var noteIsDirty: Bool { isEditingNote && editingDraft != (selectedNote?.body ?? "") }
    public var externalChangeDetected: Bool = false

    // NotePicker (Composer)
    public var showNotePicker: Bool = false
    public var notePickerQuery: String = ""

    // Wiki disambig (B1)
    public var disambigCandidates: [VaultNode] = []
    public var disambigOriginalName: String = ""
    public var showDisambigSheet: Bool = false

    // Editor split mode (B4)
    public var editorSplitMode: EditorSplitMode = .editor

    // 노트 생성 (B5)
    public var showCreateNoteSheet: Bool = false

    // Favorites (C2)
    public var favoriteNotePaths: Set<String> = []

    // Recents (C3) — LRU 10개
    public var recentNotePaths: [String] = []

    // 도움말 sheet (C1)
    public var showShortcutHelp: Bool = false

    private var vaultWatcher: VaultWatcher?
    private var watcherTask: Task<Void, Never>?
    private var fullTextSearchTask: Task<Void, Never>?

    // MARK: 내부
    private var streamConsumeTask: Task<Void, Never>?
    private var currentClaudeSession: (any ClaudeStreamSession)?
    private var telegramBot: (any TelegramClient)?
    private var alertDispatcher: TelegramAlertDispatcher?
    private var commandPump: TelegramCommandPump?

    private let logger = Logger(subsystem: "com.yuminai", category: "AppModel")

    public init(
        workspaceStore: any WorkspaceStore,
        sessionStore: any SessionStore,
        keychainStore: any KeychainStore,
        preferencesStore: any AppPreferencesStore,
        claudeAdapter: any ClaudeAdapter,
        preferences: AppPreferences
    ) {
        self.workspaceStore = workspaceStore
        self.sessionStore = sessionStore
        self.keychainStore = keychainStore
        self.preferencesStore = preferencesStore
        self.claudeAdapter = claudeAdapter
        self.preferences = preferences
        self.activeSettings = preferences.defaultSessionSettings
        self.showInspector = preferences.showInspectorByDefault
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

            let claudeSession = try await claudeAdapter.spawn(in: workspace)
            currentClaudeSession = claudeSession

            let captured = claudeSession
            streamConsumeTask = Task { [weak self] in
                await self?.consumeStream(captured)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// 활성 세션 설정 변경. claudeAdapter에 반영하고, 활성 워크스페이스가 있으면 새 ClaudeStreamSession을
    /// 즉시 시작 (메시지 로그는 UI에 보존, 다음 사용자 입력부터 새 설정 적용).
    public func updateActiveSettings(_ newSettings: SessionSettings) async {
        activeSettings = newSettings
        await claudeAdapter.updateSettings(newSettings)

        guard let id = selectedWorkspaceId,
              let workspace = workspaces.first(where: { $0.id == id }) else {
            return
        }

        streamConsumeTask?.cancel()
        streamConsumeTask = nil
        if let claudeSession = currentClaudeSession {
            await claudeAdapter.terminate(claudeSession)
        }
        currentClaudeSession = nil
        isStreaming = false

        do {
            let claudeSession = try await claudeAdapter.spawn(in: workspace)
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
        }
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
        if let claudeSession = currentClaudeSession {
            await claudeAdapter.terminate(claudeSession)
        }
        currentClaudeSession = nil
        currentSession = nil
        messages = []
        isStreaming = false
    }

    // MARK: - chat

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

        let bodyForUser = trimmed.isEmpty
            ? attachmentPreamble.trimmingCharacters(in: .whitespacesAndNewlines)
            : attachmentPreamble + trimmed

        let userMsg = Message(sessionId: session.id, role: .user, content: bodyForUser)
        messages.append(userMsg)
        try? await sessionStore.append(userMsg)
        currentSessionUsage.messageCount += 1
        allTimeUsage.messageCount += 1

        inputText = ""
        attachedFiles = []  // 송신 후 자동 클리어
        isStreaming = true

        do {
            try await claudeSession.send(bodyForUser)
        } catch {
            self.error = "전송 실패: \(error.localizedDescription)"
            isStreaming = false
        }
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
                attachedFiles.append(url)
            }
        }
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
            let adapter = claudeAdapter
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

    private func deactivateTelegram() async {
        if let pump = commandPump {
            await pump.stop()
        }
        commandPump = nil
        alertDispatcher = nil
        telegramBot = nil
    }
}
