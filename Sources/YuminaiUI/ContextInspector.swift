import SwiftUI
import YuminaiCore

/// 우측 inspector. flat — 박스 없이 섹션 구분.
public struct ContextInspector: View {
    public let usage: UsageStats
    public let activeSettings: SessionSettings
    public let workspacePath: String?
    public let recentTools: [String]

    public init(
        usage: UsageStats,
        activeSettings: SessionSettings,
        workspacePath: String?,
        recentTools: [String] = []
    ) {
        self.usage = usage
        self.activeSettings = activeSettings
        self.workspacePath = workspacePath
        self.recentTools = recentTools
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                section("active") {
                    KeyValueRow(key: "model", value: activeSettings.model.rawValue)
                    KeyValueRow(key: "mode", value: activeSettings.permissionMode.rawValue)
                    KeyValueRow(key: "effort", value: activeSettings.effortLevel.rawValue)
                    if let budget = activeSettings.maxBudgetUSD {
                        KeyValueRow(key: "budget", value: String(format: "$%.2f", budget))
                    }
                    if let path = workspacePath {
                        KeyValueRow(key: "cwd", value: path, lineLimit: 2)
                    }
                }

                section("context") {
                    let ratio = usage.contextUsage(maxTokens: activeSettings.model.contextWindowTokens)
                    KeyValueRow(key: "used", value: String(format: "%.1f%%", ratio * 100))
                    KeyValueRow(key: "window", value: activeSettings.model.contextWindowTokens.formattedShort)
                    GaugeBar(ratio: ratio).padding(.top, 4)
                }

                section("tokens") {
                    KeyValueRow(key: "input", value: usage.inputTokens.formattedShort)
                    KeyValueRow(key: "output", value: usage.outputTokens.formattedShort)
                    KeyValueRow(key: "cache R", value: usage.cacheReadTokens.formattedShort, valueColor: Theme.Color.success)
                    KeyValueRow(key: "cache W", value: usage.cacheCreationTokens.formattedShort, valueColor: Theme.Color.warning)
                    KeyValueRow(key: "msg", value: "\(usage.messageCount)")
                }

                section("cost") {
                    KeyValueRow(
                        key: "session",
                        value: String(format: "$%.4f", usage.costUSD),
                        valueColor: Theme.Color.accent
                    )
                }

                if !recentTools.isEmpty {
                    section("recent tools") {
                        ForEach(Array(recentTools.suffix(8).enumerated()), id: \.offset) { _, tool in
                            Text(tool)
                                .font(Theme.Typography.small)
                                .foregroundStyle(Theme.Color.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: Theme.Layout.inspectorWidth)
        .flatChrome(borders: [.leading])
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
                .textCase(.uppercase)
                .tracking(0.5)
            VStack(alignment: .leading, spacing: 2) {
                content()
            }
        }
    }
}

struct KeyValueRow: View {
    let key: String
    let value: String
    var lineLimit: Int = 1
    var valueColor: SwiftUI.Color = Theme.Color.text

    var body: some View {
        HStack(alignment: .top) {
            Text(key)
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(Theme.Typography.label.monospacedDigit())
                .foregroundStyle(valueColor)
                .lineLimit(lineLimit)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct GaugeBar: View {
    let ratio: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.Color.borderSubtle)
                Rectangle()
                    .fill(color)
                    .frame(width: max(2, geo.size.width * ratio))
            }
        }
        .frame(height: 4)
    }

    private var color: SwiftUI.Color {
        switch ratio {
        case ..<0.5: return Theme.Color.success
        case ..<0.75: return Theme.Color.warning
        default: return Theme.Color.error
        }
    }
}
