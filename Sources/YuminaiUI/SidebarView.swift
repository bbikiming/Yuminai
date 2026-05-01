import SwiftUI
import YuminaiCore

/// 워크스페이스 사이드바.
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
            Divider()
            content
        }
        .frame(minWidth: 220)
    }

    private var header: some View {
        HStack {
            Text("Workspaces")
                .font(.headline)
            Spacer()
            Button(action: onCreate) {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .help("새 워크스페이스 (⌘N)")
        }
        .padding(Theme.Spacing.md)
    }

    @ViewBuilder
    private var content: some View {
        if workspaces.isEmpty {
            VStack(spacing: Theme.Spacing.md) {
                Spacer()
                Text("워크스페이스가 없습니다")
                    .foregroundStyle(Theme.Color.labelSecondary)
                Button("+ 첫 워크스페이스") {
                    onCreate()
                }
                .controlSize(.regular)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else {
            List(workspaces, selection: $selectedId) { workspace in
                WorkspaceRow(workspace: workspace)
                    .tag(workspace.id)
                    .contextMenu {
                        Button("삭제", role: .destructive) {
                            onDelete(workspace)
                        }
                    }
            }
            .listStyle(.sidebar)
        }
    }
}

struct WorkspaceRow: View {
    let workspace: Workspace

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(workspace.name)
                .font(.body)
            Text(workspace.directoryPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}
