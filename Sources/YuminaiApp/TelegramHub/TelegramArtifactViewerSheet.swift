import SwiftUI
import AppKit
import YuminaiCore
import YuminaiUI

/// **ADR-097** — Telegram deep link (`yuminai://diff/{uuid}`, `yuminai://log/{uuid}`)
/// 클릭 시 표시하는 artifact viewer sheet.
///
/// - diff: +/-/@@ syntax highlighting (green/red/cyan)
/// - log: monospaced + 마지막 줄 자동 스크롤
/// - 만료/없음: AnimatedEmptyState
@MainActor
struct TelegramArtifactViewerSheet: View {

    let artifactId: UUID

    @Environment(AppModel.self) private var appModel
    @State private var artifact: TelegramArtifactStore.Artifact?
    @State private var loading = true
    @State private var notFound = false

    var body: some View {
        YuminaiSheet(width: 720, height: 560) {
            VStack(alignment: .leading, spacing: 0) {
                if loading {
                    loadingView
                } else if notFound || artifact == nil {
                    expiredView
                } else {
                    artifactBody
                }
            }
        } footer: {
            footerButtons
        }
        .task { await load() }
    }

    // MARK: - Loading

    private var loadingView: some View {
        HStack {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.xl)
    }

    // MARK: - Expired / Not Found

    private var expiredView: some View {
        AnimatedEmptyState(
            icon: "clock.badge.xmark",
            iconTint: Theme.Color.textTertiary,
            title: "Artifact 없음",
            message: "이 artifact는 만료되었거나 존재하지 않습니다.\n(ID: \(artifactId.uuidString.lowercased()))"
        )
    }

    // MARK: - Artifact Body

    @ViewBuilder
    private var artifactBody: some View {
        switch artifact {
        case .diff(let content, let files, let added, let removed, _):
            VStack(alignment: .leading, spacing: 0) {
                diffHeader(files: files, added: added, removed: removed)
                Divider()
                diffContentView(content: content)
            }

        case .log(let content, let title, let elapsed, let success):
            VStack(alignment: .leading, spacing: 0) {
                logHeader(title: title, elapsed: elapsed, success: success)
                Divider()
                logContentView(content: content)
            }

        case nil:
            EmptyView()
        }
    }

    // MARK: - Diff Header

    private func diffHeader(files: Int, added: Int, removed: Int) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(Theme.Color.accent)
                .font(.system(size: 16, weight: .medium))
            VStack(alignment: .leading, spacing: 2) {
                Text("Diff Viewer")
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.Color.text)
                Text("\(files) file\(files == 1 ? "" : "s")  +\(added) / -\(removed)")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }

    // MARK: - Log Header

    private func logHeader(title: String, elapsed: TimeInterval, success: Bool) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(success ? Color.green : Color.red)
                .font(.system(size: 16, weight: .medium))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.Color.text)
                Text("\(formatElapsed(elapsed))  \(success ? "PASSED" : "FAILED")")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }

    // MARK: - Diff Content (syntax highlight)

    private func diffContentView(content: String) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(content.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                    Text(line.isEmpty ? " " : line)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(diffLineColor(line))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(diffLineBg(line))
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
        }
    }

    private func diffLineColor(_ line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return Color.green }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return Color.red }
        if line.hasPrefix("@@") { return Color.cyan }
        return Theme.Color.text
    }

    private func diffLineBg(_ line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return Color.green.opacity(0.07) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return Color.red.opacity(0.07) }
        return Color.clear
    }

    // MARK: - Log Content (auto scroll to bottom)

    private func logContentView(content: String) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    let lines = content.components(separatedBy: "\n")
                    ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Theme.Color.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .id(idx)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
            }
            .onAppear {
                let lineCount = content.components(separatedBy: "\n").count
                if lineCount > 0 {
                    withAnimation {
                        proxy.scrollTo(lineCount - 1, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footerButtons: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // Workspace 열기 (diff 전용)
            if case .diff(_, _, _, _, let workspace) = artifact, let ws = workspace {
                FlatButton("Workspace 열기", variant: .secondary, size: .small) {
                    Task { await openWorkspace(named: ws) }
                }
            }

            Spacer()

            FlatButton("복사", variant: .secondary, size: .small) {
                copyContent()
            }

            FlatButton("닫기", variant: .primary, size: .small) {
                appModel.showTelegramArtifactSheet = false
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }

    // MARK: - Private Helpers

    private func load() async {
        loading = true
        let fetched = await appModel.telegramArtifactStore.fetch(artifactId)
        artifact = fetched
        notFound = fetched == nil
        loading = false
    }

    private func copyContent() {
        let text: String
        switch artifact {
        case .diff(let content, _, _, _, _): text = content
        case .log(let content, _, _, _): text = content
        case nil: return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func openWorkspace(named name: String) async {
        // workspace 이름으로 전환 — 향후 AppModel.transitionToWorkspaceByName 연동
        _ = name
    }

    private func formatElapsed(_ elapsed: TimeInterval) -> String {
        let total = Int(elapsed.rounded())
        let min = total / 60
        let sec = total % 60
        return min > 0 ? "\(min)m \(sec)s" : "\(sec)s"
    }
}
