import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-086 Phase 4 / ADR-101 / ADR-102** — 봇 편집/추가 sheet.
///
/// ADR-102: Form/.grouped → CardSection 카드 레이아웃. 입력별 명확한 라벨 + helper text +
/// 필수 표시 (*) + 외형 설정 점진 노출 (DisclosureGroup).
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
    @State private var showAppearance: Bool = false

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
        YuminaiSheet(width: 540, height: 600) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                basicCard
                accessCard
                appearanceCard
            }
            .padding(Theme.Spacing.lg)
        } footer: {
            HStack {
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
                    .keyboardShortcut(.escape, modifiers: [])
                FlatButton("저장", variant: .primary) {
                    submit()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!isFormValid)
            }
        }
        .overlay(alignment: .topTrailing) {
            SheetCloseButton(action: onCancel)
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(existing == nil ? "새 봇 추가" : "봇 편집")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Color.text)
            Text(existing == nil
                ? "BotFather에서 받은 봇 정보를 입력해 주세요."
                : "봇 설정을 수정합니다. 변경 즉시 저장돼요.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }

    private var basicCard: some View {
        CardSection(style: .subtle) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                sectionHeader(icon: "person.text.rectangle.fill", title: "기본 정보")

                fieldLabel("봇 이름", required: true)
                TextField("예: 우리집 비서", text: $displayName)
                    .textFieldStyle(.roundedBorder)
                fieldHelper("Hub 봇 목록과 알림에 표시되는 이름이에요.")

                fieldLabel("Username", required: false)
                TextField("예: my_bot (BotFather에서 받은 @username)", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                if let dupMsg = duplicateMessage {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.Color.danger)
                        Text(dupMsg)
                            .foregroundStyle(Theme.Color.danger)
                    }
                    .font(Theme.Typography.micro)
                } else {
                    fieldHelper("선택 — BotFather가 알려준 @username을 그대로 입력하면 됩니다.")
                }

                fieldLabel("macOS 비밀번호 저장소 키", required: true)
                TextField("telegram.bot.token", text: $keychainKey)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                fieldHelper("봇 토큰을 macOS 비밀번호 저장소(Keychain)에 어떤 이름으로 저장할지 정해요. 봇별로 다른 이름을 쓰는 걸 권장해요.")
            }
        }
    }

    private var accessCard: some View {
        CardSection(style: .subtle) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                sectionHeader(icon: "lock.shield.fill", title: "접근 허가")

                Toggle(isOn: $enabled) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("봇 활성화")
                            .font(Theme.Typography.label)
                            .foregroundStyle(Theme.Color.text)
                        Text(enabled ? "메시지를 받고 답장할 수 있어요" : "비활성 상태 — 메시지 수신 안 함")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                }
                .toggleStyle(.switch)

                Divider()

                fieldLabel("사용 가능한 사람", required: false)
                TextField("예: 123456789, 987654321", text: $allowedUserIdsText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                if allowedUserIdsText.trimmingCharacters(in: .whitespaces).isEmpty {
                    InfoCallout(tone: .warning) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("⚠ 비어있으면 모든 사람이 사용할 수 있어요")
                                .font(Theme.Typography.small.weight(.semibold))
                            Text("보안을 위해 텔레그램 사용자 번호를 직접 추가하는 걸 권장해요. 콤마로 여러 명을 구분합니다.")
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Color.textSecondary)
                        }
                    }
                } else {
                    fieldHelper("\(parseAllowedIds().count)명이 이 봇을 사용할 수 있어요.")
                }
            }
        }
    }

    private var appearanceCard: some View {
        CardSection(style: .subtle) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        showAppearance.toggle()
                    }
                } label: {
                    HStack {
                        Image(systemName: "paintpalette.fill")
                            .foregroundStyle(Theme.Color.textSecondary)
                            .frame(width: 18)
                        Text("외형 + 메모 (선택)")
                            .font(Theme.Typography.label)
                            .foregroundStyle(Theme.Color.text)
                        Spacer()
                        Image(systemName: showAppearance ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showAppearance {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        fieldLabel("아이콘 (SF Symbol)", required: false)
                        TextField("paperplane.circle.fill", text: $iconName)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                        fieldHelper("Apple SF Symbols 이름. 비워두면 기본 종이비행기 아이콘.")

                        fieldLabel("색상", required: false)
                        TextField("accent", text: $colorName)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                        fieldHelper("accent / blue / green / orange / purple 등.")

                        fieldLabel("메모", required: false)
                        TextField("이 봇에 대한 메모...", text: $notes, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...4)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    // MARK: - Field helpers

    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Color.accent)
            Text(title)
                .font(Theme.Typography.label.weight(.semibold))
                .foregroundStyle(Theme.Color.text)
        }
    }

    private func fieldLabel(_ text: String, required: Bool) -> some View {
        HStack(spacing: 3) {
            Text(text)
                .font(Theme.Typography.small.weight(.medium))
                .foregroundStyle(Theme.Color.textSecondary)
            if required {
                Text("*")
                    .font(Theme.Typography.small.weight(.semibold))
                    .foregroundStyle(Theme.Color.danger)
            }
        }
    }

    private func fieldHelper(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Image(systemName: "info.circle")
                .font(.system(size: 10))
                .foregroundStyle(Theme.Color.textTertiary)
                .padding(.top, 1)
            Text(text)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Validation

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

    private var duplicateMessage: String? {
        if case .duplicateUsername = validationResult {
            return "이미 사용 중인 username이에요."
        }
        return nil
    }

    // MARK: - Submit

    private func submit() {
        let allowedIds = parseAllowedIds()
        let config = TelegramBotConfig(
            id: existing?.id ?? UUID(),
            displayName: displayName.trimmingCharacters(in: .whitespaces),
            username: username.trimmingCharacters(in: .whitespaces),
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

    private func parseAllowedIds() -> [Int64] {
        allowedUserIdsText
            .split(separator: ",")
            .compactMap { Int64($0.trimmingCharacters(in: .whitespaces)) }
    }
}
