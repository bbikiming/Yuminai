import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-083 Phase 1** — 충돌 파일 시각화 + 단순화 resolution.
///
/// 단순화 디자인 (vs full 3-way merge editor):
/// - 좌측: 충돌 파일 list
/// - 우측: 선택 파일의 conflict block들 (ours / theirs side-by-side)
/// - 각 파일 단위로 "내 변경 채택" / "받은 변경 채택" 버튼
/// - 수동 편집은 외부 에디터 안내 (block 단위 inline edit는 별도 ADR)
struct GitConflictSheet: View {
    @Environment(AppModel.self) private var appModel
    @State private var conflictedFiles: [String] = []
    @State private var selectedFile: String?
    @State private var blocks: [ConflictBlock] = []
    @State private var loading: Bool = true

    var body: some View {
        YuminaiSheet(width: 880, height: 620) {
            HStack(spacing: 0) {
                fileList
                    .frame(width: 260)
                FlatVDivider()
                conflictPane
                    .frame(maxWidth: .infinity)
            }
        } footer: {
            HStack {
                Text("\(conflictedFiles.count)개 충돌 파일")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                Spacer()
                Button("Merge 취소", role: .destructive) {
                    Task {
                        await appModel.gitMergeAbort()
                        appModel.showGitConflictSheet = false
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Color.danger)
                .padding(.horizontal, 8)
                FlatButton("닫기", variant: .secondary) {
                    appModel.showGitConflictSheet = false
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .task { await reload() }
        .onChange(of: selectedFile) { _, newValue in
            Task { await loadBlocks(for: newValue) }
        }
    }

    // MARK: - File list

    @ViewBuilder
    private var fileList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("충돌 파일")
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
                .accessibilityLabel("새로고침")
            }
            .padding(Theme.Spacing.md)
            FlatHDivider()
            if loading {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .padding(.vertical, 32)
            } else if conflictedFiles.isEmpty {
                EmptyStateHint(
                    icon: "checkmark.circle",
                    title: "충돌 없음",
                    message: "현재 working tree에 충돌 파일이 없어요."
                )
                .padding(.vertical, 24)
            } else {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(conflictedFiles, id: \.self) { file in
                            fileRow(file)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .background(Theme.Color.surface)
    }

    private func fileRow(_ file: String) -> some View {
        let isSelected = selectedFile == file
        return Button {
            selectedFile = file
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                Text(file.split(separator: "/").last.map(String.init) ?? file)
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
        .help(file)
        .accessibilityLabel("충돌 파일 \(file)\(isSelected ? ", 선택됨" : "")")
    }

    // MARK: - Conflict pane (right)

    @ViewBuilder
    private var conflictPane: some View {
        if let path = selectedFile {
            VStack(alignment: .leading, spacing: 0) {
                pathHeader(path)
                FlatHDivider()
                resolveActionRow(path)
                FlatHDivider()
                if blocks.isEmpty {
                    EmptyStateHint(
                        icon: "questionmark.circle",
                        title: "충돌 블록 파싱 안 됨",
                        message: "binary 파일이거나 marker가 손상됐어요."
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                            ForEach(blocks) { block in
                                blockView(block)
                            }
                        }
                        .padding(Theme.Spacing.md)
                    }
                }
            }
        } else {
            EmptyStateHint(
                icon: "arrow.left",
                title: "파일을 선택하세요",
                message: "좌측에서 충돌 파일을 클릭하면 충돌 블록을 볼 수 있어요."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func pathHeader(_ path: String) -> some View {
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
            Text("\(blocks.count)개 충돌")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
        }
        .padding(Theme.Spacing.md)
    }

    private func resolveActionRow(_ path: String) -> some View {
        HStack(spacing: 8) {
            actionButton("내 변경 채택", icon: "person.fill", color: Theme.Color.accent) {
                Task {
                    await appModel.gitResolveConflict(path: path, strategy: .ours)
                    await reload()
                }
            }
            actionButton("받은 변경 채택", icon: "arrow.down.circle.fill", color: .purple) {
                Task {
                    await appModel.gitResolveConflict(path: path, strategy: .theirs)
                    await reload()
                }
            }
            Spacer()
            Text("외부 에디터로 수동 편집 가능")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
        }
        .padding(Theme.Spacing.md)
    }

    private func actionButton(_ label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(label)
                    .font(Theme.Typography.small.weight(.medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func blockView(_ block: ConflictBlock) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("충돌 #\(block.id + 1)")
                    .font(Theme.Typography.micro.weight(.semibold))
                    .foregroundStyle(Theme.Color.textSecondary)
                Text("(라인 \(block.startLine))")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                Spacer()
            }
            HStack(alignment: .top, spacing: 8) {
                blockSide(title: "내 변경 (HEAD)", color: Theme.Color.accent, lines: block.oursLines)
                blockSide(title: "받은 변경 (incoming)", color: .purple, lines: block.theirsLines)
            }
        }
    }

    private func blockSide(title: String, color: Color, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(Theme.Typography.micro.weight(.semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 0) {
                if lines.isEmpty {
                    Text("(빈 변경)")
                        .font(Theme.Typography.codeBlock)
                        .foregroundStyle(Theme.Color.textTertiary)
                        .italic()
                } else {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(Theme.Typography.codeBlock)
                            .foregroundStyle(Theme.Color.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
    }

    // MARK: - Loading

    private func reload() async {
        loading = true
        defer { loading = false }
        conflictedFiles = await appModel.gitConflictedFiles()
        if selectedFile == nil || !conflictedFiles.contains(selectedFile ?? "") {
            selectedFile = conflictedFiles.first
        }
    }

    private func loadBlocks(for path: String?) async {
        guard let path else {
            blocks = []
            return
        }
        blocks = await appModel.gitConflictBlocks(in: path)
    }
}
