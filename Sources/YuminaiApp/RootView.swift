import SwiftUI
import YuminaiCore
import YuminaiUI

/// 앱 메인 윈도우의 루트 view. NavigationSplitView로 sidebar + chat detail.
struct RootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var bindable = appModel

        NavigationSplitView {
            SidebarView(
                workspaces: appModel.workspaces,
                selectedId: $bindable.selectedWorkspaceId,
                onCreate: { appModel.showCreateWorkspaceSheet = true },
                onDelete: { ws in
                    Task { await appModel.deleteWorkspace(ws) }
                }
            )
        } detail: {
            ChatContainer()
        }
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

    var body: some View {
        @Bindable var bindable = appModel

        if appModel.selectedWorkspaceId == nil {
            EmptyChatPlaceholder()
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
                        withAnimation(.easeInOut(duration: 0.18)) {
                            appModel.showInspector.toggle()
                        }
                    },
                    onShowDashboard: { appModel.showUsageDashboard = true }
                )

                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        ChatView(
                            messages: appModel.messages,
                            inputText: $bindable.inputText,
                            isStreaming: appModel.isStreaming,
                            emptyStateText: "Claude에 메시지를 보내 시작하세요. ⌘+Return으로 전송.",
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
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
            .navigationTitle(currentWorkspaceName)
        }
    }

    private var currentWorkspaceName: String {
        appModel.workspaces.first { $0.id == appModel.selectedWorkspaceId }?.name ?? "Yuminai"
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
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundStyle(Theme.Color.labelSecondary)
            Text("워크스페이스를 선택하거나 새로 만드세요")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button("새 워크스페이스 만들기") {
                appModel.showCreateWorkspaceSheet = true
            }
            .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
