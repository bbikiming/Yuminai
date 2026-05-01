import Foundation
import Testing
import YuminaiCore
@testable import YuminaiClaudeAdapter

/// ADR-031 T3 — Codex JSONL schema에 추가된 안전한 type alias 검증.
@Suite("CodexJSONLParser — schema extras (T3)")
struct CodexSchemaExtraTests {
    @Test("agent_message_chunk → text")
    func agentMessageChunk() async {
        let parser = CodexJSONLParser()
        let chunk = Data(#"{"type":"agent_message_chunk","content":"streamed"}"#.utf8 + [0x0A])
        let events = await parser.feed(chunk)
        #expect(events.count == 1)
        if case .text(let s) = events[0] { #expect(s == "streamed") }
        else { Issue.record("Expected .text") }
    }

    @Test("thinking 이벤트는 무시 (verbose 노이즈 방지)")
    func thinkingIgnored() async {
        let parser = CodexJSONLParser()
        let chunk = Data(#"{"type":"thinking","content":"내부 추론..."}"#.utf8 + [0x0A])
        let events = await parser.feed(chunk)
        #expect(events.isEmpty, "thinking은 emit 안 됨")
    }

    @Test("tool_use_started → toolCall")
    func toolUseStarted() async {
        let parser = CodexJSONLParser()
        let chunk = Data(#"{"type":"tool_use_started","name":"Bash","input":{"cmd":"ls"}}"#.utf8 + [0x0A])
        let events = await parser.feed(chunk)
        #expect(events.count == 1)
        if case .toolCall(let name, _) = events[0] { #expect(name == "Bash") }
    }

    @Test("status=completed도 success로")
    func toolResultCompletedStatus() async {
        let parser = CodexJSONLParser()
        let chunk = Data(#"{"type":"tool_result","output":"done","status":"completed"}"#.utf8 + [0x0A])
        let events = await parser.feed(chunk)
        if case .toolResult(let success, _) = events[0] { #expect(success) }
        else { Issue.record("Expected .toolResult") }
    }

    @Test("usage_update + cached_tokens 키")
    func usageUpdate() async {
        let parser = CodexJSONLParser()
        let chunk = Data(#"{"type":"usage_update","input_tokens":50,"output_tokens":30,"cached_tokens":10}"#.utf8 + [0x0A])
        let events = await parser.feed(chunk)
        if case .usage(let delta) = events[0] {
            #expect(delta.inputTokens == 50)
            #expect(delta.outputTokens == 30)
            #expect(delta.cacheReadTokens == 10)
        } else { Issue.record("Expected .usage") }
    }

    @Test("error 이벤트는 toolResult(success: false)로 forward")
    func errorEventForwarded() async {
        let parser = CodexJSONLParser()
        let chunk = Data(#"{"type":"error","message":"무언가 잘못됨"}"#.utf8 + [0x0A])
        let events = await parser.feed(chunk)
        #expect(events.count == 1)
        if case .toolResult(let success, let output) = events[0] {
            #expect(success == false)
            #expect(output.contains("무언가 잘못됨"))
        } else { Issue.record("Expected .toolResult(false)") }
    }

    @Test("session_initialized는 무시 (id만 추출)")
    func sessionInitializedIgnored() async {
        let parser = CodexJSONLParser()
        let chunk = Data(#"{"type":"session_initialized","session_id":"abc"}"#.utf8 + [0x0A])
        let events = await parser.feed(chunk)
        #expect(events.isEmpty)
        let id = await parser.extractedSessionId
        #expect(id == "abc")
    }
}
