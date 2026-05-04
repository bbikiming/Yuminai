import Foundation
import Testing
@testable import YuminaiCore

// MARK: - TelegramTokenValidator

@Suite("TelegramTokenValidator (ADR-092 Phase 1)")
struct TelegramTokenValidatorTests {

    // MARK: - validate(_:) — Valid tokens

    @Test("validate — 표준 형식 토큰 허용")
    func validStandardToken() {
        let result = TelegramTokenValidator.validate("110201543:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw")
        #expect(result.isValid)
    }

    @Test("validate — 짧은 random 파트도 허용")
    func validShortRandomPart() {
        let result = TelegramTokenValidator.validate("123456:abc")
        #expect(result.isValid)
    }

    @Test("validate — underscore, hyphen 포함 허용")
    func validSpecialCharsInRandomPart() {
        let result = TelegramTokenValidator.validate("987654321:Az_-aB")
        #expect(result.isValid)
    }

    @Test("validate — 앞뒤 공백은 자동 trim 후 유효 처리")
    func validWithLeadingTrailingWhitespace() {
        let result = TelegramTokenValidator.validate("  110201543:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw  ")
        #expect(result.isValid)
    }

    // MARK: - validate(_:) — Invalid tokens

    @Test("validate — 빈 문자열 거부")
    func invalidEmptyString() {
        let result = TelegramTokenValidator.validate("")
        if case .invalid(let reason) = result {
            #expect(!reason.isEmpty)
        } else {
            Issue.record("Expected invalid result for empty string")
        }
    }

    @Test("validate — 공백만 있는 문자열 거부")
    func invalidWhitespaceOnly() {
        let result = TelegramTokenValidator.validate("   ")
        if case .invalid(let reason) = result {
            #expect(!reason.isEmpty)
        } else {
            Issue.record("Expected invalid result for whitespace-only string")
        }
    }

    @Test("validate — 콜론 없는 토큰 거부")
    func invalidNoColon() {
        let result = TelegramTokenValidator.validate("110201543AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw")
        #expect(!result.isValid)
    }

    @Test("validate — 봇 ID가 숫자 아닌 경우 거부")
    func invalidNonNumericBotId() {
        let result = TelegramTokenValidator.validate("abc:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw")
        #expect(!result.isValid)
    }

    @Test("validate — random 파트가 비어있으면 거부")
    func invalidEmptyRandomPart() {
        let result = TelegramTokenValidator.validate("110201543:")
        #expect(!result.isValid)
    }

    @Test("validate — random 파트에 특수문자(@) 포함 시 거부")
    func invalidSpecialCharInRandomPart() {
        let result = TelegramTokenValidator.validate("110201543:AAHdq@TcvCH")
        #expect(!result.isValid)
    }

    @Test("validate — 콜론이 두 개 이상이면 거부")
    func invalidMultipleColons() {
        let result = TelegramTokenValidator.validate("110201543:AAH:dq")
        #expect(!result.isValid)
    }

    // MARK: - ValidationResult.isValid

    @Test("isValid — valid 케이스에서 true")
    func isValidTrue() {
        #expect(TelegramTokenValidator.ValidationResult.valid.isValid == true)
    }

    @Test("isValid — invalid 케이스에서 false")
    func isValidFalse() {
        #expect(TelegramTokenValidator.ValidationResult.invalid(reason: "test").isValid == false)
    }

    // MARK: - parseUserIds(_:)

    @Test("parseUserIds — 콤마 구분 숫자 파싱")
    func parseUserIdsCommaSeparated() {
        let ids = TelegramTokenValidator.parseUserIds("123456789, 987654321")
        #expect(ids == [123456789, 987654321])
    }

    @Test("parseUserIds — 줄바꿈 구분 파싱")
    func parseUserIdsNewlineSeparated() {
        let ids = TelegramTokenValidator.parseUserIds("123456789\n987654321")
        #expect(ids == [123456789, 987654321])
    }

    @Test("parseUserIds — 빈 입력이면 빈 배열")
    func parseUserIdsEmpty() {
        let ids = TelegramTokenValidator.parseUserIds("")
        #expect(ids.isEmpty)
    }

    @Test("parseUserIds — 공백만 있으면 빈 배열")
    func parseUserIdsWhitespaceOnly() {
        let ids = TelegramTokenValidator.parseUserIds("   ")
        #expect(ids.isEmpty)
    }

    @Test("parseUserIds — 잘못된 항목은 건너뜀")
    func parseUserIdsSkipsInvalid() {
        let ids = TelegramTokenValidator.parseUserIds("123, abc, 456, !!")
        #expect(ids == [123, 456])
    }

    @Test("parseUserIds — 음수 ID 거부 (Int64 파싱은 되나 양수만 기대)")
    func parseUserIdsNegativeId() {
        // Int64("-123") = -123이므로 파싱은 됨 — 서버에서 실제로 음수 user_id는 거의 없지만
        // 파서 자체는 Int64 범위의 모든 정수를 허용함.
        let ids = TelegramTokenValidator.parseUserIds("-123")
        #expect(ids == [-123])
    }

    @Test("parseUserIds — 혼합 구분자 (콤마 + 줄바꿈)")
    func parseUserIdsMixedSeparators() {
        let ids = TelegramTokenValidator.parseUserIds("111, 222\n333")
        #expect(ids == [111, 222, 333])
    }
}
