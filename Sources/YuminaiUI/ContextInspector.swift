import SwiftUI
import YuminaiCore

/// 우측 inspector panel — sections 형식 (no card boxes).
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
                    KVRow(key: "model", value: activeSettings.model.rawValue)
                    KVRow(key: "mode", value: activeSettings.permissionMode.rawValue)
                    KVRow(key: "effort", value: activeSettings.effortLevel.rawValue)
                    if let budget = activeSettings.maxBudgetUSD {
                        KVRow(key: "budget", value: String(format: "$%.2f", budget))
                    }
                    if let path = workspacePath {
                        KVRow(key: "cwd", value: path, lineLimit: 2, mono: true)
                    }
                }

                section("context") {
                    let ratio = usage.contextUsage(maxTokens: activeSettings.model.contextWindowTokens)
                    KVRow(key: "used", value: String(format: "%.1f%%", ratio * 100))
                    KVRow(key: "window", value: activeSettings.model.contextWindowTokens.formattedShort)
                    InspectorGauge(ratio: ratio).padding(.top, 6)
                }

                section("tokens") {
                    KVRow(key: "input", value: usage.inputTokens.formattedShort)
                    KVRow(key: "output", value: usage.outputTokens.formattedShort)
                    KVRow(key: "cache R", value: usage.cacheReadTokens.formattedShort, valueColor: Theme.Color.success)
                    KVRow(key: "cache W", value: usage.cacheCreationTokens.formattedShort, valueColor: Theme.Color.warning)
                    KVRow(key: "msg", value: "\(usage.messageCount)")
                }

                section("cost") {
                    KVRow(
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
        .background(Theme.Color.bg)
        .overlay(alignment: .leading) {
            FlatVDivider()
        }
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
                .textCase(.uppercase)
                .tracking(0.6)
            VStack(alignment: .leading, spacing: 3) {
                content()
            }
        }
    }
}

struct KVRow: View {
    let key: String
    let value: String
    var lineLimit: Int = 1
    var mono: Bool = false
    var valueColor: SwiftUI.Color = Theme.Color.text

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Text(key)
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(mono ? Theme.Typography.codeBlock : Theme.Typography.monoSmall)
                .foregroundStyle(valueColor)
                .lineLimit(lineLimit)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct InspectorGauge: View {
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
        .frame(height: 5)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }
    private var color: SwiftUI.Color {
        switch ratio {
        case ..<0.5: return Theme.Color.success
        case ..<0.75: return Theme.Color.warning
        default: return Theme.Color.danger
        }
    }
}
