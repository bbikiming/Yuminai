import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-084 Phase 5** — 텔레그램 고도화 설정 sheet.
///
/// 4개 섹션:
/// 1. 응답 모드 (minimal/concise/standard/detailed)
/// 2. 토큰 budget (per-turn / per-day / overflow action)
/// 3. 첨부파일 (송수신 + max 크기 + 화이트리스트)
/// 4. Skills (사용자 정의 prompt template)
struct TelegramAdvancedSheet: View {
    @Environment(AppModel.self) private var appModel
    @State private var section: Section = .responseMode
    @State private var newSkillTrigger: String = ""
    @State private var newSkillDisplayName: String = ""
    @State private var newSkillPrompt: String = ""
    @State private var showAddSkill: Bool = false

    enum Section: String, CaseIterable, Identifiable {
        case responseMode = "응답 모드"
        case budget = "토큰 budget"
        case attachments = "첨부파일"
        case skills = "Skills"
        case connection = "연결 + 알림"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .responseMode: return "text.bubble.fill"
            case .budget: return "dollarsign.circle.fill"
            case .attachments: return "paperclip.circle.fill"
            case .skills: return "wand.and.stars"
            case .connection: return "antenna.radiowaves.left.and.right"
            }
        }
    }

    var body: some View {
        @Bindable var bindable = appModel
        YuminaiSheet(width: 720, height: 620) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                segmentedNav
                Divider()
                content(prefs: $bindable.preferences)
            }
            .padding(Theme.Spacing.xl)
        } footer: {
            HStack {
                Spacer()
                FlatButton("닫기", variant: .primary) {
                    appModel.showTelegramAdvancedSheet = false
                    Task { await appModel.savePreferences() }
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "paperplane.fill")
                    .foregroundStyle(Theme.Color.accent)
                    .accessibilityHidden(true)
                Text("텔레그램 고도화 설정")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
            }
            Text("응답 모드 · 토큰 한도 · 첨부 · 사용자 skills를 정밀하게 설정하세요.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var segmentedNav: some View {
        Picker("Section", selection: $section) {
            ForEach(Section.allCases) { sec in
                Label(sec.rawValue, systemImage: sec.icon).tag(sec)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("설정 섹션 선택")
    }

    @ViewBuilder
    private func content(prefs: Binding<AppPreferences>) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                switch section {
                case .responseMode: responseModeSection(prefs: prefs)
                case .budget: budgetSection(prefs: prefs)
                case .attachments: attachmentSection(prefs: prefs)
                case .skills: skillsSection(prefs: prefs)
                case .connection: connectionSection(prefs: prefs)
                }
            }
            .padding(.bottom, Theme.Spacing.md)
        }
    }

    // MARK: - Phase 1 — Response mode

    private func responseModeSection(prefs: Binding<AppPreferences>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("응답 모드 선택")
                .font(Theme.Typography.body.weight(.semibold))
                .foregroundStyle(Theme.Color.text)
            Text("텔레그램으로 받는 응답의 detail 레벨을 설정합니다. minimal일수록 토큰 소모 ↓, detailed일수록 상세하지만 비용 ↑.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 6) {
                ForEach(TelegramResponseMode.allCases) { mode in
                    modeCard(mode, current: prefs.wrappedValue.telegramResponseMode) {
                        prefs.wrappedValue.telegramResponseMode = mode
                    }
                }
            }
        }
    }

    private func modeCard(_ mode: TelegramResponseMode, current: TelegramResponseMode, onTap: @escaping () -> Void) -> some View {
        let isSelected = mode == current
        return Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Theme.Color.accent : Theme.Color.textTertiary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(mode.displayName)
                            .font(Theme.Typography.body.weight(.semibold))
                            .foregroundStyle(Theme.Color.text)
                        Text("~\(mode.estimatedMaxOutputTokens) 토큰")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textTertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.Color.surfaceHi)
                            .clipShape(Capsule())
                    }
                    Text(mode.hint)
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
            }
            .padding(Theme.Spacing.md)
            .background(isSelected ? Theme.Color.accentMuted : Theme.Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(isSelected ? Theme.Color.accent : Theme.Color.borderSubtle, lineWidth: isSelected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.displayName)
        .accessibilityHint(mode.hint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Phase 2 — Budget

    private func budgetSection(prefs: Binding<AppPreferences>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("토큰 / 비용 한도")
                .font(Theme.Typography.body.weight(.semibold))
                .foregroundStyle(Theme.Color.text)
            // Per-turn max output
            VStack(alignment: .leading, spacing: 4) {
                Text("1턴당 최대 출력 토큰")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .textCase(.uppercase)
                HStack(spacing: 8) {
                    TextField("자동 (모드별 default)", value: prefs.telegramTokenBudget.perTurnMaxOutputTokens, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                    Text("nil이면 응답 모드 default 사용")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
            }
            // Per-day max USD
            VStack(alignment: .leading, spacing: 4) {
                Text("하루 최대 비용 (USD)")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .textCase(.uppercase)
                HStack(spacing: 8) {
                    TextField("무제한", value: prefs.telegramTokenBudget.perDayMaxCostUSD, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                    Text("매일 자정 UTC reset")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
            }
            // Overflow action
            VStack(alignment: .leading, spacing: 4) {
                Text("한도 초과 시 동작")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .textCase(.uppercase)
                Picker("초과 동작", selection: prefs.telegramTokenBudget.overflowAction) {
                    ForEach(TelegramOverflowAction.allCases) { action in
                        Text(action.displayName).tag(action)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("한도 초과 시 동작")
                Text(prefs.wrappedValue.telegramTokenBudget.overflowAction.hint)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
    }

    // MARK: - Phase 3 — Attachments

    private func attachmentSection(prefs: Binding<AppPreferences>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("첨부파일 송수신")
                .font(Theme.Typography.body.weight(.semibold))
                .foregroundStyle(Theme.Color.text)
            Toggle("받기 (사용자 → Yuminai)", isOn: prefs.telegramAttachmentPolicy.acceptIncoming)
                .accessibilityHint("텔레그램에서 보낸 파일을 워크스페이스에 자동 저장")
            Toggle("보내기 (Yuminai → 텔레그램)", isOn: prefs.telegramAttachmentPolicy.sendOutgoing)
                .accessibilityHint("Claude가 만든 파일을 텔레그램에 자동 전송")
            VStack(alignment: .leading, spacing: 4) {
                Text("받기 max 크기 (MB)")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .textCase(.uppercase)
                Stepper(
                    value: Binding(
                        get: { Double(prefs.wrappedValue.telegramAttachmentPolicy.maxIncomingSizeBytes) / 1_048_576 },
                        set: { prefs.wrappedValue.telegramAttachmentPolicy.maxIncomingSizeBytes = Int($0 * 1_048_576) }
                    ),
                    in: 1...50, step: 1
                ) {
                    Text(prefs.wrappedValue.telegramAttachmentPolicy.maxSizeDisplay)
                        .font(Theme.Typography.monoSmall)
                }
                .frame(maxWidth: 240)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("허용 확장자 (쉼표로 구분, 비우면 모두 허용)")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .textCase(.uppercase)
                let extsBinding = Binding<String>(
                    get: { prefs.wrappedValue.telegramAttachmentPolicy.allowedExtensions.sorted().joined(separator: ", ") },
                    set: { newVal in
                        let exts = newVal.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
                        prefs.wrappedValue.telegramAttachmentPolicy.allowedExtensions = Set(exts)
                    }
                )
                TextField("예: txt, md, json, swift", text: extsBinding)
                    .textFieldStyle(.roundedBorder)
                Text("화이트리스트 — 보안 권장 (binary 파일 거부).")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
    }

    // MARK: - Phase 4 — Skills

    private func skillsSection(prefs: Binding<AppPreferences>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("사용자 정의 Skills")
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.Color.text)
                Spacer()
                Button {
                    newSkillTrigger = ""
                    newSkillDisplayName = ""
                    newSkillPrompt = ""
                    showAddSkill.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showAddSkill ? "minus.circle" : "plus.circle.fill")
                            .font(.system(size: 11))
                        Text(showAddSkill ? "취소" : "새 skill")
                            .font(Theme.Typography.small.weight(.medium))
                    }
                    .foregroundStyle(Theme.Color.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showAddSkill ? "새 skill 취소" : "새 skill 추가")
            }
            Text("텔레그램에서 `/{trigger}` 입력 시 prompt template으로 자동 확장됩니다. 예: `/test`로 테스트 실행, `/리뷰`로 코드 리뷰.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if showAddSkill {
                addSkillForm(prefs: prefs)
            }
            VStack(spacing: 4) {
                ForEach(prefs.wrappedValue.telegramSkills) { skill in
                    skillRow(skill, prefs: prefs)
                }
            }
        }
    }

    private func addSkillForm(prefs: Binding<AppPreferences>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("/")
                    .font(Theme.Typography.monoSmall)
                    .foregroundStyle(Theme.Color.textTertiary)
                TextField("trigger (예: test)", text: $newSkillTrigger)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                TextField("표시 이름", text: $newSkillDisplayName)
                    .textFieldStyle(.roundedBorder)
            }
            TextEditor(text: $newSkillPrompt)
                .font(Theme.Typography.small)
                .padding(8)
                .background(Theme.Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .stroke(Theme.Color.borderSubtle, lineWidth: 1)
                )
                .frame(height: 80)
            HStack {
                Text("`{args}` 자리표시자 사용 가능")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                Spacer()
                Button("추가") {
                    let trigger = newSkillTrigger.trimmingCharacters(in: .whitespaces)
                    let name = newSkillDisplayName.trimmingCharacters(in: .whitespaces)
                    let prompt = newSkillPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trigger.isEmpty, !prompt.isEmpty else { return }
                    let skill = TelegramSkill(
                        trigger: trigger,
                        displayName: name.isEmpty ? trigger : name,
                        prompt: prompt
                    )
                    prefs.wrappedValue.telegramSkills.append(skill)
                    newSkillTrigger = ""
                    newSkillDisplayName = ""
                    newSkillPrompt = ""
                    showAddSkill = false
                }
                .disabled(newSkillTrigger.trimmingCharacters(in: .whitespaces).isEmpty
                          || newSkillPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Color.accentMuted.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private func skillRow(_ skill: TelegramSkill, prefs: Binding<AppPreferences>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: skill.iconName)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Color.accent)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("/\(skill.trigger)")
                        .font(Theme.Typography.monoSmall.weight(.semibold))
                        .foregroundStyle(Theme.Color.text)
                    Text(skill.displayName)
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                Text(skill.prompt)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                prefs.wrappedValue.telegramSkills.removeAll { $0.id == skill.id }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.danger)
            }
            .buttonStyle(.plain)
            .help("Skill 삭제")
            .accessibilityLabel("Skill /\(skill.trigger) 삭제")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 6)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    // MARK: - Phase 5 — Connection mode + Rate limit alert (ADR-086)

    private func connectionSection(prefs: Binding<AppPreferences>) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            // Update mode (LongPoll vs Webhook)
            VStack(alignment: .leading, spacing: 8) {
                Text("Update 수신 모드")
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.Color.text)
                Text("LongPoll: 즉시 수신 + 배터리 소모. Webhook: 배터리 절약 + HTTPS 공개 URL 필요.")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Picker("수신 모드", selection: prefs.telegramUpdateMode) {
                    ForEach(TelegramUpdateMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(prefs.wrappedValue.telegramUpdateMode.hint)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if prefs.wrappedValue.telegramUpdateMode == .webhook {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Webhook URL (HTTPS)")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textTertiary)
                            .textCase(.uppercase)
                        TextField("https://your.domain/telegram/webhook", text: Binding(
                            get: { prefs.wrappedValue.telegramWebhookURL ?? "" },
                            set: { prefs.wrappedValue.telegramWebhookURL = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        Text("ngrok / Cloudflare Tunnel / 공개 도메인이 필요. 텔레그램 BotFather에서 setWebhook 명령으로 등록해야 합니다.")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Theme.Spacing.md)
                    .background(Theme.Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                }
            }

            Divider()

            // Rate limit alert
            VStack(alignment: .leading, spacing: 8) {
                Text("사용량 알림")
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.Color.text)
                Text("일별 budget의 일정 비율 도달 시 텔레그램으로 경고 메시지 자동 전송.")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("텔레그램으로 경고 알림 보내기", isOn: prefs.telegramRateLimitAlert.notifyViaTelegram)
                if prefs.wrappedValue.telegramRateLimitAlert.notifyViaTelegram {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("알림 임계값 (%)")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textTertiary)
                            .textCase(.uppercase)
                        HStack {
                            Slider(value: prefs.telegramRateLimitAlert.thresholdRatio, in: 0.5...1.0, step: 0.05)
                                .frame(maxWidth: 240)
                            Text("\(Int(prefs.wrappedValue.telegramRateLimitAlert.thresholdRatio * 100))%")
                                .font(Theme.Typography.monoSmall)
                                .foregroundStyle(Theme.Color.text)
                                .frame(width: 50, alignment: .trailing)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cooldown (분)")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textTertiary)
                            .textCase(.uppercase)
                        Stepper(
                            value: Binding(
                                get: { Int(prefs.wrappedValue.telegramRateLimitAlert.cooldownSeconds / 60) },
                                set: { prefs.wrappedValue.telegramRateLimitAlert.cooldownSeconds = TimeInterval($0 * 60) }
                            ),
                            in: 5...720, step: 5
                        ) {
                            Text("\(Int(prefs.wrappedValue.telegramRateLimitAlert.cooldownSeconds / 60))분")
                                .font(Theme.Typography.monoSmall)
                        }
                        .frame(maxWidth: 240)
                    }
                }
            }
        }
    }
}
