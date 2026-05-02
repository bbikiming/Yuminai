import Foundation
import Testing
@testable import YuminaiCore

@Suite("TextDiff (ADR-054)")
struct TextDiffTests {
    @Test("identical text → all same lines, 0 added/removed")
    func identicalText() {
        let result = TextDiff.lineDiff(original: "a\nb\nc", replay: "a\nb\nc")
        #expect(result.addedCount == 0)
        #expect(result.removedCount == 0)
        #expect(result.sameCount == 3)
        #expect(result.changeRatio == 0.0)
    }

    @Test("empty original → all added")
    func emptyOriginal() {
        let result = TextDiff.lineDiff(original: "", replay: "x\ny")
        // 빈 string은 split하면 [""] 1개 line으로 — caller가 알고 있어야 함
        #expect(result.addedCount >= 1)
    }

    @Test("empty replay → all removed")
    func emptyReplay() {
        let result = TextDiff.lineDiff(original: "x\ny", replay: "")
        #expect(result.removedCount >= 1)
    }

    @Test("addition at end")
    func additionAtEnd() {
        let result = TextDiff.lineDiff(original: "a\nb", replay: "a\nb\nc")
        #expect(result.addedCount == 1)
        #expect(result.removedCount == 0)
        let added = result.lines.first { $0.kind == .added }
        #expect(added?.text == "c")
    }

    @Test("removal at end")
    func removalAtEnd() {
        let result = TextDiff.lineDiff(original: "a\nb\nc", replay: "a\nb")
        #expect(result.removedCount == 1)
        let removed = result.lines.first { $0.kind == .removed }
        #expect(removed?.text == "c")
    }

    @Test("replacement (line different)")
    func replacement() {
        let result = TextDiff.lineDiff(original: "a\nold\nc", replay: "a\nnew\nc")
        #expect(result.addedCount == 1)
        #expect(result.removedCount == 1)
        #expect(result.sameCount == 2)
    }

    @Test("changeRatio reasonable")
    func changeRatio() {
        let result = TextDiff.lineDiff(original: "a\nb\nc\nd", replay: "a\nb\nc\nx")
        // 3 same + 1 added + 1 removed = 5 total, change = 2/5 = 0.4
        #expect(result.changeRatio == 0.4)
    }

    @Test("summary string format")
    func summary() {
        let result = TextDiff.lineDiff(original: "a", replay: "b")
        let s = result.summary()
        #expect(s.contains("+"))
        #expect(s.contains("-"))
        #expect(s.contains("변화"))
    }

    @Test("line numbers are populated for same lines")
    func lineNumbersForSame() {
        let result = TextDiff.lineDiff(original: "a\nb", replay: "a\nb")
        for line in result.lines where line.kind == .same {
            #expect(line.originalLineNum != nil)
            #expect(line.replayLineNum != nil)
        }
    }

    @Test("maxLines truncates large input")
    func maxLinesTruncation() {
        let large = (0..<2000).map { "line\($0)" }.joined(separator: "\n")
        let result = TextDiff.lineDiff(original: large, replay: large, maxLines: 100)
        #expect(result.sameCount <= 100)
    }
}

@Suite("ChildProcessProgress (ADR-054)")
struct ChildProcessProgressTests {
    @Test("elapsedSeconds returns >= 0")
    func elapsedNonNegative() {
        let progress = ChildProcessProgress(
            purpose: .decomposition,
            agentRaw: "claude",
            startedAt: Date().addingTimeInterval(-5),
            purposeContext: "test"
        )
        #expect(progress.elapsedSeconds() >= 5)
    }

    @Test("status transitions")
    func statusTransitions() {
        var progress = ChildProcessProgress(
            purpose: .rehearsal,
            agentRaw: "codex",
            purposeContext: "test"
        )
        #expect(progress.status == .starting)
        progress.status = .running
        #expect(progress.status == .running)
        progress.status = .completed
        #expect(progress.status == .completed)
    }

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let cleanDate = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let original = ChildProcessProgress(
            id: UUID(),
            purpose: .parallel,
            agentRaw: "claude",
            startedAt: cleanDate,
            purposeContext: "Pane 2 task",
            status: .running
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ChildProcessProgress.self, from: data)
        #expect(decoded == original)
    }
}
