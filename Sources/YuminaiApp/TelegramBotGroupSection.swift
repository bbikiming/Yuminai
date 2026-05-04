import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-086 Phase 4 / ADR-101** — 봇 그룹 섹션 (그룹 추가/편집/삭제).
///
/// ADR-101: List + swipeActions + contextMenu + ExpandableInfoSection 점진 노출.
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
                List {
                    ForEach(appModel.preferences.telegramBotGroups) { group in
                        groupRow(group)
                            .listRowBackground(Theme.Color.surface)
                            .listRowSeparatorTint(Theme.Color.borderSubtle)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    Task { await appModel.removeTelegramBotGroup(group.id) }
                                } label: {
                                    Label("삭제", systemImage: "trash")
                                }
                                Button {
                                    editingGroupId = group.id
                                } label: {
                                    Label("편집", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                            .contextMenu {
                                Button {
                                    editingGroupId = group.id
                                } label: {
                                    Label("편집", systemImage: "pencil")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    Task { await appModel.removeTelegramBotGroup(group.id) }
                                } label: {
                                    Label("삭제", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .frame(maxHeight: 200)
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

    // MARK: - Group Row

    private func groupRow(_ group: TelegramBotGroup) -> some View {
        let memberCount = appModel.preferences.telegramBots.filter { $0.groupId == group.id }.count
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 10) {
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
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.Color.surfaceHi)
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                Button("편집") { editingGroupId = group.id }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Color.accent)
                    .font(Theme.Typography.small)
                    .accessibilityLabel("\(group.displayName) 그룹 편집")
            }

            // 점진 정보 노출 — override/budget 정보
            if group.responseModeOverride != nil || group.budgetOverride != nil || !group.sharedSkillIds.isEmpty {
                ExpandableInfoSection(label: "자세히 보기", labelIcon: "info.circle") {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        if let mode = group.responseModeOverride {
                            infoLine(label: "응답 모드 override", value: mode.displayName)
                        }
                        if group.budgetOverride != nil {
                            infoLine(label: "Budget override", value: "설정됨")
                        }
                        if !group.sharedSkillIds.isEmpty {
                            infoLine(label: "공유 스킬", value: "\(group.sharedSkillIds.count)개")
                        }
                    }
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
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
