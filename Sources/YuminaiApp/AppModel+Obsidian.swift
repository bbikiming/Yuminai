import Foundation
import YuminaiCore
import YuminaiObsidian
import YuminaiPersistence
import YuminaiUI

// ADR-128 — AppModel.swift 분할: Obsidian 도메인
// Obsidian Vault setup, file watcher, note CRUD, recents/favorites, full-text search, edit mode.
extension AppModel {

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
        githubPATStatus = await secretStatus(for: KeychainKey.githubPersonalAccessToken)
    }

    private func secretStatus(for key: String) async -> SecretStatus {
        do {
            return try await keychainStore.get(key) != nil ? .set : .notSet
        } catch {
            return .error(error.localizedDescription)
        }
    }
}
