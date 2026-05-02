import SwiftUI
import YuminaiCore

/// 다중 모델 통합 conversation view (ADR-049 Phase 5, ADR-050 cost meter).
///
/// SharedConversationLog 기반 단일 timeline. 각 entry에 agent badge로 어느 모델이
/// 응답했는지 시각 구분. 전통 multi-pane은 유지 — 사용자가 Settings에서 toggle.
///
/// **ADR-050 UX 강화** (Cursor cost meter pattern):
/// - 누적 토큰을 K 단위로 표시
/// - context window % 표시 (200K 기준)
/// - cost ($X.XXXX) 표시
public struct HarnessConversationView: View {
    public let entries: [ConversationEntry]
    public let estimatedTotalTokens: Int
    public let agentResponseCounts: [AgentKind: Int]
    public let sessionCostUSD: Double
    public let contextWindowSize: Int  // default 200K

    public init(
        entries: [ConversationEntry],
        estimatedTotalTokens: Int = 0,
        agentResponseCounts: [AgentKind: Int] = [:],
        sessionCostUSD: Double = 0,
        contextWindowSize: Int = 200_000
    ) {
        self.entries = entries
        self.estimatedTotalTokens = estimatedTotalTokens
        self.agentResponseCounts = agentResponseCounts
        self.sessionCostUSD = sessionCostUSD
        self.contextWindowSize = contextWindowSize
    }

    /// 컨텍스트 윈도우 사용 비율 (0.0~1.0).
    private var contextUsageRatio: Double {
        guard contextWindowSize > 0 else { return 0 }
        return min(1.0, Double(estimatedTotalTokens) / Double(contextWindowSize))
    }

    private var contextWarning: Bool { contextUsageRatio >= 0.7 }

    public var body: some View {
        VStack(spacing: 0) {
            header
            FlatHDivider()
            timeline
        }
        .background(Theme.Color.bg)
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.accent)
                Text("Harness 통합 대화")
                    .font(Theme.Typography.small.weight(.medium))
                    .foregroundStyle(Theme.Color.text)
                ForEach(Array(agentResponseCounts.keys.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { kind in
                    let count = agentResponseCounts[kind] ?? 0
                    HStack(spacing: 3) {
                        AgentBadge(agent: kind, size: .small)
                        Text("\(count)")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                }
                Spacer()
                Text("\(entries.count) entries")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Theme.Color.surface)
            // ADR-050 — Cost meter (Cursor 패턴): 항상 누적 토큰/비용/context % 표시
            costMeter
        }
    }

    private var costMeter: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge")
                .font(.system(size: 9))
                .foregroundStyle(Theme.Color.textTertiary)
            // 토큰 (K 단위)
            Text("~\(estimatedTotalTokens / 1000)K tokens")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textSecondary)
            // 비용
            if sessionCostUSD > 0 {
                Text(String(format: "$%.4f", sessionCostUSD))
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
            // 컨텍스트 윈도우 % progress bar
            HStack(spacing: 4) {
                Text("\(Int(contextUsageRatio * 100))%")
                    .font(Theme.Typography.micro.weight(contextWarning ? .medium : .regular))
                    .foregroundStyle(contextWarning ? Color.orange : Theme.Color.textTertiary)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.Color.borderSubtle)
                        .frame(width: 40, height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(contextWarning ? Color.orange : Theme.Color.accent)
                        .frame(width: 40 * contextUsageRatio, height: 4)
                }
                if contextWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.orange)
                        .help("컨텍스트 70% 초과 — 새 세션 권장")
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 4)
        .background(Theme.Color.surface.opacity(0.6))
    }

    @ViewBuilder
    private var timeline: some View {
        if entries.isEmpty {
            EmptyStateHint(
                icon: "bubble.left.and.bubble.right",
                title: "Harness 대화가 비어있어요",
                message: "사용자/agent 응답이 SharedLog에 기록되면 여기에 단일 timeline으로 표시돼요.\n자동 routing이 켜진 경우 모델 전환도 system entry로 표시됩니다."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(entries) { entry in
                            HarnessEntryRow(entry: entry).id(entry.id)
                        }
                    }
                    .padding(Theme.Spacing.md)
                }
                .onChange(of: entries.last?.id) { _, _ in
                    if let last = entries.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
}

/// 각 entry row — role 별 layout. user는 우측 정렬, agent/system은 좌측 정렬.
private struct HarnessEntryRow: View {
    let entry: ConversationEntry

    var body: some View {
        switch entry.role {
        case .user:
            userBubble
        case .agent:
            agentBubble
        case .system:
            systemBubble
        }
    }

    private var userBubble: some View {
        HStack(alignment: .top, spacing: 6) {
            Spacer()
            Text(entry.content)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Color.text)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Theme.Color.accentMuted)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .frame(maxWidth: 480, alignment: .trailing)
                .textSelection(.enabled)
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }

    private var agentBubble: some View {
        HStack(alignment: .top, spacing: 6) {
            if let kind = entry.agentKind {
                AgentBadge(agent: kind, size: .medium)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Color.accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                if let kind = entry.agentKind {
                    Text(kind.shortLabel.capitalized)
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.accent)
                }
                Text(entry.content)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Color.text)
                    .textSelection(.enabled)
                if let tokens = entry.tokenCount {
                    Text("\(tokens) output tokens")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .frame(maxWidth: 600, alignment: .leading)
            Spacer()
        }
    }

    private var systemBubble: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Color.textTertiary)
            Text(entry.content)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
                .italic()
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 4)
    }
}

/// 모델 별 색 배지 (claude/codex). size 변형.
public struct AgentBadge: View {
    public enum Size { case small, medium }
    let agent: AgentKind
    let size: Size

    public init(agent: AgentKind, size: Size = .medium) {
        self.agent = agent
        self.size = size
    }

    public var body: some View {
        Image(systemName: icon)
            .font(.system(size: size == .small ? 10 : 14, weight: .medium))
            .foregroundStyle(.white)
            .padding(size == .small ? 3 : 6)
            .background(badgeColor)
            .clipShape(Circle())
    }

    private var icon: String {
        switch agent {
        case .claude: return "c.circle.fill"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        }
    }

    private var badgeColor: Color {
        switch agent {
        case .claude: return Color(red: 0.85, green: 0.55, blue: 0.25)  // Claude 오렌지
        case .codex: return Color(red: 0.10, green: 0.65, blue: 0.45)   // Codex 그린
        }
    }
}
