import Foundation
import Testing
import YuminaiCore
@testable import YuminaiClaudeAdapter

@Suite("JSONStreamParser")
struct JSONStreamParserTests {
    @Test("assistant text 메시지 한 줄을 .text 이벤트로 변환한다")
    func parsesAssistantText() async {
        let parser = JSONStreamParser()
        let line = """
        {"type":"assistant","message":{"content":[{"type":"text","text":"Hello"}]}}
        """ + "\n"
        let events = await parser.feed(Data(line.utf8))
        #expect(events == [.text("Hello")])
    }

    @Test("assistant tool_use 메시지를 .toolCall로 변환한다")
    func parsesToolCall() async {
        let parser = JSONStreamParser()
        let line = """
        {"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"path":"/tmp/x"}}]}}
        """ + "\n"
        let events = await parser.feed(Data(line.utf8))
        guard case let .toolCall(name, input) = events.first else {
            Issue.record("expected .toolCall, got \(events)")
            return
        }
        #expect(name == "Read")
        #expect(input.contains("/tmp/x"))
    }

    @Test("user tool_result(success)를 .toolResult(success: true)로 변환")
    func parsesToolResultSuccess() async {
        let parser = JSONStreamParser()
        let line = """
        {"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"ok","is_error":false}]}}
        """ + "\n"
        let events = await parser.feed(Data(line.utf8))
        #expect(events == [.toolResult(success: true, output: "ok")])
    }

    @Test("user tool_result(is_error=true)를 .toolResult(success: false)로 변환")
    func parsesToolResultError() async {
        let parser = JSONStreamParser()
        let line = """
        {"type":"user","message":{"content":[{"type":"tool_result","content":"fail","is_error":true}]}}
        """ + "\n"
        let events = await parser.feed(Data(line.utf8))
        #expect(events == [.toolResult(success: false, output: "fail")])
    }

    @Test("result 메시지를 .completed로 변환한다")
    func parsesResult() async {
        let parser = JSONStreamParser()
        let line = """
        {"type":"result","is_error":false,"subtype":"success"}
        """ + "\n"
        let events = await parser.feed(Data(line.utf8))
        #expect(events == [.completed(exitCode: 0)])
    }

    @Test("청크가 줄 중간에 끊겨도 다음 feed에서 합쳐 처리한다")
    func handlesPartialChunks() async {
        let parser = JSONStreamParser()
        let full = """
        {"type":"assistant","message":{"content":[{"type":"text","text":"hi"}]}}
        """ + "\n"
        let mid = full.index(full.startIndex, offsetBy: 30)
        let part1 = String(full[full.startIndex..<mid])
        let part2 = String(full[mid..<full.endIndex])

        let firstEvents = await parser.feed(Data(part1.utf8))
        #expect(firstEvents.isEmpty)

        let secondEvents = await parser.feed(Data(part2.utf8))
        #expect(secondEvents == [.text("hi")])
    }

    @Test("여러 줄이 하나의 청크에 와도 모두 파싱한다")
    func parsesMultipleLinesInOneChunk() async {
        let parser = JSONStreamParser()
        let payload = """
        {"type":"assistant","message":{"content":[{"type":"text","text":"a"}]}}
        {"type":"assistant","message":{"content":[{"type":"text","text":"b"}]}}
        {"type":"result","is_error":false}
        """ + "\n"
        let events = await parser.feed(Data(payload.utf8))
        #expect(events == [.text("a"), .text("b"), .completed(exitCode: 0)])
    }

    @Test("불완전한 JSON은 silent하게 무시된다")
    func ignoresMalformedJSON() async {
        let parser = JSONStreamParser()
        let line = "not json at all\n"
        let events = await parser.feed(Data(line.utf8))
        #expect(events.isEmpty)
    }
}
