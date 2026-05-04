import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-086 Phase 4 / ADR-101 / ADR-102** — 봇 그룹 섹션.
///
/// ADR-102: List → LazyVStack 카드 (TelegramBotListSection과 동일 패턴 — nested scroll 회피).
struct TelegramBotGroupSection: View {
    @Environment(AppModel.self) private var appModel
    @State private var showAddGroup: Bool = false
    @State private var editingGroupId: UUID? = nil
    @State private var confirmDeleteGroupId: UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("봇 그룹")
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer()
                FlatButton("새 그룹", icon: "plus", variant: .secondary) {
                    showAddGroup = true
                }
            }
            if appModel.preferences.telegramBotGroups.isEmpty {
                EmptyStateHint(
                    icon: "rectangle.3.group.fill",
                    title: "그룹이 없어요",
                    message: "그룹을 만들면 여러 봇에 공통 응답 모드/예산을 적용할 수 있어요."
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.lg)
            } else {
                LazyVStack(spacing: Theme.Spacing.sm) {
                    ForEach(appModel.preferences.telegramBotGroups) { group in
                        groupCard(group)
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
        .confirmationDialog(
            "이 그룹을 삭제할까요?",
            isPresented: Binding(
                get: { confirmDeleteGroupId != nil },
                set: { if !$0 { confirmDeleteGroupId = nil } }
            ),
            titleVisibility: .visible,
            presenting: confirmDeleteGroupId
        ) { id in
            Button("삭제", role: .destructive) {
                Task { await appModel.removeTelegramBotGroup(id) }
                confirmDeleteGroupId = nil
            }
            Button("취소", role: .cancel) {
                confirmDeleteGroupId = nil
            }
        } message: { _ in
            Text("그룹에 속한 봇들은 사라지지 않고 그룹 소속만 해제돼요.")
        }
    }

    // MARK: - Group Card

    private func groupCard(_ group: TelegramBotGroup) -> some View {
        let memberCount = appModel.preferences.telegramBots.filter { $0.groupId == group.id }.count
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .center, spacing: Theme.Spacing.sm + 2) {
                Image(systemName: group.iconName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.Color.folderColor(for: group.colorName))
                    .frame(width: 32, height: 32)
                    .background(Theme.Color.folderColor(for: group.colorName).opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(group.displayName)
                            .font(Theme.Typography.body.weight(.semibold))
                            .foregroundStyle(Theme.Color.text)
                        Text("봇 \(memberCount)개")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.Color.surfaceHi)
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                HStack(spacing: 4) {
                    Button {
                        editingGroupId = group.id
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 28, height: 28)
                            .foregroundStyle(Theme.Color.accent)
                            .background(Theme.Color.accentMuted)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    }
                    .buttonStyle(.plain)
                    .help("이 그룹 편집")
                    .accessibilityLabel("\(group.displayName) 그룹 편집")

                    Button {
                        confirmDeleteGroupId = group.id
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 28, height: 28)
                            .foregroundStyle(Theme.Color.danger)
                            .background(Theme.Color.danger.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    }
                    .buttonStyle(.plain)
                    .help("이 그룹 삭제")
                    .accessibilityLabel("\(group.displayName) 그룹 삭제")
                }
            }

            if group.responseModeOverride != nil || group.budgetOverride != nil || !group.sharedSkillIds.isEmpty {
                ExpandableInfoSection(label: "자세히 보기", labelIcon: "info.circle") {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        if let mode = group.responseModeOverride {
                            infoLine(label: "응답 모드 (그룹 우선)", value: mode.displayName)
                        }
                        if group.budgetOverride != nil {
                            infoLine(label: "예산 한도 (그룹 우선)", value: "설정됨")
                        }
                        if !group.sharedSkillIds.isEmpty {
                            infoLine(label: "공유 스킬", value: "\(group.sharedSkillIds.count)개")
                        }
                    }
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Theme.Color.borderSubtle, lineWidth: 0.5)
        )
        .contextMenu {
            Button {
                editingGroupId = group.id
            } label: {
                Label("편집", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                confirmDeleteGroupId = group.id
            } label: {
                Label("삭제", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func infoLine(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text("\(label):")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
            Text(value)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }
}
