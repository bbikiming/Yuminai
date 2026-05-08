import SwiftUI
import Charts
import AppKit
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
    /// **ADR-062 Phase 2** — workspace ID → name (workspace별 cache hit chart label)
    public let workspaceNames: [UUID: String]
    public let onClose: () -> Void

    /// **ADR-062 Phase 1** — 시간 범위 filter
    @State private var timeRange: TimeRange = .last24h

    public enum TimeRange: String, CaseIterable, Identifiable {
        case last1h = "1시간"
        case last6h = "6시간"
        case last24h = "24시간"
        case last7d = "7일"
        public var id: String { rawValue }
        public var hours: Int {
            switch self {
            case .last1h: return 1
            case .last6h: return 6
            case .last24h: return 24
            case .last7d: return 7 * 24
            }
        }
    }

    private var filteredCacheTrend: [CacheHitSample] {
        let cutoff = Date().addingTimeInterval(-Double(timeRange.hours) * 3600)
        return cacheTrend.filter { $0.timestamp >= cutoff }
    }

    private var filteredRoutingDecisions: [RoutingDecisionRecord] {
        let cutoff = Date().addingTimeInterval(-Double(timeRange.hours) * 3600)
        return routingDecisions.filter { $0.timestamp >= cutoff }
    }

    public init(
        costSnapshot: CostTracker.Snapshot,
        cacheTrend: [CacheHitSample],
        routingDecisions: [RoutingDecisionRecord],
        workspaceCosts: [(workspaceName: String, costUSD: Double)],
        currentSessionUsage: UsageStats,
        workspaceNames: [UUID: String] = [:],
        onClose: @escaping () -> Void
    ) {
        self.costSnapshot = costSnapshot
        self.cacheTrend = cacheTrend
        self.routingDecisions = routingDecisions
        self.workspaceCosts = workspaceCosts
        self.currentSessionUsage = currentSessionUsage
        self.workspaceNames = workspaceNames
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            timeRangePicker
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    cacheHitTrendChart
                    costBreakdownChart
                    cacheVolumeStackedChart
                    workspaceCacheChart  // ADR-062 Phase 2
                    routingOutcomeDonut
                    routingTimelineHeatmap
                    routingLearningHistoryChart  // ADR-062 Phase 4
                    workspaceCostChart
                    tokenUsageChart
                    cacheCostSavingsChart
                }
                .padding(Theme.Spacing.lg)
            }
            Divider()
            footer
        }
        .yuminaiSheetFrame(width: 920, height: 700, wrapInScrollView: false)
        .background(Theme.Color.bg)
    }

    /// **ADR-062 Phase 1** — 시간 범위 picker.
    private var timeRangePicker: some View {
        HStack {
            Text("시간 범위:")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
            Picker("", selection: $timeRange) {
                ForEach(TimeRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
            Spacer()
            Text("표시 데이터: cache \(filteredCacheTrend.count) · routing \(filteredRoutingDecisions.count)")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
        }
        .padding(Theme.Spacing.md)
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
            // ADR-062 Phase 5 — PNG export
            FlatButton("PNG 내보내기", icon: "square.and.arrow.up", variant: .secondary) {
                exportChartsToPNG()
            }
            // ADR-067 Phase 1 — SVG export menu
            Menu {
                Button("Cache Hit Trend → SVG") { exportSVG(.cacheTrend) }
                Button("Cost Breakdown → SVG") { exportSVG(.costBreakdown) }
                Button("Workspace Cost → SVG") { exportSVG(.workspaceCost) }
            } label: {
                Label("SVG 내보내기", systemImage: "doc.richtext")
                    .font(Theme.Typography.small)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 140)
            Spacer()
            FlatButton("닫기", variant: .primary) { onClose() }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(Theme.Spacing.md)
    }

    /// **ADR-067 Phase 1** — SVG export 종류.
    private enum SVGKind {
        case cacheTrend, costBreakdown, workspaceCost
    }

    @MainActor
    private func exportSVG(_ kind: SVGKind) {
        let svg: String
        let suggestedName: String
        switch kind {
        case .cacheTrend:
            let values = filteredCacheTrend.map { $0.hitRatio * 100 }
            svg = SVGExporter.lineChart(values: values, title: "Cache Hit Ratio (%)", strokeColor: "#10b981", fillColor: "#10b98140")
            suggestedName = "yuminai-cache-trend.svg"
        case .costBreakdown:
            let labels = ["Main", "Decomp", "Rehearsal", "Parallel", "Routing"]
            let values = [costSnapshot.main, costSnapshot.decomposition, costSnapshot.rehearsal, costSnapshot.parallel, costSnapshot.routing]
            svg = SVGExporter.barChart(labels: labels, values: values, title: "Cost Breakdown (USD)", barColor: "#3b82f6")
            suggestedName = "yuminai-cost-breakdown.svg"
        case .workspaceCost:
            svg = SVGExporter.barChart(
                labels: workspaceCosts.map { $0.workspaceName },
                values: workspaceCosts.map { $0.costUSD },
                title: "Workspace Cost (Today)",
                barColor: "#8b5cf6"
            )
            suggestedName = "yuminai-workspace-cost.svg"
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.svg]
        panel.nameFieldStringValue = suggestedName
        if panel.runModal() == .OK, let url = panel.url {
            try? svg.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// **ADR-062 Phase 5** — SwiftUI ImageRenderer로 chart 영역 PNG 저장.
    @MainActor
    private func exportChartsToPNG() {
        // 모든 chart를 한 번에 렌더링 (ScrollView 안의 contents)
        let snapshotView = VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            cacheHitTrendChart
            costBreakdownChart
            workspaceCacheChart
            routingOutcomeDonut
            routingLearningHistoryChart
            workspaceCostChart
            tokenUsageChart
            cacheCostSavingsChart
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 880)
        .background(Theme.Color.bg)

        let renderer = ImageRenderer(content: snapshotView)
        renderer.scale = 2.0  // Retina
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "yuminai-charts-\(Date().timeIntervalSince1970).png"
        if panel.runModal() == .OK, let url = panel.url {
            try? png.write(to: url)
        }
    }

    // MARK: - 1. Cache Hit Trend (LineMark + AreaMark)

    private var cacheHitTrendChart: some View {
        chartSection(title: "1. Cache Hit Ratio (시계열, hourly)", subtitle: "ADR-060 Phase 4 trend · 시간 범위 filter 적용") {
            if filteredCacheTrend.isEmpty {
                emptyHint("아직 cache hit 데이터 없음 — /decompose 또는 rehearsal 실행하면 누적")
            } else {
                Chart(filteredCacheTrend) { sample in
                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Hit Ratio", sample.hitRatio)
                    )
                    .foregroundStyle(Theme.Color.gitAdded)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Hit Ratio", sample.hitRatio)
                    )
                    .foregroundStyle(LinearGradient(
                        colors: [Theme.Color.gitAdded.opacity(0.3), Theme.Color.gitAdded.opacity(0.0)],
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
                        .foregroundStyle(Theme.Color.gitAdded.opacity(0.7))
                        .position(by: .value("Type", "Read"))
                        BarMark(
                            x: .value("Time", sample.timestamp),
                            y: .value("Uncached", sample.uncachedInputTokens)
                        )
                        .foregroundStyle(Theme.Color.warningStrong.opacity(0.7))
                        .position(by: .value("Type", "Uncached"))
                    }
                }
                .chartLegend(position: .top)
                .frame(height: 180)
            }
        }
    }

    // MARK: - ADR-062 Phase 2: Workspace Cache Hit Chart

    @ViewBuilder
    private var workspaceCacheChart: some View {
        chartSection(title: "4. Workspace별 Cache Hit Ratio (ADR-062 Phase 2)", subtitle: "어떤 프로젝트에서 cache 효과가 좋은지") {
            // workspaceId별 sample 그룹화 + ratio 계산
            let grouped = Dictionary(grouping: filteredCacheTrend.compactMap { sample -> (UUID, CacheHitSample)? in
                guard let wsId = sample.workspaceId else { return nil }
                return (wsId, sample)
            }, by: { $0.0 })
            let wsRatios: [(name: String, ratio: Double, totalRead: Int)] = grouped.compactMap { (wsId, samples) in
                let totalRead = samples.reduce(0) { $0 + $1.1.readTokens }
                let totalUncached = samples.reduce(0) { $0 + $1.1.uncachedInputTokens }
                let total = totalRead + totalUncached
                guard total > 0 else { return nil }
                let name = workspaceNames[wsId] ?? wsId.uuidString.prefix(8) + "…"
                let ratio = Double(totalRead) / Double(total)
                return (name: String(name), ratio: ratio, totalRead: totalRead)
            }.sorted { $0.ratio > $1.ratio }
            if wsRatios.isEmpty {
                emptyHint("workspace cache 데이터 없음 (워크스페이스에서 격리 호출 시 누적)")
            } else {
                Chart {
                    ForEach(Array(wsRatios.enumerated()), id: \.offset) { _, item in
                        BarMark(
                            x: .value("Ratio", item.ratio),
                            y: .value("Workspace", item.name)
                        )
                        .foregroundStyle(item.ratio > 0.5 ? Theme.Color.gitAdded : (item.ratio > 0.2 ? Theme.Color.favoriteStar : Theme.Color.warningStrong))
                        .annotation(position: .trailing) {
                            Text("\(Int(item.ratio * 100))% (\(item.totalRead.formattedShort) tok)")
                                .font(.caption2)
                                .foregroundStyle(Theme.Color.textSecondary)
                        }
                    }
                }
                .chartXScale(domain: 0...1)
                .chartXAxis {
                    AxisMarks(position: .bottom) { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(Int(v * 100))%")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: CGFloat(wsRatios.count * 32 + 40))
            }
        }
    }

    // MARK: - 5. Routing Outcome Donut

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

    // MARK: - ADR-062 Phase 4: Routing Learning History Chart

    private var routingLearningHistoryChart: some View {
        chartSection(title: "7. Routing 결정 시간 추이 (ADR-062 Phase 4)", subtitle: "applied vs cancelled 시간순 누적 line chart") {
            if filteredRoutingDecisions.isEmpty {
                emptyHint("routing 기록 없음")
            } else {
                // 시간 순으로 정렬 (오래된 → 최근), 누적 카운트 계산
                let sorted = filteredRoutingDecisions.sorted { $0.timestamp < $1.timestamp }
                var appliedCum = 0
                var cancelCum = 0
                let timelineData: [(time: Date, applied: Int, cancelled: Int)] = sorted.map { record in
                    if record.outcome == .applied { appliedCum += 1 }
                    if record.outcome == .cancelled { cancelCum += 1 }
                    return (time: record.timestamp, applied: appliedCum, cancelled: cancelCum)
                }
                Chart {
                    ForEach(Array(timelineData.enumerated()), id: \.offset) { _, point in
                        LineMark(
                            x: .value("Time", point.time),
                            y: .value("Cumulative", point.applied),
                            series: .value("Type", "Applied")
                        )
                        .foregroundStyle(Theme.Color.gitAdded)
                        .interpolationMethod(.stepEnd)
                        LineMark(
                            x: .value("Time", point.time),
                            y: .value("Cumulative", point.cancelled),
                            series: .value("Type", "Cancelled")
                        )
                        .foregroundStyle(Theme.Color.warningStrong)
                        .interpolationMethod(.stepEnd)
                    }
                }
                .chartLegend(position: .top)
                .frame(height: 180)
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
                        .foregroundStyle(Theme.Color.infoBlue.opacity(0.7))
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
                        .foregroundStyle(Theme.Color.gitAdded)
                        .interpolationMethod(.catmullRom)
                        AreaMark(
                            x: .value("Time", item.timestamp),
                            y: .value("Saved", item.savedUSD)
                        )
                        .foregroundStyle(LinearGradient(
                            colors: [Theme.Color.gitAdded.opacity(0.3), Theme.Color.gitAdded.opacity(0.0)],
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
                    .foregroundStyle(Theme.Color.gitAdded)
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
        // ADR-071 Phase 3 — VoiceOver: 차트 섹션을 단일 element로 묶고 title+subtitle을 label로
        .accessibilityElement(children: .contain)
        .accessibilityLabel("차트, \(title)")
        .accessibilityHint(subtitle)
    }

    private func emptyHint(_ message: String) -> some View {
        Text(message)
            .font(Theme.Typography.small)
            .foregroundStyle(Theme.Color.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(Theme.Spacing.lg)
    }
}
