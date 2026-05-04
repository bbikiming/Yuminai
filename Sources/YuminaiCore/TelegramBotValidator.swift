import Foundation

/// **ADR-101** — 봇 추가/편집 검증 helper.
///
/// 중복 체크, 형식 검증, sheet별 `isFormValid` 계산을 단일 위치에서 제공.
///
/// ## 사용 예
/// ```swift
/// let result = TelegramBotValidator.validateBot(
///     displayName: name, username: username,
///     keychainKey: key, existingId: bot.id,
///     existingBots: appModel.preferences.telegramBots
/// )
/// if case .duplicateUsername(let id) = result { ... }
/// ```
public enum TelegramBotValidator {

    // MARK: - ValidationResult

    public enum ValidationResult: Equatable {
        /// 모든 검증 통과.
        case valid
        /// displayName이 비어있음.
        case invalidName
        /// keychainKey가 비어있음.
        case invalidKey
        /// username이 이미 다른 봇에 등록됨. `existingId`는 충돌하는 봇의 UUID.
        case duplicateUsername(existingId: UUID)

        public var isValid: Bool {
            self == .valid
        }

        /// 사용자에게 보여줄 오류 메시지.
        public var errorMessage: String? {
            switch self {
            case .valid:
                return nil
            case .invalidName:
                return "봇 이름을 입력해 주세요."
            case .invalidKey:
                return "macOS 비밀번호 저장소 키를 입력해 주세요."
            case .duplicateUsername:
                return "이 username은 이미 사용 중이에요."
            }
        }
    }

    // MARK: - Bot validation

    /// 봇 추가/편집 폼 전체 검증.
    ///
    /// - Parameters:
    ///   - displayName: 표시 이름 입력값.
    ///   - username: username 입력값 (비어있어도 허용).
    ///   - keychainKey: Keychain 키 입력값.
    ///   - existingId: 편집 중인 봇 ID (신규라면 nil). 자기 자신과의 중복은 허용.
    ///   - existingBots: 현재 등록된 봇 목록.
    /// - Returns: `ValidationResult`
    public static func validateBot(
        displayName: String,
        username: String,
        keychainKey: String,
        existingId: UUID?,
        existingBots: [TelegramBotConfig]
    ) -> ValidationResult {
        let trimmedName = displayName.trimmingCharacters(in: .whitespaces)
        if trimmedName.isEmpty { return .invalidName }

        let trimmedKey = keychainKey.trimmingCharacters(in: .whitespaces)
        if trimmedKey.isEmpty { return .invalidKey }

        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)
        if !trimmedUsername.isEmpty {
            let duplicate = existingBots.first { bot in
                bot.username.lowercased() == trimmedUsername.lowercased()
                && bot.id != existingId
            }
            if let duplicate {
                return .duplicateUsername(existingId: duplicate.id)
            }
        }

        return .valid
    }

    // MARK: - Username availability

    /// username이 등록된 봇 목록에서 사용 가능한지 여부.
    ///
    /// - Parameters:
    ///   - username: 검사할 username.
    ///   - bots: 현재 등록된 봇 목록.
    ///   - excludingId: 이 ID의 봇은 중복 검사에서 제외 (편집 시 자기 자신).
    /// - Returns: 사용 가능하면 true.
    public static func isUsernameAvailable(
        _ username: String,
        in bots: [TelegramBotConfig],
        excludingId: UUID? = nil
    ) -> Bool {
        let trimmed = username.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return true }
        return !bots.contains { bot in
            bot.username.lowercased() == trimmed && bot.id != excludingId
        }
    }

    // MARK: - Chat type

    public enum ChatType: Equatable {
        case privateChat   // chatId > 0
        case groupChat     // chatId < 0
        case unknown       // chatId == 0

        public init(chatId: Int64) {
            if chatId > 0 { self = .privateChat }
            else if chatId < 0 { self = .groupChat }
            else { self = .unknown }
        }

        public var displayName: String {
            switch self {
            case .privateChat: return "1:1 대화"
            case .groupChat:   return "그룹 채팅"
            case .unknown:     return "알 수 없는 대화방"
            }
        }

        public var helpText: String {
            switch self {
            case .privateChat:
                return "나만 볼 수 있는 1:1 비공개 대화방. 가장 안전하고 추천."
            case .groupChat:
                return "여러 명이 함께 볼 수 있는 단체방. 신뢰하는 멤버만 있는 방을 권장."
            case .unknown:
                return "유효한 대화방 번호가 아닙니다."
            }
        }
    }

    // MARK: - CokacdirImport validation

    /// CokacdirImportSheet 가져오기 버튼 활성화 조건 검사.
    ///
    /// - Parameters:
    ///   - selectedUsername: 선택된 봇의 username.
    ///   - chatId: 선택된 chat id (nil이면 미선택).
    ///   - existingBots: 현재 등록된 봇 목록 (중복 체크용).
    /// - Returns: `(isValid: Bool, isDuplicate: Bool)`
    public static func validateCokacdirImport(
        selectedUsername: String?,
        chatId: Int64?,
        existingBots: [TelegramBotConfig]
    ) -> (isValid: Bool, isDuplicate: Bool) {
        guard let username = selectedUsername, !username.isEmpty,
              let chatId, chatId != 0 else {
            return (false, false)
        }
        let isDuplicate = !isUsernameAvailable(username, in: existingBots)
        return (!isDuplicate, isDuplicate)
    }

    // MARK: - Binding validation

    /// BotChatBinding 편집 폼 활성화 조건.
    public static func isBindingFormValid(
        selectedBotId: UUID?,
        chatIdText: String
    ) -> Bool {
        guard selectedBotId != nil else { return false }
        let trimmed = chatIdText.trimmingCharacters(in: .whitespaces)
        return Int64(trimmed) != nil
    }

    // MARK: - Command validation

    /// 커맨드 편집 폼 활성화 조건.
    public static func isCommandFormValid(trigger: String, description: String) -> Bool {
        let trimmedTrigger = trigger.trimmingCharacters(in: .whitespaces)
        let trimmedDescription = description.trimmingCharacters(in: .whitespaces)
        guard trimmedTrigger.hasPrefix("/") else { return false }
        let cmd = trimmedTrigger.dropFirst()
        guard !cmd.isEmpty, cmd.count <= 32 else { return false }
        return !trimmedDescription.isEmpty && trimmedDescription.count <= 256
    }
}
