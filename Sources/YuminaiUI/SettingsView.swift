import SwiftUI
import AppKit
import YuminaiCore

/// 시크릿 항목의 현재 상태. SecretField 표시에 사용.
public enum SecretStatus: Sendable, Equatable {
    case notSet
    case set
    case error(String)
}

/// openclaw CLI 감지 상태 — Telegram 탭 UI 표시용. AppModel이 OpenClawDetector → 이 struct로 변환해 주입.
public struct OpenClawUIStatus: Sendable, Equatable {
    public let installed: Bool
    public let version: String?
    public let telegramActive: Bool
    public let message: String

    public init(installed: Bool, version: String?, telegramActive: Bool, message: String) {
        self.installed = installed
        self.version = version
        self.telegramActive = telegramActive
        self.message = message
    }

    public static let unknown = OpenClawUIStatus(
        installed: false,
        version: nil,
        telegramActive: false,
        message: "‘새로고침’을 눌러 openclaw 상태를 감지해보세요."
    )
}

/// macOS 시스템 설정 룩 — `.formStyle(.grouped)` + `LabeledContent` 표준 패턴.
///
/// 모든 Section은 `Section { } header: { } footer: { }` 명시적 형식 사용 (macOS 26 ambiguity 회피).
public struct SettingsView: View {
    @Binding public var preferences: AppPreferences

    public let anthropicKeyStatus: SecretStatus
    public let telegramTokenStatus: SecretStatus
    public let openClawStatus: OpenClawUIStatus?

    public let onUpdateAnthropicKey: (String) -> Void
    public let onClearAnthropicKey: () -> Void
    public let onUpdateTelegramToken: (String) -> Void
    public let onClearTelegramToken: () -> Void
    public let onTestTelegramSend: () -> Void
    public let onSelectClaudeBinary: () -> Void
    public let onSelectOpenClawBinary: () -> Void
    public let onRefreshOpenClawStatus: () -> Void

    public init(
        preferences: Binding<AppPreferences>,
        anthropicKeyStatus: SecretStatus,
        telegramTokenStatus: SecretStatus,
        openClawStatus: OpenClawUIStatus? = nil,
        onUpdateAnthropicKey: @escaping (String) -> Void,
        onClearAnthropicKey: @escaping () -> Void,
        onUpdateTelegramToken: @escaping (String) -> Void,
        onClearTelegramToken: @escaping () -> Void,
        onTestTelegramSend: @escaping () -> Void,
        onSelectClaudeBinary: @escaping () -> Void,
        onSelectOpenClawBinary: @escaping () -> Void = {},
        onRefreshOpenClawStatus: @escaping () -> Void = {}
    ) {
        self._preferences = preferences
        self.anthropicKeyStatus = anthropicKeyStatus
        self.telegramTokenStatus = telegramTokenStatus
        self.openClawStatus = openClawStatus
        self.onUpdateAnthropicKey = onUpdateAnthropicKey
        self.onClearAnthropicKey = onClearAnthropicKey
        self.onUpdateTelegramToken = onUpdateTelegramToken
        self.onClearTelegramToken = onClearTelegramToken
        self.onTestTelegramSend = onTestTelegramSend
        self.onSelectClaudeBinary = onSelectClaudeBinary
        self.onSelectOpenClawBinary = onSelectOpenClawBinary
        self.onRefreshOpenClawStatus = onRefreshOpenClawStatus
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
                    LabeledContent("연결 방식") {
                        Picker("", selection: $preferences.telegramUseOpenClaw) {
                            Text("Bot 토큰 직접 입력").tag(false)
                            Text("openclaw에 위임").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    if preferences.telegramUseOpenClaw {
                        openClawConnectionFields
                    } else {
                        directTokenFields
                    }

                    LabeledContent("Chat ID") {
                        TextField(
                            preferences.telegramUseOpenClaw ? "Telegram 숫자 chat id (알림 수신처)" : "숫자",
                            text: Binding(
                                get: { preferences.telegramChatId.map(String.init) ?? "" },
                                set: { preferences.telegramChatId = Int64($0) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220)
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
                            .disabled(!testButtonEnabled)
                    }
                }
            } header: {
                Text("연결")
            } footer: {
                Text(connectionFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if preferences.telegramEnabled {
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

    private var directTokenFields: some View {
        LabeledContent("Bot 토큰") {
            SecretField(
                status: telegramTokenStatus,
                onSave: onUpdateTelegramToken,
                onClear: onClearTelegramToken
            )
        }
    }

    @ViewBuilder
    private var openClawConnectionFields: some View {
        LabeledContent("openclaw 경로") {
            HStack(spacing: 6) {
                TextField("/opt/homebrew/bin/openclaw", text: $preferences.openClawBinaryPath)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                Button("찾아보기…", action: onSelectOpenClawBinary)
            }
        }
        LabeledContent("Telegram 대상") {
            TextField(
                "@username 또는 숫자 chat id",
                text: $preferences.openClawTelegramTarget
            )
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 280)
        }
        LabeledContent("openclaw 상태") {
            HStack(spacing: 8) {
                openClawStatusBadge
                Button("새로고침", action: onRefreshOpenClawStatus)
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var openClawStatusBadge: some View {
        let status = openClawStatus ?? .unknown
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: openClawIcon(for: status))
                    .foregroundStyle(openClawTint(for: status))
                Text(openClawTitle(for: status))
                    .font(.caption.weight(.medium))
            }
            Text(status.message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func openClawIcon(for status: OpenClawUIStatus) -> String {
        if !status.installed { return "questionmark.circle" }
        if status.telegramActive { return "checkmark.circle.fill" }
        return "exclamationmark.triangle.fill"
    }

    private func openClawTint(for status: OpenClawUIStatus) -> Color {
        if !status.installed { return .secondary }
        if status.telegramActive { return .green }
        return .orange
    }

    private func openClawTitle(for status: OpenClawUIStatus) -> String {
        if !status.installed { return "openclaw 미감지" }
        let suffix = status.version.map { " — \($0)" } ?? ""
        return status.telegramActive ? "telegram 채널 활성\(suffix)" : "telegram 채널 비활성\(suffix)"
    }

    private var testButtonEnabled: Bool {
        guard preferences.telegramChatId != nil else { return false }
        if preferences.telegramUseOpenClaw {
            let pathOk = !preferences.openClawBinaryPath.isEmpty
            let targetOk = !preferences.openClawTelegramTarget
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return pathOk && targetOk
        }
        return telegramTokenStatus == .set
    }

    private var connectionFooter: String {
        if preferences.telegramUseOpenClaw {
            return "openclaw에 등록된 토큰을 위임 사용해요. Yuminai는 토큰을 직접 보거나 저장하지 않아요. openclaw에 telegram 채널이 먼저 활성화돼 있어야 해요."
        }
        return "BotFather에서 받은 토큰과, 본인 Telegram 계정의 user ID를 입력하세요."
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
