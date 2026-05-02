import SwiftUI
import YuminaiCore
import YuminaiObsidian

/// 우측 inspector — Tab (컨텍스트 | 노트) + 콘텐츠 + 편집 + favorites + recents.
public struct InspectorPanel: View {
    @Binding public var tab: InspectorTab
    public let usage: UsageStats
    public let activeSettings: SessionSettings
    public let workspacePath: String?
    public let recentTools: [String]

    // Notes
    public let vaultConfigured: Bool
    public let vaultRoot: URL?
    public let vaultTree: [VaultNode]
    @Binding public var noteSearchQuery: String
    @Binding public var fullTextEnabled: Bool
    public let fullTextHits: [SearchHit]
    public let selectedNote: Note?

    // Editing
    public let isEditing: Bool
    @Binding public var editingDraft: String
    public let isDirty: Bool
    public let externalChangeDetected: Bool
    @Binding public var splitMode: EditorSplitMode

    // C2/C3
    public let favoriteNotePaths: Set<String>
    public let recentNotePaths: [String]
    public let onToggleFavorite: (String) -> Void

    // B5
    public let onCreateNote: () -> Void
    public let onDeleteNote: (String) -> Void

    // wiki resolver (B3)
    public let noteResolver: ((String) -> String?)?

    public let onSelectNote: (String) -> Void
    public let onClearSelectedNote: () -> Void
    public let onOpenInObsidian: () -> Void
    public let onOpenSettings: () -> Void
    public let onWikiLink: (String) -> Void
    public let onStartEditing: () -> Void
    public let onSave: () -> Void
    public let onDiscardEdits: () -> Void
    public let onReloadNote: () -> Void

    // Files panel (ADR-037 D1+D2 + ADR-038 E2 multi-tab)
    public let workspaceFileTree: [FileNode]
    public let openFileTabs: [FileTab]
    public let activeFileTabId: UUID?
    public let selectedFilePath: String?
    public let selectedFileContents: String?
    public let isEditingFile: Bool
    @Binding public var fileDraft: String
    public let isFileDirty: Bool
    public let onSelectFile: (String) -> Void
    public let onSelectFileTab: (UUID) -> Void
    public let onCloseFileTab: (UUID) -> Void
    public let onStartEditingFile: () -> Void
    public let onSaveFile: () -> Void
    public let onDiscardFileEdits: () -> Void
    public let onRefreshFileTree: () -> Void
    public let onOpenFileInExternalEditor: (String) -> Void
    public let onShowFileSearch: () -> Void
    public let onRequestCreateFile: (String) -> Void
    public let onRequestCreateFolder: (String) -> Void
    public let onRequestRename: (String, Bool) -> Void
    public let onRequestDelete: (String, Bool) -> Void

    // Diff review (ADR-027 phase A3)
    public let pendingChanges: [ChangedFile]
    public let pendingDiff: String
    public let onAcceptAllChanges: () -> Void
    public let onRejectAllChanges: () -> Void
    public let onRejectChange: (ChangedFile) -> Void
    public let onOpenChangeInEditor: (ChangedFile) -> Void
    public let readChangedFile: ((ChangedFile) -> String?)?
    public let onSaveChangedFile: ((ChangedFile, String) -> Void)?

    // Delivery loop (ADR-029 phase B)
    public let deliveryResults: [DeliveryResult]
    public let isDeliveryRunning: Bool
    public let deliveryConfig: DeliveryConfig
    public let onRunBuild: () -> Void
    public let onRunTest: () -> Void
    public let onRunLint: () -> Void
    public let onClearDelivery: () -> Void
    public let onConfigureDelivery: () -> Void

    public init(
        tab: Binding<InspectorTab>,
        usage: UsageStats,
        activeSettings: SessionSettings,
        workspacePath: String?,
        recentTools: [String] = [],
        vaultConfigured: Bool,
        vaultRoot: URL?,
        vaultTree: [VaultNode],
        noteSearchQuery: Binding<String>,
        fullTextEnabled: Binding<Bool>,
        fullTextHits: [SearchHit],
        selectedNote: Note?,
        isEditing: Bool,
        editingDraft: Binding<String>,
        isDirty: Bool,
        externalChangeDetected: Bool,
        splitMode: Binding<EditorSplitMode> = .constant(.editor),
        favoriteNotePaths: Set<String> = [],
        recentNotePaths: [String] = [],
        onToggleFavorite: @escaping (String) -> Void = { _ in },
        onCreateNote: @escaping () -> Void = {},
        onDeleteNote: @escaping (String) -> Void = { _ in },
        noteResolver: ((String) -> String?)? = nil,
        onSelectNote: @escaping (String) -> Void,
        onClearSelectedNote: @escaping () -> Void,
        onOpenInObsidian: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onWikiLink: @escaping (String) -> Void = { _ in },
        onStartEditing: @escaping () -> Void = {},
        onSave: @escaping () -> Void = {},
        onDiscardEdits: @escaping () -> Void = {},
        onReloadNote: @escaping () -> Void = {},
        pendingChanges: [ChangedFile] = [],
        pendingDiff: String = "",
        onAcceptAllChanges: @escaping () -> Void = {},
        onRejectAllChanges: @escaping () -> Void = {},
        onRejectChange: @escaping (ChangedFile) -> Void = { _ in },
        onOpenChangeInEditor: @escaping (ChangedFile) -> Void = { _ in },
        readChangedFile: ((ChangedFile) -> String?)? = nil,
        onSaveChangedFile: ((ChangedFile, String) -> Void)? = nil,
        deliveryResults: [DeliveryResult] = [],
        isDeliveryRunning: Bool = false,
        deliveryConfig: DeliveryConfig = .disabled,
        onRunBuild: @escaping () -> Void = {},
        onRunTest: @escaping () -> Void = {},
        onRunLint: @escaping () -> Void = {},
        onClearDelivery: @escaping () -> Void = {},
        onConfigureDelivery: @escaping () -> Void = {},
        workspaceFileTree: [FileNode] = [],
        openFileTabs: [FileTab] = [],
        activeFileTabId: UUID? = nil,
        selectedFilePath: String? = nil,
        selectedFileContents: String? = nil,
        isEditingFile: Bool = false,
        fileDraft: Binding<String> = .constant(""),
        isFileDirty: Bool = false,
        onSelectFile: @escaping (String) -> Void = { _ in },
        onSelectFileTab: @escaping (UUID) -> Void = { _ in },
        onCloseFileTab: @escaping (UUID) -> Void = { _ in },
        onStartEditingFile: @escaping () -> Void = {},
        onSaveFile: @escaping () -> Void = {},
        onDiscardFileEdits: @escaping () -> Void = {},
        onRefreshFileTree: @escaping () -> Void = {},
        onOpenFileInExternalEditor: @escaping (String) -> Void = { _ in },
        onShowFileSearch: @escaping () -> Void = {},
        onRequestCreateFile: @escaping (String) -> Void = { _ in },
        onRequestCreateFolder: @escaping (String) -> Void = { _ in },
        onRequestRename: @escaping (String, Bool) -> Void = { _, _ in },
        onRequestDelete: @escaping (String, Bool) -> Void = { _, _ in }
    ) {
        self._tab = tab
        self.usage = usage
        self.activeSettings = activeSettings
        self.workspacePath = workspacePath
        self.recentTools = recentTools
        self.vaultConfigured = vaultConfigured
        self.vaultRoot = vaultRoot
        self.vaultTree = vaultTree
        self._noteSearchQuery = noteSearchQuery
        self._fullTextEnabled = fullTextEnabled
        self.fullTextHits = fullTextHits
        self.selectedNote = selectedNote
        self.isEditing = isEditing
        self._editingDraft = editingDraft
        self.isDirty = isDirty
        self.externalChangeDetected = externalChangeDetected
        self._splitMode = splitMode
        self.favoriteNotePaths = favoriteNotePaths
        self.recentNotePaths = recentNotePaths
        self.onToggleFavorite = onToggleFavorite
        self.onCreateNote = onCreateNote
        self.onDeleteNote = onDeleteNote
        self.noteResolver = noteResolver
        self.onSelectNote = onSelectNote
        self.onClearSelectedNote = onClearSelectedNote
        self.onOpenInObsidian = onOpenInObsidian
        self.onOpenSettings = onOpenSettings
        self.onWikiLink = onWikiLink
        self.onStartEditing = onStartEditing
        self.onSave = onSave
        self.onDiscardEdits = onDiscardEdits
        self.onReloadNote = onReloadNote
        self.pendingChanges = pendingChanges
        self.pendingDiff = pendingDiff
        self.onAcceptAllChanges = onAcceptAllChanges
        self.onRejectAllChanges = onRejectAllChanges
        self.onRejectChange = onRejectChange
        self.onOpenChangeInEditor = onOpenChangeInEditor
        self.readChangedFile = readChangedFile
        self.onSaveChangedFile = onSaveChangedFile
        self.deliveryResults = deliveryResults
        self.isDeliveryRunning = isDeliveryRunning
        self.deliveryConfig = deliveryConfig
        self.onRunBuild = onRunBuild
        self.onRunTest = onRunTest
        self.onRunLint = onRunLint
        self.onClearDelivery = onClearDelivery
        self.onConfigureDelivery = onConfigureDelivery
        self.workspaceFileTree = workspaceFileTree
        self.openFileTabs = openFileTabs
        self.activeFileTabId = activeFileTabId
        self.selectedFilePath = selectedFilePath
        self.selectedFileContents = selectedFileContents
        self.isEditingFile = isEditingFile
        self._fileDraft = fileDraft
        self.isFileDirty = isFileDirty
        self.onSelectFile = onSelectFile
        self.onSelectFileTab = onSelectFileTab
        self.onCloseFileTab = onCloseFileTab
        self.onStartEditingFile = onStartEditingFile
        self.onSaveFile = onSaveFile
        self.onDiscardFileEdits = onDiscardFileEdits
        self.onRefreshFileTree = onRefreshFileTree
        self.onOpenFileInExternalEditor = onOpenFileInExternalEditor
        self.onShowFileSearch = onShowFileSearch
        self.onRequestCreateFile = onRequestCreateFile
        self.onRequestCreateFolder = onRequestCreateFolder
        self.onRequestRename = onRequestRename
        self.onRequestDelete = onRequestDelete
    }

    public var body: some View {
        VStack(spacing: 0) {
            tabBar
            FlatHDivider()
            content
        }
        .frame(width: Theme.Layout.inspectorWidth)
        .background(Theme.Color.bg)
        .overlay(alignment: .leading) { FlatVDivider() }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(InspectorTab.allCases, id: \.self) { item in
                tabButton(item)
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 6)
    }

    private func tabButton(_ item: InspectorTab) -> some View {
        let isActive = tab == item
        return Button(action: { tab = item }) {
            HStack(spacing: 5) {
                Image(systemName: item.icon)
                    .font(.system(size: 11, weight: .medium))
                Text(item.label)
                    .font(Theme.Typography.label)
            }
            .foregroundStyle(isActive ? Theme.Color.text : Theme.Color.textSecondary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 5)
            .background(isActive ? Theme.Color.surfaceHi : .clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .overlay(alignment: .bottom) {
                if isActive {
                    Rectangle()
                        .fill(Theme.Color.accent)
                        .frame(height: 2)
                        .offset(y: 6)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .context:
            ContextInspector(
                usage: usage,
                activeSettings: activeSettings,
                workspacePath: workspacePath,
                recentTools: recentTools
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .notes:
            notesContent
        case .files:
            FilesPanel(
                tree: workspaceFileTree,
                openTabs: openFileTabs,
                activeTabId: activeFileTabId,
                selectedPath: selectedFilePath,
                fileContents: selectedFileContents,
                isEditing: isEditingFile,
                draft: $fileDraft,
                isDirty: isFileDirty,
                onSelect: onSelectFile,
                onSelectTab: onSelectFileTab,
                onCloseTab: onCloseFileTab,
                onStartEditing: onStartEditingFile,
                onSave: onSaveFile,
                onDiscardEdits: onDiscardFileEdits,
                onRefreshTree: onRefreshFileTree,
                onOpenInExternalEditor: onOpenFileInExternalEditor,
                onShowSearch: onShowFileSearch,
                onRequestCreateFile: onRequestCreateFile,
                onRequestCreateFolder: onRequestCreateFolder,
                onRequestRename: onRequestRename,
                onRequestDelete: onRequestDelete
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .changes:
            VSplitView {
                DiffReviewView(
                    changes: pendingChanges,
                    unifiedDiff: pendingDiff,
                    onAcceptAll: onAcceptAllChanges,
                    onRejectAll: onRejectAllChanges,
                    onRejectFile: onRejectChange,
                    onOpenInEditor: onOpenChangeInEditor,
                    readFileContents: readChangedFile,
                    onSaveFileContents: onSaveChangedFile
                )
                .frame(minHeight: 200)

                DeliveryResultsView(
                    results: deliveryResults,
                    isRunning: isDeliveryRunning,
                    config: deliveryConfig,
                    onRunBuild: onRunBuild,
                    onRunTest: onRunTest,
                    onRunLint: onRunLint,
                    onClear: onClearDelivery,
                    onConfigure: onConfigureDelivery
                )
                .frame(minHeight: 160, idealHeight: 240)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var notesContent: some View {
        if !vaultConfigured {
            EmptyVaultView(onOpenSettings: onOpenSettings)
        } else if let note = selectedNote {
            VStack(spacing: 0) {
                noteHeader(note)
                FlatHDivider().opacity(0.5)
                if externalChangeDetected {
                    externalChangeBanner
                }
                if isEditing {
                    splitEditor(note: note)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            NoteHeaderView(note: note)
                            MarkdownViewer(
                                markdown: note.body,
                                vaultRoot: vaultRoot,
                                noteResolver: noteResolver,
                                onWikiLink: onWikiLink
                            )
                        }
                    }
                }
            }
        } else {
            VStack(spacing: 0) {
                vaultActionBar
                FlatHDivider().opacity(0.5)
                if !recentNotePaths.isEmpty || !favoriteNotePaths.isEmpty {
                    quickAccessSection
                    FlatHDivider().opacity(0.5)
                }
                NoteTreeView(
                    nodes: vaultTree,
                    searchQuery: $noteSearchQuery,
                    fullTextEnabled: $fullTextEnabled,
                    fullTextHits: fullTextHits,
                    selectedPath: nil,
                    onSelect: onSelectNote
                )
            }
        }
    }

    private var vaultActionBar: some View {
        HStack {
            Text("Vault")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
                .textCase(.uppercase)
                .tracking(0.6)
            Spacer()
            FlatButton("새 노트", icon: "plus", variant: .ghost, size: .small, action: onCreateNote)
                .help("새 마크다운 파일을 Vault에 만들기")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
    }

    @ViewBuilder
    private var quickAccessSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !favoriteNotePaths.isEmpty {
                quickAccessGroup(title: "즐겨찾기", icon: "star.fill", paths: Array(favoriteNotePaths).sorted())
            }
            if !recentNotePaths.isEmpty {
                quickAccessGroup(title: "최근", icon: "clock", paths: Array(recentNotePaths.prefix(5)))
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private func quickAccessGroup(title: String, icon: String, paths: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.Color.textTertiary)
                Text(title)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.6)
            }
            .padding(.leading, 4)
            VStack(spacing: 1) {
                ForEach(paths, id: \.self) { path in
                    QuickNoteRow(path: path, onSelect: { onSelectNote(path) })
                }
            }
        }
    }

    @ViewBuilder
    private func splitEditor(note: Note) -> some View {
        HStack(spacing: 0) {
            if splitMode != .preview {
                editorPane
            }
            if splitMode == .split {
                FlatVDivider()
            }
            if splitMode != .editor {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        MarkdownViewer(
                            markdown: editingDraft,
                            vaultRoot: vaultRoot,
                            noteResolver: noteResolver,
                            onWikiLink: onWikiLink
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .background(Theme.Color.bg)
            }
        }
    }

    private var editorPane: some View {
        VStack(spacing: 0) {
            TextEditor(text: $editingDraft)
                .font(Theme.Typography.codeBlock)
                .scrollContentBackground(.hidden)
                .padding(Theme.Spacing.md)
                .background(Theme.Color.bg)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Text(isDirty ? "저장 안 됨 — ⌘S로 저장" : "저장됨")
                    .font(Theme.Typography.small)
                    .foregroundStyle(isDirty ? Theme.Color.accent : Theme.Color.textTertiary)
                Spacer()
                Button("저장 (⌘S)", action: onSave)
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!isDirty)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Color.surface)
            .overlay(alignment: .top) { FlatHDivider() }
        }
        .frame(maxWidth: .infinity)
    }

    private func noteHeader(_ note: Note) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button(action: handleBack) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                    Text("트리")
                        .font(Theme.Typography.small)
                }
                .foregroundStyle(Theme.Color.textSecondary)
            }
            .buttonStyle(.plain)
            .help("노트 트리로 돌아가기")

            FlatVDivider().frame(height: 12)

            Text(note.title)
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Color.text)
                .lineLimit(1)
                .truncationMode(.middle)

            if isDirty {
                Text("●")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.Color.accent)
                    .help("저장되지 않은 변경 사항")
            }

            Spacer()

            Button(action: { onToggleFavorite(note.path) }) {
                Image(systemName: favoriteNotePaths.contains(note.path) ? "star.fill" : "star")
                    .font(.system(size: 12))
                    .foregroundStyle(favoriteNotePaths.contains(note.path) ? Theme.Color.accent : Theme.Color.textSecondary)
            }
            .buttonStyle(.plain)
            .help("즐겨찾기")

            if isEditing {
                splitToggle
            } else {
                modeToggle
            }

            Button(action: { onDeleteNote(note.path) }) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .buttonStyle(.plain)
            .help("이 노트를 휴지통으로 이동")

            Button(action: onOpenInObsidian) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Obsidian 앱에서 열기")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var modeToggle: some View {
        HStack(spacing: 0) {
            modeButton(label: "보기", isActive: !isEditing) {
                if isEditing { onDiscardEdits() }
            }
            modeButton(label: "편집", isActive: isEditing, action: onStartEditing)
        }
        .background(Theme.Color.surfaceHi)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private func modeButton(label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Theme.Typography.micro)
                .foregroundStyle(isActive ? Theme.Color.text : Theme.Color.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isActive ? Theme.Color.elevated : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
    }

    private var splitToggle: some View {
        HStack(spacing: 0) {
            ForEach(EditorSplitMode.allCases, id: \.self) { mode in
                Button(action: { splitMode = mode }) {
                    Image(systemName: mode.icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(splitMode == mode ? Theme.Color.text : Theme.Color.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(splitMode == mode ? Theme.Color.elevated : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .help(mode.label)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Theme.Color.surfaceHi)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private var externalChangeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Color.warning)
            Text("외부에서 변경됐어요")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.text)
            Spacer()
            Button("다시 불러오기", action: onReloadNote)
                .controlSize(.small)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 6)
        .background(Theme.Color.warning.opacity(0.10))
    }

    private func handleBack() {
        if isEditing && isDirty {
            onDiscardEdits()
        }
        onClearSelectedNote()
    }
}

public enum InspectorTab: String, CaseIterable, Sendable, Equatable {
    case context, notes, files, changes

    public var label: String {
        switch self {
        case .context: return "컨텍스트"
        case .notes: return "노트"
        case .files: return "파일"
        case .changes: return "변경"
        }
    }

    public var icon: String {
        switch self {
        case .context: return "info.circle"
        case .notes: return "doc.text"
        case .files: return "folder"
        case .changes: return "arrow.triangle.2.circlepath"
        }
    }
}

struct QuickNoteRow: View {
    let path: String
    let onSelect: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Color.textTertiary)
                Text((path as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: ""))
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(hovering ? Theme.Color.surfaceHi : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct EmptyVaultView: View {
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Spacer()
            Image(systemName: "book.closed")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.Color.textTertiary)
            Text("Obsidian Vault가 연결되지 않았어요")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Color.textSecondary)
                .multilineTextAlignment(.center)
            Text("설정 → 일반에서 Vault 폴더 경로를\n입력하면 노트를 여기서 볼 수 있어요.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textTertiary)
                .multilineTextAlignment(.center)
            FlatButton("설정 열기", icon: "gearshape", variant: .secondary, size: .small) {
                onOpenSettings()
            }
            .padding(.top, 4)
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
