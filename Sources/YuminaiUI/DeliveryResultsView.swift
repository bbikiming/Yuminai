import SwiftUI
import YuminaiCore

/// Inspector "변경" 탭 하단에 표시되는 delivery (build/test/lint) 결과 영역 (ADR-029, M4).
///
/// **레이아웃**:
/// - 헤더: "Delivery" 라벨 + run buttons (build / test / lint) + 설정 톱니
/// - 본문: 최근 결과 리스트 (status icon + kind + 명령 + duration + attempt)
/// - 결과 클릭 → 펼쳐서 stdout/stderr 표시
public struct DeliveryResultsView: View {
    public let results: [DeliveryResult]
    public let isRunning: Bool
    public let config: DeliveryConfig
    public let onRunBuild: () -> Void
    public let onRunTest: () -> Void
    public let onRunLint: () -> Void
    public let onClear: () -> Void
    public let onConfigure: () -> Void

    @State private var expandedId: UUID?

    public init(
        results: [DeliveryResult],
        isRunning: Bool,
        config: DeliveryConfig,
        onRunBuild: @escaping () -> Void,
        onRunTest: @escaping () -> Void,
        onRunLint: @escaping () -> Void,
        onClear: @escaping () -> Void,
        onConfigure: @escaping () -> Void
    ) {
        self.results = results
        self.isRunning = isRunning
        self.config = config
        self.onRunBuild = onRunBuild
        self.onRunTest = onRunTest
        self.onRunLint = onRunLint
        self.onClear = onClear
        self.onConfigure = onConfigure
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            FlatHDivider()
            if results.isEmpty {
                emptyBody
            } else {
                resultsList
            }
        }
        .background(Theme.Color.bg)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Color.accent)
            Text("Delivery")
                .font(Theme.Typography.small.weight(.semibold))
                .foregroundStyle(Theme.Color.text)
            HelpHint(
                "워크스페이스의 build/test/lint 명령을 자동/수동으로 실행하고 결과를 보여줍니다. agent turn 완료 시 자동 실행이 켜져있으면 테스트 → 린트 순서로 돕니다. 실패하면 다음 사용자 메시지 앞에 결과가 자동 첨부됩니다 (max-attempts hard cap 적용).",
                title: "Delivery 자동화",
                placement: .top
            )
            if isRunning {
                ProgressView().controlSize(.mini).padding(.leading, 4)
            }
            Spacer()
            if !results.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .buttonStyle(.plain)
                .help("결과 비우기")
            }
            Button(action: onConfigure) {
                Image(systemName: "gear")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Delivery 자동화 설정")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)

        // run buttons
    }

    @ViewBuilder
    private var emptyBody: some View {
        VStack(spacing: 8) {
            if !config.hasAnyCommand {
                EmptyStateHint(
                    icon: "checkmark.shield",
                    title: "Delivery 명령이 설정되지 않았어요",
                    message: "톱니 아이콘을 눌러 build/test/lint 명령을 설정하면 agent turn 완료 시 자동 실행되거나 아래 버튼으로 수동 실행할 수 있어요.",
                    action: .init(label: "설정 열기", perform: onConfigure)
                )
            } else {
                EmptyStateHint(
                    icon: "play.circle",
                    title: "아직 실행된 결과가 없어요",
                    message: config.autoRunOnTurnComplete
                        ? "agent turn이 끝나면 자동으로 실행돼요."
                        : "‘테스트’/‘빌드’/‘린트’ 버튼으로 수동 실행하세요.",
                    action: nil
                )
                runButtonRow
                    .padding(.bottom, Theme.Spacing.sm)
            }
        }
    }

    private var resultsList: some View {
        VStack(spacing: 0) {
            runButtonRow
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
            FlatHDivider()
            ScrollView {
                VStack(spacing: 1) {
                    // 최근 것 위로
                    ForEach(results.reversed()) { r in
                        ResultRow(
                            result: r,
                            expanded: expandedId == r.id,
                            onToggle: {
                                expandedId = (expandedId == r.id) ? nil : r.id
                            }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var runButtonRow: some View {
        HStack(spacing: 6) {
            runButton(label: "테스트", icon: DeliveryResult.Kind.test.icon,
                      enabled: !(config.testCommand?.isEmpty ?? true), action: onRunTest)
            runButton(label: "빌드", icon: DeliveryResult.Kind.build.icon,
                      enabled: !(config.buildCommand?.isEmpty ?? true), action: onRunBuild)
            runButton(label: "린트", icon: DeliveryResult.Kind.lint.icon,
                      enabled: !(config.lintCommand?.isEmpty ?? true), action: onRunLint)
            Spacer()
        }
    }

    private func runButton(label: String, icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10))
                Text(label).font(Theme.Typography.small)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(enabled ? Theme.Color.surface : Theme.Color.bg)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .stroke(enabled ? Theme.Color.borderSubtle : Theme.Color.borderSubtle.opacity(0.5), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .foregroundStyle(enabled ? Theme.Color.text : Theme.Color.textTertiary)
        }
        .buttonStyle(.plain)
        .disabled(!enabled || isRunning)
        .help(enabled ? "\(label) 실행" : "\(label) 명령이 설정되지 않았어요")
    }
}

private struct ResultRow: View {
    let result: DeliveryResult
    let expanded: Bool
    let onToggle: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 11))
                        .foregroundStyle(statusColor)
                        .frame(width: 14)
                    Text(result.kind.label)
                        .font(Theme.Typography.small.weight(.medium))
                        .foregroundStyle(Theme.Color.text)
                        .frame(width: 36, alignment: .leading)
                    Text(result.command)
                        .font(Theme.Typography.monoSmall)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(durationLabel)
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                    if result.attempt > 1 {
                        Text("#\(result.attempt)")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(.orange)
                    }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.Color.textTertiary)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 5)
                .background(hovering ? Theme.Color.surfaceHi : .clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }

            if expanded {
                expandedDetail
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Color.surface)
            }
        }
    }

    private var statusIcon: String {
        if result.timedOut { return "clock.badge.xmark" }
        return result.success ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private var statusColor: SwiftUI.Color {
        if result.timedOut { return .orange }
        return result.success ? .green : .red
    }

    private var durationLabel: String {
        if result.durationMs >= 1000 {
            return String(format: "%.1fs", Double(result.durationMs) / 1000)
        }
        return "\(result.durationMs)ms"
    }

    @ViewBuilder
    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: 6) {
            if result.timedOut {
                InlineHint(
                    "타임아웃 — 워크스페이스 Delivery 설정에서 timeout 시간을 늘려보세요.",
                    icon: "clock.badge.xmark",
                    kind: .warning
                )
            }
            if !result.stderr.isEmpty {
                Text("stderr")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                ScrollView {
                    Text(result.stderr)
                        .font(Theme.Typography.monoSmall)
                        .foregroundStyle(Theme.Color.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 160)
            }
            if !result.stdout.isEmpty {
                Text("stdout")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                ScrollView {
                    Text(result.stdout)
                        .font(Theme.Typography.monoSmall)
                        .foregroundStyle(Theme.Color.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 160)
            }
        }
    }
}
