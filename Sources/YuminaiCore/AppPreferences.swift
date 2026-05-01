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
    /// openclaw CLI에 위임하는 모드. true면 토큰 직접 입력 대신 openclaw vault의 토큰 사용.
    public var telegramUseOpenClaw: Bool
    public var openClawBinaryPath: String
    /// openclaw `--target` 인자 (Telegram chat id 숫자 또는 `@username`).
    public var openClawTelegramTarget: String
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
        telegramUseOpenClaw: Bool = false,
        openClawBinaryPath: String = AppPreferences.detectOpenClawBinaryPath(),
        openClawTelegramTarget: String = "",
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
        self.telegramUseOpenClaw = telegramUseOpenClaw
        self.openClawBinaryPath = openClawBinaryPath
        self.openClawTelegramTarget = openClawTelegramTarget
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

    /// `openclaw` CLI 자동 감지. 모두 실패 시 brew 경로를 잠정 기본값으로.
    public static func detectOpenClawBinaryPath() -> String {
        let candidates = [
            "/opt/homebrew/bin/openclaw",
            "/usr/local/bin/openclaw",
            NSString(string: "~/.local/bin/openclaw").expandingTildeInPath
        ]
        let fm = FileManager.default
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return path
        }
        return candidates[0]
    }
}
