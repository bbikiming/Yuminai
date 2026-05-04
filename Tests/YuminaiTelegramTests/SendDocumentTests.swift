import Foundation
import Testing
import YuminaiCore
@testable import YuminaiTelegram

/// **ADR-096 Phase C** — sendDocument 단위 테스트.
@Suite("sendDocument (ADR-096)")
struct SendDocumentTests {

    @Test("MockTelegramBot.sendDocument는 sentDocumentLog에 기록되고 SentTelegramMessage를 반환한다")
    func mockSendDocumentLogs() async throws {
        let bot = MockTelegramBot()
        let payload = "hello world".data(using: .utf8)!
        let result = try await bot.sendDocument(
            fileName: "diff.txt",
            data: payload,
            caption: "patch preview",
            to: 42
        )
        #expect(result.chatId == 42)

        let docLog = await bot.sentDocumentLog
        #expect(docLog.count == 1)
        #expect(docLog[0].fileName == "diff.txt")
        #expect(docLog[0].caption == "patch preview")
        #expect(docLog[0].chatId == 42)
        #expect(docLog[0].data == payload)
    }

    @Test("MockTelegramBot.sendDocument는 sentLog에도 기록된다")
    func mockSendDocumentAlsoLogsInSentLog() async throws {
        let bot = MockTelegramBot()
        let payload = Data(repeating: 0xAB, count: 100)
        _ = try await bot.sendDocument(
            fileName: "log.txt",
            data: payload,
            caption: nil,
            to: 99
        )
        let sent = await bot.sentLog
        #expect(sent.count == 1)
        #expect(sent[0].chatId == 99)
    }

    @Test("caption nil이면 sentLog에는 fileName이 기록된다")
    func captionNilUsesFileName() async throws {
        let bot = MockTelegramBot()
        _ = try await bot.sendDocument(
            fileName: "output.log",
            data: Data([0x01]),
            caption: nil,
            to: 7
        )
        let sent = await bot.sentLog
        #expect(sent[0].text == "output.log")
    }

    @Test("LiveTelegramBot.sendDocument — 50MB 초과 시 즉시 throw")
    func liveBot_rejectsOver50MB() async {
        let token = "test:token"
        let bot = LiveTelegramBot(token: token, allowedUserIds: [])
        // 50MB + 1 byte
        let oversized = Data(count: 50 * 1024 * 1024 + 1)
        do {
            _ = try await bot.sendDocument(fileName: "big.bin", data: oversized, caption: nil, to: 1)
            Issue.record("50MB 초과 데이터를 전송했는데 throw되지 않음")
        } catch let error as NSError {
            #expect(error.domain == "TelegramBot")
            #expect(error.code == -2)
        }
    }

    @Test("caption 1024자 초과는 프로토콜 명세 준수 — truncate 기대 (MockTelegramBot에서 그대로 보관)")
    func captionStoredAsProvidedInMock() async throws {
        let bot = MockTelegramBot()
        let longCaption = String(repeating: "가", count: 2000)
        _ = try await bot.sendDocument(
            fileName: "file.txt",
            data: Data([0x01]),
            caption: longCaption,
            to: 1
        )
        let docLog = await bot.sentDocumentLog
        // Mock은 truncate 안 함 — 입력 그대로 저장 (LiveBot이 truncate)
        #expect(docLog[0].caption == longCaption)
    }
}
