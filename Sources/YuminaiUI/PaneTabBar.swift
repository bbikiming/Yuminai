import SwiftUI
import YuminaiCore

/// 워크스페이스 안의 agent pane들을 탭으로 표시 (ADR-030, M1 phase C).
///
/// 각 pane은 자체 session + messages를 보유. tab 전환 시 chat 영역이 해당 pane의 state로 swap.
/// "+" 버튼으로 새 pane 추가 (Claude/Codex 선택), 각 탭의 ✕로 close (마지막은 disabled).
public struct PaneTabBar: View {
    public let panes: [AgentPane]
    public let activePaneId: UUID?
    public let codexAvailable: Bool
    public let onSelect: (UUID) -> Void
    public let onClose: (UUID) -> Void
    public let onAdd: (AgentKind) -> Void
    public let onRename: (AgentPane) -> Void
    public let onPromoteToPrimary: (UUID) -> Void

    @Binding public var splitMode: PaneSplitMode

    public init(
        panes: [AgentPane],
        activePaneId: UUID?,
        codexAvailable: Bool,
        splitMode: Binding<PaneSplitMode> = .constant(.single),
        onSelect: @escaping (UUID) -> Void,
        onClose: @escaping (UUID) -> Void,
        onAdd: @escaping (AgentKind) -> Void,
        onRename: @escaping (AgentPane) -> Void = { _ in },
        onPromoteToPrimary: @escaping (UUID) -> Void = { _ in }
    ) {
        self.panes = panes
        self.activePaneId = activePaneId
        self.codexAvailable = codexAvailable
        self._splitMode = splitMode
        self.onSelect = onSelect
        self.onClose = onClose
        self.onAdd = onAdd
        self.onRename = onRename
        self.onPromoteToPrimary = onPromoteToPrimary
    }

    public var body: some View {
        HStack(spacing: 1) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(panes) { pane in
                        PaneTabButton(
                            pane: pane,
                            isActive: pane.id == activePaneId,
                            canClose: panes.count > 1,
                            onSelect: { onSelect(pane.id) },
                            onClose: { onClose(pane.id) },
                            onRename: { onRename(pane) },
                            onPromote: { onPromoteToPrimary(pane.id) }
                        )
                    }
                }
                .padding(.horizontal, Theme.Spacing.sm)
            }

            addPaneMenu

            if panes.count > 1 {
                splitModePicker
            }

            HelpHint(
                "한 워크스페이스에서 Claude와 Codex를 동시에 띄울 수 있어요. 각 pane은 자체 conversation을 가지고, 같은 프로젝트 폴더를 공유하므로 한 쪽이 만든 파일을 다른 쪽이 즉시 봅니다. 탭을 전환하면 messages도 swap돼요.",
                title: "에이전트 패널",
                placement: .bottom
            )
            .padding(.trailing, Theme.Spacing.sm)
        }
        .frame(height: 28)
        .background(Theme.Color.bgSidebar)
        .overlay(alignment: .bottom) { FlatHDivider() }
    }

    @ViewBuilder
    private var splitModePicker: some View {
        Menu {
            ForEach(PaneSplitMode.allCases, id: \.self) { mode in
                Button {
                    splitMode = mode
                } label: {
                    Label(mode.label, systemImage: mode.icon)
                }
            }
        } label: {
            Image(systemName: splitMode.icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(splitMode == .single ? Theme.Color.textSecondary : Theme.Color.accent)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("패널 레이아웃 (단일/좌·우/위·아래)")
    }

    @ViewBuilder
    private var addPaneMenu: some View {
        Menu {
            Button {
                onAdd(.claude)
            } label: {
                Label("Claude pane 추가", systemImage: AgentKind.claude.icon)
            }
            Button {
                onAdd(.codex)
            } label: {
                Label("Codex pane 추가", systemImage: AgentKind.codex.icon)
            }
            .disabled(!codexAvailable)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Color.textSecondary)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("새 에이전트 pane 추가 (Claude/Codex)")
    }
}

private struct PaneTabButton: View {
    let pane: AgentPane
    let isActive: Bool
    let canClose: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onRename: () -> Void
    let onPromote: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 5) {
                Image(systemName: pane.agentKind.icon)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(isActive ? Theme.Color.accent : Theme.Color.textTertiary)
                Text(pane.displayName)
                    .font(Theme.Typography.small)
                    .foregroundStyle(isActive ? Theme.Color.text : Theme.Color.textSecondary)
                    .lineLimit(1)
                if pane.role == .primary {
                    Image(systemName: "star.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(Theme.Color.accent)
                        .help("기본 pane — 텔레그램 forward 대상")
                }
                if canClose && (hovering || isActive) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.Color.textSecondary)
                            .frame(width: 12, height: 12)
                            .background(Theme.Color.surfaceHi)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("pane 닫기")
                }
            }
            .padding(.horizontal, Theme.Spacing.sm + 2)
            .padding(.vertical, 4)
            .background(rowBg)
            .overlay(alignment: .bottom) {
                if isActive {
                    Rectangle()
                        .fill(Theme.Color.accent)
                        .frame(height: 2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("이름 바꾸기…", systemImage: "pencil", action: onRename)
            if pane.role != .primary {
                Button("기본 pane으로 설정", systemImage: "star", action: onPromote)
            }
            if canClose {
                Divider()
                Button("닫기", systemImage: "xmark", role: .destructive, action: onClose)
            }
        }
    }

    private var rowBg: SwiftUI.Color {
        if isActive { return Theme.Color.bg }
        if hovering { return Theme.Color.surfaceHi }
        return .clear
    }
}
