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
