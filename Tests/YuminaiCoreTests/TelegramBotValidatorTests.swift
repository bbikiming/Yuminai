import XCTest
@testable import YuminaiCore

/// **ADR-101** — TelegramBotValidator 단위 테스트.
final class TelegramBotValidatorTests: XCTestCase {

    // MARK: - Fixtures

    private func makeBot(
        id: UUID = UUID(),
        displayName: String = "Test Bot",
        username: String = "test_bot",
        keychainKey: String = "telegram.bot.test"
    ) -> TelegramBotConfig {
        TelegramBotConfig(
            id: id,
            displayName: displayName,
            username: username,
            keychainKey: keychainKey
        )
    }

    // MARK: - validateBot: 정상 케이스

    func test_validateBot_validInputs_returnsValid() {
        let bots: [TelegramBotConfig] = []
        let result = TelegramBotValidator.validateBot(
            displayName: "내 봇",
            username: "my_bot",
            keychainKey: "telegram.bot.test",
            existingId: nil,
            existingBots: bots
        )
        XCTAssertEqual(result, .valid)
    }

    func test_validateBot_emptyUsername_stillValid() {
        // username은 선택 사항 — 비어있어도 valid
        let result = TelegramBotValidator.validateBot(
            displayName: "내 봇",
            username: "",
            keychainKey: "telegram.bot.test",
            existingId: nil,
            existingBots: []
        )
        XCTAssertEqual(result, .valid)
    }

    // MARK: - validateBot: 빈 displayName

    func test_validateBot_emptyDisplayName_returnsInvalidName() {
        let result = TelegramBotValidator.validateBot(
            displayName: "",
            username: "my_bot",
            keychainKey: "telegram.bot.test",
            existingId: nil,
            existingBots: []
        )
        XCTAssertEqual(result, .invalidName)
    }

    func test_validateBot_whitespaceOnlyDisplayName_returnsInvalidName() {
        let result = TelegramBotValidator.validateBot(
            displayName: "   ",
            username: "my_bot",
            keychainKey: "telegram.bot.test",
            existingId: nil,
            existingBots: []
        )
        XCTAssertEqual(result, .invalidName)
    }

    // MARK: - validateBot: 빈 keychainKey

    func test_validateBot_emptyKeychainKey_returnsInvalidKey() {
        let result = TelegramBotValidator.validateBot(
            displayName: "내 봇",
            username: "my_bot",
            keychainKey: "",
            existingId: nil,
            existingBots: []
        )
        XCTAssertEqual(result, .invalidKey)
    }

    func test_validateBot_whitespaceKeychainKey_returnsInvalidKey() {
        let result = TelegramBotValidator.validateBot(
            displayName: "내 봇",
            username: "my_bot",
            keychainKey: "  ",
            existingId: nil,
            existingBots: []
        )
        XCTAssertEqual(result, .invalidKey)
    }

    // MARK: - validateBot: 중복 username

    func test_validateBot_duplicateUsername_returnsDuplicateWithCorrectId() {
        let existingId = UUID()
        let bots = [makeBot(id: existingId, username: "existing_bot")]
        let result = TelegramBotValidator.validateBot(
            displayName: "새 봇",
            username: "existing_bot",
            keychainKey: "telegram.bot.new",
            existingId: nil,
            existingBots: bots
        )
        XCTAssertEqual(result, .duplicateUsername(existingId: existingId))
    }

    func test_validateBot_duplicateUsernameCaseInsensitive() {
        let existingId = UUID()
        let bots = [makeBot(id: existingId, username: "Existing_Bot")]
        let result = TelegramBotValidator.validateBot(
            displayName: "새 봇",
            username: "existing_bot",
            keychainKey: "telegram.bot.new",
            existingId: nil,
            existingBots: bots
        )
        XCTAssertEqual(result, .duplicateUsername(existingId: existingId))
    }

    func test_validateBot_editingSelf_notDuplicate() {
        let selfId = UUID()
        let bots = [makeBot(id: selfId, username: "my_bot")]
        // 자기 자신을 편집 — 같은 username이어도 중복 아님
        let result = TelegramBotValidator.validateBot(
            displayName: "내 봇",
            username: "my_bot",
            keychainKey: "telegram.bot.test",
            existingId: selfId,
            existingBots: bots
        )
        XCTAssertEqual(result, .valid)
    }

    // MARK: - isUsernameAvailable

    func test_isUsernameAvailable_emptyUsername_alwaysTrue() {
        let bots = [makeBot(username: "some_bot")]
        XCTAssertTrue(TelegramBotValidator.isUsernameAvailable("", in: bots))
    }

    func test_isUsernameAvailable_notInList_returnsTrue() {
        let bots = [makeBot(username: "bot_a")]
        XCTAssertTrue(TelegramBotValidator.isUsernameAvailable("bot_b", in: bots))
    }

    func test_isUsernameAvailable_alreadyInList_returnsFalse() {
        let bots = [makeBot(username: "bot_a")]
        XCTAssertFalse(TelegramBotValidator.isUsernameAvailable("bot_a", in: bots))
    }

    func test_isUsernameAvailable_excludingId_returnsTrue() {
        let id = UUID()
        let bots = [makeBot(id: id, username: "bot_a")]
        XCTAssertTrue(TelegramBotValidator.isUsernameAvailable("bot_a", in: bots, excludingId: id))
    }

    // MARK: - ChatType

    func test_chatType_positiveId_isPrivate() {
        let ct = TelegramBotValidator.ChatType(chatId: 123456789)
        XCTAssertEqual(ct, .privateChat)
    }

    func test_chatType_negativeId_isGroup() {
        let ct = TelegramBotValidator.ChatType(chatId: -100123456789)
        XCTAssertEqual(ct, .groupChat)
    }

    func test_chatType_zeroId_isUnknown() {
        let ct = TelegramBotValidator.ChatType(chatId: 0)
        XCTAssertEqual(ct, .unknown)
    }

    // MARK: - isBindingFormValid

    func test_isBindingFormValid_bothSet_returnsTrue() {
        XCTAssertTrue(
            TelegramBotValidator.isBindingFormValid(
                selectedBotId: UUID(),
                chatIdText: "123456789"
            )
        )
    }

    func test_isBindingFormValid_noBotId_returnsFalse() {
        XCTAssertFalse(
            TelegramBotValidator.isBindingFormValid(
                selectedBotId: nil,
                chatIdText: "123456789"
            )
        )
    }

    func test_isBindingFormValid_invalidChatId_returnsFalse() {
        XCTAssertFalse(
            TelegramBotValidator.isBindingFormValid(
                selectedBotId: UUID(),
                chatIdText: "not_a_number"
            )
        )
    }

    // MARK: - isCommandFormValid

    func test_isCommandFormValid_valid_returnsTrue() {
        XCTAssertTrue(TelegramBotValidator.isCommandFormValid(trigger: "/run", description: "실행"))
    }

    func test_isCommandFormValid_noSlash_returnsFalse() {
        XCTAssertFalse(TelegramBotValidator.isCommandFormValid(trigger: "run", description: "실행"))
    }

    func test_isCommandFormValid_emptyDescription_returnsFalse() {
        XCTAssertFalse(TelegramBotValidator.isCommandFormValid(trigger: "/run", description: ""))
    }

    func test_isCommandFormValid_slashOnly_returnsFalse() {
        XCTAssertFalse(TelegramBotValidator.isCommandFormValid(trigger: "/", description: "실행"))
    }

    // MARK: - ValidationResult errorMessage

    func test_errorMessage_valid_isNil() {
        XCTAssertNil(TelegramBotValidator.ValidationResult.valid.errorMessage)
    }

    func test_errorMessage_invalidName_notNil() {
        XCTAssertNotNil(TelegramBotValidator.ValidationResult.invalidName.errorMessage)
    }

    func test_errorMessage_duplicateUsername_notNil() {
        XCTAssertNotNil(
            TelegramBotValidator.ValidationResult.duplicateUsername(existingId: UUID()).errorMessage
        )
    }
}
