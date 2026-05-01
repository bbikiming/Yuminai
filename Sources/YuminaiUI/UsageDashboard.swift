import SwiftUI
import YuminaiCore

/// 사용량 대시보드 — 현재 세션 + 누적. ⌘D로 호출.
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
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            header

            UsageSection(
                title: "현재 세션",
                usage: currentSessionUsage,
                model: activeModel
            )

            Divider()

            UsageSection(
                title: "앱 시작 후 누적",
                usage: allTimeUsage,
                model: activeModel
            )

            Divider()

            ModelPricingFooter(model: activeModel)

            Spacer(minLength: Theme.Spacing.lg)

            HStack {
                Spacer()
                Button("닫기", action: onClose)
                    .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 640, height: 540)
    }

    private var header: some View {
        HStack {
            Image(systemName: "chart.bar.xaxis")
                .font(.title2)
                .foregroundStyle(Theme.Color.accent)
            Text("사용량 대시보드")
                .font(.title2).bold()
            Spacer()
            Text("model · \(activeModel.displayName)")
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Color.labelSecondary)
        }
    }
}

struct UsageSection: View {
    let title: String
    let usage: UsageStats
    let model: ClaudeModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(title)
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Color.labelSecondary)

            HStack(spacing: Theme.Spacing.lg) {
                StatBox(label: "메시지", value: "\(usage.messageCount)")
                StatBox(label: "Input", value: usage.inputTokens.formattedShort)
                StatBox(label: "Output", value: usage.outputTokens.formattedShort)
                StatBox(label: "Cache R", value: usage.cacheReadTokens.formattedShort, color: Theme.Color.success)
                StatBox(label: "Cache W", value: usage.cacheCreationTokens.formattedShort, color: Theme.Color.warning)
                StatBox(
                    label: "비용",
                    value: String(format: "$%.4f", usage.costUSD),
                    color: Theme.Color.accent
                )
            }

            ContextRow(usage: usage, model: model)
        }
    }
}

struct StatBox: View {
    let label: String
    let value: String
    var color: SwiftUI.Color = Theme.Color.label

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.Typography.statLabel)
                .foregroundStyle(Theme.Color.labelTertiary)
            Text(value)
                .font(Theme.Typography.statBig)
                .foregroundStyle(color)
        }
        .frame(minWidth: 70, alignment: .leading)
    }
}

struct ContextRow: View {
    let usage: UsageStats
    let model: ClaudeModel

    var body: some View {
        let ratio = usage.contextUsage(maxTokens: model.contextWindowTokens)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("컨텍스트 사용률")
                    .font(Theme.Typography.statLabel)
                    .foregroundStyle(Theme.Color.labelTertiary)
                Spacer()
                Text(String(format: "%.1f%% / %@",
                            ratio * 100,
                            model.contextWindowTokens.formattedShort))
                    .font(Theme.Typography.toolbarLabel.monospacedDigit())
                    .foregroundStyle(Theme.Color.label)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.Color.dividerSubtle)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor(ratio))
                        .frame(width: max(2, geo.size.width * ratio))
                }
            }
            .frame(height: 8)
        }
    }

    private func barColor(_ ratio: Double) -> SwiftUI.Color {
        switch ratio {
        case ..<0.5: return Theme.Color.success
        case ..<0.75: return Theme.Color.warning
        default: return Theme.Color.error
        }
    }
}

struct ModelPricingFooter: View {
    let model: ClaudeModel

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            label("input", String(format: "$%.2f / 1M", model.inputPricePerMillion))
            label("output", String(format: "$%.2f / 1M", model.outputPricePerMillion))
            label("context", model.contextWindowTokens.formattedShort)
            Spacer()
            Text("실제 가격은 Anthropic 공식 가격 기준")
                .font(.caption2)
                .foregroundStyle(Theme.Color.labelTertiary)
        }
    }

    private func label(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key)
                .font(Theme.Typography.statLabel)
                .foregroundStyle(Theme.Color.labelTertiary)
            Text(value)
                .font(Theme.Typography.toolbarLabel.monospacedDigit())
                .foregroundStyle(Theme.Color.label)
        }
    }
}
