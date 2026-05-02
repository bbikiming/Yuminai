import SwiftUI
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
    /// 이름 변경 — 대상 path + isFolder. ADR-039
    public let onRequestRename: (String, Bool) -> Void
    /// 삭제 — 대상 path + isFolder. ADR-039
    public let onRequestDelete: (String, Bool) -> Void

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
        onRequestDelete: @escaping (String, Bool) -> Void = { _, _ in }
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
                    "워크스페이스 디렉토리의 파일 트리예요. .git/.build/node_modules 같은 자동 제외 폴더는 안 보여요. 파일 클릭 → 새 tab으로 열림. 여러 파일 동시 열기 가능 (max 10), ⌘P로 빠른 검색.",
                    title: "파일 트리",
                    placement: .bottom
                )
                Spacer()
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
                                onDelete: onRequestDelete
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
            action: .init(label: "외부에서 열기", perform: { onOpenInExternalEditor(path) })
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

    @State private var expanded: Bool

    init(
        node: FileNode,
        depth: Int,
        selectedPath: String?,
        onSelect: @escaping (String) -> Void,
        onCreateFile: @escaping (String) -> Void = { _ in },
        onCreateFolder: @escaping (String) -> Void = { _ in },
        onRename: @escaping (String, Bool) -> Void = { _, _ in },
        onDelete: @escaping (String, Bool) -> Void = { _, _ in }
    ) {
        self.node = node
        self.depth = depth
        self.selectedPath = selectedPath
        self.onSelect = onSelect
        self.onCreateFile = onCreateFile
        self.onCreateFolder = onCreateFolder
        self.onRename = onRename
        self.onDelete = onDelete
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
                        onDelete: onDelete
                    )
                }
            }
        }
    }

    @State private var hovering = false

    private var row: some View {
        Button(action: tap) {
            HStack(spacing: 4) {
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
                Text(node.name)
                    .font(Theme.Typography.small)
                    .foregroundStyle(isSelected ? Theme.Color.text : Theme.Color.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 2)
            .background(rowBg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu { contextMenuContent }
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
        Button {
            onRename(node.path, node.isFolder)
        } label: {
            Label("이름 변경", systemImage: "pencil")
        }
        Button(role: .destructive) {
            onDelete(node.path, node.isFolder)
        } label: {
            Label("삭제", systemImage: "trash")
        }
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
        if isSelected { return Theme.Color.accentMuted }
        if hovering { return Theme.Color.surfaceHi }
        return .clear
    }

    private func tap() {
        switch node {
        case .folder:
            withAnimation(.easeOut(duration: 0.10)) { expanded.toggle() }
        case .file(_, let path, _, _, _):
            onSelect(path)
        }
    }
}
