import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-082 Phase 1** — 현재 워크스페이스의 git 변경 사항 viewer.
///
/// 좌측: modified files list (status badge + path)
/// 우측: 선택한 파일의 inline diff (+ green / − red)
///
/// 단순화 디자인 (Apple Sample Code "DocBased" 패턴):
/// - master-detail layout
/// - 빈 상태 안내
/// - copy diff to clipboard
struct GitDiffSheet: View {
    @Environment(AppModel.self) private var appModel
    @State private var changedFiles: [ChangedFile] = []
    @State private var selectedPath: String?
    @State private var diffText: String = ""
    @State private var loading: Bool = true

    var body: some View {
        YuminaiSheet(width: 880, height: 600) {
            HStack(spacing: 0) {
                fileList
                    .frame(width: 260)
                FlatVDivider()
                diffPane
                    .frame(maxWidth: .infinity)
            }
        } footer: {
            HStack {
                Text("\(changedFiles.count)개 변경 파일")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(diffText, forType: .string)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                        Text("Diff 복사")
                            .font(Theme.Typography.small.weight(.medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.Color.surfaceHi)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .disabled(diffText.isEmpty)
                .accessibilityLabel("Diff 클립보드로 복사")
                FlatButton("닫기", variant: .secondary) {
                    appModel.showGitDiffSheet = false
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .task { await reload() }
        .onChange(of: selectedPath) { _, newValue in
            Task { await loadDiff(for: newValue) }
        }
        .overlay(alignment: .topTrailing) {
            SheetCloseButton { appModel.showGitDiffSheet = false }
        }
    }

    // MARK: - File list (left)

    @ViewBuilder
    private var fileList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("변경된 파일")
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.Color.text)
                Spacer()
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .buttonStyle(.plain)
                .help("새로고침")
                .accessibilityLabel("Diff 새로고침")
            }
            .padding(Theme.Spacing.md)
            FlatHDivider()
            if loading {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .padding(.vertical, 32)
            } else if changedFiles.isEmpty {
                EmptyStateHint(
                    icon: "checkmark.circle",
                    title: "변경 사항 없음",
                    message: "working tree가 깨끗해요. 파일을 수정한 후 다시 열어보세요."
                )
                .padding(.vertical, 24)
            } else {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(changedFiles) { file in
                            fileRow(file)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .background(Theme.Color.surface)
    }

    private func fileRow(_ file: ChangedFile) -> some View {
        let isSelected = selectedPath == file.path
        return Button {
            selectedPath = file.path
        } label: {
            HStack(spacing: 6) {
                statusBadge(file.status)
                Text(file.path.split(separator: "/").last.map(String.init) ?? file.path)
                    .font(Theme.Typography.monoSmall)
                    .foregroundStyle(Theme.Color.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 4)
            .background(isSelected ? Theme.Color.accentMuted : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(file.path)
        .accessibilityLabel("\(file.status.label) \(file.path)\(isSelected ? ", 선택됨" : "")")
    }

    private func statusBadge(_ status: ChangedFile.Status) -> some View {
        let color: Color = {
            switch status {
            case .modified: return .yellow
            case .added: return .green
            case .deleted: return .red
            case .renamed, .copied: return .blue
            case .untracked: return .gray
            case .unknown: return Theme.Color.textTertiary
            }
        }()
        let symbol: String = {
            switch status {
            case .modified: return "M"
            case .added: return "A"
            case .deleted: return "D"
            case .renamed: return "R"
            case .copied: return "C"
            case .untracked: return "?"
            case .unknown: return "•"
            }
        }()
        return Text(symbol)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .frame(width: 14, height: 14)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .accessibilityHidden(true)
    }

    // MARK: - Diff pane (right)

    @ViewBuilder
    private var diffPane: some View {
        if let path = selectedPath {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Color.textSecondary)
                    Text(path)
                        .font(Theme.Typography.monoSmall)
                        .foregroundStyle(Theme.Color.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                .padding(Theme.Spacing.md)
                FlatHDivider()
                if diffText.isEmpty {
                    EmptyStateHint(
                        icon: "doc.text",
                        title: "Diff 없음",
                        message: "이 파일은 untracked이거나 binary 파일입니다."
                    )
                    .padding(.vertical, 32)
                } else {
                    ScrollView {
                        diffLines
                    }
                }
            }
        } else {
            EmptyStateHint(
                icon: "arrow.left",
                title: "파일을 선택하세요",
                message: "좌측 목록에서 파일을 클릭하면 변경 내용을 볼 수 있어요."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Inline diff coloring (+ green, - red, @@ accent).
    private var diffLines: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(diffText.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, lineSubstring in
                let line = String(lineSubstring)
                Text(line)
                    .font(Theme.Typography.codeBlock)
                    .foregroundStyle(diffLineColor(line))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 1)
                    .background(diffLineBackground(line))
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
    }

    private func diffLineColor(_ line: String) -> Color {
        if line.hasPrefix("+++") || line.hasPrefix("---") { return Theme.Color.textTertiary }
        if line.hasPrefix("@@") { return Theme.Color.accent }
        if line.hasPrefix("+") { return .green }
        if line.hasPrefix("-") { return .red }
        return Theme.Color.text
    }

    private func diffLineBackground(_ line: String) -> Color {
        if line.hasPrefix("+++") || line.hasPrefix("---") { return Color.clear }
        if line.hasPrefix("@@") { return Theme.Color.accentMuted.opacity(0.5) }
        if line.hasPrefix("+") { return Theme.Color.gitAdded.opacity(0.10) }
        if line.hasPrefix("-") { return Theme.Color.gitRemoved.opacity(0.10) }
        return Color.clear
    }

    // MARK: - Loading

    private func reload() async {
        loading = true
        defer { loading = false }
        guard let ws = appModel.workspaces.first(where: { $0.id == appModel.selectedWorkspaceId }) else {
            changedFiles = []
            return
        }
        let url = URL(fileURLWithPath: ws.directoryPath)
        let runner = GitRunner(workspaceURL: url)
        guard await runner.isRepository() else {
            changedFiles = []
            return
        }
        changedFiles = (try? await runner.changedFiles()) ?? []
        // 첫 파일 자동 선택
        if selectedPath == nil || !changedFiles.contains(where: { $0.path == selectedPath }) {
            selectedPath = changedFiles.first?.path
        }
    }

    private func loadDiff(for path: String?) async {
        guard let path,
              let ws = appModel.workspaces.first(where: { $0.id == appModel.selectedWorkspaceId }) else {
            diffText = ""
            return
        }
        let url = URL(fileURLWithPath: ws.directoryPath)
        let runner = GitRunner(workspaceURL: url)
        diffText = (try? await runner.diff(paths: [path])) ?? ""
    }
}
