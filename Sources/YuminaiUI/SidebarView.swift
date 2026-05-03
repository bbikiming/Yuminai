import SwiftUI
import YuminaiCore

/// 워크스페이스 사이드바 v4 (ADR-076) — Pin + Folder 그룹화 지원.
///
/// ## 사이드바 구조 (위에서 아래로)
/// 1. **Top header**: collapse / search 버튼
/// 2. **Primary actions**: 새 워크스페이스 / 설정
/// 3. **Pin 그룹** (있을 때만): 사용자가 핀한 워크스페이스 (📌 아이콘)
/// 4. **Folder 그룹들**: 사용자가 만든 폴더 (📁 아이콘, expand/collapse)
/// 5. **Uncategorized 그룹**: 폴더에 안 든 워크스페이스
/// 6. **Update card** (필요 시)
/// 7. **Bottom user card**: 사용자 + 설정 진입
public struct SidebarView: View {
    public let workspaces: [Workspace]
    @Binding public var selectedId: UUID?
    public let telegramBoundId: UUID?
    public let telegramAvailable: Bool
    /// **ADR-076 Phase 1** — 핀된 워크스페이스 IDs (사이드바 상단 그룹).
    public let pinnedWorkspaceIds: [UUID]
    /// **ADR-076 Phase 1** — 워크스페이스 폴더들.
    public let folders: [WorkspaceFolder]
    public let onCreate: () -> Void
    public let onDelete: (Workspace) -> Void
    public let onCollapse: () -> Void
    public let onSearch: () -> Void
    public let onOpenSettings: () -> Void
    public let onToggleTelegramBind: (Workspace) -> Void
    public let onConfigureDelivery: (Workspace) -> Void
    public let onEditProjectProfile: (Workspace) -> Void
    /// **ADR-076 Phase 4** — 핀 토글 콜백.
    public let onTogglePin: (Workspace) -> Void
    /// **ADR-076 Phase 4** — 폴더 expand/collapse 토글.
    public let onToggleFolderExpansion: (UUID) -> Void
    /// **ADR-076 Phase 4** — 워크스페이스를 폴더로 이동 (folderId == nil이면 폴더에서 제거).
    public let onMoveToFolder: (Workspace, UUID?) -> Void
    /// **ADR-076 Phase 4** — 새 폴더 생성 (이름 입력은 호출자가 처리).
    public let onCreateFolder: () -> Void
    /// **ADR-076 Phase 4** — 폴더 이름 변경.
    public let onRenameFolder: (WorkspaceFolder) -> Void
    /// **ADR-076 Phase 4** — 폴더 삭제.
    public let onDeleteFolder: (WorkspaceFolder) -> Void
    public let userName: String
    public let updateAvailable: Bool

    public init(
        workspaces: [Workspace],
        selectedId: Binding<UUID?>,
        telegramBoundId: UUID? = nil,
        telegramAvailable: Bool = false,
        pinnedWorkspaceIds: [UUID] = [],
        folders: [WorkspaceFolder] = [],
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
        userName: String = "yuminai",
        updateAvailable: Bool = false
    ) {
        self.workspaces = workspaces
        self._selectedId = selectedId
        self.telegramBoundId = telegramBoundId
        self.telegramAvailable = telegramAvailable
        self.pinnedWorkspaceIds = pinnedWorkspaceIds
        self.folders = folders
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

    // MARK: - Top header (collapse + search)

    private var topHeader: some View {
        HStack(spacing: 4) {
            IconButton("sidebar.left", help: "사이드바 접기 (⌘⌥1)", action: onCollapse)
            IconButton("magnifyingglass", help: "워크스페이스 검색 (⌘P)", action: onSearch)
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(height: Theme.Layout.toolbarHeight)
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

    // MARK: - Workspace list (ADR-076 — Pin + Folders + Uncategorized)

    /// 워크스페이스 ID로 빠른 lookup.
    private var workspacesById: [UUID: Workspace] {
        Dictionary(uniqueKeysWithValues: workspaces.map { ($0.id, $0) })
    }

    /// 폴더에 속한 모든 워크스페이스 ID set (uncategorized 계산용).
    private var foldersWorkspaceIds: Set<UUID> {
        Set(folders.flatMap { $0.workspaceIds })
    }

    /// 핀된 워크스페이스들 (pinnedWorkspaceIds 순서 유지).
    private var pinnedWorkspaces: [Workspace] {
        pinnedWorkspaceIds.compactMap { workspacesById[$0] }
    }

    /// 폴더에 속하지 않은 워크스페이스들 (핀 여부와 무관).
    private var uncategorizedWorkspaces: [Workspace] {
        workspaces.filter { !foldersWorkspaceIds.contains($0.id) }
    }

    /// 전체 워크스페이스 enumerate index (⌘1~9 단축키 매핑용).
    /// pinned + folders (expanded) + uncategorized 순서로.
    private func shortcutIndex(of workspaceId: UUID) -> Int? {
        // pin 그룹 먼저
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
                    // 1. Pin 그룹 (있을 때만)
                    if !pinnedWorkspaces.isEmpty {
                        pinSection
                    }
                    // 2. Folder 그룹들 (각 expand/collapse)
                    ForEach(folders) { folder in
                        folderSection(folder)
                    }
                    // 3. Uncategorized 그룹 (폴더에 안 든 워크스페이스 — 폴더가 있을 때만 헤더 표시)
                    if !uncategorizedWorkspaces.isEmpty {
                        uncategorizedSection
                    }
                    // 4. "새 폴더 만들기" (사이드바 하단)
                    newFolderButton
                }
            }
        }
    }

    // MARK: - Pin section (ADR-076 Phase 3)

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
                ForEach(pinnedWorkspaces) { workspace in
                    workspaceRow(workspace)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
        }
    }

    // MARK: - Folder section (ADR-076 Phase 3)

    @ViewBuilder
    private func folderSection(_ folder: WorkspaceFolder) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FolderHeaderRow(
                folder: folder,
                workspaceCount: folder.workspaceIds.count,
                onToggle: { onToggleFolderExpansion(folder.id) },
                onRename: { onRenameFolder(folder) },
                onDelete: { onDeleteFolder(folder) }
            )
            if folder.isExpanded {
                let folderWorkspaces = folder.workspaceIds.compactMap { workspacesById[$0] }
                if folderWorkspaces.isEmpty {
                    Text("(비어있음 — 워크스페이스를 우클릭해 이동)")
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

    // MARK: - Uncategorized section

    private var uncategorizedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 헤더는 폴더가 있을 때만 (폴더가 없으면 그냥 워크스페이스 리스트)
            if !folders.isEmpty {
                Text("기타 워크스페이스")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .padding(.horizontal, Theme.Layout.sidebarItemPadH + Theme.Spacing.sm)
                    .padding(.top, Theme.Layout.sidebarGroupHeaderTop)
                    .padding(.bottom, Theme.Spacing.sm)
            } else if pinnedWorkspaces.isEmpty {
                // 폴더도 핀도 없으면 기존 "워크스페이스" 헤더
                Text("워크스페이스")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .padding(.horizontal, Theme.Layout.sidebarItemPadH + Theme.Spacing.sm)
                    .padding(.top, Theme.Layout.sidebarGroupHeaderTop)
                    .padding(.bottom, Theme.Spacing.sm)
            } else {
                // 핀만 있고 폴더 없음 → "전체" 헤더
                Text("전체")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .padding(.horizontal, Theme.Layout.sidebarItemPadH + Theme.Spacing.sm)
                    .padding(.top, Theme.Layout.sidebarGroupHeaderTop)
                    .padding(.bottom, Theme.Spacing.sm)
            }
            VStack(spacing: 1) {
                ForEach(uncategorizedWorkspaces) { workspace in
                    workspaceRow(workspace)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
        }
    }

    // MARK: - "새 폴더 만들기" button

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
        .accessibilityHint("워크스페이스를 그룹화할 새 폴더를 생성합니다")
    }

    // MARK: - 공통 workspace row 생성

    @ViewBuilder
    private func workspaceRow(_ workspace: Workspace, indented: Bool = false) -> some View {
        WorkspaceItemRow(
            workspace: workspace,
            shortcutIndex: shortcutIndex(of: workspace.id),
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
            onCreateNewFolder: onCreateFolder
        )
    }
}

// MARK: - FolderHeaderRow (ADR-076 Phase 3)

/// 폴더 헤더 — chevron + folder icon + 이름 + 카운트.
struct FolderHeaderRow: View {
    let folder: WorkspaceFolder
    let workspaceCount: Int
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
                    .foregroundStyle(Theme.Color.accent)
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
            .background(hovering ? Theme.Color.surfaceHi.opacity(0.5) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.15), value: folder.isExpanded)
            .animation(.easeOut(duration: 0.10), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.top, Theme.Layout.sidebarGroupHeaderTop)
        .padding(.bottom, Theme.Spacing.xs)
        .contextMenu {
            Button("이름 바꾸기", systemImage: "pencil", action: onRename)
            Divider()
            Button("폴더 삭제 (안의 워크스페이스는 유지)", systemImage: "folder.badge.minus", role: .destructive, action: onDelete)
        }
        .accessibilityLabel("폴더 \(folder.name), \(workspaceCount)개 워크스페이스, \(folder.isExpanded ? "펼쳐짐" : "접힘")")
        .accessibilityHint("탭하여 펼치거나 접습니다")
    }
}

// MARK: - Sidebar item rows

/// "+ 새 워크스페이스" 같은 primary action.
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

/// Settings 같은 일반 menu (icon + label).
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

/// 그룹 헤더 ("Workspaces", "Pinned", "Recents" 등).
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

/// 워크스페이스 한 row.
struct WorkspaceItemRow: View {
    let workspace: Workspace
    /// **ADR-076** — 단축키 index (없으면 nil).
    let shortcutIndex: Int?
    let isSelected: Bool
    let isTelegramBound: Bool
    /// **ADR-076** — 핀 상태 표시.
    let isPinned: Bool
    let telegramAvailable: Bool
    /// **ADR-076** — 폴더 안 워크스페이스는 들여쓰기.
    let indented: Bool
    /// **ADR-076** — 폴더 이동 메뉴용.
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

    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Theme.Spacing.sm + 2) {
                // Selected dot — ● filled accent / ○ outline subtle
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

                // ADR-076 — 핀 indicator (작은 핀 아이콘)
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

                // ⌘1~9 단축키 hint (hover + 9개 이내일 때만)
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
            // ADR-076 Phase 4 — Pin 토글
            Button(
                isPinned ? "상단 고정 해제" : "상단에 고정",
                systemImage: isPinned ? "pin.slash" : "pin",
                action: onTogglePin
            )
            // ADR-076 Phase 4 — 폴더 이동
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
            // ADR-049 — ProjectProfile 편집
            Button("프로젝트 프로필 편집…",
                   systemImage: "rectangle.stack.fill",
                   action: onEditProjectProfile)
            Divider()
            Button("지우기", role: .destructive, action: onDelete)
        }
        .accessibilityLabel("\(workspace.name)\(isSelected ? ", 선택됨" : "")\(isPinned ? ", 고정됨" : "")\(isTelegramBound ? ", 텔레그램 연결됨" : "")")
        .accessibilityHint("이중 클릭으로 활성화. 우클릭으로 메뉴 열기.")
    }

    private var rowBg: SwiftUI.Color {
        if isSelected { return Theme.Color.elevated }
        if hovering { return Theme.Color.surfaceHi }
        return .clear
    }
}

/// 워크스페이스 0개일 때 사이드바 본문.
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

// MARK: - Update card

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

// MARK: - Bottom user card

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
