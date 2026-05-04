import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-092 Phase 1 / ADR-093 Phase 2** — Telegram Hub Activity 탭.
///
/// Phase 1: 사용량 대시보드 요약 + 에러 로그 바로가기 + placeholder.
/// Phase 2: `ActivityFeedView`로 placeholder 교체. 실시간 에러 피드 + 통합 통계.
struct TelegramHubActivityTab: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            usageSummarySection
            errorLogSection
            // ADR-093 Phase 2 — 실시간 피드 (placeholder 교체)
            ActivityFeedView()
        }
    }

    // MARK: - 사용량 요약

    private var usageSummarySection: some View {
        CardSection(style: .subtle) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SectionHeaderRow(
                    icon: "chart.bar.fill",
                    iconColor: Theme.Color.accent,
                    title: "사용량 통계",
                    caption: "지난 7일"
                )
                HStack(spacing: Theme.Spacing.xl) {
                    statItem(
                        label: "총 Turn",
                        value: "\(appModel.telegramUsageSnapshot.totalTurns)"
                    )
                    statItem(
                        label: "처리된 업데이트",
                        value: "\(appModel.telegramHealth.totalUpdatesProcessed)"
                    )
                    statItem(
                        label: "연속 실패",
                        value: "\(appModel.telegramHealth.consecutiveFailures)"
                    )
                    Spacer()
                    FlatButton("상세 보기", icon: "arrow.up.right", variant: .ghost) {
                        appModel.presentExclusiveSheet { $0.showTelegramUsageDashboard = true }
                    }
                }
                .padding(.top, Theme.Spacing.xs)
            }
        }
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Theme.Typography.body.weight(.semibold))
                .foregroundStyle(Theme.Color.text)
            Text(label)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
        }
    }

    // MARK: - 에러 로그

    private var errorLogSection: some View {
        CardSection(
            style: appModel.telegramHealth.state == .failed ? .accent : .subtle,
            accentColor: Theme.Color.danger
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SectionHeaderRow(
                    icon: "exclamationmark.triangle.fill",
                    iconColor: appModel.telegramHealth.state == .failed
                        ? Theme.Color.danger
                        : Theme.Color.textTertiary,
                    title: "에러 로그",
                    caption: appModel.telegramHealth.lastErrorMessage.map { "마지막: \($0)" }
                )
                HStack {
                    Text(errorLogSummary)
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    FlatButton("열기", icon: "arrow.up.right.square", variant: .ghost) {
                        appModel.showTelegramErrorLogSheet = true
                    }
                }
            }
        }
    }

    private var errorLogSummary: String {
        switch appModel.telegramHealth.state {
        case .idle:
            return "텔레그램이 비활성 상태예요. 봇을 추가하고 활성화하면 여기서 상태를 확인할 수 있어요."
        case .healthy:
            return "정상 동작 중. 에러가 없어요."
        case .degraded:
            let failures = appModel.telegramHealth.consecutiveFailures
            return "일시 오류 \(failures)회 — 자동 재시도 중. 에러 로그를 열어 자세한 내용을 확인하세요."
        case .failed:
            return "영구 실패 상태예요. 에러 로그를 열어 원인을 확인하고 봇 설정을 점검하세요."
        }
    }
}
