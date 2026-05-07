import SwiftUI

/// 새 노트 생성 sheet (B5).
public struct CreateNoteSheet: View {
    @State private var filename: String = ""
    @State private var title: String = ""
    @State private var folder: String = ""

    public let onCreate: (String, String?, String) -> Void
    public let onCancel: () -> Void

    public init(
        onCreate: @escaping (String, String?, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onCreate = onCreate
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            VStack(alignment: .leading, spacing: 4) {
                Text("새 노트 만들기")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
                Text("Vault에 새 마크다운 파일을 만들어요. 만든 후 바로 편집할 수 있어요.")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                fieldLabel("파일명")
                FlatTextField("예: 2026-05-01-회의록", text: $filename)
                Text(".md는 자동으로 붙어요")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                fieldLabel("제목 (옵션)")
                FlatTextField("frontmatter title — 비워두면 파일명 사용", text: $title)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                fieldLabel("폴더 (옵션)")
                FlatTextField("예: meetings/2026", text: $folder)
                Text("Vault 루트 기준 경로. 비워두면 root.")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
            }

            Spacer(minLength: Theme.Spacing.lg)

            HStack {
                Spacer()
                FlatButton("취소", variant: .secondary, action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])
                FlatButton("만들기", variant: .primary) {
                    let trimmedFilename = filename.trimmingCharacters(in: .whitespaces)
                    guard !trimmedFilename.isEmpty else { return }
                    let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
                    onCreate(
                        trimmedFilename,
                        trimmedTitle.isEmpty ? nil : trimmedTitle,
                        folder.trimmingCharacters(in: .whitespaces)
                    )
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(filename.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Theme.Spacing.xxl)
        // ADR-073 — 너비만 반응형 (높이는 컨텐츠 기반).
        .yuminaiSheetFrame(width: 520)
        .background(Theme.Color.bg)
        .overlay(alignment: .topTrailing) {
            SheetCloseButton(action: onCancel)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.micro)
            .foregroundStyle(Theme.Color.textTertiary)
            .textCase(.uppercase)
            .tracking(0.6)
    }
}
