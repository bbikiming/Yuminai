import Foundation
import Testing
@testable import YuminaiCore

@Suite("CSVExporter (ADR-063 Phase 4)")
struct CSVExporterTests {
    @Test("escape: 일반 text는 그대로")
    func escapePlain() {
        #expect(CSVExporter.escape("hello") == "hello")
    }

    @Test("escape: comma 포함 → quote")
    func escapeComma() {
        #expect(CSVExporter.escape("hello, world") == "\"hello, world\"")
    }

    @Test("escape: quote 포함 → escape + quote")
    func escapeQuote() {
        #expect(CSVExporter.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
    }

    @Test("escape: newline 포함 → quote")
    func escapeNewline() {
        let result = CSVExporter.escape("line1\nline2")
        #expect(result.hasPrefix("\""))
        #expect(result.hasSuffix("\""))
    }

    @Test("format: header + rows")
    func formatBasic() {
        let csv = CSVExporter.format(
            headers: ["a", "b"],
            rows: [["1", "2"], ["3", "4"]]
        )
        #expect(csv == "a,b\n1,2\n3,4\n")
    }

    @Test("exportChatStats CSV 헤더 정확")
    func chatStatsHeader() {
        var stats = ChatUsageStats(chatId: 100)
        stats.turnCount = 5
        let csv = CSVExporter.exportChatStats([stats])
        #expect(csv.hasPrefix("chat_id,turn_count,total_cost_usd,input_tokens,output_tokens,last_used_at\n"))
        #expect(csv.contains("100,5"))
    }

    @Test("exportCommandStats: 빈도 순 정렬")
    func commandStatsSorted() {
        let stats = ["/a": 1, "/b": 5, "/c": 3]
        let csv = CSVExporter.exportCommandStats(stats)
        let lines = csv.split(separator: "\n")
        #expect(lines.count == 4)  // header + 3
        #expect(lines[1].hasPrefix("/b,5"))  // 가장 많은 것 먼저
    }

    @Test("exportHourlyBuckets: timestamp 순서")
    func hourlyBucketsTimestamp() {
        var b1 = HourlyUsageBucket(timestamp: Date(timeIntervalSince1970: 1000))
        b1.turnCount = 1
        var b2 = HourlyUsageBucket(timestamp: Date(timeIntervalSince1970: 2000))
        b2.turnCount = 2
        let csv = CSVExporter.exportHourlyBuckets([b2, b1])  // 역순 입력
        let lines = csv.split(separator: "\n")
        #expect(lines.count == 3)
        // 정렬되어 b1이 먼저
        #expect(lines[1].contains(",1,"))
        #expect(lines[2].contains(",2,"))
    }
}

@Suite("TelegramUsageStore daily aggregation (ADR-063 Phase 2)")
struct DailyAggregationTests {
    private func makeStore() -> TelegramUsageStore {
        let suite = "yuminai-tg-daily-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return TelegramUsageStore(defaults: defaults)
    }

    @Test("dailyAggregation: hourly buckets를 같은 날짜로 병합")
    func dailyAggregation() async {
        let store = makeStore()
        await store.recordTurnStart(chatId: 1)
        await store.recordTurnComplete(chatId: 1, costUSD: 0.01, inputTokens: 100, outputTokens: 50)
        let daily = await store.dailyAggregation()
        #expect(daily.count == 1)
        #expect(daily[0].turnCount == 1)
        #expect(abs(daily[0].costUSD - 0.01) < 0.0001)
    }

    @Test("dailyAggregation: 빈 hourly → 빈 daily")
    func emptyAggregation() async {
        let store = makeStore()
        let daily = await store.dailyAggregation()
        #expect(daily.isEmpty)
    }
}

@Suite("ChatUsageStats workspace usage (ADR-063 Phase 5)")
struct ChatWorkspaceUsageTests {
    private func makeStore() -> TelegramUsageStore {
        let suite = "yuminai-tg-ws-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return TelegramUsageStore(defaults: defaults)
    }

    @Test("workspaceUsageCounts 누적")
    func workspaceUsageAccumulate() async {
        let store = makeStore()
        let ws1 = UUID()
        let ws2 = UUID()
        await store.recordTurnStart(chatId: 100, workspaceId: ws1)
        await store.recordTurnStart(chatId: 100, workspaceId: ws1)
        await store.recordTurnStart(chatId: 100, workspaceId: ws2)
        let snap = await store.snapshot()
        let stats = snap.chatStats["100"]
        #expect(stats?.workspaceUsageCounts[ws1.uuidString] == 2)
        #expect(stats?.workspaceUsageCounts[ws2.uuidString] == 1)
    }

    @Test("workspaceId nil이면 누적 X")
    func nilWorkspaceIgnored() async {
        let store = makeStore()
        await store.recordTurnStart(chatId: 100, workspaceId: nil)
        let snap = await store.snapshot()
        let stats = snap.chatStats["100"]
        #expect(stats?.workspaceUsageCounts.isEmpty == true)
    }
}
