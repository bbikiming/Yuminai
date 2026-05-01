import SwiftUI
import YuminaiCore
import YuminaiObsidian

/// 우측 inspector — Tab (컨텍스트 | 노트) + 콘텐츠.
public struct InspectorPanel: View {
    @Binding public var tab: InspectorTab
    public let usage: UsageStats
    public let activeSettings: SessionSettings
    public let workspacePath: String?
    public let recentTools: [String]

    // Notes tab
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

    public let onSelectNote: (String) -> Void
    public let onClearSelectedNote: () -> Void
    public let onOpenInObsidian: () -> Void
    public let onOpenSettings: () -> Void
    public let onWikiLink: (String) -> Void
    public let onStartEditing: () -> Void
    public let onSave: () -> Void
    public let onDiscardEdits: () -> Void
    public let onReloadNote: () -> Void

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
        onSelectNote: @escaping (String) -> Void,
        onClearSelectedNote: @escaping () -> Void,
        onOpenInObsidian: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onWikiLink: @escaping (String) -> Void = { _ in },
        onStartEditing: @escaping () -> Void = {},
        onSave: @escaping () -> Void = {},
        onDiscardEdits: @escaping () -> Void = {},
        onReloadNote: @escaping () -> Void = {}
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
        self.onSelectNote = onSelectNote
        self.onClearSelectedNote = onClearSelectedNote
        self.onOpenInObsidian = onOpenInObsidian
        self.onOpenSettings = onOpenSettings
        self.onWikiLink = onWikiLink
        self.onStartEditing = onStartEditing
        self.onSave = onSave
        self.onDiscardEdits = onDiscardEdits
        self.onReloadNote = onReloadNote
    }

    public var body: some View {
        VStack(spacing: 0) {
            tabBar
            FlatHDivider()
            content
        }
        .frame(width: Theme.Layout.inspectorWidth)
        .background(Theme.Color.bg)
        .overlay(alignment: .leading) {
            FlatVDivider()
        }
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
                    editor
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            NoteHeaderView(note: note)
                            MarkdownViewer(
                                markdown: note.body,
                                vaultRoot: vaultRoot,
                                onWikiLink: onWikiLink
                            )
                        }
                    }
                }
            }
        } else {
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

            modeToggle

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

    @ViewBuilder
    private var editor: some View {
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
    }

    private func handleBack() {
        if isEditing && isDirty {
            onDiscardEdits()
        }
        onClearSelectedNote()
    }
}

/// Inspector 탭 enum.
public enum InspectorTab: String, CaseIterable, Sendable, Equatable {
    case context, notes

    public var label: String {
        switch self {
        case .context: return "컨텍스트"
        case .notes: return "노트"
        }
    }

    public var icon: String {
        switch self {
        case .context: return "info.circle"
        case .notes: return "doc.text"
        }
    }
}

/// Vault 미설정 안내.
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
