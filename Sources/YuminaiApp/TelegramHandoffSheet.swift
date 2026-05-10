import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-151** — 텔레그램 핸드오프 확인 sheet.
///
/// 사용자가 "📱 텔레그램으로 이어서" 버튼을 탭하면 표시:
/// - 어느 텔레그램 채팅으로 보낼지 확인
/// - 전송할 컨텍스트 미리보기
/// - 봇 미연결 시 안내 (Hub 진입 링크)
struct TelegramHandoffSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var sentSuccessfully = false

    var body: some View {
        YuminaiSheet(width: 480, height: 380) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                Divider()
                if appModel.preferences.telegramBotChatBindings.isEmpty {
                    noBindingView
                } else {
                    contentView
                }
            }
            .padding(Theme.Spacing.lg)
        } footer: {
            footerButtons
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("텔레그램으로 이어서 작업하기")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
                Text("현재 세션 컨텍스트를 텔레그램으로 전송합니다")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
            }

            Spacer()

            SheetCloseButton(action: { dismiss() })
        }
    }

    // MARK: - No binding view

    private var noBindingView: some View {
        VStack(spacing: Theme.Spacing.md) {
            Spacer()
            Image(systemName: "link.badge.plus")
                .font(.system(size: 36))
                .foregroundStyle(Theme.Color.textTertiary)

            Text("연결된 텔레그램 채팅이 없어요")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Color.text)

            Text("Telegram Hub에서 봇을 등록하고 채팅과 워크스페이스를 연결해 주세요.\n연결 후 이 버튼으로 진행 중인 작업을 이어서 할 수 있어요.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Color.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                dismiss()
                appModel.showTelegramHubSheet = true
            } label: {
                Label("Telegram Hub 열기", systemImage: "paperplane.circle.fill")
                    .font(Theme.Typography.body.weight(.medium))
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Content view (binding 있을 때)

    private var contentView: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // 전송 대상 표시
            targetBindingRow

            Divider()

            // 컨텍스트 미리보기
            previewSection

            if let error = errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Typography.small)
                    .foregroundStyle(.red)
            }

            if sentSuccessfully {
                Label("전송 완료! 텔레그램에서 이어서 작업하세요.", systemImage: "checkmark.circle.fill")
                    .font(Theme.Typography.small)
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - Target binding row

    private var targetBindingRow: some View {
        let binding = appModel.preferences.telegramBotChatBindings.first
        let botConfig = binding.flatMap { b in
            appModel.preferences.telegramBots.first { $0.id == b.botId }
        }

        return HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "paperplane.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("전송 대상")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                HStack(spacing: 6) {
                    if let bot = botConfig {
                        Text("@\(bot.username)")
                            .font(Theme.Typography.monoSmall)
                            .foregroundStyle(Theme.Color.text)
                    }
                    if let b = binding {
                        Text("· chat \(b.chatId)")
                            .font(Theme.Typography.monoSmall)
                            .foregroundStyle(Theme.Color.textSecondary)
                        if !b.nickname.isEmpty {
                            Text("(\(b.nickname))")
                                .font(Theme.Typography.small)
                                .foregroundStyle(Theme.Color.textTertiary)
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Color.surfaceHi)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    // MARK: - Preview section

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("전송할 메시지 미리보기")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)

            ScrollView {
                Text(previewText)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 100)
            .padding(Theme.Spacing.sm)
            .background(Theme.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .stroke(Theme.Color.borderSubtle, lineWidth: 0.5)
            )
        }
    }

    private var previewText: String {
        let session = appModel.activeChatSession
        let wsId = session?.workspaceId ?? appModel.selectedWorkspaceId
        let workspaceName = wsId.flatMap { id in
            appModel.workspaces.first { $0.id == id }?.name
        }
        let lastUserPrompt = appModel.messages.last(where: { $0.role == .user })?.content

        return TelegramHandoffFormatter.format(
            workspaceName: workspaceName,
            lastUserPrompt: lastUserPrompt,
            sessionTitle: session?.title
        )
    }

    // MARK: - Footer buttons

    private var footerButtons: some View {
        HStack {
            Button("취소") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Color.textSecondary)

            Spacer()

            if !appModel.preferences.telegramBotChatBindings.isEmpty {
                Button {
                    sendHandoff()
                } label: {
                    if isSending {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("전송 중…")
                        }
                    } else {
                        Label("텔레그램으로 전송", systemImage: "paperplane.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSending || sentSuccessfully)
            }
        }
    }

    // MARK: - Actions

    private func sendHandoff() {
        isSending = true
        errorMessage = nil

        Task {
            let result = await appModel.handoffActiveSessionToTelegram()
            await MainActor.run {
                isSending = false
                switch result {
                case .success:
                    sentSuccessfully = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        dismiss()
                    }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
