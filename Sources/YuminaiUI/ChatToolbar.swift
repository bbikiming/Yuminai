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
    /// **ADR-079 Phase 4** — Git branch (nil이면 git repo 아님 → indicator 숨김).
    public let gitBranch: String?
    /// **ADR-079 Phase 4** — Git dirty stats (nil이면 표시 X).
    public let gitDirtyStats: DirtyStats?
    /// **ADR-079 Phase 4** — branch picker 클릭 콜백.
    public let onShowGitBranchPicker: () -> Void
    /// **ADR-079 Phase 5** — commit sheet 진입 콜백.
    public let onShowGitCommit: () -> Void
    public let inspectorVisible: Bool
    public let inspectorAllowed: Bool
    public let layoutBadge: String?
    /// **ADR-070** — 현재 layout mode. `tiny`에서는 비필수 버튼 숨김.
    public let layoutMode: LayoutMode
    public let activeAgent: AgentKind
    public let codexAvailable: Bool
    public let terminalVisible: Bool
    public let previewVisible: Bool
    public let commandsVisible: Bool
    public let onToggleSidebar: () -> Void
    public let onToggleInspector: () -> Void
    public let onToggleTerminal: () -> Void
    public let onTogglePreview: () -> Void
    public let onToggleCommands: () -> Void
    public let onShowDashboard: () -> Void
    public let onShowShortcutHelp: () -> Void
    public let onSelectWorkspace: (UUID) -> Void
    public let onCreateWorkspace: () -> Void
    public let onSelectAgent: (AgentKind) -> Void

    public init(
        workspaceName: String,
        workspacePath: String? = nil,
        workspaces: [Workspace] = [],
        selectedWorkspaceId: UUID? = nil,
        isStreaming: Bool,
        gitBranch: String? = nil,
        gitDirtyStats: DirtyStats? = nil,
        onShowGitBranchPicker: @escaping () -> Void = {},
        onShowGitCommit: @escaping () -> Void = {},
        inspectorVisible: Bool,
        inspectorAllowed: Bool = true,
        layoutBadge: String? = nil,
        layoutMode: LayoutMode = .regular,
        activeAgent: AgentKind = .default,
        codexAvailable: Bool = false,
        terminalVisible: Bool = false,
        previewVisible: Bool = false,
        commandsVisible: Bool = false,
        onToggleSidebar: @escaping () -> Void,
        onToggleInspector: @escaping () -> Void,
        onToggleTerminal: @escaping () -> Void = {},
        onTogglePreview: @escaping () -> Void = {},
        onToggleCommands: @escaping () -> Void = {},
        onShowDashboard: @escaping () -> Void,
        onShowShortcutHelp: @escaping () -> Void = {},
        onSelectWorkspace: @escaping (UUID) -> Void = { _ in },
        onCreateWorkspace: @escaping () -> Void = {},
        onSelectAgent: @escaping (AgentKind) -> Void = { _ in }
    ) {
        self.workspaceName = workspaceName
        self.workspacePath = workspacePath
        self.gitBranch = gitBranch
        self.gitDirtyStats = gitDirtyStats
        self.onShowGitBranchPicker = onShowGitBranchPicker
        self.onShowGitCommit = onShowGitCommit
        self.workspaces = workspaces
        self.selectedWorkspaceId = selectedWorkspaceId
        self.isStreaming = isStreaming
        self.inspectorVisible = inspectorVisible
        self.inspectorAllowed = inspectorAllowed
        self.layoutBadge = layoutBadge
        self.layoutMode = layoutMode
        self.activeAgent = activeAgent
        self.codexAvailable = codexAvailable
        self.terminalVisible = terminalVisible
        self.previewVisible = previewVisible
        self.commandsVisible = commandsVisible
        self.onToggleSidebar = onToggleSidebar
        self.onToggleInspector = onToggleInspector
        self.onToggleTerminal = onToggleTerminal
        self.onTogglePreview = onTogglePreview
        self.onToggleCommands = onToggleCommands
        self.onShowDashboard = onShowDashboard
        self.onShowShortcutHelp = onShowShortcutHelp
        self.onSelectWorkspace = onSelectWorkspace
        self.onCreateWorkspace = onCreateWorkspace
        self.onSelectAgent = onSelectAgent
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            IconButton(
                "sidebar.left",
                help: "사이드바 (⌘⌥1)",
                detailedHelp: ToolbarHoverInfo(
                    title: "사이드바",
                    body: "워크스페이스 목록과 파일 트리를 좌측에 표시/숨김합니다.",
                    shortcut: "⌘⌥1"
                ),
                voiceLabels: ["사이드바", "측면바", "사이드바 토글"],
                action: onToggleSidebar
            )

            breadcrumb
                .padding(.leading, Theme.Spacing.xs)

            HStack(spacing: 4) {
                agentPicker
                HelpHint(
                    "이 워크스페이스에서 채팅을 처리할 에이전트입니다. 같은 폴더에서 Claude/Codex를 자유롭게 바꿔 가며 협업할 수 있어요. 각 에이전트는 자체 세션 ID로 컨텍스트를 따로 보존합니다.",
                    title: "에이전트 전환",
                    placement: .bottom
                )
            }
            .padding(.leading, Theme.Spacing.sm)

            if isStreaming {
                streamingBadge
                    .padding(.leading, Theme.Spacing.sm)
            }

            if let layoutBadge {
                modeBadge(layoutBadge)
                    .padding(.leading, Theme.Spacing.sm)
            }

            // ADR-079 Phase 4-5 — Git branch indicator + commit button
            if let gitBranch {
                gitBranchIndicator(branch: gitBranch, stats: gitDirtyStats)
                    .padding(.leading, Theme.Spacing.sm)
                if let stats = gitDirtyStats, !stats.isEmpty {
                    gitCommitButton(stats: stats)
                        .padding(.leading, 4)
                }
            }

            Spacer()

            // ADR-070 Phase 1+5 — tiny 모드에서는 핵심 버튼만, 그 외는 풍부한 hover popover.
            if !layoutMode.hidesNonEssentialToolbarItems {
                IconButton(
                    terminalVisible ? "terminal.fill" : "terminal",
                    help: terminalVisible ? "터미널 숨기기 (⌘⌥T)" : "터미널 열기 (⌘⌥T)",
                    detailedHelp: ToolbarHoverInfo(
                        title: "터미널",
                        body: "워크스페이스 폴더에서 직접 명령어를 실행할 수 있는 zsh/bash 터미널을 엽니다.",
                        shortcut: "⌘⌥T"
                    ),
                    voiceLabels: ["터미널", "콘솔", "쉘", "터미널 토글"],
                    action: onToggleTerminal
                )
                .keyboardShortcut("t", modifiers: [.command, .option])

                IconButton(
                    previewVisible ? "safari.fill" : "safari",
                    help: previewVisible ? "Preview 숨기기 (⌘⌥P)" : "Preview 열기 (⌘⌥P)",
                    detailedHelp: ToolbarHoverInfo(
                        title: "미리보기",
                        body: "워크스페이스의 HTML/Markdown 파일을 브라우저처럼 즉시 렌더링합니다.",
                        shortcut: "⌘⌥P"
                    ),
                    voiceLabels: ["미리보기", "프리뷰", "preview"],
                    action: onTogglePreview
                )
                .keyboardShortcut("p", modifiers: [.command, .option])

                IconButton(
                    commandsVisible ? "rectangle.stack.fill" : "rectangle.stack",
                    help: commandsVisible ? "명령어 숨기기 (⌘⌥R)" : "명령어 열기 (⌘⌥R)",
                    detailedHelp: ToolbarHoverInfo(
                        title: "자주 쓰는 명령어",
                        body: "테스트 실행, 빌드, 린트 등 워크스페이스에 등록된 명령어를 한 번에 실행합니다.",
                        shortcut: "⌘⌥R"
                    ),
                    voiceLabels: ["명령어", "커맨드", "테스트 실행", "빌드"],
                    action: onToggleCommands
                )
                .keyboardShortcut("r", modifiers: [.command, .option])
            }

            IconButton(
                "chart.bar",
                help: "사용량 대시보드 (⌘D)",
                detailedHelp: ToolbarHoverInfo(
                    title: "사용량 대시보드",
                    body: "토큰 사용량, 비용, 캐시 적중률 등 LLM 사용 통계를 한 눈에 확인합니다.",
                    shortcut: "⌘D"
                ),
                voiceLabels: ["대시보드", "사용량", "통계", "비용"],
                action: onShowDashboard
            )
            .keyboardShortcut("d", modifiers: .command)

            IconButton(
                "questionmark.circle",
                help: "단축키 + 사용 가이드 (⌘/)",
                detailedHelp: ToolbarHoverInfo(
                    title: "도움말 · 단축키",
                    body: "전체 단축키 목록과 사용 가이드를 봅니다.",
                    shortcut: "⌘/"
                ),
                voiceLabels: ["도움말", "단축키", "헬프", "가이드"],
                action: onShowShortcutHelp
            )

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
                help: inspectorVisible ? "정보 패널 닫기 (⌘⌥I)" : "정보 패널 열기 (⌘⌥I)",
                detailedHelp: ToolbarHoverInfo(
                    title: "정보 패널",
                    body: "현재 세션의 컨텍스트, 비용 분석, 도구 호출 내역 등 상세 정보를 우측에 표시합니다.",
                    shortcut: "⌘⌥I"
                ),
                voiceLabels: ["정보 패널", "인스펙터", "Inspector", "오른쪽 패널"],
                action: onToggleInspector
            )
            .keyboardShortcut("i", modifiers: [.command, .option])
        } else {
            Image(systemName: "sidebar.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Color.textDisabled)
                .frame(width: 28, height: 28)
                .help("정보 패널 — 창을 더 넓혀주세요 (1080px 이상)")
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
        .accessibilityLabel("현재 워크스페이스 \(workspaceName)")
        .accessibilityHint("클릭하면 다른 워크스페이스로 전환할 수 있는 메뉴가 열립니다.")
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
        .accessibilityLabel("현재 에이전트 \(activeAgent.displayName)")
        .accessibilityHint("클릭하면 다른 에이전트(Claude / Codex)로 전환할 수 있는 메뉴가 열립니다.")
    }

    /// **ADR-079 Phase 4** — Git branch indicator (클릭 시 picker popover).
    private func gitBranchIndicator(branch: String, stats: DirtyStats?) -> some View {
        Button(action: onShowGitBranchPicker) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.Color.textSecondary)
                Text(branch)
                    .font(Theme.Typography.monoSmall)
                    .foregroundStyle(Theme.Color.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let stats, !stats.isEmpty {
                    // dirty 마커 (작은 점)
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 3)
            .background(Theme.Color.surfaceHi.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
        .buttonStyle(.plain)
        .help("Git 브랜치: \(branch)" + (stats?.isEmpty == false ? " · \(stats!.summary)" : " · 깨끗함"))
        .accessibilityLabel("Git 브랜치 \(branch)")
        .accessibilityHint("탭하여 브랜치 선택 또는 새 브랜치 만들기")
    }

    /// **ADR-079 Phase 5** — 1-click commit 버튼 (dirty 시에만 표시).
    private func gitCommitButton(stats: DirtyStats) -> some View {
        Button(action: onShowGitCommit) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("커밋")
                    .font(Theme.Typography.micro.weight(.medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 3)
            .background(Theme.Color.accent)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
        .buttonStyle(.plain)
        .help("Git 커밋 만들기 (\(stats.summary))")
        .accessibilityLabel("Git 커밋 만들기")
        .accessibilityHint(stats.summary)
    }

    private var streamingBadge: some View {
        HStack(spacing: 6) {
            PulseDot(color: Theme.Color.accent, size: 6)
                .accessibilityHidden(true)
            Text("응답 중")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.accent)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 2)
        .background(Theme.Color.accentMuted)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("에이전트가 응답을 작성 중입니다")
    }
}
