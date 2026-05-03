import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-076 Phase 4** — 폴더 생성/이름 변경 sheet.
///
/// 두 가지 모드:
/// - **생성 모드** (existingFolder == nil): 빈 입력으로 새 폴더 생성
/// - **이름 변경 모드** (existingFolder != nil): 기존 이름 prefilled
struct FolderRenameSheet: View {
    let existingFolder: WorkspaceFolder?
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        // ADR-074 — YuminaiSheet container (footer 항상 고정)
        YuminaiSheet(width: 460, height: 220) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                input
            }
            .padding(Theme.Spacing.xl)
        } footer: {
            HStack {
                Spacer()
                FlatButton("취소", variant: .secondary, action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])
                FlatButton(existingFolder == nil ? "만들기" : "저장", variant: .primary) {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    onConfirm(trimmed)
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            name = existingFolder?.name ?? ""
            inputFocused = true
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(Theme.Color.accent)
                    .accessibilityHidden(true)
                Text(existingFolder == nil ? "새 폴더 만들기" : "폴더 이름 바꾸기")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
            }
            Text(existingFolder == nil
                 ? "워크스페이스를 그룹화할 폴더 이름을 입력하세요."
                 : "폴더의 새 이름을 입력하세요.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }

    private var input: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("이름")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
                .textCase(.uppercase)
                .tracking(0.6)
            FlatTextField("예: 클라이언트 프로젝트", text: $name)
                .focused($inputFocused)
                .accessibilityLabel("폴더 이름")
        }
    }
}
