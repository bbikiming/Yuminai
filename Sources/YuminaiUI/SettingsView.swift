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
    public let onImportFromCokacdir: () -> Void

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
        onImportFromCokacdir: @escaping () -> Void = {}
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
        self.onImportFromCokacdir = onImportFromCokacdir
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
        }
        .frame(minWidth: 640, idealWidth: 720, maxWidth: 880,
               minHeight: 480, idealHeight: 560, maxHeight: 760)
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
                Text("Claude CLI")
            } footer: {
                Text("`which claude` 결과 또는 직접 지정한 경로를 사용합니다.")
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
