import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-079 Phase 4** — Branch picker를 sheet로 wrap (async 브랜치 로딩 지원).
struct GitBranchPickerSheetWrapper: View {
    @Environment(AppModel.self) private var appModel
    @State private var branches: [BranchInfo] = []
    @State private var loading: Bool = true

    var body: some View {
        Group {
            if loading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("브랜치 목록 로딩 중…")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .frame(width: 320, height: 200)
                .background(Theme.Color.bg)
            } else {
                GitBranchPickerPopover(
                    branches: branches,
                    currentBranch: appModel.gitBranch ?? "unknown",
                    onSwitch: { name in
                        Task { await appModel.switchGitBranch(name) }
                    },
                    onCreateBranch: { name in
                        Task { await appModel.createGitBranch(name) }
                    },
                    onClose: { appModel.showGitBranchPicker = false }
                )
            }
        }
        .task {
            branches = await appModel.gitBranches()
            loading = false
        }
    }
}
