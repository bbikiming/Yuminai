import Foundation
import Testing
import YuminaiCore
@testable import YuminaiClaudeAdapter

@Suite("CodexJSONLParser")
struct CodexJSONLParserTests {
    @Test("agent_message 텍스트는 .text 이벤트로 변환")
    func agentMessageBecomesText() async {
        let parser = CodexJSONLParser()
        let chunk = Data(#"{"type":"agent_message","content":"hello world"}"# .utf8 + [0x0A])
        let events = await parser.feed(chunk)
        #expect(events.count == 1)
        if case .text(let s) = events[0] { #expect(s == "hello world") }
        else { Issue.record("Expected .text") }
    }

    @Test("tool_call은 .toolCall(name:input:)로 변환")
    func toolCallBecomesToolCall() async {
        let parser = CodexJSONLParser()
        let chunk = Data(#"{"type":"tool_call","name":"Read","arguments":{"path":"foo"}}"# .utf8 + [0x0A])
        let events = await parser.feed(chunk)
        #expect(events.count == 1)
        if case .toolCall(let name, let input) = events[0] {
            #expect(name == "Read")
            #expect(input.contains("foo"))
        } else {
            Issue.record("Expected .toolCall")
        }
    }

    @Test("tool_result은 success/output 추출")
    func toolResultExtraction() async {
        let parser = CodexJSONLParser()
        let chunk = Data(#"{"type":"tool_result","output":"done","is_error":false}"# .utf8 + [0x0A])
        let events = await parser.feed(chunk)
        #expect(events.count == 1)
        if case .toolResult(let success, let output) = events[0] {
            #expect(success == true)
            #expect(output == "done")
        } else {
            Issue.record("Expected .toolResult")
        }
    }

    @Test("session_id가 있으면 extractedSessionId에 저장")
    func extractsSessionId() async {
        let parser = CodexJSONLParser()
        let chunk = Data(#"{"type":"session_started","session_id":"abc-123"}"# .utf8 + [0x0A])
        _ = await parser.feed(chunk)
        let id = await parser.extractedSessionId
        #expect(id == "abc-123")
    }

    @Test("usage 이벤트는 .usage(UsageDelta) 변환 — 토큰/비용 추출")
    func usageExtraction() async {
        let parser = CodexJSONLParser()
        let chunk = Data(#"{"type":"usage","input_tokens":120,"output_tokens":80,"cost_usd":0.01}"# .utf8 + [0x0A])
        let events = await parser.feed(chunk)
        #expect(events.count == 1)
        if case .usage(let delta) = events[0] {
            #expect(delta.inputTokens == 120)
            #expect(delta.outputTokens == 80)
            #expect(delta.costUSD == 0.01)
        } else {
            Issue.record("Expected .usage")
        }
    }

    @Test("non-JSON 라인은 raw text로 forward (디버깅 가능)")
    func nonJSONFallsBackToText() async {
        let parser = CodexJSONLParser()
        let chunk = Data("not json content\n".utf8)
        let events = await parser.feed(chunk)
        #expect(events.count == 1)
        if case .text(let s) = events[0] { #expect(s == "not json content") }
        else { Issue.record("Expected .text") }
    }

    @Test("알 수 없는 type은 [codex <type>] prefix로 forward")
    func unknownTypeForwarded() async {
        let parser = CodexJSONLParser()
        let chunk = Data(#"{"type":"future_event","payload":"x"}"# .utf8 + [0x0A])
        let events = await parser.feed(chunk)
        #expect(events.count == 1)
        if case .text(let s) = events[0] {
            #expect(s.hasPrefix("[codex future_event]"))
        } else {
            Issue.record("Expected .text fallback")
        }
    }

    @Test("partial chunk는 newline 도착 시까지 buffer")
    func partialChunkBuffers() async {
        let parser = CodexJSONLParser()
        let part1 = Data(#"{"type":"agent_message","cont"#.utf8)
        let part2 = Data(#"ent":"continued"}"#.utf8 + [0x0A])
        let r1 = await parser.feed(part1)
        #expect(r1.isEmpty)
        let r2 = await parser.feed(part2)
        #expect(r2.count == 1)
        if case .text(let s) = r2[0] { #expect(s == "continued") }
    }
}
