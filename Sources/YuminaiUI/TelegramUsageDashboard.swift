import SwiftUI
import Charts
import AppKit
import YuminaiCore

/// **ADR-062 Phase 6** — 사용자 신규 요청.
///
/// "텔레그램과의 연동 기능을 얼마나 이용했고 얼마나 토큰이 소모됐는지" 대시보드.
///
/// **표시 정보**:
/// 1. 요약 카드: 총 turn / 총 cost / 총 token / 명령 수
/// 2. 시간별 turn count (BarMark, hourly)
/// 3. 시간별 cost trend (LineMark + AreaMark)
/// 4. chat별 사용량 (horizontal BarMark + ranking)
/// 5. 명령별 사용 빈도 (BarMark Top 10)
/// 6. 토큰 분리 (input vs output, BarMark stacked)
/// **ADR-063 Phase 5** — workspace × chat usage chart datum.
private struct WorkspaceUsageDatum: Identifiable, Hashable {
    let id = UUID()
    let chatLabel: String
    let workspaceName: String
    let count: Int
}

public struct TelegramUsageDashboard: View {
    public let snapshot: TelegramUsageStore.Snapshot
    public let dailyBuckets: [DailyUsageBucket]
    /// chat ID → workspace name (UI 라벨 보강용)
    public let chatIdToWorkspaceName: [String: String]
    /// **ADR-063 Phase 5** — workspace UUID(string) → name
    public let workspaceIdToName: [String: String]
    /// **ADR-064 Phase 1** — routing decisions (telegram dashboard에 통합)
    public let routingDecisions: [RoutingDecisionRecord]
    public let onClose: () -> Void
    public let onClearStats: () -> Void

    /// **ADR-063 Phase 3** — 시간 범위 filter
    @State private var timeRange: TimeRange = .last7d
    /// **ADR-063 Phase 2** — daily vs hourly view 토글
    @State private var aggregationMode: AggregationMode = .hourly

    public enum TimeRange: String, CaseIterable, Identifiable {
        case last24h = "24h"
        case last3d = "3일"
        case last7d = "7일"
        public var id: String { rawValue }
        public var hours: Int {
            switch self {
            case .last24h: return 24
            case .last3d: return 72
            case .last7d: return 168
            }
        }
    }

    public enum AggregationMode: String, CaseIterable, Identifiable {
        case hourly = "시간별"
        case daily = "일별"
        public var id: String { rawValue }
    }

    private var filteredHourly: [HourlyUsageBucket] {
        let cutoff = Date().addingTimeInterval(-Double(timeRange.hours) * 3600)
        return snapshot.hourlyBuckets.filter { $0.timestamp >= cutoff }
    }

    private var filteredDaily: [DailyUsageBucket] {
        let cutoff = Date().addingTimeInterval(-Double(timeRange.hours) * 3600)
        return dailyBuckets.filter { $0.date >= cutoff }
    }

    public init(
        snapshot: TelegramUsageStore.Snapshot,
        dailyBuckets: [DailyUsageBucket] = [],
        chatIdToWorkspaceName: [String: String],
        workspaceIdToName: [String: String] = [:],
        routingDecisions: [RoutingDecisionRecord] = [],
        onClose: @escaping () -> Void,
        onClearStats: @escaping () -> Void
    ) {
        self.snapshot = snapshot
        self.dailyBuckets = dailyBuckets
        self.chatIdToWorkspaceName = chatIdToWorkspaceName
        self.workspaceIdToName = workspaceIdToName
        self.routingDecisions = routingDecisions
        self.onClose = onClose
        self.onClearStats = onClearStats
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            controlsBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    summaryCards
                    hourlyTurnsChart
                    hourlyCostChart
                    forecastChart           // ADR-064 Phase 5
                    chatRankingChart
                    chatActivityGauge       // ADR-064 Phase 4
                    commandFrequencyChart
                    tokenBreakdownChart
                    workspaceUsagePerChatChart
                    workspaceChatHeatmap    // ADR-064 Phase 2
                    routingTrendChart       // ADR-064 Phase 1
                }
                .padding(Theme.Spacing.lg)
            }
            Divider()
            footer
        }
        .frame(width: 880, height: 720)
        .background(Theme.Color.bg)
    }

    /// **ADR-063 Phase 3** — 시간 범위 + aggregation mode picker.
    private var controlsBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Text("기간:")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                Picker("", selection: $timeRange) {
                    ForEach(TimeRange.allCases) { r in Text(r.rawValue).tag(r) }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            HStack(spacing: 6) {
                Text("집계:")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                Picker("", selection: $aggregationMode) {
                    ForEach(AggregationMode.allCases) { m in Text(m.rawValue).tag(m) }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }
            Spacer()
            // ADR-063 Phase 4 — CSV export
            Menu {
                Button("Chat Stats → CSV") { exportCSV(.chatStats) }
                Button("Command Stats → CSV") { exportCSV(.commandStats) }
                Button("Hourly Buckets → CSV") { exportCSV(.hourly) }
                Button("Daily Buckets → CSV") { exportCSV(.daily) }
            } label: {
                Label("CSV 내보내기", systemImage: "tablecells")
                    .font(Theme.Typography.small)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 140)
        }
        .padding(Theme.Spacing.md)
    }

    // MARK: - Header / Footer

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "paperplane.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Telegram 사용 통계")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
                Text("ADR-062 Phase 6 — 외부 vibe-coding 활용도 + 토큰 소모 시각화")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
        }
        .padding(Theme.Spacing.lg)
    }

    private var footer: some View {
        HStack {
            FlatButton("통계 초기화", icon: "trash", variant: .secondary) { onClearStats() }
            Spacer()
            FlatButton("닫기", variant: .primary) { onClose() }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(Theme.Spacing.md)
    }

    // MARK: - 1. Summary cards

    private var summaryCards: some View {
        HStack(spacing: 12) {
            summaryCard(
                icon: "arrow.up.circle.fill",
                color: .blue,
                label: "총 외부 turn",
                value: "\(snapshot.totalTurns)"
            )
            summaryCard(
                icon: "dollarsign.circle.fill",
                color: .green,
                label: "총 비용",
                value: "$\(String(format: "%.4f", snapshot.totalCostUSD))"
            )
            summaryCard(
                icon: "text.bubble.fill",
                color: .indigo,
                label: "총 토큰",
                value: totalTokens.formattedShort
            )
            summaryCard(
                icon: "command.circle.fill",
                color: .orange,
                label: "총 명령",
                value: "\(snapshot.totalCommands)"
            )
        }
    }

    private func summaryCard(icon: String, color: Color, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(label)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .textCase(.uppercase)
                Spacer()
            }
            Text(value)
                .font(Theme.Typography.title.weight(.semibold))
                .foregroundStyle(Theme.Color.text)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private var totalTokens: Int {
        snapshot.chatStats.values.reduce(0) { $0 + $1.totalInputTokens + $1.totalOutputTokens }
    }

    // MARK: - 2. Hourly Turn Count (BarMark)

    @ViewBuilder
    private var hourlyTurnsChart: some View {
        let title = aggregationMode == .hourly ? "시간별 외부 turn 횟수" : "일별 외부 turn 횟수"
        chartSection(title: title, subtitle: "ADR-063 Phase 2/3 — \(timeRange.rawValue) range, \(aggregationMode.rawValue) 집계", chartId: "hourly_turns") {
            if aggregationMode == .hourly {
                if filteredHourly.isEmpty {
                    emptyHint("Telegram 외부 turn 사용 시작하면 누적")
                } else {
                    Chart(filteredHourly) { bucket in
                        BarMark(x: .value("Time", bucket.timestamp), y: .value("Turns", bucket.turnCount))
                            .foregroundStyle(Color.blue.opacity(0.7))
                    }
                    .frame(height: 160)
                }
            } else {
                if filteredDaily.isEmpty {
                    emptyHint("일별 데이터 없음")
                } else {
                    Chart(filteredDaily) { bucket in
                        BarMark(x: .value("Date", bucket.date), y: .value("Turns", bucket.turnCount))
                            .foregroundStyle(Color.blue.opacity(0.7))
                    }
                    .frame(height: 160)
                }
            }
        }
    }

    // MARK: - 3. Hourly Cost (LineMark + AreaMark)

    @ViewBuilder
    private var hourlyCostChart: some View {
        chartSection(title: "누적 비용 trend", subtitle: "ADR-063 Phase 3 — \(timeRange.rawValue) range", chartId: "hourly_cost") {
            let buckets: [(date: Date, cost: Double)] = aggregationMode == .hourly
                ? filteredHourly.map { ($0.timestamp, $0.costUSD) }
                : filteredDaily.map { ($0.date, $0.costUSD) }
            if buckets.isEmpty {
                emptyHint("아직 cost 발생 없음")
            } else {
                Chart {
                    ForEach(Array(buckets.enumerated()), id: \.offset) { _, b in
                        LineMark(x: .value("Time", b.date), y: .value("Cost", b.cost))
                            .foregroundStyle(Color.green)
                            .interpolationMethod(.catmullRom)
                        AreaMark(x: .value("Time", b.date), y: .value("Cost", b.cost))
                            .foregroundStyle(LinearGradient(colors: [Color.green.opacity(0.3), Color.green.opacity(0)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("$\(String(format: "%.4f", v))").font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 160)
            }
        }
    }

    // MARK: - 4. Chat Ranking (horizontal bar)

    private var chatRankingChart: some View {
        chartSection(title: "Chat별 사용량 ranking", subtitle: "turn count + cost 별", chartId: "chat_ranking") {
            let sorted = snapshot.chatStats.values.sorted { $0.turnCount > $1.turnCount }.prefix(10)
            if sorted.isEmpty {
                emptyHint("chat 사용 기록 없음")
            } else {
                Chart {
                    ForEach(Array(sorted), id: \.chatId) { chat in
                        let label = chatLabel(for: chat.chatId)
                        BarMark(
                            x: .value("Turns", chat.turnCount),
                            y: .value("Chat", label)
                        )
                        .foregroundStyle(Color.blue.opacity(0.7))
                        .annotation(position: .trailing) {
                            Text("\(chat.turnCount) turn · $\(String(format: "%.4f", chat.totalCostUSD))")
                                .font(.caption2)
                                .foregroundStyle(Theme.Color.textSecondary)
                        }
                    }
                }
                .frame(height: CGFloat(sorted.count * 32 + 40))
            }
        }
    }

    private func chatLabel(for chatId: Int64) -> String {
        let key = String(chatId)
        if let wsName = chatIdToWorkspaceName[key] {
            return "\(wsName) (#\(key.suffix(6)))"
        }
        return "Chat #\(chatId)"
    }

    // MARK: - 5. Command Frequency (BarMark Top 10)

    private var commandFrequencyChart: some View {
        chartSection(title: "명령 사용 빈도 (Top 10)", subtitle: "/decompose, /tasks, /rehearse 등", chartId: "command_freq") {
            let sorted = snapshot.commandStats.sorted { $0.value > $1.value }.prefix(10)
            if sorted.isEmpty {
                emptyHint("명령 사용 없음")
            } else {
                Chart {
                    ForEach(Array(sorted), id: \.key) { item in
                        BarMark(
                            x: .value("Command", item.key),
                            y: .value("Count", item.value)
                        )
                        .foregroundStyle(Color.orange.opacity(0.7))
                        .annotation(position: .top) {
                            Text("\(item.value)")
                                .font(.caption2)
                                .foregroundStyle(Theme.Color.textSecondary)
                        }
                    }
                }
                .frame(height: 180)
            }
        }
    }

    // MARK: - 6. Token Breakdown (Stacked BarMark per hour)

    private var tokenBreakdownChart: some View {
        chartSection(title: "토큰 사용 (input vs output)", subtitle: "시간별 stacked bar", chartId: "token_breakdown") {
            if snapshot.hourlyBuckets.isEmpty {
                emptyHint("토큰 사용 없음")
            } else {
                Chart {
                    ForEach(snapshot.hourlyBuckets) { bucket in
                        BarMark(
                            x: .value("Time", bucket.timestamp),
                            y: .value("Input", bucket.inputTokens)
                        )
                        .foregroundStyle(Color.blue.opacity(0.7))
                        .position(by: .value("Type", "Input"))
                        BarMark(
                            x: .value("Time", bucket.timestamp),
                            y: .value("Output", bucket.outputTokens)
                        )
                        .foregroundStyle(Color.orange.opacity(0.7))
                        .position(by: .value("Type", "Output"))
                    }
                }
                .chartLegend(position: .top)
                .frame(height: 180)
            }
        }
    }

    // MARK: - Helpers

    // MARK: - ADR-064 Phase 5: EWMA Forecast

    @ViewBuilder
    private var forecastChart: some View {
        chartSection(title: "사용량 forecast (EWMA)", subtitle: "ADR-064 Phase 5 — 다음 \(aggregationMode.rawValue) 예상치", chartId: "forecast") {
            forecastContent
        }
    }

    @ViewBuilder
    private var forecastContent: some View {
        let costs: [Double] = aggregationMode == .hourly
            ? filteredHourly.map { $0.costUSD }
            : filteredDaily.map { $0.costUSD }
        if costs.count < UsageForecaster.minSamples {
            emptyHint("forecast: \(UsageForecaster.minSamples)개 이상 sample 필요 (현재 \(costs.count))")
        } else {
            let smoothed = UsageForecaster.ewmaSeries(costs)
            let next = UsageForecaster.forecastNext(costs) ?? 0
            let trend = UsageForecaster.trend(costs)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Image(systemName: trend.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(trend == .up ? .red : (trend == .down ? .green : .gray))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("다음 \(aggregationMode.rawValue) 예상: $\(String(format: "%.4f", next))")
                            .font(Theme.Typography.body.weight(.medium))
                        Text("Trend: \(trend.rawValue)")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                    Spacer()
                }
                Chart {
                    ForEach(Array(smoothed.enumerated()), id: \.offset) { idx, value in
                        LineMark(
                            x: .value("Sample", idx),
                            y: .value("Smoothed", value)
                        )
                        .foregroundStyle(Color.purple)
                        .interpolationMethod(.catmullRom)
                    }
                    ForEach(Array(costs.enumerated()), id: \.offset) { idx, value in
                        PointMark(
                            x: .value("Sample", idx),
                            y: .value("Actual", value)
                        )
                        .foregroundStyle(Color.gray.opacity(0.5))
                        .symbolSize(20)
                    }
                    // forecast point (다음 sample)
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
    }

    // MARK: - ADR-064 Phase 4: Chat last activity gauge

    private var chatActivityGauge: some View {
        chartSection(title: "Chat 활동 시간 (gauge)", subtitle: "ADR-064 Phase 4 — 마지막 활동 후 경과 시간", chartId: "activity_gauge") {
            chatActivityContent
        }
    }

    @ViewBuilder
    private var chatActivityContent: some View {
        let sorted = snapshot.chatStats.values.sorted { $0.lastUsedAt > $1.lastUsedAt }.prefix(10)
        if sorted.isEmpty {
            emptyHint("chat 활동 기록 없음")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(sorted), id: \.chatId) { chat in
                    HStack(spacing: 8) {
                        Text(chatLabel(for: chat.chatId))
                            .font(Theme.Typography.small)
                            .foregroundStyle(Theme.Color.text)
                            .frame(width: 200, alignment: .leading)
                            .lineLimit(1)
                        let elapsed = Date().timeIntervalSince(chat.lastUsedAt)
                        let pct = activityFreshness(elapsed: elapsed)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Theme.Color.surfaceHi)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(activityColor(pct))
                                    .frame(width: geo.size.width * pct)
                            }
                        }
                        .frame(height: 10)
                        Text(formatElapsed(elapsed))
                            .font(Theme.Typography.monoSmall)
                            .foregroundStyle(activityColor(pct))
                            .frame(width: 80, alignment: .trailing)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// 마지막 활동으로부터 경과 시간 → freshness ratio (1.0 = 방금, 0.0 = 일주일+).
    private func activityFreshness(elapsed: TimeInterval) -> Double {
        let weekSeconds: TimeInterval = 7 * 86_400
        return max(0, 1 - elapsed / weekSeconds)
    }

    private func activityColor(_ freshness: Double) -> Color {
        if freshness > 0.7 { return .green }
        if freshness > 0.3 { return .yellow }
        return .gray
    }

    private func formatElapsed(_ secs: TimeInterval) -> String {
        if secs < 60 { return "\(Int(secs))초 전" }
        if secs < 3600 { return "\(Int(secs / 60))분 전" }
        if secs < 86_400 { return "\(Int(secs / 3600))시간 전" }
        return "\(Int(secs / 86_400))일 전"
    }

    // MARK: - ADR-064 Phase 2: workspace × chat heatmap (RectangleMark)

    @ViewBuilder
    private var workspaceChatHeatmap: some View {
        chartSection(title: "Workspace × Chat heatmap", subtitle: "ADR-064 Phase 2 — 사용 빈도 heatmap (intensity = count)", chartId: "ws_chat_heatmap") {
            heatmapContent
        }
    }

    @ViewBuilder
    private var heatmapContent: some View {
        let data: [WorkspaceUsageDatum] = snapshot.chatStats.values.flatMap { chat -> [WorkspaceUsageDatum] in
            chat.workspaceUsageCounts.map { (wsKey, count) in
                let wsName = workspaceIdToName[wsKey] ?? String(wsKey.prefix(8)) + "…"
                return WorkspaceUsageDatum(
                    chatLabel: chatLabel(for: chat.chatId),
                    workspaceName: wsName,
                    count: count
                )
            }
        }
        if data.isEmpty {
            emptyHint("아직 workspace × chat 데이터 없음")
        } else {
            let maxCount = data.map(\.count).max() ?? 1
            Chart {
                ForEach(data) { d in
                    RectangleMark(
                        x: .value("Chat", d.chatLabel),
                        y: .value("Workspace", d.workspaceName)
                    )
                    .foregroundStyle(by: .value("Intensity", d.count))
                    .annotation(position: .overlay) {
                        Text("\(d.count)")
                            .font(.caption2)
                            .foregroundStyle(.white)
                    }
                }
            }
            .chartForegroundStyleScale(range: Gradient(colors: [.blue.opacity(0.2), .blue]))
            .frame(height: CGFloat(min(8, snapshot.chatStats.count) * 50 + 60))
            Text("색상 진하기 = 사용 빈도 (max \(maxCount))")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
        }
    }

    // MARK: - ADR-064 Phase 1: Routing trend in Telegram dashboard

    private var routingTrendChart: some View {
        chartSection(title: "Routing 결정 trend (외부 turn 영향)", subtitle: "ADR-064 Phase 1 — Telegram dashboard에 routing log 통합", chartId: "routing_trend") {
            routingTrendContent
        }
    }

    @ViewBuilder
    private var routingTrendContent: some View {
        let cutoff = Date().addingTimeInterval(-Double(timeRange.hours) * 3600)
        let filtered = routingDecisions.filter { $0.timestamp >= cutoff }
        if filtered.isEmpty {
            emptyHint("routing 결정 없음 (자동 routing 활성 + 외부 turn 시 누적)")
        } else {
            // outcome 분포 dot bar
            let counts = Dictionary(grouping: filtered, by: \.outcome).mapValues(\.count)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    statBlock("Applied", counts[.applied] ?? 0, color: .green)
                    statBlock("Cancelled", counts[.cancelled] ?? 0, color: .orange)
                    statBlock("Skipped", counts[.skipped] ?? 0, color: .gray)
                    statBlock("Failed", counts[.failed] ?? 0, color: .red)
                    Spacer()
                }
                Chart {
                    ForEach(Array(filtered.suffix(60).reversed().enumerated()), id: \.element.id) { idx, record in
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
                .frame(height: 100)
            }
        }
    }

    private func statBlock(_ label: String, _ value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
                .textCase(.uppercase)
            Text("\(value)")
                .font(Theme.Typography.body.weight(.semibold))
                .foregroundStyle(color)
        }
    }

    /// **ADR-063 Phase 5** — chat별 어떤 workspace를 가장 많이 사용했는지 stacked bar.
    private var workspaceUsagePerChatChart: some View {
        chartSection(title: "Chat × Workspace 사용 분포", subtitle: "ADR-063 Phase 5 — chat별 workspace 멀티 사용", chartId: "chat_workspace") {
            workspaceUsageContent
        }
    }

    @ViewBuilder
    private var workspaceUsageContent: some View {
        let data: [WorkspaceUsageDatum] = snapshot.chatStats.values.flatMap { chat -> [WorkspaceUsageDatum] in
            chat.workspaceUsageCounts.map { (wsKey, count) in
                let wsName = workspaceIdToName[wsKey] ?? String(wsKey.prefix(8)) + "…"
                return WorkspaceUsageDatum(
                    chatLabel: chatLabel(for: chat.chatId),
                    workspaceName: wsName,
                    count: count
                )
            }
        }
        if data.isEmpty {
            emptyHint("workspace × chat 데이터 없음 (외부 turn에서 누적)")
        } else {
            Chart {
                ForEach(data) { d in
                    BarMark(
                        x: .value("Chat", d.chatLabel),
                        y: .value("Count", d.count)
                    )
                    .foregroundStyle(by: .value("Workspace", d.workspaceName))
                    .position(by: .value("Workspace", d.workspaceName))
                }
            }
            .chartLegend(position: .top)
            .frame(height: 200)
        }
    }

    /// **ADR-063 Phase 1** — chartSection. PNG export는 caller가 별도 호출.
    /// chartId는 export filename용.
    private func chartSection<Content: View>(
        title: String,
        subtitle: String,
        chartId: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let renderedContent = content()
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.Typography.body.weight(.semibold))
                        .foregroundStyle(Theme.Color.text)
                    Text(subtitle)
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
                Spacer()
                // ADR-063 Phase 1 — per-chart PNG export
                Button {
                    exportChartPNG(chartId: chartId, view: AnyView(renderedContent))
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Color.textTertiary)
                }
                .buttonStyle(.plain)
                .help("이 chart를 PNG로 저장")
            }
            renderedContent
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

    // MARK: - ADR-063 Phase 1 — per-chart PNG export

    @MainActor
    private func exportChartPNG(chartId: String, view: AnyView) {
        let snapshotView = view
            .padding(Theme.Spacing.lg)
            .frame(width: 800, height: 220)
            .background(Theme.Color.bg)
        let renderer = ImageRenderer(content: snapshotView)
        renderer.scale = 2.0
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "yuminai-\(chartId)-\(Int(Date().timeIntervalSince1970)).png"
        if panel.runModal() == .OK, let url = panel.url {
            try? png.write(to: url)
        }
    }

    // MARK: - ADR-063 Phase 4 — CSV export

    private enum CSVKind {
        case chatStats, commandStats, hourly, daily
    }

    @MainActor
    private func exportCSV(_ kind: CSVKind) {
        let csv: String
        let suggestedName: String
        switch kind {
        case .chatStats:
            csv = CSVExporter.exportChatStats(Array(snapshot.chatStats.values))
            suggestedName = "telegram-chat-stats.csv"
        case .commandStats:
            csv = CSVExporter.exportCommandStats(snapshot.commandStats)
            suggestedName = "telegram-command-stats.csv"
        case .hourly:
            csv = CSVExporter.exportHourlyBuckets(filteredHourly)
            suggestedName = "telegram-hourly-buckets.csv"
        case .daily:
            csv = CSVExporter.exportDailyBuckets(filteredDaily)
            suggestedName = "telegram-daily-buckets.csv"
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = suggestedName
        if panel.runModal() == .OK, let url = panel.url {
            try? csv.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
