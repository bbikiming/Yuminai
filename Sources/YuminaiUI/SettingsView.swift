import SwiftUI
import AppKit
import YuminaiCore

/// 시크릿 항목의 현재 상태. SecretField 표시에 사용.
public enum SecretStatus: Sendable, Equatable {
    case notSet
    case set
    case error(String)
}

/// 앱 글로벌 설정 화면. macOS의 Settings scene으로 노출.
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

    public init(
        preferences: Binding<AppPreferences>,
        anthropicKeyStatus: SecretStatus,
        telegramTokenStatus: SecretStatus,
        onUpdateAnthropicKey: @escaping (String) -> Void,
        onClearAnthropicKey: @escaping () -> Void,
        onUpdateTelegramToken: @escaping (String) -> Void,
        onClearTelegramToken: @escaping () -> Void,
        onTestTelegramSend: @escaping () -> Void,
        onSelectClaudeBinary: @escaping () -> Void
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
    }

    public var body: some View {
        TabView {
            generalTab.tabItem { Label("일반", systemImage: "gear") }
            modelTab.tabItem { Label("모델·모드", systemImage: "cpu") }
            editTab.tabItem { Label("편집", systemImage: "pencil.and.outline") }
            telegramTab.tabItem { Label("Telegram", systemImage: "paperplane") }
            anthropicTab.tabItem { Label("Anthropic", systemImage: "key") }
        }
        .frame(width: 640, height: 540)
        .padding()
    }

    private var generalTab: some View {
        Form {
            Section("Claude CLI") {
                HStack {
                    TextField("실행 경로", text: $preferences.claudeBinaryPath)
                        .textFieldStyle(.roundedBorder)
                    Button("선택…", action: onSelectClaudeBinary)
                }
            }
            Section("Obsidian (옵션)") {
                TextField(
                    "Vault 경로 (미정이면 비워두세요)",
                    text: Binding(
                        get: { preferences.obsidianVaultPath ?? "" },
                        set: { preferences.obsidianVaultPath = $0.isEmpty ? nil : $0 }
                    )
                )
                .textFieldStyle(.roundedBorder)
                Text("v0.2에서 노트 인라인 주입에 사용됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("외관") {
                Stepper(value: $preferences.fontSizeOffset, in: -2...6) {
                    Text("폰트 크기 보정: \(preferences.fontSizeOffset >= 0 ? "+" : "")\(preferences.fontSizeOffset)")
                }
                Toggle("새 창 열 때 Inspector 자동 표시", isOn: $preferences.showInspectorByDefault)
            }
        }
    }

    private var modelTab: some View {
        Form {
            Section("기본 모델") {
                Picker("모델", selection: $preferences.defaultSessionSettings.model) {
                    ForEach(ClaudeModel.allCases, id: \.self) { m in
                        Text("\(m.displayName) — \(m.subtitle)").tag(m)
                    }
                }
                Text(modelHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("기본 권한 모드") {
                Picker("Permission mode", selection: $preferences.defaultSessionSettings.permissionMode) {
                    ForEach(PermissionMode.allCases, id: \.self) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                Text(preferences.defaultSessionSettings.permissionMode.shortDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("기본 추론 강도 (effort)") {
                Picker("Effort", selection: $preferences.defaultSessionSettings.effortLevel) {
                    ForEach(EffortLevel.allCases, id: \.self) { e in
                        Text(e.displayName).tag(e)
                    }
                }
                Text(preferences.defaultSessionSettings.effortLevel.shortDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("실행 옵션") {
                Toggle("Hook 이벤트 포함 (--include-hook-events)", isOn: $preferences.defaultSessionSettings.includeHookEvents)
                HStack {
                    Text("최대 비용 (USD)")
                    Spacer()
                    TextField(
                        "제한 없음",
                        value: $preferences.defaultSessionSettings.maxBudgetUSD,
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                }
            }
            Text("이 설정은 새 워크스페이스의 *기본값*입니다. 채팅 toolbar에서 세션별로 즉시 변경 가능.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, Theme.Spacing.sm)
        }
    }

    private var editTab: some View {
        Form {
            Section("편집 동작") {
                Toggle("Edit/Write 후 자동 포맷터 실행", isOn: $preferences.editPreferences.autoFormat)
                Toggle("변경 후 diff 미리보기 표시", isOn: $preferences.editPreferences.showDiffOnEdit)
                Toggle("편집 자동 백업 (.harness/backups)", isOn: $preferences.editPreferences.autoBackup)
            }
            Text("실제 편집 정책은 Claude CLI의 권한 모드 + 워크스페이스 settings.json이 함께 결정합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, Theme.Spacing.sm)
        }
    }

    private var telegramTab: some View {
        Form {
            Section("연결") {
                Toggle("Telegram 통합 활성화", isOn: $preferences.telegramEnabled)
                if preferences.telegramEnabled {
                    SecretField(
                        title: "Bot 토큰",
                        status: telegramTokenStatus,
                        onSave: onUpdateTelegramToken,
                        onClear: onClearTelegramToken
                    )
                    TextField(
                        "Chat ID (숫자)",
                        text: Binding(
                            get: { preferences.telegramChatId.map(String.init) ?? "" },
                            set: { preferences.telegramChatId = Int64($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    TextField(
                        "허용 사용자 ID들 (쉼표로 구분)",
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
                    Button("테스트 메시지 전송", action: onTestTelegramSend)
                        .disabled(telegramTokenStatus != .set || preferences.telegramChatId == nil)
                }
            }
            if preferences.telegramEnabled {
                Section("알림 정책") {
                    Toggle("작업 완료 시", isOn: $preferences.telegramAlertPolicy.sendOnComplete)
                    Toggle("에러 시", isOn: $preferences.telegramAlertPolicy.sendOnError)
                    Toggle("의사결정 필요 시", isOn: $preferences.telegramAlertPolicy.sendOnDecisionRequired)
                }
            }
        }
    }

    private var anthropicTab: some View {
        Form {
            Section("Anthropic API Key (옵션)") {
                Text("Claude CLI에서 이미 OAuth/로그인이 되어있으면 비워두세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecretField(
                    title: "API Key",
                    status: anthropicKeyStatus,
                    onSave: onUpdateAnthropicKey,
                    onClear: onClearAnthropicKey
                )
            }
        }
    }

    private var modelHelp: String {
        let m = preferences.defaultSessionSettings.model
        return String(
            format: "%@ — input $%.2f / 1M · output $%.2f / 1M · ctx %@",
            m.subtitle,
            m.inputPricePerMillion,
            m.outputPricePerMillion,
            m.contextWindowTokens.formattedShort
        )
    }
}

/// 시크릿 입력 필드. 값 자체를 표시하지 않고 상태만 보여준다.
struct SecretField: View {
    let title: String
    let status: SecretStatus
    let onSave: (String) -> Void
    let onClear: () -> Void

    @State private var input: String = ""
    @State private var isEditing: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text(title)
                    .font(Theme.Typography.label)
                Spacer()
                statusBadge
            }
            if isEditing {
                HStack {
                    SecureField("토큰 입력", text: $input)
                        .textFieldStyle(.roundedBorder)
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
                }
            } else {
                HStack {
                    Button(status == .set ? "변경…" : "설정…") {
                        isEditing = true
                    }
                    if status == .set {
                        Button("삭제", role: .destructive, action: onClear)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .notSet:
            Text("미설정")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .set:
            Text("설정됨")
                .font(.caption)
                .foregroundStyle(Theme.Color.success)
        case .error(let msg):
            Text(msg)
                .font(.caption)
                .foregroundStyle(Theme.Color.error)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
