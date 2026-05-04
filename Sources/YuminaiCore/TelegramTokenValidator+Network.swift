import Foundation

/// **ADR-093 Phase 2** — `getMe` API 호출로 토큰 유효성 실제 검증 + 봇 정보 반환.
///
/// `TelegramTokenValidator`의 network extension.
/// 형식 검증(`validate(_:)`)은 이미 있으므로, 이 파일은 네트워크 레이어만 추가.
///
/// 사용 패턴:
/// ```swift
/// let info = try await TelegramTokenValidator.fetchBotInfo(token: token)
/// print(info.username)  // "YuminaiBot"
/// ```

// MARK: - TelegramBotInfo

/// `getMe` API 응답에서 추출한 봇 기본 정보.
public struct TelegramBotInfo: Sendable, Equatable {
    public let id: Int64
    /// BotFather에서 설정한 username (@ 제외).
    public let username: String
    /// 봇 표시 이름 (first_name).
    public let firstName: String
    /// 그룹/채널에 참여 가능한지.
    public let canJoinGroups: Bool

    public init(
        id: Int64,
        username: String,
        firstName: String,
        canJoinGroups: Bool
    ) {
        self.id = id
        self.username = username
        self.firstName = firstName
        self.canJoinGroups = canJoinGroups
    }
}

// MARK: - Network errors

/// `fetchBotInfo` 호출 시 발생할 수 있는 에러.
public enum TelegramNetworkError: Error, LocalizedError, Sendable {
    /// 토큰 형식 자체가 잘못됨.
    case invalidTokenFormat(String)
    /// HTTP 응답이 비정상적 (예: 401 Unauthorized).
    case httpError(Int)
    /// `ok: false` 응답 — Telegram API 오류.
    case apiError(String)
    /// JSON 파싱 실패.
    case decodingFailed
    /// 네트워크 연결 실패.
    case networkUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .invalidTokenFormat(let reason):
            return "토큰 형식 오류: \(reason)"
        case .httpError(let code):
            return "HTTP 오류 \(code) — 토큰이 유효하지 않거나 만료됐을 수 있어요."
        case .apiError(let description):
            return "Telegram API 오류: \(description)"
        case .decodingFailed:
            return "서버 응답 파싱 실패 — 잠시 후 다시 시도해 주세요."
        case .networkUnavailable(let detail):
            return "네트워크 연결 실패: \(detail)"
        }
    }
}

// MARK: - URLSession protocol (unit test 주입용)

/// URLSession의 데이터 요청 기능을 추상화하는 protocol.
/// 실제 코드는 `URLSession.shared`를 사용하고, 테스트에서는 mock을 주입.
public protocol TelegramURLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: TelegramURLSessionProtocol {}

// MARK: - Network extension

public extension TelegramTokenValidator {

    /// `getMe` API 호출 — 토큰 유효성 실제 검증 + 봇 정보 반환.
    ///
    /// - Parameters:
    ///   - token: Telegram 봇 토큰 (형식 검증 자동 포함).
    ///   - session: URLSession (기본값: `.shared`). 테스트 시 mock 주입 가능.
    /// - Returns: `TelegramBotInfo` — 봇 ID, username, firstName, canJoinGroups.
    /// - Throws: `TelegramNetworkError` (형식 오류 / HTTP 오류 / 파싱 실패 / 네트워크 실패).
    static func fetchBotInfo(
        token: String,
        session: any TelegramURLSessionProtocol = URLSession.shared
    ) async throws -> TelegramBotInfo {
        // 1. 형식 검증 먼저
        let result = TelegramTokenValidator.validate(token)
        if case .invalid(let reason) = result {
            throw TelegramNetworkError.invalidTokenFormat(reason)
        }

        let trimmed = token.trimmingCharacters(in: .whitespaces)

        // 2. URL 구성
        guard let url = URL(string: "https://api.telegram.org/bot\(trimmed)/getMe") else {
            throw TelegramNetworkError.invalidTokenFormat("URL 구성 실패")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0

        // 3. 네트워크 호출
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw TelegramNetworkError.networkUnavailable(urlError.localizedDescription)
        } catch {
            throw TelegramNetworkError.networkUnavailable(error.localizedDescription)
        }

        // 4. HTTP 상태 코드 검증
        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode != 200 {
            throw TelegramNetworkError.httpError(httpResponse.statusCode)
        }

        // 5. JSON 파싱
        let decoded: TelegramGetMeResponse
        do {
            decoded = try JSONDecoder().decode(TelegramGetMeResponse.self, from: data)
        } catch {
            throw TelegramNetworkError.decodingFailed
        }

        guard decoded.ok, let result2 = decoded.result else {
            throw TelegramNetworkError.apiError(decoded.description ?? "알 수 없는 오류")
        }

        return TelegramBotInfo(
            id: result2.id,
            username: result2.username ?? "",
            firstName: result2.firstName,
            canJoinGroups: result2.canJoinGroups ?? false
        )
    }
}

// MARK: - Private response types

private struct TelegramGetMeResponse: Decodable {
    let ok: Bool
    let result: TelegramUserResult?
    let description: String?
}

private struct TelegramUserResult: Decodable {
    let id: Int64
    let firstName: String
    let username: String?
    let canJoinGroups: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case username
        case canJoinGroups = "can_join_groups"
    }
}
