import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-089 + ADR-090 + ADR-091** — 새 대화 세션 sheet (3-mode + 정제된 GUI).
///
/// ## 3가지 모드 (라디오 1개 선택)
///
/// 1. **기존 워크스페이스** — 이미 만든 폴더에서 작업
/// 2. **새 워크스페이스** — 새 폴더 inline 생성 + 즉시 시작
/// 3. **자유 대화** — 경로 없이 순수 Q&A (나중에 워크스페이스로 옮길 수 있음)
///
/// ## ADR-091 변경 (기존 ADR-089 대체)
/// - workspaceId가 옵션이 됨 (자유 대화 가능)
/// - 모드 selector가 sheet 상단에 위치 (선택에 따라 sub-form 변경)
/// - 고급 설정: DisclosureGroup 대신 custom Button + 큰 클릭 영역 + 부드러운 expansion
/// - 외부 ScrollView 1개만 (이중 스크롤 제거)
struct NewChatSessionSheet: View {
    @Environment(AppModel.self) private var appModel

    // 공통
    @State private var title: String = ""
    @State private var selectedAgent: AgentKind = .default
    @State private var selectedClaudeModel: ClaudeModel = .sonnet
    @State private var selectedCodexModel: CodexModel = .default
    @State private var permissionMode: PermissionMode = .default
    @State private var effortLevel: EffortLevel = .medium
    @State private var advancedExpanded: Bool = false

    // 모드 + 모드별 입력
    @State private var sourceMode: ChatSessionSource = .existingWorkspace
    @State private var selectedWorkspaceId: UUID? = nil  // .existingWorkspace
    @State private var newWorkspaceName: String = ""     // .newWorkspace
    @State private var newWorkspacePath: String = ""     // .newWorkspace

    var body: some View {
        YuminaiSheet(width: 660, height: 720) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    HeaderHero(
                        icon: "bubble.left.and.text.bubble.right.fill",
                        iconTint: Theme.Color.accent,
                        title: "새 대화 세션",
                        subtitle: "어떤 환경에서 대화할지 1개 선택하세요. 기존 프로젝트 / 새 프로젝트 / 자유 대화 중에서요."
                    )

                    sourceModeCard
                    titleCard
                    sourceSpecificCard
                    agentCard
                    advancedCard
                }
                .padding(Theme.Spacing.xl)
            }
            .scrollIndicators(.visible)
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
                .disabled(!canStart)
            }
        }
    }

    // MARK: - 1) Source mode (3-radio)

    private var sourceModeCard: some View {
        CardSection {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeaderRow(
                    icon: "list.bullet.rectangle.fill",
                    iconColor: Theme.Color.accent,
                    title: "어떤 모드로 시작할까요?",
                    caption: "1개 선택",
                    required: true
                )
                VStack(spacing: 6) {
                    ForEach(ChatSessionSource.allCases) { mode in
                        sourceModeRadio(mode)
                    }
                }
            }
        }
    }

    private func sourceModeRadio(_ mode: ChatSessionSource) -> some View {
        let isSelected = sourceMode == mode
        let isDisabled = mode == .existingWorkspace && appModel.workspaces.isEmpty
        return RadioCardButton(
            isSelected: isSelected,
            accentColor: tintForMode(mode),
            action: {
                if !isDisabled {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                        sourceMode = mode
                    }
                }
            }
        ) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(tintForMode(mode).opacity(isSelected ? 0.18 : 0.10))
                        .frame(width: 30, height: 30)
                    Image(systemName: mode.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tintForMode(mode))
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(mode.displayName)
                            .font(Theme.Typography.label.weight(.semibold))
                            .foregroundStyle(Theme.Color.text)
                        if isDisabled {
                            Text("워크스페이스 없음")
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Color.textTertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Theme.Color.surface)
                                .clipShape(Capsule())
                        }
                    }
                    Text(mode.subtitle)
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1.0)
    }

    private func tintForMode(_ mode: ChatSessionSource) -> Color {
        switch mode {
        case .existingWorkspace: return Theme.Color.accent
        case .newWorkspace: return Theme.Color.success
        case .freeChat: return .purple
        }
    }

    // MARK: - 2) Title

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

    // MARK: - 3) Source-specific input

    @ViewBuilder
    private var sourceSpecificCard: some View {
        switch sourceMode {
        case .existingWorkspace:
            existingWorkspaceCard
        case .newWorkspace:
            newWorkspaceCard
        case .freeChat:
            freeChatCard
        }
    }

    private var existingWorkspaceCard: some View {
        CardSection(
            style: selectedWorkspaceId == nil && !appModel.workspaces.isEmpty ? .accent : .subtle,
            accentColor: .orange
        ) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeaderRow(
                    icon: "folder.fill",
                    iconColor: Theme.Color.accent,
                    title: "워크스페이스 선택",
                    caption: appModel.workspaces.isEmpty ? nil : "\(appModel.workspaces.count)개",
                    required: !appModel.workspaces.isEmpty
                ) {
                    if let id = selectedWorkspaceId,
                       let ws = appModel.workspaces.first(where: { $0.id == id }) {
                        Label(ws.name, systemImage: "checkmark.circle.fill")
                            .font(Theme.Typography.micro.weight(.medium))
                            .foregroundStyle(Theme.Color.success)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 200)
                    }
                }

                if appModel.workspaces.isEmpty {
                    AnimatedEmptyState(
                        icon: "folder.badge.questionmark",
                        iconTint: .orange,
                        title: "워크스페이스가 없어요",
                        message: "위에서 '새 워크스페이스' 또는 '자유 대화' 모드를 선택해 주세요."
                    ) {
                        EmptyView()
                    }
                    .frame(minHeight: 140)
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

    // MARK: - newWorkspace 모드

    private var newWorkspaceCard: some View {
        CardSection(
            style: !canStartNewWorkspace ? .accent : .subtle,
            accentColor: .orange
        ) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeaderRow(
                    icon: "folder.badge.plus",
                    iconColor: Theme.Color.success,
                    title: "새 워크스페이스",
                    caption: "이름 + 폴더 경로",
                    required: true
                )
                VStack(alignment: .leading, spacing: 6) {
                    Text("워크스페이스 이름")
                        .font(Theme.Typography.micro.weight(.medium))
                        .foregroundStyle(Theme.Color.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.4)
                    TextField("예: emotion-lab", text: $newWorkspaceName)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("폴더 경로")
                        .font(Theme.Typography.micro.weight(.medium))
                        .foregroundStyle(Theme.Color.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.4)
                    HStack(spacing: 6) {
                        TextField("/Users/you/Projects/my-project", text: $newWorkspacePath)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .font(.system(size: 12, design: .monospaced))
                        Button {
                            choosePath()
                        } label: {
                            Label("선택", systemImage: "folder")
                                .labelStyle(.titleAndIcon)
                                .font(Theme.Typography.small)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Theme.Color.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                        .stroke(Theme.Color.borderSubtle, lineWidth: 0.5)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                        }
                        .buttonStyle(.plain)
                        .help("폴더 선택…")
                    }
                    Text("존재하지 않는 경로면 자동으로 만들어요. 보통 git repo 루트를 선택하세요.")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
            }
        }
    }

    private func choosePath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "워크스페이스 폴더를 선택하거나 새로 만드세요"
        if panel.runModal() == .OK, let url = panel.url {
            newWorkspacePath = url.path
            if newWorkspaceName.isEmpty {
                newWorkspaceName = url.lastPathComponent
            }
        }
    }

    private var canStartNewWorkspace: Bool {
        !newWorkspaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !newWorkspacePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - freeChat 모드

    private var freeChatCard: some View {
        CardSection(style: .accent, accentColor: .purple) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeaderRow(
                    icon: "bubble.left.and.bubble.right.fill",
                    iconColor: .purple,
                    title: "자유 대화",
                    caption: "경로 미지정"
                )
                InfoCallout(tone: .info) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("자유 대화는 어떻게 다른가요?")
                            .font(Theme.Typography.small.weight(.semibold))
                            .foregroundStyle(Theme.Color.text)
                        bulletText("폴더 cwd 없음 — 파일 작업/도구 실행 없이 순수 Q&A")
                        bulletText("나중에 사이드바 우클릭 → '워크스페이스 지정'으로 작업 환경에 attach 가능")
                        bulletText("질문/브레인스토밍/모델 비교에 적합")
                    }
                }
            }
        }
    }

    private func bulletText(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
            Text(text)
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 4) Agent + Model

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

    // MARK: - 5) 고급 설정 (custom expansion — DisclosureGroup 대체)

    private var advancedCard: some View {
        CardSection {
            VStack(alignment: .leading, spacing: 0) {
                // 헤더 — 전체 row를 큰 버튼으로 (클릭 영역 ↑)
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        advancedExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Theme.Color.textSecondary.opacity(0.12))
                                .frame(width: 22, height: 22)
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.Color.textSecondary)
                        }
                        Text("고급 설정")
                            .font(Theme.Typography.label.weight(.semibold))
                            .foregroundStyle(Theme.Color.text)
                        Text("권한 + 추론 강도")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textTertiary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.Color.textTertiary)
                            .rotationEffect(.degrees(advancedExpanded ? 0 : -90))
                            .animation(.spring(response: 0.30, dampingFraction: 0.7), value: advancedExpanded)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("권한 모드와 추론 강도 설정")
                .accessibilityLabel("고급 설정 \(advancedExpanded ? "닫기" : "열기")")

                if advancedExpanded {
                    VStack(alignment: .leading, spacing: 12) {
                        Divider()
                            .padding(.vertical, 4)
                        advancedRow(
                            label: "권한 모드",
                            picker: AnyView(
                                Picker("권한 모드", selection: $permissionMode) {
                                    ForEach(PermissionMode.allCases, id: \.self) { mode in
                                        Text(mode.displayName).tag(mode)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            ),
                            hint: permissionMode.shortDescription
                        )
                        advancedRow(
                            label: "추론 강도",
                            picker: AnyView(
                                Picker("추론 강도", selection: $effortLevel) {
                                    ForEach(EffortLevel.allCases, id: \.self) { level in
                                        Text(level.displayName).tag(level)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            ),
                            hint: effortLevel.shortDescription
                        )
                    }
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func advancedRow(label: String, picker: AnyView, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(Theme.Typography.small.weight(.medium))
                    .foregroundStyle(Theme.Color.textSecondary)
                    .frame(width: 90, alignment: .leading)
                picker
                Spacer()
            }
            Text(hint)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
                .padding(.leading, 90)
        }
    }

    // MARK: - Footer help + canStart

    private var canStart: Bool {
        switch sourceMode {
        case .existingWorkspace:
            return selectedWorkspaceId != nil && !appModel.workspaces.isEmpty
        case .newWorkspace:
            return canStartNewWorkspace
        case .freeChat:
            return true  // 자유 대화는 추가 입력 없이 즉시 시작 가능
        }
    }

    @ViewBuilder
    private var helpText: some View {
        switch sourceMode {
        case .existingWorkspace:
            if appModel.workspaces.isEmpty {
                Label("워크스페이스가 없으니 다른 모드를 선택하세요", systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(.orange)
            } else if selectedWorkspaceId == nil {
                Label("워크스페이스 1개를 선택하세요", systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(.orange)
            } else {
                summaryLabel
            }
        case .newWorkspace:
            if !canStartNewWorkspace {
                Label("이름과 경로를 입력하세요", systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(.orange)
            } else {
                summaryLabel
            }
        case .freeChat:
            summaryLabel
        }
    }

    private var summaryLabel: some View {
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

    // MARK: - Action

    private func startChatSession() async {
        let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "새 대화 \(formatNowShort())"
            : title.trimmingCharacters(in: .whitespacesAndNewlines)
        let settings = SessionSettings(
            model: selectedClaudeModel,
            codexModel: selectedCodexModel,
            permissionMode: permissionMode,
            effortLevel: effortLevel
        )

        var workspaceId: UUID? = nil
        switch sourceMode {
        case .existingWorkspace:
            workspaceId = selectedWorkspaceId
        case .newWorkspace:
            // 새 워크스페이스 inline 생성
            let trimmedName = newWorkspaceName.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedPath = newWorkspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty, !trimmedPath.isEmpty else { return }
            // 폴더 없으면 생성 시도
            try? FileManager.default.createDirectory(
                atPath: trimmedPath, withIntermediateDirectories: true
            )
            let newWs = Workspace(
                name: trimmedName,
                directoryPath: trimmedPath,
                agentKind: selectedAgent
            )
            await appModel.createWorkspace(newWs)
            workspaceId = newWs.id
        case .freeChat:
            workspaceId = nil  // 자유 대화 — 경로 없음
        }

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
