import Foundation

/// **ADR-094 Phase 3** — Telegram bot command descriptor.
///
/// 각 커맨드는 BotFather에 등록되며 사용자가 `/trigger` 형식으로 호출한다.
/// `requiresHITL`이 true이면 실행 전 `TelegramHITLCoordinator`를 통해 데스크탑 승인을 요구한다.
public struct TelegramCommand: Sendable, Codable, Hashable, Identifiable {
    public let id: UUID
    /// BotFather 등록 시 사용되는 slash prefix 포함 trigger (예: "/run").
    /// Telegram API 전송 시 "/" 제거 후 전달됨.
    public var trigger: String
    /// BotFather에 표시되는 설명 (max 256자).
    public var description: String
    /// 실행 권한 정책.
    public var permission: Permission
    /// true이면 실행 전 `TelegramHITLCoordinator`를 통해 데스크탑 승인 요청.
    public var requiresHITL: Bool
    /// false이면 BotFather sync 및 커맨드 라우팅에서 제외.
    public var enabled: Bool

    /// 커맨드 실행 권한 정책.
    public enum Permission: Codable, Hashable, Sendable {
        /// 허용 목록의 모든 사용자 (AppPreferences.telegramAllowedUserIds 기준).
        case anyUser
        /// 봇 관리자만 (향후 admin userId 설정 시 사용).
        case admin
        /// 명시적으로 지정된 user ID 목록.
        case userIds([Int64])
    }

    public init(
        id: UUID = UUID(),
        trigger: String,
        description: String,
        permission: Permission = .anyUser,
        requiresHITL: Bool = false,
        enabled: Bool = true
    ) {
        self.id = id
        self.trigger = trigger
        self.description = description
        self.permission = permission
        self.requiresHITL = requiresHITL
        self.enabled = enabled
    }

    // MARK: - Validation

    /// trigger가 "/" 시작이고 command 부분이 1~32자인지 검사.
    public var isValidTrigger: Bool {
        guard trigger.hasPrefix("/") else { return false }
        let cmd = String(trigger.dropFirst())
        return !cmd.isEmpty && cmd.count <= 32
    }

    /// description이 1~256자인지 검사.
    public var isValidDescription: Bool {
        !description.isEmpty && description.count <= 256
    }

    /// Telegram API 전송용 command (prefix "/" 제거).
    public var apiCommand: String {
        trigger.hasPrefix("/") ? String(trigger.dropFirst()) : trigger
    }
}

// MARK: - Default Seeds

extension TelegramCommand {
    /// **ADR-094** — Preferences 최초 로드 시 fallback으로 사용되는 기본 7개 커맨드.
    public static let defaultCommands: [TelegramCommand] = [
        TelegramCommand(
            trigger: "/run",
            description: "Execute in current workspace",
            permission: .anyUser,
            requiresHITL: false,
            enabled: true
        ),
        TelegramCommand(
            trigger: "/switch",
            description: "Change workspace binding",
            permission: .admin,
            requiresHITL: false,
            enabled: true
        ),
        TelegramCommand(
            trigger: "/diff",
            description: "Show pending diff",
            permission: .anyUser,
            requiresHITL: false,
            enabled: true
        ),
        TelegramCommand(
            trigger: "/approve",
            description: "Approve last HITL request",
            permission: .anyUser,
            requiresHITL: false,
            enabled: true
        ),
        TelegramCommand(
            trigger: "/reject",
            description: "Reject last HITL request",
            permission: .anyUser,
            requiresHITL: false,
            enabled: true
        ),
        TelegramCommand(
            trigger: "/abort",
            description: "Cancel running task",
            permission: .anyUser,
            requiresHITL: false,
            enabled: true
        ),
        TelegramCommand(
            trigger: "/status",
            description: "Show current task status",
            permission: .anyUser,
            requiresHITL: false,
            enabled: true
        ),
    ]
}

// MARK: - Permission display

extension TelegramCommand.Permission {
    /// UI 표시용 짧은 레이블.
    public var displayLabel: String {
        switch self {
        case .anyUser: return "전체"
        case .admin: return "관리자"
        case .userIds(let ids):
            if ids.isEmpty { return "없음" }
            return "특정 \(ids.count)명"
        }
    }
}
