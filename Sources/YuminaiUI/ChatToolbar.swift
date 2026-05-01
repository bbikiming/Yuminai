import SwiftUI
import YuminaiCore

/// 채팅 영역 상단 toolbar v3 — Breadcrumb 좌측 inline (codex #9 반영) + 반응형 inspector 버튼.
///
/// Breadcrumb 클릭 시 workspace switcher menu (worksapces 리스트 + "+ 새").
public struct ChatToolbar: View {
    public let workspaceName: String
    public let workspacePath: String?
    public let workspaces: [Workspace]
    public let selectedWorkspaceId: UUID?
    public let isStreaming: Bool
    public let inspectorVisible: Bool
    public let inspectorAllowed: Bool
    public let layoutBadge: String?
    public let activeAgent: AgentKind
    public let codexAvailable: Bool
    public let onToggleSidebar: () -> Void
    public let onToggleInspector: () -> Void
    public let onShowDashboard: () -> Void
    public let onSelectWorkspace: (UUID) -> Void
    public let onCreateWorkspace: () -> Void
    public let onSelectAgent: (AgentKind) -> Void

    public init(
        workspaceName: String,
        workspacePath: String? = nil,
        workspaces: [Workspace] = [],
        selectedWorkspaceId: UUID? = nil,
        isStreaming: Bool,
        inspectorVisible: Bool,
        inspectorAllowed: Bool = true,
        layoutBadge: String? = nil,
        activeAgent: AgentKind = .default,
        codexAvailable: Bool = false,
        onToggleSidebar: @escaping () -> Void,
        onToggleInspector: @escaping () -> Void,
        onShowDashboard: @escaping () -> Void,
        onSelectWorkspace: @escaping (UUID) -> Void = { _ in },
        onCreateWorkspace: @escaping () -> Void = {},
        onSelectAgent: @escaping (AgentKind) -> Void = { _ in }
    ) {
        self.workspaceName = workspaceName
        self.workspacePath = workspacePath
        self.workspaces = workspaces
        self.selectedWorkspaceId = selectedWorkspaceId
        self.isStreaming = isStreaming
        self.inspectorVisible = inspectorVisible
        self.inspectorAllowed = inspectorAllowed
        self.layoutBadge = layoutBadge
        self.activeAgent = activeAgent
        self.codexAvailable = codexAvailable
        self.onToggleSidebar = onToggleSidebar
        self.onToggleInspector = onToggleInspector
        self.onShowDashboard = onShowDashboard
        self.onSelectWorkspace = onSelectWorkspace
        self.onCreateWorkspace = onCreateWorkspace
        self.onSelectAgent = onSelectAgent
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            IconButton("sidebar.left", help: "사이드바 (⌘⌥1)", action: onToggleSidebar)

            breadcrumb
                .padding(.leading, Theme.Spacing.xs)

            agentPicker
                .padding(.leading, Theme.Spacing.sm)

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
                help: inspectorVisible ? "Inspector 닫기 (⌘⌥I)" : "Inspector 열기 (⌘⌥I)",
                action: onToggleInspector
            )
            .keyboardShortcut("i", modifiers: [.command, .option])
        } else {
            Image(systemName: "sidebar.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Color.textDisabled)
                .frame(width: 28, height: 28)
                .help("Inspector — 창을 더 넓혀주세요 (1080px↑)")
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

    @State private var breadcrumbHovering = false

    private var breadcrumb: some View {
        Menu {
            if workspaces.isEmpty {
                Text("워크스페이스가 없어요")
            } else {
                ForEach(workspaces) { ws in
                    Button {
                        onSelectWorkspace(ws.id)
                    } label: {
                        HStack {
                            if ws.id == selectedWorkspaceId {
                                Image(systemName: "checkmark")
                            }
                            Text(ws.name)
                        }
                    }
                }
            }
            Divider()
            Button {
                onCreateWorkspace()
            } label: {
                Label("새 워크스페이스 만들기", systemImage: "plus")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Color.textSecondary)

                Text(workspaceName)
                    .font(Theme.Typography.mono)
                    .foregroundStyle(Theme.Color.text)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(breadcrumbHovering ? Theme.Color.accent : Theme.Color.textTertiary)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 4)
            .background(breadcrumbHovering ? Theme.Color.surfaceHi : .clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .animation(.easeOut(duration: 0.10), value: breadcrumbHovering)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { breadcrumbHovering = $0 }
        .help(workspacePath ?? workspaceName)
    }

    @State private var agentHovering = false

    private var agentPicker: some View {
        Menu {
            Button {
                onSelectAgent(.claude)
            } label: {
                Label {
                    VStack(alignment: .leading) {
                        Text(AgentKind.claude.displayName)
                        Text(AgentKind.claude.hint).font(.caption)
                    }
                } icon: {
                    if activeAgent == .claude {
                        Image(systemName: "checkmark")
                    } else {
                        Image(systemName: AgentKind.claude.icon)
                    }
                }
            }
            Button {
                onSelectAgent(.codex)
            } label: {
                Label {
                    VStack(alignment: .leading) {
                        Text(AgentKind.codex.displayName)
                        Text(codexAvailable ? AgentKind.codex.hint : "codex CLI 미감지 — 설정에서 경로 확인").font(.caption)
                    }
                } icon: {
                    if activeAgent == .codex {
                        Image(systemName: "checkmark")
                    } else {
                        Image(systemName: AgentKind.codex.icon)
                    }
                }
            }
            .disabled(!codexAvailable)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: activeAgent.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Color.accent)
                Text(activeAgent.displayName)
                    .font(Theme.Typography.mono)
                    .foregroundStyle(Theme.Color.text)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(agentHovering ? Theme.Color.accent : Theme.Color.textTertiary)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 4)
            .background(agentHovering ? Theme.Color.surfaceHi : Theme.Color.accentMuted)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .animation(.easeOut(duration: 0.10), value: agentHovering)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { agentHovering = $0 }
        .help("이 워크스페이스에서 사용할 에이전트")
    }

    private var streamingBadge: some View {
        HStack(spacing: 6) {
            PulseDot(color: Theme.Color.accent, size: 6)
            Text("응답 중")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.accent)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 2)
        .background(Theme.Color.accentMuted)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }
}
