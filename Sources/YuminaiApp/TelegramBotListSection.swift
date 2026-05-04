import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-086 Phase 4 / ADR-101** — 봇 목록 섹션 (등록된 봇 추가/편집/삭제).
///
/// ADR-101 변경:
/// - `List` 기반으로 전환 (iOS 스타일 `.insetGrouped` 느낌)
/// - `swipeActions` — trailing: 삭제/편집
/// - `contextMenu` — 편집 / 활성화 토글 / 삭제
/// - `ExpandableInfoSection` — 부가 정보 점진 노출
struct TelegramBotListSection: View {
    @Environment(AppModel.self) private var appModel
    @State private var showAddBot: Bool = false
    @State private var editingBotId: UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("등록된 봇")
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer()
                FlatButton("새 봇 추가", variant: .secondary) {
                    showAddBot = true
                }
            }
            if appModel.preferences.telegramBots.isEmpty {
                EmptyStateHint(
                    icon: "person.crop.square.filled.and.at.rectangle",
                    title: "등록된 봇이 없어요",
                    message: "새 봇을 추가하면 여러 봇으로 다양한 그룹을 운영할 수 있어요."
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(appModel.preferences.telegramBots) { bot in
                        botRow(bot)
                            .listRowBackground(Theme.Color.surface)
                            .listRowSeparatorTint(Theme.Color.borderSubtle)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    Task { await appModel.removeTelegramBot(bot.id) }
                                } label: {
                                    Label("삭제", systemImage: "trash")
                                }
                                Button {
                                    editingBotId = bot.id
                                } label: {
                                    Label("편집", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                            .contextMenu {
                                Button {
                                    editingBotId = bot.id
                                } label: {
                                    Label("편집", systemImage: "pencil")
                                }
                                Button {
                                    let toggled = TelegramBotConfig(
                                        id: bot.id,
                                        displayName: bot.displayName,
                                        username: bot.username,
                                        keychainKey: bot.keychainKey,
                                        groupId: bot.groupId,
                                        allowedUserIds: bot.allowedUserIds,
                                        enabled: !bot.enabled,
                                        iconName: bot.iconName,
                                        colorName: bot.colorName,
                                        notes: bot.notes
                                    )
                                    Task { await appModel.updateTelegramBot(toggled) }
                                } label: {
                                    Label(
                                        bot.enabled ? "비활성화" : "활성화",
                                        systemImage: bot.enabled ? "pause.circle" : "play.circle"
                                    )
                                }
                                Divider()
                                Button(role: .destructive) {
                                    Task { await appModel.removeTelegramBot(bot.id) }
                                } label: {
                                    Label("삭제", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .frame(maxHeight: 300)
            }
        }
        .sheet(isPresented: $showAddBot) {
            TelegramBotEditSheet(existing: nil) { config in
                Task {
                    await appModel.addTelegramBot(config)
                    showAddBot = false
                }
            } onCancel: {
                showAddBot = false
            }
            .environment(appModel)
        }
        .sheet(item: Binding(
            get: { editingBotId.flatMap { id in appModel.preferences.telegramBots.first { $0.id == id } } },
            set: { _ in editingBotId = nil }
        )) { bot in
            TelegramBotEditSheet(existing: bot) { config in
                Task {
                    await appModel.updateTelegramBot(config)
                    editingBotId = nil
                }
            } onCancel: {
                editingBotId = nil
            }
            .environment(appModel)
        }
    }

    // MARK: - Bot Row

    private func botRow(_ bot: TelegramBotConfig) -> some View {
        let groupName = bot.groupId.flatMap { gid in
            appModel.preferences.telegramBotGroups.first { $0.id == gid }?.displayName
        }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 10) {
                // 아이콘
                Image(systemName: bot.iconName)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Color.folderColor(for: bot.colorName))
                    .frame(width: 28)
                    .accessibilityHidden(true)

                // 이름 + 배지 (항상 표시)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(bot.displayName)
                            .font(Theme.Typography.label)
                            .foregroundStyle(Theme.Color.text)
                        if !bot.enabled {
                            statusBadge("비활성", color: Theme.Color.textTertiary)
                        }
                        if let groupName {
                            statusBadge(groupName, color: Theme.Color.accent)
                        }
                    }
                    if !bot.username.isEmpty {
                        Text("@\(bot.username)")
                            .font(Theme.Typography.small)
                            .foregroundStyle(Theme.Color.textSecondary)
                            .textSelection(.enabled)
                    }
                }

                Spacer()

                // 빠른 편집 버튼 (hover 없이 항상 표시 — macOS List에서는 swipe 안 되므로)
                Button("편집") { editingBotId = bot.id }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Color.accent)
                    .font(Theme.Typography.small)
                    .accessibilityLabel("\(bot.displayName) 봇 편집")
            }

            // 점진 정보 노출 — chevron 클릭 시만 표시
            ExpandableInfoSection(label: "자세히 보기", labelIcon: "info.circle") {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    if !bot.notes.isEmpty {
                        infoLine(label: "메모", value: bot.notes)
                    }
                    infoLine(label: "macOS 비밀번호 저장소 키", value: bot.keychainKey)
                    infoLine(
                        label: "사용 가능한 사람",
                        value: bot.allowedUserIds.isEmpty
                            ? "전체 허용 (주의)"
                            : "\(bot.allowedUserIds.count)명 지정"
                    )
                    infoLine(label: "아이콘", value: bot.iconName)
                    infoLine(label: "색상", value: bot.colorName)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Helpers

    private func statusBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Theme.Typography.micro)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.10))
            .clipShape(Capsule())
    }

    private func infoLine(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text("\(label):")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
            Text(value)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
