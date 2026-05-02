import Foundation
import Observation
import YuminaiCore

/// 워크스페이스 파일 시스템 (트리 + 다중 탭 + 다중 선택 + CRUD) 단일 책임 (ADR-042 R3.2).
///
/// **분리 근거 (audit C1)**:
/// - AppModel에서 두 번째로 큰 도메인 (state 9개 + 메서드 ~17개, ~310줄)
/// - WorkspaceFileTree actor wrapping + tab lifecycle + multi-select + inline rename + CRUD가 한 클래스에 응집 가능
/// - workspace 의존성은 외부 (rootURL caller가 주입) — 다른 도메인과 cross-coupling X
///
/// **Facade 패턴**: AppModel은 `files` 보유 + 기존 호출자 API (workspaceFileTree, openFileTabs 등)는
/// computed pass-through로 유지 → R3.1 패턴과 동일.
///
/// **Legacy alias 정리**: `selectedFilePath`/`selectedFileContents`/`isEditingWorkspaceFile`/`workspaceFileDraft`/
/// `isWorkspaceFileDirty`는 AppModel에서 제거되고, 호출자가 `files.activeTab?.path` 등 직접 사용 (ADR-042 R3.2 정리).
@MainActor
@Observable
public final class WorkspaceFileManager {
    // MARK: - State

    public var tree: [FileNode] = []
    /// 열린 파일 tab들 (max 10, FIFO non-dirty 제거).
    public var openTabs: [FileTab] = []
    /// 활성 tab id.
    public var activeTabId: UUID?
    /// File search (Cmd+P) 표시 여부.
    public var showSearchSheet: Bool = false
    /// File CRUD sheet/alert state.
    public var nameSheetIntent: FileNameSheetIntent?
    public var deleteConfirmation: FileDeleteConfirmation?
    /// 다중 선택 (Cmd+Click).
    public var selectedPaths: Set<String> = []
    /// inline rename 대상 path.
    public var inlineRenamePath: String?

    /// 마지막 에러 메시지 (caller가 표시).
    public var lastError: String?

    private var actor: WorkspaceFileTree?

    public init() {}

    // MARK: - Active tab projection

    public var activeTab: FileTab? {
        openTabs.first { $0.id == activeTabId }
    }

    /// active tab의 draft 편집 (custom setter — array mutation).
    public var activeDraft: String {
        get { activeTab?.draft ?? "" }
        set {
            guard let id = activeTabId,
                  let idx = openTabs.firstIndex(where: { $0.id == id }) else { return }
            openTabs[idx].draft = newValue
        }
    }

    // MARK: - Tree refresh

    public func refresh(workspace: Workspace?) async {
        guard let workspace else {
            tree = []
            return
        }
        let actor: WorkspaceFileTree
        if let existing = self.actor, existing.rootURL.path == workspace.directoryPath {
            actor = existing
        } else {
            actor = WorkspaceFileTree(rootURL: URL(fileURLWithPath: workspace.directoryPath))
            self.actor = actor
        }
        do {
            tree = try await actor.tree()
        } catch {
            lastError = "파일 트리 로드 실패: \(error.localizedDescription)"
        }
    }

    // MARK: - Tab lifecycle

    public func selectFile(_ relativePath: String) async {
        guard let actor else { return }
        if let existing = openTabs.first(where: { $0.path == relativePath }) {
            activeTabId = existing.id
            return
        }
        do {
            let contents = try await actor.read(relativePath)
            let tab = FileTab(path: relativePath, savedContents: contents)
            openTabs.append(tab)
            activeTabId = tab.id
            if openTabs.count > AppLimits.maxFileTabs {
                if let firstClean = openTabs.firstIndex(where: { !$0.isDirty && $0.id != tab.id }) {
                    openTabs.remove(at: firstClean)
                }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func setActiveTab(_ tabId: UUID) {
        guard openTabs.contains(where: { $0.id == tabId }) else { return }
        activeTabId = tabId
    }

    public func closeTab(_ tabId: UUID) {
        guard let idx = openTabs.firstIndex(where: { $0.id == tabId }) else { return }
        if openTabs[idx].isDirty {
            lastError = "저장 안 된 변경이 있어요: \(openTabs[idx].displayName). 저장 또는 취소 후 닫으세요."
            return
        }
        let wasActive = activeTabId == tabId
        openTabs.remove(at: idx)
        if wasActive {
            if idx < openTabs.count {
                activeTabId = openTabs[idx].id
            } else if idx > 0 {
                activeTabId = openTabs[idx - 1].id
            } else {
                activeTabId = nil
            }
        }
    }

    public func closeAllNonDirtyTabs() {
        let cleanIds = openTabs.filter { !$0.isDirty }.map(\.id)
        for id in cleanIds {
            closeTab(id)
        }
    }

    public func selectAdjacentTab(offset: Int) {
        guard !openTabs.isEmpty else { return }
        let currentIdx = activeTabId.flatMap { id in
            openTabs.firstIndex(where: { $0.id == id })
        } ?? 0
        let count = openTabs.count
        let nextIdx = ((currentIdx + offset) % count + count) % count
        activeTabId = openTabs[nextIdx].id
    }

    public func closeActiveTab() {
        guard let id = activeTabId else { return }
        closeTab(id)
    }

    public func startEditing() {
        guard let id = activeTabId,
              let idx = openTabs.firstIndex(where: { $0.id == id }) else { return }
        openTabs[idx].draft = openTabs[idx].savedContents
        openTabs[idx].isEditing = true
    }

    public func save() async {
        guard let id = activeTabId,
              let idx = openTabs.firstIndex(where: { $0.id == id }),
              let actor else { return }
        let tab = openTabs[idx]
        do {
            try await actor.write(tab.path, contents: tab.draft)
            openTabs[idx].savedContents = tab.draft
            openTabs[idx].isEditing = false
        } catch {
            lastError = "파일 저장 실패: \(error.localizedDescription)"
        }
    }

    public func discardEdits() {
        guard let id = activeTabId,
              let idx = openTabs.firstIndex(where: { $0.id == id }) else { return }
        openTabs[idx].draft = openTabs[idx].savedContents
        openTabs[idx].isEditing = false
    }

    // MARK: - CRUD (ADR-039/040)

    public func createFile(at relativePath: String) async {
        guard let actor else { return }
        do {
            let path = try await actor.createFile(relativePath)
            await refresh(workspace: currentWorkspaceFromActor)
            await selectFile(path)
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func createFolder(at relativePath: String) async {
        guard let actor else { return }
        do {
            try await actor.createFolder(relativePath)
            await refresh(workspace: currentWorkspaceFromActor)
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func renameNode(at relativePath: String, to newName: String) async {
        guard let actor else { return }
        do {
            let newPath = try await actor.rename(relativePath, to: newName)
            updateTabPathsForRename(oldPath: relativePath, newPath: newPath)
            await refresh(workspace: currentWorkspaceFromActor)
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func commitNameIntent(_ intent: FileNameSheetIntent, name: String) async {
        switch intent {
        case .newFile(let parent):
            let path = parent.isEmpty ? name : "\(parent)/\(name)"
            await createFile(at: path)
        case .newFolder(let parent):
            let path = parent.isEmpty ? name : "\(parent)/\(name)"
            await createFolder(at: path)
        case .rename(let path, _):
            await renameNode(at: path, to: name)
        }
    }

    public func deleteNode(at relativePath: String, moveToTrash: Bool = true) async {
        guard let actor else { return }
        do {
            try await actor.delete(relativePath, moveToTrash: moveToTrash)
            closeTabsAffectedByPath(relativePath)
            selectedPaths.remove(relativePath)
            await refresh(workspace: currentWorkspaceFromActor)
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func moveNode(at relativePath: String, to newRelativePath: String) async {
        guard let actor else { return }
        do {
            let newPath = try await actor.move(relativePath, to: newRelativePath)
            updateTabPathsForRename(oldPath: relativePath, newPath: newPath)
            await refresh(workspace: currentWorkspaceFromActor)
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func deleteSelected(moveToTrash: Bool = true) async {
        guard let actor, !selectedPaths.isEmpty else { return }
        let paths = Array(selectedPaths)
        do {
            try await actor.deleteMany(paths, moveToTrash: moveToTrash)
        } catch {
            lastError = "일부 삭제 실패: \(error.localizedDescription)"
        }
        for path in paths {
            closeTabsAffectedByPath(path)
        }
        selectedPaths.removeAll()
        await refresh(workspace: currentWorkspaceFromActor)
    }

    // MARK: - Selection (ADR-040 F3)

    public func toggleSelection(_ path: String) {
        if selectedPaths.contains(path) {
            selectedPaths.remove(path)
        } else {
            selectedPaths.insert(path)
        }
    }

    public func clearSelection() {
        selectedPaths.removeAll()
    }

    // MARK: - Inline rename (ADR-040 F4)

    public func beginInlineRename(_ path: String) {
        inlineRenamePath = path
    }

    public func cancelInlineRename() {
        inlineRenamePath = nil
    }

    public func commitInlineRename(_ path: String, newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != (path as NSString).lastPathComponent else {
            inlineRenamePath = nil
            return
        }
        await renameNode(at: path, to: trimmed)
        inlineRenamePath = nil
    }

    // MARK: - Tab sync helpers

    private func updateTabPathsForRename(oldPath: String, newPath: String) {
        for idx in openTabs.indices {
            let p = openTabs[idx].path
            if p == oldPath {
                openTabs[idx] = FileTab(
                    id: openTabs[idx].id,
                    path: newPath,
                    savedContents: openTabs[idx].savedContents,
                    draft: openTabs[idx].draft,
                    isEditing: openTabs[idx].isEditing
                )
            } else if p.hasPrefix(oldPath + "/") {
                let suffix = p.dropFirst(oldPath.count + 1)
                openTabs[idx] = FileTab(
                    id: openTabs[idx].id,
                    path: "\(newPath)/\(suffix)",
                    savedContents: openTabs[idx].savedContents,
                    draft: openTabs[idx].draft,
                    isEditing: openTabs[idx].isEditing
                )
            }
        }
    }

    private func closeTabsAffectedByPath(_ relativePath: String) {
        let affectedIds = openTabs
            .filter { $0.path == relativePath || $0.path.hasPrefix(relativePath + "/") }
            .map(\.id)
        for id in affectedIds {
            if let idx = openTabs.firstIndex(where: { $0.id == id }) {
                openTabs.remove(at: idx)
                if activeTabId == id {
                    activeTabId = openTabs.last?.id
                }
            }
        }
    }

    /// actor가 보유한 rootURL로 임시 Workspace 재구성 (refresh 내부 호출 전용).
    /// CRUD 메서드들이 refresh를 호출할 때 사용 — caller workspace 인자 X.
    private var currentWorkspaceFromActor: Workspace? {
        guard let actor else { return nil }
        return Workspace(name: "", directoryPath: actor.rootURL.path)
    }
}
