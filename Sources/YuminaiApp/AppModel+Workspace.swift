import Foundation
import AppKit
import YuminaiCore
import YuminaiPersistence

// ADR-128 — AppModel.swift 분할: Workspace 도메인
// Workspace CRUD, Pin/Folder/Tag 관리, smart filter, import/export, duplicate.
extension AppModel {

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
}
