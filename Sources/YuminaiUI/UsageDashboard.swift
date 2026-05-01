import SwiftUI
import YuminaiCore

/// 사용량 대시보드 — flat 그리드.
public struct UsageDashboard: View {
    public let currentSessionUsage: UsageStats
    public let allTimeUsage: UsageStats
    public let activeModel: ClaudeModel
    public let onClose: () -> Void

    public init(
        currentSessionUsage: UsageStats,
        allTimeUsage: UsageStats,
        activeModel: ClaudeModel,
        onClose: @escaping () -> Void
    ) {
        self.currentSessionUsage = currentSessionUsage
        self.allTimeUsage = allTimeUsage
        self.activeModel = activeModel
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            header

            FlatSection("current session") {
                UsageGrid(usage: currentSessionUsage, model: activeModel)
            }

            FlatSection("all time (since launch)") {
                UsageGrid(usage: allTimeUsage, model: activeModel)
            }

            FlatSection("model pricing", footer: "Anthropic 공식 가격 기준 (대략값)") {
                PricingGrid(model: activeModel)
            }

            Spacer(minLength: Theme.Spacing.md)

            HStack {
                Spacer()
                FlatButton("close", variant: .secondary, action: onClose)
                    .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: 660, height: 580)
        .background(Theme.Color.bg)
    }

    private var header: some View {
        HStack {
            Text("Usage Dashboard")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Color.text)
            Spacer()
            HStack(spacing: 4) {
                Text("model")
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
                StatBox(label: "messages", value: "\(usage.messageCount)")
                StatBox(label: "input", value: usage.inputTokens.formattedShort)
                StatBox(label: "output", value: usage.outputTokens.formattedShort)
                StatBox(label: "cache R", value: usage.cacheReadTokens.formattedShort, color: Theme.Color.success)
                StatBox(label: "cache W", value: usage.cacheCreationTokens.formattedShort, color: Theme.Color.warning)
                StatBox(label: "cost", value: String(format: "$%.4f", usage.costUSD), color: Theme.Color.accent)
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
                Text("context")
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
            label("input", String(format: "$%.2f / 1M", model.inputPricePerMillion))
            label("output", String(format: "$%.2f / 1M", model.outputPricePerMillion))
            label("context", model.contextWindowTokens.formattedShort)
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
