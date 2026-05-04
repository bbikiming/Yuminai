import Foundation

/// **ADR-092 Phase 1** — 텔레그램 봇 토큰 형식 검증 유틸리티.
///
/// BotFather가 발급하는 토큰 형식: `<bot_id>:<random_string>`
/// - `<bot_id>`: 숫자 (Telegram user ID)
/// - `<random_string>`: 영문자, 숫자, `_`, `-` 조합
///
/// 예시: `110201543:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw`
///
/// Phase 2에서 getMe API 호출로 실제 검증 추가 예정.
public struct TelegramTokenValidator: Sendable {

    // MARK: - 검증 결과

    public enum ValidationResult: Sendable, Equatable {
        /// 형식이 올바름.
        case valid
        /// 형식이 잘못됨. 이유 설명 포함.
        case invalid(reason: String)

        public var isValid: Bool {
            if case .valid = self { return true }
            return false
        }
    }

    // MARK: - 토큰 정규식

    /// `^\d+:[A-Za-z0-9_-]+$`
    /// - 앞부분: 1개 이상의 숫자 (봇 ID)
    /// - 구분자: 콜론 `:`
    /// - 뒷부분: 1개 이상의 영문자/숫자/underscore/hyphen (random token)
    private static let tokenPattern = #"^\d+:[A-Za-z0-9_\-]+$"#

    private static let tokenRegex: NSRegularExpression = {
        // 컴파일 타임에 패턴이 고정되어 있으므로 try! 사용 안전.
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: tokenPattern)
    }()

    // MARK: - 공용 API

    /// 토큰 형식을 검증한다.
    ///
    /// - Parameter token: 검증할 토큰 문자열 (공백은 자동 trim됨).
    /// - Returns: ``ValidationResult`` — `.valid` 또는 `.invalid(reason:)`.
    public static func validate(_ token: String) -> ValidationResult {
        let trimmed = token.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            return .invalid(reason: "토큰을 입력해 주세요.")
        }

        let range = NSRange(trimmed.startIndex..., in: trimmed)
        let match = tokenRegex.firstMatch(in: trimmed, range: range)

        if match == nil {
            return .invalid(reason: "형식이 올바르지 않아요. BotFather에서 발급받은 토큰을 그대로 붙여 넣으세요. (예: 110201543:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw)")
        }

        return .valid
    }

    /// 콤마 구분 user_id 문자열을 파싱하여 `[Int64]`로 반환.
    ///
    /// - 숫자가 아닌 항목은 건너뜀.
    /// - 빈 입력이면 빈 배열 반환.
    ///
    /// - Parameter text: 콤마(또는 줄바꿈) 구분 user_id 텍스트.
    /// - Returns: 파싱된 user IDs. 잘못된 항목 제외.
    public static func parseUserIds(_ text: String) -> [Int64] {
        text
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .compactMap { component -> Int64? in
                let trimmed = component.trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty ? nil : Int64(trimmed)
            }
    }
}
