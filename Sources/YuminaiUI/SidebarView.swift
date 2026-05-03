import SwiftUI
import UniformTypeIdentifiers
import YuminaiCore

/// 워크스페이스 사이드바 v5 (ADR-076 + ADR-077) — Pin + Folder + Smart folder + Drag/Drop.
///
/// ## 사이드바 구조 (위에서 아래로)
/// 1. **Top header**: collapse / search 버튼
/// 2. **Primary actions**: 새 워크스페이스 / 설정
/// 3. **📌 핀 그룹** (있을 때만, 항상 최상단): drag reorder 가능
/// 4. **🤖 Smart 그룹들**: 활성화된 자동 폴더 (recentWeek, telegramBound 등)
/// 5. **📁 Folder 그룹들**: 사용자가 만든 폴더 (drop target, 색상/아이콘 customization)
/// 6. **Uncategorized 그룹**: 폴더에 안 든 워크스페이스 (drop = 폴더에서 제거)
/// 7. **Update card** (필요 시)
/// 8. **Bottom user card**: 사용자 + 설정
public struct SidebarView: View {
    public let workspaces: [Workspace]
    @Binding public var selectedId: UUID?
    public let telegramBoundId: UUID?
    public let telegramAvailable: Bool
    public let pinnedWorkspaceIds: [UUID]
    public let folders: [WorkspaceFolder]
    /// **ADR-077 Phase 3** — 활성화된 smart folders.
    public let enabledSmartFolders: Set<SmartFolderKind>
    /// **ADR-077 Phase 3** — Smart folder별 매칭 워크스페이스 IDs (호출자가 계산해서 전달).
    public let smartFolderContents: [SmartFolderKind: [UUID]]
    public let onCreate: () -> Void
    public let onDelete: (Workspace) -> Void
    public let onCollapse: () -> Void
    public let onSearch: () -> Void
    public let onOpenSettings: () -> Void
    public let onToggleTelegramBind: (Workspace) -> Void
    public let onConfigureDelivery: (Workspace) -> Void
    public let onEditProjectProfile: (Workspace) -> Void
    public let onTogglePin: (Workspace) -> Void
    public let onToggleFolderExpansion: (UUID) -> Void
    public let onMoveToFolder: (Workspace, UUID?) -> Void
    public let onCreateFolder: () -> Void
    public let onRenameFolder: (WorkspaceFolder) -> Void
    public let onDeleteFolder: (WorkspaceFolder) -> Void
    /// **ADR-077 Phase 4** — Pin 순서 이동 (offset: -1=위, +1=아래).
    public let onMovePin: (Workspace, Int) -> Void
    /// **ADR-077 Phase 4** — Pin drag-to-position (target index).
    public let onMovePinToIndex: (Workspace, Int) -> Void
    /// **ADR-077 Phase 3** — Smart folder 활성/비활성 토글.
    public let onToggleSmartFolder: (SmartFolderKind) -> Void
    public let userName: String
    public let updateAvailable: Bool

    public init(
        workspaces: [Workspace],
        selectedId: Binding<UUID?>,
        telegramBoundId: UUID? = nil,
        telegramAvailable: Bool = false,
        pinnedWorkspaceIds: [UUID] = [],
        folders: [WorkspaceFolder] = [],
        enabledSmartFolders: Set<SmartFolderKind> = [],
        smartFolderContents: [SmartFolderKind: [UUID]] = [:],
        onCreate: @escaping () -> Void,
        onDelete: @escaping (Workspace) -> Void,
        onCollapse: @escaping () -> Void = {},
        onSearch: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {},
        onToggleTelegramBind: @escaping (Workspace) -> Void = { _ in },
        onConfigureDelivery: @escaping (Workspace) -> Void = { _ in },
        onEditProjectProfile: @escaping (Workspace) -> Void = { _ in },
        onTogglePin: @escaping (Workspace) -> Void = { _ in },
        onToggleFolderExpansion: @escaping (UUID) -> Void = { _ in },
        onMoveToFolder: @escaping (Workspace, UUID?) -> Void = { _, _ in },
        onCreateFolder: @escaping () -> Void = {},
        onRenameFolder: @escaping (WorkspaceFolder) -> Void = { _ in },
        onDeleteFolder: @escaping (WorkspaceFolder) -> Void = { _ in },
        onMovePin: @escaping (Workspace, Int) -> Void = { _, _ in },
        onMovePinToIndex: @escaping (Workspace, Int) -> Void = { _, _ in },
        onToggleSmartFolder: @escaping (SmartFolderKind) -> Void = { _ in },
        userName: String = "yuminai",
        updateAvailable: Bool = false
    ) {
        self.workspaces = workspaces
        self._selectedId = selectedId
        self.telegramBoundId = telegramBoundId
        self.telegramAvailable = telegramAvailable
        self.pinnedWorkspaceIds = pinnedWorkspaceIds
        self.folders = folders
        self.enabledSmartFolders = enabledSmartFolders
        self.smartFolderContents = smartFolderContents
        self.onCreate = onCreate
        self.onDelete = onDelete
        self.onCollapse = onCollapse
        self.onSearch = onSearch
        self.onOpenSettings = onOpenSettings
        self.onToggleTelegramBind = onToggleTelegramBind
        self.onConfigureDelivery = onConfigureDelivery
        self.onEditProjectProfile = onEditProjectProfile
        self.onTogglePin = onTogglePin
        self.onToggleFolderExpansion = onToggleFolderExpansion
        self.onMoveToFolder = onMoveToFolder
        self.onCreateFolder = onCreateFolder
        self.onRenameFolder = onRenameFolder
        self.onDeleteFolder = onDeleteFolder
        self.onMovePin = onMovePin
        self.onMovePinToIndex = onMovePinToIndex
        self.onToggleSmartFolder = onToggleSmartFolder
        self.userName = userName
        self.updateAvailable = updateAvailable
    }

    public var body: some View {
        VStack(spacing: 0) {
            topHeader
            primaryAndMenu
            workspaceList
            Spacer(minLength: 0)
            if updateAvailable {
                UpdateCard()
                    .padding(.horizontal, Theme.Layout.sidebarPadding)
                    .padding(.bottom, Theme.Spacing.sm)
            }
            BottomUserCard(name: userName, onSettings: onOpenSettings)
        }
        .frame(width: Theme.Layout.sidebarWidth)
        .background(Theme.Color.bgSidebar)
    }

    // MARK: - Top header (collapse + search + smart folders menu)

    private var topHeader: some View {
        HStack(spacing: 4) {
            IconButton("sidebar.left", help: "사이드바 접기 (⌘⌥1)", action: onCollapse)
            IconButton("magnifyingglass", help: "워크스페이스 검색 (⌘P)", action: onSearch)
            Spacer()
            // ADR-077 Phase 3 — Smart folders 토글 메뉴
            smartFolderMenu
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(height: Theme.Layout.toolbarHeight)
    }

    private var smartFolderMenu: some View {
        Menu {
            Text("자동 그룹 표시")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
            Divider()
            ForEach(SmartFolderKind.allCases) { kind in
                Button {
                    onToggleSmartFolder(kind)
                } label: {
                    HStack {
                        if enabledSmartFolders.contains(kind) {
                            Image(systemName: "checkmark")
                        }
                        Image(systemName: kind.iconName)
                        Text(kind.displayName)
                    }
                }
            }
        } label: {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(enabledSmartFolders.isEmpty ? Theme.Color.textSecondary : Theme.Color.accent)
                .frame(width: 28, height: 28)
                .background(Theme.Color.surfaceHi.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("자동 그룹 (Smart folders)")
        .accessibilityLabel("자동 그룹 메뉴")
        .accessibilityHint("최근 7일, 텔레그램 연결 등 자동 분류 폴더 표시 토글")
    }

    // MARK: - "+ New workspace" + Settings

    private var primaryAndMenu: some View {
        VStack(alignment: .leading, spacing: 1) {
            SidebarPrimaryRow(
                label: "새 워크스페이스",
                icon: "plus",
                action: onCreate
            )
            SidebarMenuRow(
                label: "설정",
                icon: "gear",
                action: onOpenSettings
            )
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.md)
    }

    // MARK: - Workspace list

    private var workspacesById: [UUID: Workspace] {
        Dictionary(uniqueKeysWithValues: workspaces.map { ($0.id, $0) })
    }

    private var foldersWorkspaceIds: Set<UUID> {
        Set(folders.flatMap { $0.workspaceIds })
    }

    private var pinnedWorkspaces: [Workspace] {
        pinnedWorkspaceIds.compactMap { workspacesById[$0] }
    }

    private var uncategorizedWorkspaces: [Workspace] {
        workspaces.filter { !foldersWorkspaceIds.contains($0.id) }
    }

    private func shortcutIndex(of workspaceId: UUID) -> Int? {
        if let pinIdx = pinnedWorkspaces.firstIndex(where: { $0.id == workspaceId }) {
            return pinIdx
        }
        var idx = pinnedWorkspaces.count
        for folder in folders where folder.isExpanded {
            for ws in folder.workspaceIds.compactMap({ workspacesById[$0] }) {
                if ws.id == workspaceId { return idx }
                idx += 1
            }
        }
        for ws in uncategorizedWorkspaces {
            if ws.id == workspaceId { return idx }
            idx += 1
        }
        return nil
    }

    @ViewBuilder
    private var workspaceList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if workspaces.isEmpty {
                    EmptyWorkspaceHint(onCreate: onCreate)
                } else {
                    // 1. Pin 그룹 (drag reorder 활성)
                    if !pinnedWorkspaces.isEmpty {
                        pinSection
                    }
                    // 2. Smart 그룹들 (활성화된 것만, 매칭 워크스페이스가 있을 때만)
                    ForEach(SmartFolderKind.allCases) { kind in
                        if enabledSmartFolders.contains(kind),
                           let ids = smartFolderContents[kind], !ids.isEmpty {
                            smartFolderSection(kind, workspaceIds: ids)
                        }
                    }
                    // 3. 사용자 폴더 그룹들 (drop target)
                    ForEach(folders) { folder in
                        folderSection(folder)
                    }
                    // 4. Uncategorized (drop = 폴더에서 제거)
                    if !uncategorizedWorkspaces.isEmpty {
                        uncategorizedSection
                    }
                    // 5. "새 폴더 만들기"
                    newFolderButton
                }
            }
        }
    }

    // MARK: - Pin section (ADR-076 + ADR-077 Phase 4 — drag reorder)

    private var pinSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.Color.accent)
                    .accessibilityHidden(true)
                Text("핀")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.6)
            }
            .padding(.horizontal, Theme.Layout.sidebarItemPadH + Theme.Spacing.sm)
            .padding(.top, Theme.Layout.sidebarGroupHeaderTop)
            .padding(.bottom, Theme.Spacing.sm)

            VStack(spacing: 1) {
                ForEach(Array(pinnedWorkspaces.enumerated()), id: \.element.id) { idx, workspace in
                    workspaceRow(workspace, pinIndex: idx)
                        // ADR-077 Phase 4 — Pin reorder drag (workspace 자체)
                        .draggable(WorkspacePinReorderPayload(workspaceId: workspace.id, currentIndex: idx))
                        // 다른 pin 위로 drop = swap (target index에 삽입)
                        .dropDestination(for: WorkspacePinReorderPayload.self) { items, _ in
                            guard let item = items.first else { return false }
                            onMovePinToIndex(workspace, idx)
                            _ = item  // suppress warning (workspaceId already in callback context)
                            return true
                        }
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
        }
    }

    // MARK: - Smart folder section (ADR-077 Phase 3)

    @ViewBuilder
    private func smartFolderSection(_ kind: SmartFolderKind, workspaceIds: [UUID]) -> some View {
        let smartWorkspaces = workspaceIds.compactMap { workspacesById[$0] }
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: kind.iconName)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.folderColor(for: kind.colorName))
                    .accessibilityHidden(true)
                Text(kind.displayName)
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Color.text)
                Text("\(smartWorkspaces.count)")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Theme.Color.surfaceHi)
                    .clipShape(Capsule())
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 8))
                    .foregroundStyle(Theme.Color.textTertiary)
                    .accessibilityHidden(true)
                Spacer()
            }
            .padding(.horizontal, Theme.Layout.sidebarItemPadH + Theme.Spacing.sm)
            .padding(.top, Theme.Layout.sidebarGroupHeaderTop)
            .padding(.bottom, Theme.Spacing.sm)
            .help(kind.hint)

            VStack(spacing: 1) {
                ForEach(smartWorkspaces) { workspace in
                    workspaceRow(workspace, indented: true)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
        }
    }

    // MARK: - Folder section (drop target — ADR-077 Phase 1)

    @State private var hoveringFolderId: UUID?

    @ViewBuilder
    private func folderSection(_ folder: WorkspaceFolder) -> some View {
        let isDropTarget = hoveringFolderId == folder.id
        VStack(alignment: .leading, spacing: 0) {
            FolderHeaderRow(
                folder: folder,
                workspaceCount: folder.workspaceIds.count,
                isDropTarget: isDropTarget,
                onToggle: { onToggleFolderExpansion(folder.id) },
                onRename: { onRenameFolder(folder) },
                onDelete: { onDeleteFolder(folder) }
            )
            // ADR-077 Phase 1 — Folder header가 drop target
            .dropDestination(for: WorkspaceDragPayload.self) { items, _ in
                guard let item = items.first,
                      let ws = workspacesById[item.workspaceId] else { return false }
                onMoveToFolder(ws, folder.id)
                hoveringFolderId = nil
                return true
            } isTargeted: { hovering in
                hoveringFolderId = hovering ? folder.id : nil
            }

            if folder.isExpanded {
                let folderWorkspaces = folder.workspaceIds.compactMap { workspacesById[$0] }
                if folderWorkspaces.isEmpty {
                    Text("(비어있음 — 워크스페이스를 여기로 끌어다 놓으세요)")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                        .padding(.horizontal, Theme.Layout.sidebarItemPadH + Theme.Spacing.lg)
                        .padding(.vertical, Theme.Spacing.xs)
                } else {
                    VStack(spacing: 1) {
                        ForEach(folderWorkspaces) { workspace in
                            workspaceRow(workspace, indented: true)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.sm)
                }
            }
        }
    }

    // MARK: - Uncategorized section (drop = 폴더에서 제거 — ADR-077 Phase 1)

    @State private var hoveringUncategorized: Bool = false

    private var uncategorizedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            uncategorizedHeader
            VStack(spacing: 1) {
                ForEach(uncategorizedWorkspaces) { workspace in
                    workspaceRow(workspace)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
        }
        // ADR-077 Phase 1 — uncategorized 영역에 drop = 폴더에서 제거
        .dropDestination(for: WorkspaceDragPayload.self) { items, _ in
            guard let item = items.first,
                  let ws = workspacesById[item.workspaceId] else { return false }
            onMoveToFolder(ws, nil)
            hoveringUncategorized = false
            return true
        } isTargeted: { hovering in
            hoveringUncategorized = hovering
        }
        .background(hoveringUncategorized ? Theme.Color.surfaceHi.opacity(0.3) : .clear)
        .animation(.easeOut(duration: 0.15), value: hoveringUncategorized)
    }

    @ViewBuilder
    private var uncategorizedHeader: some View {
        let label: String = {
            if !folders.isEmpty || !enabledSmartFolders.isEmpty {
                return "기타 워크스페이스"
            } else if !pinnedWorkspaces.isEmpty {
                return "전체"
            } else {
                return "워크스페이스"
            }
        }()
        Text(label)
            .font(Theme.Typography.micro)
            .foregroundStyle(Theme.Color.textTertiary)
            .textCase(.uppercase)
            .tracking(0.6)
            .padding(.horizontal, Theme.Layout.sidebarItemPadH + Theme.Spacing.sm)
            .padding(.top, Theme.Layout.sidebarGroupHeaderTop)
            .padding(.bottom, Theme.Spacing.sm)
    }

    // MARK: - "새 폴더 만들기"

    private var newFolderButton: some View {
        Button(action: onCreateFolder) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.textTertiary)
                Text("새 폴더 만들기")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textTertiary)
                Spacer()
            }
            .padding(.horizontal, Theme.Layout.sidebarItemPadH + Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, Theme.Spacing.lg)
        .accessibilityLabel("새 폴더 만들기")
    }

    // MARK: - 공통 workspace row

    @ViewBuilder
    private func workspaceRow(_ workspace: Workspace, indented: Bool = false, pinIndex: Int? = nil) -> some View {
        WorkspaceItemRow(
            workspace: workspace,
            shortcutIndex: shortcutIndex(of: workspace.id),
            pinIndex: pinIndex,
            pinnedTotal: pinnedWorkspaces.count,
            isSelected: workspace.id == selectedId,
            isTelegramBound: workspace.id == telegramBoundId,
            isPinned: pinnedWorkspaceIds.contains(workspace.id),
            telegramAvailable: telegramAvailable,
            indented: indented,
            availableFolders: folders,
            currentFolderId: folders.first(where: { $0.workspaceIds.contains(workspace.id) })?.id,
            onSelect: { selectedId = workspace.id },
            onDelete: { onDelete(workspace) },
            onToggleTelegramBind: { onToggleTelegramBind(workspace) },
            onConfigureDelivery: { onConfigureDelivery(workspace) },
            onEditProjectProfile: { onEditProjectProfile(workspace) },
            onTogglePin: { onTogglePin(workspace) },
            onMoveToFolder: { folderId in onMoveToFolder(workspace, folderId) },
            onCreateNewFolder: onCreateFolder,
            onMovePinUp: pinIndex != nil ? { onMovePin(workspace, -1) } : nil,
            onMovePinDown: pinIndex != nil ? { onMovePin(workspace, +1) } : nil
        )
        // ADR-077 Phase 1 — pinned 그룹 외에는 일반 drag (folder로 이동용)
        .modifier(WorkspaceDragModifier(workspaceId: workspace.id, isPinReorder: pinIndex != nil))
    }
}

/// **ADR-077 Phase 1** — pin index 유무에 따라 다른 draggable payload 적용.
struct WorkspaceDragModifier: ViewModifier {
    let workspaceId: UUID
    let isPinReorder: Bool

    func body(content: Content) -> some View {
        if isPinReorder {
            // pinSection에서 별도로 .draggable(.pinReorder) 적용 → 여기선 no-op
            content
        } else {
            content.draggable(WorkspaceDragPayload(workspaceId: workspaceId))
        }
    }
}

// MARK: - FolderHeaderRow (ADR-077 Phase 2 — 색상/아이콘 + drop target highlight)

struct FolderHeaderRow: View {
    let folder: WorkspaceFolder
    let workspaceCount: Int
    /// **ADR-077 Phase 1** — drag hover 중 강조.
    let isDropTarget: Bool
    let onToggle: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.Color.textSecondary)
                    .rotationEffect(.degrees(folder.isExpanded ? 90 : 0))
                    .frame(width: 12)
                Image(systemName: folder.iconName)
                    .font(.system(size: 11))
                    // ADR-077 Phase 2 — folder colorName 적용
                    .foregroundStyle(Theme.Color.folderColor(for: folder.colorName))
                    .frame(width: 14)
                Text(folder.name)
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Color.text)
                    .lineLimit(1)
                Text("\(workspaceCount)")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Theme.Color.surfaceHi)
                    .clipShape(Capsule())
                Spacer()
            }
            .padding(.horizontal, Theme.Layout.sidebarItemPadH + Theme.Spacing.xs)
            .padding(.vertical, Theme.Layout.sidebarItemPadV + 1)
            // ADR-077 Phase 1 — drop target일 때 folder 색상으로 강조
            .background(
                isDropTarget
                    ? Theme.Color.folderColor(for: folder.colorName).opacity(0.18)
                    : (hovering ? Theme.Color.surfaceHi.opacity(0.5) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .stroke(
                        isDropTarget ? Theme.Color.folderColor(for: folder.colorName) : .clear,
                        lineWidth: 2
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.15), value: folder.isExpanded)
            .animation(.easeOut(duration: 0.10), value: hovering)
            .animation(.easeOut(duration: 0.15), value: isDropTarget)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.top, Theme.Layout.sidebarGroupHeaderTop)
        .padding(.bottom, Theme.Spacing.xs)
        .contextMenu {
            Button("이름·색상·아이콘 편집…", systemImage: "pencil", action: onRename)
            Divider()
            Button("폴더 삭제 (안의 워크스페이스는 유지)", systemImage: "folder.badge.minus", role: .destructive, action: onDelete)
        }
        .accessibilityLabel("폴더 \(folder.name), \(workspaceCount)개 워크스페이스, \(folder.isExpanded ? "펼쳐짐" : "접힘")\(isDropTarget ? ", 드롭 가능" : "")")
        .accessibilityHint("탭하여 펼치거나 접습니다. 워크스페이스를 끌어다 놓으면 폴더에 추가됩니다.")
    }
}

// MARK: - Sidebar item rows (ADR-076 + ADR-077 — pin reorder menu)

struct SidebarPrimaryRow: View {
    let label: String
    let icon: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm + 2) {
                Image(systemName: icon)
                    .font(.system(size: Theme.Layout.sidebarIconSize, weight: .semibold))
                    .foregroundStyle(Theme.Color.accent)
                    .frame(width: 16)
                Text(label)
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Color.text)
                Spacer()
            }
            .padding(.horizontal, Theme.Layout.sidebarItemPadH)
            .padding(.vertical, Theme.Layout.sidebarItemPadV)
            .frame(height: Theme.Layout.sidebarItemHeight)
            .background(hovering ? Theme.Color.surfaceHi : .clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .keyboardShortcut("n", modifiers: .command)
    }
}

struct SidebarMenuRow: View {
    let label: String
    let icon: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm + 2) {
                Image(systemName: icon)
                    .font(.system(size: Theme.Layout.sidebarIconSize, weight: .regular))
                    .foregroundStyle(Theme.Color.textSecondary)
                    .frame(width: 16)
                Text(label)
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer()
            }
            .padding(.horizontal, Theme.Layout.sidebarItemPadH)
            .padding(.vertical, Theme.Layout.sidebarItemPadV)
            .frame(height: Theme.Layout.sidebarItemHeight)
            .background(hovering ? Theme.Color.surfaceHi : .clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct SidebarGroupHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(Theme.Typography.micro)
            .foregroundStyle(Theme.Color.textTertiary)
            .textCase(.uppercase)
            .tracking(0.6)
            .padding(.horizontal, Theme.Layout.sidebarItemPadH + Theme.Spacing.sm)
            .padding(.top, Theme.Layout.sidebarGroupHeaderTop)
            .padding(.bottom, Theme.Spacing.sm)
    }
}

struct WorkspaceItemRow: View {
    let workspace: Workspace
    let shortcutIndex: Int?
    /// **ADR-077 Phase 4** — pin 그룹 안 위치 (없으면 nil — 일반 row).
    let pinIndex: Int?
    /// **ADR-077 Phase 4** — pin 그룹 총 개수 (boundary 체크용).
    let pinnedTotal: Int
    let isSelected: Bool
    let isTelegramBound: Bool
    let isPinned: Bool
    let telegramAvailable: Bool
    let indented: Bool
    let availableFolders: [WorkspaceFolder]
    let currentFolderId: UUID?
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onToggleTelegramBind: () -> Void
    let onConfigureDelivery: () -> Void
    let onEditProjectProfile: () -> Void
    let onTogglePin: () -> Void
    let onMoveToFolder: (UUID?) -> Void
    let onCreateNewFolder: () -> Void
    /// **ADR-077 Phase 4** — pin 그룹 안 위/아래 이동 (nil = 비활성).
    let onMovePinUp: (() -> Void)?
    let onMovePinDown: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Theme.Spacing.sm + 2) {
                ZStack {
                    Circle()
                        .stroke(Theme.Color.borderSubtle, lineWidth: 1)
                        .frame(width: Theme.Layout.sidebarDotSize, height: Theme.Layout.sidebarDotSize)
                    if isSelected {
                        Circle()
                            .fill(Theme.Color.accent)
                            .frame(width: Theme.Layout.sidebarDotSize, height: Theme.Layout.sidebarDotSize)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 16)
                .animation(.easeOut(duration: 0.15), value: isSelected)
                .accessibilityHidden(true)

                Text(workspace.name)
                    .font(Theme.Typography.label)
                    .foregroundStyle(isSelected ? Theme.Color.text : Theme.Color.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.Color.accent)
                        .accessibilityHidden(true)
                }

                if isTelegramBound {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.Color.accent)
                        .help("텔레그램에서 제어 중인 세션")
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityHidden(true)
                }

                Spacer()

                if let idx = shortcutIndex, idx < 9 && hovering && !isSelected {
                    Text("⌘\(idx + 1)")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                        .transition(.opacity)
                }
            }
            .padding(.leading, indented ? Theme.Layout.sidebarItemPadH + Theme.Spacing.lg : Theme.Layout.sidebarItemPadH)
            .padding(.trailing, Theme.Layout.sidebarItemPadH)
            .padding(.vertical, Theme.Layout.sidebarItemPadV)
            .frame(height: Theme.Layout.sidebarItemHeight)
            .background(rowBg)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .selectedBar(isSelected)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.10), value: hovering)
            .animation(.easeOut(duration: 0.15), value: isTelegramBound)
        }
        .buttonStyle(PressedScaleStyle(scale: 0.98))
        .onHover { hovering = $0 }
        .contextMenu {
            // Pin 토글
            Button(
                isPinned ? "상단 고정 해제" : "상단에 고정",
                systemImage: isPinned ? "pin.slash" : "pin",
                action: onTogglePin
            )
            // ADR-077 Phase 4 — Pin 순서 이동 (pin 그룹 안에서만)
            if let onMovePinUp, let pinIdx = pinIndex {
                Divider()
                Button("위로 이동", systemImage: "chevron.up", action: onMovePinUp)
                    .disabled(pinIdx == 0)
                if let onMovePinDown {
                    Button("아래로 이동", systemImage: "chevron.down", action: onMovePinDown)
                        .disabled(pinIdx >= pinnedTotal - 1)
                }
            }
            // 폴더 이동
            Menu {
                Button("폴더에서 제거 (전체로)", systemImage: "tray.and.arrow.up") {
                    onMoveToFolder(nil)
                }
                .disabled(currentFolderId == nil)
                Divider()
                ForEach(availableFolders) { folder in
                    Button {
                        onMoveToFolder(folder.id)
                    } label: {
                        HStack {
                            if folder.id == currentFolderId {
                                Image(systemName: "checkmark")
                            }
                            Image(systemName: folder.iconName)
                            Text(folder.name)
                        }
                    }
                }
                if !availableFolders.isEmpty {
                    Divider()
                }
                Button("새 폴더 만들기…", systemImage: "folder.badge.plus", action: onCreateNewFolder)
            } label: {
                Label("폴더로 이동", systemImage: "folder")
            }
            Divider()
            Button("이름 복사") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(workspace.name, forType: .string)
            }
            if telegramAvailable {
                Divider()
                Button(isTelegramBound ? "텔레그램 연결 해제" : "텔레그램에 연결",
                       systemImage: isTelegramBound ? "paperplane.slash" : "paperplane",
                       action: onToggleTelegramBind)
            }
            Divider()
            Button("Delivery 자동화 설정…",
                   systemImage: "checkmark.shield",
                   action: onConfigureDelivery)
            Button("프로젝트 프로필 편집…",
                   systemImage: "rectangle.stack.fill",
                   action: onEditProjectProfile)
            Divider()
            Button("지우기", role: .destructive, action: onDelete)
        }
        .accessibilityLabel("\(workspace.name)\(isSelected ? ", 선택됨" : "")\(isPinned ? ", 고정됨" : "")\(isTelegramBound ? ", 텔레그램 연결됨" : "")")
        .accessibilityHint("이중 클릭으로 활성화. 우클릭으로 메뉴. 끌어서 폴더로 이동.")
    }

    private var rowBg: SwiftUI.Color {
        if isSelected { return Theme.Color.elevated }
        if hovering { return Theme.Color.surfaceHi }
        return .clear
    }
}

struct EmptyWorkspaceHint: View {
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("아직 시작한 작업이 없네요.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
            Text("위 ‘+ 새 워크스페이스’로 시작해보세요.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textTertiary)
        }
        .padding(.horizontal, Theme.Layout.sidebarPadding)
        .padding(.top, Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Update card / Bottom user card (변경 없음)

public struct UpdateCard: View {
    public init() {}

    public var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Color.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("업데이트 준비")
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Color.text)
                Text("새 버전이 도착했어요")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Color.textSecondary)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(Theme.Color.borderSubtle, lineWidth: Theme.Stroke.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
    }
}

public struct BottomUserCard: View {
    public let name: String
    public let onSettings: () -> Void

    public init(name: String, onSettings: @escaping () -> Void) {
        self.name = name
        self.onSettings = onSettings
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Circle()
                .fill(Theme.Color.surfaceHi)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.Color.textSecondary)
                )
                .frame(width: 22, height: 22)
            Text(name)
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Color.text)
            Spacer()
            IconButton("gearshape", size: 14, help: "설정 (⌘,)", action: onSettings)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm + 2)
        .frame(height: 48)
        .overlay(alignment: .top) {
            FlatHDivider()
        }
    }
}
