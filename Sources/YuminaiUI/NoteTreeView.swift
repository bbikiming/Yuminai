import SwiftUI
import YuminaiObsidian

/// Vault 트리 + 검색 (파일명 + 옵션 본문).
public struct NoteTreeView: View {
    public let nodes: [VaultNode]
    @Binding public var searchQuery: String
    @Binding public var fullTextEnabled: Bool
    public let fullTextHits: [SearchHit]
    public let selectedPath: String?
    public let onSelect: (String) -> Void

    public init(
        nodes: [VaultNode],
        searchQuery: Binding<String>,
        fullTextEnabled: Binding<Bool> = .constant(false),
        fullTextHits: [SearchHit] = [],
        selectedPath: String?,
        onSelect: @escaping (String) -> Void
    ) {
        self.nodes = nodes
        self._searchQuery = searchQuery
        self._fullTextEnabled = fullTextEnabled
        self.fullTextHits = fullTextHits
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
        VStack(spacing: 4) {
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
            if !searchQuery.isEmpty {
                HStack(spacing: 4) {
                    Toggle(isOn: $fullTextEnabled) {
                        Text("본문도 검색")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    Spacer()
                    if fullTextEnabled {
                        Text("\(fullTextHits.count)개 매칭")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                }
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
        } else if !searchQuery.isEmpty && fullTextEnabled {
            // 본문 검색 모드: SearchHit 리스트
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(fullTextHits) { hit in
                        SearchHitRow(
                            hit: hit,
                            query: searchQuery,
                            isSelected: hit.path == selectedPath,
                            onSelect: { onSelect(hit.path) }
                        )
                    }
                }
                .padding(.horizontal, Theme.Spacing.xs)
                .padding(.vertical, 4)
            }
        } else if !searchQuery.isEmpty {
            // 파일명 검색 모드: flat
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

    /// `fullTextEnabled` 모드에서 결과 없을 때 빈 상태 분기 처리용.
    private var hasFullTextResults: Bool {
        !fullTextHits.isEmpty
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

/// 본문 검색 결과 row — 매칭 단어 highlight (B2).
struct SearchHitRow: View {
    let hit: SearchHit
    let query: String
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: hit.matchSource == .filename ? "doc.text" : "text.magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? Theme.Color.accent : Theme.Color.textSecondary)
                    Text(highlightedTitle)
                        .font(Theme.Typography.label)
                        .foregroundStyle(isSelected ? Theme.Color.text : Theme.Color.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                if let line = hit.matchedLine {
                    Text(highlightedLine(line))
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                        .lineLimit(2)
                        .padding(.leading, 16)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
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

    private var highlightedTitle: AttributedString {
        Self.highlight(text: hit.title, query: query, accent: Theme.Color.accent)
    }

    private func highlightedLine(_ line: String) -> AttributedString {
        Self.highlight(text: line, query: query, accent: Theme.Color.accent)
    }

    /// matched substring을 accent 색 + bold로 강조.
    static func highlight(text: String, query: String, accent: SwiftUI.Color) -> AttributedString {
        var attr = AttributedString(text)
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return attr }
        let lowered = text.lowercased()
        let qLower = q.lowercased()
        var searchStart = lowered.startIndex
        while let foundRange = lowered.range(of: qLower, range: searchStart..<lowered.endIndex) {
            let nsLower = lowered.distance(from: lowered.startIndex, to: foundRange.lowerBound)
            let nsUpper = lowered.distance(from: lowered.startIndex, to: foundRange.upperBound)
            if let attrLower = AttributedString.Index(text.index(text.startIndex, offsetBy: nsLower), within: attr),
               let attrUpper = AttributedString.Index(text.index(text.startIndex, offsetBy: nsUpper), within: attr) {
                attr[attrLower..<attrUpper].foregroundColor = accent
                attr[attrLower..<attrUpper].font = .system(size: 11, weight: .bold)
            }
            searchStart = foundRange.upperBound
        }
        return attr
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
