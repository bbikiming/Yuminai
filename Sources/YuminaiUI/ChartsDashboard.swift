import SwiftUI
import Charts
import YuminaiCore

/// **ADR-061 Phase 1** — 통합 SwiftUI Charts dashboard.
///
/// 다양한 데이터 시각화:
/// 1. **Cache Hit Trend** (LineMark / AreaMark) — hourly cache hit ratio 시계열
/// 2. **Cost Breakdown** (BarMark) — 5 buckets cost
/// 3. **Cache Volume Stacked** (BarMark stacked) — read/uncached tokens
/// 4. **Routing Outcome Distribution** (SectorMark, donut chart)
/// 5. **Routing Decisions Timeline** (RectangleMark) — 시간순 outcome heatmap
/// 6. **Workspace Cost** (horizontal BarMark)
/// 7. **Token Usage** (BarMark) — input/output tokens
/// 8. **Cache Cost Savings** (LineMark) — cache로 절약한 추정 비용
///
/// **출처**: SwiftUI Charts framework (macOS 13+)
/// https://developer.apple.com/documentation/charts
public struct ChartsDashboard: View {
    public let costSnapshot: CostTracker.Snapshot
    public let cacheTrend: [CacheHitSample]
    public let routingDecisions: [RoutingDecisionRecord]
    public let workspaceCosts: [(workspaceName: String, costUSD: Double)]
    public let currentSessionUsage: UsageStats
    public let onClose: () -> Void

    public init(
        costSnapshot: CostTracker.Snapshot,
        cacheTrend: [CacheHitSample],
        routingDecisions: [RoutingDecisionRecord],
        workspaceCosts: [(workspaceName: String, costUSD: Double)],
        currentSessionUsage: UsageStats,
        onClose: @escaping () -> Void
    ) {
        self.costSnapshot = costSnapshot
        self.cacheTrend = cacheTrend
        self.routingDecisions = routingDecisions
        self.workspaceCosts = workspaceCosts
        self.currentSessionUsage = currentSessionUsage
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    cacheHitTrendChart
                    costBreakdownChart
                    cacheVolumeStackedChart
                    routingOutcomeDonut
                    routingTimelineHeatmap
                    workspaceCostChart
                    tokenUsageChart
                    cacheCostSavingsChart
                }
                .padding(Theme.Spacing.lg)
            }
            Divider()
            footer
        }
        .frame(width: 920, height: 700)
        .background(Theme.Color.bg)
    }

    // MARK: - Header / Footer

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Color.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Charts Dashboard")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
                Text("ADR-061 Phase 1 — 8개 chart로 시각화 (cache trend / cost / routing / workspace / tokens)")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
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

    // MARK: - 1. Cache Hit Trend (LineMark + AreaMark)

    private var cacheHitTrendChart: some View {
        chartSection(title: "1. Cache Hit Ratio (시계열, hourly)", subtitle: "ADR-060 Phase 4 trend") {
            if cacheTrend.isEmpty {
                emptyHint("아직 cache hit 데이터 없음 — /decompose 또는 rehearsal 실행하면 누적")
            } else {
                Chart(cacheTrend) { sample in
                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Hit Ratio", sample.hitRatio)
                    )
                    .foregroundStyle(Color.green)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Hit Ratio", sample.hitRatio)
                    )
                    .foregroundStyle(LinearGradient(
                        colors: [Color.green.opacity(0.3), Color.green.opacity(0.0)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .interpolationMethod(.catmullRom)
                }
                .chartYScale(domain: 0...1)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(Int(v * 100))%")
                                    .font(.caption)
                            }
                        }
                    }
                }
                .frame(height: 180)
            }
        }
    }

    // MARK: - 2. Cost Breakdown (BarMark)

    private var costBreakdownChart: some View {
        chartSection(title: "2. Cost 분리 (5 buckets)", subtitle: "ADR-052/053/055 격리 호출별") {
            let data: [(label: String, value: Double, color: Color)] = [
                ("Main", costSnapshot.main, .blue),
                ("Decomp", costSnapshot.decomposition, .indigo),
                ("Rehearsal", costSnapshot.rehearsal, .orange),
                ("Parallel", costSnapshot.parallel, .purple),
                ("Routing", costSnapshot.routing, .gray)
            ]
            Chart {
                ForEach(data, id: \.label) { item in
                    BarMark(
                        x: .value("Bucket", item.label),
                        y: .value("Cost", item.value)
                    )
                    .foregroundStyle(item.color)
                    .annotation(position: .top) {
                        if item.value > 0 {
                            Text("$\(String(format: "%.4f", item.value))")
                                .font(.caption2)
                                .foregroundStyle(Theme.Color.textSecondary)
                        }
                    }
                }
            }
            .frame(height: 180)
        }
    }

    // MARK: - 3. Cache Volume Stacked Bar

    private var cacheVolumeStackedChart: some View {
        chartSection(title: "3. Cache 토큰 볼륨 (시계열)", subtitle: "stacked bar: read vs uncached") {
            if cacheTrend.isEmpty {
                emptyHint("데이터 없음")
            } else {
                Chart {
                    ForEach(cacheTrend) { sample in
                        BarMark(
                            x: .value("Time", sample.timestamp),
                            y: .value("Read (cached)", sample.readTokens)
                        )
                        .foregroundStyle(Color.green.opacity(0.7))
                        .position(by: .value("Type", "Read"))
                        BarMark(
                            x: .value("Time", sample.timestamp),
                            y: .value("Uncached", sample.uncachedInputTokens)
                        )
                        .foregroundStyle(Color.orange.opacity(0.7))
                        .position(by: .value("Type", "Uncached"))
                    }
                }
                .chartLegend(position: .top)
                .frame(height: 180)
            }
        }
    }

    // MARK: - 4. Routing Outcome Donut

    @ViewBuilder
    private var routingOutcomeDonut: some View {
        chartSection(title: "4. Routing Outcome 분포", subtitle: "applied / cancelled / skipped / failed") {
            if routingDecisions.isEmpty {
                emptyHint("routing 기록 없음")
            } else {
                let groups = Dictionary(grouping: routingDecisions, by: \.outcome)
                let data: [(label: String, count: Int, color: Color)] = [
                    ("applied", groups[.applied]?.count ?? 0, .green),
                    ("cancelled", groups[.cancelled]?.count ?? 0, .orange),
                    ("skipped", groups[.skipped]?.count ?? 0, .gray),
                    ("failed", groups[.failed]?.count ?? 0, .red)
                ].filter { $0.count > 0 }
                Chart {
                    ForEach(data, id: \.label) { item in
                        SectorMark(
                            angle: .value("Count", item.count),
                            innerRadius: .ratio(0.55),
                            angularInset: 1.5
                        )
                        .foregroundStyle(item.color)
                        .annotation(position: .overlay) {
                            Text("\(item.count)")
                                .font(.caption)
                                .foregroundStyle(.white)
                        }
                    }
                }
                .chartLegend(position: .trailing, alignment: .center)
                .frame(height: 200)
            }
        }
    }

    // MARK: - 5. Routing Timeline Heatmap (RectangleMark)

    private var routingTimelineHeatmap: some View {
        chartSection(title: "5. Routing 결정 시간순 (최근 100개)", subtitle: "ADR-060 Phase 2 heatmap 확장") {
            let recent = Array(routingDecisions.prefix(100)).reversed()
            if recent.isEmpty {
                emptyHint("routing 기록 없음")
            } else {
                Chart {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { idx, record in
                        let color: Color = {
                            switch record.outcome {
                            case .applied: return .green
                            case .cancelled: return .orange
                            case .skipped: return .gray
                            case .failed: return .red
                            }
                        }()
                        RectangleMark(
                            x: .value("Index", idx),
                            y: .value("Outcome", record.outcome.rawValue)
                        )
                        .foregroundStyle(color)
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: 120)
            }
        }
    }

    // MARK: - 6. Workspace Cost (Horizontal BarMark)

    @ViewBuilder
    private var workspaceCostChart: some View {
        chartSection(title: "6. Workspace별 오늘 Cost", subtitle: "ADR-059/060 workspace 격리") {
            if workspaceCosts.isEmpty {
                emptyHint("아직 workspace cost 누적 없음")
            } else {
                Chart {
                    ForEach(Array(workspaceCosts.enumerated()), id: \.offset) { _, ws in
                        BarMark(
                            x: .value("Cost", ws.costUSD),
                            y: .value("Workspace", ws.workspaceName)
                        )
                        .foregroundStyle(Color.blue.opacity(0.7))
                        .annotation(position: .trailing) {
                            Text("$\(String(format: "%.4f", ws.costUSD))")
                                .font(.caption2)
                                .foregroundStyle(Theme.Color.textSecondary)
                        }
                    }
                }
                .frame(height: CGFloat(workspaceCosts.count * 30 + 40))
            }
        }
    }

    // MARK: - 7. Token Usage (BarMark)

    private var tokenUsageChart: some View {
        chartSection(title: "7. 현재 세션 토큰 사용", subtitle: "input / output / cache read") {
            let data: [(label: String, value: Int, color: Color)] = [
                ("Input", currentSessionUsage.inputTokens, .blue),
                ("Output", currentSessionUsage.outputTokens, .orange),
                ("Cache Read", currentSessionUsage.cacheReadTokens, .green),
                ("Cache Create", currentSessionUsage.cacheCreationTokens, .purple)
            ].filter { $0.value > 0 }
            if data.isEmpty {
                emptyHint("토큰 사용 0")
            } else {
                Chart {
                    ForEach(data, id: \.label) { item in
                        BarMark(
                            x: .value("Type", item.label),
                            y: .value("Tokens", item.value)
                        )
                        .foregroundStyle(item.color)
                        .annotation(position: .top) {
                            Text(item.value.formattedShort)
                                .font(.caption2)
                                .foregroundStyle(Theme.Color.textSecondary)
                        }
                    }
                }
                .frame(height: 180)
            }
        }
    }

    // MARK: - 8. Cache Cost Savings (LineMark)

    private var cacheCostSavingsChart: some View {
        chartSection(title: "8. Cache 절약 비용 (추정)", subtitle: "cache_read_tokens × $0.0003/1K (Sonnet 90% 할인)") {
            if cacheTrend.isEmpty {
                emptyHint("데이터 없음")
            } else {
                // Sonnet 4.5: cache hit input은 normal $3/M의 10% = $0.30/M = $0.0003/1K
                // 절약된 비용 = readTokens × ($3/M - $0.30/M) = readTokens × $0.0027/1K
                let savingsData = cacheTrend.map { sample -> (timestamp: Date, savedUSD: Double) in
                    let saved = Double(sample.readTokens) / 1000.0 * 0.0027
                    return (sample.timestamp, saved)
                }
                let totalSaved = savingsData.reduce(0) { $0 + $1.savedUSD }
                Chart {
                    ForEach(Array(savingsData.enumerated()), id: \.offset) { _, item in
                        LineMark(
                            x: .value("Time", item.timestamp),
                            y: .value("Saved", item.savedUSD)
                        )
                        .foregroundStyle(Color.green)
                        .interpolationMethod(.catmullRom)
                        AreaMark(
                            x: .value("Time", item.timestamp),
                            y: .value("Saved", item.savedUSD)
                        )
                        .foregroundStyle(LinearGradient(
                            colors: [Color.green.opacity(0.3), Color.green.opacity(0.0)],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("$\(String(format: "%.4f", v))")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 160)
                Text("총 절약 추정: $\(String(format: "%.4f", totalSaved))")
                    .font(Theme.Typography.small.weight(.medium))
                    .foregroundStyle(Color.green)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Helpers

    private func chartSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Typography.body.weight(.semibold))
                .foregroundStyle(Theme.Color.text)
            Text(subtitle)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
            content()
                .padding(.top, 4)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private func emptyHint(_ message: String) -> some View {
        Text(message)
            .font(Theme.Typography.small)
            .foregroundStyle(Theme.Color.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(Theme.Spacing.lg)
    }
}
