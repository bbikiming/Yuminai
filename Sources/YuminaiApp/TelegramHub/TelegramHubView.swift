import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-092 Phase 1** — Telegram Hub 메인 sheet.
///
/// 4개 탭으로 모든 텔레그램 관련 기능을 한곳에서 관리.
///
/// ## 탭 구성
/// - **Bots**: 봇 목록 + 그룹 관리 (`TelegramHubBotsTab`)
/// - **Bindings**: Chat ↔ Workspace 매핑 (`TelegramHubBindingsTab`)
/// - **Commands**: Phase 3 placeholder
/// - **Activity**: 사용량 + 에러 로그 (`TelegramHubActivityTab`)
///
/// ## 진입점 동작
/// - [+ Bot] 버튼: `preferences.telegramBots.isEmpty`이면 Wizard 자동 표시,
///   봇이 있으면 기존 `TelegramBotEditSheet` 표시.
///
/// **기존 `TelegramBotManagerSheet`는 유지됨** (deprecated 마커).
/// 진입점은 새 Hub로 점진적으로 마이그레이션.
struct TelegramHubView: View {
    @Environment(AppModel.self) private var appModel
    @State private var selectedTab: Tab = .bots
    @State private var showWizard: Bool = false
    @State private var showAddBotSheet: Bool = false
    /// **ADR-100** — Hub 안에서 띄우는 cokacdir import sheet (RootView의 sheet는 Hub modal에 가려져 안 뜸).
    @State private var showCokacdirImport: Bool = false
    @State private var cokacdirLoading: Bool = false

    enum Tab: String, CaseIterable, Identifiable {
        case bots = "봇"
        case bindings = "Bindings"
        case commands = "Commands"
        case activity = "Activity"
        case settings = "설정"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .bots:     return "person.crop.square.filled.and.at.rectangle"
            case .bindings: return "link.circle.fill"
            case .commands: return "terminal.fill"
            case .activity: return "chart.bar.fill"
            case .settings: return "bell.badge.fill"
            }
        }
    }

    var body: some View {
        YuminaiSheet(width: 880, height: 680) {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.top, Theme.Spacing.xl)
                    .padding(.bottom, Theme.Spacing.md)
                tabBar
                    .padding(.horizontal, Theme.Spacing.xl)
                Divider()
                tabContent
                    .padding(Theme.Spacing.xl)
            }
        } footer: {
            HStack {
                Text(footerSummary)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                Spacer()
                FlatButton("닫기", variant: .primary) {
                    appModel.showTelegramHubSheet = false
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .sheet(isPresented: $showWizard) {
            TelegramOnboardingWizard {
                showWizard = false
            }
            .environment(appModel)
        }
        .sheet(isPresented: $showAddBotSheet) {
            TelegramBotEditSheet(existing: nil) { config in
                Task {
                    await appModel.addTelegramBot(config)
                    showAddBotSheet = false
                }
            } onCancel: {
                showAddBotSheet = false
            }
        }
        // ADR-100 — Hub 자체 sheet로 cokacdir import (RootView sheet는 modal 위 modal로 안 뜸)
        .sheet(isPresented: $showCokacdirImport) {
            CokacdirImportSheet(
                bots: appModel.cokacdirBots,
                chatLabels: appModel.cokacdirChatLabels,
                error: appModel.cokacdirImportError,
                mode: .hub,
                onSelect: { bot, chatId in
                    Task {
                        await appModel.addBotFromCokacdirToHub(bot, chatId: chatId)
                        // 에러 없으면 닫기, 있으면 sheet 유지 (사용자가 에러 확인 후 수동 닫기)
                        if appModel.cokacdirImportError == nil {
                            showCokacdirImport = false
                        }
                    }
                },
                onCancel: { showCokacdirImport = false }
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            IconHero(
                icon: "paperplane.circle.fill",
                tint: Theme.Color.accent,
                size: 36
            )
            VStack(alignment: .leading, spacing: 2) {
                Text("Telegram Hub")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
                Text("봇 관리, Chat 바인딩, 커맨드, 활동 통계를 한곳에서.")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
            cokacdirImportButton
            addBotButton
        }
    }

    /// **ADR-100** — cokacdir bot_settings.json에서 봇을 multi-bot 모델로 직접 import.
    /// RootView 대신 Hub 자체 sheet로 띄움 (modal 위 modal SwiftUI 한계 우회).
    private var cokacdirImportButton: some View {
        FlatButton(
            cokacdirLoading ? "로딩 중…" : "cokacdir에서",
            icon: "square.and.arrow.down",
            variant: .secondary
        ) {
            Task {
                cokacdirLoading = true
                await appModel.loadCokacdirBots(mode: .hub, presentSheet: false)
                cokacdirLoading = false
                showCokacdirImport = true
            }
        }
        .disabled(cokacdirLoading)
        .help("~/.cokacdir/bot_settings.json에서 봇을 가져와 Hub에 추가합니다.")
    }

    private var addBotButton: some View {
        FlatButton("봇 추가", icon: "plus", variant: .primary) {
            if appModel.preferences.telegramBots.isEmpty {
                showWizard = true
            } else {
                showAddBotSheet = true
            }
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases) { tab in
                tabButton(tab)
            }
        }
    }

    private func tabButton(_ tab: Tab) -> some View {
        let isSelected = tab == selectedTab
        return Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11, weight: .medium))
                    .accessibilityHidden(true)
                Text(tab.rawValue)
                    .font(Theme.Typography.label.weight(isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? Theme.Color.accent : Theme.Color.textSecondary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                isSelected
                ? Theme.Color.accent.opacity(0.10)
                : Color.clear
            )
            .overlay(
                isSelected
                ? RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .stroke(Theme.Color.accent.opacity(0.20), lineWidth: 0.5)
                : nil
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .bots:
            TelegramHubBotsTab()
                .transition(tabTransition)
        case .bindings:
            TelegramHubBindingsTab()
                .transition(tabTransition)
        case .commands:
            TelegramHubCommandsTab()
                .transition(tabTransition)
        case .activity:
            TelegramHubActivityTab()
                .transition(tabTransition)
        case .settings:
            TelegramHubSettingsTab()
                .transition(tabTransition)
        }
    }

    private var tabTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.98))
    }

    // MARK: - Footer Summary

    private var footerSummary: String {
        let bots = appModel.preferences.telegramBots.count
        let groups = appModel.preferences.telegramBotGroups.count
        let bindings = appModel.preferences.telegramBotChatBindings.count
        let errors = appModel.telegramHealth.consecutiveFailures

        var parts = ["봇 \(bots)개", "그룹 \(groups)개", "매핑 \(bindings)개"]
        if errors > 0 {
            parts.append("에러 \(errors)회")
        }
        return parts.joined(separator: " · ")
    }
}
