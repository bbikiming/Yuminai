import SwiftUI
import YuminaiCore

/// 우측 inspector — 컨텍스트 / 도구 호출 / 활성 설정을 한 화면.
///
/// ⌘⌥I로 토글. 좁은 윈도우에서는 자동 숨김 권장 (호출자 책임).
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
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                section("Active") {
                    KeyValueRow(key: "model", value: activeSettings.model.displayName)
                    KeyValueRow(key: "mode", value: activeSettings.permissionMode.displayName)
                    KeyValueRow(key: "effort", value: activeSettings.effortLevel.displayName)
                    if let budget = activeSettings.maxBudgetUSD {
                        KeyValueRow(key: "budget", value: String(format: "$%.2f", budget))
                    }
                    if let path = workspacePath {
                        KeyValueRow(key: "cwd", value: path, mono: true, lineLimit: 2)
                    }
                }

                section("Context") {
                    let ratio = usage.contextUsage(maxTokens: activeSettings.model.contextWindowTokens)
                    KeyValueRow(
                        key: "사용률",
                        value: String(format: "%.1f%%", ratio * 100)
                    )
                    KeyValueRow(
                        key: "윈도우",
                        value: activeSettings.model.contextWindowTokens.formattedShort
                    )
                    GaugeBar(ratio: ratio)
                }

                section("Tokens") {
                    KeyValueRow(key: "input", value: usage.inputTokens.formattedShort)
                    KeyValueRow(key: "output", value: usage.outputTokens.formattedShort)
                    KeyValueRow(
                        key: "cache R",
                        value: usage.cacheReadTokens.formattedShort,
                        valueColor: Theme.Color.success
                    )
                    KeyValueRow(
                        key: "cache W",
                        value: usage.cacheCreationTokens.formattedShort,
                        valueColor: Theme.Color.warning
                    )
                    KeyValueRow(key: "msg", value: "\(usage.messageCount)")
                }

                section("Cost") {
                    KeyValueRow(
                        key: "이 세션",
                        value: String(format: "$%.4f", usage.costUSD),
                        valueColor: Theme.Color.accent
                    )
                }

                if !recentTools.isEmpty {
                    section("Recent Tools") {
                        ForEach(Array(recentTools.suffix(8).enumerated()), id: \.offset) { _, tool in
                            Text(tool)
                                .font(Theme.Typography.toolbarLabel)
                                .foregroundStyle(Theme.Color.labelSecondary)
                        }
                    }
                }
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
        .chromeBackground()
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Theme.Color.dividerSubtle)
                .frame(width: 1)
        }
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.statLabel)
                .foregroundStyle(Theme.Color.labelTertiary)
                .textCase(.uppercase)
            VStack(alignment: .leading, spacing: 4) {
                content()
            }
        }
    }
}

struct KeyValueRow: View {
    let key: String
    let value: String
    var mono: Bool = false
    var lineLimit: Int = 1
    var valueColor: SwiftUI.Color = Theme.Color.label

    var body: some View {
        HStack(alignment: .top) {
            Text(key)
                .font(Theme.Typography.toolbarLabel)
                .foregroundStyle(Theme.Color.labelSecondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(mono ? Theme.Typography.codeBlock : Theme.Typography.toolbarLabel.monospacedDigit())
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
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.Color.dividerSubtle)
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: max(2, geo.size.width * ratio))
            }
        }
        .frame(height: 6)
    }

    private var color: SwiftUI.Color {
        switch ratio {
        case ..<0.5: return Theme.Color.success
        case ..<0.75: return Theme.Color.warning
        default: return Theme.Color.error
        }
    }
}
