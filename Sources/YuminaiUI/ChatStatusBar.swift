import SwiftUI
import YuminaiCore

/// 메시지 리스트와 Composer 사이 status row — 컨텍스트 게이지 + 메시지/토큰/비용.
/// **ADR-072 Phase 1** — 작은 화면에서 cost label이 잘리지 않도록 layoutMode 기반 반응형.
public struct ChatStatusBar: View {
    public let usage: UsageStats
    public let contextWindow: Int
    /// **ADR-072 Phase 1** — 반응형 padding/spacing 결정용.
    public let layoutMode: LayoutMode

    public init(
        usage: UsageStats,
        contextWindow: Int,
        isStreaming: Bool = false,
        layoutMode: LayoutMode = .regular
    ) {
        self.usage = usage
        self.contextWindow = contextWindow
        self.layoutMode = layoutMode
        _ = isStreaming
    }

    /// 작은 화면에서는 일부 stat 숨김 (cost는 항상 보장).
    private var showsAllStats: Bool {
        switch layoutMode {
        case .tiny, .compact: return false
        case .medium, .regular, .wide: return true
        }
    }

    private var spacing: CGFloat {
        switch layoutMode {
        case .tiny: return Theme.Spacing.sm
        case .compact: return Theme.Spacing.md
        case .medium, .regular, .wide: return Theme.Spacing.lg
        }
    }

    public var body: some View {
        HStack(spacing: spacing) {
            ContextGauge(usage: usage, contextWindow: contextWindow)
                // ADR-072 Phase 1 — tiny 모드에서는 컨텍스트 게이지만으로도 충분
                .layoutPriority(1)

            if showsAllStats {
                FlatVDivider().frame(height: 14)

                statItem(label: "msg", value: "\(usage.messageCount)")
                statItem(label: "in", value: usage.inputTokens.formattedShort)
                statItem(label: "out", value: usage.outputTokens.formattedShort)
                if usage.cacheReadTokens > 0 {
                    statItem(label: "cache", value: usage.cacheReadTokens.formattedShort, color: Theme.Color.success)
                }
            }

            Spacer(minLength: Theme.Spacing.sm)

            // ADR-072 Phase 1 — cost label은 잘리지 않게 layoutPriority + fixedSize
            costLabel
                .layoutPriority(2)
                .fixedSize()
        }
        .padding(.horizontal, Theme.Layout.contentPaddingH(for: layoutMode))
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
