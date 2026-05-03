import SwiftUI
import YuminaiCore

// MARK: - ADR-087 Phase 3 — Agent 색상 / 통합 picker UI helper

extension AgentKind {
    /// Agent별 브랜드 색상 (Composer strip / 메시지 마커 / picker badge).
    public var brandColor: Color {
        switch self {
        case .claude: return Theme.Color.agentClaude
        case .codex: return Theme.Color.agentCodex
        }
    }

    public var brandMutedColor: Color {
        switch self {
        case .claude: return Theme.Color.agentClaudeMuted
        case .codex: return Theme.Color.agentCodexMuted
        }
    }

    /// 한 줄 짧은 한국어 캐치프레이즈 (UnifiedAgentModelPicker 헤더용).
    public var tagline: String {
        switch self {
        case .claude: return "설계·리뷰에 강함"
        case .codex: return "빠른 코드 생성"
        }
    }
}

// MARK: - ADR-087 Phase 2 — UnifiedAgentModelPicker
//
// Composer footer의 큰 트리거 버튼 — 한 클릭에 agent + model 동시 선택.
// 메뉴 구조:
//   🟠 Claude (현재 선택 시 ✓)
//     · Haiku — 빠름·저비용
//     · Sonnet — 균형
//     · Opus — 최고 성능
//   ─────
//   🟢 Codex (Codex 미감지 시 disabled + hint)
//     · (현재 model picker UI에서는 동일 ClaudeModel enum 사용 — Codex CLI가 sonnet/opus
//        alias를 자체 매핑하는 것으로 가정. 향후 별도 CodexModel enum 분리 가능.)
//     · Sonnet equivalent
//     · Opus equivalent

public struct UnifiedAgentModelPicker: View {
    @Binding public var agent: AgentKind
    @Binding public var claudeModel: ClaudeModel
    @Binding public var codexModel: CodexModel
    public let codexAvailable: Bool
    public let onAgentChange: (AgentKind) -> Void
    public let onClaudeModelChange: (ClaudeModel) -> Void
    public let onCodexModelChange: (CodexModel) -> Void

    public init(
        agent: Binding<AgentKind>,
        claudeModel: Binding<ClaudeModel>,
        codexModel: Binding<CodexModel>,
        codexAvailable: Bool,
        onAgentChange: @escaping (AgentKind) -> Void = { _ in },
        onClaudeModelChange: @escaping (ClaudeModel) -> Void = { _ in },
        onCodexModelChange: @escaping (CodexModel) -> Void = { _ in }
    ) {
        self._agent = agent
        self._claudeModel = claudeModel
        self._codexModel = codexModel
        self.codexAvailable = codexAvailable
        self.onAgentChange = onAgentChange
        self.onClaudeModelChange = onClaudeModelChange
        self.onCodexModelChange = onCodexModelChange
    }

    public var body: some View {
        Menu {
            // Claude 섹션
            Section("Claude · \(AgentKind.claude.tagline)") {
                ForEach(ClaudeModel.allCases, id: \.self) { m in
                    Button {
                        selectClaude(m)
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text("\(m.displayName) — \(m.subtitle)")
                                Text("$\(String(format: "%.2f", m.inputPricePerMillion))/M in · $\(String(format: "%.2f", m.outputPricePerMillion))/M out")
                                    .font(.caption)
                            }
                        } icon: {
                            if agent == .claude && claudeModel == m {
                                Image(systemName: "checkmark")
                            } else {
                                Image(systemName: AgentKind.claude.icon)
                            }
                        }
                    }
                }
            }
            // ADR-088 — Codex 섹션은 CodexModel (OpenAI 모델들)로 교체
            Section("Codex · \(AgentKind.codex.tagline)") {
                if !codexAvailable {
                    Text("codex CLI 미감지 — 설정에서 경로 확인")
                        .font(.caption)
                }
                ForEach(CodexModel.knownCases, id: \.self) { m in
                    Button {
                        selectCodex(m)
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text("\(m.displayName) — \(m.subtitle)")
                                Text("$\(String(format: "%.2f", m.inputPricePerMillion))/M in · $\(String(format: "%.2f", m.outputPricePerMillion))/M out")
                                    .font(.caption)
                            }
                        } icon: {
                            if agent == .codex && codexModel == m {
                                Image(systemName: "checkmark")
                            } else {
                                Image(systemName: AgentKind.codex.icon)
                            }
                        }
                    }
                    .disabled(!codexAvailable)
                }
                // 사용자 정의 (~/.codex/config.toml의 model 필드와 동일하게)
                if case .custom(let raw) = codexModel {
                    Divider()
                    Button {
                        selectCodex(.custom(raw))
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text(raw)
                                Text("사용자 정의 (~/.codex/config.toml)")
                                    .font(.caption)
                            }
                        } icon: {
                            Image(systemName: agent == .codex ? "checkmark" : "person.crop.circle.badge.questionmark")
                        }
                    }
                    .disabled(!codexAvailable)
                }
            }
        } label: {
            UnifiedAgentTrigger(
                agent: agent,
                modelLabel: agent == .claude ? claudeModel.displayName : codexModel.displayName
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Agent와 모델을 한 번에 선택. 같은 워크스페이스에서 Claude ⇄ Codex 자유롭게 전환 가능.")
        .accessibilityLabel("현재 \(agent.displayName) · \(agent == .claude ? claudeModel.displayName : codexModel.displayName)")
        .accessibilityHint("클릭하면 다른 agent + 모델 조합으로 한 번에 전환할 수 있습니다.")
    }

    private func selectClaude(_ newModel: ClaudeModel) {
        let agentChanged = agent != .claude
        let modelChanged = claudeModel != newModel
        agent = .claude
        claudeModel = newModel
        if agentChanged { onAgentChange(.claude) }
        if modelChanged { onClaudeModelChange(newModel) }
    }

    private func selectCodex(_ newModel: CodexModel) {
        let agentChanged = agent != .codex
        let modelChanged = codexModel != newModel
        agent = .codex
        codexModel = newModel
        if agentChanged { onAgentChange(.codex) }
        if modelChanged { onCodexModelChange(newModel) }
    }
}

/// UnifiedAgentModelPicker의 trigger label — Composer footer에 큰 시각적 anchor.
/// **ADR-088 + ADR-090** — model 표시 라벨을 string으로 받아 ClaudeModel/CodexModel 둘 다 지원.
/// 정교화: 그라디언트 배경 + spring scale + pulsing dot.
private struct UnifiedAgentTrigger: View {
    let agent: AgentKind
    let modelLabel: String
    @State private var hovering = false
    @State private var pressed = false

    var body: some View {
        HStack(spacing: 7) {
            // Agent 색상 dot — pulsing animation
            ZStack {
                Circle()
                    .fill(agent.brandColor.opacity(0.30))
                    .frame(width: 14, height: 14)
                    .scaleEffect(hovering ? 1.4 : 1.0)
                    .opacity(hovering ? 0.0 : 0.8)
                    .animation(
                        hovering
                            ? .easeOut(duration: 0.6).repeatForever(autoreverses: false)
                            : .easeOut(duration: 0.20),
                        value: hovering
                    )
                Circle()
                    .fill(agent.brandColor)
                    .frame(width: 8, height: 8)
            }
            .accessibilityHidden(true)
            Image(systemName: agent.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(agent.brandColor)
                .symbolRenderingMode(.hierarchical)
            Text(agent.displayName)
                .font(Theme.Typography.label.weight(.semibold))
                .foregroundStyle(Theme.Color.text)
            Text("·")
                .foregroundStyle(Theme.Color.textTertiary)
            Text(modelLabel)
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Color.textSecondary)
                .contentTransition(.opacity)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(hovering ? agent.brandColor : Theme.Color.textTertiary)
                .padding(.leading, 2)
        }
        .padding(.horizontal, Theme.Spacing.md - 1)
        .padding(.vertical, Theme.Spacing.xs + 2)
        .background(triggerBackground)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(agent.brandColor.opacity(hovering ? 0.5 : 0.20), lineWidth: hovering ? 1.2 : 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .scaleEffect(pressed ? 0.97 : 1.0)
        .shadow(color: agent.brandColor.opacity(hovering ? 0.20 : 0.08), radius: hovering ? 6 : 2, y: 1)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.spring(response: 0.20, dampingFraction: 0.7), value: pressed)
        .onHover { hovering = $0 }
    }

    private var triggerBackground: some View {
        LinearGradient(
            colors: hovering
                ? [agent.brandMutedColor, agent.brandMutedColor.opacity(0.7)]
                : [agent.brandMutedColor.opacity(0.6), agent.brandMutedColor.opacity(0.4)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// Composer footer 모델 picker — Claude Code 스타일 PickerMenu.
public struct ModelPicker: View {
    @Binding public var selection: ClaudeModel
    public var onChange: (ClaudeModel) -> Void

    public init(selection: Binding<ClaudeModel>, onChange: @escaping (ClaudeModel) -> Void = { _ in }) {
        self._selection = selection
        self.onChange = onChange
    }

    public var body: some View {
        PickerMenu(
            sections: [
                PickerSection(
                    title: "모델",
                    shortcutHint: ["⇧", "⌘", "M"],
                    items: ClaudeModel.allCases.enumerated().map { idx, model in
                        PickerItem(
                            label: model.displayName,
                            subtitle: model.subtitle,
                            isSelected: model == selection,
                            shortcutHint: "\(idx + 1)"
                        ) {
                            selection = model
                            onChange(model)
                        }
                    }
                )
            ]
        ) {
            PickerTriggerLabel(label: "모델", value: selection.rawValue)
        }
    }
}

/// 권한 모드 picker.
public struct ModePicker: View {
    @Binding public var selection: PermissionMode
    public var onChange: (PermissionMode) -> Void

    public init(selection: Binding<PermissionMode>, onChange: @escaping (PermissionMode) -> Void = { _ in }) {
        self._selection = selection
        self.onChange = onChange
    }

    public var body: some View {
        PickerMenu(
            sections: [
                PickerSection(
                    title: "권한 모드",
                    items: PermissionMode.allCases.map { mode in
                        PickerItem(
                            label: mode.displayName,
                            subtitle: mode.shortDescription,
                            isSelected: mode == selection
                        ) {
                            selection = mode
                            onChange(mode)
                        }
                    }
                )
            ],
            menuWidth: 320
        ) {
            PickerTriggerLabel(label: "권한", value: selection.rawValue)
        }
    }
}

/// 추론 강도 picker.
public struct EffortPicker: View {
    @Binding public var selection: EffortLevel
    public var onChange: (EffortLevel) -> Void

    public init(selection: Binding<EffortLevel>, onChange: @escaping (EffortLevel) -> Void = { _ in }) {
        self._selection = selection
        self.onChange = onChange
    }

    public var body: some View {
        PickerMenu(
            sections: [
                PickerSection(
                    title: "작업량",
                    shortcutHint: ["⇧", "⌘", "E"],
                    items: EffortLevel.allCases.map { level in
                        PickerItem(
                            label: level.displayName,
                            subtitle: level.shortDescription,
                            isSelected: level == selection
                        ) {
                            selection = level
                            onChange(level)
                        }
                    }
                )
            ]
        ) {
            PickerTriggerLabel(label: "강도", value: selection.rawValue)
        }
    }
}

// MARK: - Trigger label (Composer footer 안의 inline button)

struct PickerTriggerLabel: View {
    let label: String
    let value: String

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .foregroundStyle(Theme.Color.textTertiary)
            Text("·")
                .foregroundStyle(Theme.Color.textTertiary)
            Text(value)
                .foregroundStyle(Theme.Color.text)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(hovering ? Theme.Color.accent : Theme.Color.textTertiary)
                .padding(.leading, 1)
        }
        .font(Theme.Typography.label)
        .padding(.horizontal, Theme.Spacing.md - 2)
        .padding(.vertical, Theme.Spacing.xs + 1)
        .background(hovering ? Theme.Color.surfaceHi : .clear)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .animation(.easeOut(duration: 0.10), value: hovering)
        .onHover { hovering = $0 }
    }
}
