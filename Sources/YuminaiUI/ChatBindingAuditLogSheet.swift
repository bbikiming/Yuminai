import SwiftUI
import YuminaiCore

/// **ADR-062 Phase 3** — Chat binding audit log viewer.
public struct ChatBindingAuditLogSheet: View {
    public let entries: [ChatBindingAuditEntry]
    public let onClose: () -> Void

    public init(entries: [ChatBindingAuditEntry], onClose: @escaping () -> Void) {
        self.entries = entries
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        // ADR-073 — 반응형. 내부 ScrollView 있어 wrap=false.
        .yuminaiSheetFrame(width: 720, height: 540, wrapInScrollView: false)
        .background(Theme.Color.bg)
    }

    private var header: some View {
        HStack {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(Theme.Color.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Chat Binding Audit Log")
                    .font(Theme.Typography.title)
                Text("ADR-061 Phase 4 — bind/unbind/rebind history (\(entries.count)개)")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
        }
        .padding(Theme.Spacing.lg)
    }

    @ViewBuilder
    private var content: some View {
        if entries.isEmpty {
            EmptyStateHint(
                icon: "tray",
                title: "Audit log 비어있음",
                message: "Telegram에서 /bind 또는 /unbind 명령 사용 시 여기에 기록됩니다."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(entries) { entry in
                        AuditEntryRow(entry: entry)
                    }
                }
                .padding(Theme.Spacing.sm)
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            FlatButton("닫기", variant: .primary) { onClose() }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(Theme.Spacing.md)
    }
}

private struct AuditEntryRow: View {
    let entry: ChatBindingAuditEntry

    var body: some View {
        HStack(spacing: 8) {
            actionIcon
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(actionLabel)
                        .font(Theme.Typography.small.weight(.semibold))
                        .foregroundStyle(actionColor)
                    Text("Chat \(entry.chatId)")
                        .font(Theme.Typography.monoSmall)
                        .foregroundStyle(Theme.Color.text)
                    if let name = entry.workspaceName {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Color.textTertiary)
                        Text(name)
                            .font(Theme.Typography.small.weight(.medium))
                            .foregroundStyle(Theme.Color.text)
                    }
                }
                HStack(spacing: 6) {
                    Text("user \(entry.userId)")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                    Text("·")
                        .foregroundStyle(Theme.Color.textTertiary)
                    Text(formatTime(entry.timestamp))
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 6)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private var actionLabel: String {
        switch entry.action {
        case .bind: return "BIND"
        case .unbind: return "UNBIND"
        case .rebind: return "REBIND"
        }
    }

    private var actionColor: Color {
        switch entry.action {
        case .bind: return .green
        case .unbind: return .red
        case .rebind: return .orange
        }
    }

    @ViewBuilder
    private var actionIcon: some View {
        let name: String = {
            switch entry.action {
            case .bind: return "link.circle.fill"
            case .unbind: return "link.badge.plus"  // 실제는 unlink가 없음
            case .rebind: return "arrow.triangle.2.circlepath.circle.fill"
            }
        }()
        Image(systemName: name)
            .font(.system(size: 14))
            .foregroundStyle(actionColor)
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: date)
    }
}
