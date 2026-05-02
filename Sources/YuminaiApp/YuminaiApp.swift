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

            let claudeAdapter = LiveClaudeAdapter(
                claudePath: URL(fileURLWithPath: prefs.claudeBinaryPath)
            )

            // codex CLI가 실행 가능하면 어댑터 활성화 (없으면 nil — UI에서 disabled)
            let codexAdapter: (any ClaudeAdapter)?
            if FileManager.default.isExecutableFile(atPath: prefs.codexBinaryPath) {
                codexAdapter = LiveCodexAdapter(
                    codexPath: URL(fileURLWithPath: prefs.codexBinaryPath)
                )
            } else {
                codexAdapter = nil
            }

            // ADR-053 — ChildClaudeProcess (decomposition / rehearsal / parallel 격리 호출)
            let childProcess: (any ChildClaudeProcess)? = LiveChildClaudeProcess(
                claudePath: URL(fileURLWithPath: prefs.claudeBinaryPath),
                codexPath: URL(fileURLWithPath: prefs.codexBinaryPath),
                defaultSettings: prefs.defaultSessionSettings
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
                .frame(minWidth: 1000, minHeight: 700)
                .task {
                    await appModel.bootstrap()
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("새 워크스페이스") {
                    appModel.showCreateWorkspaceSheet = true
                }
                .keyboardShortcut("n", modifiers: .command)
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
                onSelect: { bot, chatId in
                    Task { await appModel.applyCokacdirBot(bot, chatId: chatId) }
                },
                onCancel: {
                    appModel.showCokacdirImportSheet = false
                }
            )
        }
    }
}
