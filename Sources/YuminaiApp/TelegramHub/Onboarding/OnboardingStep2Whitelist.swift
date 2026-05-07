import SwiftUI
import YuminaiCore
import YuminaiTelegram
import YuminaiUI

/// **ADR-092 Phase 1 / ADR-095 Phase 4** — Onboarding Step 2: 사용자 허용 목록.
///
/// - 수동 user_id 입력 (콤마 구분)
/// - "비어있으면 모든 사용자 허용 (위험)" 경고 InfoCallout
/// - **/start 자동 감지** (ADR-095): 토큰이 있으면 즉시 polling 시작 →
///   `/start` 보낸 사용자 목록 표시 → 클릭 시 허용 목록 자동 추가.
struct OnboardingStep2Whitelist: View {
    @Binding var allowedUserIdsText: String
    /// Step 1에서 입력한 토큰 — 자동 감지에 사용. 빈 문자열이면 자동 감지 비활성.
    var token: String

    @State private var detectedUsers: [TelegramFirstMessageDetector.Detection] = []
    @State private var detector = TelegramFirstMessageDetector()
    @State private var isDetecting: Bool = false
    @State private var detectionTask: Task<Void, Never>? = nil

    private var parsedIds: [Int64] {
        TelegramTokenValidator.parseUserIds(allowedUserIdsText)
    }

    private var isEmpty: Bool { allowedUserIdsText.trimmingCharacters(in: .whitespaces).isEmpty }
    private var tokenValid: Bool { TelegramTokenValidator.validate(token).isValid }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            // 헤더
            HeaderHero(
                icon: "person.2.shield.fill",
                iconTint: Theme.Color.accent,
                title: TelegramHubFriendlyText.Whitelist.title,
                subtitle: TelegramHubFriendlyText.Whitelist.subtitle
            )

            // 경고 (비어있을 때)
            if isEmpty {
                InfoCallout(tone: .warning) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(TelegramHubFriendlyText.Whitelist.emptyWarningTitle)
                            .font(Theme.Typography.small.weight(.semibold))
                            .foregroundStyle(Theme.Color.text)
                        Text(TelegramHubFriendlyText.Whitelist.emptyHint)
                            .font(Theme.Typography.small)
                            .foregroundStyle(Theme.Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // User ID 입력 카드
            CardSection(style: .subtle) {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    SectionHeaderRow(
                        icon: "person.fill.checkmark",
                        iconColor: Theme.Color.accent,
                        title: TelegramHubFriendlyText.Whitelist.userIdsTitle,
                        caption: isEmpty ? "비어있음 = 전체 허용" : "\(parsedIds.count)명"
                    )
                    TextEditor(text: $allowedUserIdsText)
                        .font(Theme.Typography.body)
                        .frame(minHeight: 80, maxHeight: 120)
                        .scrollContentBackground(.hidden)
                        .background(Theme.Color.surfaceHi)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                        .autocorrectionDisabled()
                    Text("예시: 123456789, 987654321")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                    if !isEmpty && !parsedIds.isEmpty {
                        parsedIdBadges
                    } else if !allowedUserIdsText.isEmpty && parsedIds.isEmpty {
                        Text("숫자 ID만 인식돼요. 잘못된 항목은 건너뜁니다.")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.warning)
                    }
                }
            }

            // /start 자동 감지 카드 (ADR-095 Phase 4)
            CardSection(style: .subtle) {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    SectionHeaderRow(
                        icon: "antenna.radiowaves.left.and.right",
                        iconColor: tokenValid ? Theme.Color.accent : Theme.Color.textTertiary,
                        title: "/start 자동 감지",
                        caption: isDetecting ? "감지 중…" : (tokenValid ? "활성" : "토큰 입력 후 활성화")
                    ) {
                        if isDetecting {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }

                    if tokenValid {
                        Text("봇에 /start를 보내면 자동으로 감지됩니다. 감지된 사용자를 클릭하면 허용 목록에 추가할 수 있어요.")
                            .font(Theme.Typography.small)
                            .foregroundStyle(Theme.Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if !detectedUsers.isEmpty {
                            detectedUserList
                        } else if isDetecting {
                            HStack(spacing: 6) {
                                Image(systemName: "iphone.radiowaves.left.and.right")
                                    .foregroundStyle(Theme.Color.textTertiary)
                                    .font(.system(size: 14))
                                Text("폰에서 봇에 /start를 보내세요…")
                                    .font(Theme.Typography.small)
                                    .foregroundStyle(Theme.Color.textTertiary)
                            }
                            .transition(.opacity)
                        }
                    } else {
                        Text("Step 1에서 유효한 토큰을 입력하면 /start 자동 감지가 활성화됩니다.")
                            .font(Theme.Typography.small)
                            .foregroundStyle(Theme.Color.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isEmpty)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: detectedUsers.count)
        .task {
            await startDetectionIfPossible()
        }
        .onDisappear {
            stopDetection()
        }
    }

    // MARK: - 감지된 사용자 목록

    private var detectedUserList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(detectedUsers) { user in
                detectedUserRow(user)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func detectedUserRow(_ user: TelegramFirstMessageDetector.Detection) -> some View {
        let alreadyAdded = parsedIds.contains(user.userId)
        return HStack(spacing: 8) {
            Image(systemName: alreadyAdded ? "checkmark.circle.fill" : "person.circle")
                .foregroundStyle(alreadyAdded ? Theme.Color.success : Theme.Color.accent)
                .font(.system(size: 18))

            VStack(alignment: .leading, spacing: 2) {
                Text(user.firstName + (user.username.map { " (@\($0))" } ?? ""))
                    .font(Theme.Typography.small.weight(.medium))
                    .foregroundStyle(Theme.Color.text)
                Text("ID: \(user.userId)")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
            }

            Spacer()

            if !alreadyAdded {
                FlatButton("추가", icon: "plus.circle.fill", variant: .secondary) {
                    addUserToWhitelist(user.userId)
                }
            } else {
                Text("추가됨")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.success)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private var parsedIdBadges: some View {
        FlowLayout(spacing: 6) {
            ForEach(parsedIds, id: \.self) { userId in
                Text("\(userId)")
                    .font(Theme.Typography.micro.weight(.medium))
                    .foregroundStyle(Theme.Color.text)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.Color.accent.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Theme.Color.accent.opacity(0.25), lineWidth: 0.5)
                    )
            }
        }
    }

    private func addUserToWhitelist(_ userId: Int64) {
        let current = allowedUserIdsText.trimmingCharacters(in: .whitespaces)
        if current.isEmpty {
            allowedUserIdsText = "\(userId)"
        } else {
            allowedUserIdsText = "\(current), \(userId)"
        }
    }

    private func startDetectionIfPossible() async {
        guard tokenValid, !token.isEmpty else { return }

        isDetecting = true
        detectionTask?.cancel()

        detectionTask = Task {
            do {
                let stream = try await detector.startDetecting(token: token)
                for await detection in stream {
                    // 중복 제거
                    if !detectedUsers.contains(where: { $0.userId == detection.userId }) {
                        detectedUsers.append(detection)
                    }
                }
            } catch {
                // 토큰 오류 등 — 조용히 무시
            }
            isDetecting = false
        }
    }

    private func stopDetection() {
        detectionTask?.cancel()
        detectionTask = nil
        Task { await detector.stop() }
    }
}

// MARK: - FlowLayout (간단한 줄바꿈 레이아웃)

/// 태그/배지 등을 자동 줄바꿈해서 나열하는 레이아웃.
private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var totalHeight: CGFloat = 0
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if lineWidth + size.width + (lineWidth > 0 ? spacing : 0) > maxWidth {
                totalHeight += lineHeight + spacing
                lineWidth = size.width
                lineHeight = size.height
            } else {
                lineWidth += size.width + (lineWidth > 0 ? spacing : 0)
                lineHeight = max(lineHeight, size.height)
            }
        }
        totalHeight += lineHeight
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += lineHeight + spacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
