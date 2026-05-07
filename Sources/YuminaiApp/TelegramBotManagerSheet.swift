import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-086 Phase 4** — Multi-bot 관리 sheet.
///
/// 3개 섹션:
/// 1. **봇 목록**: 등록된 봇들 (이름/username/그룹/상태) + 추가/편집/삭제
/// 2. **그룹 관리**: 봇을 묶을 그룹 (응답 모드/budget override)
/// 3. **Chat ↔ Workspace 매핑**: 봇별 chat이 어떤 워크스페이스로 연결되는지
///
/// 사용 시나리오:
/// - 시나리오 A: 1봇 × N워크스페이스 (한 봇으로 여러 프로젝트 — chat별 workspace 다름)
/// - 시나리오 B: N봇 × M그룹 (팀별 봇 격리 + 그룹별 정책)
struct TelegramBotManagerSheet: View {
    @Environment(AppModel.self) private var appModel
    @State private var section: Section = .bots

    enum Section: String, CaseIterable, Identifiable {
        case bots = "봇 목록"
        case groups = "그룹"
        case bindings = "Chat ↔ Workspace"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .bots: return "person.crop.square.filled.and.at.rectangle"
            case .groups: return "rectangle.3.group.fill"
            case .bindings: return "link.circle.fill"
            }
        }
    }

    var body: some View {
        YuminaiSheet(width: 760, height: 620) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                segmentedNav
                Divider()
                contentArea
            }
            .padding(Theme.Spacing.xl)
        } footer: {
            HStack {
                Text(footerSummary)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                Spacer()
                FlatButton("닫기", variant: .primary) {
                    appModel.showTelegramBotManagerSheet = false
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .overlay(alignment: .topTrailing) {
            SheetCloseButton { appModel.showTelegramBotManagerSheet = false }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "person.3.fill")
                    .foregroundStyle(Theme.Color.accent)
                    .accessibilityHidden(true)
                Text("Multi-Bot 관리")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
            }
            Text("여러 텔레그램 봇을 그룹으로 운영하거나, 한 봇으로 여러 워크스페이스를 오갈 수 있게 설정하세요.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var segmentedNav: some View {
        Picker("Section", selection: $section) {
            ForEach(Section.allCases) { sec in
                Label(sec.rawValue, systemImage: sec.icon).tag(sec)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var footerSummary: String {
        let bots = appModel.preferences.telegramBots.count
        let groups = appModel.preferences.telegramBotGroups.count
        let bindings = appModel.preferences.telegramBotChatBindings.count
        return "봇 \(bots)개 · 그룹 \(groups)개 · 매핑 \(bindings)개"
    }

    @ViewBuilder
    private var contentArea: some View {
        switch section {
        case .bots: TelegramBotListSection()
        case .groups: TelegramBotGroupSection()
        case .bindings: TelegramBotBindingSection()
        }
    }
}
