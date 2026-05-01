import SwiftUI
import YuminaiCore

/// 채팅 영역 상단 toolbar v3 — Breadcrumb 좌측 inline (codex #9 반영) + 반응형 inspector 버튼.
public struct ChatToolbar: View {
    public let workspaceName: String
    public let workspacePath: String?
    public let isStreaming: Bool
    public let inspectorVisible: Bool
    public let inspectorAllowed: Bool
    public let layoutBadge: String?
    public let onToggleSidebar: () -> Void
    public let onToggleInspector: () -> Void
    public let onShowDashboard: () -> Void
    public let onSwitchWorkspace: () -> Void

    public init(
        workspaceName: String,
        workspacePath: String? = nil,
        isStreaming: Bool,
        inspectorVisible: Bool,
        inspectorAllowed: Bool = true,
        layoutBadge: String? = nil,
        onToggleSidebar: @escaping () -> Void,
        onToggleInspector: @escaping () -> Void,
        onShowDashboard: @escaping () -> Void,
        onSwitchWorkspace: @escaping () -> Void = {}
    ) {
        self.workspaceName = workspaceName
        self.workspacePath = workspacePath
        self.isStreaming = isStreaming
        self.inspectorVisible = inspectorVisible
        self.inspectorAllowed = inspectorAllowed
        self.layoutBadge = layoutBadge
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

            if let layoutBadge {
                modeBadge(layoutBadge)
                    .padding(.leading, Theme.Spacing.sm)
            }

            Spacer()

            IconButton("chart.bar", help: "사용량 대시보드 (⌘D)", action: onShowDashboard)
                .keyboardShortcut("d", modifiers: .command)

            inspectorToggle
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Theme.Layout.toolbarHeight)
        .background(Theme.Color.bg)
        .overlay(alignment: .bottom) {
            FlatHDivider()
        }
    }

    @ViewBuilder
    private var inspectorToggle: some View {
        if inspectorAllowed {
            IconButton(
                inspectorVisible ? "sidebar.right" : "sidebar.right",
                help: "Inspector (⌘⌥I)",
                action: onToggleInspector
            )
            .keyboardShortcut("i", modifiers: [.command, .option])
        } else {
            Image(systemName: "sidebar.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Color.textDisabled)
                .frame(width: 28, height: 28)
                .help("Inspector — 윈도우가 좁아 사용 불가 (1080px 이상 필요)")
        }
    }

    private func modeBadge(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.micro)
            .foregroundStyle(Theme.Color.textTertiary)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 2)
            .background(Theme.Color.surfaceHi)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
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
