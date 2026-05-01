import SwiftUI
import YuminaiCore
import YuminaiUI

/// pane custom 이름 변경 모달 (ADR-032 U3).
struct PaneRenameSheet: View {
    let pane: AgentPane
    @State var draft: String
    let onApply: (String?) -> Void
    let onCancel: () -> Void

    init(pane: AgentPane, onApply: @escaping (String?) -> Void, onCancel: @escaping () -> Void) {
        self.pane = pane
        self._draft = State(initialValue: pane.customName ?? "")
        self.onApply = onApply
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pane 이름 바꾸기")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
                Text("\(pane.agentKind.displayName) pane")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                TextField("예: Claude (설계), Codex (구현)", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { apply() }
                InlineHint(
                    "비워두면 기본 이름(\(pane.agentKind.displayName))을 사용해요. mention(`@`)에서도 이 이름이 자동완성 후보로 나옵니다.",
                    icon: "lightbulb",
                    kind: .tip
                )
            }

            HStack {
                Spacer()
                FlatButton("취소", variant: .secondary, action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])
                FlatButton("저장", variant: .primary, action: apply)
                    .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 420)
        .background(Theme.Color.bg)
    }

    private func apply() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        onApply(trimmed.isEmpty ? nil : trimmed)
    }
}
