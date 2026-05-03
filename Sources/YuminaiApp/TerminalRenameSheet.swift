import SwiftUI
import YuminaiCore
import YuminaiUI

/// 터미널 세션 라벨 변경 sheet (ADR-040 T4).
struct TerminalRenameSheet: View {
    let session: TerminalSession
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var label: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .foregroundStyle(Theme.Color.accent)
                Text("터미널 라벨 변경")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
                Spacer()
            }
            .padding(Theme.Spacing.lg)
            Divider()
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("현재: \(session.label)")
                    .font(Theme.Typography.monoSmall)
                    .foregroundStyle(Theme.Color.textSecondary)
                TextField("새 라벨", text: $label)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.Typography.body)
                    .focused($inputFocused)
                    .onSubmit { submit() }
                InlineHint(
                    "터미널 탭 바에 표시되는 라벨이에요. 워크스페이스 별로만 유지되고 영속되지 않아요.",
                    icon: "info.circle",
                    kind: .info
                )
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            HStack {
                Spacer()
                Button("취소", action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])
                Button("변경", action: submit)
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
            .padding(Theme.Spacing.md)
        }
        // ADR-073 — 짧은 sheet (220px).
        .yuminaiSheetFrame(width: 420, height: 220, wrapInScrollView: false)
        .background(Theme.Color.bg)
        .onAppear {
            label = session.label
            inputFocused = true
        }
    }

    private var isValid: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard isValid else { return }
        onSubmit(label.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
