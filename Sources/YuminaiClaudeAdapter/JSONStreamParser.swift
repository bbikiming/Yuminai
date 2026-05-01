import Foundation
import YuminaiCore

/// `claude -p --output-format stream-json --input-format stream-json` 출력의 NDJSON 파서.
///
/// stdout 청크가 도착하는 대로 `feed(_:)`에 넣고, 완성된 JSON 라인이 있으면
/// `ClaudeEvent` 배열로 반환한다.
///
/// - Note: 정확한 메시지 schema는 W2 단계에서 실제 출력 분석 후 정밀화. 현재 파서는
///   합리적 가정 기반으로 알려진 type만 처리하고 나머지는 silently 무시한다.
public actor JSONStreamParser {
    private var buffer = Data()

    public init() {}

    /// 새 청크를 누적하고 완성된 JSON 라인들을 이벤트로 변환.
    public func feed(_ chunk: Data) -> [ClaudeEvent] {
        buffer.append(chunk)
        return drainCompleteLines()
    }

    /// 스트림 종료 시 남은 buffer를 한 번 더 시도.
    public func flush() -> [ClaudeEvent] {
        guard !buffer.isEmpty else { return [] }
        let events = parseLineToEvents(buffer)
        buffer.removeAll()
        return events
    }

    private func drainCompleteLines() -> [ClaudeEvent] {
        var events: [ClaudeEvent] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if line.isEmpty { continue }
            events.append(contentsOf: parseLineToEvents(Data(line)))
        }
        return events
    }

    private func parseLineToEvents(_ data: Data) -> [ClaudeEvent] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        let type = object["type"] as? String ?? ""
        var events: [ClaudeEvent] = []

        switch type {
        case "assistant":
            if let event = parseAssistant(object) {
                events.append(event)
            }
            if let delta = extractUsage(from: object["message"] as? [String: Any]) {
                events.append(.usage(delta))
            }
        case "user":
            if let event = parseUserToolResult(object) {
                events.append(event)
            }
        case "result":
            let cost = object["total_cost_usd"] as? Double
            if let delta = extractUsage(from: object) {
                events.append(.usage(delta.merging(cost: cost)))
            } else if let cost {
                events.append(.usage(ClaudeEvent.UsageDelta(costUSD: cost)))
            }
            let isError = object["is_error"] as? Bool ?? false
            events.append(.completed(exitCode: isError ? 1 : 0))
        case "system":
            events.append(.statusChange(.idle))
        default:
            break
        }
        return events
    }

    /// `usage` 객체(여러 메시지 타입에 들어있음)에서 token 정보 추출.
    private func extractUsage(from container: [String: Any]?) -> ClaudeEvent.UsageDelta? {
        guard let container, let usage = container["usage"] as? [String: Any] else { return nil }

        let input = (usage["input_tokens"] as? Int) ?? 0
        let output = (usage["output_tokens"] as? Int) ?? 0
        let cacheCreation = (usage["cache_creation_input_tokens"] as? Int) ?? 0
        let cacheRead = (usage["cache_read_input_tokens"] as? Int) ?? 0

        if input == 0, output == 0, cacheCreation == 0, cacheRead == 0 {
            return nil
        }
        return ClaudeEvent.UsageDelta(
            inputTokens: input,
            outputTokens: output,
            cacheCreationTokens: cacheCreation,
            cacheReadTokens: cacheRead,
            costUSD: nil
        )
    }

    private func parseAssistant(_ object: [String: Any]) -> ClaudeEvent? {
        guard let message = object["message"] as? [String: Any] else { return nil }

        if let plain = message["content"] as? String {
            return .text(plain)
        }

        // 배열은 element-wise cast — `as? [[String: Any]]`는 NSArray 브리징에서 실패할 수 있음
        guard let raw = message["content"] as? [Any] else { return nil }
        let blocks = raw.compactMap { $0 as? [String: Any] }

        let texts = blocks.compactMap { block -> String? in
            guard block["type"] as? String == "text" else { return nil }
            return block["text"] as? String
        }
        if !texts.isEmpty {
            return .text(texts.joined())
        }

        if let toolUse = blocks.first(where: { ($0["type"] as? String) == "tool_use" }),
           let name = toolUse["name"] as? String {
            let inputJSON = serializeJSON(toolUse["input"] ?? [String: Any]())
            return .toolCall(name: name, input: inputJSON)
        }
        return nil
    }

    private func parseUserToolResult(_ object: [String: Any]) -> ClaudeEvent? {
        guard let message = object["message"] as? [String: Any],
              let raw = message["content"] as? [Any]
        else { return nil }

        let blocks = raw.compactMap { $0 as? [String: Any] }
        guard let toolResult = blocks.first(where: { ($0["type"] as? String) == "tool_result" })
        else { return nil }

        let isError = toolResult["is_error"] as? Bool ?? false
        let output: String
        if let str = toolResult["content"] as? String {
            output = str
        } else if let inner = toolResult["content"] as? [Any] {
            let innerBlocks = inner.compactMap { $0 as? [String: Any] }
            output = innerBlocks.compactMap { $0["text"] as? String }.joined()
        } else {
            output = ""
        }
        return .toolResult(success: !isError, output: output)
    }

    private func serializeJSON(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let str = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        // JSONSerialization은 슬래시를 `\/`로 escape — 가독성 위해 복원
        return str.replacingOccurrences(of: "\\/", with: "/")
    }
}
