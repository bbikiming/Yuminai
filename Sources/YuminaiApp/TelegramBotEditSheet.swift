import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-086 Phase 4** — 봇 편집/추가 sheet.
struct TelegramBotEditSheet: View {
    let existing: TelegramBotConfig?
    let onSave: (TelegramBotConfig) -> Void
    let onCancel: () -> Void

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
                        TextField("Keychain key", text: $keychainKey)
                            .help("이 봇 token을 keychain에 어떤 key로 저장할지")
                            .autocorrectionDisabled()
                    } header: {
                        Text("기본")
                    }
                    Section {
                        Toggle("활성", isOn: $enabled)
                        TextField("허용 user IDs (콤마 구분)", text: $allowedUserIdsText)
                            .help("비어있으면 모든 사용자 허용 (위험)")
                            .autocorrectionDisabled()
                    } header: {
                        Text("권한")
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
                Spacer()
                FlatButton("취소", variant: .secondary, action: onCancel)
                FlatButton("저장", variant: .primary) {
                    let allowedIds = parseAllowedIds()
                    let config = TelegramBotConfig(
                        id: existing?.id ?? UUID(),
                        displayName: displayName.isEmpty ? "이름 없음" : displayName,
                        username: username,
                        keychainKey: keychainKey.isEmpty ? "telegram.bot.token" : keychainKey,
                        groupId: existing?.groupId,
                        allowedUserIds: allowedIds,
                        enabled: enabled,
                        iconName: iconName.isEmpty ? "paperplane.circle.fill" : iconName,
                        colorName: colorName.isEmpty ? "accent" : colorName,
                        notes: notes
                    )
                    onSave(config)
                }
            }
        }
    }

    private func parseAllowedIds() -> [Int64] {
        allowedUserIdsText
            .split(separator: ",")
            .compactMap { Int64($0.trimmingCharacters(in: .whitespaces)) }
    }
}
