import SwiftUI
import YuminaiCore

/// 채팅 영역 상단 toolbar v3 — Breadcrumb 좌측 inline (codex #9 반영).
public struct ChatToolbar: View {
    public let workspaceName: String
    public let workspacePath: String?
    public let isStreaming: Bool
    public let inspectorVisible: Bool
    public let onToggleSidebar: () -> Void
    public let onToggleInspector: () -> Void
    public let onShowDashboard: () -> Void
    public let onSwitchWorkspace: () -> Void

    public init(
        workspaceName: String,
        workspacePath: String? = nil,
        isStreaming: Bool,
        inspectorVisible: Bool,
        onToggleSidebar: @escaping () -> Void,
        onToggleInspector: @escaping () -> Void,
        onShowDashboard: @escaping () -> Void,
        onSwitchWorkspace: @escaping () -> Void = {}
    ) {
        self.workspaceName = workspaceName
        self.workspacePath = workspacePath
        self.isStreaming = isStreaming
        self.inspectorVisible = inspectorVisible
        self.onToggleSidebar = onToggleSidebar
        self.onToggleInspector = onToggleInspector
        self.onShowDashboard = onShowDashboard
        self.onSwitchWorkspace = onSwitchWorkspace
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            IconButton("sidebar.left", help: "사이드바 (⌘⌥1)", action: onToggleSidebar)

            breadcrumb
                .padding(.leading, Theme.Spacing.xs)

            if isStreaming {
                streamingBadge
                    .padding(.leading, Theme.Spacing.sm)
            }

            Spacer()

            IconButton("chart.bar", help: "사용량 대시보드 (⌘D)", action: onShowDashboard)
                .keyboardShortcut("d", modifiers: .command)

            IconButton(
                inspectorVisible ? "sidebar.right" : "sidebar.right",
                help: "Inspector (⌘⌥I)",
                action: onToggleInspector
            )
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Theme.Layout.toolbarHeight)
        .background(Theme.Color.bg)
        .overlay(alignment: .bottom) {
            FlatHDivider()
        }
    }

    private var breadcrumb: some View {
        Button(action: onSwitchWorkspace) {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Color.textSecondary)

                Text(workspaceName)
                    .font(Theme.Typography.mono)
                    .foregroundStyle(Theme.Color.text)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(workspacePath ?? workspaceName)
    }

    private var streamingBadge: some View {
        HStack(spacing: 6) {
            PulseDot(color: Theme.Color.accent, size: 6)
            Text("streaming")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.accent)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 2)
        .background(Theme.Color.accentMuted)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }
}
