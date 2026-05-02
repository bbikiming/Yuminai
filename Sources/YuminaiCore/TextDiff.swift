import Foundation

// MARK: - TextDiff (ADR-054)

/// 두 텍스트의 line-level diff 계산.
///
/// **출처/근거**:
/// - Promptfoo "row-per-turn matrix" UI 패턴 (https://www.promptfoo.dev/docs/configuration/guide/)
/// - Myers diff algorithm (단순화된 LCS 변형) — Git/diff utility 기반
///
/// **사용 예** (RehearsalSheet diff view):
/// ```swift
/// let diff = TextDiff.lineDiff(original: task.output, replay: rehearsalRun.resultText)
/// // diff.lines = [DiffLine(kind: .same/.added/.removed, text: "...")]
/// ```
///
/// **알고리즘**: 단순 LCS 기반 line diff. 큰 텍스트는 적절히 truncate (UI에서 lineCap 적용 권장).
public enum TextDiff {
    public struct DiffLine: Sendable, Hashable {
        public enum Kind: Sendable, Hashable {
            case same
            case added       // replay에만 있음
            case removed     // original에만 있음
        }
        public let kind: Kind
        public let text: String
        /// original 텍스트의 line index (있으면).
        public let originalLineNum: Int?
        /// replay 텍스트의 line index (있으면).
        public let replayLineNum: Int?

        public init(kind: Kind, text: String, originalLineNum: Int? = nil, replayLineNum: Int? = nil) {
            self.kind = kind
            self.text = text
            self.originalLineNum = originalLineNum
            self.replayLineNum = replayLineNum
        }
    }

    public struct DiffResult: Sendable, Hashable {
        public let lines: [DiffLine]
        public let addedCount: Int
        public let removedCount: Int
        public let sameCount: Int

        public init(lines: [DiffLine]) {
            self.lines = lines
            self.addedCount = lines.filter { $0.kind == .added }.count
            self.removedCount = lines.filter { $0.kind == .removed }.count
            self.sameCount = lines.filter { $0.kind == .same }.count
        }

        /// 변화량 % (added + removed / max line count)
        public var changeRatio: Double {
            let total = max(1, addedCount + removedCount + sameCount)
            return Double(addedCount + removedCount) / Double(total)
        }

        /// 요약 텍스트 ("+12 -8 / 50 same")
        public func summary() -> String {
            "+\(addedCount) -\(removedCount) / \(sameCount) same (변화 \(String(format: "%.1f", changeRatio * 100))%)"
        }
    }

    /// LCS 기반 line diff. O(n*m) — 작은 텍스트(<10K lines)에 적합.
    /// 큰 텍스트는 caller가 truncate 후 호출 권장.
    public static func lineDiff(original: String, replay: String, maxLines: Int = 1000) -> DiffResult {
        let aLines = Array(original.split(separator: "\n", omittingEmptySubsequences: false).prefix(maxLines)).map(String.init)
        let bLines = Array(replay.split(separator: "\n", omittingEmptySubsequences: false).prefix(maxLines)).map(String.init)

        let n = aLines.count
        let m = bLines.count

        // 빈 case 처리
        if n == 0 && m == 0 { return DiffResult(lines: []) }
        if n == 0 {
            return DiffResult(lines: bLines.enumerated().map { idx, line in
                DiffLine(kind: .added, text: line, originalLineNum: nil, replayLineNum: idx + 1)
            })
        }
        if m == 0 {
            return DiffResult(lines: aLines.enumerated().map { idx, line in
                DiffLine(kind: .removed, text: line, originalLineNum: idx + 1, replayLineNum: nil)
            })
        }

        // LCS 길이 표 — DP
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 1...n {
            for j in 1...m {
                if aLines[i - 1] == bLines[j - 1] {
                    lcs[i][j] = lcs[i - 1][j - 1] + 1
                } else {
                    lcs[i][j] = max(lcs[i - 1][j], lcs[i][j - 1])
                }
            }
        }

        // backtrack
        var result: [DiffLine] = []
        var i = n
        var j = m
        while i > 0 && j > 0 {
            if aLines[i - 1] == bLines[j - 1] {
                result.append(DiffLine(kind: .same, text: aLines[i - 1], originalLineNum: i, replayLineNum: j))
                i -= 1
                j -= 1
            } else if lcs[i - 1][j] >= lcs[i][j - 1] {
                result.append(DiffLine(kind: .removed, text: aLines[i - 1], originalLineNum: i, replayLineNum: nil))
                i -= 1
            } else {
                result.append(DiffLine(kind: .added, text: bLines[j - 1], originalLineNum: nil, replayLineNum: j))
                j -= 1
            }
        }
        while i > 0 {
            result.append(DiffLine(kind: .removed, text: aLines[i - 1], originalLineNum: i, replayLineNum: nil))
            i -= 1
        }
        while j > 0 {
            result.append(DiffLine(kind: .added, text: bLines[j - 1], originalLineNum: nil, replayLineNum: j))
            j -= 1
        }

        return DiffResult(lines: result.reversed())
    }
}
