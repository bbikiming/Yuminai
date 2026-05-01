import SwiftUI
import YuminaiObsidian

/// Composer "노트 첨부" 버튼이 호출하는 popover — Vault 트리에서 노트 선택.
public struct NotePickerPopover: View {
    public let vaultTree: [VaultNode]
    @Binding public var query: String
    public let onSelectPath: (String) -> Void
    public let onClose: () -> Void

    public init(
        vaultTree: [VaultNode],
        query: Binding<String>,
        onSelectPath: @escaping (String) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.vaultTree = vaultTree
        self._query = query
        self.onSelectPath = onSelectPath
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            FlatHDivider()
            content
        }
        .frame(width: 320, height: 360)
        .background(Theme.Color.elevated)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Color.accent)
            Text("노트 첨부")
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Color.text)
            Spacer()
            IconButton("xmark", size: 11, help: "닫기 (Esc)", action: onClose)
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var content: some View {
        let trees = vaultTree
        return NoteTreeView(
            nodes: trees,
            searchQuery: $query,
            selectedPath: nil,
            onSelect: { path in
                onSelectPath(path)
                onClose()
            }
        )
    }
}
