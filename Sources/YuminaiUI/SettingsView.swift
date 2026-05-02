import SwiftUI
import AppKit
import YuminaiCore

/// 시크릿 항목의 현재 상태. SecretField 표시에 사용.
public enum SecretStatus: Sendable, Equatable {
    case notSet
    case set
    case error(String)
}

/// macOS 시스템 설정 룩 — `.formStyle(.grouped)` + `LabeledContent` 표준 패턴.
///
/// 모든 Section은 `Section { } header: { } footer: { }` 명시적 형식 사용 (macOS 26 ambiguity 회피).
public struct SettingsView: View {
    @Binding public var preferences: AppPreferences

    public let anthropicKeyStatus: SecretStatus
    public let telegramTokenStatus: SecretStatus

    public let onUpdateAnthropicKey: (String) -> Void
    public let onClearAnthropicKey: () -> Void
    public let onUpdateTelegramToken: (String) -> Void
    public let onClearTelegramToken: () -> Void
    public let onTestTelegramSend: () -> Void
    public let onSelectClaudeBinary: () -> Void
    public let onSelectCodexBinary: () -> Void
    public let onImportFromCokacdir: () -> Void

    /// **ADR-056 Phase 5** — Routing learning panel용 snapshot + callbacks.
    public let routingLearningSnapshot: RoutingLearningStore.Snapshot
    public let onUnmuteKeyword: (String) -> Void
    public let onAddCustomKeyword: (String, String) -> Void
    public let onRemoveCustomKeyword: (String, String) -> Void

    public init(
        preferences: Binding<AppPreferences>,
        anthropicKeyStatus: SecretStatus,
        telegramTokenStatus: SecretStatus,
        onUpdateAnthropicKey: @escaping (String) -> Void,
        onClearAnthropicKey: @escaping () -> Void,
        onUpdateTelegramToken: @escaping (String) -> Void,
        onClearTelegramToken: @escaping () -> Void,
        onTestTelegramSend: @escaping () -> Void,
        onSelectClaudeBinary: @escaping () -> Void,
        onSelectCodexBinary: @escaping () -> Void = {},
        onImportFromCokacdir: @escaping () -> Void = {},
        routingLearningSnapshot: RoutingLearningStore.Snapshot = RoutingLearningStore.Snapshot(mutedKeywords: [], cancelCounts: [:], customKeywords: [:]),
        onUnmuteKeyword: @escaping (String) -> Void = { _ in },
        onAddCustomKeyword: @escaping (String, String) -> Void = { _, _ in },
        onRemoveCustomKeyword: @escaping (String, String) -> Void = { _, _ in }
    ) {
        self._preferences = preferences
        self.anthropicKeyStatus = anthropicKeyStatus
        self.telegramTokenStatus = telegramTokenStatus
        self.onUpdateAnthropicKey = onUpdateAnthropicKey
        self.onClearAnthropicKey = onClearAnthropicKey
        self.onUpdateTelegramToken = onUpdateTelegramToken
        self.onClearTelegramToken = onClearTelegramToken
        self.onTestTelegramSend = onTestTelegramSend
        self.onSelectClaudeBinary = onSelectClaudeBinary
        self.onSelectCodexBinary = onSelectCodexBinary
        self.onImportFromCokacdir = onImportFromCokacdir
        self.routingLearningSnapshot = routingLearningSnapshot
        self.onUnmuteKeyword = onUnmuteKeyword
        self.onAddCustomKeyword = onAddCustomKeyword
        self.onRemoveCustomKeyword = onRemoveCustomKeyword
    }

    public var body: some View {
        TabView {
            generalTab
                .tabItem { Label("일반", systemImage: "gearshape") }
            modelTab
                .tabItem { Label("모델·모드", systemImage: "cpu") }
            editTab
                .tabItem { Label("편집", systemImage: "pencil.and.outline") }
            telegramTab
                .tabItem { Label("텔레그램", systemImage: "paperplane") }
            anthropicTab
                .tabItem { Label("Anthropic", systemImage: "key") }
            // ADR-056 Phase 5 — Routing learning tab
            routingLearningTab
                .tabItem { Label("Routing 학습", systemImage: "brain.head.profile") }
        }
        .frame(minWidth: 640, idealWidth: 720, maxWidth: 880,
               minHeight: 480, idealHeight: 560, maxHeight: 760)
    }

    /// **ADR-056 Phase 5** — Routing learning tab.
    private var routingLearningTab: some View {
        Form {
            Section {
                RoutingLearningPanel(
                    snapshot: routingLearningSnapshot,
                    onUnmute: onUnmuteKeyword,
                    onAddCustom: onAddCustomKeyword,
                    onRemoveCustom: onRemoveCustomKeyword
                )
            } header: {
                Text("Routing 자동 학습 (ADR-055/056)")
            } footer: {
                Text("자동 routing이 잘못 판단했다고 cancel하면 해당 keyword가 기록됩니다. 3회 도달 시 자동 mute. 사용자 정의 keyword는 base보다 우선 매칭됩니다.")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
        .padding()
    }

    // MARK: - 일반

    private var generalTab: some View {
        Form {
            Section {
                LabeledContent("실행 경로") {
                    HStack(spacing: 8) {
                        TextField("", text: $preferences.claudeBinaryPath)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                        Button("찾아보기…", action: onSelectClaudeBinary)
                    }
                }
            } header: {
                HStack(spacing: 4) {
                    Text("Claude CLI")
                    HelpHint(
                        "Yuminai가 채팅 전송 시 spawn하는 Claude Code CLI입니다. `which claude` 결과를 자동 감지합니다. Claude Code OAuth/로그인이 돼있으면 Anthropic API Key 입력은 비워둬도 됩니다.",
                        title: "Claude CLI 경로",
                        placement: .trailing
                    )
                }
            } footer: {
                Text("`which claude` 결과 또는 직접 지정한 경로를 사용합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("실행 경로") {
                    HStack(spacing: 8) {
                        TextField("", text: $preferences.codexBinaryPath)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                        Button("찾아보기…", action: onSelectCodexBinary)
                    }
                }
                LabeledContent("상태") {
                    HStack(spacing: 6) {
                        Image(systemName: codexInstalled ? "checkmark.circle.fill" : "questionmark.circle")
                            .foregroundStyle(codexInstalled ? .green : .secondary)
                        Text(codexInstalled ? "감지됨" : "미감지")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                HStack(spacing: 4) {
                    Text("Codex CLI")
                    HelpHint(
                        "OpenAI Codex CLI입니다. 설치돼 있으면 워크스페이스마다 toolbar에서 Claude ↔ Codex 전환이 가능합니다. 두 에이전트는 같은 프로젝트 폴더를 공유하므로 한 쪽이 만든 파일을 다른 쪽이 즉시 봅니다.",
                        title: "Codex CLI",
                        placement: .trailing
                    )
                }
            } footer: {
                Text("Codex가 설치돼 있으면 워크스페이스마다 ‘에이전트’를 Claude/Codex로 전환할 수 있어요. 같은 프로젝트 폴더 안에서 두 에이전트가 파일을 공유합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Vault 경로") {
                    TextField(
                        "비워두면 Obsidian 통합 비활성",
                        text: Binding(
                            get: { preferences.obsidianVaultPath ?? "" },
                            set: { preferences.obsidianVaultPath = $0.isEmpty ? nil : $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                }
            } header: {
                Text("Obsidian")
            } footer: {
                Text("v0.2에서 노트 인라인 주입에 사용됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("폰트 크기 보정") {
                    Stepper(
                        value: $preferences.fontSizeOffset,
                        in: -2...6
                    ) {
                        Text("\(preferences.fontSizeOffset >= 0 ? "+" : "")\(preferences.fontSizeOffset)pt")
                            .monospacedDigit()
                    }
                    .fixedSize()
                }
                Toggle(isOn: $preferences.showInspectorByDefault) {
                    Text("새 창 열 때 Inspector 표시")
                }
            } header: {
                Text("외관")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - 모델·모드

    private var modelTab: some View {
        Form {
            Section {
                Picker("모델", selection: $preferences.defaultSessionSettings.model) {
                    ForEach(ClaudeModel.allCases, id: \.self) { m in
                        Text("\(m.displayName) — \(m.subtitle)").tag(m)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("기본 모델")
            } footer: {
                Text(modelHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("권한 모드", selection: $preferences.defaultSessionSettings.permissionMode) {
                    ForEach(PermissionMode.allCases, id: \.self) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("기본 권한 모드")
            } footer: {
                Text(preferences.defaultSessionSettings.permissionMode.shortDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("강도", selection: $preferences.defaultSessionSettings.effortLevel) {
                    ForEach(EffortLevel.allCases, id: \.self) { e in
                        Text(e.displayName).tag(e)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("기본 추론 강도")
            } footer: {
                Text(preferences.defaultSessionSettings.effortLevel.shortDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: $preferences.defaultSessionSettings.includeHookEvents) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hook 이벤트 포함")
                        Text("Claude의 lifecycle 이벤트(PreToolUse 등)를 받습니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("최대 비용 (USD)") {
                    TextField(
                        "제한 없음",
                        value: $preferences.defaultSessionSettings.maxBudgetUSD,
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                }
            } header: {
                Text("실행 옵션")
            } footer: {
                Text("이 설정은 새 워크스페이스의 기본값입니다. 채팅 toolbar에서 세션별로 즉시 바꿀 수 있어요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - 편집

    private var editTab: some View {
        Form {
            Section {
                Toggle(isOn: $preferences.editPreferences.autoFormat) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("자동 포맷팅")
                        Text("Edit/Write 후 프로젝트의 포맷터를 자동 실행합니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $preferences.editPreferences.showDiffOnEdit) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("변경 후 diff 미리보기")
                        Text("파일이 수정되면 변경 내용을 인라인으로 보여줘요.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $preferences.editPreferences.autoBackup) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("편집 자동 백업")
                        Text("`.harness/backups`에 변경 전 사본을 저장합니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("편집 동작")
            } footer: {
                Text("실제 편집 정책은 Claude CLI의 권한 모드 + 워크스페이스 settings.json이 함께 결정합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - 텔레그램

    private var telegramTab: some View {
        Form {
            Section {
                Toggle(isOn: $preferences.telegramEnabled) {
                    Text("텔레그램 알림 켜기")
                }
                if preferences.telegramEnabled {
                    LabeledContent("Bot 토큰") {
                        SecretField(
                            status: telegramTokenStatus,
                            onSave: onUpdateTelegramToken,
                            onClear: onClearTelegramToken
                        )
                    }
                    if let source = preferences.telegramSourceLabel {
                        LabeledContent("토큰 출처") {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.down.app.fill")
                                    .foregroundStyle(.secondary)
                                Text("cokacdir — \(source)")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    LabeledContent("Chat ID") {
                        TextField(
                            "숫자",
                            text: Binding(
                                get: { preferences.telegramChatId.map(String.init) ?? "" },
                                set: { preferences.telegramChatId = Int64($0) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                    }
                    LabeledContent("허용 사용자 ID") {
                        TextField(
                            "쉼표로 구분",
                            text: Binding(
                                get: {
                                    preferences.telegramAllowedUserIds.map(String.init).joined(separator: ", ")
                                },
                                set: { newValue in
                                    preferences.telegramAllowedUserIds = newValue
                                        .split(separator: ",")
                                        .compactMap { Int64($0.trimmingCharacters(in: .whitespaces)) }
                                }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                    }
                    LabeledContent("연결 확인") {
                        Button("테스트 메시지 보내기", action: onTestTelegramSend)
                            .disabled(telegramTokenStatus != .set || preferences.telegramChatId == nil)
                    }
                }
            } header: {
                Text("연결")
            } footer: {
                Text("BotFather에서 받은 토큰과, 본인 Telegram 계정의 user ID를 입력하세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if preferences.telegramEnabled {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.down.on.square")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("이 PC의 cokacdir에서 봇 가져오기")
                                .font(.callout.weight(.medium))
                            Text("`~/.cokacdir/workspace/bot_settings.json`에서 봇과 chat id를 자동으로 채워요.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("열기…", action: onImportFromCokacdir)
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("cokacdir 통합")
                } footer: {
                    Text("⚠ cokacdir 봇 서버가 같은 토큰으로 동시에 실행 중이면 두 곳에서 Telegram update를 나눠 가져 메시지가 한쪽에만 도착할 수 있어요. Yuminai를 쓰는 동안에는 cokacdir의 해당 봇을 잠시 꺼두는 걸 권장해요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("작업 완료 시", isOn: $preferences.telegramAlertPolicy.sendOnComplete)
                    Toggle("에러 발생 시", isOn: $preferences.telegramAlertPolicy.sendOnError)
                    Toggle("의사결정 필요 시", isOn: $preferences.telegramAlertPolicy.sendOnDecisionRequired)
                } header: {
                    Text("알림 정책")
                }

                // ADR-046 — 외부 turn 안전장치
                Section {
                    Toggle(isOn: $preferences.telegramRemoteRequiresPlan) {
                        LabelWithHint(
                            "외부 turn은 Plan 모드 강제",
                            hint: "지하철에서 모바일로 명령 보낼 때 destructive 작업(rm, git reset 등)이 PC confirmation 없이 실행되지 않게 1턴 동안 plan-mode로 강제합니다. agent가 계획만 보여주면 사용자가 ‘진행해 줘’로 명시 승인."
                        )
                    }
                    Toggle(isOn: $preferences.telegramShowCostInline) {
                        LabelWithHint(
                            "비용 가시화 (/status)",
                            hint: "외부 turn 횟수 + 누적 비용 + 컨텍스트 % 를 /status 응답에 포함. 70%↑ 컨텍스트는 새 세션 권장 안내."
                        )
                    }
                    Toggle(isOn: $preferences.telegramForwardAssistant) {
                        LabelWithHint(
                            "Assistant 응답 forward",
                            hint: "Claude 응답 본문을 chunk로 텔레그램에 자동 전송. 끄면 알림(완료/에러)만 도착."
                        )
                    }
                    Toggle(isOn: $preferences.telegramForwardToolCalls) {
                        LabelWithHint(
                            "Tool 호출 요약 forward",
                            hint: "🔧 Bash / Edit / Write 등 도구 사용을 텔레그램에 표시. 위험 작업(rm -rf 등)은 🚨 알림으로 강조."
                        )
                    }
                } header: {
                    Text("외부 사용 안전")
                }
            }

            // ADR-049 — Harness 토글
            Section {
                Toggle(isOn: $preferences.harnessAutoRoutingEnabled) {
                    LabelWithHint(
                        "자동 routing (모델 선택)",
                        hint: "사용자 입력 keyword 분석 (한국어/영어) 후 적합한 모델로 자동 pane 전환. 예: ‘구현해줘’ → Codex / ‘리뷰’ → Claude. 전환 시 handoff prompt가 자동 inject돼 새 모델이 컨텍스트 catch up. 비용: 모델 전환마다 handoff prompt만큼 토큰 추가 (~4K tokens)."
                    )
                }
                if preferences.harnessAutoRoutingEnabled {
                    HStack {
                        LabelWithHint(
                            "Cancel countdown (초)",
                            hint: "ADR-051 — 자동 routing 전 사용자가 개입할 수 있는 시간. 0이면 즉시 전환, 3 권장. Esc 또는 banner 버튼으로 취소."
                        )
                        Spacer()
                        Stepper(value: $preferences.harnessRoutingCountdownSeconds, in: 0...10) {
                            Text("\(preferences.harnessRoutingCountdownSeconds)초").font(Theme.Typography.monoSmall)
                        }
                        .frame(width: 140)
                    }
                }
                Toggle(isOn: $preferences.harnessUIEnabled) {
                    LabelWithHint(
                        "Harness 통합 view (Inspector 탭)",
                        hint: "Inspector에 ‘Harness’ 탭 추가 — 모든 모델 응답을 단일 timeline으로 + agent badge + TaskGraph mini-map. 전통 multi-pane은 그대로 유지."
                    )
                }
                Toggle(isOn: $preferences.harnessInlineModeEnabled) {
                    LabelWithHint(
                        "Inline mode (메인 chat 교체)",
                        hint: "ADR-051 — 메인 chat area를 Harness 통합 view로 교체. multi-pane이 안 보임. ⌘K Command Palette에서 빠른 토글 가능."
                    )
                }
                // ADR-052 — 새 토글들
                Divider().padding(.vertical, 4)
                Toggle(isOn: $preferences.multiAgentParallelEnabled) {
                    LabelWithHint(
                        "Multi-agent 병렬 실행 (실험적)",
                        hint: "ADR-052 — 두 pane에서 dependency-free task 동시 실행 (BSP barrier merge 패턴, LangGraph/CrewAI 차용). Cognition Devin 권고: 비용 ~2x, 충돌 위험 있음. dependency 검증 후 ⌘K → ‘병렬 실행’으로 launch."
                    )
                }
                Toggle(isOn: $preferences.routingLogRawPrompts) {
                    LabelWithHint(
                        "Routing log: raw prompt 저장",
                        hint: "ADR-052 — 자동 routing 결정의 사용자 prompt를 disk에 보존 (privacy 위험). 끄면 80자 prefix만. OTel GenAI semconv ‘sensitive PII’ 가이드를 따라 default OFF."
                    )
                }
                HStack {
                    LabelWithHint(
                        "Routing log retention (일)",
                        hint: "ADR-052 — 메모리에 유지할 routing decision 일수. disk 파일은 별도 manual cleanup 필요."
                    )
                    Spacer()
                    Stepper(value: $preferences.routingLogRetentionDays, in: 1...30) {
                        Text("\(preferences.routingLogRetentionDays)일").font(Theme.Typography.monoSmall)
                    }
                    .frame(width: 140)
                }
            } header: {
                Text("Harness (다중 모델 오케스트레이션)")
            }

            // Agent chain (ADR-034 A1)
            Section {
                Toggle(isOn: $preferences.agentChainEnabled) {
                    LabelWithHint(
                        "agent → agent 자동 답장",
                        hint: "응답 본문에 `@<other>` 멘션이 있으면 자동으로 다음 turn을 그 pane에서 시작합니다. 진정한 multi-agent 협업이 가능하지만 무한 루프 위험이 있어 hop 제한을 둡니다."
                    )
                }
                if preferences.agentChainEnabled {
                    HStack {
                        LabelWithHint(
                            "최대 hop",
                            hint: "한 사용자 turn 후 자동 답장이 몇 번까지 chain할 수 있는지. 같은 pane 재방문은 자동 차단."
                        )
                        Spacer()
                        // ADR-042 R2.M20 — 5 hops은 토큰 폭발 위험 (각 hop 마다 응답 prepend 누적). 3으로 cap.
                        Stepper(value: $preferences.agentChainMaxHops, in: 1...3) {
                            Text("\(preferences.agentChainMaxHops) hop").font(Theme.Typography.monoSmall)
                        }
                        .frame(width: 140)
                    }
                }
            } header: {
                Text("Agent Chain")
            } footer: {
                Text("기본 OFF. 사용자 명시 입력만으로 작동하는 게 안전한 default. ON 시에도 hop 제한과 같은 pane 재방문 차단으로 무한 루프를 방지합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Anthropic

    private var anthropicTab: some View {
        Form {
            Section {
                LabeledContent("API Key") {
                    SecretField(
                        status: anthropicKeyStatus,
                        onSave: onUpdateAnthropicKey,
                        onClear: onClearAnthropicKey
                    )
                }
            } header: {
                Text("Anthropic API Key")
            } footer: {
                Text("Claude CLI에서 이미 OAuth/로그인이 되어있으면 비워두세요. (대부분의 경우 이게 더 편해요)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Helpers

    private var codexInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: preferences.codexBinaryPath)
    }

    private var modelHelp: String {
        let m = preferences.defaultSessionSettings.model
        return String(
            format: "%@ — 입력 $%.2f / 1M · 출력 $%.2f / 1M · 컨텍스트 %@",
            m.subtitle,
            m.inputPricePerMillion,
            m.outputPricePerMillion,
            m.contextWindowTokens.formattedShort
        )
    }
}

// MARK: - SecretField (LabeledContent 안의 컨트롤)

struct SecretField: View {
    let status: SecretStatus
    let onSave: (String) -> Void
    let onClear: () -> Void

    @State private var input: String = ""
    @State private var isEditing: Bool = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 8) {
                statusBadge
                if isEditing {
                    SecureField("토큰 입력", text: $input)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                    Button("저장") {
                        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSave(trimmed)
                        input = ""
                        isEditing = false
                    }
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("취소") {
                        input = ""
                        isEditing = false
                    }
                } else {
                    Button(status == .set ? "바꾸기…" : "넣기…") {
                        isEditing = true
                    }
                    if status == .set {
                        Button("지우기", role: .destructive, action: onClear)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .notSet:
            Text("아직 안 넣음")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .set:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Text("준비 완료")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .error(let msg):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}
