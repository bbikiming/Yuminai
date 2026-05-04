import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-092 Phase 1 / ADR-093 Phase 2** — Onboarding Step 1: 봇 토큰 입력 + getMe 검증.
///
/// - BotFather 링크 (클릭 가능)
/// - 토큰 정규식 검증: `^\d+:[A-Za-z0-9_-]+$`
/// - 형식 valid + "검증" 버튼 클릭 → `getMe` API 호출
/// - 성공 시 username / displayName 자동 채우기
/// - 검증 중 spinner, 성공/실패 피드백 표시
struct OnboardingStep1Token: View {
    @Binding var token: String
    @Binding var username: String
    @Binding var displayName: String

    @State private var validationState: ValidationState = .idle

    private var validationResult: TelegramTokenValidator.ValidationResult {
        TelegramTokenValidator.validate(token)
    }

    private var isTokenFormatValid: Bool { validationResult.isValid }

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
                        .onChange(of: token) { _, _ in
                            // 토큰이 바뀌면 검증 상태 초기화
                            if case .success = validationState { } else { }
                            validationState = .idle
                        }
                        tokenStatusIcon
                    }
                    if case .invalid(let reason) = validationResult, !token.isEmpty {
                        Text(reason)
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.danger)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // getMe 검증 버튼 (형식이 맞을 때만)
                    if isTokenFormatValid {
                        getMeVerifyButton
                    }

                    // getMe 결과 피드백
                    validationFeedback
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isTokenFormatValid)

            // 봇 정보 입력 (검증 성공 이후 표시)
            if case .success = validationState {
                botInfoCard
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: true)
            } else if isTokenFormatValid && validationState == .idle {
                // 형식 유효하면 수동 입력 허용
                botInfoCard
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isTokenFormatValid)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - getMe 검증 버튼

    private var getMeVerifyButton: some View {
        HStack {
            Spacer()
            switch validationState {
            case .validating:
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.75)
                    Text("봇 정보 확인 중...")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            case .success:
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.Color.success)
                    Text("검증 완료")
                        .font(Theme.Typography.small.weight(.medium))
                        .foregroundStyle(Theme.Color.success)
                }
            case .idle, .failed:
                FlatButton(
                    validationState == .idle ? "Telegram에서 검증" : "재시도",
                    icon: "network",
                    variant: .secondary
                ) {
                    validateWithGetMe()
                }
            }
        }
    }

    // MARK: - 검증 피드백

    @ViewBuilder
    private var validationFeedback: some View {
        if case .failed(let message) = validationState {
            InfoCallout(tone: .warning) {
                Text(message)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: - 봇 정보 카드

    private var botInfoCard: some View {
        CardSection(style: .subtle) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeaderRow(
                    icon: "person.circle.fill",
                    iconColor: Theme.Color.accent,
                    title: "봇 정보"
                ) {
                    if case .success = validationState {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.Color.success)
                            Text("자동 채워짐")
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Color.success)
                        }
                    }
                }
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
    }

    // MARK: - Token status icon

    private var tokenStatusIcon: some View {
        Group {
            if token.isEmpty {
                EmptyView()
            } else if case .success = validationState {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Theme.Color.success)
                    .accessibilityLabel("Telegram 검증 완료")
            } else if isTokenFormatValid {
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
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isTokenFormatValid)
    }

    // MARK: - getMe API 호출

    private func validateWithGetMe() {
        validationState = .validating
        let tokenCopy = token.trimmingCharacters(in: .whitespaces)
        Task {
            do {
                let info = try await TelegramTokenValidator.fetchBotInfo(token: tokenCopy)
                await MainActor.run {
                    // username, displayName 자동 채우기
                    if username.isEmpty {
                        username = info.username
                    }
                    if displayName.isEmpty {
                        displayName = info.firstName
                    }
                    validationState = .success(info)
                }
            } catch let networkError as TelegramNetworkError {
                await MainActor.run {
                    validationState = .failed(networkError.localizedDescription ?? "검증 실패")
                }
            } catch {
                await MainActor.run {
                    validationState = .failed(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Helpers

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

// MARK: - ValidationState

/// getMe API 검증 상태 머신.
private enum ValidationState: Equatable {
    case idle
    case validating
    case success(TelegramBotInfo)
    case failed(String)

    static func == (lhs: ValidationState, rhs: ValidationState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.validating, .validating): return true
        case (.success(let a), .success(let b)): return a == b
        case (.failed(let a), .failed(let b)): return a == b
        default: return false
        }
    }
}
