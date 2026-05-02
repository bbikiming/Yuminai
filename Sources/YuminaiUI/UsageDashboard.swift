import SwiftUI
import YuminaiCore

/// 사용량 대시보드 — flat 그리드.
public struct UsageDashboard: View {
    public let currentSessionUsage: UsageStats
    public let allTimeUsage: UsageStats
    public let activeModel: ClaudeModel
    /// **ADR-055 #6** — 5 buckets cost snapshot (격리 호출 비용 분리 가시화)
    public let costSnapshot: CostTracker.Snapshot
    /// **ADR-055 #6** — 외부 turn cost (Telegram에서 시작된 turn 누적)
    public let externalTurnCount: Int
    public let externalTurnCostUSD: Double
    /// **ADR-059 Phase 1** — ChildProcess cache hit 누적 (Anthropic prompt cache 효과 측정)
    public let cumulativeCacheHitRatio: Double
    public let totalCacheReadTokens: Int
    public let totalCacheCreationTokens: Int
    public let onClose: () -> Void

    public init(
        currentSessionUsage: UsageStats,
        allTimeUsage: UsageStats,
        activeModel: ClaudeModel,
        costSnapshot: CostTracker.Snapshot = CostTracker.Snapshot(main: 0, decomposition: 0, rehearsal: 0, routing: 0, parallel: 0),
        externalTurnCount: Int = 0,
        externalTurnCostUSD: Double = 0,
        cumulativeCacheHitRatio: Double = 0,
        totalCacheReadTokens: Int = 0,
        totalCacheCreationTokens: Int = 0,
        onClose: @escaping () -> Void
    ) {
        self.currentSessionUsage = currentSessionUsage
        self.allTimeUsage = allTimeUsage
        self.activeModel = activeModel
        self.costSnapshot = costSnapshot
        self.externalTurnCount = externalTurnCount
        self.externalTurnCostUSD = externalTurnCostUSD
        self.cumulativeCacheHitRatio = cumulativeCacheHitRatio
        self.totalCacheReadTokens = totalCacheReadTokens
        self.totalCacheCreationTokens = totalCacheCreationTokens
        self.onClose = onClose
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header

                FlatSection("이번 세션") {
                    UsageGrid(usage: currentSessionUsage, model: activeModel)
                }

                // ADR-055 #6 — 5 buckets cost histogram
                FlatSection("Cost 분리 (격리 호출별 — ADR-053/054/055)") {
                    CostBucketsHistogram(snapshot: costSnapshot)
                }

                // ADR-059 Phase 1 — Cache hit dashboard
                if totalCacheReadTokens > 0 || totalCacheCreationTokens > 0 {
                    FlatSection("Cache 효과 (ADR-055 #1 + ADR-058 Phase 1)") {
                        CacheHitDashboard(
                            ratio: cumulativeCacheHitRatio,
                            readTokens: totalCacheReadTokens,
                            creationTokens: totalCacheCreationTokens
                        )
                    }
                }

                if externalTurnCount > 0 {
                    FlatSection("외부 turn (Telegram)") {
                        ExternalTurnSummary(count: externalTurnCount, totalCostUSD: externalTurnCostUSD)
                    }
                }

                FlatSection("앱 실행 후 누적") {
                    UsageGrid(usage: allTimeUsage, model: activeModel)
                }

                FlatSection("모델 가격", footer: "Anthropic 공식 가격 기준 (대략값)") {
                    PricingGrid(model: activeModel)
                }

                Spacer(minLength: Theme.Spacing.md)

                HStack {
                    Spacer()
                    FlatButton("닫기", variant: .secondary, action: onClose)
                        .keyboardShortcut(.escape, modifiers: [])
                }
            }
            .padding(Theme.Spacing.xxl)
        }
        .frame(width: 660, height: 700)
        .background(Theme.Color.bg)
    }

    private var header: some View {
        HStack {
            Text("사용량")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Color.text)
            Spacer()
            HStack(spacing: 4) {
                Text("모델")
                    .foregroundStyle(Theme.Color.textTertiary)
                Text("·")
                    .foregroundStyle(Theme.Color.textTertiary)
                Text(activeModel.rawValue)
                    .foregroundStyle(Theme.Color.text)
            }
            .font(Theme.Typography.monoSmall)
        }
    }
}

struct UsageGrid: View {
    let usage: UsageStats
    let model: ClaudeModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.xl) {
                StatBox(label: "메시지", value: "\(usage.messageCount)")
                StatBox(label: "입력", value: usage.inputTokens.formattedShort)
                StatBox(label: "출력", value: usage.outputTokens.formattedShort)
                StatBox(label: "캐시 R", value: usage.cacheReadTokens.formattedShort, color: Theme.Color.success)
                StatBox(label: "캐시 W", value: usage.cacheCreationTokens.formattedShort, color: Theme.Color.warning)
                StatBox(label: "비용", value: String(format: "$%.4f", usage.costUSD), color: Theme.Color.accent)
            }
            ContextRow(usage: usage, model: model)
        }
    }
}

struct StatBox: View {
    let label: String
    let value: String
    var color: SwiftUI.Color = Theme.Color.text

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
                .textCase(.uppercase)
                .tracking(0.6)
            Text(value)
                .font(Theme.Typography.monoStat)
                .foregroundStyle(color)
        }
        .frame(minWidth: 64, alignment: .leading)
    }
}

struct ContextRow: View {
    let usage: UsageStats
    let model: ClaudeModel

    var body: some View {
        let ratio = usage.contextUsage(maxTokens: model.contextWindowTokens)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("컨텍스트")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Spacer()
                Text(String(format: "%.1f%% / %@", ratio * 100, model.contextWindowTokens.formattedShort))
                    .font(Theme.Typography.monoSmall)
                    .foregroundStyle(Theme.Color.text)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.Color.borderSubtle)
                    Rectangle()
                        .fill(barColor(ratio))
                        .frame(width: max(2, geo.size.width * ratio))
                }
            }
            .frame(height: 6)
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }

    private func barColor(_ ratio: Double) -> SwiftUI.Color {
        switch ratio {
        case ..<0.5: return Theme.Color.success
        case ..<0.75: return Theme.Color.warning
        default: return Theme.Color.danger
        }
    }
}

struct PricingGrid: View {
    let model: ClaudeModel

    var body: some View {
        HStack(spacing: Theme.Spacing.xxl) {
            label("입력 / 1M", String(format: "$%.2f", model.inputPricePerMillion))
            label("출력 / 1M", String(format: "$%.2f", model.outputPricePerMillion))
            label("컨텍스트", model.contextWindowTokens.formattedShort)
            Spacer()
        }
    }

    private func label(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(key)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
                .textCase(.uppercase)
                .tracking(0.6)
            Text(value)
                .font(Theme.Typography.monoSmall)
                .foregroundStyle(Theme.Color.text)
        }
    }
}

// MARK: - ADR-055 #6 — Cost buckets histogram

/// 5 buckets cost 분리 시각화. CostTracker.Snapshot 입력.
struct CostBucketsHistogram: View {
    let snapshot: CostTracker.Snapshot

    private var maxValue: Double {
        max(snapshot.main, snapshot.decomposition, snapshot.rehearsal, snapshot.parallel, snapshot.routing, 0.0001)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            bucketRow(label: "Main", value: snapshot.main, color: .blue, hint: "사용자 conversation")
            bucketRow(label: "Decomposition", value: snapshot.decomposition, color: .indigo, hint: "/decompose 격리 호출")
            bucketRow(label: "Rehearsal", value: snapshot.rehearsal, color: .orange, hint: "다른 모델로 재실행")
            bucketRow(label: "Parallel", value: snapshot.parallel, color: .purple, hint: "병렬 두 번째 pane")
            bucketRow(label: "Routing", value: snapshot.routing, color: .gray, hint: "LLM-based 분류 (현재 0)")
            Divider().padding(.vertical, 2)
            HStack {
                Text("Total")
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.Color.text)
                Spacer()
                Text(String(format: "$%.4f", snapshot.total))
                    .font(Theme.Typography.monoSmall.weight(.semibold))
                    .foregroundStyle(Theme.Color.accent)
            }
        }
    }

    private func bucketRow(label: String, value: Double, color: Color, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(label)
                    .font(Theme.Typography.small.weight(.medium))
                    .foregroundStyle(Theme.Color.text)
                Text(hint)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                Spacer()
                Text(String(format: "$%.4f", value))
                    .font(Theme.Typography.monoSmall)
                    .foregroundStyle(Theme.Color.text)
            }
            // 가로 bar (최대값 대비 비율)
            GeometryReader { geo in
                let width = geo.size.width * CGFloat(value / maxValue)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.Color.surface)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.6))
                        .frame(width: max(width, 2))
                }
            }
            .frame(height: 6)
        }
    }
}

/// **ADR-059 Phase 1** — Anthropic prompt cache 효과 dashboard.
struct CacheHitDashboard: View {
    let ratio: Double
    let readTokens: Int
    let creationTokens: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                statBlock(label: "Hit Ratio", value: "\(Int(ratio * 100))%", color: ratio > 0.5 ? .green : (ratio > 0.2 ? .yellow : .orange))
                statBlock(label: "Read Tokens", value: readTokens.formattedShort, color: .blue)
                statBlock(label: "Creation Tokens", value: creationTokens.formattedShort, color: .indigo)
                Spacer()
            }
            // Visual bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.Color.surface)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(
                            colors: [.green.opacity(0.6), .blue.opacity(0.6)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 8)
            // Hint
            Text(ratio > 0.5 ? "✓ 효율적: ProjectProfile 안정화 효과" : (ratio > 0.2 ? "보통: 더 많은 격리 호출에서 cache hit 기대" : "낮음: 첫 호출 또는 5분 TTL 만료 후"))
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
        }
    }

    private func statBlock(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
                .textCase(.uppercase)
                .tracking(0.6)
            Text(value)
                .font(Theme.Typography.title)
                .foregroundStyle(color)
        }
    }
}

/// **ADR-055 #6** — 외부 turn 카운트 + 누적 cost 요약 view.
struct ExternalTurnSummary: View {
    let count: Int
    let totalCostUSD: Double

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("외부 turn 횟수")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .textCase(.uppercase)
                Text("\(count)")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("외부 turn 누적 비용")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .textCase(.uppercase)
                Text(String(format: "$%.4f", totalCostUSD))
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.accent)
            }
            Spacer()
        }
    }
}
