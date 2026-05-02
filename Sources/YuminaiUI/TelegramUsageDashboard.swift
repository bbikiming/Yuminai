import SwiftUI
import Charts
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
public struct TelegramUsageDashboard: View {
    public let snapshot: TelegramUsageStore.Snapshot
    /// chat ID → workspace name (UI 라벨 보강용)
    public let chatIdToWorkspaceName: [String: String]
    public let onClose: () -> Void
    public let onClearStats: () -> Void

    public init(
        snapshot: TelegramUsageStore.Snapshot,
        chatIdToWorkspaceName: [String: String],
        onClose: @escaping () -> Void,
        onClearStats: @escaping () -> Void
    ) {
        self.snapshot = snapshot
        self.chatIdToWorkspaceName = chatIdToWorkspaceName
        self.onClose = onClose
        self.onClearStats = onClearStats
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    summaryCards
                    hourlyTurnsChart
                    hourlyCostChart
                    chatRankingChart
                    commandFrequencyChart
                    tokenBreakdownChart
                }
                .padding(Theme.Spacing.lg)
            }
            Divider()
            footer
        }
        .frame(width: 880, height: 700)
        .background(Theme.Color.bg)
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

    private var hourlyTurnsChart: some View {
        chartSection(title: "시간별 외부 turn 횟수", subtitle: "최근 7일, hourly bucket") {
            if snapshot.hourlyBuckets.isEmpty {
                emptyHint("Telegram 외부 turn 사용 시작하면 누적")
            } else {
                Chart(snapshot.hourlyBuckets) { bucket in
                    BarMark(
                        x: .value("Time", bucket.timestamp),
                        y: .value("Turns", bucket.turnCount)
                    )
                    .foregroundStyle(Color.blue.opacity(0.7))
                }
                .frame(height: 160)
            }
        }
    }

    // MARK: - 3. Hourly Cost (LineMark + AreaMark)

    private var hourlyCostChart: some View {
        chartSection(title: "시간별 누적 비용", subtitle: "외부 turn cost 추이") {
            if snapshot.hourlyBuckets.isEmpty {
                emptyHint("아직 cost 발생 없음")
            } else {
                Chart(snapshot.hourlyBuckets) { bucket in
                    LineMark(
                        x: .value("Time", bucket.timestamp),
                        y: .value("Cost", bucket.costUSD)
                    )
                    .foregroundStyle(Color.green)
                    .interpolationMethod(.catmullRom)
                    AreaMark(
                        x: .value("Time", bucket.timestamp),
                        y: .value("Cost", bucket.costUSD)
                    )
                    .foregroundStyle(LinearGradient(
                        colors: [Color.green.opacity(0.3), Color.green.opacity(0)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .interpolationMethod(.catmullRom)
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
            }
        }
    }

    // MARK: - 4. Chat Ranking (horizontal bar)

    private var chatRankingChart: some View {
        chartSection(title: "Chat별 사용량 ranking", subtitle: "turn count + cost 별") {
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
        chartSection(title: "명령 사용 빈도 (Top 10)", subtitle: "/decompose, /tasks, /rehearse 등") {
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
        chartSection(title: "토큰 사용 (input vs output)", subtitle: "시간별 stacked bar") {
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
