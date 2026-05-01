import SwiftUI
import AppKit
import YuminaiCore

/// 새 워크스페이스 생성 시트. 디렉토리는 NSOpenPanel로 선택.
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
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("새 워크스페이스")
                .font(.title2)
                .bold()

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("이름")
                    .font(Theme.Typography.label)
                TextField("예: nunchi-v2", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("작업 디렉토리")
                    .font(Theme.Typography.label)
                HStack {
                    TextField("예: ~/Documents/projects/nunchi-v2", text: $directoryPath)
                        .textFieldStyle(.roundedBorder)
                    Button("선택…") {
                        selectDirectory()
                    }
                }
                Text("Claude CLI가 이 디렉토리에서 실행됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: Theme.Spacing.md)

            HStack {
                Spacer()
                Button("취소") { onCancel() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("생성") { create() }
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(!isValid)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 520)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !directoryPath.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func create() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedPath = directoryPath.trimmingCharacters(in: .whitespaces)
        let expanded = NSString(string: trimmedPath).expandingTildeInPath
        let workspace = Workspace(name: trimmedName, directoryPath: expanded)
        onCreate(workspace)
    }

    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "워크스페이스 디렉토리를 선택하세요"
        panel.prompt = "선택"
        if panel.runModal() == .OK, let url = panel.url {
            directoryPath = url.path
        }
    }
}
