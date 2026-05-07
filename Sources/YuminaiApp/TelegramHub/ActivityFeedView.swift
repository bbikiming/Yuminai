import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-093 Phase 2** — Activity 탭 통합 피드.
///
/// 구성:
/// 1. 통합 통계 카드 (총 메시지 · 에러 · 활성 chat)
/// 2. 시간 정렬 이벤트 피드 (최근 50개, `TelegramErrorEntry` 기반)
/// 3. 빠른 액션 (에러 로그 비우기, 큐 비우기)
///
/// 데이터 소스: `appModel.telegramRecentErrors(limit: 50)` + `appModel.telegramUsageSnapshot`.
@MainActor
struct ActivityFeedView: View {
    @Environment(AppModel.self) private var appModel
    @State private var events: [ActivityEvent] = []
    @State private var isLoadingEvents = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            summaryCard
            feedSection
            quickActionsSection
        }
        .onAppear { loadEvents() }
        .onChange(of: appModel.telegramHealth) { _, _ in loadEvents() }
    }

    // MARK: - 통합 통계 카드

    private var summaryCard: some View {
        CardSection(style: .subtle) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SectionHeaderRow(
                    icon: "chart.bar.fill",
                    iconColor: Theme.Color.accent,
                    title: "통합 통계"
                )
                HStack(spacing: Theme.Spacing.xl) {
                    statChip(
                        label: "총 Turn",
                        value: "\(appModel.telegramUsageSnapshot.totalTurns)",
                        color: Theme.Color.accent
                    )
                    statChip(
                        label: "에러",
                        value: "\(errorCount)",
                        color: errorCount > 0 ? Theme.Color.danger : Theme.Color.success
                    )
                    statChip(
                        label: "활성 Chat",
                        value: "\(activeChatCount)",
                        color: Theme.Color.accent
                    )
                    Spacer()
                }
                .padding(.top, Theme.Spacing.xs)
            }
        }
    }

    private func statChip(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Theme.Typography.body.weight(.semibold))
                .foregroundStyle(color)
            Text(label)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
        }
    }

    // MARK: - 이벤트 피드

    private var feedSection: some View {
        CardSection(style: .subtle) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SectionHeaderRow(
                    icon: "clock.fill",
                    iconColor: Theme.Color.accent,
                    title: "최근 활동",
                    caption: "최근 50건"
                )
                if isLoadingEvents {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("불러오는 중...")
                            .font(Theme.Typography.small)
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                    .padding(.top, Theme.Spacing.xs)
                } else if events.isEmpty {
                    AnimatedEmptyState(
                        icon: "tray",
                        iconTint: Theme.Color.textTertiary,
                        title: "활동 없음",
                        message: "아직 기록된 이벤트가 없어요.\n텔레그램 봇에서 메시지를 보내면 여기에 표시됩니다."
                    )
                    .padding(.top, Theme.Spacing.sm)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(events) { event in
                            eventRow(event)
                            if event.id != events.last?.id {
                                Divider()
                                    .padding(.leading, 28)
                            }
                        }
                    }
                    .padding(.top, Theme.Spacing.xs)
                }
            }
        }
    }

    private func eventRow(_ event: ActivityEvent) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            // 아이콘
            ZStack {
                Circle()
                    .fill(event.iconColor.opacity(0.12))
                    .frame(width: 22, height: 22)
                Image(systemName: event.iconName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(event.iconColor)
            }
            .accessibilityHidden(true)

            // 내용
            VStack(alignment: .leading, spacing: 2) {
                Text(event.description)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.text)
                    .lineLimit(2)
                Text(relativeTime(event.timestamp))
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
            }

            Spacer()
        }
        .padding(.vertical, Theme.Spacing.xs)
        .contentShape(Rectangle())
    }

    // MARK: - 빠른 액션

    private var quickActionsSection: some View {
        CardSection(style: .subtle) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SectionHeaderRow(
                    icon: "bolt.fill",
                    iconColor: Theme.Color.accent,
                    title: "빠른 액션"
                )
                HStack(spacing: Theme.Spacing.sm) {
                    FlatButton("에러 로그 열기", icon: "arrow.up.right.square", variant: .ghost) {
                        appModel.showTelegramErrorLogSheet = true
                    }
                    FlatButton("에러 로그 비우기", icon: "trash", variant: .ghost) {
                        Task { await appModel.telegramClearErrorLog() }
                    }
                    if appModel.telegramQueueDepth > 0 {
                        FlatButton(
                            "대기 큐 (\(appModel.telegramQueueDepth)건)",
                            icon: "tray.and.arrow.up",
                            variant: .secondary
                        ) {
                            // Phase 3에서 큐 flush UI 추가 예정
                        }
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Computed

    private var errorCount: Int {
        events.filter { $0.kind == .error }.count
    }

    private var activeChatCount: Int {
        appModel.telegramUsageSnapshot.totalActiveChatCount
    }

    // MARK: - Data loading

    private func loadEvents() {
        isLoadingEvents = true
        Task {
            let errors = await appModel.telegramRecentErrors(limit: 50)
            let newEvents = errors.map { ActivityEvent(from: $0) }
                .sorted { $0.timestamp > $1.timestamp }
            events = newEvents
            isLoadingEvents = false
        }
    }

    // MARK: - Helpers

    private func relativeTime(_ date: Date) -> String {
        RelativeTime.format(date)
    }
}

// MARK: - ActivityEvent

/// Activity 피드의 이벤트 1건. `TelegramErrorEntry` 래핑 + 뷰 표시용 계산 프로퍼티.
struct ActivityEvent: Identifiable, Sendable {
    enum Kind: Sendable {
        case error
        case warning
        case info
    }

    let id: UUID
    let timestamp: Date
    let kind: Kind
    let description: String
    let category: TelegramErrorEntry.Category

    init(from entry: TelegramErrorEntry) {
        self.id = entry.id
        self.timestamp = entry.timestamp
        self.category = entry.category
        switch entry.category {
        case .auth, .server:
            self.kind = .error
        case .rateLimit, .parsing:
            self.kind = .warning
        case .network, .other:
            self.kind = .info
        }
        self.description = entry.userFacingMessage
    }

    var iconName: String {
        switch category {
        case .auth: return "lock.slash.fill"
        case .rateLimit: return "gauge"
        case .network: return "wifi.exclamationmark"
        case .server: return "server.rack"
        case .parsing: return "doc.text.magnifyingglass"
        case .other: return "exclamationmark.circle.fill"
        }
    }

    var iconColor: Color {
        switch kind {
        case .error: return Theme.Color.danger
        case .warning: return .orange
        case .info: return Theme.Color.textTertiary
        }
    }
}

// MARK: - TelegramUsageStore.Snapshot convenience

private extension TelegramUsageStore.Snapshot {
    var totalActiveChatCount: Int {
        chatStats.values.filter { $0.turnCount > 0 }.count
    }
}
