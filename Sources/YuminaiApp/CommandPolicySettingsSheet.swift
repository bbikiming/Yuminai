import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-133** — 명령 정책 설정 Sheet wrapper.
///
/// `CommandPolicySettingsView`를 Sheet 컨테이너로 감싼다.
/// 진입점: AutoRunSettingsView 안 [명령 정책 편집] 버튼 또는 RootView 전역 sheet.
struct CommandPolicySettingsSheet: View {

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var bindable = appModel
        VStack(spacing: 0) {
            SheetHeader(
                icon: "shield.lefthalf.filled",
                title: "명령 정책 설정",
                onClose: { dismiss() }
            ) {
                Button {
                    appModel.preferences = {
                        var p = appModel.preferences
                        p.commandPolicy = .default
                        return p
                    }()
                } label: {
                    Text("기본값으로 초기화")
                        .font(Theme.Typography.small.weight(.medium))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .buttonStyle(.plain)
            }

            CommandPolicySettingsView(policy: $bindable.preferences.commandPolicy)

            Divider()

            // 저장 버튼
            HStack {
                Spacer()
                Button("닫기") {
                    Task { await appModel.savePreferences() }
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(Theme.Typography.body.weight(.semibold))
                .foregroundStyle(Theme.Color.accent)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
            }
            .background(Theme.Color.surface)
        }
        .frame(minWidth: 580, minHeight: 500)
        .background(Theme.Color.bg)
    }
}
