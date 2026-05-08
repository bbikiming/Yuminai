import SwiftUI
import YuminaiCore

/// **ADR-093 Phase 2** — 상시 표시 봇 상태 Dock (stateless, props 기반).
///
/// `TelegramHealthPill` 대체. SidebarView 하단에 배치.
/// AppModel 의존성 없이 순수 props로 동작.
/// 상태 관리(popover 내용 로딩)는 `BotStatusDock` (YuminaiApp)이 담당.
///
/// 표시 형식:
/// ```
/// 🟢 @YuminaiBot · queue: 2 · 1m ago
/// ```
/// queue: 0이면 숨김. 다중 봇이면 "+N more" 배지.
public struct BotStatusDockView: View {
    public let health: TelegramHealthSnapshot
    public let queueDepth: Int
    public let botCount: Int
    public let firstBotUsername: String?
    @Binding public var showPopover: Bool
    public let onOpenHub: () -> Void
    public let onOpenErrorLog: () -> Void
    public let recentErrors: [TelegramErrorEntry]

    @State private var isHovering = false

    public init(
        health: TelegramHealthSnapshot,
        queueDepth: Int,
        botCount: Int,
        firstBotUsername: String?,
        showPopover: Binding<Bool>,
        onOpenHub: @escaping () -> Void,
        onOpenErrorLog: @escaping () -> Void,
        recentErrors: [TelegramErrorEntry] = []
    ) {
        self.health = health
        self.queueDepth = queueDepth
        self.botCount = botCount
        self.firstBotUsername = firstBotUsername
        self._showPopover = showPopover
        self.onOpenHub = onOpenHub
        self.onOpenErrorLog = onOpenErrorLog
        self.recentErrors = recentErrors
    }

    public var body: some View {
        HStack(spacing: 0) {
            dockButton
            Spacer()
        }
    }

    // MARK: - Main dock button

    private var dockButton: some View {
        Button(action: { showPopover.toggle() }) {
            HStack(spacing: 4) {
                statusDot
                Text(primaryLabel)
                    .font(Theme.Typography.micro.weight(.medium))
                    .foregroundStyle(labelColor)
                if queueDepth > 0 {
                    queueBadge
                }
                if let timeText = lastActivityText {
                    Text("·")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                    Text(timeText)
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
                if additionalBotCount > 0 {
                    Text("+\(additionalBotCount)개 더")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                isHovering
                    ? labelColor.opacity(0.14)
                    : labelColor.opacity(0.08)
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(labelColor.opacity(0.25), lineWidth: 0.5)
            )
            .scaleEffect(isHovering ? 1.02 : 1.0)
            .animation(
                .spring(response: 0.4, dampingFraction: 0.85),
                value: isHovering
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                showPopover = false
                onOpenHub()
            }
        )
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            dockPopover
        }
        .help(tooltip)
        .accessibilityLabel("텔레그램 봇 상태 \(health.state.displayName)")
    }

    // MARK: - Status dot

    private var statusDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }

    // MARK: - Queue badge

    private var queueBadge: some View {
        HStack(spacing: 2) {
            Text("대기:")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
            Text("\(queueDepth)")
                .font(Theme.Typography.micro.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Theme.Color.warningStrong)
                .clipShape(Capsule())
        }
    }

    // MARK: - Popover

    private var dockPopover: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // 헤더
            HStack {
                Image(systemName: "paperplane.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Color.accent)
                Text("Telegram 봇 상태")
                    .font(Theme.Typography.label.weight(.semibold))
                    .foregroundStyle(Theme.Color.text)
                Spacer()
                Button {
                    showPopover = false
                    onOpenHub()
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Color.accent)
                }
                .buttonStyle(.plain)
                .help("Hub 열기")
            }

            Divider()

            // 상태 요약
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: 6) {
                    statusDot
                    Text(health.state.displayName)
                        .font(Theme.Typography.small.weight(.medium))
                        .foregroundStyle(Theme.Color.text)
                    if queueDepth > 0 {
                        Text("· 대기 \(queueDepth)건")
                            .font(Theme.Typography.small)
                            .foregroundStyle(.orange)
                    }
                }
                if let errorMsg = health.lastErrorMessage {
                    Text(errorMsg)
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .lineLimit(2)
                }
            }

            // 최근 에러 (있을 때만)
            if !recentErrors.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("최근 에러")
                        .font(Theme.Typography.micro.weight(.semibold))
                        .foregroundStyle(Theme.Color.textTertiary)
                    ForEach(recentErrors.prefix(3)) { entry in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(errorColor(entry.category))
                                .frame(width: 5, height: 5)
                            Text(entry.userFacingMessage)
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Color.textSecondary)
                                .lineLimit(1)
                            Spacer()
                            Text(relativeTime(entry.timestamp))
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Color.textTertiary)
                        }
                    }
                }
            }

            Divider()

            // 빠른 액션
            HStack {
                Spacer()
                Button("에러 로그") {
                    onOpenErrorLog()
                }
                .buttonStyle(.plain)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.accent)
                // ADR-141 — 접근성: 44×44 hit target + 명확한 label
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("봇 에러 로그 열기")
            }
        }
        .padding(Theme.Spacing.md)
        .frame(width: 300)
    }

    // MARK: - Computed properties

    private var primaryLabel: String {
        if let username = firstBotUsername {
            return "@\(username)"
        }
        return health.state.displayName
    }

    private var dotColor: Color {
        switch health.state {
        case .idle: return Theme.Color.textTertiary
        case .healthy: return Theme.Color.success
        case .degraded: return .orange
        case .failed: return Theme.Color.danger
        }
    }

    private var labelColor: Color { dotColor }

    private var lastActivityText: String? {
        guard let date = health.lastSuccessAt else { return nil }
        return relativeTime(date)
    }

    private var additionalBotCount: Int {
        max(0, botCount - 1)
    }

    private var tooltip: String {
        let base = "\(primaryLabel) — \(health.state.displayName)"
        if queueDepth > 0 {
            return "\(base). 대기 큐: \(queueDepth)건. 더블 클릭으로 Hub 열기."
        }
        return "\(base). 더블 클릭으로 Hub 열기."
    }

    // MARK: - Helpers

    private func relativeTime(_ date: Date) -> String {
        RelativeTime.format(date)
    }

    private func errorColor(_ category: TelegramErrorEntry.Category) -> Color {
        switch category {
        case .auth: return Theme.Color.danger
        case .rateLimit: return .orange
        case .network: return .yellow
        case .server: return Theme.Color.danger
        case .parsing: return .purple
        case .other: return Theme.Color.textTertiary
        }
    }
}
