import SwiftUI
import AppKit
import os
import YuminaiCore
import YuminaiClaudeAdapter
import YuminaiPersistence
import YuminaiUI

/// Yuminai SPM executable 엔트리. `swift run YuminaiApp`으로 실행.
///
/// 정식 .app 번들/Xcode 프로젝트는 후속 단계 (`App/README.md`).
@main
@MainActor
struct YuminaiAppMain: App {
    @NSApplicationDelegateAdaptor(YuminaiAppDelegate.self) private var appDelegate
    @State private var appModel: AppModel

    init() {
        // SPM executable은 .app 번들이 아니므로 macOS가 기본적으로 background-only로 취급한다.
        // 윈도우/Dock 아이콘이 보이려면 명시적으로 .regular activation policy 지정 필요.
        NSApplication.shared.setActivationPolicy(.regular)

        let logger = Logger(subsystem: "com.yuminai", category: "Bootstrap")

        do {
            let container = try YuminaiModelContainerFactory.live()
            let workspaceStore = SwiftDataWorkspaceStore(container: container)
            let sessionStore = SwiftDataSessionStore(container: container)
            let keychainStore = LiveKeychainStore()
            let preferencesStore = UserDefaultsAppPreferencesStore()

            // 동기 init이라 await 못 씀 — UserDefaults 직접 접근으로 prefs 초기 로드
            let prefs: AppPreferences
            if let data = UserDefaults.standard.data(forKey: UserDefaultsAppPreferencesStore.defaultKey),
               let decoded = try? JSONDecoder().decode(AppPreferences.self, from: data) {
                prefs = decoded
            } else {
                prefs = AppPreferences()
            }

            // ADR-108 — userProfileProvider: AppModel init 전에 closure로 묶어두고,
            // model 생성 후 weak 참조 주입. bootstrap 동기 제약 내 안전한 패턴.
            // nonisolated(unsafe) — init() 동기 컨텍스트 내 단순 대입, race 없음.
            nonisolated(unsafe) var weakModel: AppModel? = nil
            let profileProvider: @Sendable () -> String? = {
                weakModel?.preferences.userProfile.renderForSystemPrompt()
            }

            let claudeAdapter = LiveClaudeAdapter(
                claudePath: URL(fileURLWithPath: prefs.claudeBinaryPath),
                userProfileProvider: profileProvider
            )

            // codex CLI가 실행 가능하면 어댑터 활성화 (없으면 nil — UI에서 disabled)
            let codexAdapter: (any ClaudeAdapter)?
            if FileManager.default.isExecutableFile(atPath: prefs.codexBinaryPath) {
                codexAdapter = LiveCodexAdapter(
                    codexPath: URL(fileURLWithPath: prefs.codexBinaryPath),
                    userProfileProvider: profileProvider
                )
            } else {
                codexAdapter = nil
            }

            // ADR-053 — ChildClaudeProcess (decomposition / rehearsal / parallel 격리 호출)
            let childProcess: (any ChildClaudeProcess)? = LiveChildClaudeProcess(
                claudePath: URL(fileURLWithPath: prefs.claudeBinaryPath),
                codexPath: URL(fileURLWithPath: prefs.codexBinaryPath),
                defaultSettings: prefs.defaultSessionSettings,
                userProfileProvider: profileProvider
            )

            let model = AppModel(
                workspaceStore: workspaceStore,
                sessionStore: sessionStore,
                keychainStore: keychainStore,
                preferencesStore: preferencesStore,
                claudeAdapter: claudeAdapter,
                codexAdapter: codexAdapter,
                childProcess: childProcess,
                preferences: prefs
            )
            // ADR-108 — model 생성 후 weakModel에 주입 → profileProvider가 올바른 model 참조
            weakModel = model
            self._appModel = State(wrappedValue: model)

            logger.info("Yuminai bootstrap 성공")
        } catch {
            logger.critical("Yuminai bootstrap 실패: \(error.localizedDescription)")
            fatalError("Yuminai 초기화 실패: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup("Yuminai") {
            RootView()
                .environment(appModel)
                // ADR-074 — RootView 자체가 minWindowWidth/Height(460/360) 적용 중.
                // 여기선 ideal size만 지정 (defaultSize는 SwiftUI가 첫 실행 시 사용).
                .task {
                    await appModel.bootstrap()
                }
                // ADR-096 — yuminai:// URL scheme 핸들러
                .onOpenURL { url in
                    guard let link = TelegramDeepLink.parse(url) else { return }
                    Task { await appModel.handleDeepLink(link) }
                }
        }
        // ADR-074 — `contentMinSize`는 사용자 zoom 동작을 일부 제한할 수 있음.
        // `.contentSize`로 변경하여 zoom + manual resize 모두 자유롭게.
        .windowResizability(.contentSize)
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("새 워크스페이스") {
                    appModel.showCreateWorkspaceSheet = true
                }
                .keyboardShortcut("n", modifiers: .command)
                // ADR-089 — 새 ad-hoc 대화 세션
                Button("새 대화 세션") {
                    appModel.showNewChatSessionSheet = true
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            // ADR-078 Phase 5 — File menu에 import/export 추가
            CommandGroup(after: .newItem) {
                Divider()
                Button("워크스페이스 백업 내보내기…") {
                    Task { await appModel.exportArchiveToFile() }
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("워크스페이스 백업 가져오기…") {
                    Task { await appModel.importArchiveFromFile(strategy: .skipExisting) }
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }
            // ADR-084 — 텔레그램 고도화 메뉴
            CommandMenu("텔레그램") {
                Button("고급 설정…") {
                    appModel.showTelegramAdvancedSheet = true
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                // ADR-086 Phase 4 — Multi-bot 관리
                Button("Multi-Bot 관리…") {
                    appModel.showTelegramBotManagerSheet = true
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                // ADR-086 Phase 1 — 에러 로그
                Button("에러 로그…") {
                    appModel.showTelegramErrorLogSheet = true
                }
                Divider()
                Button("응답 모드: 최소") {
                    Task {
                        appModel.preferences.telegramResponseMode = .minimal
                        await appModel.savePreferences()
                    }
                }
                Button("응답 모드: 간결") {
                    Task {
                        appModel.preferences.telegramResponseMode = .concise
                        await appModel.savePreferences()
                    }
                }
                Button("응답 모드: 기본") {
                    Task {
                        appModel.preferences.telegramResponseMode = .standard
                        await appModel.savePreferences()
                    }
                }
                Button("응답 모드: 상세") {
                    Task {
                        appModel.preferences.telegramResponseMode = .detailed
                        await appModel.savePreferences()
                    }
                }
            }
            // macOS 표준 Help 메뉴 — 사용자 가이드 (웹) + 단축키 도움말
            CommandGroup(replacing: .help) {
                Button("Yuminai 사용자 가이드 (웹)") {
                    NSWorkspace.shared.open(AppLinks.userGuide)
                }
                .keyboardShortcut("?", modifiers: [.command, .shift])
                Button("단축키 도움말…") {
                    appModel.presentExclusiveSheet { $0.showShortcutHelp = true }
                }
                Divider()
                // ADR-104 — 초기 설정 가이드 재진입
                Button("초기 설정 가이드…") {
                    appModel.openSetupWizard()
                }
            }
        }

        Settings {
            SettingsContainer()
                .environment(appModel)
        }
    }
}

/// SPM executable이 첫 윈도우를 활성화하고 ⌘Q 종료를 자연스럽게 처리하기 위한 NSApplicationDelegate.
final class YuminaiAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

/// Settings scene이 Bindable Environment를 직접 받기 위한 컨테이너.
struct SettingsContainer: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var bindable = appModel

        SettingsView(
            preferences: $bindable.preferences,
            anthropicKeyStatus: appModel.anthropicKeyStatus,
            telegramTokenStatus: appModel.telegramTokenStatus,
            onUpdateAnthropicKey: { value in
                Task { await appModel.saveAnthropicKey(value) }
            },
            onClearAnthropicKey: {
                Task { await appModel.clearAnthropicKey() }
            },
            onUpdateTelegramToken: { value in
                Task { await appModel.saveTelegramToken(value) }
            },
            onClearTelegramToken: {
                Task { await appModel.clearTelegramToken() }
            },
            onTestTelegramSend: {
                Task { await appModel.sendTelegramTest() }
            },
            onSelectClaudeBinary: {
                appModel.selectClaudeBinary()
            },
            onSelectCodexBinary: {
                appModel.selectCodexBinary()
            },
            onImportFromCokacdir: {
                Task { await appModel.loadCokacdirBots() }
            },
            // ADR-056 Phase 5 — Routing learning panel
            routingLearningSnapshot: appModel.routingLearningSnapshot,
            onUnmuteKeyword: { kw in
                Task { await appModel.unmuteKeyword(kw) }
            },
            onAddCustomKeyword: { kw, kind in
                Task { await appModel.addCustomRoutingKeyword(kw, taskKind: kind) }
            },
            onRemoveCustomKeyword: { kw, kind in
                Task { await appModel.removeCustomRoutingKeyword(kw, taskKind: kind) }
            }
        )
        .onChange(of: appModel.preferences) { _, _ in
            Task { await appModel.savePreferences() }
        }
        .sheet(isPresented: $bindable.showCokacdirImportSheet) {
            CokacdirImportSheet(
                bots: appModel.cokacdirBots,
                chatLabels: appModel.cokacdirChatLabels,
                error: appModel.cokacdirImportError,
                mode: appModel.cokacdirImportMode,
                existingBots: appModel.preferences.telegramBots,
                onSelect: { bot, chatId in
                    Task {
                        switch appModel.cokacdirImportMode {
                        case .legacy:
                            await appModel.applyCokacdirBot(bot, chatId: chatId)
                        case .hub:
                            await appModel.addBotFromCokacdirToHub(bot, chatId: chatId)
                        }
                    }
                },
                onCancel: {
                    appModel.showCokacdirImportSheet = false
                }
            )
        }
    }
}
