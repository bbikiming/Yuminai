import SwiftUI
import YuminaiObsidian

/// 동명 노트 다수 시 사용자가 선택하도록 (B1).
public struct WikiDisambiguationSheet: View {
    public let originalName: String
    public let candidates: [VaultNode]
    public let onSelect: (String) -> Void
    public let onCancel: () -> Void

    public init(
        originalName: String,
        candidates: [VaultNode],
        onSelect: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.originalName = originalName
        self.candidates = candidates
        self.onSelect = onSelect
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: 4) {
                Text("같은 이름의 노트가 여러 개 있어요")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
                Text("‘\(originalName)’ — 어떤 노트로 이동할까요?")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
            }

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(candidates, id: \.path) { node in
                        DisambigRow(node: node, onSelect: { onSelect(node.path) })
                    }
                }
            }
            .frame(maxHeight: 280)

            HStack {
                Spacer()
                FlatButton("취소", variant: .secondary, action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding(Theme.Spacing.xl)
        // ADR-073 — 너비만 반응형 (높이는 컨텐츠 기반).
        .yuminaiSheetFrame(width: 480)
        .background(Theme.Color.bg)
    }
}

struct DisambigRow: View {
    let node: VaultNode
    let onSelect: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Color.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.name)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Color.text)
                    Text(node.path)
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm + 2)
            .background(hovering ? Theme.Color.surfaceHi : Theme.Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(Theme.Color.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
