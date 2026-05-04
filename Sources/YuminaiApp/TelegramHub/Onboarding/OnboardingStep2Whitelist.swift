import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-092 Phase 1** — Onboarding Step 2: 사용자 허용 목록.
///
/// - 수동 user_id 입력 (콤마 구분)
/// - "비어있으면 모든 사용자 허용 (위험)" 경고 InfoCallout
///
/// **Phase 2 예정**: /start 메시지 자동 감지로 user_id 추가.
struct OnboardingStep2Whitelist: View {
    @Binding var allowedUserIdsText: String

    private var parsedIds: [Int64] {
        TelegramTokenValidator.parseUserIds(allowedUserIdsText)
    }

    private var isEmpty: Bool { allowedUserIdsText.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            // 헤더
            HeaderHero(
                icon: "person.2.shield.fill",
                iconTint: Theme.Color.accent,
                title: "사용자 허용 목록",
                subtitle: "이 봇에 접근을 허용할 텔레그램 사용자 ID를 지정하세요. 나중에 봇 설정에서 언제든 수정할 수 있어요."
            )

            // 경고 (비어있을 때)
            if isEmpty {
                InfoCallout(tone: .warning) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("모든 사용자 허용 (위험)")
                            .font(Theme.Typography.small.weight(.semibold))
                            .foregroundStyle(Theme.Color.text)
                        Text("허용 목록이 비어있으면 누구나 이 봇에 메시지를 보낼 수 있어요. 개인용이라면 본인 ID를 꼭 추가하세요.")
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
                        title: "허용된 User IDs",
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

            // Phase 2 placeholder
            CardSection(style: .subtle) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    SectionHeaderRow(
                        icon: "antenna.radiowaves.left.and.right",
                        iconColor: Theme.Color.textTertiary,
                        title: "/start 자동 감지",
                        caption: "Phase 2에서 추가 예정"
                    )
                    Text("Phase 2에서는 봇에 /start를 보낸 사용자를 자동으로 감지하여 허용 목록에 추가할 수 있어요.")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isEmpty)
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
