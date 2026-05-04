import SwiftUI
import YuminaiCore
import YuminaiUI
import YuminaiTelegram

/// **ADR-092 Phase 1** — Telegram 봇 등록 3-step Onboarding Wizard.
///
/// ## 단계
/// 1. **Step 1** — 봇 토큰 입력 + 형식 검증
/// 2. **Step 2** — 사용자 허용 목록 설정
/// 3. **Step 3** — 워크스페이스 바인딩 (선택)
///
/// 완료 시:
/// - `appModel.addTelegramBot(config)` 호출
/// - Chat ID와 워크스페이스가 지정됐으면 `appModel.upsertBotChatBinding(binding)` 호출
///
/// **Phase 2 예정**: Step 1에서 getMe API 호출로 username 자동 채우기.
struct TelegramOnboardingWizard: View {
    @Environment(AppModel.self) private var appModel
    let onDismiss: () -> Void

    // MARK: - 단계 상태

    @State private var currentStep: Int = 1
    private let totalSteps = 3

    // MARK: - Step 1 상태

    @State private var token: String = ""
    @State private var username: String = ""
    @State private var displayName: String = ""

    // MARK: - Step 2 상태

    @State private var allowedUserIdsText: String = ""

    // MARK: - Step 3 상태

    @State private var chatIdText: String = ""
    @State private var selectedWorkspaceId: UUID? = nil

    // MARK: - 완료 진행 중

    @State private var isSubmitting: Bool = false

    // MARK: - 검증

    private var step1Valid: Bool {
        TelegramTokenValidator.validate(token).isValid &&
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var canGoNext: Bool {
        switch currentStep {
        case 1: return step1Valid
        case 2: return true  // Step 2는 빈 목록도 허용
        case 3: return true  // Step 3는 선택 사항
        default: return false
        }
    }

    var body: some View {
        YuminaiSheet(width: 600, height: 580) {
            VStack(alignment: .leading, spacing: 0) {
                progressDots
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.top, Theme.Spacing.xl)
                    .padding(.bottom, Theme.Spacing.lg)
                Divider()
                stepContent
                    .padding(Theme.Spacing.xl)
            }
        } footer: {
            HStack(spacing: Theme.Spacing.md) {
                if currentStep > 1 {
                    FlatButton("이전", icon: "chevron.left", variant: .ghost) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            currentStep -= 1
                        }
                    }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                }
                Spacer()
                FlatButton("취소", variant: .secondary) {
                    onDismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
                if currentStep < totalSteps {
                    FlatButton("다음", icon: "chevron.right", variant: .primary) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            currentStep += 1
                        }
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canGoNext)
                } else {
                    FlatButton(isSubmitting ? "추가 중…" : "완료", variant: .primary) {
                        Task { await submit() }
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(isSubmitting)
                }
            }
        }
    }

    // MARK: - Progress Dots

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(1...totalSteps, id: \.self) { step in
                let isActive = step == currentStep
                let isCompleted = step < currentStep
                Circle()
                    .fill(isActive || isCompleted ? Theme.Color.accent : Theme.Color.borderStrong)
                    .frame(width: isActive ? 10 : 8, height: isActive ? 10 : 8)
                    .overlay(
                        isCompleted
                        ? Image(systemName: "checkmark")
                            .font(.system(size: 5, weight: .bold))
                            .foregroundStyle(.white)
                        : nil
                    )
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: currentStep)
                    .accessibilityLabel("Step \(step)\(isCompleted ? " (완료)" : isActive ? " (현재)" : "")")
            }
            Spacer()
            Text("\(currentStep) / \(totalSteps)")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case 1:
            OnboardingStep1Token(
                token: $token,
                username: $username,
                displayName: $displayName
            )
            .transition(stepTransition)
        case 2:
            OnboardingStep2Whitelist(
                allowedUserIdsText: $allowedUserIdsText,
                token: token
            )
            .transition(stepTransition)
        case 3:
            OnboardingStep3Binding(
                workspaces: appModel.workspaces,
                chatIdText: $chatIdText,
                selectedWorkspaceId: $selectedWorkspaceId
            )
            .transition(stepTransition)
        default:
            EmptyView()
        }
    }

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    // MARK: - Submit

    private func submit() async {
        guard step1Valid else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        let parsedUserIds = TelegramTokenValidator.parseUserIds(allowedUserIdsText)

        let config = TelegramBotConfig(
            displayName: displayName.trimmingCharacters(in: .whitespaces),
            username: username.trimmingCharacters(in: .whitespaces),
            keychainKey: "telegram.bot.\(UUID().uuidString)",
            allowedUserIds: parsedUserIds,
            enabled: true
        )
        await appModel.addTelegramBot(config)

        // Step 3: 바인딩 생성 (Chat ID + 워크스페이스 모두 있을 때)
        let trimmedChatId = chatIdText.trimmingCharacters(in: .whitespaces)
        if let chatId = Int64(trimmedChatId) {
            let binding = BotChatBinding(
                botId: config.id,
                chatId: chatId,
                activeWorkspaceId: selectedWorkspaceId,
                allowedWorkspaceIds: selectedWorkspaceId.map { [$0] } ?? []
            )
            await appModel.upsertBotChatBinding(binding)
        }

        onDismiss()
    }
}
