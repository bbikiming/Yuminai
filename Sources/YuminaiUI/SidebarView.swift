import SwiftUI
import YuminaiCore

/// 워크스페이스 사이드바 v3 — 스크린샷 룩 (top header → primary action → group → items → update card → user card).
public struct SidebarView: View {
    public let workspaces: [Workspace]
    @Binding public var selectedId: UUID?
    public let telegramBoundId: UUID?
    public let telegramAvailable: Bool
    public let onCreate: () -> Void
    public let onDelete: (Workspace) -> Void
    public let onCollapse: () -> Void
    public let onSearch: () -> Void
    public let onOpenSettings: () -> Void
    public let onToggleTelegramBind: (Workspace) -> Void
    public let userName: String
    public let updateAvailable: Bool

    public init(
        workspaces: [Workspace],
        selectedId: Binding<UUID?>,
        telegramBoundId: UUID? = nil,
        telegramAvailable: Bool = false,
        onCreate: @escaping () -> Void,
        onDelete: @escaping (Workspace) -> Void,
        onCollapse: @escaping () -> Void = {},
        onSearch: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {},
        onToggleTelegramBind: @escaping (Workspace) -> Void = { _ in },
        userName: String = "yuminai",
        updateAvailable: Bool = false
    ) {
        self.workspaces = workspaces
        self._selectedId = selectedId
        self.telegramBoundId = telegramBoundId
        self.telegramAvailable = telegramAvailable
        self.onCreate = onCreate
        self.onDelete = onDelete
        self.onCollapse = onCollapse
        self.onSearch = onSearch
        self.onOpenSettings = onOpenSettings
        self.onToggleTelegramBind = onToggleTelegramBind
        self.userName = userName
        self.updateAvailable = updateAvailable
    }

    public var body: some View {
        VStack(spacing: 0) {
            topHeader
            primaryAndMenu
            workspaceList
            Spacer(minLength: 0)
            if updateAvailable {
                UpdateCard()
                    .padding(.horizontal, Theme.Layout.sidebarPadding)
                    .padding(.bottom, Theme.Spacing.sm)
            }
            BottomUserCard(name: userName, onSettings: onOpenSettings)
        }
        .frame(width: Theme.Layout.sidebarWidth)
        .background(Theme.Color.bgSidebar)
    }

    // MARK: - Top header (collapse + search)

    private var topHeader: some View {
        HStack(spacing: 4) {
            IconButton("sidebar.left", help: "사이드바 접기 (⌘⌥1)", action: onCollapse)
            IconButton("magnifyingglass", help: "워크스페이스 검색 (⌘P)", action: onSearch)
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(height: Theme.Layout.toolbarHeight)
    }

    // MARK: - "+ New workspace" + Settings

    private var primaryAndMenu: some View {
        VStack(alignment: .leading, spacing: 1) {
            SidebarPrimaryRow(
                label: "새 워크스페이스",
                icon: "plus",
                action: onCreate
            )
            SidebarMenuRow(
                label: "설정",
                icon: "gear",
                action: onOpenSettings
            )
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.md)
    }

    // MARK: - Workspace list

    private var workspaceList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !workspaces.isEmpty {
                    SidebarGroupHeader("워크스페이스")
                    VStack(spacing: 1) {
                        ForEach(Array(workspaces.enumerated()), id: \.element.id) { index, workspace in
                            WorkspaceItemRow(
                                workspace: workspace,
                                index: index,
                                isSelected: workspace.id == selectedId,
                                isTelegramBound: workspace.id == telegramBoundId,
                                telegramAvailable: telegramAvailable,
                                onSelect: { selectedId = workspace.id },
                                onDelete: { onDelete(workspace) },
                                onToggleTelegramBind: { onToggleTelegramBind(workspace) }
                            )
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.sm)
                } else {
                    EmptyWorkspaceHint(onCreate: onCreate)
                }
            }
        }
    }
}

// MARK: - Sidebar item rows

/// "+ 새 워크스페이스" 같은 primary action.
struct SidebarPrimaryRow: View {
    let label: String
    let icon: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm + 2) {
                Image(systemName: icon)
                    .font(.system(size: Theme.Layout.sidebarIconSize, weight: .semibold))
                    .foregroundStyle(Theme.Color.accent)
                    .frame(width: 16)
                Text(label)
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Color.text)
                Spacer()
            }
            .padding(.horizontal, Theme.Layout.sidebarItemPadH)
            .padding(.vertical, Theme.Layout.sidebarItemPadV)
            .frame(height: Theme.Layout.sidebarItemHeight)
            .background(hovering ? Theme.Color.surfaceHi : .clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .keyboardShortcut("n", modifiers: .command)
    }
}

/// Settings 같은 일반 menu (icon + label).
struct SidebarMenuRow: View {
    let label: String
    let icon: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm + 2) {
                Image(systemName: icon)
                    .font(.system(size: Theme.Layout.sidebarIconSize, weight: .regular))
                    .foregroundStyle(Theme.Color.textSecondary)
                    .frame(width: 16)
                Text(label)
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer()
            }
            .padding(.horizontal, Theme.Layout.sidebarItemPadH)
            .padding(.vertical, Theme.Layout.sidebarItemPadV)
            .frame(height: Theme.Layout.sidebarItemHeight)
            .background(hovering ? Theme.Color.surfaceHi : .clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// 그룹 헤더 ("Workspaces", "Pinned", "Recents" 등).
struct SidebarGroupHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(Theme.Typography.micro)
            .foregroundStyle(Theme.Color.textTertiary)
            .textCase(.uppercase)
            .tracking(0.6)
            .padding(.horizontal, Theme.Layout.sidebarItemPadH + Theme.Spacing.sm)
            .padding(.top, Theme.Layout.sidebarGroupHeaderTop)
            .padding(.bottom, Theme.Spacing.sm)
    }
}

/// 워크스페이스 한 row.
struct WorkspaceItemRow: View {
    let workspace: Workspace
    let index: Int
    let isSelected: Bool
    let isTelegramBound: Bool
    let telegramAvailable: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onToggleTelegramBind: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Theme.Spacing.sm + 2) {
                // Selected dot — ● filled accent / ○ outline subtle
                ZStack {
                    Circle()
                        .stroke(Theme.Color.borderSubtle, lineWidth: 1)
                        .frame(width: Theme.Layout.sidebarDotSize, height: Theme.Layout.sidebarDotSize)
                    if isSelected {
                        Circle()
                            .fill(Theme.Color.accent)
                            .frame(width: Theme.Layout.sidebarDotSize, height: Theme.Layout.sidebarDotSize)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 16)
                .animation(.easeOut(duration: 0.15), value: isSelected)

                Text(workspace.name)
                    .font(Theme.Typography.label)
                    .foregroundStyle(isSelected ? Theme.Color.text : Theme.Color.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if isTelegramBound {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.Color.accent)
                        .help("텔레그램에서 제어 중인 세션")
                        .transition(.scale.combined(with: .opacity))
                }

                Spacer()

                if index < 9 && hovering && !isSelected {
                    Text("⌘\(index + 1)")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, Theme.Layout.sidebarItemPadH)
            .padding(.vertical, Theme.Layout.sidebarItemPadV)
            .frame(height: Theme.Layout.sidebarItemHeight)
            .background(rowBg)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .selectedBar(isSelected)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.10), value: hovering)
            .animation(.easeOut(duration: 0.15), value: isTelegramBound)
        }
        .buttonStyle(PressedScaleStyle(scale: 0.98))
        .onHover { hovering = $0 }
        .contextMenu {
            Button("이름 복사") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(workspace.name, forType: .string)
            }
            if telegramAvailable {
                Divider()
                Button(isTelegramBound ? "텔레그램 연결 해제" : "텔레그램에 연결",
                       systemImage: isTelegramBound ? "paperplane.slash" : "paperplane",
                       action: onToggleTelegramBind)
            }
            Divider()
            Button("지우기", role: .destructive, action: onDelete)
        }
        .accessibilityLabel("\(workspace.name)\(isSelected ? ", 선택됨" : "")\(isTelegramBound ? ", 텔레그램 연결됨" : "")")
        .accessibilityHint("이중 클릭으로 활성화")
    }

    private var rowBg: SwiftUI.Color {
        if isSelected { return Theme.Color.elevated }
        if hovering { return Theme.Color.surfaceHi }
        return .clear
    }
}

/// 워크스페이스 0개일 때 사이드바 본문.
struct EmptyWorkspaceHint: View {
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("아직 시작한 작업이 없네요.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
            Text("위 ‘+ 새 워크스페이스’로 시작해보세요.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textTertiary)
        }
        .padding(.horizontal, Theme.Layout.sidebarPadding)
        .padding(.top, Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Update card

public struct UpdateCard: View {
    public init() {}

    public var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Color.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("업데이트 준비")
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Color.text)
                Text("새 버전이 도착했어요")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Color.textSecondary)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(Theme.Color.borderSubtle, lineWidth: Theme.Stroke.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
    }
}

// MARK: - Bottom user card

public struct BottomUserCard: View {
    public let name: String
    public let onSettings: () -> Void

    public init(name: String, onSettings: @escaping () -> Void) {
        self.name = name
        self.onSettings = onSettings
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Circle()
                .fill(Theme.Color.surfaceHi)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.Color.textSecondary)
                )
                .frame(width: 22, height: 22)
            Text(name)
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Color.text)
            Spacer()
            IconButton("gearshape", size: 14, help: "설정 (⌘,)", action: onSettings)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm + 2)
        .frame(height: 48)
        .overlay(alignment: .top) {
            FlatHDivider()
        }
    }
}
