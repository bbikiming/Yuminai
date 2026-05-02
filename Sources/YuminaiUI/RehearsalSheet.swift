import SwiftUI
import YuminaiCore

/// Walk-through Rehearsal sheet (ADR-052).
///
/// 완료된 task를 다른 모델로 재실행하여 결과 비교.
///
/// **출처/근거**:
/// - Promptfoo provider matrix UI (https://www.promptfoo.dev/docs/configuration/guide/)
/// - Braintrust Eval comparison (https://www.braintrust.dev/docs/guides/evals)
/// - LangSmith Comparative experiments (`/datasets/comparative/{id}`)
/// - Postman "Save Response" + Environment switcher
///
/// **UX 안전장치** (조사 권고):
/// - 배경 yellow tint (Xcode debug overlay 패턴)
/// - 상단 banner "REHEARSAL · …" 닫기 불가
/// - "Promote to main" 명시적 액션 (rehearsal과 production 혼동 방지)
public struct RehearsalSheet: View {
    public let task: HarnessTask
    public let allEntries: [ConversationEntry]
    public let rehearsals: [RehearsalRun]
    public let onLaunch: (AgentKind) -> Void
    public let onClose: () -> Void

    @State private var selectedReplayAgent: AgentKind = .claude
    @State private var selectedRunId: UUID?
    @State private var viewMode: ViewMode = .sideBySide

    enum ViewMode: String, CaseIterable, Identifiable {
        case sideBySide = "원본 vs 리허설"
        case diff = "Diff (line-by-line)"
        var id: String { rawValue }
    }

    public init(
        task: HarnessTask,
        allEntries: [ConversationEntry],
        rehearsals: [RehearsalRun],
        onLaunch: @escaping (AgentKind) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.task = task
        self.allEntries = allEntries
        self.rehearsals = rehearsals
        self.onLaunch = onLaunch
        self.onClose = onClose
        // Default replay = task가 사용한 것과 다른 모델
        let original = task.assignedAgent ?? .claude
        let other: AgentKind = (original == .claude) ? .codex : .claude
        _selectedReplayAgent = State(initialValue: other)
    }

    public var body: some View {
        VStack(spacing: 0) {
            rehearsalBanner
            header
            Divider()
            HStack(spacing: 0) {
                runsListPane.frame(width: 240)
                Divider()
                detailPane.frame(maxWidth: .infinity)
            }
            Divider()
            footer
        }
        .frame(width: 880, height: 600)
        .background(Theme.Color.bg)
        // Yellow tint background overlay (Xcode debug pattern)
        .overlay(
            Color.yellow.opacity(0.04)
                .allowsHitTesting(false)
        )
    }

    // MARK: - Banner

    private var rehearsalBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.bubble.fill")
                .foregroundStyle(.white)
            Text("REHEARSAL · 원본: \(task.assignedAgent?.shortLabel ?? "?") · 재실행: \(selectedReplayAgent.shortLabel)")
                .font(Theme.Typography.small.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
            Text("결과는 production conversation에 자동 반영되지 않습니다")
                .font(Theme.Typography.micro)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, 8)
        .background(Color.orange)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Color.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("[Rehearsal] \(task.title)")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
                Text("다른 모델로 같은 task를 재실행해 비교 — 비용은 별도 발생")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
            launchControls
        }
        .padding(Theme.Spacing.lg)
    }

    private var launchControls: some View {
        HStack(spacing: 8) {
            Picker("재실행 모델", selection: $selectedReplayAgent) {
                ForEach(AgentKind.allCases, id: \.self) { kind in
                    Text(kind.shortLabel.capitalized).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            FlatButton("리허설 실행", icon: "play.fill", variant: .primary) {
                onLaunch(selectedReplayAgent)
            }
        }
    }

    // MARK: - Runs list

    private var runsListPane: some View {
        VStack(spacing: 0) {
            Text("이전 리허설 (\(rehearsals.count))")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.sm)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if rehearsals.isEmpty {
                        EmptyStateHint(
                            icon: "tray",
                            title: "아직 리허설 결과가 없어요",
                            message: "위 ‘리허설 실행’ 버튼을 눌러 다른 모델로 재시도해보세요."
                        )
                        .padding(Theme.Spacing.md)
                    } else {
                        ForEach(rehearsals, id: \.id) { run in
                            RunRowView(
                                run: run,
                                selected: run.id == selectedRunId,
                                onTap: { selectedRunId = run.id }
                            )
                        }
                    }
                }
            }
        }
        .background(Theme.Color.surface)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailPane: some View {
        VStack(spacing: 0) {
            // ADR-054 — view mode picker (only show when run selected for diff)
            if selectedRunId != nil, let _ = rehearsals.first(where: { $0.id == selectedRunId }) {
                viewModePicker
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    if viewMode == .diff, let runId = selectedRunId, let run = rehearsals.first(where: { $0.id == runId }) {
                        diffSection(run)
                    } else {
                        originalSection
                        if let runId = selectedRunId, let run = rehearsals.first(where: { $0.id == runId }) {
                            Divider()
                            rehearsalResultSection(run)
                        }
                    }
                    metadataSection
                }
                .padding(Theme.Spacing.lg)
            }
        }
    }

    private var viewModePicker: some View {
        HStack {
            Picker("View", selection: $viewMode) {
                ForEach(ViewMode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, 6)
        .background(Theme.Color.surface)
    }

    /// ADR-054 — Promptfoo row-per-turn diff matrix view
    private func diffSection(_ run: RehearsalRun) -> some View {
        let original = task.output ?? task.description
        let replay = run.resultText ?? "(결과 없음)"
        let diff = TextDiff.lineDiff(original: original, replay: replay, maxLines: 500)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Diff — \(diff.summary())")
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.Color.text)
                Spacer()
                changeRatioBar(diff.changeRatio)
            }
            VStack(spacing: 1) {
                ForEach(Array(diff.lines.enumerated()), id: \.offset) { _, line in
                    DiffLineRow(line: line)
                }
            }
            .padding(8)
            .background(Theme.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
    }

    private func changeRatioBar(_ ratio: Double) -> some View {
        let percent = Int(ratio * 100)
        let color: Color = percent < 20 ? .green : (percent < 50 ? .yellow : .orange)
        return HStack(spacing: 4) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 10))
                .foregroundStyle(color)
            Text("변화 \(percent)%")
                .font(Theme.Typography.micro)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var originalSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("원본 결과")
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.Color.text)
                Spacer()
                Text(task.assignedAgent?.shortLabel.capitalized ?? "?")
                    .font(Theme.Typography.monoSmall)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.Color.surfaceHi)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            Text(task.output ?? task.description)
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .textSelection(.enabled)
        }
    }

    private func rehearsalResultSection(_ run: RehearsalRun) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("리허설 결과")
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.Color.text)
                Spacer()
                Text(run.replayAgentRaw)
                    .font(Theme.Typography.monoSmall)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                statusBadge(run.status)
            }
            if let result = run.resultText {
                Text(result)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.text)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.yellow.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    .textSelection(.enabled)
            } else if let err = run.errorMessage {
                Text("오류: \(err)")
                    .font(Theme.Typography.small)
                    .foregroundStyle(.red)
            } else {
                Text("결과 대기 중…")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            if let dur = run.durationMs {
                Text("\(dur)ms · 추정 비용 $\(String(format: "%.4f", run.estimatedCostUSD))")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Metadata")
                .font(Theme.Typography.body.weight(.semibold))
                .foregroundStyle(Theme.Color.text)
            metaRow(label: "Task ID", value: task.id.uuidString.prefix(8).description)
            metaRow(label: "원본 모델", value: task.assignedAgent?.shortLabel ?? "(미배정)")
            metaRow(label: "재실행 모델", value: selectedReplayAgent.shortLabel)
            metaRow(label: "Entries", value: "\(allEntries.filter { task.entryRefs.contains($0.id) || (task.entryRefs.isEmpty && $0.timestamp >= task.createdAt) }.count)개")
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(Theme.Typography.monoSmall)
                .foregroundStyle(Theme.Color.text)
            Spacer()
        }
    }

    private func statusBadge(_ status: RehearsalRun.Status) -> some View {
        let (color, label, icon): (Color, String, String) = {
            switch status {
            case .pending: return (.gray, "대기", "circle.dotted")
            case .running: return (.blue, "실행 중", "circle.dashed")
            case .completed: return (.green, "완료", "checkmark.circle.fill")
            case .failed: return (.red, "실패", "xmark.circle.fill")
            case .cancelled: return (.orange, "취소", "minus.circle.fill")
            }
        }()
        return Label(label, systemImage: icon)
            .font(Theme.Typography.micro)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("⚠ 리허설은 별도 비용 발생. ‘Promote to main’ 액션 없이는 production conversation에 반영되지 않음")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
            Spacer()
            FlatButton("닫기", variant: .primary) { onClose() }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(Theme.Spacing.md)
    }
}

/// ADR-054 — DiffLine row (line-by-line view).
private struct DiffLineRow: View {
    let line: TextDiff.DiffLine

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // line numbers (original / replay)
            Text(originalLineLabel)
                .font(Theme.Typography.monoSmall)
                .foregroundStyle(Theme.Color.textTertiary)
                .frame(width: 32, alignment: .trailing)
            Text(replayLineLabel)
                .font(Theme.Typography.monoSmall)
                .foregroundStyle(Theme.Color.textTertiary)
                .frame(width: 32, alignment: .trailing)
            // marker
            Text(marker)
                .font(Theme.Typography.monoSmall.weight(.bold))
                .foregroundStyle(markerColor)
                .frame(width: 14, alignment: .center)
            // line text
            Text(line.text.isEmpty ? " " : line.text)
                .font(Theme.Typography.monoSmall)
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }

    private var originalLineLabel: String {
        line.originalLineNum.map(String.init) ?? "·"
    }

    private var replayLineLabel: String {
        line.replayLineNum.map(String.init) ?? "·"
    }

    private var marker: String {
        switch line.kind {
        case .same: return " "
        case .added: return "+"
        case .removed: return "-"
        }
    }

    private var markerColor: Color {
        switch line.kind {
        case .same: return Theme.Color.textTertiary
        case .added: return .green
        case .removed: return .red
        }
    }

    private var textColor: Color {
        switch line.kind {
        case .same: return Theme.Color.textSecondary
        case .added: return Theme.Color.text
        case .removed: return Theme.Color.text
        }
    }

    private var backgroundColor: Color {
        switch line.kind {
        case .same: return Color.clear
        case .added: return Color.green.opacity(0.08)
        case .removed: return Color.red.opacity(0.08)
        }
    }
}

private struct RunRowView: View {
    let run: RehearsalRun
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                statusDot
                VStack(alignment: .leading, spacing: 2) {
                    Text(run.replayAgentRaw)
                        .font(Theme.Typography.small.weight(.medium))
                        .foregroundStyle(Theme.Color.text)
                    Text(timeAgo(run.startedAt))
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 6)
            .background(selected ? Theme.Color.accentMuted : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var statusDot: some View {
        let color: Color = {
            switch run.status {
            case .pending: return .gray
            case .running: return .blue
            case .completed: return .green
            case .failed: return .red
            case .cancelled: return .orange
            }
        }()
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "\(Int(interval))초 전" }
        if interval < 3600 { return "\(Int(interval/60))분 전" }
        if interval < 86_400 { return "\(Int(interval/3600))시간 전" }
        return "\(Int(interval/86400))일 전"
    }
}
