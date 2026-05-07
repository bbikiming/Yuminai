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

    /// **ADR-066 Phase 2** — anomaly threshold (Settings preference에서)
    public let anomalyThreshold: Double

    public init(
        chatStats: ChatUsageStats,
        workspaceIdToName: [String: String],
        workspaceLabel: String? = nil,
        chatHourlyBuckets: [HourlyUsageBucket] = [],
        anomalyThreshold: Double = 2.0,
        onClose: @escaping () -> Void
    ) {
        self.chatStats = chatStats
        self.workspaceIdToName = workspaceIdToName
        self.workspaceLabel = workspaceLabel
        self.chatHourlyBuckets = chatHourlyBuckets
        self.anomalyThreshold = anomalyThreshold
        self.onClose = onClose
    }

    public var body: some View {
        // ADR-074 — YuminaiSheet: header/footer 외 컨텐츠만 스크롤. 큰 화면에선 스크롤 없음.
        YuminaiSheet(width: 680, height: 600) {
            VStack(spacing: 0) {
                header
                Divider()
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    summaryCard
                    workspaceUsageSection
                    forecastSection  // ADR-065 Phase 2
                    anomaliesSection // ADR-065 Phase 3
                }
                .padding(Theme.Spacing.lg)
            }
        } footer: {
            footer
        }
        .overlay(alignment: .topTrailing) {
            SheetCloseButton(action: onClose)
        }
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
        // ADR-071 Phase 3 — VoiceOver
        .accessibilityElement(children: .contain)
        .accessibilityLabel("워크스페이스 사용 분포 차트")
        .accessibilityValue(counts.isEmpty ? "데이터 없음" : "\(counts.count)개 워크스페이스, 총 \(counts.values.reduce(0, +))회 사용")
    }

    /// **ADR-065 Phase 2 + ADR-066 Phase 3 + 5** — chat별 forecast + multiplicative + CI.
    @ViewBuilder
    private var forecastSection: some View {
        let costs = chatHourlyBuckets.map(\.costUSD)
        VStack(alignment: .leading, spacing: 6) {
            Text("Cost Forecast (EWMA + Holt-Winters + 95% CI)")
                .font(Theme.Typography.body.weight(.semibold))
            if costs.count < UsageForecaster.minSamples {
                Text("forecast: \(UsageForecaster.minSamples)개 이상 sample 필요 (현재 \(costs.count))")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
            } else {
                let trend = UsageForecaster.trend(costs)
                // ADR-066 Phase 5 — confidence interval
                let ci = UsageForecaster.forecastWithCI(costs)
                // ADR-066 Phase 3 — multiplicative HW (data 충분 시)
                let hwAdditive = UsageForecaster.holtWintersForecast(costs, seasonLength: min(24, costs.count / 2), steps: 1, model: .additive)
                let hwMult = UsageForecaster.holtWintersForecast(costs, seasonLength: min(24, costs.count / 2), steps: 1, model: .multiplicative)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: trend.icon)
                            .foregroundStyle(trend == .up ? .red : (trend == .down ? .green : .gray))
                        if let ci {
                            Text("EWMA: $\(String(format: "%.4f", ci.forecast))")
                                .font(Theme.Typography.small.weight(.medium))
                            Text("[$\(String(format: "%.4f", ci.lowerBound))~$\(String(format: "%.4f", ci.upperBound))]")
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Color.textTertiary)
                        }
                        Spacer()
                    }
                    if let add = hwAdditive?.first {
                        Text("HW additive: $\(String(format: "%.4f", add))")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(.purple)
                    }
                    if let mult = hwMult?.first {
                        Text("HW multiplicative: $\(String(format: "%.4f", mult))")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(.indigo)
                    }
                }
                Chart {
                    ForEach(Array(costs.enumerated()), id: \.offset) { idx, value in
                        LineMark(
                            x: .value("Sample", idx),
                            y: .value("Cost", value)
                        )
                        .foregroundStyle(Color.blue)
                    }
                    if let ci {
                        // ADR-066 Phase 5 — confidence interval as RuleMark
                        PointMark(
                            x: .value("Sample", costs.count),
                            y: .value("Forecast", ci.forecast)
                        )
                        .foregroundStyle(Color.red)
                        .symbolSize(80)
                        RuleMark(
                            x: .value("Sample", costs.count),
                            yStart: .value("Lower", ci.lowerBound),
                            yEnd: .value("Upper", ci.upperBound)
                        )
                        .foregroundStyle(Color.red.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 8))
                    }
                }
                .frame(height: 140)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        // ADR-071 Phase 3 — VoiceOver
        .accessibilityElement(children: .contain)
        .accessibilityLabel("비용 예측 차트, EWMA 및 Holt-Winters 모델, 95% 신뢰구간 포함")
        .accessibilityValue(costs.count < UsageForecaster.minSamples
                            ? "샘플 부족, \(costs.count)개"
                            : "샘플 \(costs.count)개")
    }

    /// **ADR-065 Phase 3 + ADR-066 Phase 2** — anomaly detection (threshold from preferences).
    @ViewBuilder
    private var anomaliesSection: some View {
        let costs = chatHourlyBuckets.map(\.costUSD)
        let anomalies = UsageForecaster.detectAnomalies(costs, threshold: anomalyThreshold)
        VStack(alignment: .leading, spacing: 6) {
            Text("Anomaly Detection (z-score > \(String(format: "%.1f", anomalyThreshold)))")
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
