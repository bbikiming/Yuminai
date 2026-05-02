import Foundation
import Testing
@testable import YuminaiCore

@Suite("UsageForecaster (ADR-064 Phase 5)")
struct UsageForecasterTests {
    @Test("ewmaSeries: 빈 배열 → 빈 배열")
    func emptySeries() {
        #expect(UsageForecaster.ewmaSeries([]).isEmpty)
    }

    @Test("ewmaSeries: 첫 값은 그대로")
    func firstValuePreserved() {
        let result = UsageForecaster.ewmaSeries([10.0, 20.0, 30.0])
        #expect(result[0] == 10.0)
    }

    @Test("ewmaSeries: alpha=0.3 정확 계산")
    func ewmaCalc() {
        // S_1 = 10
        // S_2 = 0.3 * 20 + 0.7 * 10 = 13.0
        // S_3 = 0.3 * 30 + 0.7 * 13 = 18.1
        let result = UsageForecaster.ewmaSeries([10.0, 20.0, 30.0], alpha: 0.3)
        #expect(abs(result[0] - 10.0) < 0.001)
        #expect(abs(result[1] - 13.0) < 0.001)
        #expect(abs(result[2] - 18.1) < 0.001)
    }

    @Test("forecastNext: minSamples 미만 → nil")
    func forecastMinSamples() {
        #expect(UsageForecaster.forecastNext([1.0, 2.0]) == nil)  // 2 < 3
    }

    @Test("forecastNext: minSamples 이상 → 마지막 EWMA")
    func forecastBasic() {
        let next = UsageForecaster.forecastNext([10.0, 20.0, 30.0])
        #expect(next != nil)
    }

    @Test("forecastFuture: N개 반환")
    func forecastN() {
        let future = UsageForecaster.forecastFuture([10.0, 20.0, 30.0], steps: 5)
        #expect(future.count == 5)
    }

    @Test("trend: 상승 데이터 → up")
    func trendUp() {
        let trend = UsageForecaster.trend([1.0, 2.0, 3.0, 4.0, 5.0])
        #expect(trend == .up)
    }

    @Test("trend: 하락 데이터 → down")
    func trendDown() {
        let trend = UsageForecaster.trend([10.0, 8.0, 6.0, 4.0, 2.0])
        #expect(trend == .down)
    }

    @Test("trend: flat 데이터")
    func trendFlat() {
        let trend = UsageForecaster.trend([10.0, 10.0, 10.0, 10.0, 10.0])
        #expect(trend == .flat)
    }

    @Test("Trend.icon 정확")
    func trendIcons() {
        #expect(UsageForecaster.Trend.up.icon == "arrow.up.right")
        #expect(UsageForecaster.Trend.down.icon == "arrow.down.right")
        #expect(UsageForecaster.Trend.flat.icon == "arrow.right")
    }

    // MARK: - ADR-065 Phase 1: Holt-Winters

    @Test("Holt-Winters: 충분치 않은 데이터 → nil")
    func hwInsufficient() {
        // seasonLength=24, 2*24=48개 미만
        let result = UsageForecaster.holtWintersForecast([1.0, 2.0, 3.0], seasonLength: 24)
        #expect(result == nil)
    }

    @Test("Holt-Winters: seasonal 패턴 forecast")
    func hwSeasonal() {
        // sine wave 시뮬레이션 (24-period)
        var values: [Double] = []
        for i in 0..<48 {
            values.append(10 + 5 * sin(Double(i) * .pi / 12))
        }
        let result = UsageForecaster.holtWintersForecast(values, seasonLength: 24, steps: 5)
        #expect(result != nil)
        #expect(result?.count == 5)
    }

    // MARK: - ADR-065 Phase 3: Anomaly detection

    @Test("Anomaly: 정상 분포는 anomaly 없음")
    func anomalyNormal() {
        let values = [1.0, 1.1, 0.9, 1.0, 1.05, 0.95, 1.0]
        let anomalies = UsageForecaster.detectAnomalies(values)
        #expect(anomalies.isEmpty)
    }

    @Test("Anomaly: spike 감지 (high)")
    func anomalySpike() {
        let values = [1.0, 1.0, 1.0, 1.0, 1.0, 100.0, 1.0, 1.0, 1.0]
        let anomalies = UsageForecaster.detectAnomalies(values)
        #expect(!anomalies.isEmpty)
        #expect(anomalies.first?.direction == .high)
        #expect(anomalies.first?.value == 100.0)
    }

    @Test("Anomaly: 데이터 부족 (< 3) → 빈 배열")
    func anomalyTooSmall() {
        let anomalies = UsageForecaster.detectAnomalies([1.0, 100.0])
        #expect(anomalies.isEmpty)
    }

    @Test("Anomaly: stddev 0이면 빈 배열")
    func anomalyConstant() {
        let anomalies = UsageForecaster.detectAnomalies([5.0, 5.0, 5.0, 5.0])
        #expect(anomalies.isEmpty)
    }
}

@Suite("CSVExporter Markdown export (ADR-065 Phase 4)")
struct MarkdownExportTests {
    @Test("formatMarkdown: 기본 table")
    func basicTable() {
        let md = CSVExporter.formatMarkdown(
            headers: ["A", "B"],
            rows: [["1", "2"], ["3", "4"]]
        )
        #expect(md.contains("| A | B |"))
        #expect(md.contains("| --- | --- |"))
        #expect(md.contains("| 1 | 2 |"))
    }

    @Test("formatMarkdown: pipe escape")
    func pipeEscape() {
        let md = CSVExporter.formatMarkdown(
            headers: ["text"],
            rows: [["a|b"]]
        )
        #expect(md.contains("a\\|b"))
    }

    @Test("formatMarkdown: newline → <br>")
    func newlineEscape() {
        let md = CSVExporter.formatMarkdown(
            headers: ["text"],
            rows: [["line1\nline2"]]
        )
        #expect(md.contains("line1<br>line2"))
    }

    @Test("exportTelegramUsageReportMarkdown: section 구조")
    func reportStructure() {
        let snap = TelegramUsageStore.Snapshot(
            chatStats: [:],
            commandStats: [:],
            hourlyBuckets: []
        )
        let md = CSVExporter.exportTelegramUsageReportMarkdown(snapshot: snap)
        #expect(md.contains("# Yuminai Telegram Usage Report"))
        #expect(md.contains("## Summary"))
        #expect(md.contains("## Chat Stats"))
        #expect(md.contains("## Command Stats"))
    }
}

@Suite("Holt-Winters multiplicative + CI (ADR-066 Phase 3 + 5)")
struct HWMultiCITests {
    @Test("multiplicative HW: 양수 데이터")
    func multPositive() {
        var values: [Double] = []
        for i in 0..<48 {
            values.append(10 + 5 * sin(Double(i) * .pi / 12) + 5)  // 양수 보장
        }
        let result = UsageForecaster.holtWintersForecast(values, seasonLength: 24, steps: 3, model: .multiplicative)
        #expect(result != nil)
        #expect(result?.count == 3)
    }

    @Test("multiplicative HW: 0 포함 → additive fallback")
    func multZeroFallback() {
        var values = Array(repeating: 1.0, count: 48)
        values[10] = 0  // 0 포함
        let result = UsageForecaster.holtWintersForecast(values, seasonLength: 24, model: .multiplicative)
        #expect(result != nil)  // additive fallback
    }

    @Test("forecastWithCI: minSamples 미만 nil")
    func ciMinSamples() {
        let ci = UsageForecaster.forecastWithCI([1.0])
        #expect(ci == nil)
    }

    @Test("forecastWithCI: 잔차 stddev 기반 CI")
    func ciCalc() {
        let ci = UsageForecaster.forecastWithCI([10.0, 12.0, 14.0, 11.0, 13.0])
        #expect(ci != nil)
        #expect(ci!.upperBound > ci!.forecast)
        #expect(ci!.lowerBound <= ci!.forecast)
        #expect(ci!.stddev > 0)
    }

    @Test("forecastWithCI: lowerBound는 0 이상 clamp")
    func ciLowerBoundClamped() {
        let ci = UsageForecaster.forecastWithCI([0.001, 0.002, 0.001, 0.003])
        #expect(ci != nil)
        #expect(ci!.lowerBound >= 0)
    }
}

@Suite("SVGExporter (ADR-066 Phase 4)")
struct SVGExporterTests {
    @Test("lineChart: 빈 데이터 → empty hint")
    func emptyChart() {
        let svg = SVGExporter.lineChart(values: [], title: "test")
        #expect(svg.contains("no data"))
        #expect(svg.contains("<svg"))
        #expect(svg.contains("</svg>"))
    }

    @Test("lineChart: 정상 데이터")
    func normalLine() {
        let svg = SVGExporter.lineChart(values: [1.0, 2.0, 3.0, 4.0, 5.0], title: "Trend")
        #expect(svg.contains("Trend"))
        #expect(svg.contains("<path"))
        #expect(svg.contains("<circle"))  // points
    }

    @Test("barChart: labels + values 매칭")
    func barChart() {
        let svg = SVGExporter.barChart(
            labels: ["A", "B", "C"],
            values: [10, 20, 30],
            title: "Bars"
        )
        #expect(svg.contains("<rect"))
        #expect(svg.contains(">A<"))
        #expect(svg.contains(">B<"))
    }

    @Test("escape: XML special chars")
    func xmlEscape() {
        let svg = SVGExporter.lineChart(values: [1.0], title: "<a&b>")
        #expect(svg.contains("&lt;a&amp;b&gt;"))
    }
}

@Suite("TelegramUsageStore chat-specific buckets (ADR-066 Phase 1)")
struct ChatSpecificBucketsTests {
    private func makeStore() -> TelegramUsageStore {
        let suite = "yuminai-tg-chat-bucket-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return TelegramUsageStore(defaults: defaults)
    }

    @Test("chat별 turn count 분리")
    func chatTurnSeparation() async {
        let store = makeStore()
        await store.recordTurnStart(chatId: 100)
        await store.recordTurnStart(chatId: 200)
        let buckets100 = await store.hourlyBuckets(forChatId: 100)
        let buckets200 = await store.hourlyBuckets(forChatId: 200)
        #expect(buckets100.count == 1)
        #expect(buckets100[0].turnCount == 1)
        #expect(buckets200[0].turnCount == 1)
    }

    @Test("chat별 cost 분리")
    func chatCostSeparation() async {
        let store = makeStore()
        await store.recordTurnComplete(chatId: 1, costUSD: 0.10, inputTokens: 100, outputTokens: 50)
        await store.recordTurnComplete(chatId: 2, costUSD: 0.05, inputTokens: 50, outputTokens: 25)
        let b1 = await store.hourlyBuckets(forChatId: 1)
        let b2 = await store.hourlyBuckets(forChatId: 2)
        #expect(abs(b1[0].costUSD - 0.10) < 0.0001)
        #expect(abs(b2[0].costUSD - 0.05) < 0.0001)
    }
}

@Suite("CSVExporter streaming write (ADR-064 Phase 3)")
struct CSVStreamingTests {
    @Test("streaming write: 100 rows")
    func streamingBasic() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: url) }

        try CSVExporter.streamingWrite(
            to: url,
            headers: ["id", "value"],
            rowCount: 100,
            rowProvider: { idx in [String(idx), "v\(idx)"] }
        )

        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.split(separator: "\n")
        #expect(lines.count == 101)  // header + 100 rows
        #expect(lines[0] == "id,value")
        #expect(lines[1] == "0,v0")
        #expect(lines[100] == "99,v99")
    }

    @Test("streaming write: 0 rows (header only)")
    func streamingZeroRows() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: url) }

        try CSVExporter.streamingWrite(
            to: url,
            headers: ["a"],
            rowCount: 0,
            rowProvider: { _ in [] }
        )

        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content == "a\n")
    }

    @Test("streaming write: large rows (10K)")
    func streamingLarge() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: url) }

        try CSVExporter.streamingWrite(
            to: url,
            headers: ["id"],
            rowCount: 10_000,
            rowProvider: { idx in [String(idx)] }
        )

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = attrs[.size] as? Int ?? 0
        #expect(size > 0)
    }

    @Test("streaming write: row의 escape 적용")
    func streamingEscape() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: url) }

        try CSVExporter.streamingWrite(
            to: url,
            headers: ["text"],
            rowCount: 1,
            rowProvider: { _ in ["hello, world"] }
        )

        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("\"hello, world\""))
    }
}
