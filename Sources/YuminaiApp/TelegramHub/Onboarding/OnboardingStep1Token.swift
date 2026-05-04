import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-092 Phase 1** — Onboarding Step 1: 봇 토큰 입력.
///
/// - BotFather 링크 (클릭 가능)
/// - 토큰 정규식 검증: `^\d+:[A-Za-z0-9_-]+$`
/// - 토큰 valid 시 ✅ 표시 + Username / DisplayName 입력
///
/// **Phase 2 예정**: getMe API 실제 호출로 username 자동 채우기.
struct OnboardingStep1Token: View {
    @Binding var token: String
    @Binding var username: String
    @Binding var displayName: String

    private var validationResult: TelegramTokenValidator.ValidationResult {
        TelegramTokenValidator.validate(token)
    }

    private var isTokenValid: Bool { validationResult.isValid }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            // 헤더
            HeaderHero(
                icon: "key.fill",
                iconTint: Theme.Color.accent,
                title: "봇 토큰 입력",
                subtitle: "BotFather에서 발급받은 토큰을 붙여 넣으세요. 토큰은 Mac Keychain에 안전하게 저장됩니다."
            )

            // BotFather 안내
            InfoCallout(tone: .info) {
                HStack(spacing: 6) {
                    Text("아직 봇이 없으신가요?")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textSecondary)
                    Link("BotFather 열기",
                         destination: URL(string: "https://t.me/botfather")!)
                        .font(Theme.Typography.small.weight(.medium))
                        .foregroundStyle(Theme.Color.accent)
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            // 토큰 입력 카드
            CardSection(style: .subtle) {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    SectionHeaderRow(
                        icon: "lock.fill",
                        iconColor: Theme.Color.accent,
                        title: "Bot Token",
                        required: true
                    )
                    HStack(spacing: Theme.Spacing.sm) {
                        SecureField(
                            "110201543:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw",
                            text: $token
                        )
                        .font(Theme.Typography.body)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        if !token.isEmpty {
                            tokenStatusIcon
                        }
                    }
                    if case .invalid(let reason) = validationResult, !token.isEmpty {
                        Text(reason)
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.danger)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isTokenValid)

            // 봇 정보 입력 (토큰 valid 이후 표시)
            if isTokenValid {
                CardSection(style: .subtle) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        SectionHeaderRow(
                            icon: "person.circle.fill",
                            iconColor: Theme.Color.accent,
                            title: "봇 정보",
                            caption: "Phase 2에서 getMe API로 자동 채우기 예정"
                        )
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            labeledField(
                                label: "Username",
                                placeholder: "my_bot",
                                text: $username,
                                hint: "BotFather에서 설정한 @username (@ 제외)"
                            )
                            labeledField(
                                label: "표시 이름",
                                placeholder: "내 Yuminai Bot",
                                text: $displayName,
                                hint: "Hub에서 구분할 이름 (자유롭게 설정)"
                            )
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isTokenValid)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Helpers

    private var tokenStatusIcon: some View {
        Group {
            if isTokenValid {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.Color.success)
                    .accessibilityLabel("유효한 토큰 형식")
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Theme.Color.danger)
                    .accessibilityLabel("잘못된 토큰 형식")
            }
        }
        .font(.system(size: 16))
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isTokenValid)
    }

    private func labeledField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        hint: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.Typography.label.weight(.medium))
                .foregroundStyle(Theme.Color.textSecondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(Theme.Typography.body)
                .autocorrectionDisabled()
            if let hint {
                Text(hint)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
        }
    }
}
