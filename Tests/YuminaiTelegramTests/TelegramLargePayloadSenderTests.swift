import Foundation
import Testing
import YuminaiCore
@testable import YuminaiTelegram

/// **ADR-097** — TelegramLargePayloadSender 유닛 테스트.
///
/// MockTelegramBot을 사용해 send/sendDocument 라우팅을 검증한다.
@Suite("TelegramLargePayloadSender (ADR-097)")
struct TelegramLargePayloadSenderTests {

    // MARK: - 라우팅 결정 (RoutingDecision)

    @Test("10KB — send 결정")
    func smallTextRoutesToSend() {
        let byteCount = 10 * 1024  // 10KB
        let decision = TelegramLargePayloadSender.routingDecision(byteCount: byteCount)
        #expect(decision == .sendTruncated)
    }

    @Test("3500 bytes — send 결정 (4000 미만)")
    func verySmallTextRoutesToSend() {
        let decision = TelegramLargePayloadSender.routingDecision(byteCount: 3500)
        #expect(decision == .send)
    }

    @Test("1MB — sendTruncated 결정 (4000 이상, 5MB 미만)")
    func mediumTextRoutesToSendTruncated() {
        let byteCount = 1 * 1024 * 1024  // 1MB
        let decision = TelegramLargePayloadSender.routingDecision(byteCount: byteCount)
        #expect(decision == .sendTruncated)
    }

    @Test("6MB — sendDocument 결정")
    func largeTextRoutesToDocument() {
        let byteCount = 6 * 1024 * 1024  // 6MB
        let decision = TelegramLargePayloadSender.routingDecision(byteCount: byteCount)
        #expect(decision == .sendDocument)
    }

    // MARK: - 실제 전송 동작

    @Test("짧은 텍스트 — client.send 호출")
    func shortTextCallsSend() async throws {
        let bot = MockTelegramBot()
        let shortText = "Hello Telegram!"  // 15 bytes

        try await TelegramLargePayloadSender.sendOrAttach(
            text: shortText,
            fileName: "msg.txt",
            caption: "preview",
            to: 1234,
            client: bot
        )

        let sentLog = await bot.sentLog
        let docLog = await bot.sentDocumentLog

        #expect(sentLog.count == 1)
        #expect(docLog.count == 0)
        #expect(sentLog[0].text.contains("Hello Telegram!"))
    }

    @Test("5MB+ 텍스트 — sendDocument 호출")
    func largeTextCallsSendDocument() async throws {
        let bot = MockTelegramBot()
        // 6MB 텍스트 생성 (반복 문자열)
        let chunk = String(repeating: "A", count: 1024)
        let largeText = String(repeating: chunk, count: 6 * 1024)  // ~6MB

        try await TelegramLargePayloadSender.sendOrAttach(
            text: largeText,
            fileName: "large_diff.txt",
            caption: "Large diff preview",
            to: 5678,
            client: bot
        )

        let docLog = await bot.sentDocumentLog

        #expect(docLog.count == 1)
        #expect(docLog[0].fileName == "large_diff.txt")
        #expect(docLog[0].chatId == 5678)
    }

    @Test("51MB 텍스트 — exceedsAbsoluteMax 에러 throw")
    func exceedingAbsoluteMaxThrows() async throws {
        let bot = MockTelegramBot()
        // 51MB 텍스트
        let chunk = String(repeating: "B", count: 1024)
        let hugeText = String(repeating: chunk, count: 51 * 1024)

        await #expect(throws: TelegramLargePayloadError.self) {
            try await TelegramLargePayloadSender.sendOrAttach(
                text: hugeText,
                fileName: "huge.txt",
                caption: "too big",
                to: 9999,
                client: bot
            )
        }
    }
}
