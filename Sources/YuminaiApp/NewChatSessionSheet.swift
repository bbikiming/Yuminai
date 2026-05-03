import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-089 + ADR-090** — 새 ad-hoc 대화 세션 생성 sheet (정제된 GUI).
///
/// ## 워크스페이스 vs ChatSession 사용성 분리
///
/// 사용자가 헷갈리지 않게 sheet 상단에 명시적 안내 callout:
///
/// > "**대화 세션**은 빠른 질문/실험용 가벼운 대화입니다.
/// > 프로젝트 단위 작업은 새 워크스페이스를 만드세요."
///
/// ## 입력 흐름
///
/// 1. **세션 제목** (옵션, 비워두면 자동 생성)
/// 2. **어느 워크스페이스에서 실행할지** — RadioCardButton, **반드시** 1개 선택
/// 3. **Agent + Model** — Claude/Codex + 그 agent의 모델
/// 4. **권한 모드 + 추론 강도** (선택, DisclosureGroup)
struct NewChatSessionSheet: View {
    @Environment(AppModel.self) private var appModel

    @State private var title: String = ""
    @State private var selectedWorkspaceId: UUID? = nil
    @State private var selectedAgent: AgentKind = .default
    @State private var selectedClaudeModel: ClaudeModel = .sonnet
    @State private var selectedCodexModel: CodexModel = .default
    @State private var permissionMode: PermissionMode = .default
    @State private var effortLevel: EffortLevel = .medium
    @State private var advancedExpanded: Bool = false

    var body: some View {
        YuminaiSheet(width: 640, height: 700) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    HeaderHero(
                        icon: "bubble.left.and.text.bubble.right.fill",
                        iconTint: Theme.Color.accent,
                        title: "새 대화 세션",
                        subtitle: "Ad-hoc 질문이나 빠른 실험을 위한 가벼운 대화. 어느 워크스페이스 폴더에서 실행할지 반드시 선택하세요."
                    )

                    disambiguationCallout

                    titleCard
                    workspaceCard
                    agentCard
                    advancedCard
                }
                .padding(Theme.Spacing.xl)
            }
        } footer: {
            HStack(spacing: Theme.Spacing.md) {
                helpText
                Spacer()
                FlatButton("취소", variant: .secondary) {
                    appModel.showNewChatSessionSheet = false
                }
                .keyboardShortcut(.escape, modifiers: [])
                FlatButton("시작", variant: .primary) {
                    Task { await startChatSession() }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(selectedWorkspaceId == nil || appModel.workspaces.isEmpty)
            }
        }
    }

    // MARK: - Disambiguation callout

    private var disambiguationCallout: some View {
        InfoCallout(tone: .info) {
            VStack(alignment: .leading, spacing: 6) {
                Text("워크스페이스(프로젝트)와 다른 점")
                    .font(Theme.Typography.label.weight(.semibold))
                    .foregroundStyle(Theme.Color.text)
                comparisonRow(
                    icon: "folder.fill",
                    color: Theme.Color.accent,
                    label: "워크스페이스",
                    description: "장기 프로젝트 — 폴더 + 영구 history + agent별 설정 보존"
                )
                comparisonRow(
                    icon: "bubble.left.and.text.bubble.right.fill",
                    color: .orange,
                    label: "대화 세션",
                    description: "빠른 질문 — 제목 + 어느 폴더에서 실행할지만 정함"
                )
                Text("프로젝트 단위 작업이라면 사이드바에서 새 워크스페이스를 만드세요.")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(.top, 2)
            }
        }
    }

    private func comparisonRow(icon: String, color: Color, label: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 16, alignment: .center)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(Theme.Typography.small.weight(.semibold))
                    .foregroundStyle(Theme.Color.text)
                Text(description)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
    }

    // MARK: - Title card

    private var titleCard: some View {
        CardSection {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeaderRow(
                    icon: "text.cursor",
                    iconColor: Theme.Color.accent,
                    title: "세션 제목",
                    caption: "선택 — 비우면 자동"
                )
                TextField("예: 버그 디버깅, 리팩토링 아이디어, 빠른 질문…", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("세션 제목")
            }
        }
    }

    // MARK: - Workspace radio

    private var workspaceCard: some View {
        CardSection(
            style: selectedWorkspaceId == nil && !appModel.workspaces.isEmpty ? .accent : .subtle,
            accentColor: .orange
        ) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeaderRow(
                    icon: "folder.fill",
                    iconColor: Theme.Color.accent,
                    title: "실행 워크스페이스",
                    caption: "어느 폴더에서 실행할지",
                    required: true,
                    trailing: {
                        if selectedWorkspaceId == nil && !appModel.workspaces.isEmpty {
                            Label("필수 — 1개 선택", systemImage: "exclamationmark.triangle.fill")
                                .font(Theme.Typography.micro.weight(.medium))
                                .foregroundStyle(.orange)
                                .labelStyle(.titleAndIcon)
                        } else if let id = selectedWorkspaceId,
                                  let ws = appModel.workspaces.first(where: { $0.id == id }) {
                            Label(ws.name, systemImage: "checkmark.circle.fill")
                                .font(Theme.Typography.micro.weight(.medium))
                                .foregroundStyle(Theme.Color.success)
                                .labelStyle(.titleAndIcon)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 200)
                                .transition(.opacity.combined(with: .scale))
                        }
                    }
                )

                if appModel.workspaces.isEmpty {
                    AnimatedEmptyState(
                        icon: "folder.badge.questionmark",
                        iconTint: .orange,
                        title: "워크스페이스가 없어요",
                        message: "대화 세션은 워크스페이스(폴더) 안에서 실행돼요. 먼저 사이드바에서 워크스페이스를 만들어 주세요."
                    ) {
                        EmptyView()
                    }
                    .frame(minHeight: 160)
                } else {
                    LazyVStack(spacing: 6) {
                        ForEach(appModel.workspaces) { ws in
                            workspaceRadioRow(ws)
                        }
                    }
                }
            }
            .animation(.spring(response: 0.30, dampingFraction: 0.85), value: selectedWorkspaceId)
        }
    }

    private func workspaceRadioRow(_ ws: Workspace) -> some View {
        RadioCardButton(
            isSelected: selectedWorkspaceId == ws.id,
            accentColor: Theme.Color.accent,
            action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    selectedWorkspaceId = ws.id
                }
            }
        ) {
            HStack(alignment: .top, spacing: 8) {
                ZStack {
                    Circle()
                        .fill(ws.agentKind.brandMutedColor)
                        .frame(width: 26, height: 26)
                    Image(systemName: ws.agentKind.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ws.agentKind.brandColor)
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(ws.name)
                            .font(Theme.Typography.label.weight(.semibold))
                            .foregroundStyle(Theme.Color.text)
                        Text(ws.agentKind.displayName)
                            .font(Theme.Typography.micro)
                            .foregroundStyle(ws.agentKind.brandColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(ws.agentKind.brandMutedColor)
                            .clipShape(Capsule())
                    }
                    Text(ws.directoryPath)
                        .font(Theme.Typography.monoSmall)
                        .foregroundStyle(Theme.Color.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    // MARK: - Agent + Model

    private var agentCard: some View {
        CardSection {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeaderRow(
                    icon: "cpu",
                    iconColor: selectedAgent.brandColor,
                    title: "에이전트 + 모델",
                    caption: "이 세션에서 사용할 AI"
                )
                HStack(spacing: 8) {
                    agentToggleButton(.claude)
                    agentToggleButton(.codex)
                    Spacer()
                }
                modelPickerSection
                    .id(selectedAgent)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            .animation(.spring(response: 0.30, dampingFraction: 0.85), value: selectedAgent)
        }
    }

    private func agentToggleButton(_ agent: AgentKind) -> some View {
        let isSelected = selectedAgent == agent
        let isAvailable = agent == .claude || appModel.codexAvailable
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                selectedAgent = agent
            }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(agent.brandColor.opacity(isSelected ? 0.20 : 0.10))
                        .frame(width: 24, height: 24)
                    Image(systemName: agent.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(agent.brandColor)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(agent.displayName)
                        .font(Theme.Typography.label.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Theme.Color.text : Theme.Color.textSecondary)
                    Text(agent.tagline)
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 8)
            .background(isSelected ? agent.brandMutedColor : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(isSelected ? agent.brandColor.opacity(0.5) : Theme.Color.borderSubtle, lineWidth: isSelected ? 1.2 : 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .opacity(isAvailable ? 1.0 : 0.4)
            .scaleEffect(isSelected ? 1.0 : 0.98)
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .help(isAvailable ? agent.hint : "codex CLI 미감지 — 설정에서 경로 확인")
        .accessibilityLabel("\(agent.displayName) 선택")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var modelPickerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("모델")
                    .font(Theme.Typography.micro.weight(.medium))
                    .foregroundStyle(Theme.Color.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
            }
            if selectedAgent == .claude {
                Picker("Claude 모델", selection: $selectedClaudeModel) {
                    ForEach(ClaudeModel.allCases, id: \.self) { m in
                        Text("\(m.displayName) — \(m.subtitle)").tag(m)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                Text("입력 $\(String(format: "%.2f", selectedClaudeModel.inputPricePerMillion))/M · 출력 $\(String(format: "%.2f", selectedClaudeModel.outputPricePerMillion))/M")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
            } else {
                Picker("Codex 모델", selection: $selectedCodexModel) {
                    ForEach(CodexModel.knownCases, id: \.self) { m in
                        Text("\(m.displayName) — \(m.subtitle)").tag(m)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                if selectedCodexModel.inputPricePerMillion > 0 {
                    Text("입력 $\(String(format: "%.2f", selectedCodexModel.inputPricePerMillion))/M · 출력 $\(String(format: "%.2f", selectedCodexModel.outputPricePerMillion))/M")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
            }
        }
    }

    // MARK: - Advanced (permission + effort)

    private var advancedCard: some View {
        CardSection {
            DisclosureGroup(isExpanded: $advancedExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("권한 모드")
                            .font(Theme.Typography.small)
                            .foregroundStyle(Theme.Color.textSecondary)
                            .frame(width: 80, alignment: .leading)
                        Picker("권한 모드", selection: $permissionMode) {
                            ForEach(PermissionMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                    HStack {
                        Text("추론 강도")
                            .font(Theme.Typography.small)
                            .foregroundStyle(Theme.Color.textSecondary)
                            .frame(width: 80, alignment: .leading)
                        Picker("추론 강도", selection: $effortLevel) {
                            ForEach(EffortLevel.allCases, id: \.self) { level in
                                Text(level.displayName).tag(level)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }
                .padding(.top, 8)
            } label: {
                SectionHeaderRow(
                    icon: "slider.horizontal.3",
                    iconColor: Theme.Color.textSecondary,
                    title: "고급 설정",
                    caption: "권한 + 추론 강도"
                )
            }
            .animation(.spring(response: 0.30, dampingFraction: 0.85), value: advancedExpanded)
        }
    }

    // MARK: - Footer help

    @ViewBuilder
    private var helpText: some View {
        if appModel.workspaces.isEmpty {
            Label("워크스페이스를 먼저 만드세요", systemImage: "folder.badge.questionmark")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.danger)
        } else if selectedWorkspaceId == nil {
            Label("워크스페이스 1개를 선택해야 시작할 수 있어요", systemImage: "exclamationmark.triangle.fill")
                .font(Theme.Typography.micro)
                .foregroundStyle(.orange)
        } else {
            HStack(spacing: 6) {
                Image(systemName: selectedAgent.icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(selectedAgent.brandColor)
                Text("\(selectedAgent.displayName) · \(selectedAgent == .claude ? selectedClaudeModel.displayName : selectedCodexModel.displayName)")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textSecondary)
                Text("⌘↩ 시작")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
        }
    }

    // MARK: - Action

    private func startChatSession() async {
        guard let workspaceId = selectedWorkspaceId else { return }
        let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "새 대화 \(formatNowShort())"
            : title.trimmingCharacters(in: .whitespacesAndNewlines)
        let settings = SessionSettings(
            model: selectedClaudeModel,
            codexModel: selectedCodexModel,
            permissionMode: permissionMode,
            effortLevel: effortLevel
        )
        await appModel.createChatSession(
            title: finalTitle,
            workspaceId: workspaceId,
            agentKind: selectedAgent,
            settings: settings
        )
        appModel.showNewChatSessionSheet = false
    }

    private func formatNowShort() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }
}
