import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-135** — 자동 실행 로그 뷰어 Sheet.
///
/// `.harness/auto-run-log/<run-id>.jsonl` 파일을 스캔하여
/// 시간 정렬된 run 목록과 turn별 로그를 표시한다.
///
/// ## 구조 (sidebar + content split)
/// - 좌측 사이드바: 최근 20개 run 목록 (날짜, 진행 횟수, 비용, 완료 이유)
/// - 우측 콘텐츠: 선택된 run의 turn별 로그 + 요약
/// - 푸터: [재현] 버튼 — 같은 initialPrompt로 새 자동 실행 시작
///
/// ## 진입점
/// `AutoRunControlSheet` 하단 "로그 이력" 버튼 또는 `AppModel.showAutoRunLogViewerSheet`
@MainActor
public struct AutoRunLogViewerSheet: View {

    // MARK: - 의존

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    // MARK: - 로컬 상태

    @State private var runSummaries: [AutoRunSummary] = []
    @State private var selectedRunId: UUID?
    @State private var selectedLogs: [AutoRunTurnLog] = []
    @State private var isLoading: Bool = false

    // MARK: - Body

    public var body: some View {
        YuminaiSheet(width: 860, height: 640, wrapInScrollView: false) {
            VStack(spacing: 0) {
                SheetHeader(icon: "clock.badge.checkmark", title: "자동 실행 이력", onClose: {
                    dismiss()
                }) {
                    EmptyView()
                }

                HSplitView {
                    // 좌측: run 목록
                    runListPanel
                        .frame(minWidth: 240, idealWidth: 260, maxWidth: 300)

                    // 우측: 선택된 run 로그
                    runDetailPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } footer: {
            HStack(spacing: Theme.Spacing.sm) {
                if let firstPrompt = selectedFirstPrompt {
                    FlatButton("재현", icon: "arrow.clockwise", variant: .secondary, size: .small) {
                        replayRun(initialPrompt: firstPrompt)
                    }
                    .disabled(model.autoRunState.isActive)
                    .help("동일한 프롬프트로 새 자동 실행 시작: \"\(String(firstPrompt.prefix(40)))...\"")
                }

                Spacer()

                Text("총 \(runSummaries.count)개 실행 기록")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)

                FlatButton("닫기", variant: .secondary, size: .small) {
                    dismiss()
                }
            }
        }
        .task {
            await loadRunSummaries()
        }
    }

    // MARK: - 좌측 패널

    private var runListPanel: some View {
        VStack(spacing: 0) {
            // 헤더
            HStack {
                Text("실행 목록")
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Color.bgSidebar)

            Divider()

            if runSummaries.isEmpty && !isLoading {
                Spacer()
                VStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.Color.textTertiary)
                    Text("실행 이력 없음")
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(runSummaries) { summary in
                            RunSummaryRow(
                                summary: summary,
                                isSelected: selectedRunId == summary.runId
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectRun(summary)
                            }
                            Divider()
                        }
                    }
                }
            }
        }
        .background(Theme.Color.bgSidebar)
    }

    // MARK: - 우측 패널

    private var runDetailPanel: some View {
        Group {
            if let summary = selectedRunSummary {
                VStack(spacing: 0) {
                    // 요약 헤더
                    runDetailHeader(summary: summary)
                    Divider()
                    // turn 로그 리스트
                    if selectedLogs.isEmpty {
                        Spacer()
                        VStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 28))
                                .foregroundStyle(Theme.Color.textTertiary)
                            Text("로그를 불러오는 중...")
                                .font(Theme.Typography.label)
                                .foregroundStyle(Theme.Color.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(selectedLogs, id: \.turn) { log in
                                    TurnLogDetailRow(log: log)
                                    Divider()
                                        .padding(.leading, Theme.Spacing.lg)
                                }
                            }
                            .padding(.vertical, Theme.Spacing.sm)
                        }
                    }
                }
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 36))
                        .foregroundStyle(Theme.Color.textTertiary.opacity(0.5))
                    Text("좌측에서 실행 기록을 선택하세요")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.Color.bg)
    }

    // MARK: - 상세 헤더

    @ViewBuilder
    private func runDetailHeader(summary: AutoRunSummary) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(RelativeTime.format(summary.startedAt))
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Color.text)
                Text(summary.completionReason)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
            }

            Spacer()

            HStack(spacing: Theme.Spacing.lg) {
                statPill(label: "진행 횟수", value: "\(summary.turnCount)회")
                statPill(label: "총 비용", value: "$\(String(format: "%.4f", summary.totalCostUSD))")
                statPill(label: "소요 시간", value: summary.durationText)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surfaceHi.opacity(0.3))
    }

    private func statPill(label: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(label)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
            Text(value)
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Color.text)
        }
    }

    // MARK: - 계산 프로퍼티

    private var selectedRunSummary: AutoRunSummary? {
        guard let id = selectedRunId else { return nil }
        return runSummaries.first { $0.runId == id }
    }

    private var selectedFirstPrompt: String? {
        selectedLogs.first(where: { $0.userPrompt != nil })?.userPrompt
    }

    // MARK: - 액션

    private func loadRunSummaries() async {
        guard let wsId = model.selectedWorkspaceId,
              let ws = model.workspaces.first(where: { $0.id == wsId }) else { return }
        isLoading = true
        defer { isLoading = false }

        let logDir = URL(fileURLWithPath: ws.directoryPath)
            .appendingPathComponent(".harness")
            .appendingPathComponent("auto-run-log")

        guard FileManager.default.fileExists(atPath: logDir.path) else { return }

        let jsonlFiles: [URL]
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: logDir,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            )
            jsonlFiles = contents
                .filter { $0.pathExtension == "jsonl" }
                .sorted { a, b in
                    let aDate = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                    let bDate = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                    return aDate > bDate  // 최신 순
                }
                .prefix(20)
                .map { $0 }
        } catch {
            return
        }

        var summaries: [AutoRunSummary] = []
        for fileURL in jsonlFiles {
            guard let fileNameUUID = UUID(uuidString: fileURL.deletingPathExtension().lastPathComponent) else { continue }
            if let summary = buildSummary(from: fileURL, runId: fileNameUUID) {
                summaries.append(summary)
            }
        }
        runSummaries = summaries
    }

    private func buildSummary(from fileURL: URL, runId: UUID) -> AutoRunSummary? {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        let lines = contents.components(separatedBy: "\n").filter { !$0.isEmpty }
        var logs: [AutoRunTurnLog] = []
        let decoder = JSONDecoder()
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let log = try? decoder.decode(AutoRunTurnLog.self, from: data) else { continue }
            logs.append(log)
        }
        guard !logs.isEmpty else { return nil }
        let totalCost = logs.reduce(0.0) { $0 + $1.costUSD }
        let totalDuration = logs.reduce(0.0) { $0 + $1.durationSeconds }
        let startedAt = logs.first?.timestamp ?? Date()
        let durationMins = Int(totalDuration / 60)
        let durationSecs = Int(totalDuration) % 60
        let durationText = durationMins > 0 ? "\(durationMins)분 \(durationSecs)초" : "\(durationSecs)초"

        // 완료 이유 추론 — warnings 분석
        let hasBlocked = logs.contains { $0.warnings.contains { $0.contains("차단") } }
        let completionReason: String = hasBlocked ? "위험 명령 차단으로 일시정지" : "\(logs.count)회 진행 완료"

        return AutoRunSummary(
            runId: runId,
            startedAt: startedAt,
            turnCount: logs.count,
            totalCostUSD: totalCost,
            durationText: durationText,
            completionReason: completionReason,
            fileURL: fileURL
        )
    }

    private func selectRun(_ summary: AutoRunSummary) {
        selectedRunId = summary.runId
        selectedLogs = []
        Task {
            guard let contents = try? String(contentsOf: summary.fileURL, encoding: .utf8) else { return }
            let lines = contents.components(separatedBy: "\n").filter { !$0.isEmpty }
            let decoder = JSONDecoder()
            var logs: [AutoRunTurnLog] = []
            for line in lines {
                guard let data = line.data(using: .utf8),
                      let log = try? decoder.decode(AutoRunTurnLog.self, from: data) else { continue }
                logs.append(log)
            }
            selectedLogs = logs.sorted { $0.turn < $1.turn }
        }
    }

    private func replayRun(initialPrompt: String) {
        dismiss()
        Task {
            await model.startAutoRun(initialPrompt: initialPrompt)
        }
    }
}

// MARK: - AutoRunSummary

/// 로그 파일에서 파생된 run 요약.
private struct AutoRunSummary: Identifiable {
    let runId: UUID
    let startedAt: Date
    let turnCount: Int
    let totalCostUSD: Double
    let durationText: String
    let completionReason: String
    let fileURL: URL

    var id: UUID { runId }
}

// MARK: - RunSummaryRow

private struct RunSummaryRow: View {
    let summary: AutoRunSummary
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                Text(RelativeTime.format(summary.startedAt))
                    .font(Theme.Typography.label)
                    .foregroundStyle(isSelected ? Theme.Color.accent : Theme.Color.text)

                Text(summary.completionReason)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .lineLimit(1)

                HStack(spacing: Theme.Spacing.xs) {
                    Text("\(summary.turnCount)회")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textSecondary)
                    Text("·")
                        .foregroundStyle(Theme.Color.textTertiary)
                    Text("$\(String(format: "%.4f", summary.totalCostUSD))")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Color.accent)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(isSelected ? Theme.Color.accentMuted : .clear)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - TurnLogDetailRow

private struct TurnLogDetailRow: View {
    let log: AutoRunTurnLog

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .top) {
                Text("Turn \(log.turn)")
                    .font(Theme.Typography.monoSmall)
                    .foregroundStyle(Theme.Color.accent)
                    .frame(width: 56, alignment: .leading)

                Spacer()

                HStack(spacing: Theme.Spacing.sm) {
                    Text("$\(String(format: "%.4f", log.costUSD))")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                    Text("\(String(format: "%.1f", log.durationSeconds))초")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                    Text(RelativeTime.format(log.timestamp))
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
            }

            // 사용자 프롬프트 (첫 turn)
            if let prompt = log.userPrompt {
                HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                    Text("Q")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                        .frame(width: 14)
                    Text(String(prompt.prefix(200)) + (prompt.count > 200 ? "…" : ""))
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // 응답 미리보기
            HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                Text("A")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .frame(width: 14)
                Text(String(log.agentResponse.prefix(300)) + (log.agentResponse.count > 300 ? "…" : ""))
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 감지된 명령 / 경고
            if !log.toolCalls.isEmpty || !log.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    if !log.toolCalls.isEmpty {
                        Label("\(log.toolCalls.count)개 명령 감지", systemImage: "terminal")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    ForEach(log.warnings.prefix(3), id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.warning)
                    }
                }
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs)
                .background(Theme.Color.warning.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }
}
