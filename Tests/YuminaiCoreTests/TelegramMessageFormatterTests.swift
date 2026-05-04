import Foundation
import Testing
@testable import YuminaiCore

/// **ADR-095 Phase 4** — TelegramMessageFormatter 유닛 테스트.
@Suite("TelegramMessageFormatter (ADR-095 Phase 4)")
struct TelegramMessageFormatterTests {

    // MARK: - formatDiff: 짧은 diff (truncate 없음)

    @Test("짧은 diff — truncate 없이 전체 포함")
    func shortDiffNoTruncation() {
        let diff = """
        --- a/Foo.swift
        +++ b/Foo.swift
        @@ -1,3 +1,3 @@
        -var x = 0
        +var x = 42
        """
        let result = TelegramMessageFormatter.formatDiff(
            diff,
            files: 1,
            added: 1,
            removed: 1
        )
        #expect(result.contains("📝 Diff Preview · 1 file, +1/-1"))
        #expect(result.contains("```diff"))
        #expect(result.contains("var x = 42"))
        #expect(result.contains("```"))
        #expect(!result.contains("more lines"))
    }

    @Test("짧은 diff — deepLinkId 없으면 링크 없음")
    func shortDiffNoDeepLink() {
        let result = TelegramMessageFormatter.formatDiff(
            "--- a/Foo.swift\n+++ b/Foo.swift\n+var x = 1",
            files: 1, added: 1, removed: 0,
            deepLinkId: nil
        )
        #expect(!result.contains("yuminai://"))
        #expect(!result.contains("View Full"))
    }

    @Test("짧은 diff — deepLinkId 있으면 링크 포함")
    func shortDiffWithDeepLink() {
        let uuid = UUID(uuidString: "12345678-1234-1234-1234-123456789abc")!
        let result = TelegramMessageFormatter.formatDiff(
            "--- a/Foo.swift\n+++ b/Foo.swift\n+var x = 1",
            files: 1, added: 1, removed: 0,
            deepLinkId: uuid
        )
        #expect(result.contains("yuminai://diff/12345678-1234-1234-1234-123456789abc"))
        #expect(result.contains("View Full in Yuminai"))
    }

    // MARK: - formatDiff: 라인 한도 truncate

    @Test("긴 diff — 라인 한도 초과 시 truncate + indicator")
    func longDiffLineLimit() {
        // 50줄 diff 생성
        let lines = (1...50).map { "+line \($0)" }
        let diff = lines.joined(separator: "\n")
        let result = TelegramMessageFormatter.formatDiff(
            diff,
            files: 2,
            added: 50,
            removed: 0,
            previewLineLimit: 30
        )
        #expect(result.contains("more lines"))
        // 30줄만 포함 — 31번째 라인은 없어야
        #expect(!result.contains("+line 31"))
        #expect(result.contains("+line 30"))
    }

    @Test("긴 diff — 파일 복수형")
    func diffPluralFiles() {
        let result = TelegramMessageFormatter.formatDiff(
            "+x",
            files: 3, added: 5, removed: 2
        )
        #expect(result.contains("3 files"))
        #expect(!result.contains("3 file,"))  // "file," 아닌 "files,"
    }

    @Test("diff 파일 1개 — 단수형")
    func diffSingularFile() {
        let result = TelegramMessageFormatter.formatDiff(
            "+x",
            files: 1, added: 1, removed: 0
        )
        #expect(result.contains("1 file,"))
    }

    // MARK: - formatDiff: 바이트 한도 truncate

    @Test("매우 긴 diff — 바이트 한도 초과 시 truncate")
    func veryLongDiffByteLimit() {
        // 각 줄 50바이트 × 100줄 = 5000바이트 → 2000바이트 한도 초과
        let line = "+" + String(repeating: "a", count: 49)
        let diff = (1...100).map { _ in line }.joined(separator: "\n")
        let result = TelegramMessageFormatter.formatDiff(
            diff,
            files: 1, added: 100, removed: 0,
            maxBytes: 2000
        )
        // 결과가 4000바이트 이하여야
        let byteCount = result.utf8.count
        #expect(byteCount <= 4000)
        #expect(result.contains("more lines"))
    }

    // MARK: - enforceMaxBytes

    @Test("enforceMaxBytes — 한도 미만이면 원본 반환")
    func enforceMaxBytesUnderLimit() {
        let text = "Hello, World!"
        let result = TelegramMessageFormatter.enforceMaxBytes(text, maxBytes: 100)
        #expect(result == text)
    }

    @Test("enforceMaxBytes — 한도 초과 시 truncate + indicator 추가")
    func enforceMaxBytesOverLimit() {
        let text = String(repeating: "a", count: 500)
        let result = TelegramMessageFormatter.enforceMaxBytes(text, maxBytes: 100)
        let byteCount = result.utf8.count
        #expect(byteCount <= 100)
        #expect(result.hasSuffix("... (truncated)"))
    }

    @Test("enforceMaxBytes — 정확히 한도 바이트면 원본 반환")
    func enforceMaxBytesExactLimit() {
        let text = String(repeating: "a", count: 100)
        let result = TelegramMessageFormatter.enforceMaxBytes(text, maxBytes: 100)
        #expect(result == text)
    }

    @Test("enforceMaxBytes — 다국어 UTF-8 경계 보정")
    func enforceMaxBytesMultibyte() {
        // 한글은 UTF-8로 3바이트 — 경계에서 잘리면 안 됨
        let text = String(repeating: "가", count: 50)  // 150바이트
        let result = TelegramMessageFormatter.enforceMaxBytes(text, maxBytes: 100)
        // 결과는 유효한 UTF-8이어야 함
        let data = result.data(using: .utf8)
        #expect(data != nil)
        #expect(result.utf8.count <= 100)
    }

    // MARK: - shouldSendAsDocument

    @Test("shouldSendAsDocument — 5MB 미만이면 false")
    func shouldNotSendAsDocument() {
        #expect(!TelegramMessageFormatter.shouldSendAsDocument(byteCount: 4 * 1024 * 1024))
        #expect(!TelegramMessageFormatter.shouldSendAsDocument(byteCount: 1024))
        #expect(!TelegramMessageFormatter.shouldSendAsDocument(byteCount: 5 * 1024 * 1024 - 1))
    }

    @Test("shouldSendAsDocument — 5MB 이상이면 true")
    func shouldSendAsDocument() {
        #expect(TelegramMessageFormatter.shouldSendAsDocument(byteCount: 5 * 1024 * 1024))
        #expect(TelegramMessageFormatter.shouldSendAsDocument(byteCount: 10 * 1024 * 1024))
    }

    // MARK: - formatLog: 성공/실패 포맷

    @Test("로그 — 성공 포맷 (PASSED badge)")
    func logSuccessFormat() {
        let log = (1...5).map { "line \($0)" }.joined(separator: "\n")
        let result = TelegramMessageFormatter.formatLog(
            log,
            title: "Build · Yuminai",
            elapsed: 134,  // 2m 14s
            success: true
        )
        #expect(result.contains("✅ PASSED"))
        #expect(result.contains("🔨 Build · Yuminai"))
        #expect(result.contains("2m 14s"))
        #expect(result.contains("```"))
    }

    @Test("로그 — 실패 포맷 (FAILED badge)")
    func logFailureFormat() {
        let result = TelegramMessageFormatter.formatLog(
            "error: something failed",
            title: "Test",
            elapsed: 30,
            success: false
        )
        #expect(result.contains("❌ FAILED"))
        #expect(result.contains("30s"))
    }

    @Test("로그 — tailLines 초과 시 앞 라인 생략 + indicator")
    func logTailTruncation() {
        let lines = (1...50).map { "line \($0)" }
        let log = lines.joined(separator: "\n")
        let result = TelegramMessageFormatter.formatLog(
            log,
            title: "Build",
            elapsed: 10,
            success: true,
            tailLines: 20
        )
        // 마지막 20줄만 포함
        #expect(result.contains("line 50"))
        #expect(result.contains("line 31"))
        #expect(!result.contains("line 30\n"))  // 30번째 라인은 없어야
        #expect(result.contains("earlier lines"))
    }

    @Test("로그 — deepLinkId 있으면 로그 링크 포함")
    func logWithDeepLink() {
        let uuid = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        let result = TelegramMessageFormatter.formatLog(
            "ok",
            title: "Build",
            elapsed: 1,
            success: true,
            deepLinkId: uuid
        )
        #expect(result.contains("yuminai://log/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"))
        #expect(result.contains("View Full Log in Yuminai"))
    }

    @Test("로그 — 전체 결과 4000바이트 이하")
    func logTotalBytesLimit() {
        let line = String(repeating: "x", count: 100)
        let log = (1...200).map { _ in line }.joined(separator: "\n")
        let result = TelegramMessageFormatter.formatLog(
            log, title: "Test", elapsed: 60, success: false
        )
        #expect(result.utf8.count <= 4000)
    }
}
