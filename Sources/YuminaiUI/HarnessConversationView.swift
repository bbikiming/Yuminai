import SwiftUI
import YuminaiCore

/// 다중 모델 통합 conversation view (ADR-049 Phase 5).
///
/// SharedConversationLog 기반 단일 timeline. 각 entry에 agent badge로 어느 모델이
/// 응답했는지 시각 구분. 전통 multi-pane은 유지 — 사용자가 Settings에서 toggle.
public struct HarnessConversationView: View {
    public let entries: [ConversationEntry]
    public let estimatedTotalTokens: Int
    public let agentResponseCounts: [AgentKind: Int]

    public init(
        entries: [ConversationEntry],
        estimatedTotalTokens: Int = 0,
        agentResponseCounts: [AgentKind: Int] = [:]
    ) {
        self.entries = entries
        self.estimatedTotalTokens = estimatedTotalTokens
        self.agentResponseCounts = agentResponseCounts
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            FlatHDivider()
            timeline
        }
        .background(Theme.Color.bg)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Color.accent)
            Text("Harness 통합 대화")
                .font(Theme.Typography.small.weight(.medium))
                .foregroundStyle(Theme.Color.text)
            // 모델별 응답 횟수
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
            Text("\(entries.count) entries · ~\(estimatedTotalTokens / 1000)K tokens")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Color.surface)
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
