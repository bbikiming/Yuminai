import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-086 Phase 4** — 봇 그룹 섹션 (그룹 추가/편집/삭제).
struct TelegramBotGroupSection: View {
    @Environment(AppModel.self) private var appModel
    @State private var showAddGroup: Bool = false
    @State private var editingGroupId: UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("봇 그룹")
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer()
                FlatButton("새 그룹", variant: .secondary) {
                    showAddGroup = true
                }
            }
            if appModel.preferences.telegramBotGroups.isEmpty {
                EmptyStateHint(
                    icon: "rectangle.3.group.fill",
                    title: "그룹이 없어요",
                    message: "그룹을 만들면 여러 봇에 공통 응답 모드/budget을 적용할 수 있어요."
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(appModel.preferences.telegramBotGroups) { group in
                            groupRow(group)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showAddGroup) {
            TelegramBotGroupEditSheet(existing: nil) { group in
                Task {
                    await appModel.addTelegramBotGroup(group)
                    showAddGroup = false
                }
            } onCancel: {
                showAddGroup = false
            }
        }
        .sheet(item: Binding(
            get: { editingGroupId.flatMap { id in appModel.preferences.telegramBotGroups.first { $0.id == id } } },
            set: { _ in editingGroupId = nil }
        )) { group in
            TelegramBotGroupEditSheet(existing: group) { updated in
                Task {
                    await appModel.updateTelegramBotGroup(updated)
                    editingGroupId = nil
                }
            } onCancel: {
                editingGroupId = nil
            }
        }
    }

    private func groupRow(_ group: TelegramBotGroup) -> some View {
        let memberCount = appModel.preferences.telegramBots.filter { $0.groupId == group.id }.count
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: group.iconName)
                .font(.system(size: 16))
                .foregroundStyle(Theme.Color.folderColor(for: group.colorName))
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(group.displayName)
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Color.text)
                    Text("봇 \(memberCount)개")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
                if let mode = group.responseModeOverride {
                    Text("응답 모드 override: \(mode.displayName)")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                if group.budgetOverride != nil {
                    Text("Budget override 설정됨")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
            Spacer()
            Button("편집") { editingGroupId = group.id }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Color.accent)
                .accessibilityLabel("\(group.displayName) 그룹 편집")
            Button("삭제", role: .destructive) {
                Task { await appModel.removeTelegramBotGroup(group.id) }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Color.danger)
            .accessibilityLabel("\(group.displayName) 그룹 삭제")
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .accessibilityElement(children: .contain)
    }
}
