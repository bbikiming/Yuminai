import SwiftUI
import YuminaiCore

/// 입력창 바로 위 status bar. 컨텍스트 사용량, 메시지 수, 비용을 inline 표시.
public struct ChatStatusBar: View {
    public let usage: UsageStats
    public let contextWindow: Int
    public let isStreaming: Bool

    public init(usage: UsageStats, contextWindow: Int, isStreaming: Bool) {
        self.usage = usage
        self.contextWindow = contextWindow
        self.isStreaming = isStreaming
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            ContextGauge(usage: usage, contextWindow: contextWindow)

            statItem(
                label: "msg",
                value: "\(usage.messageCount)"
            )
            statItem(
                label: "in",
                value: usage.inputTokens.formattedShort
            )
            statItem(
                label: "out",
                value: usage.outputTokens.formattedShort
            )
            if usage.cacheReadTokens > 0 {
                statItem(
                    label: "cache",
                    value: usage.cacheReadTokens.formattedShort,
                    color: Theme.Color.success
                )
            }

            Spacer()

            costBadge
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 6)
        .chromeBackground()
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.Color.dividerSubtle)
                .frame(height: 1)
        }
    }

    private func statItem(label: String, value: String, color: SwiftUI.Color = Theme.Color.label) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(Theme.Typography.statLabel)
                .foregroundStyle(Theme.Color.labelTertiary)
            Text(value)
                .font(Theme.Typography.toolbarLabel)
                .foregroundStyle(color)
        }
    }

    private var costBadge: some View {
        HStack(spacing: 4) {
            Text("$")
                .font(Theme.Typography.statLabel)
                .foregroundStyle(Theme.Color.labelTertiary)
            Text(String(format: "%.4f", usage.costUSD))
                .font(Theme.Typography.toolbarLabel.monospacedDigit())
                .foregroundStyle(usage.costUSD > 0 ? Theme.Color.accent : Theme.Color.labelSecondary)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 3)
        .background(
            usage.costUSD > 0 ? Theme.Color.accentMuted : Theme.Color.surface,
            in: Capsule()
        )
    }
}

/// 컨텍스트 사용 게이지. 색상은 사용률에 따라 변화.
struct ContextGauge: View {
    let usage: UsageStats
    let contextWindow: Int

    var body: some View {
        let ratio = usage.contextUsage(maxTokens: contextWindow)
        let percentText = String(format: "%.1f%%", ratio * 100)

        HStack(spacing: 6) {
            Text("ctx")
                .font(Theme.Typography.statLabel)
                .foregroundStyle(Theme.Color.labelTertiary)

            // 진행 막대
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.Color.dividerSubtle)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(gaugeColor(ratio))
                        .frame(width: max(2, geo.size.width * ratio))
                }
            }
            .frame(width: 90, height: 6)

            Text(percentText)
                .font(Theme.Typography.toolbarLabel.monospacedDigit())
                .foregroundStyle(gaugeColor(ratio))
        }
    }

    private func gaugeColor(_ ratio: Double) -> SwiftUI.Color {
        switch ratio {
        case ..<0.5: return Theme.Color.success
        case ..<0.75: return Theme.Color.warning
        default: return Theme.Color.error
        }
    }
}

extension Int {
    /// 토큰 수를 짧게 표기 (1234 → "1.2k", 1_234_567 → "1.2M").
    var formattedShort: String {
        if self < 1_000 { return "\(self)" }
        if self < 1_000_000 {
            let k = Double(self) / 1_000
            return String(format: "%.1fk", k)
        }
        let m = Double(self) / 1_000_000
        return String(format: "%.2fM", m)
    }
}
