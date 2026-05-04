import Foundation
import Testing
@testable import YuminaiTelegram
@testable import YuminaiCore

/// **ADR-095 Phase 4** — TelegramFirstMessageDetector 유닛 테스트.
///
/// `TelegramURLSessionProtocol` mock을 주입하여 실제 네트워크 없이 테스트.
@Suite("TelegramFirstMessageDetector (ADR-095 Phase 4)")
struct TelegramFirstMessageDetectorTests {

    // MARK: - Mock URLSession

    /// `/start` 메시지가 포함된 응답을 반환하는 mock.
    private final class MockStartSession: TelegramURLSessionProtocol, @unchecked Sendable {
        let responses: [Data]
        private var callCount = 0

        init(responses: [Data]) {
            self.responses = responses
        }

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            let idx = min(callCount, responses.count - 1)
            callCount += 1
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            // 두 번째 호출 이후는 cancellation을 시뮬레이션하기 위해 빈 결과 반환
            if callCount > responses.count {
                try await Task.sleep(nanoseconds: 10_000_000_000)  // 10s — cancelled 예상
            }
            return (responses[idx], response)
        }
    }

    /// 빈 updates 반환 (no /start)
    private final class EmptyUpdatesSession: TelegramURLSessionProtocol, @unchecked Sendable {
        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            let json = #"{"ok":true,"result":[]}"#
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            // 무한 루프 방지 — 1ms 뒤 취소될 예정
            try await Task.sleep(nanoseconds: 500_000_000)
            return (json.data(using: .utf8)!, response)
        }
    }

    // MARK: - 헬퍼

    private func makeStartMessageJSON(userId: Int64, username: String?, firstName: String, chatId: Int64) -> Data {
        let usernameStr = username.map { "\"\($0)\"" } ?? "null"
        let json = """
        {
          "ok": true,
          "result": [{
            "update_id": 1,
            "message": {
              "message_id": 42,
              "from": {
                "id": \(userId),
                "first_name": "\(firstName)",
                "username": \(usernameStr)
              },
              "chat": { "id": \(chatId) },
              "date": 1700000000,
              "text": "/start"
            }
          }]
        }
        """
        return json.data(using: .utf8)!
    }

    // MARK: - 테스트

    @Test("빈 토큰이면 throw")
    func emptyTokenThrows() async throws {
        let detector = TelegramFirstMessageDetector()
        do {
            _ = try await detector.startDetecting(token: "")
            #expect(Bool(false), "Should have thrown")
        } catch is TelegramNetworkError {
            // 성공
        }
    }

    @Test("/start 메시지 감지 → Detection emit")
    func detectsStartMessage() async throws {
        let responseData = makeStartMessageJSON(
            userId: 123456,
            username: "testuser",
            firstName: "Test",
            chatId: 123456
        )

        let session = MockStartSession(responses: [responseData])
        let detector = TelegramFirstMessageDetector(session: session)

        let stream = try await detector.startDetecting(token: "123456789:AABBCCDDEEFFaabbccddeeff-xyz")

        // 첫 번째 Detection 기다리기 (타임아웃 있음)
        let detection = await withTaskGroup(of: TelegramFirstMessageDetector.Detection?.self) { group in
            group.addTask {
                for await d in stream { return d }
                return nil
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                return nil
            }
            for await result in group {
                group.cancelAll()
                return result
            }
            return nil
        }

        await detector.stop()

        #expect(detection?.userId == 123456)
        #expect(detection?.username == "testuser")
        #expect(detection?.firstName == "Test")
        #expect(detection?.chatId == 123456)
    }

    @Test("/start 없는 메시지는 emit 안 함")
    func nonStartMessageNotEmitted() async throws {
        let json = """
        {
          "ok": true,
          "result": [{
            "update_id": 2,
            "message": {
              "message_id": 43,
              "from": { "id": 99999, "first_name": "Other" },
              "chat": { "id": 99999 },
              "date": 1700000001,
              "text": "/help"
            }
          }]
        }
        """.data(using: .utf8)!

        let session = MockStartSession(responses: [json])
        let detector = TelegramFirstMessageDetector(session: session)
        let stream = try await detector.startDetecting(token: "123456789:AABBCCDDEEFFaabbccddeeff-xyz")

        // 0.5초 기다려도 emit 없어야
        let detection = await withTaskGroup(of: TelegramFirstMessageDetector.Detection?.self) { group in
            group.addTask {
                for await d in stream { return d }
                return nil
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 500_000_000)
                return nil
            }
            for await result in group {
                group.cancelAll()
                return result
            }
            return nil
        }

        await detector.stop()
        #expect(detection == nil)
    }

    @Test("stop() 호출 시 stream 종료")
    func stopEndsStream() async throws {
        let session = EmptyUpdatesSession()
        let detector = TelegramFirstMessageDetector(session: session)
        let stream = try await detector.startDetecting(token: "123456789:AABBCCDDEEFFaabbccddeeff-xyz")

        // 즉시 stop
        await detector.stop()

        // stream이 종료되어야
        var count = 0
        for await _ in stream {
            count += 1
            if count > 5 { break }
        }
        #expect(count == 0)
    }

    @Test("Detection — Identifiable: 각 id는 고유")
    func detectionIdentifiable() {
        let d1 = TelegramFirstMessageDetector.Detection(
            userId: 1, username: nil, firstName: "A", chatId: 1
        )
        let d2 = TelegramFirstMessageDetector.Detection(
            userId: 1, username: nil, firstName: "A", chatId: 1
        )
        #expect(d1.id != d2.id)
    }

    @Test("Detection — username nil 허용")
    func detectionNilUsername() {
        let d = TelegramFirstMessageDetector.Detection(
            userId: 100, username: nil, firstName: "NoUsername", chatId: 100
        )
        #expect(d.username == nil)
        #expect(d.firstName == "NoUsername")
    }
}
