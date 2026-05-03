import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-086 Phase 4** — 봇 그룹 편집/추가 sheet.
struct TelegramBotGroupEditSheet: View {
    let existing: TelegramBotGroup?
    let onSave: (TelegramBotGroup) -> Void
    let onCancel: () -> Void

    @State private var displayName: String
    @State private var iconName: String
    @State private var colorName: String
    @State private var responseModeOverride: TelegramResponseMode?
    @State private var hasResponseModeOverride: Bool

    init(
        existing: TelegramBotGroup?,
        onSave: @escaping (TelegramBotGroup) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.existing = existing
        self.onSave = onSave
        self.onCancel = onCancel
        _displayName = State(initialValue: existing?.displayName ?? "")
        _iconName = State(initialValue: existing?.iconName ?? "folder.badge.person.crop")
        _colorName = State(initialValue: existing?.colorName ?? "accent")
        _responseModeOverride = State(initialValue: existing?.responseModeOverride)
        _hasResponseModeOverride = State(initialValue: existing?.responseModeOverride != nil)
    }

    var body: some View {
        YuminaiSheet(width: 520, height: 420) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text(existing == nil ? "새 그룹" : "그룹 편집")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
                Form {
                    Section {
                        TextField("표시 이름", text: $displayName)
                        TextField("아이콘 (SF Symbol)", text: $iconName)
                            .autocorrectionDisabled()
                        TextField("색상 (semantic name)", text: $colorName)
                            .autocorrectionDisabled()
                    } header: {
                        Text("기본")
                    }
                    Section {
                        Toggle("응답 모드 override", isOn: $hasResponseModeOverride)
                        if hasResponseModeOverride {
                            Picker("응답 모드", selection: Binding(
                                get: { responseModeOverride ?? .standard },
                                set: { responseModeOverride = $0 }
                            )) {
                                ForEach(TelegramResponseMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                        }
                    } header: {
                        Text("Override (선택)")
                    } footer: {
                        Text("그룹 안 모든 봇에 적용됩니다 (개별 봇 설정보다 우선).")
                            .font(Theme.Typography.micro)
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
                    let group = TelegramBotGroup(
                        id: existing?.id ?? UUID(),
                        displayName: displayName.isEmpty ? "이름 없음" : displayName,
                        iconName: iconName.isEmpty ? "folder.badge.person.crop" : iconName,
                        colorName: colorName.isEmpty ? "accent" : colorName,
                        responseModeOverride: hasResponseModeOverride ? responseModeOverride : nil,
                        budgetOverride: existing?.budgetOverride,
                        sharedSkillIds: existing?.sharedSkillIds ?? []
                    )
                    onSave(group)
                }
            }
        }
    }
}
