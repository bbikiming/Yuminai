import SwiftUI
import Charts
import YuminaiCore

/// **ADR-065 Phase 5** — chat 상세 통계 sheet.
///
/// activity gauge에서 chat 클릭 시 표시. 해당 chat의:
/// - 누적 stats (turn / cost / tokens / 마지막 활동)
/// - workspace 사용 분포 (donut)
/// - **ADR-065 Phase 2** — chat별 individual EWMA forecast (있으면)
public struct ChatDetailSheet: View {
    public let chatStats: ChatUsageStats
    public let workspaceIdToName: [String: String]
    public let workspaceLabel: String?  // 현재 binding된 workspace 이름
    /// **ADR-065 Phase 2** — 이 chat의 시간별 cost trend (전체 hourly buckets에서 추출)
    public let chatHourlyBuckets: [HourlyUsageBucket]
    public let onClose: () -> Void

    public init(
        chatStats: ChatUsageStats,
        workspaceIdToName: [String: String],
        workspaceLabel: String? = nil,
        chatHourlyBuckets: [HourlyUsageBucket] = [],
        onClose: @escaping () -> Void
    ) {
        self.chatStats = chatStats
        self.workspaceIdToName = workspaceIdToName
        self.workspaceLabel = workspaceLabel
        self.chatHourlyBuckets = chatHourlyBuckets
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    summaryCard
                    workspaceUsageSection
                    forecastSection  // ADR-065 Phase 2
                    anomaliesSection // ADR-065 Phase 3
                }
                .padding(Theme.Spacing.lg)
            }
            Divider()
            footer
        }
        .frame(width: 680, height: 600)
        .background(Theme.Color.bg)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.2.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Chat \(chatStats.chatId)")
                    .font(Theme.Typography.title)
                if let label = workspaceLabel {
                    Text("→ \(label)")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
            Spacer()
        }
        .padding(Theme.Spacing.lg)
    }

    private var footer: some View {
        HStack {
            Spacer()
            FlatButton("닫기", variant: .primary) { onClose() }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(Theme.Spacing.md)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("누적 사용량")
                .font(Theme.Typography.body.weight(.semibold))
            HStack(spacing: 16) {
                statBlock("Turns", "\(chatStats.turnCount)", color: .blue)
                statBlock("Cost", "$\(String(format: "%.4f", chatStats.totalCostUSD))", color: .green)
                statBlock("Input Tokens", chatStats.totalInputTokens.formattedShort, color: .indigo)
                statBlock("Output Tokens", chatStats.totalOutputTokens.formattedShort, color: .purple)
            }
            Text("마지막 활동: \(formatDate(chatStats.lastUsedAt))")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textTertiary)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    @ViewBuilder
    private var workspaceUsageSection: some View {
        let counts = chatStats.workspaceUsageCounts
        VStack(alignment: .leading, spacing: 6) {
            Text("Workspace 사용 분포")
                .font(Theme.Typography.body.weight(.semibold))
            if counts.isEmpty {
                Text("workspace 데이터 없음")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
            } else {
                Chart {
                    ForEach(counts.sorted(by: { $0.value > $1.value }), id: \.key) { (wsKey, count) in
                        let name = workspaceIdToName[wsKey] ?? String(wsKey.prefix(8)) + "…"
                        SectorMark(
                            angle: .value("Count", count),
                            innerRadius: .ratio(0.55),
                            angularInset: 1.5
                        )
                        .foregroundStyle(by: .value("Workspace", name))
                        .annotation(position: .overlay) {
                            Text("\(count)")
                                .font(.caption)
                                .foregroundStyle(.white)
                        }
                    }
                }
                .chartLegend(position: .trailing, alignment: .center)
                .frame(height: 200)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    /// **ADR-065 Phase 2** — chat별 individual EWMA forecast.
    @ViewBuilder
    private var forecastSection: some View {
        let costs = chatHourlyBuckets.map(\.costUSD)
        VStack(alignment: .leading, spacing: 6) {
            Text("Cost Forecast (EWMA + Holt-Winters)")
                .font(Theme.Typography.body.weight(.semibold))
            if costs.count < UsageForecaster.minSamples {
                Text("forecast: \(UsageForecaster.minSamples)개 이상 sample 필요 (현재 \(costs.count))")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
            } else {
                let next = UsageForecaster.forecastNext(costs) ?? 0
                let trend = UsageForecaster.trend(costs)
                let hwForecasts = UsageForecaster.holtWintersForecast(costs, seasonLength: min(24, costs.count / 2), steps: 5)
                HStack {
                    Image(systemName: trend.icon)
                        .foregroundStyle(trend == .up ? .red : (trend == .down ? .green : .gray))
                    Text("EWMA next: $\(String(format: "%.4f", next))")
                        .font(Theme.Typography.small.weight(.medium))
                    if let hw = hwForecasts?.first {
                        Text("· HW (seasonal): $\(String(format: "%.4f", hw))")
                            .font(Theme.Typography.small)
                            .foregroundStyle(.purple)
                    }
                    Spacer()
                }
                Chart {
                    ForEach(Array(costs.enumerated()), id: \.offset) { idx, value in
                        LineMark(
                            x: .value("Sample", idx),
                            y: .value("Cost", value)
                        )
                        .foregroundStyle(Color.blue)
                    }
                    PointMark(
                        x: .value("Sample", costs.count),
                        y: .value("Forecast", next)
                    )
                    .foregroundStyle(Color.red)
                    .symbolSize(80)
                }
                .frame(height: 140)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    /// **ADR-065 Phase 3** — anomaly detection.
    @ViewBuilder
    private var anomaliesSection: some View {
        let costs = chatHourlyBuckets.map(\.costUSD)
        let anomalies = UsageForecaster.detectAnomalies(costs, threshold: 2.0)
        VStack(alignment: .leading, spacing: 6) {
            Text("Anomaly Detection (z-score > 2.0)")
                .font(Theme.Typography.body.weight(.semibold))
            if anomalies.isEmpty {
                Text("✓ 정상 패턴 — 이상치 없음")
                    .font(Theme.Typography.small)
                    .foregroundStyle(.green)
            } else {
                ForEach(anomalies) { a in
                    HStack {
                        Image(systemName: a.direction == .high ? "exclamationmark.triangle.fill" : "arrow.down.circle.fill")
                            .foregroundStyle(a.direction == .high ? .red : .orange)
                        Text("Sample #\(a.index + 1): $\(String(format: "%.4f", a.value)) (z=\(String(format: "%.2f", a.zScore)))")
                            .font(Theme.Typography.small)
                        Text(a.direction == .high ? "비정상 spike" : "비정상 drop")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textTertiary)
                        Spacer()
                    }
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private func statBlock(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
                .textCase(.uppercase)
            Text(value)
                .font(Theme.Typography.title.weight(.semibold))
                .foregroundStyle(color)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: date)
    }
}
