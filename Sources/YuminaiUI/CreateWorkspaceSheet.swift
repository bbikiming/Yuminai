import SwiftUI
import AppKit
import YuminaiCore

/// 새 워크스페이스 생성 시트 — flat 자체 컴포넌트.
public struct CreateWorkspaceSheet: View {
    @State private var name: String = ""
    @State private var directoryPath: String = ""

    public let onCreate: (Workspace) -> Void
    public let onCancel: () -> Void

    public init(
        onCreate: @escaping (Workspace) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onCreate = onCreate
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            VStack(alignment: .leading, spacing: 6) {
                Text("새 워크스페이스 만들기")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
                Text("어떤 폴더에서 시작할까요? Claude CLI가 그 위치에서 실행돼요.")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                fieldLabel("이름")
                FlatTextField("예: 내 새 프로젝트", text: $name)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                fieldLabel("폴더")
                HStack(spacing: Theme.Spacing.sm) {
                    FlatTextField("예: ~/Documents/projects/내-프로젝트", text: $directoryPath)
                    FlatButton("폴더 고르기", variant: .secondary, size: .small) {
                        selectDirectory()
                    }
                }
            }

            Spacer(minLength: Theme.Spacing.lg)

            HStack {
                Spacer()
                FlatButton("취소", variant: .secondary) { onCancel() }
                    .keyboardShortcut(.escape, modifiers: [])
                FlatButton("만들기", variant: .primary) { create() }
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(!isValid)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: Theme.Layout.sheetWidth)
        .background(Theme.Color.bg)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.micro)
            .foregroundStyle(Theme.Color.textTertiary)
            .textCase(.uppercase)
            .tracking(0.6)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !directoryPath.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func create() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedPath = directoryPath.trimmingCharacters(in: .whitespaces)
        let expanded = NSString(string: trimmedPath).expandingTildeInPath
        onCreate(Workspace(name: trimmedName, directoryPath: expanded))
    }

    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "어떤 폴더에서 시작할까요?"
        panel.prompt = "이 폴더로"
        if panel.runModal() == .OK, let url = panel.url {
            directoryPath = url.path
        }
    }
}
