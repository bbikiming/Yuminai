import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-086 Phase 4 / ADR-101** — 봇 편집/추가 sheet.
struct TelegramBotEditSheet: View {
    let existing: TelegramBotConfig?
    let onSave: (TelegramBotConfig) -> Void
    let onCancel: () -> Void

    @Environment(AppModel.self) private var appModel

    @State private var displayName: String
    @State private var username: String
    @State private var keychainKey: String
    @State private var notes: String
    @State private var enabled: Bool
    @State private var allowedUserIdsText: String
    @State private var iconName: String
    @State private var colorName: String

    init(
        existing: TelegramBotConfig?,
        onSave: @escaping (TelegramBotConfig) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.existing = existing
        self.onSave = onSave
        self.onCancel = onCancel
        _displayName = State(initialValue: existing?.displayName ?? "")
        _username = State(initialValue: existing?.username ?? "")
        _keychainKey = State(initialValue: existing?.keychainKey ?? "telegram.bot.token")
        _notes = State(initialValue: existing?.notes ?? "")
        _enabled = State(initialValue: existing?.enabled ?? true)
        _allowedUserIdsText = State(initialValue: existing?.allowedUserIds.map(String.init).joined(separator: ", ") ?? "")
        _iconName = State(initialValue: existing?.iconName ?? "paperplane.circle.fill")
        _colorName = State(initialValue: existing?.colorName ?? "accent")
    }

    var body: some View {
        YuminaiSheet(width: 520, height: 480) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text(existing == nil ? "새 봇 추가" : "봇 편집")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
                Form {
                    Section {
                        TextField("표시 이름", text: $displayName)
                        TextField("Username (예: my_bot)", text: $username)
                            .autocorrectionDisabled()
                        TextField("macOS 비밀번호 저장소 키", text: $keychainKey)
                            .help("이 봇 토큰(BotFather에서 받은 비밀번호)을 macOS 비밀번호 저장소에 어떤 키로 저장할지 지정해요.")
                            .autocorrectionDisabled()
                    } header: {
                        Text("기본")
                    }
                    Section {
                        Toggle("활성화", isOn: $enabled)
                        TextField("사용 가능한 사람 (텔레그램 사용자 번호, 콤마 구분)", text: $allowedUserIdsText)
                            .help("비어있으면 모든 사용자 허용 (위험). 예: 123456789, 987654321")
                            .autocorrectionDisabled()
                    } header: {
                        Text("접근 허가")
                    } footer: {
                        Text("사용 가능한 사람을 비워두면 누구나 이 봇을 사용할 수 있어요. 보안을 위해 직접 추가를 권장해요.")
                            .font(Theme.Typography.micro)
                    }
                    Section {
                        TextField("아이콘 (SF Symbol)", text: $iconName)
                            .autocorrectionDisabled()
                        TextField("색상 (semantic name)", text: $colorName)
                            .autocorrectionDisabled()
                        TextField("메모 (선택)", text: $notes, axis: .vertical)
                            .lineLimit(2...4)
                    } header: {
                        Text("외형 + 메모")
                    }
                }
                .formStyle(.grouped)
            }
            .padding(Theme.Spacing.lg)
        } footer: {
            HStack {
                // 실시간 유효성 안내
                if let errorMessage = validationResult.errorMessage {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Color.danger)
                        Text(errorMessage)
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.danger)
                    }
                }
                Spacer()
                FlatButton("취소", variant: .secondary, action: onCancel)
                FlatButton("저장", variant: .primary) {
                    let allowedIds = parseAllowedIds()
                    let config = TelegramBotConfig(
                        id: existing?.id ?? UUID(),
                        displayName: displayName.trimmingCharacters(in: .whitespaces),
                        username: username,
                        keychainKey: keychainKey.trimmingCharacters(in: .whitespaces),
                        groupId: existing?.groupId,
                        allowedUserIds: allowedIds,
                        enabled: enabled,
                        iconName: iconName.isEmpty ? "paperplane.circle.fill" : iconName,
                        colorName: colorName.isEmpty ? "accent" : colorName,
                        notes: notes
                    )
                    onSave(config)
                }
                .disabled(!isFormValid)
            }
        }
    }

    // MARK: - Validation

    /// 실시간 폼 유효성 검사 — TelegramBotValidator 위임.
    private var validationResult: TelegramBotValidator.ValidationResult {
        TelegramBotValidator.validateBot(
            displayName: displayName,
            username: username,
            keychainKey: keychainKey,
            existingId: existing?.id,
            existingBots: appModel.preferences.telegramBots
        )
    }

    private var isFormValid: Bool { validationResult.isValid }

    private func parseAllowedIds() -> [Int64] {
        allowedUserIdsText
            .split(separator: ",")
            .compactMap { Int64($0.trimmingCharacters(in: .whitespaces)) }
    }
}
