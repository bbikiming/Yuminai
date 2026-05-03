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
/// **ADR-070** — UX 라이팅 전면 개선 + Harness/Agent Chain을 텔레그램에서 분리한 "자동화" 탭으로 이동.
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
                .tabItem { Label("텔레그램 알림", systemImage: "paperplane") }
            // ADR-070 Phase 4 — Harness/Agent Chain은 텔레그램에서 분리 → "자동화" 탭
            automationTab
                .tabItem { Label("자동화", systemImage: "wand.and.stars") }
            anthropicTab
                .tabItem { Label("API 키", systemImage: "key") }
            // ADR-056 Phase 5 — Routing learning tab
            routingLearningTab
                .tabItem { Label("자동 선택 학습", systemImage: "brain.head.profile") }
        }
        // ADR-070 Phase 1 — 보조 모니터(960×640)에서도 잘림 없이 표시. maxHeight 제거.
        .frame(
            minWidth: Theme.Layout.settingsMinWidth,
            idealWidth: Theme.Layout.settingsIdealWidth,
            minHeight: Theme.Layout.settingsMinHeight,
            idealHeight: Theme.Layout.settingsIdealHeight
        )
    }

    /// **ADR-056 Phase 5 + ADR-070 Phase 2** — 자동 선택 학습 탭.
    /// Form + Section 패턴으로 다른 탭과 정렬 통일.
    private var routingLearningTab: some View {
        Form {
            Section {
                RoutingLearningPanel(
                    snapshot: routingLearningSnapshot,
                    onUnmute: onUnmuteKeyword,
                    onAddCustom: onAddCustomKeyword,
                    onRemoveCustom: onRemoveCustomKeyword
                )
                .padding(.vertical, 4)
            } header: {
                HStack(spacing: 4) {
                    Text("자동 모델 선택 학습")
                    HelpHint(
                        "사용자 입력 단어를 분석해 알맞은 모델로 자동 전환합니다. 잘못 판단했다면 취소해 주세요. 같은 단어에서 \(RoutingLearningStore.muteThreshold)회 취소되면 자동으로 차단됩니다.",
                        title: "자동 모델 선택이란?",
                        placement: .trailing
                    )
                }
            } footer: {
                Text("자동 전환이 잘못 판단했다고 취소하면 단어가 기록됩니다. \(RoutingLearningStore.muteThreshold)회 도달 시 자동으로 차단되며, 사용자 정의 단어는 기본 단어보다 우선 매칭됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
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
                        "Yuminai가 채팅 전송 시 실행하는 Claude Code CLI입니다. `which claude` 결과를 자동 감지합니다. Claude Code에 OAuth로 로그인되어 있으면 ‘API 키’ 탭은 비워둬도 됩니다.",
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
                        Text(codexInstalled ? "감지됨" : "감지되지 않음")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                HStack(spacing: 4) {
                    Text("Codex CLI")
                    HelpHint(
                        "OpenAI Codex CLI입니다. 설치되어 있으면 워크스페이스마다 toolbar에서 Claude ↔ Codex 전환이 가능합니다. 두 에이전트는 같은 프로젝트 폴더를 공유하므로 한 쪽이 만든 파일을 다른 쪽이 즉시 봅니다.",
                        title: "Codex CLI",
                        placement: .trailing
                    )
                }
            } footer: {
                Text("Codex가 설치되어 있으면 워크스페이스마다 ‘에이전트’를 Claude/Codex로 전환할 수 있어요. 같은 프로젝트 폴더 안에서 두 에이전트가 파일을 공유합니다.")
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
                Text("Obsidian 통합")
            } footer: {
                Text("노트를 채팅에 인라인으로 첨부할 수 있어요.")
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
                    Text("새 창 열 때 정보 패널 표시")
                }
            } header: {
                Text("외관")
            } footer: {
                Text("정보 패널은 컨텍스트 사용량, 비용, 도구 호출 내역을 우측에 보여줍니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                        Text("도구 사용 이벤트 받기")
                        Text("Claude의 lifecycle 이벤트(파일 편집 시작/종료 등)를 받습니다.")
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
                        Text("파일 편집 후 프로젝트의 포맷터를 자동 실행합니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $preferences.editPreferences.showDiffOnEdit) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("변경 후 비교 미리보기")
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
                Text("실제 편집 정책은 Claude CLI의 권한 모드와 워크스페이스의 settings.json이 함께 결정합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - 텔레그램 알림 (ADR-070 Phase 4 — Harness 분리 후 순수 Telegram만)

    private var telegramTab: some View {
        Form {
            Section {
                Toggle(isOn: $preferences.telegramEnabled) {
                    Text("텔레그램으로 알림 받기")
                }
                if preferences.telegramEnabled {
                    LabeledContent("봇 토큰") {
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
                Text("BotFather에서 받은 토큰과 본인 Telegram 계정의 사용자 ID를 입력하세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // ADR-059 Phase 2 — Multi-chat bindings 매니저
            if preferences.telegramEnabled && !preferences.telegramChatBindings.isEmpty {
                Section {
                    ForEach(preferences.telegramChatBindings.sorted(by: { $0.key < $1.key }), id: \.key) { chatKey, workspaceId in
                        HStack {
                            Text("Chat \(chatKey)")
                                .font(.system(.callout, design: .monospaced))
                            Image(systemName: "arrow.right")
                                .foregroundStyle(.secondary)
                            Text(workspaceId.uuidString.prefix(8) + "…")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("해제") {
                                preferences.telegramChatBindings.removeValue(forKey: chatKey)
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                        }
                    }
                } header: {
                    Text("워크스페이스별 채팅 연결")
                } footer: {
                    Text("각 Telegram 채팅에 다른 워크스페이스를 연결할 수 있습니다. /bind 명령으로 채팅에서 직접 등록할 수도 있어요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                    Text("⚠ cokacdir 봇 서버가 같은 토큰으로 동시에 실행 중이면 두 곳에서 Telegram 업데이트를 나눠 가져 메시지가 한쪽에만 도착할 수 있어요. Yuminai를 쓰는 동안에는 cokacdir의 해당 봇을 잠시 꺼두는 걸 권장해요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("작업 완료 시", isOn: $preferences.telegramAlertPolicy.sendOnComplete)
                    Toggle("에러 발생 시", isOn: $preferences.telegramAlertPolicy.sendOnError)
                    Toggle("의사결정 필요 시", isOn: $preferences.telegramAlertPolicy.sendOnDecisionRequired)
                } header: {
                    Text("알림 정책")
                } footer: {
                    Text("어떤 상황에서 텔레그램 알림을 받을지 선택하세요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // ADR-046 — 외부 turn 안전장치
                Section {
                    Toggle(isOn: $preferences.telegramRemoteRequiresPlan) {
                        LabelWithHint(
                            "외부 명령은 계획만 보여주기",
                            hint: "지하철에서 모바일로 명령을 보낼 때 위험한 작업(rm, git reset 등)이 PC 확인 없이 실행되지 않도록 1턴 동안 ‘계획’ 모드로 강제합니다. 에이전트가 계획만 보여주면 사용자가 ‘진행해 줘’로 명시 승인."
                        )
                    }
                    Toggle(isOn: $preferences.telegramShowCostInline) {
                        LabelWithHint(
                            "비용 가시화 (/status 명령)",
                            hint: "외부 명령 횟수 + 누적 비용 + 컨텍스트 % 를 /status 응답에 포함. 70% 이상 컨텍스트는 새 세션 권장 안내."
                        )
                    }
                    Toggle(isOn: $preferences.telegramForwardAssistant) {
                        LabelWithHint(
                            "에이전트 응답을 텔레그램으로 전송",
                            hint: "Claude 응답 본문을 chunk로 텔레그램에 자동 전송. 끄면 알림(완료/에러)만 도착."
                        )
                    }
                    Toggle(isOn: $preferences.telegramForwardToolCalls) {
                        LabelWithHint(
                            "도구 호출 요약을 텔레그램으로 전송",
                            hint: "🔧 Bash / Edit / Write 등 도구 사용을 텔레그램에 표시. 위험 작업(rm -rf 등)은 🚨 알림으로 강조."
                        )
                    }
                } header: {
                    Text("외부 사용 안전")
                } footer: {
                    Text("모바일에서 원격으로 작업을 보낼 때 안전장치를 설정합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - 자동화 (ADR-070 Phase 4 — Harness + Agent Chain 분리)
    //
    // 분리 근거 (UX 라이팅 문헌 + IA 원칙):
    // - 텔레그램 = "외부 알림 채널 (channel)"
    // - 자동화 = "내부 모델 동작 정책 (engine)"
    // - 두 도메인은 멘탈 모델이 다름 → 분리가 NN/g Heuristic #2
    //   ("Match between system and the real world")에 부합
    // - Apple Settings 패턴: Notifications / Privacy / General 등 mutually exclusive

    private var automationTab: some View {
        Form {
            Section {
                Toggle(isOn: $preferences.harnessAutoRoutingEnabled) {
                    LabelWithHint(
                        "자동 모델 선택",
                        hint: "사용자 입력 단어를 분석해 (한국어/영어 모두) 적합한 모델로 자동 전환합니다. 예: ‘구현해줘’ → Codex / ‘리뷰’ → Claude. 전환 시 이전 대화 요약(handoff prompt)이 자동으로 새 모델에 전달돼 컨텍스트가 끊기지 않아요. 비용: 모델 전환마다 약 4K 토큰 추가."
                    )
                }
                if preferences.harnessAutoRoutingEnabled {
                    HStack {
                        LabelWithHint(
                            "전환 대기 시간 (초)",
                            hint: "자동 전환 전에 사용자가 개입할 수 있는 시간입니다. 0이면 즉시 전환, 3초 권장. Esc 키 또는 banner 버튼으로 취소할 수 있어요."
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
                        "통합 타임라인 보기 (정보 패널 안)",
                        hint: "정보 패널에 ‘통합 보기’ 탭이 추가됩니다 — 모든 모델 응답을 하나의 타임라인으로 + 에이전트 뱃지 + 작업 그래프 미니맵. 기존 다중 화면은 그대로 유지."
                    )
                }
                Toggle(isOn: $preferences.harnessInlineModeEnabled) {
                    LabelWithHint(
                        "통합 보기를 메인 화면으로 사용",
                        hint: "메인 채팅 영역을 통합 보기로 교체합니다. 다중 화면이 보이지 않아요. ⌘K 명령 팔레트에서 빠른 토글이 가능합니다."
                    )
                }
                // ADR-052 — 새 토글들
                Divider().padding(.vertical, 4)
                Toggle(isOn: $preferences.multiAgentParallelEnabled) {
                    LabelWithHint(
                        "여러 에이전트 동시 실행 (실험적)",
                        hint: "두 화면에서 의존성 없는 작업을 동시에 실행합니다 (BSP barrier merge 패턴). 비용 약 2배, 충돌 위험 있음. 의존성 검증 후 ⌘K → ‘병렬 실행’으로 시작하세요."
                    )
                }
                Toggle(isOn: $preferences.routingLogRawPrompts) {
                    LabelWithHint(
                        "전환 결정 로그에 원본 입력 저장",
                        hint: "자동 전환 결정의 사용자 입력을 디스크에 보존합니다 (개인정보 위험). 끄면 80자 미리보기만 저장. 기본값은 OFF (보안 권장)."
                    )
                }
                // ADR-059 Phase 2 — Auto new session slider
                HStack {
                    LabelWithHint(
                        "자동 새 세션 (컨텍스트 %)",
                        hint: "컨텍스트가 이 % 도달하면 활성 화면을 자동으로 새로고침(clean start)합니다. 0%로 두면 비활성. 위험: 진행 중 작업 컨텍스트 손실 가능."
                    )
                    Spacer()
                    let pct = Binding<Double>(
                        get: { (preferences.autoNewSessionContextThreshold ?? 0) * 100 },
                        set: { preferences.autoNewSessionContextThreshold = $0 == 0 ? nil : $0 / 100 }
                    )
                    Slider(value: pct, in: 0...95, step: 5)
                        .frame(width: 180)
                    Text(preferences.autoNewSessionContextThreshold.map { "\(Int($0 * 100))%" } ?? "꺼짐")
                        .font(Theme.Typography.monoSmall)
                        .frame(width: 50, alignment: .trailing)
                }
                // ADR-066 Phase 2 — Anomaly Z-score threshold slider
                HStack {
                    LabelWithHint(
                        "이상치 감지 민감도",
                        hint: "텔레그램 사용량 대시보드의 이상치 감지 민감도. 2.0=95% (기본, 표준), 3.0=99.7% (덜 민감), 1.5=87% (더 민감)."
                    )
                    Spacer()
                    Slider(value: $preferences.anomalyZScoreThreshold, in: 1.0...4.0, step: 0.1)
                        .frame(width: 180)
                    Text(String(format: "%.1f", preferences.anomalyZScoreThreshold))
                        .font(Theme.Typography.monoSmall)
                        .frame(width: 50, alignment: .trailing)
                }
                HStack {
                    LabelWithHint(
                        "전환 결정 보존 기간 (일)",
                        hint: "메모리에 유지할 자동 전환 결정 일수입니다. 디스크 파일은 별도로 수동 정리 필요."
                    )
                    Spacer()
                    Stepper(value: $preferences.routingLogRetentionDays, in: 1...30) {
                        Text("\(preferences.routingLogRetentionDays)일").font(Theme.Typography.monoSmall)
                    }
                    .frame(width: 140)
                }
            } header: {
                HStack(spacing: 4) {
                    Text("다중 모델 자동 전환")
                    HelpHint(
                        "Claude / Codex 등 여러 LLM을 같은 워크스페이스에서 자동으로 전환하며 사용하는 기능입니다. 입력 단어에 따라 적합한 모델이 선택됩니다.",
                        title: "다중 모델 자동 전환이란?",
                        placement: .trailing
                    )
                }
            } footer: {
                Text("이 기능은 여러 LLM을 자동으로 전환하며 사용하는 고급 기능입니다. 처음에는 ‘자동 모델 선택’만 켜고 사용해 보세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Agent chain (ADR-034 A1)
            Section {
                Toggle(isOn: $preferences.agentChainEnabled) {
                    LabelWithHint(
                        "에이전트 간 자동 답장",
                        hint: "응답 본문에 `@<다른에이전트>` 멘션이 있으면 자동으로 다음 답장을 그 에이전트가 작성합니다. 진정한 multi-agent 협업이 가능하지만 무한 루프 위험이 있어 횟수 제한을 둡니다."
                    )
                }
                if preferences.agentChainEnabled {
                    HStack {
                        LabelWithHint(
                            "최대 연쇄 횟수",
                            hint: "한 사용자 입력 후 자동 답장이 몇 번까지 이어질 수 있는지. 같은 에이전트 재방문은 자동 차단."
                        )
                        Spacer()
                        // ADR-042 R2.M20 — 5 hops은 토큰 폭발 위험. 3으로 cap.
                        Stepper(value: $preferences.agentChainMaxHops, in: 1...3) {
                            Text("\(preferences.agentChainMaxHops)회").font(Theme.Typography.monoSmall)
                        }
                        .frame(width: 140)
                    }
                }
            } header: {
                HStack(spacing: 4) {
                    Text("에이전트 자동 답장")
                    HelpHint(
                        "한 에이전트의 응답에 다른 에이전트가 자동으로 답장하는 기능입니다. 예: Claude 응답에 ‘@codex 구현해줘’가 있으면 Codex가 자동으로 답장.",
                        title: "에이전트 자동 답장이란?",
                        placement: .trailing
                    )
                }
            } footer: {
                Text("기본값은 꺼짐입니다. 사용자 입력만으로 작동하는 게 안전한 기본 설정입니다. 켜더라도 횟수 제한과 같은 에이전트 재방문 차단으로 무한 루프를 방지합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - API 키 (이전 "Anthropic")

    private var anthropicTab: some View {
        Form {
            Section {
                LabeledContent("API 키") {
                    SecretField(
                        status: anthropicKeyStatus,
                        onSave: onUpdateAnthropicKey,
                        onClear: onClearAnthropicKey
                    )
                }
            } header: {
                Text("Anthropic API 키")
            } footer: {
                Text("Claude CLI에 OAuth로 이미 로그인되어 있다면 비워두세요. (대부분의 경우 이게 더 편해요)")
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
                    Button(status == .set ? "바꾸기…" : "입력하기…") {
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
            Text("아직 설정하지 않음")
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
