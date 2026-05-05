import SwiftUI
import UniformTypeIdentifiers
import YuminaiCore

/// 워크스페이스 사이드바 v5 (ADR-076 + ADR-077) — Pin + Folder + Smart folder + Drag/Drop.
///
/// ## 사이드바 구조 (위에서 아래로)
/// 1. **Top header**: collapse / search 버튼
/// 2. **Primary actions**: 새 워크스페이스 / 설정
/// 3. **📌 핀 그룹** (있을 때만, 항상 최상단): drag reorder 가능
/// 4. **🤖 Smart 그룹들**: 활성화된 자동 폴더 (recentWeek, telegramBound 등)
/// 5. **📁 Folder 그룹들**: 사용자가 만든 폴더 (drop target, 색상/아이콘 customization)
/// 6. **Uncategorized 그룹**: 폴더에 안 든 워크스페이스 (drop = 폴더에서 제거)
/// 7. **Update card** (필요 시)
/// 8. **Bottom user card**: 사용자 + 설정
public struct SidebarView: View {
    // ADR-093 Phase 2 — BotStatusDockView popover 상태
    @State private var showBotDockPopover = false

    public let workspaces: [Workspace]
    @Binding public var selectedId: UUID?
    public let telegramBoundId: UUID?
    public let telegramAvailable: Bool
    public let pinnedWorkspaceIds: [UUID]
    public let folders: [WorkspaceFolder]
    /// **ADR-077 Phase 3** — 활성화된 smart folders.
    public let enabledSmartFolders: Set<SmartFolderKind>
    /// **ADR-077 Phase 3** — Smart folder별 매칭 워크스페이스 IDs (호출자가 계산해서 전달).
    public let smartFolderContents: [SmartFolderKind: [UUID]]
    public let onCreate: () -> Void
    public let onDelete: (Workspace) -> Void
    public let onCollapse: () -> Void
    public let onSearch: () -> Void
    public let onOpenSettings: () -> Void
    public let onToggleTelegramBind: (Workspace) -> Void
    public let onConfigureDelivery: (Workspace) -> Void
    public let onEditProjectProfile: (Workspace) -> Void
    public let onTogglePin: (Workspace) -> Void
    public let onToggleFolderExpansion: (UUID) -> Void
    public let onMoveToFolder: (Workspace, UUID?) -> Void
    public let onCreateFolder: () -> Void
    public let onRenameFolder: (WorkspaceFolder) -> Void
    public let onDeleteFolder: (WorkspaceFolder) -> Void
    /// **ADR-077 Phase 4** — Pin 순서 이동 (offset: -1=위, +1=아래).
    public let onMovePin: (Workspace, Int) -> Void
    /// **ADR-077 Phase 4** — Pin drag-to-position (target index).
    public let onMovePinToIndex: (Workspace, Int) -> Void
    /// **ADR-077 Phase 3** — Smart folder 활성/비활성 토글.
    public let onToggleSmartFolder: (SmartFolderKind) -> Void
    /// **ADR-078 Phase 2** — Folder drag reorder (drag-to-position).
    public let onMoveFolderToIndex: (WorkspaceFolder, Int) -> Void
    /// **ADR-078 Phase 2** — Folder 1칸 위/아래 (offset: -1=위, +1=아래).
    public let onReorderFolder: (WorkspaceFolder, Int) -> Void
    // ADR-078 Phase 4 — Tag system
    /// 사용자 정의 태그 목록.
    public let tags: [WorkspaceTag]
    /// 활성 tag 필터 IDs (intersection 적용).
    public let activeTagFilters: Set<UUID>
    /// 워크스페이스별 태그 IDs (filter chip 표시용).
    public let workspaceTagIds: [UUID: Set<UUID>]
    /// Tag 필터 토글 (사이드바 chip click).
    public let onToggleTagFilter: (WorkspaceTag) -> Void
    /// 모든 tag 필터 해제.
    public let onClearTagFilters: () -> Void
    /// 워크스페이스 ↔ tag toggle (context menu).
    public let onToggleWorkspaceTag: (Workspace, WorkspaceTag) -> Void
    /// 새 tag 생성.
    public let onCreateTag: () -> Void
    /// Tag 편집 (이름/색상).
    public let onEditTag: (WorkspaceTag) -> Void
    /// Tag 삭제 (모든 워크스페이스에서 제거).
    public let onDeleteTag: (WorkspaceTag) -> Void
    /// **ADR-106** — 사용자 프로필 (BottomUserCard 표시용).
    public let profile: UserProfile
    /// **ADR-106** — 프로필 편집 sheet 열기.
    public let onEditProfile: () -> Void
    public let updateAvailable: Bool
    /// **ADR-086 Phase 1** — 텔레그램 health snapshot (사이드바 하단 pill 표시용).
    public let telegramHealth: TelegramHealthSnapshot
    /// **ADR-086 Phase 1** — Health pill click → 에러 로그 sheet 열기.
    public let onOpenTelegramErrorLog: () -> Void
    /// **ADR-092 Phase 1** — Telegram Hub sheet 열기.
    public let onOpenTelegramHub: () -> Void
    /// **ADR-114 P0-2** — 자료 라이브러리 sheet 열기 (사이드바 직접 진입).
    public let onOpenLibrary: () -> Void
    /// **ADR-114 P0-2** — 스택 번들 카탈로그 sheet 열기 (사이드바 직접 진입).
    public let onOpenBundles: () -> Void
    /// **ADR-093 Phase 2** — Offline queue depth (BotStatusDockView 표시용).
    public let telegramQueueDepth: Int
    /// **ADR-093 Phase 2** — 봇 목록 (BotStatusDockView 다중 봇 배지).
    public let telegramBotCount: Int
    /// **ADR-093 Phase 2** — 첫 번째 활성 봇 username (BotStatusDockView 레이블).
    public let telegramFirstBotUsername: String?
    /// **ADR-093 Phase 2** — 최근 에러 (BotStatusDockView popover).
    public let telegramRecentErrors: [TelegramErrorEntry]
    /// **ADR-089** — 활성 chat sessions (lastActiveAt desc로 정렬됨).
    public let chatSessions: [ChatSession]
    /// **ADR-089** — 현재 활성 chat session id (강조 표시용).
    public let activeChatSessionId: UUID?
    /// **ADR-089** — 워크스페이스 이름 lookup용 (chatSession.workspaceId → name).
    public let workspaceNameById: (UUID) -> String?
    /// **ADR-089** — 새 대화 세션 만들기 sheet 열기.
    public let onCreateChatSession: () -> Void
    /// **ADR-089** — chat session 클릭 → activate.
    public let onSelectChatSession: (UUID) -> Void
    /// **ADR-089** — chat session 삭제.
    public let onDeleteChatSession: (UUID) -> Void
    /// **ADR-089** — 워크스페이스로 복귀 (활성 chat session 해제).
    public let onDeactivateChatSession: () -> Void
    /// **ADR-091** — 자유 대화에 워크스페이스 attach (또는 nil로 detach).
    public let onAttachChatSessionToWorkspace: (UUID, UUID?) -> Void

    public init(
        workspaces: [Workspace],
        selectedId: Binding<UUID?>,
        telegramBoundId: UUID? = nil,
        telegramAvailable: Bool = false,
        pinnedWorkspaceIds: [UUID] = [],
        folders: [WorkspaceFolder] = [],
        enabledSmartFolders: Set<SmartFolderKind> = [],
        smartFolderContents: [SmartFolderKind: [UUID]] = [:],
        onCreate: @escaping () -> Void,
        onDelete: @escaping (Workspace) -> Void,
        onCollapse: @escaping () -> Void = {},
        onSearch: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {},
        onToggleTelegramBind: @escaping (Workspace) -> Void = { _ in },
        onConfigureDelivery: @escaping (Workspace) -> Void = { _ in },
        onEditProjectProfile: @escaping (Workspace) -> Void = { _ in },
        onTogglePin: @escaping (Workspace) -> Void = { _ in },
        onToggleFolderExpansion: @escaping (UUID) -> Void = { _ in },
        onMoveToFolder: @escaping (Workspace, UUID?) -> Void = { _, _ in },
        onCreateFolder: @escaping () -> Void = {},
        onRenameFolder: @escaping (WorkspaceFolder) -> Void = { _ in },
        onDeleteFolder: @escaping (WorkspaceFolder) -> Void = { _ in },
        onMovePin: @escaping (Workspace, Int) -> Void = { _, _ in },
        onMovePinToIndex: @escaping (Workspace, Int) -> Void = { _, _ in },
        onToggleSmartFolder: @escaping (SmartFolderKind) -> Void = { _ in },
        onMoveFolderToIndex: @escaping (WorkspaceFolder, Int) -> Void = { _, _ in },
        onReorderFolder: @escaping (WorkspaceFolder, Int) -> Void = { _, _ in },
        tags: [WorkspaceTag] = [],
        activeTagFilters: Set<UUID> = [],
        workspaceTagIds: [UUID: Set<UUID>] = [:],
        onToggleTagFilter: @escaping (WorkspaceTag) -> Void = { _ in },
        onClearTagFilters: @escaping () -> Void = {},
        onToggleWorkspaceTag: @escaping (Workspace, WorkspaceTag) -> Void = { _, _ in },
        onCreateTag: @escaping () -> Void = {},
        onEditTag: @escaping (WorkspaceTag) -> Void = { _ in },
        onDeleteTag: @escaping (WorkspaceTag) -> Void = { _ in },
        profile: UserProfile = .default,
        onEditProfile: @escaping () -> Void = {},
        updateAvailable: Bool = false,
        telegramHealth: TelegramHealthSnapshot = TelegramHealthSnapshot(),
        onOpenTelegramErrorLog: @escaping () -> Void = {},
        onOpenTelegramHub: @escaping () -> Void = {},
        onOpenLibrary: @escaping () -> Void = {},
        onOpenBundles: @escaping () -> Void = {},
        telegramQueueDepth: Int = 0,
        telegramBotCount: Int = 0,
        telegramFirstBotUsername: String? = nil,
        telegramRecentErrors: [TelegramErrorEntry] = [],
        chatSessions: [ChatSession] = [],
        activeChatSessionId: UUID? = nil,
        workspaceNameById: @escaping (UUID) -> String? = { _ in nil },
        onCreateChatSession: @escaping () -> Void = {},
        onSelectChatSession: @escaping (UUID) -> Void = { _ in },
        onDeleteChatSession: @escaping (UUID) -> Void = { _ in },
        onDeactivateChatSession: @escaping () -> Void = {},
        onAttachChatSessionToWorkspace: @escaping (UUID, UUID?) -> Void = { _, _ in }
    ) {
        self.workspaces = workspaces
        self._selectedId = selectedId
        self.telegramBoundId = telegramBoundId
        self.telegramAvailable = telegramAvailable
        self.pinnedWorkspaceIds = pinnedWorkspaceIds
        self.folders = folders
        self.enabledSmartFolders = enabledSmartFolders
        self.smartFolderContents = smartFolderContents
        self.onCreate = onCreate
        self.onDelete = onDelete
        self.onCollapse = onCollapse
        self.onSearch = onSearch
        self.onOpenSettings = onOpenSettings
        self.onToggleTelegramBind = onToggleTelegramBind
        self.onConfigureDelivery = onConfigureDelivery
        self.onEditProjectProfile = onEditProjectProfile
        self.onTogglePin = onTogglePin
        self.onToggleFolderExpansion = onToggleFolderExpansion
        self.onMoveToFolder = onMoveToFolder
        self.onCreateFolder = onCreateFolder
        self.onRenameFolder = onRenameFolder
        self.onDeleteFolder = onDeleteFolder
        self.onMovePin = onMovePin
        self.onMovePinToIndex = onMovePinToIndex
        self.onToggleSmartFolder = onToggleSmartFolder
        self.onMoveFolderToIndex = onMoveFolderToIndex
        self.onReorderFolder = onReorderFolder
        self.tags = tags
        self.activeTagFilters = activeTagFilters
        self.workspaceTagIds = workspaceTagIds
        self.onToggleTagFilter = onToggleTagFilter
        self.onClearTagFilters = onClearTagFilters
        self.onToggleWorkspaceTag = onToggleWorkspaceTag
        self.onCreateTag = onCreateTag
        self.onEditTag = onEditTag
        self.onDeleteTag = onDeleteTag
        self.profile = profile
        self.onEditProfile = onEditProfile
        self.updateAvailable = updateAvailable
        self.telegramHealth = telegramHealth
        self.onOpenTelegramErrorLog = onOpenTelegramErrorLog
        self.onOpenTelegramHub = onOpenTelegramHub
        self.onOpenLibrary = onOpenLibrary
        self.onOpenBundles = onOpenBundles
        self.telegramQueueDepth = telegramQueueDepth
        self.telegramBotCount = telegramBotCount
        self.telegramFirstBotUsername = telegramFirstBotUsername
        self.telegramRecentErrors = telegramRecentErrors
        self.chatSessions = chatSessions
        self.activeChatSessionId = activeChatSessionId
        self.workspaceNameById = workspaceNameById
        self.onCreateChatSession = onCreateChatSession
        self.onSelectChatSession = onSelectChatSession
        self.onDeleteChatSession = onDeleteChatSession
        self.onDeactivateChatSession = onDeactivateChatSession
        self.onAttachChatSessionToWorkspace = onAttachChatSessionToWorkspace
    }

    public var body: some View {
        VStack(spacing: 0) {
            topHeader
            primaryAndMenu
            // ADR-078 Phase 4 — Tag filter chip bar (탭이 있을 때만)
            if !tags.isEmpty {
                tagFilterBar
            }
            ScrollView {
                VStack(spacing: 0) {
                    // ADR-089 — 워크스페이스(프로젝트) 명시 라벨
                    sidebarSectionLabel(
                        title: "워크스페이스",
                        subtitle: "프로젝트 (영속)",
                        icon: "folder.fill",
                        color: Theme.Color.accent
                    )
                    workspaceListContent
                    // ADR-089 — Ad-hoc 대화 세션 section (워크스페이스 아래)
                    chatSessionsSection
                }
            }
            Spacer(minLength: 0)
            if updateAvailable {
                UpdateCard()
                    .padding(.horizontal, Theme.Layout.sidebarPadding)
                    .padding(.bottom, Theme.Spacing.sm)
            }
            // ADR-093 Phase 2 — BotStatusDockView (TelegramHealthPill 대체)
            if telegramAvailable || telegramHealth.state != .idle {
                BotStatusDockView(
                    health: telegramHealth,
                    queueDepth: telegramQueueDepth,
                    botCount: telegramBotCount,
                    firstBotUsername: telegramFirstBotUsername,
                    showPopover: $showBotDockPopover,
                    onOpenHub: onOpenTelegramHub,
                    onOpenErrorLog: onOpenTelegramErrorLog,
                    recentErrors: telegramRecentErrors
                )
                .padding(.horizontal, Theme.Layout.sidebarPadding)
                .padding(.bottom, Theme.Spacing.xs)
            }
            BottomUserCard(
                profile: profile,
                onEditProfile: onEditProfile,
                onSettings: onOpenSettings
            )
        }
        .frame(width: Theme.Layout.sidebarWidth)
        .background(Theme.Color.bgSidebar)
    }

    /// **ADR-089** — workspaceList의 ScrollView를 제외한 inner content (재사용용).
    /// 기존 workspaceList는 자체 ScrollView를 가졌으므로, 새 outer ScrollView 안에서
    /// content만 분리.
    private var workspaceListContent: some View {
        // 기존 workspaceList의 body를 재활용 — 단순화 위해 그대로 호출
        // (workspaceList는 이미 ScrollView 포함이므로 frame 제한 적용)
        workspaceList
            .frame(maxHeight: 320)
    }

    // MARK: - ADR-089 + ADR-090 Sidebar 섹션 라벨 (정교화)

    private func sidebarSectionLabel(
        title: String,
        subtitle: String,
        icon: String,
        color: SwiftUI.Color
    ) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 16, height: 16)
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(color)
            }
            .accessibilityHidden(true)
            Text(title)
                .font(Theme.Typography.micro.weight(.semibold))
                .foregroundStyle(Theme.Color.text)
                .textCase(.uppercase)
                .tracking(0.6)
            Text(subtitle)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Theme.Color.surfaceHi.opacity(0.5))
                .clipShape(Capsule())
            Spacer()
        }
        .padding(.horizontal, Theme.Layout.sidebarPadding)
        .padding(.top, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.xs)
    }

    // MARK: - ADR-089 Chat sessions section

    private var chatSessionsSection: some View {
        VStack(spacing: 0) {
            chatSessionsHeader
            if chatSessions.isEmpty {
                chatSessionEmptyHint
            } else {
                if activeChatSessionId != nil {
                    deactivateRow
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                LazyVStack(spacing: 2) {
                    ForEach(chatSessions) { session in
                        // ADR-091 — workspaceId 옵션화 (자유 대화는 nil)
                        // ADR-091 sync — active workspace와 연결 여부 계산
                        ChatSessionRow(
                            session: session,
                            workspaceName: session.workspaceId.flatMap { workspaceNameById($0) },
                            isActive: activeChatSessionId == session.id,
                            availableWorkspaces: workspaces,
                            isLinkedToActiveWorkspace: session.workspaceId == selectedId,
                            willSwitchWorkspace: session.workspaceId != nil && session.workspaceId != selectedId,
                            onSelect: { onSelectChatSession(session.id) },
                            onDelete: { onDeleteChatSession(session.id) },
                            onAttach: { wsId in onAttachChatSessionToWorkspace(session.id, wsId) }
                        )
                    }
                }
                .animation(.spring(response: 0.30, dampingFraction: 0.85), value: activeChatSessionId)
            }
        }
    }

    private var chatSessionsHeader: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 16, height: 16)
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            .accessibilityHidden(true)
            Text("대화 세션")
                .font(Theme.Typography.micro.weight(.semibold))
                .foregroundStyle(Theme.Color.text)
                .textCase(.uppercase)
                .tracking(0.6)
            Text("Ad-hoc")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Theme.Color.surfaceHi.opacity(0.5))
                .clipShape(Capsule())
            if !chatSessions.isEmpty {
                Text("\(chatSessions.count)")
                    .font(Theme.Typography.micro.weight(.medium))
                    .foregroundStyle(Theme.Color.textSecondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Theme.Color.surface)
                    .clipShape(Capsule())
                    .contentTransition(.numericText())
            }
            Spacer()
            Button(action: onCreateChatSession) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.Color.accent)
                    .frame(width: 20, height: 20)
                    .background(Theme.Color.accent.opacity(0.10))
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(Theme.Color.accent.opacity(0.20), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .help("새 대화 세션 (⌘⇧N) — 빠른 질문/실험용")
            .accessibilityLabel("새 대화 세션 만들기")
        }
        .padding(.horizontal, Theme.Layout.sidebarPadding)
        .padding(.top, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.xs)
    }

    private var deactivateRow: some View {
        Button(action: onDeactivateChatSession) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.textSecondary)
                Text("워크스페이스 main 대화로 복귀")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer()
            }
            .padding(.horizontal, Theme.Layout.sidebarPadding)
            .padding(.vertical, 6)
            .background(Theme.Color.surface.opacity(0.5))
            .overlay(alignment: .bottom) { FlatHDivider().opacity(0.4) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("이 워크스페이스의 main 대화로 돌아가기")
    }

    private var chatSessionEmptyHint: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.10))
                    .frame(width: 36, height: 36)
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(.orange)
            }
            Text("아직 대화 세션이 없어요")
                .font(Theme.Typography.small.weight(.medium))
                .foregroundStyle(Theme.Color.textSecondary)
            Button(action: onCreateChatSession) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 10))
                    Text("첫 대화 시작하기")
                        .font(Theme.Typography.small.weight(.medium))
                }
                .foregroundStyle(Theme.Color.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Theme.Color.accent.opacity(0.10))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, Theme.Layout.sidebarPadding)
        .padding(.vertical, Theme.Spacing.md)
    }

    // MARK: - Top header (collapse + search + smart folders menu)

    private var topHeader: some View {
        HStack(spacing: 4) {
            IconButton("sidebar.left", help: "사이드바 접기 (⌘⌥1)", action: onCollapse)
            IconButton("magnifyingglass", help: "워크스페이스 검색 (⌘P)", action: onSearch)
            Spacer()
            // ADR-077 Phase 3 — Smart folders 토글 메뉴
            smartFolderMenu
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(height: Theme.Layout.toolbarHeight)
    }

    private var smartFolderMenu: some View {
        Menu {
            Text("자동 그룹 표시")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
            Divider()
            ForEach(SmartFolderKind.allCases) { kind in
                Button {
                    onToggleSmartFolder(kind)
                } label: {
                    HStack {
                        if enabledSmartFolders.contains(kind) {
                            Image(systemName: "checkmark")
                        }
                        Image(systemName: kind.iconName)
                        Text(kind.displayName)
                    }
                }
            }
        } label: {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(enabledSmartFolders.isEmpty ? Theme.Color.textSecondary : Theme.Color.accent)
                .frame(width: 28, height: 28)
                .background(Theme.Color.surfaceHi.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("자동 그룹 (Smart folders)")
        .accessibilityLabel("자동 그룹 메뉴")
        .accessibilityHint("최근 7일, 텔레그램 연결 등 자동 분류 폴더 표시 토글")
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
                label: "Telegram Hub",
                icon: "paperplane.circle.fill",
                action: onOpenTelegramHub
            )
            // ADR-114 P0-2 — 라이브러리 + 번들 직접 진입 (UserProfileSheet 5단 깊이 제거)
            // ADR-116 — 컬러 이모지 제거, SF Symbol 단색으로 통일
            SidebarMenuRow(
                label: "라이브러리",
                icon: "books.vertical.circle.fill",
                action: onOpenLibrary
            )
            SidebarMenuRow(
                label: "스택 번들",
                icon: "shippingbox.circle.fill",
                action: onOpenBundles
            )
            SidebarMenuRow(
                label: "사용자 가이드",
                icon: "questionmark.circle.fill",
                isExternalLink: true,
                action: { NSWorkspace.shared.open(AppLinks.userGuide) }
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

    // MARK: - ADR-078 Phase 4 — Tag filter chip bar

    private var tagFilterBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("태그")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Spacer()
                if !activeTagFilters.isEmpty {
                    Button("모두 해제", action: onClearTagFilters)
                        .font(Theme.Typography.micro)
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.Color.accent)
                        .accessibilityLabel("태그 필터 모두 해제")
                }
                Button(action: onCreateTag) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .buttonStyle(.plain)
                .help("새 태그 만들기")
                .accessibilityLabel("새 태그 만들기")
            }
            .padding(.horizontal, Theme.Layout.sidebarItemPadH + Theme.Spacing.sm)
            // FlowLayout 대신 ScrollView(.horizontal) — 사이드바 좁아도 모든 tag 접근
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(tags) { tag in
                        tagChip(tag)
                    }
                }
                .padding(.horizontal, Theme.Layout.sidebarItemPadH + Theme.Spacing.sm)
            }
        }
        .padding(.vertical, Theme.Spacing.sm)
    }

    private func tagChip(_ tag: WorkspaceTag) -> some View {
        let isActive = activeTagFilters.contains(tag.id)
        let color = Theme.Color.folderColor(for: tag.colorName)
        return Button {
            onToggleTagFilter(tag)
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(tag.name)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(isActive ? .white : Theme.Color.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(isActive ? color : Theme.Color.surfaceHi)
            .clipShape(Capsule())
            .animation(.easeOut(duration: 0.10), value: isActive)
        }
        .buttonStyle(.plain)
        // ADR-079 Phase 2 — 태그 chip을 workspace row 위로 drag → tag 추가
        .draggable(TagAssignmentPayload(tagId: tag.id))
        .contextMenu {
            Button("이름·색상 편집…", systemImage: "pencil") { onEditTag(tag) }
            Divider()
            Button("태그 삭제 (모든 워크스페이스에서 제거)", systemImage: "trash", role: .destructive) {
                onDeleteTag(tag)
            }
        }
        .accessibilityLabel("\(tag.name) 태그\(isActive ? ", 활성 필터" : "")")
        .accessibilityHint("탭하여 필터 토글. 워크스페이스로 드래그하여 태그 추가. 우클릭으로 편집/삭제.")
    }

    // MARK: - Workspace list

    private var workspacesById: [UUID: Workspace] {
        Dictionary(uniqueKeysWithValues: workspaces.map { ($0.id, $0) })
    }

    private var foldersWorkspaceIds: Set<UUID> {
        Set(folders.flatMap { $0.workspaceIds })
    }

    /// **ADR-078 Phase 4** — tag 필터 적용된 워크스페이스 ID set (nil = 필터 없음).
    private var filteredWorkspaceIds: Set<UUID>? {
        guard !activeTagFilters.isEmpty else { return nil }
        // intersection: 활성된 모든 tag 가진 워크스페이스
        var result: Set<UUID>?
        for tagId in activeTagFilters {
            let wsIds = Set(workspaceTagIds.compactMap { (wsId, tagSet) in
                tagSet.contains(tagId) ? wsId : nil
            })
            if let existing = result {
                result = existing.intersection(wsIds)
            } else {
                result = wsIds
            }
        }
        return result ?? []
    }

    /// **ADR-078 Phase 4** — tag 필터를 통과한 워크스페이스만.
    private var visibleWorkspaces: [Workspace] {
        guard let filtered = filteredWorkspaceIds else { return workspaces }
        return workspaces.filter { filtered.contains($0.id) }
    }

    private var pinnedWorkspaces: [Workspace] {
        pinnedWorkspaceIds.compactMap { workspacesById[$0] }
            .filter { ws in filteredWorkspaceIds?.contains(ws.id) ?? true }
    }

    private var uncategorizedWorkspaces: [Workspace] {
        visibleWorkspaces.filter { !foldersWorkspaceIds.contains($0.id) }
    }

    private func shortcutIndex(of workspaceId: UUID) -> Int? {
        if let pinIdx = pinnedWorkspaces.firstIndex(where: { $0.id == workspaceId }) {
            return pinIdx
        }
        var idx = pinnedWorkspaces.count
        for folder in folders where folder.isExpanded {
            for ws in folder.workspaceIds.compactMap({ workspacesById[$0] }) {
                if ws.id == workspaceId { return idx }
                idx += 1
            }
        }
        for ws in uncategorizedWorkspaces {
            if ws.id == workspaceId { return idx }
            idx += 1
        }
        return nil
    }

    @ViewBuilder
    private var workspaceList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if workspaces.isEmpty {
                    EmptyWorkspaceHint(onCreate: onCreate)
                } else {
                    // 1. Pin 그룹 (drag reorder 활성)
                    if !pinnedWorkspaces.isEmpty {
                        pinSection
                    }
                    // 2. Smart 그룹들 (활성화된 것만, 매칭 워크스페이스가 있을 때만)
                    ForEach(SmartFolderKind.allCases) { kind in
                        if enabledSmartFolders.contains(kind),
                           let ids = smartFolderContents[kind], !ids.isEmpty {
                            smartFolderSection(kind, workspaceIds: ids)
                        }
                    }
                    // 3. 사용자 폴더 그룹들 (drop target — workspace 추가 + 폴더 자체 reorder)
                    ForEach(Array(folders.enumerated()), id: \.element.id) { idx, folder in
                        // ADR-078 Phase 2 — 폴더 위 drop zone (folder reorder)
                        folderDropZone(targetIndex: idx, isVisible: folderDropIndicatorIndex == idx)
                        folderSection(folder, index: idx)
                    }
                    // 마지막 폴더 아래 drop zone
                    if !folders.isEmpty {
                        folderDropZone(targetIndex: folders.count, isVisible: folderDropIndicatorIndex == folders.count)
                    }
                    // 4. Uncategorized (drop = 폴더에서 제거)
                    if !uncategorizedWorkspaces.isEmpty {
                        uncategorizedSection
                    }
                    // 5. "새 폴더 만들기"
                    newFolderButton
                }
            }
        }
    }

    // MARK: - Pin section (ADR-076 + ADR-077 + ADR-078 Phase 1 — line indicator)

    /// **ADR-078 Phase 1** — drop position indicator state.
    /// nil = drop indicator 없음, N = N번째 row 위에 line 표시 (count = 마지막 row 아래).
    @State private var pinDropIndicatorIndex: Int?

    private var pinSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.Color.accent)
                    .accessibilityHidden(true)
                Text("핀")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.6)
            }
            .padding(.horizontal, Theme.Layout.sidebarItemPadH + Theme.Spacing.sm)
            .padding(.top, Theme.Layout.sidebarGroupHeaderTop)
            .padding(.bottom, Theme.Spacing.sm)

            VStack(spacing: 0) {
                ForEach(Array(pinnedWorkspaces.enumerated()), id: \.element.id) { idx, workspace in
                    // ADR-078 Phase 1 — drop zone before this row
                    pinDropZone(targetIndex: idx, isVisible: pinDropIndicatorIndex == idx)
                    workspaceRow(workspace, pinIndex: idx)
                        // ADR-077 Phase 4 — Pin reorder drag
                        .draggable(WorkspacePinReorderPayload(workspaceId: workspace.id, currentIndex: idx))
                }
                // ADR-078 Phase 1 — 마지막 row 아래 drop zone (append 위치)
                pinDropZone(targetIndex: pinnedWorkspaces.count, isVisible: pinDropIndicatorIndex == pinnedWorkspaces.count)
            }
            .padding(.horizontal, Theme.Spacing.sm)
        }
    }

    /// **ADR-078 Phase 1** — pin row 사이/끝의 drop zone.
    /// hover 시 파란 line indicator 표시. drop 시 해당 위치에 insert.
    @ViewBuilder
    private func pinDropZone(targetIndex: Int, isVisible: Bool) -> some View {
        // Drop zone은 6px 높이 — 너무 두꺼우면 사용자에게 어색, 너무 얇으면 hit target 부족
        ZStack {
            Color.clear
                .frame(height: 6)
            if isVisible {
                // Line indicator: 2px 두께 + brand cyan + insets
                Capsule()
                    .fill(Theme.Color.accent)
                    .frame(height: 2)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .transition(.opacity.combined(with: .scale(scale: 1.0, anchor: .center)))
            }
        }
        .contentShape(Rectangle())
        .dropDestination(for: WorkspacePinReorderPayload.self) { items, _ in
            guard let item = items.first,
                  let ws = workspacesById[item.workspaceId] else { return false }
            // pin이 아닌 워크스페이스 (다른 곳에서 온 reorder payload는 무시)
            guard pinnedWorkspaceIds.contains(item.workspaceId) else { return false }
            onMovePinToIndex(ws, targetIndex)
            pinDropIndicatorIndex = nil
            return true
        } isTargeted: { hovering in
            withAnimation(.easeOut(duration: 0.10)) {
                pinDropIndicatorIndex = hovering ? targetIndex : nil
            }
        }
    }

    // MARK: - Smart folder section (ADR-077 Phase 3)

    @ViewBuilder
    private func smartFolderSection(_ kind: SmartFolderKind, workspaceIds: [UUID]) -> some View {
        let smartWorkspaces = workspaceIds.compactMap { workspacesById[$0] }
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: kind.iconName)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.folderColor(for: kind.colorName))
                    .accessibilityHidden(true)
                Text(kind.displayName)
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Color.text)
                Text("\(smartWorkspaces.count)")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Theme.Color.surfaceHi)
                    .clipShape(Capsule())
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 8))
                    .foregroundStyle(Theme.Color.textTertiary)
                    .accessibilityHidden(true)
                Spacer()
            }
            .padding(.horizontal, Theme.Layout.sidebarItemPadH + Theme.Spacing.sm)
            .padding(.top, Theme.Layout.sidebarGroupHeaderTop)
            .padding(.bottom, Theme.Spacing.sm)
            .help(kind.hint)

            VStack(spacing: 1) {
                ForEach(smartWorkspaces) { workspace in
                    workspaceRow(workspace, indented: true)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
        }
    }

    // MARK: - Folder section (drop target — ADR-077 Phase 1 + ADR-078 Phase 2)

    @State private var hoveringFolderId: UUID?
    /// **ADR-078 Phase 2** — folder reorder drop indicator.
    @State private var folderDropIndicatorIndex: Int?

    /// **ADR-078 Phase 2** — folder 사이 drop zone (folder reorder).
    @ViewBuilder
    private func folderDropZone(targetIndex: Int, isVisible: Bool) -> some View {
        ZStack {
            Color.clear.frame(height: 6)
            if isVisible {
                Capsule()
                    .fill(Theme.Color.accent)
                    .frame(height: 2)
                    .padding(.horizontal, Theme.Spacing.md)
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .dropDestination(for: FolderReorderPayload.self) { items, _ in
            guard let item = items.first,
                  let folder = folders.first(where: { $0.id == item.folderId }) else { return false }
            onMoveFolderToIndex(folder, targetIndex)
            folderDropIndicatorIndex = nil
            return true
        } isTargeted: { hovering in
            withAnimation(.easeOut(duration: 0.10)) {
                folderDropIndicatorIndex = hovering ? targetIndex : nil
            }
        }
    }

    @ViewBuilder
    private func folderSection(_ folder: WorkspaceFolder, index: Int) -> some View {
        let isDropTarget = hoveringFolderId == folder.id
        VStack(alignment: .leading, spacing: 0) {
            FolderHeaderRow(
                folder: folder,
                index: index,
                totalCount: folders.count,
                workspaceCount: folder.workspaceIds.count,
                isDropTarget: isDropTarget,
                onToggle: { onToggleFolderExpansion(folder.id) },
                onRename: { onRenameFolder(folder) },
                onDelete: { onDeleteFolder(folder) },
                onMoveUp: { onReorderFolder(folder, -1) },
                onMoveDown: { onReorderFolder(folder, +1) }
            )
            // ADR-078 Phase 2 — folder header를 drag (folder reorder)
            .draggable(FolderReorderPayload(folderId: folder.id, currentIndex: index))
            // ADR-077 Phase 1 — Folder header가 drop target (workspace → folder 추가)
            .dropDestination(for: WorkspaceDragPayload.self) { items, _ in
                guard let item = items.first,
                      let ws = workspacesById[item.workspaceId] else { return false }
                onMoveToFolder(ws, folder.id)
                hoveringFolderId = nil
                return true
            } isTargeted: { hovering in
                hoveringFolderId = hovering ? folder.id : nil
            }

            if folder.isExpanded {
                // ADR-078 Phase 4 — folder 내부에도 tag 필터 적용
                let folderWorkspaces = folder.workspaceIds
                    .compactMap { workspacesById[$0] }
                    .filter { ws in filteredWorkspaceIds?.contains(ws.id) ?? true }
                if folderWorkspaces.isEmpty {
                    Text("(비어있음 — 워크스페이스를 여기로 끌어다 놓으세요)")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                        .padding(.horizontal, Theme.Layout.sidebarItemPadH + Theme.Spacing.lg)
                        .padding(.vertical, Theme.Spacing.xs)
                } else {
                    VStack(spacing: 1) {
                        ForEach(folderWorkspaces) { workspace in
                            workspaceRow(workspace, indented: true)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.sm)
                }
            }
        }
    }

    // MARK: - Uncategorized section (drop = 폴더에서 제거 — ADR-077 Phase 1)

    @State private var hoveringUncategorized: Bool = false

    private var uncategorizedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            uncategorizedHeader
            VStack(spacing: 1) {
                ForEach(uncategorizedWorkspaces) { workspace in
                    workspaceRow(workspace)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
        }
        // ADR-077 Phase 1 — uncategorized 영역에 drop = 폴더에서 제거
        .dropDestination(for: WorkspaceDragPayload.self) { items, _ in
            guard let item = items.first,
                  let ws = workspacesById[item.workspaceId] else { return false }
            onMoveToFolder(ws, nil)
            hoveringUncategorized = false
            return true
        } isTargeted: { hovering in
            hoveringUncategorized = hovering
        }
        .background(hoveringUncategorized ? Theme.Color.surfaceHi.opacity(0.3) : .clear)
        .animation(.easeOut(duration: 0.15), value: hoveringUncategorized)
    }

    @ViewBuilder
    private var uncategorizedHeader: some View {
        let label: String = {
            if !folders.isEmpty || !enabledSmartFolders.isEmpty {
                return "기타 워크스페이스"
            } else if !pinnedWorkspaces.isEmpty {
                return "전체"
            } else {
                return "워크스페이스"
            }
        }()
        Text(label)
            .font(Theme.Typography.micro)
            .foregroundStyle(Theme.Color.textTertiary)
            .textCase(.uppercase)
            .tracking(0.6)
            .padding(.horizontal, Theme.Layout.sidebarItemPadH + Theme.Spacing.sm)
            .padding(.top, Theme.Layout.sidebarGroupHeaderTop)
            .padding(.bottom, Theme.Spacing.sm)
    }

    // MARK: - "새 폴더 만들기"

    private var newFolderButton: some View {
        Button(action: onCreateFolder) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.textTertiary)
                Text("새 폴더 만들기")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textTertiary)
                Spacer()
            }
            .padding(.horizontal, Theme.Layout.sidebarItemPadH + Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, Theme.Spacing.lg)
        .accessibilityLabel("새 폴더 만들기")
    }

    // MARK: - 공통 workspace row

    /// **ADR-091 sync** — 특정 워크스페이스에 연결된 세션 수.
    private func linkedSessionCount(for workspaceId: UUID) -> Int {
        chatSessions.filter { $0.workspaceId == workspaceId }.count
    }

    /// **ADR-091 sync** — active chat session이 이 워크스페이스와 연결돼 있는지.
    private func isLinkedToActiveSession(workspaceId: UUID) -> Bool {
        guard let activeId = activeChatSessionId,
              let activeSession = chatSessions.first(where: { $0.id == activeId }) else {
            return false
        }
        return activeSession.workspaceId == workspaceId
    }

    @ViewBuilder
    private func workspaceRow(_ workspace: Workspace, indented: Bool = false, pinIndex: Int? = nil) -> some View {
        let assignedTagIds = workspaceTagIds[workspace.id] ?? []
        let assignedTags = tags.filter { assignedTagIds.contains($0.id) }
        WorkspaceItemRow(
            workspace: workspace,
            shortcutIndex: shortcutIndex(of: workspace.id),
            pinIndex: pinIndex,
            pinnedTotal: pinnedWorkspaces.count,
            isSelected: workspace.id == selectedId,
            isTelegramBound: workspace.id == telegramBoundId,
            isPinned: pinnedWorkspaceIds.contains(workspace.id),
            telegramAvailable: telegramAvailable,
            indented: indented,
            availableFolders: folders,
            currentFolderId: folders.first(where: { $0.workspaceIds.contains(workspace.id) })?.id,
            // ADR-078 Phase 4 — tag context menu + indicator
            allTags: tags,
            assignedTags: assignedTags,
            // ADR-091 sync — 연결된 세션 정보
            linkedSessionCount: linkedSessionCount(for: workspace.id),
            isLinkedToActiveSession: isLinkedToActiveSession(workspaceId: workspace.id),
            onSelect: { selectedId = workspace.id },
            onDelete: { onDelete(workspace) },
            onToggleTelegramBind: { onToggleTelegramBind(workspace) },
            onConfigureDelivery: { onConfigureDelivery(workspace) },
            onEditProjectProfile: { onEditProjectProfile(workspace) },
            onTogglePin: { onTogglePin(workspace) },
            onMoveToFolder: { folderId in onMoveToFolder(workspace, folderId) },
            onCreateNewFolder: onCreateFolder,
            onMovePinUp: pinIndex != nil ? { onMovePin(workspace, -1) } : nil,
            onMovePinDown: pinIndex != nil ? { onMovePin(workspace, +1) } : nil,
            onToggleTag: { tag in onToggleWorkspaceTag(workspace, tag) },
            onCreateNewTag: onCreateTag
        )
        .modifier(WorkspaceDragModifier(workspaceId: workspace.id, isPinReorder: pinIndex != nil))
        // ADR-079 Phase 2 — tag drop target (chip → workspace = tag 추가)
        .dropDestination(for: TagAssignmentPayload.self) { items, _ in
            guard let item = items.first,
                  let tag = tags.first(where: { $0.id == item.tagId }) else { return false }
            onToggleWorkspaceTag(workspace, tag)
            return true
        }
    }
}

// MARK: - ADR-090 ChatSessionRow (별도 component로 분리 — 호버 state 격리)

private struct ChatSessionRow: View {
    let session: ChatSession
    let workspaceName: String?
    let isActive: Bool
    let availableWorkspaces: [Workspace]
    /// **ADR-091 sync** — 이 세션의 workspaceId가 현재 active workspace와 일치하는지.
    /// true이면 워크스페이스 row와 동일한 accent 색상 그룹으로 표시.
    let isLinkedToActiveWorkspace: Bool
    /// **ADR-091 sync** — 이 세션을 클릭하면 워크스페이스 전환이 발생하는지.
    /// (session.workspaceId != nil && session.workspaceId != currentSelectedId)
    let willSwitchWorkspace: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onAttach: (UUID?) -> Void  // ADR-091 — nil이면 detach
    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 8) {
                ZStack {
                    Circle()
                        .fill(session.agentKind.brandMutedColor)
                        .frame(width: 22, height: 22)
                    Image(systemName: session.agentKind.icon)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(session.agentKind.brandColor)
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.title)
                        .font(Theme.Typography.small.weight(isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? Theme.Color.text : Theme.Color.textSecondary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        // ADR-091 — 자유 대화는 다른 아이콘 + 안내
                        Image(systemName: locationIcon)
                            .font(.system(size: 7))
                            .foregroundStyle(locationColor)
                        Text(locationLabel)
                            .font(Theme.Typography.micro)
                            .foregroundStyle(locationColor)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if !session.savedMessages.isEmpty {
                    Text("\(session.savedMessages.count)")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Theme.Color.surface)
                        .clipShape(Capsule())
                        .accessibilityLabel("메시지 \(session.savedMessages.count)개")
                }
            }
            .padding(.horizontal, Theme.Layout.sidebarPadding)
            .padding(.vertical, 6)
            .background(rowBackground)
            .overlay(alignment: .leading) {
                if isActive {
                    // 활성 세션: 완전한 accent bar
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Theme.Color.accent, Theme.Color.accent.opacity(0.6)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 3)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                } else if isLinkedToActiveWorkspace {
                    // ADR-091 sync — active workspace와 연결된 비활성 세션: 얇은 muted accent strip
                    Rectangle()
                        .fill(Theme.Color.accent.opacity(0.40))
                        .frame(width: 2)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            // ADR-091 sync — hover 시 워크스페이스 전환 여부 추가 안내
            .overlay(alignment: .trailing) {
                if isHovering && willSwitchWorkspace && !isActive {
                    Image(systemName: "arrow.right.square.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.Color.accent.opacity(0.70))
                        .padding(.trailing, Theme.Layout.sidebarPadding)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu {
            // ADR-091 — 워크스페이스 attach/change/detach
            if availableWorkspaces.isEmpty {
                Text("워크스페이스 없음 — 먼저 만드세요")
            } else {
                Menu("워크스페이스 지정", systemImage: "folder.badge.gearshape") {
                    if !session.isFreeChat {
                        Button("자유 대화로 변경 (경로 해제)", systemImage: "bubble.left.and.bubble.right") {
                            onAttach(nil)
                        }
                        Divider()
                    }
                    ForEach(availableWorkspaces) { ws in
                        Button {
                            onAttach(ws.id)
                        } label: {
                            HStack {
                                if session.workspaceId == ws.id {
                                    Image(systemName: "checkmark")
                                }
                                Image(systemName: "folder.fill")
                                Text(ws.name)
                            }
                        }
                    }
                }
            }
            Divider()
            Button("삭제", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .help(rowHelp)
        .accessibilityLabel("\(session.title), \(workspaceName ?? "삭제된 워크스페이스"), \(session.agentKind.displayName)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .animation(.easeOut(duration: 0.10), value: isHovering)
        .animation(.spring(response: 0.30, dampingFraction: 0.85), value: isActive)
    }

    private var rowBackground: Color {
        if isActive {
            return Theme.Color.accent.opacity(0.10)
        } else if isLinkedToActiveWorkspace {
            // ADR-091 sync — active workspace 연결 세션은 미묘한 tint
            return Theme.Color.accent.opacity(0.05)
        } else if isHovering {
            return Theme.Color.surfaceHi.opacity(0.7)
        } else {
            return Color.clear
        }
    }

    /// **ADR-091 sync** — hover tooltip: 워크스페이스 전환 여부 안내.
    private var rowHelp: String {
        let base = "\(session.title) — \(session.subtitle(workspaceName: workspaceName))"
        if session.isFreeChat {
            return "\(base) (클릭해도 워크스페이스 전환 없음)"
        } else if willSwitchWorkspace, let name = workspaceName {
            return "\(base) → [\(name)]으로 전환됩니다"
        }
        return base
    }

    /// **ADR-091** — 위치 표시 아이콘/색상/라벨 (워크스페이스 / 자유 대화 / 삭제됨).
    private var locationIcon: String {
        if session.isFreeChat { return "bubble.left.and.bubble.right" }
        if workspaceName == nil { return "exclamationmark.triangle.fill" }
        return "folder.fill"
    }

    private var locationColor: Color {
        if session.isFreeChat { return .purple }
        if workspaceName == nil { return Theme.Color.warning }
        return Theme.Color.textTertiary
    }

    private var locationLabel: String {
        if session.isFreeChat { return "자유 대화 (경로 미지정)" }
        return workspaceName ?? "(삭제된 워크스페이스)"
    }
}

/// **ADR-077 Phase 1** — pin index 유무에 따라 다른 draggable payload 적용.
struct WorkspaceDragModifier: ViewModifier {
    let workspaceId: UUID
    let isPinReorder: Bool

    func body(content: Content) -> some View {
        if isPinReorder {
            // pinSection에서 별도로 .draggable(.pinReorder) 적용 → 여기선 no-op
            content
        } else {
            content.draggable(WorkspaceDragPayload(workspaceId: workspaceId))
        }
    }
}

// MARK: - FolderHeaderRow (ADR-077 Phase 2 — 색상/아이콘 + drop target highlight)

struct FolderHeaderRow: View {
    let folder: WorkspaceFolder
    /// **ADR-078 Phase 2** — folder의 현재 index (위/아래 메뉴 enable 결정).
    let index: Int
    let totalCount: Int
    let workspaceCount: Int
    let isDropTarget: Bool
    let onToggle: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    /// **ADR-078 Phase 2** — folder 1칸 위/아래 이동.
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.Color.textSecondary)
                    .rotationEffect(.degrees(folder.isExpanded ? 90 : 0))
                    .frame(width: 12)
                Image(systemName: folder.iconName)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.folderColor(for: folder.colorName))
                    .frame(width: 14)
                Text(folder.name)
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Color.text)
                    .lineLimit(1)
                Text("\(workspaceCount)")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Theme.Color.surfaceHi)
                    .clipShape(Capsule())
                Spacer()
            }
            .padding(.horizontal, Theme.Layout.sidebarItemPadH + Theme.Spacing.xs)
            .padding(.vertical, Theme.Layout.sidebarItemPadV + 1)
            .background(
                isDropTarget
                    ? Theme.Color.folderColor(for: folder.colorName).opacity(0.18)
                    : (hovering ? Theme.Color.surfaceHi.opacity(0.5) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .stroke(
                        isDropTarget ? Theme.Color.folderColor(for: folder.colorName) : .clear,
                        lineWidth: 2
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.15), value: folder.isExpanded)
            .animation(.easeOut(duration: 0.10), value: hovering)
            .animation(.easeOut(duration: 0.15), value: isDropTarget)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.xs)
        .contextMenu {
            Button("이름·색상·아이콘 편집…", systemImage: "pencil", action: onRename)
            // ADR-078 Phase 2 — folder reorder menu
            Divider()
            Button("위로 이동", systemImage: "chevron.up", action: onMoveUp)
                .disabled(index == 0)
            Button("아래로 이동", systemImage: "chevron.down", action: onMoveDown)
                .disabled(index >= totalCount - 1)
            Divider()
            Button("폴더 삭제 (안의 워크스페이스는 유지)", systemImage: "folder.badge.minus", role: .destructive, action: onDelete)
        }
        .accessibilityLabel("폴더 \(folder.name), \(workspaceCount)개 워크스페이스, \(folder.isExpanded ? "펼쳐짐" : "접힘")\(isDropTarget ? ", 드롭 가능" : "")")
        .accessibilityHint("탭하여 펼치거나 접습니다. 워크스페이스를 끌어다 놓으면 폴더에 추가됩니다. 폴더 자체를 끌어 순서 변경 가능.")
    }
}

// MARK: - Sidebar item rows (ADR-076 + ADR-077 — pin reorder menu)

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

struct SidebarMenuRow: View {
    let label: String
    let icon: String
    let action: () -> Void
    /// trailing 외부 링크 인디케이터 (`arrow.up.forward.square`). 클릭 시 외부 URL/브라우저로 이동함을 암시.
    let isExternalLink: Bool

    @State private var hovering = false

    init(
        label: String,
        icon: String,
        isExternalLink: Bool = false,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.icon = icon
        self.isExternalLink = isExternalLink
        self.action = action
    }

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
                if isExternalLink {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(hovering ? Theme.Color.accent : Theme.Color.textTertiary)
                        .accessibilityLabel("외부 링크")
                }
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

struct WorkspaceItemRow: View {
    let workspace: Workspace
    let shortcutIndex: Int?
    let pinIndex: Int?
    let pinnedTotal: Int
    let isSelected: Bool
    let isTelegramBound: Bool
    let isPinned: Bool
    let telegramAvailable: Bool
    let indented: Bool
    let availableFolders: [WorkspaceFolder]
    let currentFolderId: UUID?
    /// **ADR-078 Phase 4** — 사용자 정의 모든 tag.
    let allTags: [WorkspaceTag]
    /// **ADR-078 Phase 4** — 이 워크스페이스에 적용된 tag.
    let assignedTags: [WorkspaceTag]
    /// **ADR-091 sync** — 이 워크스페이스에 연결된 채팅 세션 수 (0이면 배지 숨김).
    let linkedSessionCount: Int
    /// **ADR-091 sync** — 이 워크스페이스가 현재 활성 세션과 연결돼 있는지 (동일 accent pair).
    let isLinkedToActiveSession: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onToggleTelegramBind: () -> Void
    let onConfigureDelivery: () -> Void
    let onEditProjectProfile: () -> Void
    let onTogglePin: () -> Void
    let onMoveToFolder: (UUID?) -> Void
    let onCreateNewFolder: () -> Void
    let onMovePinUp: (() -> Void)?
    let onMovePinDown: (() -> Void)?
    /// **ADR-078 Phase 4** — tag toggle.
    let onToggleTag: (WorkspaceTag) -> Void
    /// **ADR-078 Phase 4** — 새 tag 만들기.
    let onCreateNewTag: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Theme.Spacing.sm + 2) {
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
                .accessibilityHidden(true)

                Text(workspace.name)
                    .font(Theme.Typography.label)
                    .foregroundStyle(isSelected ? Theme.Color.text : Theme.Color.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.Color.accent)
                        .accessibilityHidden(true)
                }

                if isTelegramBound {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.Color.accent)
                        .help("텔레그램에서 제어 중인 세션")
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityHidden(true)
                }

                // ADR-091 sync — 연결된 세션 수 배지
                if linkedSessionCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "bubble.left.fill")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(isLinkedToActiveSession ? Theme.Color.accent : Theme.Color.textTertiary)
                        Text("\(linkedSessionCount)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(isLinkedToActiveSession ? Theme.Color.accent : Theme.Color.textTertiary)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        isLinkedToActiveSession
                            ? Theme.Color.accent.opacity(0.12)
                            : Theme.Color.surfaceHi.opacity(0.8)
                    )
                    .clipShape(Capsule())
                    .help("연결된 대화 세션 \(linkedSessionCount)개\(isLinkedToActiveSession ? " (현재 활성 세션 포함)" : "")")
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                    .animation(.spring(response: 0.25, dampingFraction: 0.80), value: isLinkedToActiveSession)
                    .accessibilityLabel("연결된 세션 \(linkedSessionCount)개")
                }

                // ADR-078 Phase 4 — assigned tag dots (max 3 표시)
                if !assignedTags.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(assignedTags.prefix(3)) { tag in
                            Circle()
                                .fill(Theme.Color.folderColor(for: tag.colorName))
                                .frame(width: 5, height: 5)
                                .help(tag.name)
                        }
                        if assignedTags.count > 3 {
                            Text("+\(assignedTags.count - 3)")
                                .font(.system(size: 8))
                                .foregroundStyle(Theme.Color.textTertiary)
                        }
                    }
                    .accessibilityHidden(true)
                }

                Spacer()

                if let idx = shortcutIndex, idx < 9 && hovering && !isSelected {
                    Text("⌘\(idx + 1)")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                        .transition(.opacity)
                }
            }
            .padding(.leading, indented ? Theme.Layout.sidebarItemPadH + Theme.Spacing.lg : Theme.Layout.sidebarItemPadH)
            .padding(.trailing, Theme.Layout.sidebarItemPadH)
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
            // Pin 토글
            Button(
                isPinned ? "상단 고정 해제" : "상단에 고정",
                systemImage: isPinned ? "pin.slash" : "pin",
                action: onTogglePin
            )
            // ADR-077 Phase 4 — Pin 순서 이동 (pin 그룹 안에서만)
            if let onMovePinUp, let pinIdx = pinIndex {
                Divider()
                Button("위로 이동", systemImage: "chevron.up", action: onMovePinUp)
                    .disabled(pinIdx == 0)
                if let onMovePinDown {
                    Button("아래로 이동", systemImage: "chevron.down", action: onMovePinDown)
                        .disabled(pinIdx >= pinnedTotal - 1)
                }
            }
            // 폴더 이동
            Menu {
                Button("폴더에서 제거 (전체로)", systemImage: "tray.and.arrow.up") {
                    onMoveToFolder(nil)
                }
                .disabled(currentFolderId == nil)
                Divider()
                ForEach(availableFolders) { folder in
                    Button {
                        onMoveToFolder(folder.id)
                    } label: {
                        HStack {
                            if folder.id == currentFolderId {
                                Image(systemName: "checkmark")
                            }
                            Image(systemName: folder.iconName)
                            Text(folder.name)
                        }
                    }
                }
                if !availableFolders.isEmpty {
                    Divider()
                }
                Button("새 폴더 만들기…", systemImage: "folder.badge.plus", action: onCreateNewFolder)
            } label: {
                Label("폴더로 이동", systemImage: "folder")
            }
            // ADR-078 Phase 4 — 태그 toggle submenu
            Menu {
                if allTags.isEmpty {
                    Text("등록된 태그 없음")
                } else {
                    ForEach(allTags) { tag in
                        let assigned = assignedTags.contains(tag)
                        Button {
                            onToggleTag(tag)
                        } label: {
                            HStack {
                                if assigned {
                                    Image(systemName: "checkmark")
                                }
                                Image(systemName: "tag.fill")
                                Text(tag.name)
                            }
                        }
                    }
                    Divider()
                }
                Button("새 태그 만들기…", systemImage: "plus", action: onCreateNewTag)
            } label: {
                Label("태그", systemImage: "tag")
            }
            Divider()
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
            Button("Delivery 자동화 설정…",
                   systemImage: "checkmark.shield",
                   action: onConfigureDelivery)
            Button("프로젝트 프로필 편집…",
                   systemImage: "rectangle.stack.fill",
                   action: onEditProjectProfile)
            Divider()
            Button("지우기", role: .destructive, action: onDelete)
        }
        .accessibilityLabel("\(workspace.name)\(isSelected ? ", 선택됨" : "")\(isPinned ? ", 고정됨" : "")\(isTelegramBound ? ", 텔레그램 연결됨" : "")")
        .accessibilityHint("이중 클릭으로 활성화. 우클릭으로 메뉴. 끌어서 폴더로 이동.")
    }

    private var rowBg: SwiftUI.Color {
        if isSelected { return Theme.Color.elevated }
        // ADR-091 sync — active session과 연결된 워크스페이스는 subtle tint 적용
        if isLinkedToActiveSession { return Theme.Color.accent.opacity(0.06) }
        if hovering { return Theme.Color.surfaceHi }
        return .clear
    }
}

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

// MARK: - Update card / Bottom user card (변경 없음)

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

public struct BottomUserCard: View {
    public let profile: UserProfile
    public let onEditProfile: () -> Void
    public let onSettings: () -> Void

    public init(
        profile: UserProfile,
        onEditProfile: @escaping () -> Void,
        onSettings: @escaping () -> Void
    ) {
        self.profile = profile
        self.onEditProfile = onEditProfile
        self.onSettings = onSettings
    }

    public var body: some View {
        Button(action: onEditProfile) {
            HStack(spacing: Theme.Spacing.md) {
                profileAvatar
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.displayName)
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Color.text)
                        .lineLimit(1)
                    if !profile.jobTitle.isEmpty {
                        Text(profile.jobTitle)
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                IconButton("gearshape", size: 14, help: "설정 (⌘,)", action: onSettings)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm + 2)
            .frame(height: 48)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            FlatHDivider()
        }
        .help("프로필 편집")
    }

    @ViewBuilder
    private var profileAvatar: some View {
        if let path = profile.profileImagePath,
           let nsImage = NSImage(contentsOfFile: path) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
                .frame(width: 22, height: 22)
                .clipShape(Circle())
        } else {
            let initial = profile.displayName.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? ""
            Circle()
                .fill(Theme.Color.surfaceHi)
                .overlay {
                    if initial.isEmpty {
                        Image(systemName: "person.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.Color.textSecondary)
                    } else {
                        Text(initial.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                }
                .frame(width: 22, height: 22)
        }
    }
}
