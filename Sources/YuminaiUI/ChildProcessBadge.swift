import SwiftUI
import YuminaiCore

/// **ADR-054** — 진행 중인 ChildClaudeProcess (decomposition/rehearsal/parallel) 표시 badge.
///
/// 사용자가 격리된 호출이 진행 중임을 시각적으로 인지 — Linear/Cursor의
/// "background task" badge 패턴 차용. chatArea 상단 또는 InspectorPanel 상단에 표시.
public struct ChildProcessBadge: View {
    public let processes: [ChildProcessProgress]

    public init(processes: [ChildProcessProgress]) {
        self.processes = processes
    }

    public var body: some View {
        if processes.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 6) {
                ForEach(processes) { progress in
                    badge(progress)
                }
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 4)
            .background(Theme.Color.surface)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func badge(_ progress: ChildProcessProgress) -> some View {
        HStack(spacing: 4) {
            statusIcon(progress.status)
            Text(progress.purpose.displayLabel)
                .font(Theme.Typography.micro.weight(.medium))
                .foregroundStyle(color(for: progress))
            Text(progress.purposeContext)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textSecondary)
                .lineLimit(1)
            elapsedText(progress)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color(for: progress).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private func statusIcon(_ status: ChildProcessProgress.Status) -> some View {
        switch status {
        case .starting, .running:
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.6)
                .frame(width: 10, height: 10)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.red)
        }
    }

    private func elapsedText(_ progress: ChildProcessProgress) -> some View {
        let s = progress.elapsedSeconds()
        return Text("\(s)s")
            .font(Theme.Typography.micro)
            .foregroundStyle(Theme.Color.textTertiary)
    }

    private func color(for progress: ChildProcessProgress) -> Color {
        switch progress.status {
        case .starting, .running:
            switch progress.purpose {
            case .decomposition: return .blue
            case .rehearsal: return .orange
            case .parallel: return .purple
            case .routing: return .gray
            }
        case .completed: return .green
        case .failed: return .red
        }
    }
}
