import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-089** — 새 ad-hoc 대화 세션 생성 sheet.
///
/// ## 워크스페이스 vs ChatSession 사용성 분리
///
/// 사용자가 헷갈리지 않게 sheet 상단에 명시적 안내:
///
/// > "**대화 세션**은 빠른 질문/실험용 가벼운 대화입니다.
/// > 프로젝트 단위 작업은 새 워크스페이스를 만드세요."
///
/// ## 입력 흐름
///
/// 1. **세션 제목** (옵션, 비워두면 자동 생성)
/// 2. **어느 워크스페이스에서 실행할지** — 라디오 리스트, **반드시** 1개 선택
///    (선택 안 하면 "시작" 버튼 disabled + 안내)
/// 3. **Agent + Model** — Claude/Codex + 그 agent의 모델
/// 4. **권한 모드 + 추론 강도** (선택)
///
/// 시작 누르면: `AppModel.createChatSession()` → 자동 active로 전환 → main chat 영역이 새 session 표시.
struct NewChatSessionSheet: View {
    @Environment(AppModel.self) private var appModel

    @State private var title: String = ""
    @State private var selectedWorkspaceId: UUID? = nil
    @State private var selectedAgent: AgentKind = .default
    @State private var selectedClaudeModel: ClaudeModel = .sonnet
    @State private var selectedCodexModel: CodexModel = .default
    @State private var permissionMode: PermissionMode = .default
    @State private var effortLevel: EffortLevel = .medium

    var body: some View {
        YuminaiSheet(width: 620, height: 640) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                disambiguationCallout
                Divider()
                titleSection
                workspaceSection
                agentSection
                advancedSection
            }
            .padding(Theme.Spacing.xl)
        } footer: {
            HStack {
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

    // MARK: - Header + 분리 안내

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .foregroundStyle(Theme.Color.accent)
                    .accessibilityHidden(true)
                Text("새 대화 세션")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
            }
            Text("Ad-hoc 질문이나 빠른 실험용 가벼운 대화. 어느 워크스페이스 폴더에서 실행할지 반드시 선택하세요.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var disambiguationCallout: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Theme.Color.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("워크스페이스(프로젝트)와 다른 점")
                    .font(Theme.Typography.label.weight(.semibold))
                    .foregroundStyle(Theme.Color.text)
                Text("• **워크스페이스** = 장기 프로젝트 (폴더 + 영구 history + agent별 설정 보존)")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                Text("• **대화 세션** = 빠른 질문 (제목 + 어느 폴더에서 실행할지만 정함)")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                Text("프로젝트 단위 작업이라면 사이드바에서 새 워크스페이스를 만드세요.")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(.top, 2)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.accentMuted)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    // MARK: - Title

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("세션 제목 (선택)")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
                .textCase(.uppercase)
                .tracking(0.6)
            TextField("예: 버그 디버깅, 리팩토링 아이디어, 빠른 질문…", text: $title)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("세션 제목")
            Text("비워두면 첫 메시지를 기준으로 자동 생성됩니다.")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
        }
    }

    // MARK: - Workspace 라디오 (필수)

    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("실행 워크스페이스")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Text("*")
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Color.danger)
                Spacer()
                if selectedWorkspaceId == nil && !appModel.workspaces.isEmpty {
                    Text("필수 — 1개 선택")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.warning)
                }
            }

            if appModel.workspaces.isEmpty {
                emptyWorkspaceState
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(appModel.workspaces) { ws in
                            workspaceRadioRow(ws)
                        }
                    }
                }
                .frame(maxHeight: 220)
                .background(Theme.Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
        }
    }

    private var emptyWorkspaceState: some View {
        VStack(spacing: 6) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 24))
                .foregroundStyle(Theme.Color.textTertiary)
            Text("워크스페이스가 없어요")
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Color.text)
            Text("대화 세션은 워크스페이스(폴더) 안에서 실행되어야 해요.\n먼저 사이드바에서 워크스페이스를 만들어 주세요.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.lg)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private func workspaceRadioRow(_ ws: Workspace) -> some View {
        let isSelected = selectedWorkspaceId == ws.id
        return Button {
            selectedWorkspaceId = ws.id
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Theme.Color.accent : Theme.Color.textTertiary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(ws.name)
                            .font(Theme.Typography.label.weight(.semibold))
                            .foregroundStyle(Theme.Color.text)
                        Image(systemName: ws.agentKind.icon)
                            .font(.system(size: 9))
                            .foregroundStyle(ws.agentKind.brandColor)
                        Text(ws.agentKind.displayName)
                            .font(Theme.Typography.micro)
                            .foregroundStyle(ws.agentKind.brandColor)
                    }
                    Text(ws.directoryPath)
                        .font(Theme.Typography.monoSmall)
                        .foregroundStyle(Theme.Color.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 10)
            .background(isSelected ? Theme.Color.accentMuted : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(ws.name) 워크스페이스 선택")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Agent + Model

    private var agentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("에이전트 + 모델")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
                .textCase(.uppercase)
                .tracking(0.6)
            HStack(spacing: 8) {
                agentButton(.claude)
                if appModel.codexAvailable {
                    agentButton(.codex)
                } else {
                    agentButton(.codex).disabled(true).opacity(0.5)
                }
                Spacer()
            }
            // Model picker (active agent에 따라)
            if selectedAgent == .claude {
                Picker("Claude 모델", selection: $selectedClaudeModel) {
                    ForEach(ClaudeModel.allCases, id: \.self) { m in
                        Text("\(m.displayName) — \(m.subtitle)").tag(m)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            } else {
                Picker("Codex 모델", selection: $selectedCodexModel) {
                    ForEach(CodexModel.knownCases, id: \.self) { m in
                        Text("\(m.displayName) — \(m.subtitle)").tag(m)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }

    private func agentButton(_ agent: AgentKind) -> some View {
        let isSelected = selectedAgent == agent
        return Button {
            selectedAgent = agent
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(agent.brandColor)
                    .frame(width: 8, height: 8)
                Image(systemName: agent.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(agent.brandColor)
                Text(agent.displayName)
                    .font(Theme.Typography.label.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.Color.text : Theme.Color.textSecondary)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs + 1)
            .background(isSelected ? agent.brandMutedColor : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .stroke(isSelected ? agent.brandColor.opacity(0.4) : Theme.Color.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Advanced (permission + effort)

    private var advancedSection: some View {
        DisclosureGroup("고급 설정 (권한 + 추론 강도)") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("권한 모드", selection: $permissionMode) {
                    ForEach(PermissionMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Picker("추론 강도", selection: $effortLevel) {
                    ForEach(EffortLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
            }
            .padding(.top, 6)
        }
        .font(Theme.Typography.small)
    }

    // MARK: - Footer

    @ViewBuilder
    private var helpText: some View {
        if appModel.workspaces.isEmpty {
            Text("워크스페이스를 먼저 만드세요")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.danger)
        } else if selectedWorkspaceId == nil {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.Color.warning)
                Text("워크스페이스를 1개 선택해야 시작할 수 있어요")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        } else {
            EmptyView()
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
