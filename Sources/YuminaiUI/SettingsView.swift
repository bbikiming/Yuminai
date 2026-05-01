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
            telegramTab.tabItem { Label("Telegram", systemImage: "paperplane") }
            anthropicTab.tabItem { Label("Anthropic", systemImage: "key") }
        }
        .frame(width: 560, height: 480)
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
                Picker("기본 모델", selection: $preferences.defaultModelAlias) {
                    Text("Sonnet").tag("sonnet")
                    Text("Opus").tag("opus")
                    Text("Haiku").tag("haiku")
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
                Stepper(
                    value: $preferences.fontSizeOffset,
                    in: -2...6
                ) {
                    Text("폰트 크기 보정: \(preferences.fontSizeOffset >= 0 ? "+" : "")\(preferences.fontSizeOffset)")
                }
            }
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
