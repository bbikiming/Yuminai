import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-086 Phase 4 / ADR-101 / ADR-102** — 봇 목록 섹션 (등록된 봇 추가/편집/삭제).
///
/// ADR-102 변경:
/// - `List` → `LazyVStack` 카드 스타일 (YuminaiSheet의 wrapInScrollView와 nested scroll 회피)
/// - `swipeActions` 제거 (macOS 트랙패드 swipe는 List 전용 + 사용자에게 잘 안 보임)
/// - `contextMenu` (우클릭 메뉴) 유지 — macOS 자연스러운 인터랙션
/// - 편집/삭제 inline 버튼 row 우측에 배치 (시각적으로 명확)
/// - `ExpandableInfoSection` — 부가 정보 점진 노출 유지
struct TelegramBotListSection: View {
    @Environment(AppModel.self) private var appModel
    @State private var showAddBot: Bool = false
    @State private var editingBotId: UUID? = nil
    @State private var confirmDeleteBotId: UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("등록된 봇")
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer()
                FlatButton("새 봇 추가", icon: "plus", variant: .secondary) {
                    showAddBot = true
                }
            }
            if appModel.preferences.telegramBots.isEmpty {
                EmptyStateHint(
                    icon: "person.crop.square.filled.and.at.rectangle",
                    title: "등록된 봇이 없어요",
                    message: "[새 봇 추가]를 눌러 첫 봇을 등록하세요. 또는 [cokacdir에서] 버튼으로 한 번에 가져올 수 있어요."
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.xl)
            } else {
                LazyVStack(spacing: Theme.Spacing.sm) {
                    ForEach(appModel.preferences.telegramBots) { bot in
                        botCard(bot)
                    }
                }
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
        .confirmationDialog(
            "이 봇을 삭제할까요?",
            isPresented: Binding(
                get: { confirmDeleteBotId != nil },
                set: { if !$0 { confirmDeleteBotId = nil } }
            ),
            titleVisibility: .visible,
            presenting: confirmDeleteBotId
        ) { id in
            Button("삭제", role: .destructive) {
                Task { await appModel.removeTelegramBot(id) }
                confirmDeleteBotId = nil
            }
            Button("취소", role: .cancel) {
                confirmDeleteBotId = nil
            }
        } message: { _ in
            Text("이 봇과 연결된 대화방 설정도 함께 사라져요. 봇 토큰은 macOS 비밀번호 저장소에서 즉시 제거됩니다.")
        }
    }

    // MARK: - Bot Card

    private func botCard(_ bot: TelegramBotConfig) -> some View {
        let groupName = bot.groupId.flatMap { gid in
            appModel.preferences.telegramBotGroups.first { $0.id == gid }?.displayName
        }
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .center, spacing: Theme.Spacing.sm + 2) {
                // 아이콘
                Image(systemName: bot.iconName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.Color.folderColor(for: bot.colorName))
                    .frame(width: 32, height: 32)
                    .background(Theme.Color.folderColor(for: bot.colorName).opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    .accessibilityHidden(true)

                // 이름 + 배지 (항상 표시)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(bot.displayName)
                            .font(Theme.Typography.body.weight(.semibold))
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

                // inline 버튼 — 편집(파랑) / 삭제(빨강)
                HStack(spacing: 4) {
                    Button {
                        editingBotId = bot.id
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 28, height: 28)
                            .foregroundStyle(Theme.Color.accent)
                            .background(Theme.Color.accentMuted)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    }
                    .buttonStyle(.plain)
                    .help("이 봇 편집")
                    .accessibilityLabel("\(bot.displayName) 봇 편집")

                    Button {
                        confirmDeleteBotId = bot.id
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 28, height: 28)
                            .foregroundStyle(Theme.Color.danger)
                            .background(Theme.Color.danger.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    }
                    .buttonStyle(.plain)
                    .help("이 봇 삭제")
                    .accessibilityLabel("\(bot.displayName) 봇 삭제")
                }
            }

            // 점진 정보 노출
            ExpandableInfoSection(label: "자세히 보기", labelIcon: "info.circle") {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    if !bot.notes.isEmpty {
                        infoLine(label: "메모", value: bot.notes)
                    }
                    infoLine(label: "macOS 비밀번호 저장소 키", value: bot.keychainKey)
                    infoLine(
                        label: "사용 가능한 사람",
                        value: bot.allowedUserIds.isEmpty
                            ? "전체 허용 (보안 주의)"
                            : "\(bot.allowedUserIds.count)명 지정"
                    )
                    infoLine(label: "아이콘", value: bot.iconName)
                    infoLine(label: "색상", value: bot.colorName)
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
                confirmDeleteBotId = bot.id
            } label: {
                Label("삭제", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Helpers

    private func statusBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Theme.Typography.micro)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func infoLine(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
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
