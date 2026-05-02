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
    /// pane 응답에 `@<other>` mention이 있으면 자동으로 다음 turn dispatch (ADR-034 A1).
    /// **default OFF** — 무한 루프 위험, 명시적 토글 필요.
    public var agentChainEnabled: Bool
    /// chain max hops — 0이면 비활성. default 1 (한 번만 자동 답장).
    public var agentChainMaxHops: Int
    public var fontSizeOffset: Int
    public var showInspectorByDefault: Bool

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
        agentChainEnabled: Bool = false,
        agentChainMaxHops: Int = 1,
        fontSizeOffset: Int = 0,
        showInspectorByDefault: Bool = false
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
        self.agentChainEnabled = agentChainEnabled
        self.agentChainMaxHops = agentChainMaxHops
        self.fontSizeOffset = fontSizeOffset
        self.showInspectorByDefault = showInspectorByDefault
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
        self.agentChainEnabled = try c.decodeIfPresent(Bool.self, forKey: .agentChainEnabled) ?? false
        self.agentChainMaxHops = try c.decodeIfPresent(Int.self, forKey: .agentChainMaxHops) ?? 1
        self.fontSizeOffset = try c.decodeIfPresent(Int.self, forKey: .fontSizeOffset) ?? 0
        self.showInspectorByDefault = try c.decodeIfPresent(Bool.self, forKey: .showInspectorByDefault) ?? false
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
