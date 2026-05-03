import Foundation

/// **ADR-086 Phase 3-4** — 멀티 텔레그램 봇 운영 인프라.
///
/// ## 두 가지 운영 시나리오
///
/// ### 시나리오 1: 1봇 × 다중 워크스페이스 (default)
/// - 한 텔레그램 봇 (예: @yuminai_bot)
/// - chat ID별로 다른 워크스페이스 mapping (`telegramChatBindings`)
/// - 사용자가 chat 안에서 `/switch project-a`로 전환 가능
/// - **장점**: 봇 1개로 모든 프로젝트 관리, BotFather 1회 setup
/// - **단점**: 사용자가 active workspace 매번 확인 필요
///
/// ### 시나리오 2: 다봇 그룹 운영 (advanced)
/// - 여러 봇을 BotGroup으로 묶음 (예: "ClientA Bots", "Personal Bots")
/// - 각 봇이 다른 chat group에 속해 다른 팀 분리 운영
/// - 그룹 단위 정책 (응답 모드, budget) 적용
/// - **장점**: 팀별 분리 + 권한 관리 + 독립 통계
/// - **단점**: BotFather에서 봇 N개 생성 필요
///
/// ## 데이터 모델
/// - `TelegramBotConfig`: 단일 봇 정의 (id + token reference + name + group)
/// - `TelegramBotGroup`: 봇 그룹 (id + name + 정책 override)
/// - `BotChatBinding`: 봇 ↔ chat ↔ workspace 3-way 매핑
/// - `TelegramBotRegistry`: 모든 봇/그룹/binding 관리 actor

// MARK: - BotConfig

/// **ADR-086 Phase 3** — 단일 텔레그램 봇 정의.
/// 시크릿 토큰은 KeychainStore에 저장, config는 reference만 보관.
public struct TelegramBotConfig: Sendable, Codable, Hashable, Identifiable {
    public let id: UUID
    /// 사용자 정의 표시 이름 (예: "Personal Bot", "ClientA Production")
    public var displayName: String
    /// BotFather에서 받은 username (예: "yuminai_bot") — 표시용.
    public var username: String
    /// Keychain에 저장된 token의 key.
    /// `KeychainKey.telegramBotToken(_:)` 형식 — 봇별 분리 저장.
    public var keychainKey: String
    /// 이 봇이 속한 그룹 ID. nil = "기본" 그룹.
    public var groupId: UUID?
    /// 화이트리스트된 사용자 IDs.
    public var allowedUserIds: [Int64]
    /// 활성 여부 (false면 polling 안 함).
    public var enabled: Bool
    /// SF Symbol icon name (그룹별 시각 구분).
    public var iconName: String
    /// 색상 (folder palette 공유).
    public var colorName: String
    /// 메모 (선택).
    public var notes: String

    public init(
        id: UUID = UUID(),
        displayName: String,
        username: String,
        keychainKey: String,
        groupId: UUID? = nil,
        allowedUserIds: [Int64] = [],
        enabled: Bool = true,
        iconName: String = "paperplane.circle.fill",
        colorName: String = "accent",
        notes: String = ""
    ) {
        self.id = id
        self.displayName = displayName
        self.username = username
        self.keychainKey = keychainKey
        self.groupId = groupId
        self.allowedUserIds = allowedUserIds
        self.enabled = enabled
        self.iconName = iconName
        self.colorName = colorName
        self.notes = notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.displayName = try c.decode(String.self, forKey: .displayName)
        self.username = try c.decode(String.self, forKey: .username)
        self.keychainKey = try c.decode(String.self, forKey: .keychainKey)
        self.groupId = try c.decodeIfPresent(UUID.self, forKey: .groupId)
        self.allowedUserIds = try c.decodeIfPresent([Int64].self, forKey: .allowedUserIds) ?? []
        self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.iconName = try c.decodeIfPresent(String.self, forKey: .iconName) ?? "paperplane.circle.fill"
        self.colorName = try c.decodeIfPresent(String.self, forKey: .colorName) ?? "accent"
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }
}

// MARK: - BotGroup

/// **ADR-086 Phase 3** — 봇 그룹 (예: "ClientA", "Personal", "Production").
///
/// 그룹 단위로:
/// - 응답 모드 override (그룹별 다른 detail level)
/// - Budget override (그룹별 quota)
/// - Skill 공유 (그룹 안 모든 봇에서 같은 skill 사용)
public struct TelegramBotGroup: Sendable, Codable, Hashable, Identifiable {
    public let id: UUID
    public var displayName: String
    public var iconName: String
    public var colorName: String
    /// 그룹 단위 응답 모드 override (nil = 봇별 또는 global).
    public var responseModeOverride: TelegramResponseMode?
    /// 그룹 단위 budget override (nil = global budget).
    public var budgetOverride: TelegramTokenBudget?
    /// 그룹 안 모든 봇이 공유할 skill IDs (preferences.telegramSkills의 subset).
    public var sharedSkillIds: [UUID]

    public init(
        id: UUID = UUID(),
        displayName: String,
        iconName: String = "folder.badge.person.crop",
        colorName: String = "accent",
        responseModeOverride: TelegramResponseMode? = nil,
        budgetOverride: TelegramTokenBudget? = nil,
        sharedSkillIds: [UUID] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.iconName = iconName
        self.colorName = colorName
        self.responseModeOverride = responseModeOverride
        self.budgetOverride = budgetOverride
        self.sharedSkillIds = sharedSkillIds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.displayName = try c.decode(String.self, forKey: .displayName)
        self.iconName = try c.decodeIfPresent(String.self, forKey: .iconName) ?? "folder.badge.person.crop"
        self.colorName = try c.decodeIfPresent(String.self, forKey: .colorName) ?? "accent"
        self.responseModeOverride = try c.decodeIfPresent(TelegramResponseMode.self, forKey: .responseModeOverride)
        self.budgetOverride = try c.decodeIfPresent(TelegramTokenBudget.self, forKey: .budgetOverride)
        self.sharedSkillIds = try c.decodeIfPresent([UUID].self, forKey: .sharedSkillIds) ?? []
    }
}

// MARK: - BotChatBinding

/// **ADR-086 Phase 3** — 3-way 매핑: bot ↔ chat ↔ workspace.
///
/// 이전 `telegramChatBindings: [String: UUID]` (chat → workspace)에서 발전:
/// - 같은 chat ID여도 다른 봇이면 다른 workspace 가능
/// - 한 chat 안에서 사용자가 `/switch` 명령으로 workspace 변경 가능 (history 보관)
public struct BotChatBinding: Sendable, Codable, Hashable, Identifiable {
    public let id: UUID
    public let botId: UUID
    /// Telegram chat ID.
    public let chatId: Int64
    /// 현재 활성 workspace UUID (사용자가 /switch로 변경 가능).
    public var activeWorkspaceId: UUID?
    /// 이 chat에서 사용 가능한 workspace IDs (whitelist, 빈 set = 모든 workspace).
    public var allowedWorkspaceIds: Set<UUID>
    /// chat 한국어 별명 (사용자 표시용, 예: "iPhone Telegram", "ClientA Slack").
    public var nickname: String

    public init(
        id: UUID = UUID(),
        botId: UUID,
        chatId: Int64,
        activeWorkspaceId: UUID? = nil,
        allowedWorkspaceIds: Set<UUID> = [],
        nickname: String = ""
    ) {
        self.id = id
        self.botId = botId
        self.chatId = chatId
        self.activeWorkspaceId = activeWorkspaceId
        self.allowedWorkspaceIds = allowedWorkspaceIds
        self.nickname = nickname
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.botId = try c.decode(UUID.self, forKey: .botId)
        self.chatId = try c.decode(Int64.self, forKey: .chatId)
        self.activeWorkspaceId = try c.decodeIfPresent(UUID.self, forKey: .activeWorkspaceId)
        self.allowedWorkspaceIds = try c.decodeIfPresent(Set<UUID>.self, forKey: .allowedWorkspaceIds) ?? []
        self.nickname = try c.decodeIfPresent(String.self, forKey: .nickname) ?? ""
    }
}

// MARK: - BotRegistry (actor)

/// **ADR-086 Phase 3** — 모든 봇/그룹/binding을 관리하는 중앙 registry.
///
/// AppPreferences가 데이터 저장소, 이 actor는 mutation API + lookup helpers.
public actor TelegramBotRegistry {
    public private(set) var bots: [TelegramBotConfig]
    public private(set) var groups: [TelegramBotGroup]
    public private(set) var bindings: [BotChatBinding]

    public init(
        bots: [TelegramBotConfig] = [],
        groups: [TelegramBotGroup] = [],
        bindings: [BotChatBinding] = []
    ) {
        self.bots = bots
        self.groups = groups
        self.bindings = bindings
    }

    // MARK: - Bot CRUD

    public func addBot(_ bot: TelegramBotConfig) {
        if !bots.contains(where: { $0.id == bot.id }) {
            bots.append(bot)
        }
    }

    public func updateBot(_ bot: TelegramBotConfig) {
        if let idx = bots.firstIndex(where: { $0.id == bot.id }) {
            bots[idx] = bot
        }
    }

    public func removeBot(id: UUID) {
        bots.removeAll { $0.id == id }
        // 관련 binding도 정리
        bindings.removeAll { $0.botId == id }
    }

    // MARK: - Group CRUD

    public func addGroup(_ group: TelegramBotGroup) {
        if !groups.contains(where: { $0.id == group.id }) {
            groups.append(group)
        }
    }

    public func updateGroup(_ group: TelegramBotGroup) {
        if let idx = groups.firstIndex(where: { $0.id == group.id }) {
            groups[idx] = group
        }
    }

    public func removeGroup(id: UUID) {
        groups.removeAll { $0.id == id }
        // 그룹 안 봇들은 ungrouped로 (groupId = nil)
        for i in bots.indices {
            if bots[i].groupId == id {
                bots[i].groupId = nil
            }
        }
    }

    // MARK: - Binding CRUD

    public func addBinding(_ binding: BotChatBinding) {
        // 같은 (botId, chatId) 조합 이미 있으면 update
        if let idx = bindings.firstIndex(where: { $0.botId == binding.botId && $0.chatId == binding.chatId }) {
            bindings[idx] = binding
        } else {
            bindings.append(binding)
        }
    }

    public func removeBinding(botId: UUID, chatId: Int64) {
        bindings.removeAll { $0.botId == botId && $0.chatId == chatId }
    }

    /// 사용자가 `/switch <workspace-name>` 명령 시 호출 — active workspace 변경.
    public func switchWorkspace(botId: UUID, chatId: Int64, to workspaceId: UUID) {
        if let idx = bindings.firstIndex(where: { $0.botId == botId && $0.chatId == chatId }) {
            // allowedWorkspaceIds 체크 (빈 set이면 모두 허용)
            let allowed = bindings[idx].allowedWorkspaceIds
            if allowed.isEmpty || allowed.contains(workspaceId) {
                bindings[idx].activeWorkspaceId = workspaceId
            }
        }
    }

    // MARK: - Lookup

    public func bot(id: UUID) -> TelegramBotConfig? {
        bots.first { $0.id == id }
    }

    public func group(id: UUID) -> TelegramBotGroup? {
        groups.first { $0.id == id }
    }

    public func bots(in groupId: UUID?) -> [TelegramBotConfig] {
        bots.filter { $0.groupId == groupId }
    }

    public func binding(botId: UUID, chatId: Int64) -> BotChatBinding? {
        bindings.first { $0.botId == botId && $0.chatId == chatId }
    }

    /// 특정 봇의 모든 chat bindings.
    public func bindings(forBot botId: UUID) -> [BotChatBinding] {
        bindings.filter { $0.botId == botId }
    }

    // MARK: - Effective settings (group override → bot → global fallback)

    /// 특정 봇의 effective response mode (group override 적용).
    public func effectiveResponseMode(botId: UUID, globalDefault: TelegramResponseMode) -> TelegramResponseMode {
        guard let bot = bot(id: botId) else { return globalDefault }
        if let groupId = bot.groupId, let g = group(id: groupId), let mode = g.responseModeOverride {
            return mode
        }
        return globalDefault
    }

    /// 특정 봇의 effective budget (group override 적용).
    public func effectiveBudget(botId: UUID, globalDefault: TelegramTokenBudget) -> TelegramTokenBudget {
        guard let bot = bot(id: botId) else { return globalDefault }
        if let groupId = bot.groupId, let g = group(id: groupId), let budget = g.budgetOverride {
            return budget
        }
        return globalDefault
    }
}

// MARK: - Phase 2 — Offline queue

/// **ADR-086 Phase 2** — Network 끊겼을 때 메시지 보관 → 복구 시 재전송.
public struct PendingTelegramMessage: Sendable, Codable, Hashable, Identifiable {
    public let id: UUID
    public let botId: UUID
    public let chatId: Int64
    public let text: String
    public let queuedAt: Date
    /// 재시도 횟수 (max 도달 시 폐기).
    public var attemptCount: Int

    public init(
        id: UUID = UUID(),
        botId: UUID,
        chatId: Int64,
        text: String,
        queuedAt: Date = Date(),
        attemptCount: Int = 0
    ) {
        self.id = id
        self.botId = botId
        self.chatId = chatId
        self.text = text
        self.queuedAt = queuedAt
        self.attemptCount = attemptCount
    }
}

/// **ADR-086 Phase 2** — Offline queue (network 복구 시 재전송).
public actor TelegramOfflineQueue {
    private var pending: [PendingTelegramMessage] = []
    private let maxAttempts: Int
    private let maxQueueSize: Int

    public init(maxAttempts: Int = 5, maxQueueSize: Int = 100) {
        self.maxAttempts = maxAttempts
        self.maxQueueSize = maxQueueSize
    }

    public func enqueue(_ message: PendingTelegramMessage) {
        // 큐가 가득 차면 oldest 삭제 (drop-oldest 전략)
        if pending.count >= maxQueueSize {
            pending.removeFirst()
        }
        pending.append(message)
    }

    public func all() -> [PendingTelegramMessage] {
        pending
    }

    public func count() -> Int {
        pending.count
    }

    /// 큐의 모든 메시지를 처리 시도. attempt 증가 + 성공 시 제거.
    /// - Parameter sender: 실제 send 함수 (success → true).
    /// - Returns: (success count, dropped count)
    public func flush(sender: (PendingTelegramMessage) async -> Bool) async -> (sent: Int, dropped: Int) {
        var sent = 0
        var dropped = 0
        var remaining: [PendingTelegramMessage] = []
        for var msg in pending {
            let success = await sender(msg)
            if success {
                sent += 1
            } else {
                msg.attemptCount += 1
                if msg.attemptCount >= maxAttempts {
                    dropped += 1
                } else {
                    remaining.append(msg)
                }
            }
        }
        pending = remaining
        return (sent, dropped)
    }

    public func clear() {
        pending.removeAll()
    }
}

// MARK: - Phase 2 — Rate limit alert (80% threshold)

/// **ADR-086 Phase 2** — Rate limit 사용량 경고 (할당량 80% 도달 시).
public struct RateLimitAlertConfig: Sendable, Codable, Hashable {
    /// 일별 budget의 % (0~1). default 0.8 (80%).
    public var thresholdRatio: Double
    /// 알림 받을 channel (텔레그램으로 자동 전송).
    public var notifyViaTelegram: Bool
    /// 알림 cooldown (한 번 알림 후 다음 알림까지 대기 시간, 초).
    public var cooldownSeconds: TimeInterval

    public init(
        thresholdRatio: Double = 0.8,
        notifyViaTelegram: Bool = true,
        cooldownSeconds: TimeInterval = 3600  // 1시간
    ) {
        self.thresholdRatio = thresholdRatio
        self.notifyViaTelegram = notifyViaTelegram
        self.cooldownSeconds = cooldownSeconds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.thresholdRatio = try c.decodeIfPresent(Double.self, forKey: .thresholdRatio) ?? 0.8
        self.notifyViaTelegram = try c.decodeIfPresent(Bool.self, forKey: .notifyViaTelegram) ?? true
        self.cooldownSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .cooldownSeconds) ?? 3600
    }
}

// MARK: - Phase 5 — Webhook mode

/// **ADR-086 Phase 5** — Update receiving 모드.
/// - longPoll: 기존 (배터리 소모 ↑, latency 즉시)
/// - webhook: HTTPS callback URL (배터리 절약, ngrok/Cloudflare Tunnel 등 필요)
public enum TelegramUpdateMode: String, Sendable, Codable, CaseIterable, Identifiable {
    case longPoll
    case webhook

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .longPoll: return "Long Polling (default)"
        case .webhook: return "Webhook (HTTPS)"
        }
    }

    public var hint: String {
        switch self {
        case .longPoll: return "30초 long-poll. 즉시 수신 + 배터리 소모 (기본)."
        case .webhook: return "서버가 직접 푸시. 배터리 절약 + HTTPS 공개 URL 필요 (ngrok/Cloudflare Tunnel)."
        }
    }
}

// MARK: - Phase 2 — Rate limit alert tracker

/// **ADR-086 Phase 2** — 사용량 80% 도달 시 텔레그램 경고 (cooldown 적용).
///
/// 사용 패턴:
/// 1. AppModel이 매 turn 종료 후 `report(usedToday:dailyBudget:)` 호출
/// 2. tracker가 ratio 계산 → threshold 도달 + cooldown 경과 시 `shouldAlert(now:)` true
/// 3. 호출자가 alert message 전송 → `markAlerted(now:)`로 cooldown 시작
public actor RateLimitAlertTracker {
    private var config: RateLimitAlertConfig
    private var lastAlertedAt: Date?
    /// 가장 최근 reported ratio (0~1).
    private(set) var currentRatio: Double = 0.0
    /// 가장 최근 reported usedToday (USD).
    private(set) var currentUsedUSD: Double = 0.0
    /// 가장 최근 reported dailyBudget (USD).
    private(set) var currentBudgetUSD: Double = 0.0

    public init(config: RateLimitAlertConfig = RateLimitAlertConfig()) {
        self.config = config
    }

    public func updateConfig(_ config: RateLimitAlertConfig) {
        self.config = config
    }

    /// AppModel이 매 turn 후 호출. 현재 사용률 갱신.
    public func report(usedToday: Double, dailyBudget: Double) {
        currentUsedUSD = usedToday
        currentBudgetUSD = dailyBudget
        currentRatio = dailyBudget > 0 ? min(1.0, usedToday / dailyBudget) : 0.0
    }

    /// alert를 보낼지 결정. true면 호출자가 텔레그램 메시지 전송 후 `markAlerted` 호출.
    public func shouldAlert(now: Date = Date()) -> Bool {
        guard config.notifyViaTelegram else { return false }
        guard currentRatio >= config.thresholdRatio else { return false }
        if let last = lastAlertedAt {
            let elapsed = now.timeIntervalSince(last)
            return elapsed >= config.cooldownSeconds
        }
        return true
    }

    public func markAlerted(now: Date = Date()) {
        lastAlertedAt = now
    }

    /// alert message 생성 (한국어). 호출자가 `chatId`로 전송.
    public func makeAlertMessage() -> String {
        let pct = Int((currentRatio * 100).rounded())
        return "⚠️ 텔레그램 사용량 알림\n오늘 \(pct)% 사용 ($\(String(format: "%.2f", currentUsedUSD)) / $\(String(format: "%.2f", currentBudgetUSD)))\n다음 자정에 reset됩니다."
    }
}
