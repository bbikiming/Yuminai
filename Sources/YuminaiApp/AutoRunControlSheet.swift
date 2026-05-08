import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-132** — 자동 실행 제어 패널 sheet.
///
/// 구조:
/// - 헤더: "자동 실행" + 상태 badge
/// - 본문 1: 진행 상황 (Turn N/30, Budget $X.XX/$3.00, 경과 시간)
/// - 본문 2: 실시간 turn 로그 (스크롤)
/// - 본문 3: AutoRunConfig 편집 (advanced 섹션)
/// - 푸터: [⏸ 일시정지] [⏹ 중단] [닫기]
@MainActor
public struct AutoRunControlSheet: View {

    // MARK: - 의존

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    // MARK: - 로컬 상태

    @State private var showSettings: Bool = false

    // MARK: - Body

    public var body: some View {
        YuminaiSheet(width: 580, height: 620) {
            VStack(spacing: 0) {
                SheetHeader(icon: "gearshape.2.fill", title: "자동 실행", onClose: {
                    dismiss()
                }) {
                    stateBadge
                }

                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        progressSection
                        logSection
                        if showSettings {
                            settingsSection
                        }
                    }
                    .padding(Theme.Spacing.lg)
                }
            }
        } footer: {
            HStack(spacing: Theme.Spacing.sm) {
                // 설정 토글
                Button {
                    showSettings.toggle()
                } label: {
                    Label("설정", systemImage: "gearshape")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .buttonStyle(.plain)

                // ADR-135 — 로그 이력 뷰어
                Button {
                    model.showAutoRunLogViewerSheet = true
                } label: {
                    Label("로그 이력", systemImage: "clock.badge.checkmark")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .buttonStyle(.plain)

                Spacer()

                // 일시정지 / 재개
                if case .paused = model.autoRunState {
                    FlatButton("다시 시작", variant: .primary, size: .small) {
                        Task { await model.resumeAutoRun() }
                    }
                } else if case .running = model.autoRunState {
                    FlatButton("일시 정지", variant: .secondary, size: .small) {
                        Task { await model.pauseAutoRun() }
                    }
                }

                // 중단
                if model.autoRunState.isActive {
                    FlatButton("중단", variant: .destructive, size: .small) {
                        Task { await model.stopAutoRun() }
                    }
                }

                FlatButton("닫기", variant: .secondary, size: .small) {
                    dismiss()
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
        }
    }

    // MARK: - 상태 badge

    private var stateBadge: some View {
        Group {
            switch model.autoRunState {
            case .idle:
                Text("대기 중")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.Color.surfaceHi))
            case .running:
                HStack(spacing: 4) {
                    PulseDot(color: Theme.Color.autoRunActive, size: 6)
                    Text("실행 중")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.autoRunActive)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Theme.Color.autoRunActive.opacity(0.1)))
            case .paused:
                Text("일시정지")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.autoRunPaused)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.Color.autoRunPaused.opacity(0.1)))
            case .completed:
                Text("완료")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.Color.surfaceHi))
            case .stopped:
                Text("중단됨")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.Color.surfaceHi))
            }
        }
    }

    // MARK: - 진행 상황

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("진행 상황")
                .font(Theme.Typography.bodyEmphasis)
                .foregroundStyle(Theme.Color.text)

            let config = model.preferences.autoRunConfig
            let logs = model.autoRunLogs
            let turnCount = logs.count
            let totalCost = logs.reduce(0.0) { $0 + $1.costUSD }
            let startedAt: Date? = {
                if case .running(_, _, let t) = model.autoRunState { return t }
                return nil
            }()

            HStack(spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("진행 횟수")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                    Text("\(turnCount) / \(config.maxTurns)")
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Color.text)
                }

                Divider().frame(height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text("예산")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                    Text("$\(String(format: "%.4f", totalCost)) / $\(String(format: "%.2f", config.maxBudgetUSD))")
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Color.text)
                }

                Divider().frame(height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text("경과 시간")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                    if let started = startedAt {
                        let elapsed = Int(Date().timeIntervalSince(started))
                        Text("\(elapsed / 60)분 \(elapsed % 60)초")
                            .font(Theme.Typography.label)
                            .foregroundStyle(Theme.Color.text)
                    } else {
                        Text("—")
                            .font(Theme.Typography.label)
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                }

                Spacer()
            }

            // Turn 진행 바
            if config.maxTurns > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Theme.Color.surfaceHi)
                            .frame(height: 4)
                        Capsule()
                            .fill(Theme.Color.autoRunActive)
                            .frame(
                                width: geo.size.width * min(1.0, Double(turnCount) / Double(config.maxTurns)),
                                height: 4
                            )
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surfaceHi.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    // MARK: - 로그

    @ViewBuilder
    private var logSection: some View {
        if !model.autoRunLogs.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("실행 로그")
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Color.text)

                ForEach(model.autoRunLogs.suffix(10), id: \.turn) { log in
                    AutoRunLogRow(log: log)
                }

                if model.autoRunLogs.count > 10 {
                    Text("... \(model.autoRunLogs.count - 10)개 이전 로그 숨김")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
            }
        } else {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "clock.badge.questionmark")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.Color.textTertiary)
                Text("아직 실행 로그가 없습니다.")
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(Theme.Spacing.xl)
        }
    }

    // MARK: - 설정 (inline)

    private var settingsSection: some View {
        AutoRunSettingsView(config: Binding(
            get: { model.preferences.autoRunConfig },
            set: { newConfig in
                var updated = model.preferences
                updated.autoRunConfig = newConfig
                model.preferences = updated
            }
        ))
    }
}

// MARK: - 로그 행

private struct AutoRunLogRow: View {
    let log: AutoRunTurnLog

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Text("#\(log.turn)")
                .font(Theme.Typography.monoSmall)
                .foregroundStyle(Theme.Color.textTertiary)
                .frame(width: 28, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                let preview = String(log.agentResponse.prefix(80))
                Text(preview + (log.agentResponse.count > 80 ? "…" : ""))
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(2)

                HStack(spacing: Theme.Spacing.xs) {
                    Text("$\(String(format: "%.4f", log.costUSD))")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                    Text("·")
                        .foregroundStyle(Theme.Color.textTertiary)
                    Text("\(String(format: "%.1f", log.durationSeconds))초")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)

                    if !log.warnings.isEmpty {
                        Text("⚠")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.warningStrong)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}
