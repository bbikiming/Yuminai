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
        let event = parseLine(buffer)
        buffer.removeAll()
        return event.map { [$0] } ?? []
    }

    private func drainCompleteLines() -> [ClaudeEvent] {
        var events: [ClaudeEvent] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            // newline까지 포함해서 제거
            buffer.removeSubrange(buffer.startIndex...newline)
            if line.isEmpty { continue }
            if let event = parseLine(Data(line)) {
                events.append(event)
            }
        }
        return events
    }

    private func parseLine(_ data: Data) -> ClaudeEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let type = object["type"] as? String ?? ""

        switch type {
        case "assistant":
            return parseAssistant(object)
        case "user":
            return parseUserToolResult(object)
        case "result":
            let isError = object["is_error"] as? Bool ?? false
            return .completed(exitCode: isError ? 1 : 0)
        case "system":
            // session_id init 등 — 현재는 status idle로 매핑
            return .statusChange(.idle)
        default:
            return nil
        }
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
