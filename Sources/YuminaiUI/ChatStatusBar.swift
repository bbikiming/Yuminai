import SwiftUI
import YuminaiCore

/// 메시지 리스트와 Composer 사이 status row — 컨텍스트 게이지 + 메시지/토큰/비용.
public struct ChatStatusBar: View {
    public let usage: UsageStats
    public let contextWindow: Int

    public init(usage: UsageStats, contextWindow: Int, isStreaming: Bool = false) {
        self.usage = usage
        self.contextWindow = contextWindow
        _ = isStreaming
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            ContextGauge(usage: usage, contextWindow: contextWindow)

            FlatVDivider().frame(height: 14)

            statItem(label: "msg", value: "\(usage.messageCount)")
            statItem(label: "in", value: usage.inputTokens.formattedShort)
            statItem(label: "out", value: usage.outputTokens.formattedShort)
            if usage.cacheReadTokens > 0 {
                statItem(label: "cache", value: usage.cacheReadTokens.formattedShort, color: Theme.Color.success)
            }

            Spacer()

            costLabel
        }
        .padding(.horizontal, Theme.Layout.contentPaddingH)
        .frame(height: Theme.Layout.statusBarHeight)
        .background(Theme.Color.bg)
        .overlay(alignment: .top) {
            FlatHDivider()
        }
    }

    private func statItem(label: String, value: String, color: SwiftUI.Color = Theme.Color.text) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
            Text(value)
                .font(Theme.Typography.monoSmall)
                .foregroundStyle(color)
        }
    }

    private var costLabel: some View {
        HStack(spacing: 5) {
            Text("cost")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
            Text(String(format: "$%.4f", usage.costUSD))
                .font(Theme.Typography.monoSmall)
                .foregroundStyle(usage.costUSD > 0 ? Theme.Color.accent : Theme.Color.textSecondary)
        }
    }
}

/// 컨텍스트 게이지 (좌측 status item).
struct ContextGauge: View {
    let usage: UsageStats
    let contextWindow: Int

    var body: some View {
        let ratio = usage.contextUsage(maxTokens: contextWindow)
        HStack(spacing: 6) {
            Text("ctx")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.Color.borderSubtle)
                    Rectangle()
                        .fill(gaugeColor(ratio))
                        .frame(width: max(2, geo.size.width * ratio))
                }
            }
            .frame(width: 80, height: 4)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            Text(String(format: "%.1f%%", ratio * 100))
                .font(Theme.Typography.monoSmall)
                .foregroundStyle(gaugeColor(ratio))
        }
    }

    private func gaugeColor(_ ratio: Double) -> SwiftUI.Color {
        switch ratio {
        case ..<0.5: return Theme.Color.success
        case ..<0.75: return Theme.Color.warning
        default: return Theme.Color.danger
        }
    }
}

extension Int {
    var formattedShort: String {
        if self < 1_000 { return "\(self)" }
        if self < 1_000_000 {
            return String(format: "%.1fk", Double(self) / 1_000)
        }
        return String(format: "%.2fM", Double(self) / 1_000_000)
    }
}
