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
