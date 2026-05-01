import Foundation
import Testing
import YuminaiCore
@testable import YuminaiTelegram

@Suite("MockTelegramBot")
struct MockTelegramBotTests {
    @Test("send는 sentLog에 기록되고 SentTelegramMessage를 반환한다")
    func sendLogsAndReturns() async throws {
        let bot = MockTelegramBot()
        let result = try await bot.send("hello", to: 12345)
        #expect(result.chatId == 12345)
        let log = await bot.sentLog
        #expect(log.count == 1)
        #expect(log[0].text == "hello")
        #expect(log[0].chatId == 12345)
    }

    @Test("edit은 editLog에 기록된다")
    func editLogs() async throws {
        let bot = MockTelegramBot()
        try await bot.edit(messageId: 99, in: 12345, text: "updated")
        let log = await bot.editLog
        #expect(log.count == 1)
        #expect(log[0].messageId == 99)
        #expect(log[0].text == "updated")
    }

    @Test("injectIncoming으로 수신 메시지를 시뮬레이션할 수 있다")
    func injectIncomingDelivers() async {
        let bot = MockTelegramBot()
        let test = IncomingTelegramMessage(
            updateId: 1, userId: 100, chatId: 200, text: "hi"
        )

        let receivedTask = Task<IncomingTelegramMessage?, Never> {
            for await msg in bot.incoming {
                return msg
            }
            return nil
        }

        bot.injectIncoming(test)

        // 짧게 대기 후 cancel
        try? await Task.sleep(for: .milliseconds(50))
        receivedTask.cancel()

        let received = await receivedTask.value
        #expect(received == test)
    }
}

@Suite("TelegramAlertDispatcher")
struct TelegramAlertDispatcherTests {
    @Test("workComplete 정책 ON일 때 송신")
    func sendsWhenPolicyOn() async {
        let bot = MockTelegramBot()
        let dispatcher = TelegramAlertDispatcher(
            client: bot,
            policy: TelegramAlertPolicy(sendOnComplete: true),
            chatId: 42
        )
        await dispatcher.dispatch(category: .workComplete, message: "done")
        let log = await bot.sentLog
        #expect(log.count == 1)
        #expect(log[0].chatId == 42)
        #expect(log[0].text.contains("[COMPLETE]"))
        #expect(log[0].text.contains("done"))
    }

    @Test("workComplete 정책 OFF일 때 송신 안 함")
    func skipsWhenPolicyOff() async {
        let bot = MockTelegramBot()
        let dispatcher = TelegramAlertDispatcher(
            client: bot,
            policy: TelegramAlertPolicy(sendOnComplete: false, sendOnError: true),
            chatId: 42
        )
        await dispatcher.dispatch(category: .workComplete, message: "done")
        let log = await bot.sentLog
        #expect(log.isEmpty)
    }

    @Test("정책 변경이 즉시 반영된다")
    func policyUpdateAppliesImmediately() async {
        let bot = MockTelegramBot()
        let dispatcher = TelegramAlertDispatcher(
            client: bot,
            policy: TelegramAlertPolicy(sendOnComplete: false),
            chatId: 1
        )
        await dispatcher.dispatch(category: .workComplete, message: "x")
        var log = await bot.sentLog
        #expect(log.isEmpty)

        await dispatcher.updatePolicy(TelegramAlertPolicy(sendOnComplete: true))
        await dispatcher.dispatch(category: .workComplete, message: "y")
        log = await bot.sentLog
        #expect(log.count == 1)
    }
}

@Suite("EchoCommandRouter")
struct EchoCommandRouterTests {
    @Test("text가 있으면 echo: prefix로 반환")
    func echoesText() async {
        let router = EchoCommandRouter()
        let response = await router.handle(
            IncomingTelegramMessage(updateId: 1, userId: 1, chatId: 1, text: "hi")
        )
        #expect(response == "echo: hi")
    }

    @Test("text가 nil이면 nil 반환")
    func nilTextReturnsNil() async {
        let router = EchoCommandRouter()
        let response = await router.handle(
            IncomingTelegramMessage(updateId: 1, userId: 1, chatId: 1, text: nil)
        )
        #expect(response == nil)
    }
}
