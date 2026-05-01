import Foundation

/// `@<agent>` mention parsing (ADR-031, T2 — 인터-에이전트 메시지).
///
/// **참조** (ADR-027 evidence): MetaGPT 메시지 환경 + AutoGen GroupChat speaker selection.
///
/// 지원 syntax:
/// - `@claude <prompt>` — 첫 Claude pane으로 dispatch
/// - `@codex <prompt>` — 첫 Codex pane으로 dispatch
/// - `@<custom-name> <prompt>` — 부분 매칭으로 displayName이 일치하는 pane
/// - `@me <prompt>` — 현재 active pane (no-op, 일반 메시지와 동일)
///
/// mention은 메시지 시작 부분에만 인식 (중간/끝의 `@xxx`는 일반 텍스트).
public struct MentionParser: Sendable {
    public struct Mention: Sendable, Equatable {
        public let target: String        // 사용자가 입력한 raw target ("@codex", "@claude")
        public let body: String          // mention 제거 후 prompt 본문
        public let originalText: String  // 원본 (디버깅 + 라우팅 실패 시 fallback)

        public init(target: String, body: String, originalText: String) {
            self.target = target
            self.body = body
            self.originalText = originalText
        }
    }

    public init() {}

    /// 메시지에서 leading mention 추출. mention이 없으면 nil.
    public func parse(_ text: String) -> Mention? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("@") else { return nil }

        // 첫 단어 추출 — `@<word>` (공백 또는 줄바꿈까지)
        let scanRange = trimmed.startIndex..<trimmed.endIndex
        let separators: CharacterSet = .whitespacesAndNewlines
        guard let firstSepIdx = trimmed.unicodeScalars.firstIndex(where: { separators.contains($0) })
        else {
            // mention만 있고 body 없음 — invalid
            return nil
        }
        let mentionEnd = String.Index(firstSepIdx, within: trimmed) ?? trimmed.endIndex
        let target = String(trimmed[scanRange.lowerBound..<mentionEnd])
        guard target.count > 1 else { return nil }  // `@` 한 글자만은 무시

        let bodyStart = trimmed.index(after: mentionEnd)
        guard bodyStart < trimmed.endIndex else { return nil }
        let body = String(trimmed[bodyStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }

        return Mention(target: target, body: body, originalText: text)
    }

    /// 자연어 안의 `@<agent>` mention 추출 (ADR-034 A2).
    /// leading parse가 nil일 때 fallback으로 사용.
    /// 첫 번째 발견된 `@<word>`만 — body는 전체 원문 (mention 위치 보존).
    /// 예: "이거 @codex 검토해줘" → target=@codex, body=원문 그대로
    public func parseInline(_ text: String) -> Mention? {
        let scalars = Array(text)
        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            // `@` 발견 — 이전 char가 공백/시작이면 mention 후보
            if c == "@" {
                let prev = i > 0 ? scalars[i - 1] : " "
                if prev.isWhitespace || prev.isNewline || i == 0 {
                    // word 추출
                    var j = i + 1
                    while j < scalars.count {
                        let ch = scalars[j]
                        if ch.isWhitespace || ch.isNewline || ch == "," || ch == "." || ch == "!" || ch == "?" {
                            break
                        }
                        j += 1
                    }
                    let target = String(scalars[i..<j])
                    if target.count > 1 {
                        return Mention(target: target, body: text, originalText: text)
                    }
                }
            }
            i += 1
        }
        return nil
    }

    /// leading + inline 조합 — leading 우선, 없으면 inline.
    public func parseAny(_ text: String) -> Mention? {
        if let leading = parse(text) { return leading }
        return parseInline(text)
    }

    /// mention의 target에서 `@` 제거하고 normalize (lowercase).
    public static func normalizedTarget(_ target: String) -> String {
        var t = target
        if t.hasPrefix("@") { t.removeFirst() }
        return t.lowercased()
    }
}
