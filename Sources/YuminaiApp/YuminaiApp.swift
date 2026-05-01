import SwiftUI
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
    @State private var appModel: AppModel

    init() {
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

            let model = AppModel(
                workspaceStore: workspaceStore,
                sessionStore: sessionStore,
                keychainStore: keychainStore,
                preferencesStore: preferencesStore,
                claudeAdapter: claudeAdapter,
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
            }
        )
        .onChange(of: appModel.preferences) { _, _ in
            Task { await appModel.savePreferences() }
        }
    }
}
