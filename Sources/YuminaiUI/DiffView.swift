import SwiftUI
import YuminaiCore

/// 워크스페이스의 git diff를 시각화하는 view (ADR-027 phase A3).
///
/// view-only — accept/reject 액션은 부모(Inspector "변경" 탭)가 처리. editable diff는 v0.5.
///
/// **레이아웃**:
/// - 상단: 변경 요약 (N개 파일) + accept all / reject all 버튼
/// - 본문: 파일 목록 (status badge + path) + 각 파일별 reject 버튼
/// - 하단: 선택된 파일의 unified diff (monospace + +/- 색)
public struct DiffReviewView: View {
    public let changes: [ChangedFile]
    public let unifiedDiff: String
    public let onAcceptAll: () -> Void
    public let onRejectAll: () -> Void
    public let onRejectFile: (ChangedFile) -> Void

    @State private var selectedPath: String?

    public init(
        changes: [ChangedFile],
        unifiedDiff: String,
        onAcceptAll: @escaping () -> Void,
        onRejectAll: @escaping () -> Void,
        onRejectFile: @escaping (ChangedFile) -> Void
    ) {
        self.changes = changes
        self.unifiedDiff = unifiedDiff
        self.onAcceptAll = onAcceptAll
        self.onRejectAll = onRejectAll
        self.onRejectFile = onRejectFile
    }

    public var body: some View {
        if changes.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                summaryHeader
                FlatHDivider()
                ScrollView {
                    fileList
                }
                .frame(maxHeight: 220)
                FlatHDivider()
                diffViewer
                    .frame(maxHeight: .infinity)
            }
        }
    }

    // MARK: - Components

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 24))
                .foregroundStyle(Theme.Color.textTertiary)
            Text("변경된 파일이 없어요")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Color.textSecondary)
            Text("에이전트가 코드를 수정하면 여기에 표시됩니다.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var summaryHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Color.accent)
            Text("\(changes.count)개 파일 변경")
                .font(Theme.Typography.small.weight(.semibold))
                .foregroundStyle(Theme.Color.text)
            Spacer()
            FlatButton("모두 원복", variant: .secondary, size: .small, action: onRejectAll)
            FlatButton("모두 적용", variant: .primary, size: .small, action: onAcceptAll)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Color.surface)
    }

    private var fileList: some View {
        VStack(spacing: 1) {
            ForEach(changes) { file in
                FileRow(
                    file: file,
                    selected: selectedPath == file.path,
                    onSelect: { selectedPath = file.path },
                    onReject: { onRejectFile(file) }
                )
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var diffViewer: some View {
        if let path = selectedPath {
            ScrollView([.horizontal, .vertical]) {
                colorizedDiff(for: path)
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.Color.bg)
        } else {
            VStack(spacing: 6) {
                Text("파일을 선택하면 변경 내용을 볼 수 있어요")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Color.bg)
        }
    }

    /// unified diff에서 해당 파일의 hunk만 추출 + +/- 색 처리.
    private func colorizedDiff(for path: String) -> some View {
        let hunks = Self.extractHunks(from: unifiedDiff, path: path)
        return VStack(alignment: .leading, spacing: 1) {
            if hunks.isEmpty {
                // diff에 hunk가 없으면 (untracked 등) 안내
                Text("(untracked 파일이거나 diff가 없어요)")
                    .font(Theme.Typography.monoSmall)
                    .foregroundStyle(Theme.Color.textTertiary)
            } else {
                ForEach(Array(hunks.enumerated()), id: \.offset) { _, line in
                    diffLine(line)
                }
            }
        }
    }

    private func diffLine(_ line: String) -> some View {
        let kind = Self.lineKind(line)
        let bg: SwiftUI.Color
        let fg: SwiftUI.Color
        switch kind {
        case .added:
            bg = SwiftUI.Color.green.opacity(0.12)
            fg = SwiftUI.Color.green
        case .removed:
            bg = SwiftUI.Color.red.opacity(0.12)
            fg = SwiftUI.Color.red
        case .hunkHeader:
            bg = Theme.Color.surfaceHi
            fg = Theme.Color.textSecondary
        case .context:
            bg = .clear
            fg = Theme.Color.text
        }
        return Text(line.isEmpty ? " " : line)
            .font(Theme.Typography.mono)
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .background(bg)
    }

    // MARK: - Parsing helpers

    enum LineKind { case added, removed, hunkHeader, context }

    static func lineKind(_ line: String) -> LineKind {
        guard let first = line.first else { return .context }
        if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("diff ") || line.hasPrefix("index ") {
            return .hunkHeader
        }
        if first == "@" && line.hasPrefix("@@") { return .hunkHeader }
        if first == "+" { return .added }
        if first == "-" { return .removed }
        return .context
    }

    /// `git diff` 전체 출력에서 특정 파일에 해당하는 hunk 라인들을 추출.
    static func extractHunks(from diff: String, path: String) -> [String] {
        guard !diff.isEmpty else { return [] }
        var collected: [String] = []
        var inFile = false
        for line in diff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("diff --git") {
                // 새 파일 헤더 — path 매칭 검사
                inFile = line.contains(" a/\(path)") || line.contains(" b/\(path)") || line.contains(path)
                if inFile { collected.append(line) }
            } else if inFile {
                collected.append(line)
            }
        }
        return collected
    }
}

private struct FileRow: View {
    let file: ChangedFile
    let selected: Bool
    let onSelect: () -> Void
    let onReject: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                statusBadge
                Text(file.path)
                    .font(Theme.Typography.monoSmall)
                    .foregroundStyle(selected ? Theme.Color.text : Theme.Color.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if hovering || selected {
                    Button(action: onReject) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("이 파일 변경 원복")
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 4)
            .background(selected ? Theme.Color.accentMuted : (hovering ? Theme.Color.surfaceHi : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var statusBadge: some View {
        Text(file.status.label)
            .font(Theme.Typography.micro)
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .frame(width: 56, alignment: .center)
    }

    private var badgeColor: SwiftUI.Color {
        switch file.status {
        case .added, .untracked: return .green
        case .deleted: return .red
        case .modified, .renamed, .copied: return .orange
        case .unknown: return Theme.Color.textTertiary
        }
    }
}
