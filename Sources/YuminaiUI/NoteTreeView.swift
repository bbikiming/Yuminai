import SwiftUI
import YuminaiObsidian

/// Vault 트리 + 검색.
public struct NoteTreeView: View {
    public let nodes: [VaultNode]
    @Binding public var searchQuery: String
    public let selectedPath: String?
    public let onSelect: (String) -> Void

    public init(
        nodes: [VaultNode],
        searchQuery: Binding<String>,
        selectedPath: String?,
        onSelect: @escaping (String) -> Void
    ) {
        self.nodes = nodes
        self._searchQuery = searchQuery
        self.selectedPath = selectedPath
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(spacing: 0) {
            searchBar
            FlatHDivider().opacity(0.5)
            content
        }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Color.textTertiary)
            TextField("노트 검색", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Color.text)
            if !searchQuery.isEmpty {
                Button(action: { searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Color.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
    }

    @ViewBuilder
    private var content: some View {
        if nodes.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Text("이 Vault에 .md 노트가 없네요")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textTertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !searchQuery.isEmpty && filteredFlat.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Text("‘\(searchQuery)’와 매칭되는 노트가 없어요")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !searchQuery.isEmpty {
            // 검색 모드: flat 리스트
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredFlat) { node in
                        VaultLeafRow(
                            node: node,
                            isSelected: node.path == selectedPath,
                            depth: 0,
                            onSelect: { onSelect(node.path) }
                        )
                    }
                }
                .padding(.horizontal, Theme.Spacing.xs)
                .padding(.vertical, 4)
            }
        } else {
            // 트리 모드
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(nodes) { node in
                        VaultNodeRow(
                            node: node,
                            depth: 0,
                            selectedPath: selectedPath,
                            onSelect: onSelect
                        )
                    }
                }
                .padding(.horizontal, Theme.Spacing.xs)
                .padding(.vertical, 4)
            }
        }
    }

    private var filteredFlat: [VaultNode] {
        let q = searchQuery.lowercased()
        return flatten(nodes).filter { node in
            if case .note(let name, _, _) = node {
                return name.lowercased().contains(q)
            }
            return false
        }
    }

    private func flatten(_ nodes: [VaultNode]) -> [VaultNode] {
        nodes.flatMap { node -> [VaultNode] in
            switch node {
            case .note: return [node]
            case .folder(_, _, let children): return flatten(children)
            }
        }
    }
}

// MARK: - Tree row (folder + recursive children)

struct VaultNodeRow: View {
    let node: VaultNode
    let depth: Int
    let selectedPath: String?
    let onSelect: (String) -> Void

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch node {
            case .folder(let name, _, let children):
                folderRow(name: name)
                if expanded {
                    ForEach(children) { child in
                        VaultNodeRow(
                            node: child,
                            depth: depth + 1,
                            selectedPath: selectedPath,
                            onSelect: onSelect
                        )
                    }
                }
            case .note(let name, let path, _):
                VaultLeafRow(
                    node: node,
                    isSelected: path == selectedPath,
                    depth: depth,
                    onSelect: { onSelect(path) }
                )
                .accessibilityHidden(false)
                .help(name)
            }
        }
    }

    @State private var hovering = false

    private func folderRow(name: String) -> some View {
        Button(action: { expanded.toggle() }) {
            HStack(spacing: 5) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.Color.textTertiary)
                    .frame(width: 12)
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.textSecondary)
                Text(name)
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.leading, CGFloat(depth) * 12 + 4)
            .padding(.trailing, 6)
            .padding(.vertical, 4)
            .background(hovering ? Theme.Color.surfaceHi : .clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// 노트(leaf) row.
struct VaultLeafRow: View {
    let node: VaultNode
    let isSelected: Bool
    let depth: Int
    let onSelect: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 5) {
                Spacer().frame(width: 12)  // chevron 자리
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Theme.Color.accent : Theme.Color.textSecondary)
                Text(node.name)
                    .font(Theme.Typography.label)
                    .foregroundStyle(isSelected ? Theme.Color.text : Theme.Color.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.leading, CGFloat(depth) * 12 + 4)
            .padding(.trailing, 6)
            .padding(.vertical, 4)
            .background(rowBg)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var rowBg: SwiftUI.Color {
        if isSelected { return Theme.Color.elevated }
        if hovering { return Theme.Color.surfaceHi }
        return .clear
    }
}
