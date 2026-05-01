import SwiftUI
import YuminaiCore

/// 워크스페이스 사이드바 — flat 단일 column.
public struct SidebarView: View {
    public let workspaces: [Workspace]
    @Binding public var selectedId: UUID?
    public let onCreate: () -> Void
    public let onDelete: (Workspace) -> Void

    public init(
        workspaces: [Workspace],
        selectedId: Binding<UUID?>,
        onCreate: @escaping () -> Void,
        onDelete: @escaping (Workspace) -> Void
    ) {
        self.workspaces = workspaces
        self._selectedId = selectedId
        self.onCreate = onCreate
        self.onDelete = onDelete
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            FlatHDivider()
            content
        }
        .frame(width: Theme.Layout.sidebarWidth)
        .flatChrome(borders: [.trailing])
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("workspaces")
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Color.textTertiary)
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()
            FlatButton("", icon: "plus", variant: .ghost, size: .small, action: onCreate)
                .help("새 워크스페이스 (⌘N)")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Theme.Layout.toolbarHeight)
    }

    @ViewBuilder
    private var content: some View {
        if workspaces.isEmpty {
            VStack(spacing: Theme.Spacing.md) {
                Spacer()
                Text("─ no workspaces ─")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textTertiary)
                FlatButton("+ 새 워크스페이스", variant: .accent, size: .small, action: onCreate)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(workspaces) { workspace in
                        WorkspaceRow(
                            workspace: workspace,
                            isSelected: workspace.id == selectedId,
                            onSelect: { selectedId = workspace.id },
                            onDelete: { onDelete(workspace) }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

struct WorkspaceRow: View {
    let workspace: Workspace
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(isSelected ? ">" : " ")
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(isSelected ? Theme.Color.accent : Theme.Color.textTertiary)
                    .frame(width: 8)

                VStack(alignment: .leading, spacing: 1) {
                    Text(workspace.name)
                        .font(Theme.Typography.body)
                        .foregroundStyle(isSelected ? Theme.Color.text : Theme.Color.textSecondary)
                        .lineLimit(1)
                    Text(workspace.directoryPath)
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(rowBg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("삭제", role: .destructive, action: onDelete)
        }
    }

    private var rowBg: SwiftUI.Color {
        if isSelected { return Theme.Color.bgSelected }
        if isHovered { return Theme.Color.bgHover }
        return .clear
    }
}
