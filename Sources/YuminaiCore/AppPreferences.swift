import Foundation

/// 앱 글로벌 설정. 시크릿이 아닌 메타데이터만. (시크릿은 KeychainStore.)
///
/// `UserDefaults` 등에 저장되며 SettingsView에서 편집된다.
public struct AppPreferences: Sendable, Codable, Hashable {
    public var claudeBinaryPath: String
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
    public var fontSizeOffset: Int
    public var showInspectorByDefault: Bool

    public init(
        claudeBinaryPath: String = AppPreferences.detectClaudeBinaryPath(),
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
        fontSizeOffset: Int = 0,
        showInspectorByDefault: Bool = false
    ) {
        self.claudeBinaryPath = claudeBinaryPath
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
        self.fontSizeOffset = fontSizeOffset
        self.showInspectorByDefault = showInspectorByDefault
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
