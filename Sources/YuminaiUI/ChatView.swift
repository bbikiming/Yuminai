import SwiftUI
import YuminaiCore

/// 메시지 리스트만. Composer는 외부에서 별도 구성.
public struct ChatView: View {
    public let messages: [Message]
    public let emptyStateText: String
    /// 현재 active pane의 agent 이름 — assistant 메시지의 라벨로 사용 (ADR-032 U2).
    public let assistantLabel: String
    /// **ADR-087 Phase 4** — 현재 활성 agent (handoff chip + Codex 가용 판단용).
    public let currentAgent: AgentKind
    /// **ADR-087 Phase 4** — 다른 agent 가용 여부 (handoff chip enable).
    public let otherAgentAvailable: Bool
    /// **ADR-087 Phase 4** — Streaming 중이면 handoff chip 비활성 (response 미완성).
    public let isStreaming: Bool
    /// **ADR-087 Phase 4** — Handoff chip 클릭 콜백. (target agent, last message content) 전달.
    public let onHandoff: (AgentKind, String) -> Void

    public init(
        messages: [Message],
        emptyStateText: String = "여기서 새 작업을 시작해보세요.",
        assistantLabel: String = "Claude",
        currentAgent: AgentKind = .default,
        otherAgentAvailable: Bool = false,
        isStreaming: Bool = false,
        onHandoff: @escaping (AgentKind, String) -> Void = { _, _ in }
    ) {
        self.messages = messages
        self.emptyStateText = emptyStateText
        self.assistantLabel = assistantLabel
        self.currentAgent = currentAgent
        self.otherAgentAvailable = otherAgentAvailable
        self.isStreaming = isStreaming
        self.onHandoff = onHandoff
    }

    public var body: some View {
        if messages.isEmpty {
            EmptyChatView(text: emptyStateText)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        ForEach(messages) { message in
                            MessageBubble(message: message, assistantLabel: assistantLabel)
                                .id(message.id)
                        }
                        // ADR-087 Phase 4 — 마지막 메시지가 완료된 assistant면 handoff chip 표시
                        if shouldShowHandoffChip {
                            HandoffChip(
                                from: currentAgent,
                                to: otherAgent,
                                onTap: {
                                    onHandoff(otherAgent, lastAssistantContent)
                                }
                            )
                            .padding(.horizontal, Theme.Layout.contentPaddingH)
                            .padding(.top, 4)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.vertical, Theme.Spacing.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Theme.Color.bg)
                .onChange(of: messages.last?.id) { _, _ in
                    guard let last = messages.last else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onAppear {
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var otherAgent: AgentKind {
        currentAgent == .claude ? .codex : .claude
    }

    private var shouldShowHandoffChip: Bool {
        guard otherAgentAvailable, !isStreaming else { return false }
        guard let last = messages.last, last.role == .assistant, !last.content.isEmpty else { return false }
        return true
    }

    private var lastAssistantContent: String {
        messages.last(where: { $0.role == .assistant })?.content ?? ""
    }
}

// MARK: - ADR-087 Phase 4 — Handoff chip

/// 마지막 assistant 답변 아래 표시되는 "→ 다른 agent로 이어서" chip.
/// 클릭 시 그 답변 + 안내 prefix를 composer에 inject + agent 자동 전환.
struct HandoffChip: View {
    let from: AgentKind
    let to: AgentKind
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.Color.textSecondary)
                Text("이 답변을")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                Image(systemName: to.icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(to.brandColor)
                Text(to.displayName)
                    .font(Theme.Typography.small.weight(.semibold))
                    .foregroundStyle(to.brandColor)
                Text("로 이어서 검토")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(hovering ? to.brandMutedColor : Theme.Color.surface)
            .overlay(
                Capsule()
                    .stroke(to.brandColor.opacity(hovering ? 0.5 : 0.25), lineWidth: 0.7)
            )
            .clipShape(Capsule())
            .animation(.easeOut(duration: 0.10), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(from.displayName)의 답변을 \(to.displayName)에게 넘겨서 다른 관점으로 검토받기")
        .accessibilityLabel("\(to.displayName)에게 이 답변 넘기기")
        .accessibilityHint("\(from.displayName)의 답변을 input에 자동 prepend하고 \(to.displayName) agent로 전환합니다.")
    }
}

struct EmptyChatView: View {
    let text: String

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.Color.textTertiary)
            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Color.textSecondary)
            Text("⌘ Return 보내기 · ⌘D 사용량 · ⌘⌥I Inspector")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.bg)
    }
}
