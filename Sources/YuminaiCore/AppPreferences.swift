import Foundation

/// 앱 글로벌 설정. 시크릿이 아닌 메타데이터만. (시크릿은 KeychainStore.)
///
/// `UserDefaults` 등에 저장되며 SettingsView에서 편집된다.
public struct AppPreferences: Sendable, Codable, Hashable {
    public var claudeBinaryPath: String
    public var codexBinaryPath: String
    public var defaultSessionSettings: SessionSettings
    public var editPreferences: EditPreferences
    public var obsidianVaultPath: String?
    public var telegramEnabled: Bool
    public var telegramAllowedUserIds: [Int64]
    public var telegramChatId: Int64?
    public var telegramAlertPolicy: TelegramAlertPolicy
    /// cokacdir bot import 시 어떤 봇에서 가져왔는지 표시 (display_name).
    /// nil이면 직접 입력 모드.
    public var telegramSourceLabel: String?
    /// 텔레그램에서 직접 제어할 워크스페이스 (1개). nil이면 미연결.
    /// **ADR-058 Phase 3** — 1:1 binding (legacy). 멀티 chat 시에는 telegramChatBindings 우선 사용.
    public var telegramBoundWorkspaceId: UUID?
    /// **ADR-058 Phase 3** — chat ID → workspace UUID multi-mapping.
    /// 멀티 chat에서 각각 다른 워크스페이스 binding 가능 (chat A=웹앱, chat B=모바일앱).
    /// telegramBoundWorkspaceId는 fallback (멀티 mapping에 없는 chat용).
    public var telegramChatBindings: [String: UUID]  // chatId(string) → workspaceId
    /// 텔레그램으로 어시스턴트 응답을 forward할지 여부.
    public var telegramForwardAssistant: Bool
    /// 텔레그램으로 도구 호출 요약을 forward할지 여부.
    public var telegramForwardToolCalls: Bool
    /// ADR-046 — 외부 (텔레그램에서 시작된) turn은 plan-mode 강제로 destructive 작업 confirm 요구.
    /// **default true** (안전 기본값) — 외부 사용자는 PC confirm 모달을 못 보므로 plan을 보고 후속 turn으로 승인해야 안전.
    public var telegramRemoteRequiresPlan: Bool
    /// ADR-046 — 외부 turn 알림에 누적 비용/컨텍스트 표시 여부 (status banner).
    /// **default true** — 비용 자각 ↑.
    public var telegramShowCostInline: Bool
    /// ADR-048 Phase 3 — Harness 자동 routing 활성. 사용자 입력 keyword 분석 후
    /// 적합한 모델로 자동 pane 전환 + handoff prompt 자동 inject.
    /// **default false** — 명시 opt-in (사용자 인지 후 활성)
    public var harnessAutoRoutingEnabled: Bool
    /// ADR-049 Phase 5 — Inspector에 Harness conversation view + TaskGraph mini-map 표시.
    /// **default false** — 전통 multi-pane이 default. 옵트인하면 Inspector에 'Harness' 탭 추가.
    public var harnessUIEnabled: Bool
    /// ADR-051 — 자동 routing 전 N초 cancel countdown (사용자 신뢰 ↑).
    /// 0이면 즉시 routing (이전 동작). 3 권장.
    public var harnessRoutingCountdownSeconds: Int
    /// ADR-051 — Harness inline mode: 메인 chat area를 HarnessConversationView로 교체.
    /// **default false** — 전통 ChatView가 default.
    public var harnessInlineModeEnabled: Bool
    /// ADR-052 — Routing decision log raw prompt 저장 toggle. **default false**.
    /// 켜면 disk에 raw prompt까지 저장 (privacy 위험). 끄면 80자 prefix만.
    public var routingLogRawPrompts: Bool
    /// ADR-052 — Routing decision log retention (in-memory). default 7일.
    /// disk file은 별도 manual cleanup 필요.
    public var routingLogRetentionDays: Int
    /// ADR-052 — Multi-agent 병렬 실행 활성. **default false** (Cognition 권고: parallel = fragile).
    /// 켜면 TaskGraph의 disjoint task를 두 pane에서 동시 실행 가능.
    public var multiAgentParallelEnabled: Bool
    /// **ADR-056 Phase 4** — global per-day cost cap (USD). nil이면 무제한.
    /// 도달 시 외부 turn은 차단 (PC turn은 그대로). 매일 자정 reset.
    public var dailyBudgetUSD: Double?
    /// **ADR-059 Phase 5** — workspace별 per-day cost cap. workspaceId → USD.
    /// 비어있으면 dailyBudgetUSD (global) 사용. 우선 순위: workspace > global.
    public var workspaceDailyBudgetsUSD: [UUID: Double]
    /// **ADR-059 Phase 5** — workspace별 today cost 누적 (자정 reset).
    /// disk persist X (메모리만) — 영속 필요 시 향후 별도 store.
    /// 단, codable 안 — 따로 transient field로 처리.
    /// **ADR-058 Phase 5** — 컨텍스트가 이 % 도달하면 자동 새 세션 시작 (옵션).
    /// nil이면 비활성. 0.0~1.0 (예: 0.85 = 85%)
    /// **default nil** — 사용자 의도와 다를 수 있으므로 명시적 활성 권장.
    public var autoNewSessionContextThreshold: Double?
    /// **ADR-066 Phase 2** — Z-score anomaly detection threshold.
    /// 일반적으로 2.0 (95%) 또는 3.0 (99.7%). default 2.0.
    public var anomalyZScoreThreshold: Double
    /// pane 응답에 `@<other>` mention이 있으면 자동으로 다음 turn dispatch (ADR-034 A1).
    /// **default OFF** — 무한 루프 위험, 명시적 토글 필요.
    public var agentChainEnabled: Bool
    /// chain max hops — 0이면 비활성. default 1 (한 번만 자동 답장).
    public var agentChainMaxHops: Int
    public var fontSizeOffset: Int
    public var showInspectorByDefault: Bool
    /// **ADR-071 Phase 1** — 초보자 모드. 켜면 고급 설정 탭/섹션이 숨겨져 첫 사용자 친화적.
    /// - 새 설치: default `true` (init 기본값)
    /// - 기존 사용자 (저장된 JSON에 필드 없음): default `false` (Codable decode에서 덮어씀)
    /// 숨겨지는 항목:
    /// - 자동화 탭 (Harness + Agent Chain)
    /// - 자동 선택 학습 탭
    /// - 모델·모드 탭의 최대 비용 입력
    /// - 텔레그램 탭의 cokacdir 통합 + 외부 사용 안전 일부
    public var beginnerMode: Bool
    /// **ADR-072 Phase 4** — 첫 실행 wizard 완료 여부.
    /// false면 SplashScreen 후 OnboardingWizard 표시.
    public var hasCompletedOnboarding: Bool
    /// **ADR-076 Phase 1** — 사이드바 상단에 고정된 워크스페이스 IDs.
    /// 고정된 항목들은 폴더와 무관하게 사이드바 최상단 "핀" 그룹에 표시.
    /// Set 대신 Array — 사용자가 핀 순서를 정렬 가능 (기본: pin 순서).
    public var pinnedWorkspaceIds: [UUID]
    /// **ADR-076 Phase 1** — 워크스페이스 폴더 (Codex CLI 스타일 그룹화).
    /// 한 워크스페이스는 0~1개 폴더에만 속할 수 있음 (folder.workspaceIds로 추적).
    public var workspaceFolders: [WorkspaceFolder]
    /// **ADR-077 Phase 3** — 활성화된 smart folder kinds.
    /// 신규 사용자: `[.recentWeek]` (가장 유용). 기존 사용자: 빈 set.
    public var enabledSmartFolders: Set<SmartFolderKind>
    /// **ADR-078 Phase 4** — 사용자 정의 태그 목록.
    public var workspaceTags: [WorkspaceTag]
    /// **ADR-078 Phase 4** — 워크스페이스 ↔ 태그 매핑 (many-to-many).
    public var tagAssignments: WorkspaceTagAssignments
    /// **ADR-078 Phase 4** — 사이드바에서 활성화된 tag 필터 (intersection 방식).
    /// 비어있으면 필터 없음 (전체 표시).
    public var activeTagFilters: Set<UUID>
    /// **ADR-079 Phase 1** — 저장된 smart filter 목록 (사용자가 자주 쓰는 tag 조합).
    public var smartFilters: [SmartFilter]
    /// **ADR-079 Phase 3** — iCloud sync 활성 여부.
    /// 켜면 preferences가 NSUbiquitousKeyValueStore에 자동 동기화 (다른 PC와).
    public var iCloudSyncEnabled: Bool
    /// **ADR-084 Phase 1** — 텔레그램 응답 detail 레벨 (default: standard).
    public var telegramResponseMode: TelegramResponseMode
    /// **ADR-084 Phase 2** — 텔레그램 토큰/비용 budget.
    public var telegramTokenBudget: TelegramTokenBudget
    /// **ADR-084 Phase 3** — 첨부파일 정책.
    public var telegramAttachmentPolicy: TelegramAttachmentPolicy
    /// **ADR-084 Phase 4** — 사용자 정의 skills (default 4개로 시작).
    public var telegramSkills: [TelegramSkill]
    /// **ADR-086 Phase 3** — Multi-bot configs (그룹 운영).
    public var telegramBots: [TelegramBotConfig]
    /// **ADR-086 Phase 3** — Bot groups.
    public var telegramBotGroups: [TelegramBotGroup]
    /// **ADR-086 Phase 3** — Bot ↔ chat ↔ workspace 3-way bindings.
    public var telegramBotChatBindings: [BotChatBinding]
    /// **ADR-086 Phase 2** — Rate limit 알림 설정.
    public var telegramRateLimitAlert: RateLimitAlertConfig
    /// **ADR-086 Phase 5** — Update receiving mode.
    public var telegramUpdateMode: TelegramUpdateMode
    /// **ADR-086 Phase 5** — Webhook URL (mode == .webhook 시 사용).
    public var telegramWebhookURL: String?
    /// **ADR-089** — Ad-hoc 대화 세션 목록 (워크스페이스와 별개).
    public var chatSessions: [ChatSession]
    /// **ADR-089** — 현재 활성 ChatSession ID (nil이면 워크스페이스 main 대화).
    public var activeChatSessionId: UUID?
    /// **ADR-094 Phase 3** — BotFather에 등록할 커맨드 목록.
    /// 기존 사용자는 7개 기본 커맨드로 시작 (decodeIfPresent ?? defaultTelegramCommands).
    public var telegramCommands: [TelegramCommand]
    /// **ADR-095 Phase 4** — 다중 디바이스 알림 정책 매트릭스.
    /// 기존 사용자는 default 정책으로 시작.
    public var notificationPolicy: NotificationPolicyMatrix
    /// **ADR-095 Phase 4** — Quiet hours 시작 시각 (0-23). nil이면 비활성.
    public var quietHoursStart: Int?
    /// **ADR-095 Phase 4** — Quiet hours 종료 시각 (0-23). nil이면 비활성.
    public var quietHoursEnd: Int?
    /// **ADR-095 Phase 4** — HITL 타임아웃 (초). 기본 60초.
    public var hitlTimeoutSeconds: Int
    /// **ADR-095 Phase 4** — Diff 미리보기 라인 한도. 기본 30줄.
    public var diffPreviewLineLimit: Int
    /// **ADR-104** — 첫 실행 setup wizard 완료 여부.
    /// false이면 onboarding 완료 후 SetupWizardSheet 자동 표시.
    public var hasCompletedSetup: Bool
    /// **ADR-106** — 사용자 프로필 (이름·직업·목표 등).
    /// 기존 사용자는 .default (빈 프로필) 로 시작.
    public var userProfile: UserProfile
    /// **ADR-111** — 자료 라이브러리 항목 목록.
    /// 기존 사용자는 빈 배열로 시작 (backward-compat: decodeIfPresent ?? []).
    public var libraryItems: [ResourceLibraryItem]
    /// **ADR-119** — GitHub PAT가 Keychain에 저장됐는지 (UI 표시용 메타).
    /// 실제 토큰은 Keychain에만 저장. 기존 사용자는 false 로 시작.
    public var hasGitHubPAT: Bool
    /// **ADR-122 Phase 3** — GitHub 검색 히스토리 (ring buffer 50개).
    /// 기존 사용자는 빈 배열로 시작.
    public var githubSearchHistory: [GitHubSearchHistoryEntry]
    /// **ADR-122 Phase 3** — GitHub 즐겨찾기 검색어.
    /// 기존 사용자는 빈 배열로 시작.
    public var githubSearchFavorites: [GitHubSearchFavorite]
    /// **ADR-132** — 자동 실행 설정.
    /// 기존 사용자는 default (disabled)로 시작.
    public var autoRunConfig: AutoRunConfig
    /// **ADR-133** — 명령 정책 매트릭스 (gh/glab/git 자동 승인 정책).
    /// 기존 사용자는 보수적 default로 시작.
    public var commandPolicy: CommandPolicyMatrix
    /// **ADR-133** — GitLab PAT가 Keychain에 저장됐는지 (UI 표시용 메타).
    /// 실제 토큰은 Keychain에만 저장. 기존 사용자는 false로 시작.
    public var hasGitLabPAT: Bool
    /// **ADR-133** — GitLab 호스트 URL (self-hosted 지원).
    /// 기본값은 https://gitlab.com. self-hosted 사용자만 변경.
    public var gitlabHostURL: String

    public init(
        claudeBinaryPath: String = AppPreferences.detectClaudeBinaryPath(),
        codexBinaryPath: String = AppPreferences.detectCodexBinaryPath(),
        defaultSessionSettings: SessionSettings = .default,
        editPreferences: EditPreferences = .default,
        obsidianVaultPath: String? = nil,
        telegramEnabled: Bool = false,
        telegramAllowedUserIds: [Int64] = [],
        telegramChatId: Int64? = nil,
        telegramAlertPolicy: TelegramAlertPolicy = .default,
        telegramSourceLabel: String? = nil,
        telegramBoundWorkspaceId: UUID? = nil,
        telegramChatBindings: [String: UUID] = [:],
        telegramForwardAssistant: Bool = true,
        telegramForwardToolCalls: Bool = true,
        telegramRemoteRequiresPlan: Bool = true,
        telegramShowCostInline: Bool = true,
        harnessAutoRoutingEnabled: Bool = false,
        harnessUIEnabled: Bool = false,
        harnessRoutingCountdownSeconds: Int = 3,
        harnessInlineModeEnabled: Bool = false,
        routingLogRawPrompts: Bool = false,
        routingLogRetentionDays: Int = 7,
        multiAgentParallelEnabled: Bool = false,
        dailyBudgetUSD: Double? = nil,
        workspaceDailyBudgetsUSD: [UUID: Double] = [:],
        autoNewSessionContextThreshold: Double? = nil,
        anomalyZScoreThreshold: Double = 2.0,
        agentChainEnabled: Bool = false,
        agentChainMaxHops: Int = 1,
        fontSizeOffset: Int = 0,
        showInspectorByDefault: Bool = false,
        beginnerMode: Bool = true,  // ADR-071 Phase 1 — 새 사용자는 초보자 모드로 시작
        hasCompletedOnboarding: Bool = false,  // ADR-072 Phase 4 — 새 사용자는 wizard 표시
        pinnedWorkspaceIds: [UUID] = [],  // ADR-076 Phase 1
        workspaceFolders: [WorkspaceFolder] = [],  // ADR-076 Phase 1
        enabledSmartFolders: Set<SmartFolderKind> = SmartFolderKind.defaultEnabled,  // ADR-077 Phase 3
        workspaceTags: [WorkspaceTag] = [],  // ADR-078 Phase 4
        tagAssignments: WorkspaceTagAssignments = WorkspaceTagAssignments(),  // ADR-078 Phase 4
        activeTagFilters: Set<UUID> = [],  // ADR-078 Phase 4
        smartFilters: [SmartFilter] = [],  // ADR-079 Phase 1
        iCloudSyncEnabled: Bool = false,  // ADR-079 Phase 3 — opt-in
        telegramResponseMode: TelegramResponseMode = .standard,  // ADR-084 Phase 1
        telegramTokenBudget: TelegramTokenBudget = TelegramTokenBudget(),  // ADR-084 Phase 2
        telegramAttachmentPolicy: TelegramAttachmentPolicy = TelegramAttachmentPolicy(),  // ADR-084 Phase 3
        telegramSkills: [TelegramSkill] = TelegramSkill.defaults,  // ADR-084 Phase 4
        telegramBots: [TelegramBotConfig] = [],  // ADR-086 Phase 3
        telegramBotGroups: [TelegramBotGroup] = [],
        telegramBotChatBindings: [BotChatBinding] = [],
        telegramRateLimitAlert: RateLimitAlertConfig = RateLimitAlertConfig(),  // ADR-086 Phase 2
        telegramUpdateMode: TelegramUpdateMode = .longPoll,  // ADR-086 Phase 5
        telegramWebhookURL: String? = nil,
        chatSessions: [ChatSession] = [],  // ADR-089
        activeChatSessionId: UUID? = nil,
        telegramCommands: [TelegramCommand] = TelegramCommand.defaultCommands,  // ADR-094 Phase 3
        notificationPolicy: NotificationPolicyMatrix = .default,  // ADR-095 Phase 4
        quietHoursStart: Int? = nil,  // ADR-095 Phase 4
        quietHoursEnd: Int? = nil,  // ADR-095 Phase 4
        hitlTimeoutSeconds: Int = 60,  // ADR-095 Phase 4
        diffPreviewLineLimit: Int = 30,  // ADR-095 Phase 4
        hasCompletedSetup: Bool = false,  // ADR-104 — 신규 사용자는 setup wizard 표시
        userProfile: UserProfile = .default,  // ADR-106
        libraryItems: [ResourceLibraryItem] = [],  // ADR-111
        hasGitHubPAT: Bool = false,  // ADR-119
        githubSearchHistory: [GitHubSearchHistoryEntry] = [],  // ADR-122
        githubSearchFavorites: [GitHubSearchFavorite] = [],  // ADR-122
        autoRunConfig: AutoRunConfig = .default,  // ADR-132
        commandPolicy: CommandPolicyMatrix = .default,  // ADR-133
        hasGitLabPAT: Bool = false,  // ADR-133
        gitlabHostURL: String = "https://gitlab.com"  // ADR-133
    ) {
        self.claudeBinaryPath = claudeBinaryPath
        self.codexBinaryPath = codexBinaryPath
        self.defaultSessionSettings = defaultSessionSettings
        self.editPreferences = editPreferences
        self.obsidianVaultPath = obsidianVaultPath
        self.telegramEnabled = telegramEnabled
        self.telegramAllowedUserIds = telegramAllowedUserIds
        self.telegramChatId = telegramChatId
        self.telegramAlertPolicy = telegramAlertPolicy
        self.telegramSourceLabel = telegramSourceLabel
        self.telegramBoundWorkspaceId = telegramBoundWorkspaceId
        self.telegramChatBindings = telegramChatBindings
        self.telegramForwardAssistant = telegramForwardAssistant
        self.telegramForwardToolCalls = telegramForwardToolCalls
        self.telegramRemoteRequiresPlan = telegramRemoteRequiresPlan
        self.telegramShowCostInline = telegramShowCostInline
        self.harnessAutoRoutingEnabled = harnessAutoRoutingEnabled
        self.harnessUIEnabled = harnessUIEnabled
        self.harnessRoutingCountdownSeconds = harnessRoutingCountdownSeconds
        self.harnessInlineModeEnabled = harnessInlineModeEnabled
        self.routingLogRawPrompts = routingLogRawPrompts
        self.routingLogRetentionDays = routingLogRetentionDays
        self.multiAgentParallelEnabled = multiAgentParallelEnabled
        self.dailyBudgetUSD = dailyBudgetUSD
        self.workspaceDailyBudgetsUSD = workspaceDailyBudgetsUSD
        self.autoNewSessionContextThreshold = autoNewSessionContextThreshold
        self.anomalyZScoreThreshold = anomalyZScoreThreshold
        self.agentChainEnabled = agentChainEnabled
        self.agentChainMaxHops = agentChainMaxHops
        self.fontSizeOffset = fontSizeOffset
        self.showInspectorByDefault = showInspectorByDefault
        self.beginnerMode = beginnerMode
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.pinnedWorkspaceIds = pinnedWorkspaceIds
        self.workspaceFolders = workspaceFolders
        self.enabledSmartFolders = enabledSmartFolders
        self.workspaceTags = workspaceTags
        self.tagAssignments = tagAssignments
        self.activeTagFilters = activeTagFilters
        self.smartFilters = smartFilters
        self.iCloudSyncEnabled = iCloudSyncEnabled
        self.telegramResponseMode = telegramResponseMode
        self.telegramTokenBudget = telegramTokenBudget
        self.telegramAttachmentPolicy = telegramAttachmentPolicy
        self.telegramSkills = telegramSkills
        self.telegramBots = telegramBots
        self.telegramBotGroups = telegramBotGroups
        self.telegramBotChatBindings = telegramBotChatBindings
        self.telegramRateLimitAlert = telegramRateLimitAlert
        self.telegramUpdateMode = telegramUpdateMode
        self.telegramWebhookURL = telegramWebhookURL
        self.chatSessions = chatSessions
        self.activeChatSessionId = activeChatSessionId
        self.telegramCommands = telegramCommands
        self.notificationPolicy = notificationPolicy
        self.quietHoursStart = quietHoursStart
        self.quietHoursEnd = quietHoursEnd
        self.hitlTimeoutSeconds = hitlTimeoutSeconds
        self.diffPreviewLineLimit = diffPreviewLineLimit
        self.hasCompletedSetup = hasCompletedSetup
        self.userProfile = userProfile
        self.libraryItems = libraryItems
        self.hasGitHubPAT = hasGitHubPAT
        self.githubSearchHistory = githubSearchHistory
        self.githubSearchFavorites = githubSearchFavorites
        self.autoRunConfig = autoRunConfig
        self.commandPolicy = commandPolicy
        self.hasGitLabPAT = hasGitLabPAT
        self.gitlabHostURL = gitlabHostURL
    }

    // ADR-046 — 신규 필드 backward-compat: 기존 JSON에 없으면 default 적용
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.claudeBinaryPath = try c.decodeIfPresent(String.self, forKey: .claudeBinaryPath) ?? AppPreferences.detectClaudeBinaryPath()
        self.codexBinaryPath = try c.decodeIfPresent(String.self, forKey: .codexBinaryPath) ?? AppPreferences.detectCodexBinaryPath()
        self.defaultSessionSettings = try c.decodeIfPresent(SessionSettings.self, forKey: .defaultSessionSettings) ?? .default
        self.editPreferences = try c.decodeIfPresent(EditPreferences.self, forKey: .editPreferences) ?? .default
        self.obsidianVaultPath = try c.decodeIfPresent(String.self, forKey: .obsidianVaultPath)
        self.telegramEnabled = try c.decodeIfPresent(Bool.self, forKey: .telegramEnabled) ?? false
        self.telegramAllowedUserIds = try c.decodeIfPresent([Int64].self, forKey: .telegramAllowedUserIds) ?? []
        self.telegramChatId = try c.decodeIfPresent(Int64.self, forKey: .telegramChatId)
        self.telegramAlertPolicy = try c.decodeIfPresent(TelegramAlertPolicy.self, forKey: .telegramAlertPolicy) ?? .default
        self.telegramSourceLabel = try c.decodeIfPresent(String.self, forKey: .telegramSourceLabel)
        self.telegramBoundWorkspaceId = try c.decodeIfPresent(UUID.self, forKey: .telegramBoundWorkspaceId)
        self.telegramChatBindings = try c.decodeIfPresent([String: UUID].self, forKey: .telegramChatBindings) ?? [:]
        self.telegramForwardAssistant = try c.decodeIfPresent(Bool.self, forKey: .telegramForwardAssistant) ?? true
        self.telegramForwardToolCalls = try c.decodeIfPresent(Bool.self, forKey: .telegramForwardToolCalls) ?? true
        self.telegramRemoteRequiresPlan = try c.decodeIfPresent(Bool.self, forKey: .telegramRemoteRequiresPlan) ?? true
        self.telegramShowCostInline = try c.decodeIfPresent(Bool.self, forKey: .telegramShowCostInline) ?? true
        self.harnessAutoRoutingEnabled = try c.decodeIfPresent(Bool.self, forKey: .harnessAutoRoutingEnabled) ?? false
        self.harnessUIEnabled = try c.decodeIfPresent(Bool.self, forKey: .harnessUIEnabled) ?? false
        self.harnessRoutingCountdownSeconds = try c.decodeIfPresent(Int.self, forKey: .harnessRoutingCountdownSeconds) ?? 3
        self.harnessInlineModeEnabled = try c.decodeIfPresent(Bool.self, forKey: .harnessInlineModeEnabled) ?? false
        self.routingLogRawPrompts = try c.decodeIfPresent(Bool.self, forKey: .routingLogRawPrompts) ?? false
        self.routingLogRetentionDays = try c.decodeIfPresent(Int.self, forKey: .routingLogRetentionDays) ?? 7
        self.multiAgentParallelEnabled = try c.decodeIfPresent(Bool.self, forKey: .multiAgentParallelEnabled) ?? false
        self.dailyBudgetUSD = try c.decodeIfPresent(Double.self, forKey: .dailyBudgetUSD)
        self.workspaceDailyBudgetsUSD = try c.decodeIfPresent([UUID: Double].self, forKey: .workspaceDailyBudgetsUSD) ?? [:]
        self.autoNewSessionContextThreshold = try c.decodeIfPresent(Double.self, forKey: .autoNewSessionContextThreshold)
        self.anomalyZScoreThreshold = try c.decodeIfPresent(Double.self, forKey: .anomalyZScoreThreshold) ?? 2.0
        self.agentChainEnabled = try c.decodeIfPresent(Bool.self, forKey: .agentChainEnabled) ?? false
        self.agentChainMaxHops = try c.decodeIfPresent(Int.self, forKey: .agentChainMaxHops) ?? 1
        self.fontSizeOffset = try c.decodeIfPresent(Int.self, forKey: .fontSizeOffset) ?? 0
        self.showInspectorByDefault = try c.decodeIfPresent(Bool.self, forKey: .showInspectorByDefault) ?? false
        // ADR-071 Phase 1 — 기존 사용자는 false (이미 고급 옵션 사용 중일 가능성). 신규는 init() default true.
        self.beginnerMode = try c.decodeIfPresent(Bool.self, forKey: .beginnerMode) ?? false
        // ADR-072 Phase 4 — 기존 사용자는 true (이미 사용 중이라 wizard 불필요). 신규만 false → wizard.
        self.hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? true
        // ADR-076 Phase 1 — 신규 필드, 기존 사용자는 빈 배열로 시작
        self.pinnedWorkspaceIds = try c.decodeIfPresent([UUID].self, forKey: .pinnedWorkspaceIds) ?? []
        self.workspaceFolders = try c.decodeIfPresent([WorkspaceFolder].self, forKey: .workspaceFolders) ?? []
        // ADR-077 Phase 3 — 기존 사용자는 OFF (UX 변경 최소화), 신규 사용자만 default
        self.enabledSmartFolders = try c.decodeIfPresent(Set<SmartFolderKind>.self, forKey: .enabledSmartFolders) ?? []
        // ADR-078 Phase 4 — Tag 필드들 (기존 사용자는 빈 값)
        self.workspaceTags = try c.decodeIfPresent([WorkspaceTag].self, forKey: .workspaceTags) ?? []
        self.tagAssignments = try c.decodeIfPresent(WorkspaceTagAssignments.self, forKey: .tagAssignments) ?? WorkspaceTagAssignments()
        self.activeTagFilters = try c.decodeIfPresent(Set<UUID>.self, forKey: .activeTagFilters) ?? []
        // ADR-079 Phase 1
        self.smartFilters = try c.decodeIfPresent([SmartFilter].self, forKey: .smartFilters) ?? []
        // ADR-079 Phase 3 — iCloud sync (opt-in, 기존 사용자는 false)
        self.iCloudSyncEnabled = try c.decodeIfPresent(Bool.self, forKey: .iCloudSyncEnabled) ?? false
        // ADR-084 — 텔레그램 고도화 (기존 사용자는 default 적용)
        self.telegramResponseMode = try c.decodeIfPresent(TelegramResponseMode.self, forKey: .telegramResponseMode) ?? .standard
        self.telegramTokenBudget = try c.decodeIfPresent(TelegramTokenBudget.self, forKey: .telegramTokenBudget) ?? TelegramTokenBudget()
        self.telegramAttachmentPolicy = try c.decodeIfPresent(TelegramAttachmentPolicy.self, forKey: .telegramAttachmentPolicy) ?? TelegramAttachmentPolicy()
        // 기존 사용자도 default skills 받음 (즉시 유용)
        self.telegramSkills = try c.decodeIfPresent([TelegramSkill].self, forKey: .telegramSkills) ?? TelegramSkill.defaults
        // ADR-086 — Multi-bot + offline queue + alerts + webhook (기존 사용자는 빈 값/default)
        self.telegramBots = try c.decodeIfPresent([TelegramBotConfig].self, forKey: .telegramBots) ?? []
        self.telegramBotGroups = try c.decodeIfPresent([TelegramBotGroup].self, forKey: .telegramBotGroups) ?? []
        self.telegramBotChatBindings = try c.decodeIfPresent([BotChatBinding].self, forKey: .telegramBotChatBindings) ?? []
        self.telegramRateLimitAlert = try c.decodeIfPresent(RateLimitAlertConfig.self, forKey: .telegramRateLimitAlert) ?? RateLimitAlertConfig()
        self.telegramUpdateMode = try c.decodeIfPresent(TelegramUpdateMode.self, forKey: .telegramUpdateMode) ?? .longPoll
        self.telegramWebhookURL = try c.decodeIfPresent(String.self, forKey: .telegramWebhookURL)
        // ADR-089 — ChatSession (기존 사용자는 빈 배열로 시작)
        self.chatSessions = try c.decodeIfPresent([ChatSession].self, forKey: .chatSessions) ?? []
        self.activeChatSessionId = try c.decodeIfPresent(UUID.self, forKey: .activeChatSessionId)
        // ADR-094 Phase 3 — 기존 사용자도 7개 기본 커맨드 받음 (즉시 유용)
        self.telegramCommands = try c.decodeIfPresent([TelegramCommand].self, forKey: .telegramCommands) ?? TelegramCommand.defaultCommands
        // ADR-095 Phase 4 — 기존 사용자는 default 정책으로 시작
        self.notificationPolicy = try c.decodeIfPresent(NotificationPolicyMatrix.self, forKey: .notificationPolicy) ?? .default
        self.quietHoursStart = try c.decodeIfPresent(Int.self, forKey: .quietHoursStart)
        self.quietHoursEnd = try c.decodeIfPresent(Int.self, forKey: .quietHoursEnd)
        self.hitlTimeoutSeconds = try c.decodeIfPresent(Int.self, forKey: .hitlTimeoutSeconds) ?? 60
        self.diffPreviewLineLimit = try c.decodeIfPresent(Int.self, forKey: .diffPreviewLineLimit) ?? 30
        // ADR-104 — 기존 사용자는 true (이미 도구 설치된 가능성 높음). 신규만 false → wizard.
        self.hasCompletedSetup = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedSetup) ?? true
        // ADR-106 — 기존 사용자는 빈 프로필로 시작 (처음 입력 시 onboarding)
        self.userProfile = try c.decodeIfPresent(UserProfile.self, forKey: .userProfile) ?? .default
        // ADR-111 — 기존 사용자는 빈 라이브러리로 시작
        self.libraryItems = try c.decodeIfPresent([ResourceLibraryItem].self, forKey: .libraryItems) ?? []
        // ADR-119 — 기존 사용자는 false (PAT 미설정 상태)
        self.hasGitHubPAT = try c.decodeIfPresent(Bool.self, forKey: .hasGitHubPAT) ?? false
        // ADR-122 Phase 3 — 기존 사용자는 빈 배열로 시작
        self.githubSearchHistory = try c.decodeIfPresent([GitHubSearchHistoryEntry].self, forKey: .githubSearchHistory) ?? []
        self.githubSearchFavorites = try c.decodeIfPresent([GitHubSearchFavorite].self, forKey: .githubSearchFavorites) ?? []
        // ADR-132 — 기존 사용자는 disabled default로 시작
        self.autoRunConfig = try c.decodeIfPresent(AutoRunConfig.self, forKey: .autoRunConfig) ?? .default
        // ADR-133 — 기존 사용자는 보수적 default로 시작
        self.commandPolicy = try c.decodeIfPresent(CommandPolicyMatrix.self, forKey: .commandPolicy) ?? .default
        self.hasGitLabPAT = try c.decodeIfPresent(Bool.self, forKey: .hasGitLabPAT) ?? false
        self.gitlabHostURL = try c.decodeIfPresent(String.self, forKey: .gitlabHostURL) ?? "https://gitlab.com"
    }

    /// `claude` CLI의 가능성 높은 위치들을 순서대로 시도해 첫 번째 존재하는 경로 반환.
    /// 모두 실패 시 `~/.local/bin/claude`를 잠정 기본값으로.
    public static func detectClaudeBinaryPath() -> String {
        let candidates = [
            NSString(string: "~/.local/bin/claude").expandingTildeInPath,
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude"
        ]
        let fm = FileManager.default
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return path
        }
        return candidates[0]
    }

    /// `codex` CLI 자동 감지. 모두 실패 시 brew 경로를 잠정 기본값으로.
    public static func detectCodexBinaryPath() -> String {
        let candidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            NSString(string: "~/.local/bin/codex").expandingTildeInPath
        ]
        let fm = FileManager.default
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return path
        }
        return candidates[0]
    }

    /// cokacdir bot_settings.json 기본 경로.
    /// cokacdir v0.4.x는 `~/.cokacdir/bot_settings.json`에 저장. 폴백으로 workspace/ 하위도 확인.
    public static func defaultCokacdirBotSettingsPath() -> String {
        let home = NSString(string: "~").expandingTildeInPath
        let candidates = [
            "\(home)/.cokacdir/bot_settings.json",
            "\(home)/.cokacdir/workspace/bot_settings.json"
        ]
        let fm = FileManager.default
        for path in candidates where fm.fileExists(atPath: path) {
            return path
        }
        return candidates[0]
    }
}
