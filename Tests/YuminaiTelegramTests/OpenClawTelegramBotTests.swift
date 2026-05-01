import Foundation
import Testing
@testable import YuminaiTelegram
import YuminaiCore

// MARK: - Test fixtures

/// Mock process runner — 호출 인자를 기록하고 미리 정의된 응답을 반환.
private actor MockProcessRunner {
    var calls: [(URL, [String])] = []
    var responses: [ProcessOutput] = []
    var defaultResponse: ProcessOutput

    init(responses: [ProcessOutput] = [], defaultResponse: ProcessOutput = ProcessOutput(exitCode: 0, stdout: "", stderr: "")) {
        self.responses = responses
        self.defaultResponse = defaultResponse
    }

    func enqueue(_ output: ProcessOutput) {
        responses.append(output)
    }

    func makeRunner() -> OpenClawTelegramBot.ProcessRun {
        return { [weak self] url, args in
            await self?.record(url, args)
            return await self?.next() ?? ProcessOutput(exitCode: 0, stdout: "", stderr: "")
        }
    }

    private func record(_ url: URL, _ args: [String]) {
        calls.append((url, args))
    }

    private func next() -> ProcessOutput {
        if responses.isEmpty { return defaultResponse }
        return responses.removeFirst()
    }
}

private func makeConfig(target: String = "@me", allowed: Set<Int64> = []) -> OpenClawTelegramBot.Configuration {
    OpenClawTelegramBot.Configuration(
        binaryURL: URL(fileURLWithPath: "/opt/homebrew/bin/openclaw"),
        target: target,
        allowedUserIds: allowed
    )
}

// MARK: - send

@Suite("OpenClawTelegramBot — send")
struct OpenClawSendTests {
    @Test("send는 openclaw message send를 정확한 인자로 호출")
    func sendInvokesCli() async throws {
        let runner = MockProcessRunner(defaultResponse: ProcessOutput(
            exitCode: 0,
            stdout: #"{"messageId": 42}"#,
            stderr: ""
        ))
        let bot = OpenClawTelegramBot(
            configuration: makeConfig(target: "@daon"),
            processRun: await runner.makeRunner()
        )

        let sent = try await bot.send("hello", to: 12345)

        #expect(sent.messageId == 42)
        #expect(sent.chatId == 12345)

        let calls = await runner.calls
        #expect(calls.count == 1)
        let args = calls[0].1
        #expect(args.contains("send"))
        #expect(args.contains("--channel"))
        #expect(args.contains("telegram"))
        #expect(args.contains("--target"))
        #expect(args.contains("@daon"))
        #expect(args.contains("--message"))
        #expect(args.contains("hello"))
        #expect(args.contains("--json"))
    }

    @Test("CLI exit != 0이면 OpenClawError.cliFailed throw")
    func nonZeroExitThrows() async throws {
        let runner = MockProcessRunner(defaultResponse: ProcessOutput(
            exitCode: 1,
            stdout: "",
            stderr: "telegram channel not configured"
        ))
        let bot = OpenClawTelegramBot(
            configuration: makeConfig(),
            processRun: await runner.makeRunner()
        )

        await #expect(throws: OpenClawError.self) {
            _ = try await bot.send("x", to: 1)
        }
    }

    @Test("messageId 파싱 실패 시 0으로 fallback")
    func missingMessageIdFallsBackToZero() async throws {
        let runner = MockProcessRunner(defaultResponse: ProcessOutput(
            exitCode: 0,
            stdout: #"{"ok": true}"#,
            stderr: ""
        ))
        let bot = OpenClawTelegramBot(
            configuration: makeConfig(),
            processRun: await runner.makeRunner()
        )
        let sent = try await bot.send("x", to: 99)
        #expect(sent.messageId == 0)
        #expect(sent.chatId == 99)
    }

    @Test("messageId가 result/data 중첩 안에 있어도 파싱")
    func parsesNestedMessageId() async throws {
        let runner = MockProcessRunner(defaultResponse: ProcessOutput(
            exitCode: 0,
            stdout: #"{"result": {"message_id": 777}}"#,
            stderr: ""
        ))
        let bot = OpenClawTelegramBot(
            configuration: makeConfig(),
            processRun: await runner.makeRunner()
        )
        let sent = try await bot.send("x", to: 1)
        #expect(sent.messageId == 777)
    }
}

// MARK: - parse

@Suite("OpenClawTelegramBot — parse")
struct OpenClawParseTests {
    @Test("parseIncoming은 array 최상위 형식을 파싱")
    func parsesTopLevelArray() {
        let json = #"""
        [
          {"updateId": 100, "from": {"id": 7}, "chat": {"id": -100}, "text": "hi"}
        ]
        """#
        let result = OpenClawTelegramBot.parseIncoming(from: json)
        #expect(result.count == 1)
        #expect(result[0].updateId == 100)
        #expect(result[0].userId == 7)
        #expect(result[0].chatId == -100)
        #expect(result[0].text == "hi")
    }

    @Test("parseIncoming은 messages key 안의 array도 파싱")
    func parsesMessagesKey() {
        let json = #"""
        {"messages": [
          {"update_id": 200, "from": {"id": 8}, "chat": {"id": 1}, "text": "test"}
        ]}
        """#
        let result = OpenClawTelegramBot.parseIncoming(from: json)
        #expect(result.count == 1)
        #expect(result[0].updateId == 200)
    }

    @Test("parseIncoming은 알 수 없는 형식이면 빈 배열")
    func unknownShapeReturnsEmpty() {
        let result = OpenClawTelegramBot.parseIncoming(from: "not json")
        #expect(result.isEmpty)

        let result2 = OpenClawTelegramBot.parseIncoming(from: #"{"foo": "bar"}"#)
        #expect(result2.isEmpty)
    }

    @Test("updateId가 없거나 0이면 메시지 무시")
    func zeroUpdateIdSkipped() {
        let json = #"""
        [
          {"from": {"id": 1}, "text": "noid"},
          {"updateId": 0, "from": {"id": 1}, "text": "zero"},
          {"updateId": 5, "from": {"id": 1}, "text": "ok"}
        ]
        """#
        let result = OpenClawTelegramBot.parseIncoming(from: json)
        #expect(result.count == 1)
        #expect(result[0].updateId == 5)
    }
}

// MARK: - edit

@Suite("OpenClawTelegramBot — edit")
struct OpenClawEditTests {
    @Test("edit은 message edit + --message-id 인자를 전달")
    func editPassesMessageId() async throws {
        let runner = MockProcessRunner()
        let bot = OpenClawTelegramBot(
            configuration: makeConfig(),
            processRun: await runner.makeRunner()
        )
        try await bot.edit(messageId: 555, in: 1, text: "updated")

        let calls = await runner.calls
        #expect(calls.count == 1)
        let args = calls[0].1
        #expect(args.contains("edit"))
        #expect(args.contains("--message-id"))
        #expect(args.contains("555"))
        #expect(args.contains("updated"))
    }
}

// MARK: - OpenClawDetector

@Suite("OpenClawDetector")
struct OpenClawDetectorTests {
    @Test("바이너리가 없으면 installed=false")
    func missingBinary() async {
        let detector = OpenClawDetector(
            binaryPath: "/nonexistent/openclaw"
        )
        let status = await detector.detect()
        #expect(status.installed == false)
        #expect(status.telegramActive == false)
    }
}
