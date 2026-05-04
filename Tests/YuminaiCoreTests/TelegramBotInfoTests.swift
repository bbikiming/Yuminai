import Foundation
import Testing
@testable import YuminaiCore

// MARK: - TelegramBotInfo (ADR-093 Phase 2)

@Suite("TelegramBotInfo (ADR-093 Phase 2)")
struct TelegramBotInfoTests {

    // MARK: - Equatable

    @Test("TelegramBotInfo — 동일 값은 동등")
    func equalBotInfo() {
        let a = TelegramBotInfo(id: 123, username: "mybot", firstName: "My Bot", canJoinGroups: true)
        let b = TelegramBotInfo(id: 123, username: "mybot", firstName: "My Bot", canJoinGroups: true)
        #expect(a == b)
    }

    @Test("TelegramBotInfo — username 다르면 불일치")
    func unequalByUsername() {
        let a = TelegramBotInfo(id: 123, username: "botA", firstName: "Bot", canJoinGroups: false)
        let b = TelegramBotInfo(id: 123, username: "botB", firstName: "Bot", canJoinGroups: false)
        #expect(a != b)
    }

    @Test("TelegramBotInfo — id 다르면 불일치")
    func unequalById() {
        let a = TelegramBotInfo(id: 1, username: "bot", firstName: "Bot", canJoinGroups: false)
        let b = TelegramBotInfo(id: 2, username: "bot", firstName: "Bot", canJoinGroups: false)
        #expect(a != b)
    }

    @Test("TelegramBotInfo — canJoinGroups false → true 불일치")
    func unequalByCanJoinGroups() {
        let a = TelegramBotInfo(id: 1, username: "bot", firstName: "Bot", canJoinGroups: false)
        let b = TelegramBotInfo(id: 1, username: "bot", firstName: "Bot", canJoinGroups: true)
        #expect(a != b)
    }

    // MARK: - Sendable conformance (컴파일 타임 검증)

    @Test("TelegramBotInfo — Sendable 준수 (Task 경계 통과)")
    func sendableConformance() async {
        let info = TelegramBotInfo(id: 999, username: "testbot", firstName: "Test", canJoinGroups: true)
        let result = await Task { info }.value
        #expect(result == info)
    }
}

// MARK: - TelegramNetworkError

@Suite("TelegramNetworkError (ADR-093 Phase 2)")
struct TelegramNetworkErrorTests {

    @Test("invalidTokenFormat — errorDescription 포함")
    func invalidTokenFormatDescription() {
        let error = TelegramNetworkError.invalidTokenFormat("토큰이 짧아요")
        #expect(error.errorDescription?.isEmpty == false)
        #expect(error.errorDescription?.contains("토큰") == true)
    }

    @Test("httpError 401 — errorDescription 포함")
    func httpErrorDescription() {
        let error = TelegramNetworkError.httpError(401)
        #expect(error.errorDescription?.contains("401") == true)
    }

    @Test("apiError — errorDescription 포함")
    func apiErrorDescription() {
        let error = TelegramNetworkError.apiError("Unauthorized")
        #expect(error.errorDescription?.contains("Unauthorized") == true)
    }

    @Test("decodingFailed — errorDescription 비어있지 않음")
    func decodingFailedDescription() {
        let error = TelegramNetworkError.decodingFailed
        #expect(error.errorDescription?.isEmpty == false)
    }

    @Test("networkUnavailable — errorDescription 포함")
    func networkUnavailableDescription() {
        let error = TelegramNetworkError.networkUnavailable("연결 끊김")
        #expect(error.errorDescription?.contains("연결 끊김") == true)
    }
}

// MARK: - TelegramTokenValidator.fetchBotInfo — mock 기반

/// URLSession mock (형식 검증 + 파싱 실패 경로 테스트용).
private struct MockURLSession: TelegramURLSessionProtocol, @unchecked Sendable {
    let stubbedData: Data
    let stubbedResponse: URLResponse
    let stubbedError: Error?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let error = stubbedError { throw error }
        return (stubbedData, stubbedResponse)
    }
}

private func makeHTTPResponse(statusCode: Int, url: URL = URL(string: "https://api.telegram.org")!) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
}

@Suite("TelegramTokenValidator+Network (ADR-093 Phase 2)")
struct TelegramTokenValidatorNetworkTests {

    // MARK: - 형식 검증 실패

    @Test("fetchBotInfo — 빈 토큰은 invalidTokenFormat 에러")
    func invalidTokenThrows() async {
        let session = MockURLSession(
            stubbedData: Data(),
            stubbedResponse: makeHTTPResponse(statusCode: 200),
            stubbedError: nil
        )
        do {
            _ = try await TelegramTokenValidator.fetchBotInfo(token: "", session: session)
            Issue.record("Expected error to be thrown")
        } catch let error as TelegramNetworkError {
            if case .invalidTokenFormat = error { } else {
                Issue.record("Expected invalidTokenFormat, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - HTTP 에러

    @Test("fetchBotInfo — HTTP 401 응답 시 httpError 에러")
    func httpErrorThrows() async {
        let body = Data("{\"ok\":false,\"error_code\":401,\"description\":\"Unauthorized\"}".utf8)
        let session = MockURLSession(
            stubbedData: body,
            stubbedResponse: makeHTTPResponse(statusCode: 401),
            stubbedError: nil
        )
        do {
            _ = try await TelegramTokenValidator.fetchBotInfo(
                token: "123456:ABCdef",
                session: session
            )
            Issue.record("Expected error to be thrown")
        } catch let error as TelegramNetworkError {
            if case .httpError(let code) = error {
                #expect(code == 401)
            } else {
                Issue.record("Expected httpError, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - 파싱 성공

    @Test("fetchBotInfo — 정상 응답에서 TelegramBotInfo 파싱")
    func successfulParsing() async throws {
        let json = """
        {
            "ok": true,
            "result": {
                "id": 110201543,
                "first_name": "My Yuminai Bot",
                "username": "YuminaiBot",
                "can_join_groups": true,
                "can_read_all_group_messages": false,
                "supports_inline_queries": false,
                "is_bot": true
            }
        }
        """
        let session = MockURLSession(
            stubbedData: Data(json.utf8),
            stubbedResponse: makeHTTPResponse(statusCode: 200),
            stubbedError: nil
        )
        let info = try await TelegramTokenValidator.fetchBotInfo(
            token: "110201543:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw",
            session: session
        )
        #expect(info.id == 110201543)
        #expect(info.username == "YuminaiBot")
        #expect(info.firstName == "My Yuminai Bot")
        #expect(info.canJoinGroups == true)
    }

    // MARK: - ok: false

    @Test("fetchBotInfo — ok:false 응답 시 apiError 에러")
    func apiErrorThrows() async {
        let json = """
        {
            "ok": false,
            "error_code": 404,
            "description": "Not Found"
        }
        """
        let session = MockURLSession(
            stubbedData: Data(json.utf8),
            stubbedResponse: makeHTTPResponse(statusCode: 200),
            stubbedError: nil
        )
        do {
            _ = try await TelegramTokenValidator.fetchBotInfo(
                token: "123456:ABCdef",
                session: session
            )
            Issue.record("Expected error")
        } catch let error as TelegramNetworkError {
            if case .apiError = error { } else {
                Issue.record("Expected apiError, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - 네트워크 실패

    @Test("fetchBotInfo — URLError 발생 시 networkUnavailable 에러")
    func networkErrorThrows() async {
        let session = MockURLSession(
            stubbedData: Data(),
            stubbedResponse: makeHTTPResponse(statusCode: 200),
            stubbedError: URLError(.notConnectedToInternet)
        )
        do {
            _ = try await TelegramTokenValidator.fetchBotInfo(
                token: "123456:ABCdef",
                session: session
            )
            Issue.record("Expected error")
        } catch let error as TelegramNetworkError {
            if case .networkUnavailable = error { } else {
                Issue.record("Expected networkUnavailable, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - 파싱 실패

    @Test("fetchBotInfo — 잘못된 JSON 응답 시 decodingFailed 에러")
    func decodingFailedThrows() async {
        let session = MockURLSession(
            stubbedData: Data("not-json".utf8),
            stubbedResponse: makeHTTPResponse(statusCode: 200),
            stubbedError: nil
        )
        do {
            _ = try await TelegramTokenValidator.fetchBotInfo(
                token: "123456:ABCdef",
                session: session
            )
            Issue.record("Expected error")
        } catch let error as TelegramNetworkError {
            if case .decodingFailed = error { } else {
                Issue.record("Expected decodingFailed, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
