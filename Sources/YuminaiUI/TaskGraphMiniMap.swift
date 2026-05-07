import SwiftUI
import YuminaiCore

/// TaskGraph 시각화 (ADR-049 Phase 5, ADR-050 Kanban toggle).
///
/// 두 view mode:
/// - **list**: 의존성 들여쓰기 + status icon (default — compact)
/// - **kanban**: pending/running/completed 3 컬럼 (Linear Method 패턴)
public struct TaskGraphMiniMap: View {
    public let tasks: [HarnessTask]
    public let onUpdateStatus: (UUID, TaskStatus) -> Void
    public let onRemove: (UUID) -> Void
    public let onAddTask: () -> Void
    public let onRunReadyTask: (UUID) -> Void
    public let onShowWalkthrough: (UUID) -> Void
    /// ADR-052 — task에 대해 다른 모델로 rehearsal 시도
    public let onShowRehearsal: (UUID) -> Void

    @AppStorage("yuminai.harness.taskGraphMode") private var modeRaw: String = TaskGraphViewMode.list.rawValue

    private var mode: TaskGraphViewMode {
        TaskGraphViewMode(rawValue: modeRaw) ?? .list
    }

    public init(
        tasks: [HarnessTask],
        onUpdateStatus: @escaping (UUID, TaskStatus) -> Void = { _, _ in },
        onRemove: @escaping (UUID) -> Void = { _ in },
        onAddTask: @escaping () -> Void = {},
        onRunReadyTask: @escaping (UUID) -> Void = { _ in },
        onShowWalkthrough: @escaping (UUID) -> Void = { _ in },
        onShowRehearsal: @escaping (UUID) -> Void = { _ in }
    ) {
        self.tasks = tasks
        self.onUpdateStatus = onUpdateStatus
        self.onRemove = onRemove
        self.onAddTask = onAddTask
        self.onRunReadyTask = onRunReadyTask
        self.onShowWalkthrough = onShowWalkthrough
        self.onShowRehearsal = onShowRehearsal
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            FlatHDivider()
            content
        }
        .background(Theme.Color.bg)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Color.accent)
            Text("작업")
                .font(Theme.Typography.small.weight(.medium))
                .foregroundStyle(Theme.Color.text)
            Text("(\(tasks.count))")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
            HelpHint(
                "Harness가 추적하는 task graph. List는 의존성 들여쓰기, Kanban은 status별 컬럼 (Linear Method).\n/decompose로 큰 task를 LLM이 자동 분해할 수 있어요.",
                title: "Task Graph",
                placement: .bottom
            )
            Spacer()
            // ADR-050 — view mode toggle (list / kanban)
            Picker("View Mode", selection: Binding(
                get: { mode },
                set: { modeRaw = $0.rawValue }
            )) {
                Image(systemName: "list.bullet").tag(TaskGraphViewMode.list)
                Image(systemName: "rectangle.split.3x1").tag(TaskGraphViewMode.kanban)
            }
            .pickerStyle(.segmented)
            .frame(width: 70)
            .controlSize(.mini)
            .help(mode == .list ? "List view (의존성 들여쓰기)" : "Kanban view (status별 컬럼)")
            Button(action: onAddTask) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .buttonStyle(.plain)
            .help("수동 task 추가")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Color.surface)
    }

    @ViewBuilder
    private var content: some View {
        if tasks.isEmpty {
            EmptyStateHint(
                icon: "list.bullet.rectangle",
                title: "추적 중인 task가 없어요",
                message: "‘+’로 수동 추가하거나, /decompose 명령으로 큰 task를 LLM이 자동 분해할 수 있어요."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch mode {
            case .list:
                listView
            case .kanban:
                kanbanView
            }
        }
    }

    private var listView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(tasks) { task in
                    TaskRow(
                        task: task,
                        allTasks: tasks,
                        onUpdateStatus: { status in onUpdateStatus(task.id, status) },
                        onRemove: { onRemove(task.id) },
                        onRunReady: { onRunReadyTask(task.id) },
                        onShowWalkthrough: { onShowWalkthrough(task.id) },
                        onShowRehearsal: { onShowRehearsal(task.id) }
                    )
                }
            }
            .padding(Theme.Spacing.sm)
        }
    }

    /// Linear Method 패턴 — 3 컬럼 horizontal scroll
    private var kanbanView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                kanbanColumn(title: "Pending", status: .pending, tint: Theme.Color.textTertiary)
                kanbanColumn(title: "Running", status: .running, tint: .green)
                kanbanColumn(title: "Done", status: .completed, tint: .gray)
                if tasks.contains(where: { $0.status == .failed }) {
                    kanbanColumn(title: "Failed", status: .failed, tint: .red)
                }
            }
            .padding(Theme.Spacing.sm)
        }
    }

    private func kanbanColumn(title: String, status: TaskStatus, tint: SwiftUI.Color) -> some View {
        let columnTasks = tasks.filter { $0.status == status }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title)
                    .font(Theme.Typography.micro.weight(.medium))
                    .foregroundStyle(tint)
                Text("\(columnTasks.count)")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            .padding(.horizontal, 6)
            ForEach(columnTasks) { task in
                KanbanCard(
                    task: task,
                    allTasks: tasks,
                    onUpdateStatus: { status in onUpdateStatus(task.id, status) },
                    onRemove: { onRemove(task.id) },
                    onRunReady: { onRunReadyTask(task.id) }
                )
            }
            if columnTasks.isEmpty {
                Text("—")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(8)
            }
        }
        .frame(width: 180, alignment: .leading)
        .padding(6)
        .background(Theme.Color.surface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }
}

/// Kanban view mode (ADR-050).
public enum TaskGraphViewMode: String, Sendable, CaseIterable {
    case list, kanban
}

/// Kanban card — column 안의 단일 task 카드.
private struct KanbanCard: View {
    let task: HarnessTask
    let allTasks: [HarnessTask]
    let onUpdateStatus: (TaskStatus) -> Void
    let onRemove: () -> Void
    let onRunReady: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if let agent = task.assignedAgent {
                    AgentBadge(agent: agent, size: .small)
                }
                Text(task.title)
                    .font(Theme.Typography.micro.weight(.medium))
                    .foregroundStyle(Theme.Color.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            if !task.description.isEmpty {
                Text(task.description)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(3)
            }
            if task.isReady(allTasks: allTasks) && task.status == .pending {
                Button("▶ 실행", action: onRunReady)
                    .buttonStyle(.borderless)
                    .controlSize(.mini)
                    .foregroundStyle(Theme.Color.accent)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Color.bg)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .stroke(Theme.Color.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .onHover { hovering = $0 }
        .contextMenu {
            ForEach(TaskStatus.allCases, id: \.self) { s in
                Button(s.rawValue, action: { onUpdateStatus(s) })
            }
            Divider()
            Button(role: .destructive, action: onRemove) {
                Label("삭제", systemImage: "trash")
            }
        }
    }
}

private struct TaskRow: View {
    let task: HarnessTask
    let allTasks: [HarnessTask]
    let onUpdateStatus: (TaskStatus) -> Void
    let onRemove: () -> Void
    let onRunReady: () -> Void
    let onShowWalkthrough: () -> Void
    let onShowRehearsal: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // depth indent
            if !task.dependencies.isEmpty {
                Spacer().frame(width: 16)
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(.top, 2)
            }
            statusIcon
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(task.title)
                        .font(Theme.Typography.small.weight(.medium))
                        .foregroundStyle(Theme.Color.text)
                        .lineLimit(1)
                    if let agent = task.assignedAgent {
                        AgentBadge(agent: agent, size: .small)
                    }
                    Spacer()
                    // ADR-050 — 의존성 모두 완료된 ready task는 prominent ▶ 버튼
                    if task.isReady(allTasks: allTasks) && task.status == .pending {
                        Button(action: onRunReady) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.Color.accent)
                        }
                        .buttonStyle(.plain)
                        .help("이 task를 시작 (active pane으로 dispatch)")
                    }
                    if hovering {
                        // ADR-051 — Walk-through 버튼 (완료된 task만)
                        if task.status == .completed || task.status == .failed {
                            Button(action: onShowWalkthrough) {
                                Image(systemName: "rectangle.stack.fill.badge.person.crop")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.Color.accent)
                            }
                            .buttonStyle(.plain)
                            .help("이 task의 진행 과정 walk-through")
                            // ADR-052 — Rehearsal 버튼 (완료된 task에 대해 다른 모델로 재실행)
                            Button(action: onShowRehearsal) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.orange)
                            }
                            .buttonStyle(.plain)
                            .help("이 task를 다른 모델로 리허설 (ADR-052)")
                        }
                        Menu {
                            ForEach(TaskStatus.allCases, id: \.self) { s in
                                Button(s.rawValue, action: { onUpdateStatus(s) })
                            }
                            Divider()
                            Button(role: .destructive, action: onRemove) {
                                Label("삭제", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.Color.textSecondary)
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 20)
                    }
                }
                if !task.description.isEmpty {
                    Text(task.description)
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .lineLimit(2)
                }
                if let output = task.output, !output.isEmpty {
                    Text(output)
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.accent)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 4)
        .background(rowBg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var statusIcon: some View {
        let isReady = task.isReady(allTasks: allTasks)
        switch task.status {
        case .pending:
            Image(systemName: isReady ? "circle.dashed" : "circle.dotted")
                .font(.system(size: 12))
                .foregroundStyle(isReady ? Theme.Color.accent : Theme.Color.textTertiary)
                .help(isReady ? "실행 가능 (의존성 모두 완료)" : "대기 중 (의존성 미완료)")
        case .running:
            Image(systemName: "circle.dashed")
                .font(.system(size: 12))
                .foregroundStyle(Color.green)
                .help("진행 중")
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.green)
                .help("완료")
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.red)
                .help("실패")
        }
    }

    private var rowBg: SwiftUI.Color {
        if hovering { return Theme.Color.surfaceHi }
        return .clear
    }
}
