import SwiftUI
import YuminaiCore

/// **ADR-072 Phase 4** — 첫 실행 onboarding wizard.
///
/// UX 라이팅 + IA 근거:
/// - Apple HIG "Onboarding": 첫 사용자에게 핵심 가치 + 1-2개의 핵심 결정만 묻기
/// - NN/g "Onboarding for SaaS": 너무 많은 옵션은 결정 마비 (Hick's Law)
/// - 본 wizard: 단 한 가지 핵심 결정 — 사용 모드 선택 (초보자 / 고급 / 사용자 정의)
///
/// 흐름:
/// 1. 환영 화면 (Yuminai 핵심 가치 한 줄)
/// 2. 사용 모드 선택 (3개 카드)
/// 3. 사용자 정의 선택 시 추가 옵션 (Telegram, Harness, etc)
/// 4. 완료 → hasCompletedOnboarding = true → main UI
public struct OnboardingWizard: View {
    @Binding public var preferences: AppPreferences
    public let onComplete: () -> Void

    public init(preferences: Binding<AppPreferences>, onComplete: @escaping () -> Void) {
        self._preferences = preferences
        self.onComplete = onComplete
    }

    @State private var step: Step = .welcome
    @State private var selectedMode: UsageMode = .beginner

    public enum Step: Int {
        case welcome = 0
        case modeSelection = 1
        case customDetails = 2
        case complete = 3
    }

    public enum UsageMode: String, CaseIterable, Identifiable {
        case beginner = "초보자"
        case advanced = "고급"
        case custom = "사용자 정의"

        public var id: String { rawValue }

        var icon: String {
            switch self {
            case .beginner: return "leaf"
            case .advanced: return "wand.and.stars"
            case .custom: return "slider.horizontal.3"
            }
        }

        var title: String {
            switch self {
            case .beginner: return "초보자"
            case .advanced: return "고급"
            case .custom: return "사용자 정의"
            }
        }

        var subtitle: String {
            switch self {
            case .beginner: return "꼭 필요한 기능만"
            case .advanced: return "모든 기능 표시"
            case .custom: return "직접 선택"
            }
        }

        var description: String {
            switch self {
            case .beginner:
                return "자동화, 학습, cokacdir 통합 등 고급 옵션이 숨겨집니다. 처음 사용하는 분께 권장합니다."
            case .advanced:
                return "다중 모델 자동 전환, 에이전트 자동 답장, 색 대비 감사 등 모든 기능을 사용합니다."
            case .custom:
                return "다음 단계에서 항목을 하나씩 선택할 수 있습니다."
            }
        }
    }

    public var body: some View {
        ZStack {
            Theme.Color.bg.ignoresSafeArea()
            VStack(spacing: Theme.Spacing.xl) {
                stepContent
                Divider().padding(.horizontal, Theme.Spacing.xxl)
                navigationBar
            }
            .padding(Theme.Spacing.xxl)
            .frame(maxWidth: 720, maxHeight: 600)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("처음 시작 안내")
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome: welcomeStep
        case .modeSelection: modeSelectionStep
        case .customDetails: customDetailsStep
        case .complete: completeStep
        }
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            BrandLogo(size: 96)
                .accessibilityHidden(true)
            Text("Yuminai에 오신 것을 환영합니다")
                .font(Theme.Typography.display)
                .foregroundStyle(Theme.Color.text)
                .multilineTextAlignment(.center)
            Text("Claude · Codex 등 여러 LLM을 한 흐름으로 통합한\n바이브 코딩 워크스페이스입니다.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    // MARK: - Step 2: Mode selection

    private var modeSelectionStep: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: 6) {
                Text("어떻게 사용하시겠어요?")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
                Text("나중에 설정에서 언제든 바꿀 수 있어요.")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            VStack(spacing: Theme.Spacing.md) {
                ForEach(UsageMode.allCases) { mode in
                    modeCard(mode)
                }
            }
        }
    }

    private func modeCard(_ mode: UsageMode) -> some View {
        let isSelected = selectedMode == mode
        return Button {
            selectedMode = mode
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Theme.Color.accent : Theme.Color.surfaceHi)
                        .frame(width: 44, height: 44)
                    Image(systemName: mode.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isSelected ? Color.white : Theme.Color.textSecondary)
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(mode.title)
                            .font(Theme.Typography.body.weight(.semibold))
                            .foregroundStyle(Theme.Color.text)
                        Text("· \(mode.subtitle)")
                            .font(Theme.Typography.small)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    Text(mode.description)
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.Color.accent : Theme.Color.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.lg)
                    .fill(isSelected ? Theme.Color.accentMuted : Theme.Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg)
                    .stroke(isSelected ? Theme.Color.accent : Theme.Color.borderSubtle,
                            lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.title) — \(mode.subtitle)")
        .accessibilityHint(mode.description)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Step 3: Custom details (사용자 정의 선택 시)

    private var customDetailsStep: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: 6) {
                Text("표시할 항목을 선택하세요")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
                Text("끄면 설정 화면에 해당 옵션이 숨겨집니다. 나중에 ‘일반 → 사용 모드’에서 바꿀 수 있어요.")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 0) {
                customToggleRow(
                    title: "다중 모델 자동 전환",
                    description: "Claude / Codex 등 여러 LLM을 자동으로 전환하며 사용",
                    isOn: Binding(
                        get: { preferences.harnessAutoRoutingEnabled },
                        set: { preferences.harnessAutoRoutingEnabled = $0 }
                    )
                )
                Divider().padding(.leading, Theme.Spacing.md)
                customToggleRow(
                    title: "에이전트 자동 답장",
                    description: "한 에이전트의 응답에 다른 에이전트가 자동으로 답장",
                    isOn: Binding(
                        get: { preferences.agentChainEnabled },
                        set: { preferences.agentChainEnabled = $0 }
                    )
                )
                Divider().padding(.leading, Theme.Spacing.md)
                customToggleRow(
                    title: "텔레그램 알림",
                    description: "작업 완료/에러 시 텔레그램으로 알림",
                    isOn: Binding(
                        get: { preferences.telegramEnabled },
                        set: { preferences.telegramEnabled = $0 }
                    )
                )
            }
            .background(Theme.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg)
                    .stroke(Theme.Color.borderSubtle, lineWidth: 1)
            )
        }
    }

    private func customToggleRow(title: String, description: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.body.weight(.medium))
                    .foregroundStyle(Theme.Color.text)
                Text(description)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(title)
                .accessibilityHint(description)
        }
        .padding(Theme.Spacing.md)
    }

    // MARK: - Step 4: Complete

    private var completeStep: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Theme.Color.success.opacity(0.15))
                    .frame(width: 96, height: 96)
                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Theme.Color.success)
            }
            .accessibilityHidden(true)
            Text("준비 완료!")
                .font(Theme.Typography.display)
                .foregroundStyle(Theme.Color.text)
            Text(completionMessage)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Spacing.lg)
            Spacer()
        }
    }

    private var completionMessage: String {
        switch selectedMode {
        case .beginner:
            return "초보자 모드로 시작합니다.\n익숙해지면 ‘일반 → 사용 모드’에서 고급으로 바꿔보세요."
        case .advanced:
            return "고급 모드로 시작합니다.\n모든 기능과 ‘접근성 검사’ 탭을 사용할 수 있어요."
        case .custom:
            return "선택하신 옵션이 적용되었습니다.\n언제든 설정에서 바꿀 수 있어요."
        }
    }

    // MARK: - Navigation bar

    private var navigationBar: some View {
        HStack {
            if step.rawValue > 0 {
                Button("이전") {
                    goBack()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Color.textSecondary)
                .accessibilityLabel("이전 단계로")
            }

            // Step indicator
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { idx in
                    Circle()
                        .fill(idx == step.rawValue ? Theme.Color.accent : Theme.Color.borderSubtle)
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(step.rawValue + 1) / \(totalSteps) 단계")
            Spacer()

            FlatButton(primaryButtonLabel, variant: .primary, action: goForward)
                .accessibilityLabel(primaryButtonLabel)
        }
    }

    private var totalSteps: Int {
        selectedMode == .custom ? 4 : 3  // welcome, mode, [custom], complete
    }

    private var primaryButtonLabel: String {
        switch step {
        case .welcome: return "시작"
        case .modeSelection:
            return selectedMode == .custom ? "다음" : "다음"
        case .customDetails: return "다음"
        case .complete: return "Yuminai 시작하기"
        }
    }

    // MARK: - Navigation actions

    private func goForward() {
        switch step {
        case .welcome:
            step = .modeSelection
        case .modeSelection:
            // 모드 적용
            applyMode()
            if selectedMode == .custom {
                step = .customDetails
            } else {
                step = .complete
            }
        case .customDetails:
            step = .complete
        case .complete:
            preferences.hasCompletedOnboarding = true
            onComplete()
        }
    }

    private func goBack() {
        switch step {
        case .welcome: break
        case .modeSelection: step = .welcome
        case .customDetails: step = .modeSelection
        case .complete:
            step = (selectedMode == .custom) ? .customDetails : .modeSelection
        }
    }

    /// 사용자가 선택한 mode를 preferences에 적용.
    private func applyMode() {
        switch selectedMode {
        case .beginner:
            preferences.beginnerMode = true
        case .advanced:
            preferences.beginnerMode = false
        case .custom:
            // 사용자 정의 — beginnerMode = false (모든 옵션 보이게) + 다음 step에서 토글
            preferences.beginnerMode = false
        }
    }
}
