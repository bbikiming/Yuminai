import SwiftUI
import YuminaiCore
import YuminaiUI

/// 앱 메인 윈도우의 루트 view. NavigationSplitView를 안 쓰고 직접 HStack layout.
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
                    onDelete: { ws in Task { await appModel.deleteWorkspace(ws) } }
                )
                .transition(.move(edge: .leading))
            }

            ChatContainer(onToggleSidebar: {
                withAnimation(.easeInOut(duration: 0.16)) {
                    sidebarVisible.toggle()
                }
            })
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
}

struct ChatContainer: View {
    @Environment(AppModel.self) private var appModel
    let onToggleSidebar: () -> Void

    var body: some View {
        @Bindable var bindable = appModel

        if appModel.selectedWorkspaceId == nil {
            VStack(spacing: 0) {
                topToolbarStub
                EmptyChatPlaceholder()
            }
        } else {
            VStack(spacing: 0) {
                ChatToolbar(
                    workspaceName: currentWorkspaceName,
                    model: $bindable.activeSettings.model,
                    permissionMode: $bindable.activeSettings.permissionMode,
                    effortLevel: $bindable.activeSettings.effortLevel,
                    isStreaming: appModel.isStreaming,
                    inspectorVisible: appModel.showInspector,
                    onSettingsApply: { newSettings in
                        Task { await appModel.updateActiveSettings(newSettings) }
                    },
                    onToggleInspector: {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            appModel.showInspector.toggle()
                        }
                    },
                    onShowDashboard: { appModel.showUsageDashboard = true },
                    onToggleSidebar: onToggleSidebar
                )

                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        ChatView(
                            messages: appModel.messages,
                            inputText: $bindable.inputText,
                            isStreaming: appModel.isStreaming,
                            emptyStateText: "메시지를 입력해 시작하세요. ⌘+Return으로 전송.",
                            onSend: { Task { await appModel.sendMessage() } },
                            onCancel: { appModel.cancelStream() }
                        )
                        ChatStatusBar(
                            usage: appModel.currentSessionUsage,
                            contextWindow: appModel.currentContextWindow,
                            isStreaming: appModel.isStreaming
                        )
                    }
                    .frame(minWidth: 480)

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

    private var topToolbarStub: some View {
        HStack {
            FlatButton("", icon: "sidebar.left", variant: .ghost, size: .small, action: onToggleSidebar)
                .help("사이드바")
            Text("yuminai")
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Color.textTertiary)
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Theme.Layout.toolbarHeight)
        .flatChrome(borders: [.bottom])
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

struct EmptyChatPlaceholder: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()
            Text("─ no active workspace ─")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Color.textTertiary)
            FlatButton("+ 새 워크스페이스", variant: .accent) {
                appModel.showCreateWorkspaceSheet = true
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.bg)
    }
}
