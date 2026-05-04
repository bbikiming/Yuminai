import Foundation

/// **ADR-095 Phase 4** — Telegram 메시지 포맷터.
///
/// Diff/Log를 텔레그램 4096자 제한 안에서 "preview + deep-link" 형식으로 포맷한다.
/// 규칙 (ADR-092 §4.7):
/// - 첫 N줄 OR M바이트 중 작은 쪽
/// - ` ```diff ` fenced code block으로 감싸기
/// - "... (N more lines)" indicator
/// - "View Full in Yuminai" deep link (yuminai://diff/{uuid})
/// - maxBytes 초과 시 추가 truncate + 명시적 표시
/// - safety margin: 4096 → 4000으로 보수적
public enum TelegramMessageFormatter {

    // MARK: - Diff Formatting

    /// Diff를 텔레그램용 메시지로 포맷 — preview + jump link.
    ///
    /// - Parameters:
    ///   - diff: raw diff 문자열
    ///   - files: 변경된 파일 수
    ///   - added: 추가된 라인 수
    ///   - removed: 삭제된 라인 수
    ///   - deepLinkId: `yuminai://diff/{uuid}` 링크용 UUID (nil이면 링크 생략)
    ///   - previewLineLimit: 미리보기 최대 라인 수 (기본 30)
    ///   - maxBytes: 코드 블록 내 최대 바이트 수 (기본 2000)
    /// - Returns: 포맷된 텔레그램 메시지 문자열
    public static func formatDiff(
        _ diff: String,
        files: Int,
        added: Int,
        removed: Int,
        deepLinkId: UUID? = nil,
        previewLineLimit: Int = 30,
        maxBytes: Int = 2000
    ) -> String {
        let header = "📝 Diff Preview · \(files) file\(files == 1 ? "" : "s"), +\(added)/-\(removed)"

        let (preview, truncatedLines) = truncate(
            text: diff,
            lineLimit: previewLineLimit,
            byteLimit: maxBytes
        )

        var codeBlock = "```diff\n\(preview)"
        if truncatedLines > 0 {
            codeBlock += "\n... (\(truncatedLines) more lines)"
        }
        codeBlock += "\n```"

        var parts: [String] = [header, "", codeBlock]

        if let uuid = deepLinkId {
            let link = "yuminai://diff/\(uuid.uuidString.lowercased())"
            parts.append("")
            parts.append("[📂 View Full in Yuminai](\(link))")
        }

        let result = parts.joined(separator: "\n")
        return enforceMaxBytes(result, maxBytes: 4000)
    }

    // MARK: - Log Formatting

    /// Build/test log — last N lines + status badge.
    ///
    /// - Parameters:
    ///   - log: 전체 로그 문자열
    ///   - title: 로그 제목 (예: "Build · Yuminai")
    ///   - elapsed: 소요 시간 (초)
    ///   - success: 성공 여부
    ///   - deepLinkId: `yuminai://log/{uuid}` 링크용 UUID (nil이면 링크 생략)
    ///   - tailLines: 마지막 N줄 (기본 20)
    ///   - maxBytes: 코드 블록 내 최대 바이트 수 (기본 2000)
    /// - Returns: 포맷된 텔레그램 메시지 문자열
    public static func formatLog(
        _ log: String,
        title: String,
        elapsed: TimeInterval,
        success: Bool,
        deepLinkId: UUID? = nil,
        tailLines: Int = 20,
        maxBytes: Int = 2000
    ) -> String {
        let badge = success ? "✅ PASSED" : "❌ FAILED"
        let elapsedStr = formatElapsed(elapsed)
        let header = "🔨 \(title) · \(elapsedStr) · \(badge)"

        let allLines = log.components(separatedBy: "\n")
        let tail: [String]
        let skippedLines: Int
        if allLines.count > tailLines {
            tail = Array(allLines.suffix(tailLines))
            skippedLines = allLines.count - tailLines
        } else {
            tail = allLines
            skippedLines = 0
        }

        let tailText = tail.joined(separator: "\n")
        let (preview, truncatedBytes) = truncateByBytes(text: tailText, byteLimit: maxBytes)

        var codeBlock: String
        if skippedLines > 0 {
            codeBlock = "```\n... (\(skippedLines) earlier lines)\n\(preview)"
        } else {
            codeBlock = "```\n\(preview)"
        }
        if truncatedBytes {
            codeBlock += "\n... (truncated)"
        }
        codeBlock += "\n```"

        var parts: [String] = [header, "", "Last \(min(tailLines, allLines.count)) lines:", codeBlock]

        if let uuid = deepLinkId {
            let link = "yuminai://log/\(uuid.uuidString.lowercased())"
            parts.append("")
            parts.append("[📜 View Full Log in Yuminai](\(link))")
        }

        let result = parts.joined(separator: "\n")
        return enforceMaxBytes(result, maxBytes: 4000)
    }

    // MARK: - Utility

    /// 메시지 텍스트가 maxBytes 초과 시 truncate + indicator.
    ///
    /// Telegram 4096자 제한의 보수적 마진으로 4000자 기본값 사용.
    public static func enforceMaxBytes(_ text: String, maxBytes: Int = 4000) -> String {
        guard let data = text.data(using: .utf8), data.count > maxBytes else {
            return text
        }
        let indicator = "\n... (truncated)"
        let indicatorBytes = indicator.utf8.count
        let targetBytes = maxBytes - indicatorBytes
        guard targetBytes > 0 else { return indicator }

        // UTF-8 경계를 지키면서 truncate
        var truncated = Data(data.prefix(targetBytes))
        // UTF-8 멀티바이트 경계 보정 — 잘린 바이트가 유효한 UTF-8을 구성할 때까지 뒤에서 제거
        while !truncated.isEmpty {
            if let str = String(data: truncated, encoding: .utf8) {
                return str + indicator
            }
            truncated = truncated.dropLast()
        }
        return indicator
    }

    /// 5MB 이상이면 sendDocument 권장 (caller가 결정).
    public static func shouldSendAsDocument(byteCount: Int) -> Bool {
        byteCount >= 5 * 1024 * 1024
    }

    // MARK: - Private Helpers

    /// 라인 수 + 바이트 수 제한을 동시에 적용한 truncation.
    /// Returns: (미리보기 텍스트, 잘린 라인 수)
    private static func truncate(
        text: String,
        lineLimit: Int,
        byteLimit: Int
    ) -> (preview: String, truncatedLines: Int) {
        let allLines = text.components(separatedBy: "\n")
        let lineSlice = Array(allLines.prefix(lineLimit))
        let remainingLines = max(0, allLines.count - lineLimit)

        // 바이트 제한 적용
        let joined = lineSlice.joined(separator: "\n")
        let (bytePreview, wasBytesTruncated) = truncateByBytes(text: joined, byteLimit: byteLimit)

        if wasBytesTruncated {
            // 바이트로 잘렸을 때 남은 라인 수는 계산 어려움 — 보수적으로 "more" 표시
            let usedLines = bytePreview.components(separatedBy: "\n").count
            let truncated = allLines.count - usedLines
            return (bytePreview, max(truncated, 1))
        }

        return (joined, remainingLines)
    }

    /// 바이트 한도만 적용한 truncation.
    /// Returns: (결과 텍스트, 잘렸는지 여부)
    private static func truncateByBytes(text: String, byteLimit: Int) -> (String, Bool) {
        guard let data = text.data(using: .utf8), data.count > byteLimit else {
            return (text, false)
        }
        var truncated = Data(data.prefix(byteLimit))
        while !truncated.isEmpty {
            if let str = String(data: truncated, encoding: .utf8) {
                return (str, true)
            }
            truncated = truncated.dropLast()
        }
        return ("", true)
    }

    /// TimeInterval을 "Xm Ys" 형식으로 포맷.
    private static func formatElapsed(_ elapsed: TimeInterval) -> String {
        let totalSeconds = Int(elapsed.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}
