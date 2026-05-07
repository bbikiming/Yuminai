import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-086 Phase 4 / ADR-101 / ADR-102** — 봇 그룹 편집/추가 sheet.
///
/// ADR-102: Form/.grouped → CardSection 카드 레이아웃 (TelegramBotEditSheet 일관 톤).
/// + 그룹 개념 설명 InfoCallout + ⓘ 호버 도움말 + 친화 언어.
struct TelegramBotGroupEditSheet: View {
    let existing: TelegramBotGroup?
    let onSave: (TelegramBotGroup) -> Void
    let onCancel: () -> Void

    @State private var displayName: String
    @State private var iconName: String
    @State private var colorName: String
    @State private var responseModeOverride: TelegramResponseMode?
    @State private var hasResponseModeOverride: Bool
    @State private var showAppearance: Bool = false

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
        YuminaiSheet(width: 560, height: 620) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                if existing == nil {
                    explainerCallout
                }
                basicCard
                policyCard
                appearanceCard
            }
            .padding(Theme.Spacing.lg)
        } footer: {
            HStack {
                if !isFormValid {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Color.danger)
                        Text("그룹 이름을 입력해 주세요.")
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
            Text(existing == nil ? "새 봇 그룹" : "그룹 편집")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Color.text)
            Text(existing == nil
                ? "여러 봇을 한 묶음으로 관리하는 그룹을 만듭니다."
                : "그룹 설정을 수정합니다. 여기서 바꾼 정책은 그룹 안 모든 봇에 적용돼요.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }

    /// 그룹 개념 설명 — 신규 생성 시만 표시.
    private var explainerCallout: some View {
        InfoCallout(tone: .info) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Color.accent)
                    Text("봇 그룹이 뭔가요?")
                        .font(Theme.Typography.small.weight(.semibold))
                        .foregroundStyle(Theme.Color.text)
                }
                Text("여러 봇을 한 묶음으로 관리하는 기능이에요. 같은 그룹에 묶인 봇들은 같은 답변 스타일과 예산 정책을 따라요.")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("예: ’회사 봇 (3개)’ 그룹을 만들고 답변 모드를 ’간결’로 두면 3개 봇 모두 짧게 답변해요.")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("💡 봇이 1~2개뿐이면 그룹은 만들지 않아도 됩니다.")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
        }
    }

    private var basicCard: some View {
        CardSection(style: .subtle) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                sectionHeader(icon: "folder.badge.person.crop", title: "기본 정보")

                fieldLabel("그룹 이름", required: true, help: "Telegram Hub 봇 목록에 그룹 라벨로 표시돼요.")
                TextField("예: 회사 봇 / 개인 봇 / 테스트", text: $displayName)
                    .textFieldStyle(.roundedBorder)
                fieldHelper("이 그룹에 속한 봇들을 한눈에 알아볼 수 있는 이름을 정해 주세요.")
            }
        }
    }

    private var policyCard: some View {
        CardSection(style: .subtle) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                sectionHeader(icon: "slider.horizontal.3", title: "그룹 공통 정책 (선택)")

                Text("그룹 안 모든 봇에 같은 정책을 적용해요. 개별 봇 설정보다 우선합니다.")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(isOn: $hasResponseModeOverride) {
                    HStack(spacing: 4) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("답변 모드 통일")
                                .font(Theme.Typography.label)
                                .foregroundStyle(Theme.Color.text)
                            Text(hasResponseModeOverride
                                ? "그룹 공통 답변 스타일 적용 중"
                                : "각 봇이 자기 설정 사용")
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Color.textTertiary)
                        }
                        helpButton("그룹 안 모든 봇이 같은 답변 스타일(최소/간결/기본/상세)을 쓰게 해요. 예: 회사 봇은 모두 ’간결’, 개인 봇은 모두 ’상세’처럼 운영 가능.")
                    }
                }
                .toggleStyle(.switch)

                if hasResponseModeOverride {
                    fieldLabel("답변 스타일", required: false, help: nil)
                    Picker("", selection: Binding(
                        get: { responseModeOverride ?? .standard },
                        set: { responseModeOverride = $0 }
                    )) {
                        ForEach(TelegramResponseMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)

                    if let mode = responseModeOverride ?? Optional(.standard) {
                        fieldHelper(mode.hint)
                    }
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
                        Text("외형 (선택)")
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
                        fieldLabel("아이콘 (SF Symbol)", required: false, help: "Apple SF Symbols 이름. 비워두면 기본 폴더 아이콘.")
                        TextField("folder.badge.person.crop", text: $iconName)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                        fieldHelper("Apple SF Symbols 이름. 비워두면 기본 폴더 아이콘.")

                        fieldLabel("색상", required: false, help: nil)
                        TextField("accent", text: $colorName)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                        fieldHelper("accent / blue / green / orange / purple 등.")
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

    private func fieldLabel(_ text: String, required: Bool, help: String?) -> some View {
        HStack(spacing: 3) {
            Text(text)
                .font(Theme.Typography.small.weight(.medium))
                .foregroundStyle(Theme.Color.textSecondary)
            if required {
                Text("*")
                    .font(Theme.Typography.small.weight(.semibold))
                    .foregroundStyle(Theme.Color.danger)
            }
            if let help {
                helpButton(help)
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

    /// ⓘ 호버 도움말 버튼 — macOS는 system tooltip으로 표시.
    private func helpButton(_ tooltip: String) -> some View {
        Image(systemName: "questionmark.circle")
            .font(.system(size: 11))
            .foregroundStyle(Theme.Color.textTertiary)
            .help(tooltip)
            .accessibilityLabel("도움말")
            .accessibilityHint(tooltip)
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Submit

    private func submit() {
        let group = TelegramBotGroup(
            id: existing?.id ?? UUID(),
            displayName: displayName.trimmingCharacters(in: .whitespaces),
            iconName: iconName.isEmpty ? "folder.badge.person.crop" : iconName,
            colorName: colorName.isEmpty ? "accent" : colorName,
            responseModeOverride: hasResponseModeOverride ? responseModeOverride : nil,
            budgetOverride: existing?.budgetOverride,
            sharedSkillIds: existing?.sharedSkillIds ?? []
        )
        onSave(group)
    }
}
