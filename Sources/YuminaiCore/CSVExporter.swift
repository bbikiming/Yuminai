import Foundation

// MARK: - CSVExporter (ADR-063 Phase 4)

/// **ADR-063 Phase 4** — Telegram usage / Routing log / cache trend을 CSV로 export.
///
/// 모든 export는 단순 텍스트 (RFC 4180): comma-separated, "..." quote escape.
public enum CSVExporter {
    /// CSV 한 row를 "..." quote + escape 처리.
    public static func escape(_ field: String) -> String {
        let needsQuote = field.contains(",") || field.contains("\"") || field.contains("\n")
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return needsQuote ? "\"\(escaped)\"" : escaped
    }

    /// rows 배열을 CSV string으로.
    public static func format(headers: [String], rows: [[String]]) -> String {
        var output = headers.map(escape).joined(separator: ",") + "\n"
        for row in rows {
            output += row.map(escape).joined(separator: ",") + "\n"
        }
        return output
    }

    // MARK: - ADR-065 Phase 4 — Markdown table export

    /// **ADR-065 Phase 4** — Markdown table 형식 export.
    /// GitHub-flavored Markdown table (header + separator + rows).
    /// pipe (|)는 자동 escape (`\|`).
    public static func formatMarkdown(headers: [String], rows: [[String]]) -> String {
        // 헤더 line
        var output = "| " + headers.map(escapeMarkdownCell).joined(separator: " | ") + " |\n"
        // separator (---)
        output += "|" + String(repeating: " --- |", count: headers.count) + "\n"
        // rows
        for row in rows {
            output += "| " + row.map(escapeMarkdownCell).joined(separator: " | ") + " |\n"
        }
        return output
    }

    /// Markdown cell escape (pipe + newline).
    public static func escapeMarkdownCell(_ field: String) -> String {
        field
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    /// **ADR-065 Phase 4** — chat stats markdown table.
    public static func exportChatStatsMarkdown(_ stats: [ChatUsageStats]) -> String {
        let headers = ["Chat ID", "Turns", "Cost (USD)", "Input Tokens", "Output Tokens", "Last Used"]
        let formatter = ISO8601DateFormatter()
        let rows = stats.sorted { $0.turnCount > $1.turnCount }.map { s in
            [
                String(s.chatId),
                String(s.turnCount),
                String(format: "$%.6f", s.totalCostUSD),
                String(s.totalInputTokens),
                String(s.totalOutputTokens),
                formatter.string(from: s.lastUsedAt)
            ]
        }
        return formatMarkdown(headers: headers, rows: rows)
    }

    public static func exportCommandStatsMarkdown(_ stats: [String: Int]) -> String {
        let headers = ["Command", "Count"]
        let rows = stats.sorted { $0.value > $1.value }.map { [$0.key, String($0.value)] }
        return formatMarkdown(headers: headers, rows: rows)
    }

    /// **ADR-065 Phase 4** — comprehensive Telegram usage report (multi-section).
    /// Summary + chat stats + command stats를 한 markdown document로.
    public static func exportTelegramUsageReportMarkdown(
        snapshot: TelegramUsageStore.Snapshot,
        generatedAt: Date = Date()
    ) -> String {
        let formatter = ISO8601DateFormatter()
        var output = "# Yuminai Telegram Usage Report\n\n"
        output += "**Generated**: \(formatter.string(from: generatedAt))\n\n"
        output += "## Summary\n\n"
        output += "- **Total Turns**: \(snapshot.totalTurns)\n"
        output += "- **Total Cost**: $\(String(format: "%.6f", snapshot.totalCostUSD))\n"
        output += "- **Total Commands**: \(snapshot.totalCommands)\n"
        output += "- **Active Chats**: \(snapshot.chatStats.count)\n\n"
        output += "## Chat Stats\n\n"
        if snapshot.chatStats.isEmpty {
            output += "_(no chat data)_\n\n"
        } else {
            output += exportChatStatsMarkdown(Array(snapshot.chatStats.values))
            output += "\n"
        }
        output += "## Command Stats\n\n"
        if snapshot.commandStats.isEmpty {
            output += "_(no command data)_\n\n"
        } else {
            output += exportCommandStatsMarkdown(snapshot.commandStats)
        }
        return output
    }

    // MARK: - ADR-064 Phase 3 — Streaming write (대용량 안전)

    /// **ADR-064 Phase 3** — streaming write: 메모리에 전체 string 만들지 않고 row 단위로 disk write.
    /// 대용량 (수십만 rows) 데이터 export 시 메모리 폭발 방지.
    ///
    /// **사용 예**:
    /// ```swift
    /// try CSVExporter.streamingWrite(
    ///     to: url,
    ///     headers: ["id", "value"],
    ///     rowCount: 100_000,
    ///     rowProvider: { idx in [String(idx), "value\(idx)"] }
    /// )
    /// ```
    public static func streamingWrite(
        to url: URL,
        headers: [String],
        rowCount: Int,
        rowProvider: (Int) -> [String]
    ) throws {
        // create empty file
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        // header line
        let headerLine = headers.map(escape).joined(separator: ",") + "\n"
        if let data = headerLine.data(using: .utf8) {
            try handle.write(contentsOf: data)
        }

        // rows (한 row씩 write — 메모리 cap)
        for i in 0..<rowCount {
            let row = rowProvider(i)
            let line = row.map(escape).joined(separator: ",") + "\n"
            if let data = line.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
        }
    }

    // MARK: - Telegram Usage exports

    public static func exportChatStats(_ stats: [ChatUsageStats]) -> String {
        let headers = ["chat_id", "turn_count", "total_cost_usd", "input_tokens", "output_tokens", "last_used_at"]
        let formatter = ISO8601DateFormatter()
        let rows = stats.sorted { $0.turnCount > $1.turnCount }.map { s in
            [
                String(s.chatId),
                String(s.turnCount),
                String(format: "%.6f", s.totalCostUSD),
                String(s.totalInputTokens),
                String(s.totalOutputTokens),
                formatter.string(from: s.lastUsedAt)
            ]
        }
        return format(headers: headers, rows: rows)
    }

    public static func exportCommandStats(_ stats: [String: Int]) -> String {
        let headers = ["command", "count"]
        let rows = stats.sorted { $0.value > $1.value }.map { [$0.key, String($0.value)] }
        return format(headers: headers, rows: rows)
    }

    public static func exportHourlyBuckets(_ buckets: [HourlyUsageBucket]) -> String {
        let headers = ["timestamp", "turn_count", "cost_usd", "input_tokens", "output_tokens"]
        let formatter = ISO8601DateFormatter()
        let rows = buckets.sorted { $0.timestamp < $1.timestamp }.map { b in
            [
                formatter.string(from: b.timestamp),
                String(b.turnCount),
                String(format: "%.6f", b.costUSD),
                String(b.inputTokens),
                String(b.outputTokens)
            ]
        }
        return format(headers: headers, rows: rows)
    }

    public static func exportDailyBuckets(_ buckets: [DailyUsageBucket]) -> String {
        let headers = ["date", "turn_count", "cost_usd", "input_tokens", "output_tokens"]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let rows = buckets.sorted { $0.date < $1.date }.map { b in
            [
                formatter.string(from: b.date),
                String(b.turnCount),
                String(format: "%.6f", b.costUSD),
                String(b.inputTokens),
                String(b.outputTokens)
            ]
        }
        return format(headers: headers, rows: rows)
    }

    // MARK: - Routing log export

    public static func exportRoutingDecisions(_ decisions: [RoutingDecisionRecord]) -> String {
        let headers = [
            "timestamp", "workspace_name", "task_kind", "matched_keyword",
            "task_fingerprint", "selected_agent", "previous_agent",
            "outcome", "estimated_handoff_tokens", "redacted_prompt"
        ]
        let formatter = ISO8601DateFormatter()
        let rows = decisions.map { r in
            [
                formatter.string(from: r.timestamp),
                r.workspaceName ?? "",
                r.taskKindRaw,
                r.matchedKeyword ?? "",
                r.taskFingerprint,
                r.selectedAgentRaw,
                r.previousAgentRaw,
                r.outcome.rawValue,
                String(r.estimatedHandoffTokens),
                r.redactedPrompt
            ]
        }
        return format(headers: headers, rows: rows)
    }

    // MARK: - Cache trend export

    public static func exportCacheTrend(_ samples: [CacheHitSample]) -> String {
        let headers = ["timestamp", "workspace_id", "read_tokens", "uncached_input_tokens", "hit_ratio"]
        let formatter = ISO8601DateFormatter()
        let rows = samples.sorted { $0.timestamp < $1.timestamp }.map { s in
            [
                formatter.string(from: s.timestamp),
                s.workspaceId?.uuidString ?? "",
                String(s.readTokens),
                String(s.uncachedInputTokens),
                String(format: "%.4f", s.hitRatio)
            ]
        }
        return format(headers: headers, rows: rows)
    }
}
