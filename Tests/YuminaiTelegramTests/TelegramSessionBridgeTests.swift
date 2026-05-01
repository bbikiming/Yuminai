import Foundation
import Testing
import YuminaiCore
@testable import YuminaiTelegram

private func makeConfig(
    forwardAssistant: Bool = true,
    forwardToolCalls: Bool = true,
    flush: Duration = .milliseconds(50)
) -> TelegramSessionBridge.Configuration {
    TelegramSessionBridge.Configuration(
        chatId: 1001,
        workspaceName: "test-workspace",
        forwardAssistant: forwardAssistant,
        forwardToolCalls: forwardToolCalls,
        maxChunkSize: 100,
        flushInterval: flush
    )
}

@Suite("TelegramSessionBridge — chunking")
struct BridgeChunkingTests {
    @Test("짧은 텍스트는 단일 chunk")
    func singleChunkForShortText() {
        let chunks = TelegramSessionBridge.chunked("hello world", maxSize: 100)
        #expect(chunks == ["hello world"])
    }

    @Test("긴 텍스트는 여러 chunk + 줄바꿈 경계 우선")
    func chunksAtNewlineBoundary() {
        let text = """
        first line of content
        second line that is long
        third line continues here
        """
        let chunks = TelegramSessionBridge.chunked(text, maxSize: 30)
        #expect(chunks.count >= 2)
        // 각 chunk는 maxSize 이하
        for chunk in chunks {
            #expect(chunk.count <= 30)
        }
    }

    @Test("줄바꿈 없으면 공백 경계에서 자름")
    func chunksAtSpaceBoundary() {
        let text = String(repeating: "word ", count: 30)  // 150 chars, no newline
        let chunks = TelegramSessionBridge.chunked(text, maxSize: 50)
        #expect(chunks.count >= 3)
        for chunk in chunks {
            #expect(chunk.count <= 50)
        }
    }

    @Test("연결한 chunk가 원문과 (공백 차이만 빼면) 일치")
    func roundtripPreservesContent() {
        let text = "alpha beta gamma delta epsilon zeta"
        let chunks = TelegramSessionBridge.chunked(text, maxSize: 12)
        let joined = chunks.joined(separator: " ")
        // 공백 정규화 후 비교
        let normalize: (String) -> String = { $0.split(separator: " ").joined(separator: " ") }
        #expect(normalize(joined) == normalize(text))
    }
}

@Suite("TelegramSessionBridge — tool summarize")
struct BridgeToolSummaryTests {
    @Test("input 비어있으면 도구 이름만")
    func emptyInput() {
        let s = TelegramSessionBridge.summarizeToolCall(name: "Read", input: "")
        #expect(s == "Read")
    }

    @Test("input 있으면 첫 줄 + 80자 cap")
    func longInputCapped() {
        let long = String(repeating: "a", count: 200)
        let s = TelegramSessionBridge.summarizeToolCall(name: "Bash", input: long)
        #expect(s.hasPrefix("Bash — "))
        #expect(s.count <= 90)  // "Bash — " (7) + 80 + "…" (1) = 88
        #expect(s.hasSuffix("…"))
    }

    @Test("멀티라인 input은 첫 줄만")
    func multilineInputUsesFirstLine() {
        let s = TelegramSessionBridge.summarizeToolCall(
            name: "Edit",
            input: "first line\nsecond line\nthird line"
        )
        #expect(s == "Edit — first line")
    }
}

@Suite("TelegramSessionBridge — event forwarding")
struct BridgeForwardingTests {
    @Test("text event는 flush 후 텔레그램에 전송")
    func textIsFlushedToBot() async throws {
        let bot = MockTelegramBot()
        let bridge = TelegramSessionBridge(client: bot, configuration: makeConfig())
        await bridge.consume(event: .text("partial response"))
        // 명시적 flush를 위해 completed 이벤트 사용 (debounce 회피)
        await bridge.consume(event: .completed(exitCode: 0))

        let log = await bot.sentLog
        let texts = log.map(\.text)
        #expect(texts.contains("partial response"))
        #expect(texts.contains { $0.contains("✅ 완료") })
    }

    @Test("forwardAssistant=false면 text event 무시")
    func textSkippedWhenAssistantOff() async throws {
        let bot = MockTelegramBot()
        let bridge = TelegramSessionBridge(client: bot, configuration: makeConfig(forwardAssistant: false))
        await bridge.consume(event: .text("hidden"))
        await bridge.consume(event: .completed(exitCode: 0))
        let log = await bot.sentLog
        #expect(!log.contains { $0.text.contains("hidden") })
    }

    @Test("toolCall은 🔧 prefix + summary로 전송")
    func toolCallEmitsWithPrefix() async {
        let bot = MockTelegramBot()
        let bridge = TelegramSessionBridge(client: bot, configuration: makeConfig())
        await bridge.consume(event: .toolCall(name: "Read", input: "foo.swift"))
        let log = await bot.sentLog
        #expect(log.count == 1)
        #expect(log[0].text == "🔧 Read — foo.swift")
    }

    @Test("forwardToolCalls=false면 toolCall 무시")
    func toolCallSkippedWhenOff() async {
        let bot = MockTelegramBot()
        let bridge = TelegramSessionBridge(client: bot, configuration: makeConfig(forwardToolCalls: false))
        await bridge.consume(event: .toolCall(name: "Read", input: "foo"))
        let log = await bot.sentLog
        #expect(log.isEmpty)
    }

    @Test("notifyTurnStart는 ▶ prefix로 시작 알림")
    func turnStartSendsBanner() async {
        let bot = MockTelegramBot()
        let bridge = TelegramSessionBridge(client: bot, configuration: makeConfig())
        await bridge.notifyTurnStart(userText: "fix the bug")
        let log = await bot.sentLog
        #expect(log.count == 1)
        #expect(log[0].text.hasPrefix("▶ 시작"))
        #expect(log[0].text.contains("test-workspace"))
        #expect(log[0].text.contains("fix the bug"))
    }

    @Test("notifyCancelled는 🛑 메시지 전송")
    func cancelledSendsMessage() async {
        let bot = MockTelegramBot()
        let bridge = TelegramSessionBridge(client: bot, configuration: makeConfig())
        await bridge.notifyCancelled()
        let log = await bot.sentLog
        #expect(log.count == 1)
        #expect(log[0].text.contains("🛑"))
    }

    @Test("completed exit != 0이면 ❌ 실패 메시지")
    func failureExitSendsErrorBanner() async {
        let bot = MockTelegramBot()
        let bridge = TelegramSessionBridge(client: bot, configuration: makeConfig())
        await bridge.notifyTurnStart(userText: "x")
        await bridge.consume(event: .completed(exitCode: 1))
        let log = await bot.sentLog
        #expect(log.contains { $0.text.contains("❌ 실패") })
    }
}
