import SwiftUI
import AppKit
import YuminaiCore

/// 워크스페이스 파일 트리 + viewer/editor (ADR-037 D1+D2).
///
/// **레이아웃**: 좌측 ScrollView 트리 (300pt) | 우측 viewer/editor.
/// **단순화** (cost vs value):
/// - 1 file at a time (multi-tab은 v0.9+)
/// - syntax highlight X (raw monospace) — SwiftUI Code Editor 라이브러리 없음
/// - binary 파일은 트리에 표시는 되지만 viewer에 안 열림 (안내만)
public struct FilesPanel: View {
    public let tree: [FileNode]
    public let openTabs: [FileTab]
    public let activeTabId: UUID?
    public let selectedPath: String?
    public let fileContents: String?
    public let isEditing: Bool
    @Binding public var draft: String
    public let isDirty: Bool
    public let onSelect: (String) -> Void
    public let onSelectTab: (UUID) -> Void
    public let onCloseTab: (UUID) -> Void
    public let onStartEditing: () -> Void
    public let onSave: () -> Void
    public let onDiscardEdits: () -> Void
    public let onRefreshTree: () -> Void
    public let onOpenInExternalEditor: (String) -> Void
    public let onShowSearch: () -> Void
    /// 새 파일/폴더 생성 — parent path (root는 ""). ADR-039
    public let onRequestCreateFile: (String) -> Void
    public let onRequestCreateFolder: (String) -> Void
    /// 이름 변경 sheet — 대상 path + isFolder. ADR-039
    public let onRequestRename: (String, Bool) -> Void
    /// 삭제 — 대상 path + isFolder. ADR-039
    public let onRequestDelete: (String, Bool) -> Void
    /// 다중 선택 (Cmd+Click). ADR-040
    public let selectedPaths: Set<String>
    public let onToggleSelection: (String) -> Void
    public let onClearSelection: () -> Void
    public let onBulkDelete: () -> Void
    /// inline rename mode (트리 cell 내 TextField). ADR-040
    public let inlineRenamePath: String?
    public let onBeginInlineRename: (String) -> Void
    public let onCommitInlineRename: (String, String) -> Void
    public let onCancelInlineRename: () -> Void
    /// rename 후 agent에게 imports 업데이트 위임 (ADR-040 F5).
    public let onAskAgentToUpdateImports: (String, String) -> Void
    /// 파일 drag-drop 이동 (ADR-041 F7) — (oldPath, newPath).
    public let onMoveFile: (String, String) -> Void

    public init(
        tree: [FileNode],
        openTabs: [FileTab] = [],
        activeTabId: UUID? = nil,
        selectedPath: String?,
        fileContents: String?,
        isEditing: Bool,
        draft: Binding<String>,
        isDirty: Bool,
        onSelect: @escaping (String) -> Void,
        onSelectTab: @escaping (UUID) -> Void = { _ in },
        onCloseTab: @escaping (UUID) -> Void = { _ in },
        onStartEditing: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onDiscardEdits: @escaping () -> Void,
        onRefreshTree: @escaping () -> Void,
        onOpenInExternalEditor: @escaping (String) -> Void,
        onShowSearch: @escaping () -> Void = {},
        onRequestCreateFile: @escaping (String) -> Void = { _ in },
        onRequestCreateFolder: @escaping (String) -> Void = { _ in },
        onRequestRename: @escaping (String, Bool) -> Void = { _, _ in },
        onRequestDelete: @escaping (String, Bool) -> Void = { _, _ in },
        selectedPaths: Set<String> = [],
        onToggleSelection: @escaping (String) -> Void = { _ in },
        onClearSelection: @escaping () -> Void = {},
        onBulkDelete: @escaping () -> Void = {},
        inlineRenamePath: String? = nil,
        onBeginInlineRename: @escaping (String) -> Void = { _ in },
        onCommitInlineRename: @escaping (String, String) -> Void = { _, _ in },
        onCancelInlineRename: @escaping () -> Void = {},
        onAskAgentToUpdateImports: @escaping (String, String) -> Void = { _, _ in },
        onMoveFile: @escaping (String, String) -> Void = { _, _ in }
    ) {
        self.tree = tree
        self.openTabs = openTabs
        self.activeTabId = activeTabId
        self.selectedPath = selectedPath
        self.fileContents = fileContents
        self.isEditing = isEditing
        self._draft = draft
        self.isDirty = isDirty
        self.onSelect = onSelect
        self.onSelectTab = onSelectTab
        self.onCloseTab = onCloseTab
        self.onStartEditing = onStartEditing
        self.onSave = onSave
        self.onDiscardEdits = onDiscardEdits
        self.onRefreshTree = onRefreshTree
        self.onOpenInExternalEditor = onOpenInExternalEditor
        self.onShowSearch = onShowSearch
        self.onRequestCreateFile = onRequestCreateFile
        self.onRequestCreateFolder = onRequestCreateFolder
        self.onRequestRename = onRequestRename
        self.onRequestDelete = onRequestDelete
        self.selectedPaths = selectedPaths
        self.onToggleSelection = onToggleSelection
        self.onClearSelection = onClearSelection
        self.onBulkDelete = onBulkDelete
        self.inlineRenamePath = inlineRenamePath
        self.onBeginInlineRename = onBeginInlineRename
        self.onCommitInlineRename = onCommitInlineRename
        self.onCancelInlineRename = onCancelInlineRename
        self.onAskAgentToUpdateImports = onAskAgentToUpdateImports
        self.onMoveFile = onMoveFile
    }

    public var body: some View {
        VSplitView {
            treeSection
                .frame(minHeight: 160, idealHeight: 240)
            VStack(spacing: 0) {
                if !openTabs.isEmpty {
                    fileTabBar
                    FlatHDivider()
                }
                viewerSection
            }
            .frame(minHeight: 200)
        }
    }

    @ViewBuilder
    private var fileTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 1) {
                ForEach(openTabs) { tab in
                    FileTabButton(
                        tab: tab,
                        isActive: tab.id == activeTabId,
                        onSelect: { onSelectTab(tab.id) },
                        onClose: { onCloseTab(tab.id) }
                    )
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 2)
        }
        .background(Theme.Color.surface)
    }

    // MARK: - Tree section

    private var treeSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Color.accent)
                Text("파일")
                    .font(Theme.Typography.small.weight(.medium))
                    .foregroundStyle(Theme.Color.text)
                HelpHint(
                    "워크스페이스 디렉토리의 파일 트리예요. .git/.build/node_modules 같은 자동 제외 폴더는 안 보여요.\n\n• 파일 클릭 → 새 tab으로 열림 (max 10)\n• ⌘P 파일 빠른 검색\n• ⌘+클릭 다중 선택 → 일괄 휴지통\n• 파일을 폴더 위로 drag-drop으로 이동\n• 우클릭 → 새 파일/이름 변경/삭제\n• ⌫ 키로 휴지통, ↩︎ 로 열기",
                    title: "파일 트리",
                    placement: .bottom
                )
                Spacer()
                if !selectedPaths.isEmpty {
                    Text("\(selectedPaths.count)개 선택")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.accent)
                    Button(action: onClearSelection) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("선택 해제")
                    Button(action: onBulkDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundStyle(.red.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .help("선택 항목 일괄 휴지통으로 이동 (⌫)")
                }
                Button(action: { onRequestCreateFile("") }) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .buttonStyle(.plain)
                .help("새 파일 (root)")
                Button(action: { onRequestCreateFolder("") }) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .buttonStyle(.plain)
                .help("새 폴더 (root)")
                Button(action: onShowSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .buttonStyle(.plain)
                .help("파일 검색 (⌘P)")
                Button(action: onRefreshTree) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .buttonStyle(.plain)
                .help("트리 새로고침")
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Theme.Color.surface)
            .overlay(alignment: .bottom) { FlatHDivider() }

            if tree.isEmpty {
                EmptyStateHint(
                    icon: "folder",
                    title: "파일이 없어요",
                    message: "워크스페이스에 파일이 없거나 모두 자동 제외 폴더 (.git, .build, node_modules 등) 안에 있어요."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(tree) { node in
                            FileNodeRow(
                                node: node,
                                depth: 0,
                                selectedPath: selectedPath,
                                onSelect: onSelect,
                                onCreateFile: onRequestCreateFile,
                                onCreateFolder: onRequestCreateFolder,
                                onRename: onRequestRename,
                                onDelete: onRequestDelete,
                                multiSelectedPaths: selectedPaths,
                                onToggleMultiSelect: onToggleSelection,
                                inlineRenamePath: inlineRenamePath,
                                onBeginInlineRename: onBeginInlineRename,
                                onCommitInlineRename: onCommitInlineRename,
                                onCancelInlineRename: onCancelInlineRename,
                                onMoveFile: onMoveFile
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Viewer/editor section

    @ViewBuilder
    private var viewerSection: some View {
        if let path = selectedPath {
            VStack(spacing: 0) {
                viewerHeader(path: path)
                FlatHDivider()
                if let node = findNode(path: path), node.isBinary {
                    binaryFileNotice(path: path)
                } else if isEditing {
                    inlineEditor
                } else {
                    fileViewer
                }
            }
        } else {
            EmptyStateHint(
                icon: "doc.text",
                title: "파일을 선택하세요",
                message: "위 트리에서 파일을 클릭하면 본문이 여기 표시돼요."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func viewerHeader(path: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Color.textSecondary)
            Text(path)
                .font(Theme.Typography.monoSmall)
                .foregroundStyle(Theme.Color.text)
                .lineLimit(1)
                .truncationMode(.middle)
            if isDirty {
                Circle()
                    .fill(Theme.Color.accent)
                    .frame(width: 5, height: 5)
                    .help("저장 안 된 변경 있음")
            }
            Spacer()
            if isEditing {
                Button(action: onDiscardEdits) {
                    Text("취소")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .buttonStyle(.plain)
                Button(action: onSave) {
                    Text("저장")
                        .font(Theme.Typography.small.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(isDirty ? Theme.Color.accent : Theme.Color.surfaceHi)
                        .foregroundStyle(isDirty ? .white : Theme.Color.textTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!isDirty)
            } else {
                Button(action: { onOpenInExternalEditor(path) }) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .buttonStyle(.plain)
                .help("외부 IDE에서 열기")
                Button(action: onStartEditing) {
                    Text("편집")
                        .font(Theme.Typography.small)
                }
                .buttonStyle(.plain)
                .help("inline 편집 모드 (raw text)")
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Color.surface)
    }

    private var fileViewer: some View {
        let ext = (selectedPath as NSString?)?.pathExtension ?? ""
        let lang = CodeViewer.languageHint(for: ext)
        return CodeViewer(
            code: fileContents ?? "(읽는 중...)",
            language: lang
        )
    }

    private var inlineEditor: some View {
        TextEditor(text: $draft)
            .font(Theme.Typography.mono)
            .scrollContentBackground(.hidden)
            .background(Theme.Color.bg)
            .padding(Theme.Spacing.sm)
    }

    private func binaryFileNotice(path: String) -> some View {
        EmptyStateHint(
            icon: "doc.questionmark",
            title: "binary 파일이라 표시할 수 없어요",
            message: "이미지/오디오/실행 파일 등은 미리보기 X. ‘외부 IDE에서 열기’로 system default 앱으로 열 수 있어요.",
            action: .init(label: "외부 IDE에서 열기", perform: { onOpenInExternalEditor(path) })
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func findNode(path: String) -> FileNode? {
        Self.findNode(in: tree, path: path)
    }

    private static func findNode(in nodes: [FileNode], path: String) -> FileNode? {
        for node in nodes {
            if node.path == path { return node }
            if case .folder(_, _, let children) = node {
                if let found = findNode(in: children, path: path) { return found }
            }
        }
        return nil
    }
}

// MARK: - Tree row (recursive)

// MARK: - File tab button (multi-tab, ADR-038 E2)

private struct FileTabButton: View {
    let tab: FileTab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 4) {
                Text(tab.displayName)
                    .font(Theme.Typography.small)
                    .foregroundStyle(isActive ? Theme.Color.text : Theme.Color.textSecondary)
                    .lineLimit(1)
                if tab.isDirty {
                    Circle()
                        .fill(Theme.Color.accent)
                        .frame(width: 5, height: 5)
                }
                if hovering || isActive {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Theme.Color.textSecondary)
                            .frame(width: 12, height: 12)
                            .background(Theme.Color.surfaceHi)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 3)
            .background(rowBg)
            .overlay(alignment: .bottom) {
                if isActive {
                    Rectangle().fill(Theme.Color.accent).frame(height: 2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tab.path)
    }

    private var rowBg: SwiftUI.Color {
        if isActive { return Theme.Color.bg }
        if hovering { return Theme.Color.surfaceHi }
        return .clear
    }
}

private struct FileNodeRow: View {
    let node: FileNode
    let depth: Int
    let selectedPath: String?
    let onSelect: (String) -> Void
    let onCreateFile: (String) -> Void
    let onCreateFolder: (String) -> Void
    let onRename: (String, Bool) -> Void
    let onDelete: (String, Bool) -> Void
    let multiSelectedPaths: Set<String>
    let onToggleMultiSelect: (String) -> Void
    let inlineRenamePath: String?
    let onBeginInlineRename: (String) -> Void
    let onCommitInlineRename: (String, String) -> Void
    let onCancelInlineRename: () -> Void
    let onMoveFile: (String, String) -> Void

    @State private var expanded: Bool

    init(
        node: FileNode,
        depth: Int,
        selectedPath: String?,
        onSelect: @escaping (String) -> Void,
        onCreateFile: @escaping (String) -> Void = { _ in },
        onCreateFolder: @escaping (String) -> Void = { _ in },
        onRename: @escaping (String, Bool) -> Void = { _, _ in },
        onDelete: @escaping (String, Bool) -> Void = { _, _ in },
        multiSelectedPaths: Set<String> = [],
        onToggleMultiSelect: @escaping (String) -> Void = { _ in },
        inlineRenamePath: String? = nil,
        onBeginInlineRename: @escaping (String) -> Void = { _ in },
        onCommitInlineRename: @escaping (String, String) -> Void = { _, _ in },
        onCancelInlineRename: @escaping () -> Void = {},
        onMoveFile: @escaping (String, String) -> Void = { _, _ in }
    ) {
        self.node = node
        self.depth = depth
        self.selectedPath = selectedPath
        self.onSelect = onSelect
        self.onCreateFile = onCreateFile
        self.onCreateFolder = onCreateFolder
        self.onRename = onRename
        self.onDelete = onDelete
        self.multiSelectedPaths = multiSelectedPaths
        self.onToggleMultiSelect = onToggleMultiSelect
        self.inlineRenamePath = inlineRenamePath
        self.onBeginInlineRename = onBeginInlineRename
        self.onCommitInlineRename = onCommitInlineRename
        self.onCancelInlineRename = onCancelInlineRename
        self.onMoveFile = onMoveFile
        // depth 0-1 자동 펼침
        self._expanded = State(initialValue: depth < 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row
            if expanded, case .folder(_, _, let children) = node {
                ForEach(children) { child in
                    FileNodeRow(
                        node: child,
                        depth: depth + 1,
                        selectedPath: selectedPath,
                        onSelect: onSelect,
                        onCreateFile: onCreateFile,
                        onCreateFolder: onCreateFolder,
                        onRename: onRename,
                        onDelete: onDelete,
                        multiSelectedPaths: multiSelectedPaths,
                        onToggleMultiSelect: onToggleMultiSelect,
                        inlineRenamePath: inlineRenamePath,
                        onBeginInlineRename: onBeginInlineRename,
                        onCommitInlineRename: onCommitInlineRename,
                        onCancelInlineRename: onCancelInlineRename,
                        onMoveFile: onMoveFile
                    )
                }
            }
        }
    }

    @State private var hovering = false
    /// ADR-042 R1.C4 — drag-drop hover 시 폴더 row highlight (drop 가능 여부 가시화)
    @State private var isDropTarget = false

    private var isInlineRenaming: Bool {
        inlineRenamePath == node.path
    }

    private var row: some View {
        let core = HStack(spacing: 4) {
            Spacer().frame(width: CGFloat(depth) * 12)
            if case .folder = node {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Theme.Color.textTertiary)
                    .frame(width: 10)
            } else {
                Spacer().frame(width: 10)
            }
            Image(systemName: iconName)
                .font(.system(size: 11))
                .foregroundStyle(iconColor)
                .frame(width: 14)
            if isInlineRenaming {
                InlineRenameField(
                    initial: node.name,
                    onSubmit: { newName in onCommitInlineRename(node.path, newName) },
                    onCancel: onCancelInlineRename
                )
            } else {
                Text(node.name)
                    .font(Theme.Typography.small)
                    .foregroundStyle(isSelected ? Theme.Color.text : Theme.Color.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if isMultiSelected && !isInlineRenaming {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Color.accent)
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 2)
        .background(rowBg)
        .contentShape(Rectangle())
        .onTapGesture { tap() }
        .onHover { hovering = $0 }
        .contextMenu { contextMenuContent }
        // ADR-042 R1.C2 — F2 placeholder 제거 (동작 안 했음. v1.3+ NSEvent monitor 검토)
        // Delete = 휴지통 / Enter = select-or-toggle
        .focusable(!isInlineRenaming)
        .focusEffectDisabled()
        .onKeyPress(.delete) { @MainActor in
            onDelete(node.path, node.isFolder)
            return .handled
        }
        .onKeyPress(.deleteForward) { @MainActor in
            onDelete(node.path, node.isFolder)
            return .handled
        }
        .onKeyPress(keys: [.return]) { _ in
            tap()
            return .handled
        }
        // Drag-drop file move (F7) — 파일을 폴더에 drop하면 해당 폴더로 이동
        // ADR-042 R1.C4 — isTargeted Binding으로 hover 시 row highlight (drop 가능 여부 시각 피드백)
        return Group {
            if node.isFolder {
                core.dropDestination(for: String.self) { paths, _ in
                    handleDropPaths(paths)
                    return !paths.isEmpty
                } isTargeted: { targeted in
                    isDropTarget = targeted
                }
            } else {
                core.draggable(node.path) {
                    HStack(spacing: 4) {
                        Image(systemName: iconName)
                            .foregroundStyle(iconColor)
                        Text(node.name)
                            .font(Theme.Typography.small)
                    }
                    .padding(4)
                    .background(Theme.Color.surfaceHi)
                }
            }
        }
    }

    private func handleDropPaths(_ paths: [String]) {
        // 폴더 자기 자신에게 drop 또는 빈 배열은 무시
        guard case .folder(_, let folderPath, _) = node else { return }
        for path in paths {
            // 이미 같은 폴더에 있는지 검사
            let parentOfDragged = (path as NSString).deletingLastPathComponent
            guard parentOfDragged != folderPath else { continue }
            let fileName = (path as NSString).lastPathComponent
            let newPath = folderPath.isEmpty ? fileName : "\(folderPath)/\(fileName)"
            onMoveFile(path, newPath)
        }
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        if node.isFolder {
            Button {
                onCreateFile(node.path)
            } label: {
                Label("새 파일", systemImage: "doc.badge.plus")
            }
            Button {
                onCreateFolder(node.path)
            } label: {
                Label("새 폴더", systemImage: "folder.badge.plus")
            }
            Divider()
        }
        // ADR-042 R1.C3 — rename 단일화. inline이 default (빠른 in-place 편집).
        // sheet 변형이 필요한 power-user는 Option+Click으로 호출 가능.
        Button {
            onBeginInlineRename(node.path)
        } label: {
            Label("이름 변경", systemImage: "pencil")
        }
        Divider()
        Button {
            onToggleMultiSelect(node.path)
        } label: {
            Label(
                isMultiSelected ? "선택 해제" : "선택에 추가",
                systemImage: isMultiSelected ? "checkmark.circle.fill" : "circle"
            )
        }
        Divider()
        Button(role: .destructive) {
            onDelete(node.path, node.isFolder)
        } label: {
            Label("휴지통으로 이동", systemImage: "trash")
        }
    }

    private var isMultiSelected: Bool {
        multiSelectedPaths.contains(node.path)
    }

    private var iconName: String {
        switch node {
        case .folder: return expanded ? "folder.fill" : "folder"
        case .file(_, _, let ext, _, let isBinary):
            if isBinary { return "doc.questionmark" }
            switch ext {
            case "swift": return "swift"
            case "md", "markdown": return "doc.text"
            case "json": return "curlybraces"
            case "ts", "tsx", "js", "jsx", "mjs": return "chevron.left.forwardslash.chevron.right"
            case "py": return "circle.hexagongrid"
            case "rs": return "gearshape"
            case "go": return "arrow.right.circle"
            case "yml", "yaml", "toml": return "list.bullet.rectangle"
            case "sh", "zsh", "bash": return "terminal"
            default: return "doc"
            }
        }
    }

    private var iconColor: SwiftUI.Color {
        switch node {
        case .folder: return Theme.Color.accent
        case .file(_, _, _, _, let isBinary):
            return isBinary ? Theme.Color.textTertiary : Theme.Color.textSecondary
        }
    }

    private var isSelected: Bool {
        if case .file = node { return selectedPath == node.path }
        return false
    }

    private var rowBg: SwiftUI.Color {
        // ADR-042 R1.C4 — drop target hover (가장 강한 시각 신호 — drop 액션 임박)
        if isDropTarget { return Theme.Color.accent.opacity(0.35) }
        if isMultiSelected { return Theme.Color.accent.opacity(0.18) }
        if isSelected { return Theme.Color.accentMuted }
        if hovering { return Theme.Color.surfaceHi }
        return .clear
    }

    private func tap() {
        // ⌘ pressed → 다중 선택 토글 (ADR-040 F3)
        if NSEvent.modifierFlags.contains(.command) {
            onToggleMultiSelect(node.path)
            return
        }
        switch node {
        case .folder:
            withAnimation(.easeOut(duration: 0.10)) { expanded.toggle() }
        case .file(_, let path, _, _, _):
            onSelect(path)
        }
    }
}

/// 트리 cell 내 inline rename TextField — Esc cancel, Enter commit (ADR-040 F4).
private struct InlineRenameField: View {
    let initial: String
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(Theme.Typography.small)
            .foregroundStyle(Theme.Color.text)
            .padding(.vertical, 1)
            .padding(.horizontal, 4)
            .background(Theme.Color.bg)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Theme.Color.accent, lineWidth: 1)
            )
            .focused($focused)
            .onAppear {
                text = initial
                focused = true
            }
            .onSubmit { onSubmit(text) }
            .onExitCommand { onCancel() }
    }
}
