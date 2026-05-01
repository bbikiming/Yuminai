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

            FlatSection("이번 세션") {
                UsageGrid(usage: currentSessionUsage, model: activeModel)
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
        .frame(width: 660, height: 580)
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
