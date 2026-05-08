import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-092 Phase 1** — Onboarding Step 3: 워크스페이스 바인딩.
///
/// - Chat ID 입력 (선택 — 비어있으면 binding 생성 안 함)
/// - Chat ID가 있으면 워크스페이스 picker 표시
/// - 비어있으면 "나중에 추가 가능" 안내
struct OnboardingStep3Binding: View {
    let workspaces: [Workspace]
    @Binding var chatIdText: String
    @Binding var selectedWorkspaceId: UUID?

    private var parsedChatId: Int64? {
        let trimmed = chatIdText.trimmingCharacters(in: .whitespaces)
        return Int64(trimmed)
    }

    private var hasChatId: Bool { parsedChatId != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            // 헤더
            HeaderHero(
                icon: "link.circle.fill",
                iconTint: Theme.Color.accent,
                title: "작업 폴더 연결 (선택)",
                subtitle: "대화방 번호를 지정하면 해당 대화방을 특정 작업 폴더에 바로 연결할 수 있어요. 지금 건너뛰고 나중에 추가해도 됩니다."
            )

            // Chat ID 입력
            CardSection(style: .subtle) {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    SectionHeaderRow(
                        icon: "number.circle.fill",
                        iconColor: Theme.Color.accent,
                        title: "대화방 번호",
                        caption: "선택 사항"
                    )
                    HStack(spacing: Theme.Spacing.sm) {
                        TextField("-100123456789 또는 123456789", text: $chatIdText)
                            .font(Theme.Typography.body)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                        if !chatIdText.isEmpty {
                            chatIdStatusIcon
                        }
                    }
                    if let chatId = parsedChatId {
                        HStack(spacing: 4) {
                            Image(systemName: chatId < 0 ? "person.3.fill" : "person.crop.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(chatId < 0 ? Theme.Color.warningStrong : Theme.Color.accent)
                            Text(chatId < 0 ? "그룹 채팅" : "1:1 대화")
                                .font(Theme.Typography.micro)
                                .foregroundStyle(chatId < 0 ? Theme.Color.warningStrong : Theme.Color.accent)
                        }
                        .transition(.opacity)
                    }
                    Text("그룹 채팅이면 음수 (예: -100123456789), 1:1 대화면 양수 (예: 123456789).")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !chatIdText.isEmpty && parsedChatId == nil {
                        Text("숫자만 입력해 주세요. 음수(-) 포함 가능.")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.danger)
                    }
                }
            }

            // 워크스페이스 Picker (Chat ID 입력 시 표시)
            if hasChatId {
                workspacePickerCard
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                skipNotice
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer(minLength: 0)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: hasChatId)
        .onChange(of: hasChatId) { _, newValue in
            if !newValue {
                selectedWorkspaceId = nil
            }
        }
    }

    // MARK: - Workspace Picker

    private var workspacePickerCard: some View {
        CardSection(style: .subtle) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeaderRow(
                    icon: "folder.fill",
                    iconColor: Theme.Color.accent,
                    title: "연결할 작업 폴더"
                )
                if workspaces.isEmpty {
                    InfoCallout(tone: .warning) {
                        Text("작업 폴더가 없어요. 메인 화면에서 먼저 작업 폴더를 만들어 주세요.")
                            .font(Theme.Typography.small)
                            .foregroundStyle(Theme.Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(workspaces) { ws in
                                workspaceRow(ws)
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }
            }
        }
    }

    private func workspaceRow(_ ws: Workspace) -> some View {
        let isSelected = selectedWorkspaceId == ws.id
        return RadioCardButton(
            isSelected: isSelected,
            accentColor: Theme.Color.accent,
            action: {
                selectedWorkspaceId = isSelected ? nil : ws.id
            }
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ws.name)
                    .font(Theme.Typography.label.weight(.medium))
                    .foregroundStyle(Theme.Color.text)
                Text(ws.directoryPath)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    // MARK: - Skip Notice

    private var skipNotice: some View {
        InfoCallout(tone: .info) {
            VStack(alignment: .leading, spacing: 4) {
                Text("지금 건너뛰어도 됩니다")
                    .font(Theme.Typography.small.weight(.semibold))
                    .foregroundStyle(Theme.Color.text)
                Text("봇이 추가된 후 Hub의 연결 탭에서 언제든지 대화방 → 작업 폴더 연결을 추가할 수 있어요.")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Helpers

    private var chatIdStatusIcon: some View {
        Group {
            if parsedChatId != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.Color.success)
                    .accessibilityLabel("유효한 Chat ID")
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Theme.Color.danger)
                    .accessibilityLabel("잘못된 Chat ID")
            }
        }
        .font(.system(size: 16))
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: parsedChatId != nil)
    }
}
