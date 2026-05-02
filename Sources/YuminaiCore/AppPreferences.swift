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
    public var telegramBoundWorkspaceId: UUID?
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
        telegramForwardAssistant: Bool = true,
        telegramForwardToolCalls: Bool = true,
        telegramRemoteRequiresPlan: Bool = true,
        telegramShowCostInline: Bool = true,
        harnessAutoRoutingEnabled: Bool = false,
        harnessUIEnabled: Bool = false,
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
        self.telegramForwardAssistant = telegramForwardAssistant
        self.telegramForwardToolCalls = telegramForwardToolCalls
        self.telegramRemoteRequiresPlan = telegramRemoteRequiresPlan
        self.telegramShowCostInline = telegramShowCostInline
        self.harnessAutoRoutingEnabled = harnessAutoRoutingEnabled
        self.harnessUIEnabled = harnessUIEnabled
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
        self.telegramForwardAssistant = try c.decodeIfPresent(Bool.self, forKey: .telegramForwardAssistant) ?? true
        self.telegramForwardToolCalls = try c.decodeIfPresent(Bool.self, forKey: .telegramForwardToolCalls) ?? true
        self.telegramRemoteRequiresPlan = try c.decodeIfPresent(Bool.self, forKey: .telegramRemoteRequiresPlan) ?? true
        self.telegramShowCostInline = try c.decodeIfPresent(Bool.self, forKey: .telegramShowCostInline) ?? true
        self.harnessAutoRoutingEnabled = try c.decodeIfPresent(Bool.self, forKey: .harnessAutoRoutingEnabled) ?? false
        self.harnessUIEnabled = try c.decodeIfPresent(Bool.self, forKey: .harnessUIEnabled) ?? false
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
