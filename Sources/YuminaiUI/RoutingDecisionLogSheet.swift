import SwiftUI
import YuminaiCore

/// Routing Decision Log viewer (ADR-052).
///
/// **3-pane 패턴** (Phoenix span-detail layout 차용):
/// - Timeline: 최근 routing decisions list
/// - Decision Card: 선택된 record 상세 (Mitchell Model Card 패턴)
/// - Counterfactual: 같은 fingerprint의 과거 decisions 통계
///
/// 출처:
/// - LangSmith Run/Thread observability https://docs.smith.langchain.com/observability/concepts
/// - Phoenix span detail https://arize.com/docs/phoenix/tracing/concepts-tracing/what-are-traces
/// - Mitchell et al. "Model Cards for Model Reporting" FAT* '19
public struct RoutingDecisionLogSheet: View {
    public let decisions: [RoutingDecisionRecord]
    public let onClose: () -> Void
    public let onExport: () -> Void
    public let onClear: () -> Void

    @State private var selectedRecord: RoutingDecisionRecord?
    @State private var showRawPrompt: Bool = false
    @State private var filterOutcome: FilterOutcome = .all
    @State private var sheetTab: SheetTab = .browse

    enum SheetTab: String, CaseIterable, Identifiable {
        case browse = "결정 탐색"
        case stats = "통계 / 요약"
        var id: String { rawValue }
    }

    public init(
        decisions: [RoutingDecisionRecord],
        onClose: @escaping () -> Void,
        onExport: @escaping () -> Void,
        onClear: @escaping () -> Void
    ) {
        self.decisions = decisions
        self.onClose = onClose
        self.onExport = onExport
        self.onClear = onClear
    }

    enum FilterOutcome: String, CaseIterable, Identifiable {
        case all, applied, cancelled, skipped, failed
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "전체"
            case .applied: return "적용됨"
            case .cancelled: return "취소됨"
            case .skipped: return "건너뜀"
            case .failed: return "실패"
            }
        }
    }

    private var filteredDecisions: [RoutingDecisionRecord] {
        switch filterOutcome {
        case .all: return decisions
        case .applied: return decisions.filter { $0.outcome == .applied }
        case .cancelled: return decisions.filter { $0.outcome == .cancelled }
        case .skipped: return decisions.filter { $0.outcome == .skipped }
        case .failed: return decisions.filter { $0.outcome == .failed }
        }
    }

    private var counterfactualGroup: [RoutingDecisionRecord] {
        guard let fingerprint = selectedRecord?.taskFingerprint else { return [] }
        return decisions.filter { $0.taskFingerprint == fingerprint && $0.id != selectedRecord?.id }
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabPicker
            Divider()
            switch sheetTab {
            case .browse:
                HStack(spacing: 0) {
                    timelinePane
                        .frame(width: 280)
                    Divider()
                    detailPane
                        .frame(maxWidth: .infinity)
                }
            case .stats:
                statsPane
            }
            Divider()
            footer
        }
        // ADR-073 — 반응형. 내부 ScrollView 다수 있어 wrap=false.
        .yuminaiSheetFrame(width: 880, height: 600, wrapInScrollView: false)
        .background(Theme.Color.bg)
        .onAppear {
            if selectedRecord == nil {
                selectedRecord = decisions.first
            }
        }
        .overlay(alignment: .topTrailing) {
            SheetCloseButton(action: onClose)
        }
    }

    private var tabPicker: some View {
        HStack {
            Picker("Tab", selection: $sheetTab) {
                ForEach(SheetTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, 6)
    }

    /// ADR-054 — Routing log 통계 view (BubbleUp-style aggregation)
    private var statsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                statsCard(title: "Outcome 분포", rows: outcomeStats)
                statsCard(title: "Selected Agent 분포 (적용된 routing만)", rows: agentStats)
                statsCard(title: "Task Kind 분포", rows: taskKindStats)
                statsCard(title: "Keyword 빈도 (Top 10)", rows: keywordStats)
                statsCard(title: "Fingerprint 빈도 (반복되는 같은 종류 task)", rows: fingerprintStats)
                // ADR-060 Phase 2 — 시간순 cancel trend (최근 N개)
                cancelTrendCard
            }
            .padding(Theme.Spacing.lg)
        }
    }

    /// **ADR-060 Phase 2** — 최근 50개 결정의 cancel/applied 시간순 추이.
    /// keyword별 line chart 대신 단순 sequence (운영 부담 ↓).
    private var cancelTrendCard: some View {
        let recent = Array(decisions.prefix(50)).reversed()  // 시간순 (오래된 → 최근)
        return VStack(alignment: .leading, spacing: 6) {
            Text("최근 50개 결정 시간순 추이 (ADR-060 Phase 2)")
                .font(Theme.Typography.body.weight(.semibold))
                .foregroundStyle(Theme.Color.text)
            if recent.isEmpty {
                Text("(아직 결정 없음)")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
            } else {
                // 각 결정을 dot로 표시 (color = outcome)
                HStack(spacing: 1) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { _, record in
                        outcomeDot(record.outcome)
                            .help("\(record.matchedKeyword ?? record.taskKindRaw) → \(record.selectedAgentRaw) (\(record.outcome.rawValue))")
                    }
                    Spacer()
                }
                HStack(spacing: 8) {
                    legendDot(color: .green, label: "applied")
                    legendDot(color: .orange, label: "cancelled")
                    legendDot(color: .gray, label: "skipped")
                    legendDot(color: .red, label: "failed")
                    Spacer()
                }
                .padding(.top, 2)
                // 최근 10개 cancel ratio
                let last10 = Array(decisions.prefix(10))
                let cancelCount = last10.filter { $0.outcome == .cancelled }.count
                Text("최근 10개 중 cancel 비율: \(cancelCount)/10 (\(cancelCount * 10)%)")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .padding(.top, 4)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private func outcomeDot(_ outcome: RoutingDecisionRecord.Outcome) -> some View {
        let color: Color = {
            switch outcome {
            case .applied: return .green
            case .cancelled: return .orange
            case .skipped: return .gray
            case .failed: return .red
            }
        }()
        return Rectangle()
            .fill(color)
            .frame(width: 8, height: 16)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Rectangle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
        }
    }

    private struct StatRow: Identifiable {
        let id = UUID()
        let label: String
        let count: Int
        let pct: Double
    }

    private func statsCard(title: String, rows: [StatRow]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.Typography.body.weight(.semibold))
                .foregroundStyle(Theme.Color.text)
            if rows.isEmpty {
                Text("(데이터 없음)")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textTertiary)
            } else {
                ForEach(rows) { row in
                    statRow(row)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private func statRow(_ row: StatRow) -> some View {
        HStack(spacing: 8) {
            Text(row.label)
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.text)
                .frame(width: 200, alignment: .leading)
                .lineLimit(1)
            ProgressView(value: row.pct)
                .frame(maxWidth: .infinity)
            Text("\(row.count) (\(Int(row.pct * 100))%)")
                .font(Theme.Typography.monoSmall)
                .foregroundStyle(Theme.Color.textSecondary)
                .frame(width: 80, alignment: .trailing)
        }
    }

    private var outcomeStats: [StatRow] {
        let total = max(1, decisions.count)
        let groups = Dictionary(grouping: decisions, by: \.outcome).mapValues(\.count)
        return groups
            .sorted { $0.value > $1.value }
            .map { StatRow(label: $0.key.rawValue, count: $0.value, pct: Double($0.value) / Double(total)) }
    }

    private var agentStats: [StatRow] {
        let applied = decisions.filter { $0.outcome == .applied }
        let total = max(1, applied.count)
        let groups = Dictionary(grouping: applied, by: \.selectedAgentRaw).mapValues(\.count)
        return groups
            .sorted { $0.value > $1.value }
            .map { StatRow(label: $0.key, count: $0.value, pct: Double($0.value) / Double(total)) }
    }

    private var taskKindStats: [StatRow] {
        let total = max(1, decisions.count)
        let groups = Dictionary(grouping: decisions, by: \.taskKindRaw).mapValues(\.count)
        return groups
            .sorted { $0.value > $1.value }
            .map { StatRow(label: $0.key, count: $0.value, pct: Double($0.value) / Double(total)) }
    }

    private var keywordStats: [StatRow] {
        let withKeyword = decisions.compactMap { $0.matchedKeyword }
        let total = max(1, withKeyword.count)
        var counts: [String: Int] = [:]
        for kw in withKeyword { counts[kw, default: 0] += 1 }
        return counts
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { StatRow(label: "‘\($0.key)’", count: $0.value, pct: Double($0.value) / Double(total)) }
    }

    private var fingerprintStats: [StatRow] {
        let total = max(1, decisions.count)
        let groups = Dictionary(grouping: decisions, by: \.taskFingerprint).mapValues(\.count)
        return groups
            .sorted { $0.value > $1.value }
            .filter { $0.value >= 2 }  // 2회 이상만 표시 (반복 패턴)
            .prefix(10)
            .map { StatRow(label: $0.key, count: $0.value, pct: Double($0.value) / Double(total)) }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Color.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Routing Decision Log")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
                Text("자동 routing 결정 회고 — 모델별 분포, 사유, counterfactual 비교")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
            statsBadge
        }
        .padding(Theme.Spacing.lg)
    }

    private var statsBadge: some View {
        let appliedCount = decisions.filter { $0.outcome == .applied }.count
        let cancelledCount = decisions.filter { $0.outcome == .cancelled }.count
        return HStack(spacing: 12) {
            Label("\(appliedCount)", systemImage: "checkmark.circle.fill")
                .font(Theme.Typography.small)
                .foregroundStyle(Color.green)
            Label("\(cancelledCount)", systemImage: "xmark.circle.fill")
                .font(Theme.Typography.small)
                .foregroundStyle(Color.orange)
            Label("\(decisions.count)", systemImage: "list.bullet")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }

    // MARK: - Timeline pane

    private var timelinePane: some View {
        VStack(spacing: 0) {
            Picker("필터", selection: $filterOutcome) {
                ForEach(FilterOutcome.allCases) { f in
                    Text(f.label).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .padding(Theme.Spacing.sm)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if filteredDecisions.isEmpty {
                        EmptyStateHint(
                            icon: "arrow.triangle.branch",
                            title: "아직 routing 기록이 없어요",
                            message: "Settings에서 자동 routing을 활성화하면 메시지를 보낼 때마다 결정이 기록됩니다."
                        )
                        .padding(Theme.Spacing.md)
                    } else {
                        ForEach(filteredDecisions, id: \.id) { record in
                            DecisionRowView(
                                record: record,
                                selected: record.id == selectedRecord?.id,
                                onTap: { selectedRecord = record }
                            )
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .background(Theme.Color.surface)
    }

    // MARK: - Detail pane

    @ViewBuilder
    private var detailPane: some View {
        if let record = selectedRecord {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    decisionCard(record)
                    candidatesTable(record)
                    promptSection(record)
                    counterfactualSection(record)
                }
                .padding(Theme.Spacing.lg)
            }
        } else {
            EmptyStateHint(
                icon: "doc.text.magnifyingglass",
                title: "결정을 선택하세요",
                message: "왼쪽 timeline에서 routing 결정 1개를 선택하면 상세가 표시됩니다."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func decisionCard(_ record: RoutingDecisionRecord) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("Decision Card")
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.Color.text)
                Spacer()
                outcomeBadge(record.outcome)
            }
            HStack(spacing: 8) {
                ModelChip(label: record.previousAgentRaw)
                Image(systemName: "arrow.right")
                    .foregroundStyle(Theme.Color.textTertiary)
                ModelChip(label: record.selectedAgentRaw, highlighted: true)
            }
            VStack(alignment: .leading, spacing: 4) {
                MetaRow(label: "사유", value: record.reasonSummary)
                MetaRow(label: "분류", value: record.taskKindRaw)
                if let kw = record.matchedKeyword {
                    MetaRow(label: "Keyword", value: "‘\(kw)’")
                }
                MetaRow(label: "Fingerprint", value: record.taskFingerprint, mono: true)
                MetaRow(label: "Handoff tokens", value: "~\(record.estimatedHandoffTokens)")
                MetaRow(label: "워크스페이스", value: record.workspaceName ?? "(알 수 없음)")
                MetaRow(label: "Timestamp", value: formatTimestamp(record.timestamp), mono: true)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surfaceHi)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private func candidatesTable(_ record: RoutingDecisionRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("후보 모델")
                .font(Theme.Typography.body.weight(.semibold))
                .foregroundStyle(Theme.Color.text)
            ForEach(record.candidates, id: \.agentRaw) { candidate in
                HStack {
                    ModelChip(label: candidate.agentRaw, highlighted: candidate.agentRaw == record.selectedAgentRaw)
                    ProgressView(value: candidate.score)
                        .frame(width: 100)
                    Text(String(format: "%.2f", candidate.score))
                        .font(Theme.Typography.monoSmall)
                        .foregroundStyle(Theme.Color.textSecondary)
                    Spacer()
                    Text(candidate.reasonCodes.joined(separator: ", "))
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(candidate.agentRaw == record.selectedAgentRaw ? Theme.Color.accentMuted : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            }
        }
    }

    private func promptSection(_ record: RoutingDecisionRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("입력 프롬프트")
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.Color.text)
                Spacer()
                if record.rawPrompt != nil {
                    Toggle(isOn: $showRawPrompt) {
                        Text("원본 표시")
                            .font(Theme.Typography.micro)
                    }
                    .toggleStyle(.checkbox)
                }
            }
            Text(displayedPrompt(record))
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Color.surfaceHi)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .textSelection(.enabled)
            if record.rawPrompt == nil {
                Text("⚠ Raw prompt 미저장 — Settings → Routing log raw prompts 활성 시 보존")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
        }
    }

    private func displayedPrompt(_ record: RoutingDecisionRecord) -> String {
        if showRawPrompt, let raw = record.rawPrompt { return raw }
        return record.redactedPrompt + (record.redactedPrompt.count >= 80 ? "…" : "")
    }

    private func counterfactualSection(_ record: RoutingDecisionRecord) -> some View {
        let group = counterfactualGroup
        return VStack(alignment: .leading, spacing: 6) {
            Text("Counterfactual — 같은 fingerprint의 과거 결정 (\(group.count))")
                .font(Theme.Typography.body.weight(.semibold))
                .foregroundStyle(Theme.Color.text)
            if group.isEmpty {
                Text("같은 종류 task에 대한 다른 결정이 아직 없어요. 더 사용하면 패턴이 보일 거예요.")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
            } else {
                let agentCounts = Dictionary(grouping: group, by: \.selectedAgentRaw).mapValues(\.count)
                ForEach(agentCounts.sorted(by: { $0.value > $1.value }), id: \.key) { agent, count in
                    HStack {
                        ModelChip(label: agent)
                        Text("\(count)회")
                            .font(Theme.Typography.small)
                            .foregroundStyle(Theme.Color.textSecondary)
                        Spacer()
                    }
                }
            }
        }
    }

    private func outcomeBadge(_ outcome: RoutingDecisionRecord.Outcome) -> some View {
        let (color, label, icon): (Color, String, String) = {
            switch outcome {
            case .applied: return (.green, "적용됨", "checkmark.circle.fill")
            case .cancelled: return (.orange, "취소됨", "xmark.circle.fill")
            case .skipped: return (.gray, "건너뜀", "minus.circle")
            case .failed: return (.red, "실패", "exclamationmark.triangle.fill")
            }
        }()
        return Label(label, systemImage: icon)
            .font(Theme.Typography.small)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private func formatTimestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: date)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            FlatButton("내보내기 (JSON)", icon: "square.and.arrow.up", variant: .secondary) { onExport() }
            FlatButton("전체 지우기", icon: "trash", variant: .secondary) { onClear() }
            Spacer()
            FlatButton("닫기", variant: .primary) { onClose() }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(Theme.Spacing.md)
    }
}

// MARK: - Subviews

private struct DecisionRowView: View {
    let record: RoutingDecisionRecord
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                outcomeIcon
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(record.previousAgentRaw)
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textTertiary)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.Color.textTertiary)
                        Text(record.selectedAgentRaw)
                            .font(Theme.Typography.small.weight(.medium))
                            .foregroundStyle(Theme.Color.text)
                    }
                    Text(record.matchedKeyword.map { "‘\($0)’" } ?? record.taskKindRaw)
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .lineLimit(1)
                    Text(timeAgo(record.timestamp))
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
    private var outcomeIcon: some View {
        let (color, name): (Color, String) = {
            switch record.outcome {
            case .applied: return (.green, "checkmark.circle.fill")
            case .cancelled: return (.orange, "xmark.circle.fill")
            case .skipped: return (.gray, "minus.circle")
            case .failed: return (.red, "exclamationmark.triangle.fill")
            }
        }()
        Image(systemName: name)
            .font(.system(size: 12))
            .foregroundStyle(color)
    }

    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "\(Int(interval))초 전" }
        if interval < 3600 { return "\(Int(interval/60))분 전" }
        if interval < 86_400 { return "\(Int(interval/3600))시간 전" }
        return "\(Int(interval/86400))일 전"
    }
}

private struct ModelChip: View {
    let label: String
    var highlighted: Bool = false

    var body: some View {
        Text(label)
            .font(Theme.Typography.monoSmall)
            .foregroundStyle(highlighted ? Theme.Color.accent : Theme.Color.text)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(highlighted ? Theme.Color.accentMuted : Theme.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct MetaRow: View {
    let label: String
    let value: String
    var mono: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(mono ? Theme.Typography.monoSmall : Theme.Typography.small)
                .foregroundStyle(Theme.Color.text)
                .textSelection(.enabled)
            Spacer()
        }
    }
}
