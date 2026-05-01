import SwiftUI
import YuminaiCore
import YuminaiUI

/// 루트 view v3 — Sidebar + Chat (Toolbar/Chat/StatusBar/Composer) + 옵션 Inspector.
struct RootView: View {
    @Environment(AppModel.self) private var appModel
    @State private var sidebarVisible: Bool = true

    var body: some View {
        @Bindable var bindable = appModel

        HStack(spacing: 0) {
            if sidebarVisible {
                SidebarView(
                    workspaces: appModel.workspaces,
                    selectedId: $bindable.selectedWorkspaceId,
                    onCreate: { appModel.showCreateWorkspaceSheet = true },
                    onDelete: { ws in Task { await appModel.deleteWorkspace(ws) } },
                    onCollapse: toggleSidebar,
                    onSearch: {
                        // ⌘P palette — v0.2
                    },
                    onOpenSettings: openAppSettings,
                    userName: "yuminai",
                    updateAvailable: false
                )
                .transition(.move(edge: .leading))
            }

            ChatPane(onToggleSidebar: toggleSidebar)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.bg)
        .onChange(of: appModel.selectedWorkspaceId) { _, newValue in
            Task { await appModel.selectWorkspace(newValue) }
        }
        .sheet(isPresented: $bindable.showCreateWorkspaceSheet) {
            CreateWorkspaceSheet(
                onCreate: { ws in Task { await appModel.createWorkspace(ws) } },
                onCancel: { appModel.showCreateWorkspaceSheet = false }
            )
        }
        .sheet(isPresented: $bindable.showUsageDashboard) {
            UsageDashboard(
                currentSessionUsage: appModel.currentSessionUsage,
                allTimeUsage: appModel.allTimeUsage,
                activeModel: appModel.activeSettings.model,
                onClose: { appModel.showUsageDashboard = false }
            )
        }
        .alert(
            "오류",
            isPresented: Binding(
                get: { appModel.error != nil },
                set: { if !$0 { appModel.error = nil } }
            ),
            presenting: appModel.error
        ) { _ in
            Button("확인") { appModel.error = nil }
        } message: { error in
            Text(error)
        }
    }

    private func toggleSidebar() {
        withAnimation(Theme.Animation.panelToggle) {
            sidebarVisible.toggle()
        }
    }

    private func openAppSettings() {
        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}

/// Toolbar / ChatView / StatusBar / Composer + 옵션 Inspector.
struct ChatPane: View {
    @Environment(AppModel.self) private var appModel
    let onToggleSidebar: () -> Void

    var body: some View {
        @Bindable var bindable = appModel

        if appModel.selectedWorkspaceId == nil {
            VStack(spacing: 0) {
                placeholderToolbar
                EmptyWorkspaceView()
            }
        } else {
            VStack(spacing: 0) {
                ChatToolbar(
                    workspaceName: currentWorkspaceName,
                    workspacePath: currentWorkspacePath,
                    isStreaming: appModel.isStreaming,
                    inspectorVisible: appModel.showInspector,
                    onToggleSidebar: onToggleSidebar,
                    onToggleInspector: {
                        withAnimation(Theme.Animation.panelToggle) {
                            appModel.showInspector.toggle()
                        }
                    },
                    onShowDashboard: { appModel.showUsageDashboard = true }
                )

                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        ChatView(messages: appModel.messages)
                            .frame(maxHeight: .infinity)

                        ChatStatusBar(
                            usage: appModel.currentSessionUsage,
                            contextWindow: appModel.currentContextWindow,
                            isStreaming: appModel.isStreaming
                        )

                        Composer(
                            text: $bindable.inputText,
                            model: $bindable.activeSettings.model,
                            permissionMode: $bindable.activeSettings.permissionMode,
                            effortLevel: $bindable.activeSettings.effortLevel,
                            isStreaming: appModel.isStreaming,
                            onSend: { Task { await appModel.sendMessage() } },
                            onStop: { appModel.cancelStream() },
                            onSettingsApply: { newSettings in
                                Task { await appModel.updateActiveSettings(newSettings) }
                            }
                        )
                    }
                    .frame(minWidth: 480)
                    .background(Theme.Color.bg)

                    if appModel.showInspector {
                        ContextInspector(
                            usage: appModel.currentSessionUsage,
                            activeSettings: appModel.activeSettings,
                            workspacePath: currentWorkspacePath,
                            recentTools: recentToolNames
                        )
                        .transition(.move(edge: .trailing))
                    }
                }
            }
        }
    }

    private var placeholderToolbar: some View {
        HStack(spacing: Theme.Spacing.md) {
            IconButton("sidebar.left", help: "사이드바", action: onToggleSidebar)
            Text("yuminai")
                .font(Theme.Typography.mono)
                .foregroundStyle(Theme.Color.textSecondary)
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Theme.Layout.toolbarHeight)
        .background(Theme.Color.bg)
        .overlay(alignment: .bottom) { FlatHDivider() }
    }

    private var currentWorkspaceName: String {
        appModel.workspaces.first { $0.id == appModel.selectedWorkspaceId }?.name ?? "yuminai"
    }

    private var currentWorkspacePath: String? {
        appModel.workspaces.first { $0.id == appModel.selectedWorkspaceId }?.directoryPath
    }

    private var recentToolNames: [String] {
        appModel.messages
            .filter { $0.role == .tool }
            .map(\.content)
            .map { String($0.prefix(80)) }
    }
}

struct EmptyWorkspaceView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Theme.Color.textTertiary)
            Text("워크스페이스를 선택하거나 새로 만드세요")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Color.textSecondary)
            FlatButton("+ 새 워크스페이스 만들기", variant: .primary, size: .large) {
                appModel.showCreateWorkspaceSheet = true
            }
            .keyboardShortcut("n", modifiers: .command)
            Text("⌘N")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.bg)
    }
}
