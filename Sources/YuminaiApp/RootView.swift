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
            ChatDetailView()
        }
        .onChange(of: appModel.selectedWorkspaceId) { _, newValue in
            Task { await appModel.selectWorkspace(newValue) }
        }
        .sheet(isPresented: $bindable.showCreateWorkspaceSheet) {
            CreateWorkspaceSheet(
                onCreate: { ws in
                    Task { await appModel.createWorkspace(ws) }
                },
                onCancel: {
                    appModel.showCreateWorkspaceSheet = false
                }
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

struct ChatDetailView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var bindable = appModel

        if appModel.selectedWorkspaceId == nil {
            VStack(spacing: Theme.Spacing.lg) {
                Spacer()
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
        } else {
            ChatView(
                messages: appModel.messages,
                inputText: $bindable.inputText,
                isStreaming: appModel.isStreaming,
                emptyStateText: "Claude에 메시지를 보내 시작하세요. ⌘+Return으로 전송.",
                onSend: { Task { await appModel.sendMessage() } },
                onCancel: { appModel.cancelStream() }
            )
            .navigationTitle(currentWorkspaceName)
        }
    }

    private var currentWorkspaceName: String {
        appModel.workspaces.first { $0.id == appModel.selectedWorkspaceId }?.name ?? "Yuminai"
    }
}
