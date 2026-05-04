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

@Suite("TelegramSessionBridge — artifact wire-up (ADR-098 P1-1)")
struct BridgeArtifactWireUpTests {
    @Test("notifyDiffArtifact — store에 저장하고 deep link 포함 메시지 발송")
    func diffArtifactStoresAndSendsDeepLink() async {
        let bot = MockTelegramBot()
        let store = TelegramArtifactStore()
        let bridge = TelegramSessionBridge(client: bot, configuration: makeConfig())
        await bridge.setArtifactStore(store)

        let id = await bridge.notifyDiffArtifact(
            diff: "diff --git a/A.swift b/A.swift\n+added",
            files: 1,
            added: 1,
            removed: 0,
            workspace: "ws-1"
        )

        // store에 저장됨
        guard let id else {
            Issue.record("Expected non-nil UUID")
            return
        }
        let fetched = await store.fetch(id)
        #expect(fetched != nil)
        if case .diff(_, let files, let added, let removed, let ws) = fetched {
            #expect(files == 1)
            #expect(added == 1)
            #expect(removed == 0)
            #expect(ws == "ws-1")
        } else {
            Issue.record("Expected .diff artifact")
        }

        // 메시지 본문에 deep link UUID + yuminai://diff/ 포함
        let log = await bot.sentLog
        #expect(!log.isEmpty)
        let text = log.last?.text ?? ""
        #expect(text.contains("📝 Diff Preview"))
        #expect(text.contains("yuminai://diff/\(id.uuidString.lowercased())"))
    }

    @Test("notifyDiffArtifact — store 미주입이면 nil 반환 + 메시지 미발송")
    func diffArtifactNoStoreReturnsNil() async {
        let bot = MockTelegramBot()
        let bridge = TelegramSessionBridge(client: bot, configuration: makeConfig())

        let id = await bridge.notifyDiffArtifact(
            diff: "diff --git a/x b/x\n+x",
            files: 1,
            added: 1,
            removed: 0,
            workspace: nil
        )

        #expect(id == nil)
        let log = await bot.sentLog
        #expect(log.isEmpty)
    }

    @Test("notifyLogArtifact — store에 저장하고 deep link 포함 메시지 발송")
    func logArtifactStoresAndSendsDeepLink() async {
        let bot = MockTelegramBot()
        let store = TelegramArtifactStore()
        let bridge = TelegramSessionBridge(client: bot, configuration: makeConfig())
        await bridge.setArtifactStore(store)

        let id = await bridge.notifyLogArtifact(
            log: "Build complete!\nAll tests passed.",
            title: "swift test",
            elapsed: 4.2,
            success: true
        )

        guard let id else {
            Issue.record("Expected non-nil UUID")
            return
        }
        let fetched = await store.fetch(id)
        #expect(fetched != nil)
        if case .log(_, let title, let elapsed, let success) = fetched {
            #expect(title == "swift test")
            #expect(elapsed == 4.2)
            #expect(success == true)
        } else {
            Issue.record("Expected .log artifact")
        }

        let log = await bot.sentLog
        #expect(!log.isEmpty)
        let text = log.last?.text ?? ""
        #expect(text.contains("✅ PASSED"))
        #expect(text.contains("yuminai://log/\(id.uuidString.lowercased())"))
    }

    @Test("notifyLogArtifact — store 미주입이면 nil 반환 + 메시지 미발송")
    func logArtifactNoStoreReturnsNil() async {
        let bot = MockTelegramBot()
        let bridge = TelegramSessionBridge(client: bot, configuration: makeConfig())

        let id = await bridge.notifyLogArtifact(
            log: "doesnt matter",
            title: "noop",
            elapsed: 0.1,
            success: false
        )

        #expect(id == nil)
        let log = await bot.sentLog
        #expect(log.isEmpty)
    }

    @Test("artifact 발송은 requestChatId가 설정되면 그쪽으로 보낸다")
    func artifactRespectsRequestChatId() async {
        let bot = MockTelegramBot()
        let store = TelegramArtifactStore()
        let bridge = TelegramSessionBridge(client: bot, configuration: makeConfig())
        await bridge.setArtifactStore(store)
        await bridge.setRequestChatId(7777)

        _ = await bridge.notifyLogArtifact(
            log: "x",
            title: "t",
            elapsed: 0,
            success: true
        )

        let log = await bot.sentLog
        #expect(!log.isEmpty)
        // 모든 발송이 requestChatId로 갔는지 확인
        for entry in log {
            #expect(entry.chatId == 7777)
        }
    }

    @Test("artifact 발송 후 streaming session이 reset된다")
    func artifactResetsStreamingSession() async {
        let bot = MockTelegramBot()
        let store = TelegramArtifactStore()
        let bridge = TelegramSessionBridge(client: bot, configuration: makeConfig())
        await bridge.setArtifactStore(store)

        // 먼저 streaming으로 텍스트를 보내 streaming session을 활성화한다.
        await bridge.consume(event: .text("hello stream"))
        await bridge.consume(event: .completed(exitCode: 0))

        let beforeCount = await bot.sentLog.count
        #expect(beforeCount > 0)

        // diff artifact 발송
        _ = await bridge.notifyDiffArtifact(
            diff: "diff --git a/x b/x\n+y",
            files: 1,
            added: 1,
            removed: 0,
            workspace: nil
        )

        // 후속 text는 새 메시지로 시작 (edit이 아니라).
        await bridge.consume(event: .text("after artifact"))
        await bridge.consume(event: .completed(exitCode: 0))

        let afterTexts = await bot.sentLog.map(\.text)
        #expect(afterTexts.contains("after artifact"))
    }
}
