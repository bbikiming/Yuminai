import Foundation
import Observation
import YuminaiCore

/// 다중 모델 오케스트레이션 — Antigravity-style harness (ADR-047 Phase 2 skeleton).
///
/// **현재 책임 (Phase 1+2 minimal)**:
/// - SharedConversationLog 관리 (워크스페이스 별 단일 timeline)
/// - TaskGraph 관리 (수동 task 추가 — 자동 분해는 Phase 4)
/// - 모델 추천 (`recommendAgent(for:)`) — Phase 3에서 자동 routing 적용
/// - HandoffPrompt 생성 (`buildHandoffPrompt(...)`) — Phase 3에서 모델 전환 시 자동 호출
///
/// **현재 미구현 (Phase 3+)**:
/// - 자동 routing — 사용자 입력 → recommend → pane 자동 전환
/// - Handoff prompt 자동 inject (CLI session에 system message로)
/// - TaskGraph 자동 분해 (큰 task → sub-task LLM 호출)
/// - Multi-agent 동시 작업 (현재는 단일 active pane)
///
/// **기존 코드와의 관계**:
/// - AgentPaneCoordinator와 공존 — pane lifecycle은 그대로 사용
/// - 사용자 메시지 시 SharedLog에 기록 + (Phase 3+) routing 적용
/// - 향후 facade로 evolution 가능
@MainActor
@Observable
public final class HarnessOrchestrator {
    /// SharedConversationLog (워크스페이스 별 — Phase 1은 메모리만, Phase 4에서 영속).
    public var conversationLog: [ConversationEntry] = []

    /// TaskGraph (Phase 1은 메모리만).
    public var tasks: [HarnessTask] = []

    /// 사용자 자동 routing 활성 (Phase 3+ 적용 — 현재는 noop).
    public var autoRoutingEnabled: Bool = false

    public init() {}

    // MARK: - Conversation Log

    /// User 메시지 기록.
    public func appendUser(_ content: String, attachments: [String] = [], taskId: UUID? = nil) {
        conversationLog.append(ConversationEntry(
            role: .user,
            content: content,
            attachments: attachments,
            taskId: taskId
        ))
    }

    /// Agent 응답 기록.
    public func appendAgent(_ content: String, agentKind: AgentKind, taskId: UUID? = nil, tokenCount: Int? = nil) {
        conversationLog.append(ConversationEntry(
            role: .agent,
            agentKind: agentKind,
            content: content,
            taskId: taskId,
            tokenCount: tokenCount
        ))
    }

    /// 시스템 메시지 (handoff, transition 등).
    public func appendSystem(_ content: String, taskId: UUID? = nil) {
        conversationLog.append(ConversationEntry(
            role: .system,
            content: content,
            taskId: taskId
        ))
    }

    /// 워크스페이스 전환 시 호출. log 클리어 + tasks 초기화.
    public func resetForWorkspace() {
        conversationLog = []
        tasks = []
    }

    // MARK: - Routing

    /// 사용자 입력 → 추천 모델. autoRoutingEnabled=true 시 caller가 사용.
    /// Phase 3에서 구현될 자동 전환 로직의 input.
    public func recommendAgent(for userText: String) -> AgentKind {
        let kind = ModelCapabilityMatrix.inferTaskKind(from: userText)
        return ModelCapabilityMatrix.recommend(for: kind)
    }

    public func inferTaskKind(for userText: String) -> TaskKind {
        ModelCapabilityMatrix.inferTaskKind(from: userText)
    }

    // MARK: - Handoff

    /// 모델 전환 시 새 모델에 보낼 catch-up prompt 생성.
    /// caller (HarnessOrchestrator wrapper 또는 AppModel)가 새 pane의 첫 메시지로 사용.
    /// ADR-048 — projectProfile 추가로 프로젝트 컨텍스트 포함.
    public func buildHandoffPrompt(
        targetModel: AgentKind,
        currentTaskId: UUID? = nil,
        projectProfile: ProjectProfile? = nil,
        recentEntriesVerbatim: Int = 5,
        tokenBudget: Int = 4000
    ) -> HandoffPromptBuilder.Output {
        let task = currentTaskId.flatMap { id in tasks.first(where: { $0.id == id }) }
        return HandoffPromptBuilder.build(
            log: conversationLog,
            targetModel: targetModel,
            currentTask: task,
            projectProfile: projectProfile,
            recentEntriesVerbatim: recentEntriesVerbatim,
            tokenBudget: tokenBudget
        )
    }

    // MARK: - Task Graph

    /// 새 task 추가 (수동). Phase 4에서 LLM 자동 분해로 대체 가능.
    @discardableResult
    public func addTask(
        title: String,
        description: String,
        assignedAgent: AgentKind? = nil,
        dependencies: [UUID] = []
    ) -> HarnessTask {
        let task = HarnessTask(
            title: title,
            description: description,
            assignedAgent: assignedAgent,
            dependencies: dependencies
        )
        tasks.append(task)
        return task
    }

    public func updateTaskStatus(_ id: UUID, _ status: TaskStatus, output: String? = nil) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].status = status
        if let output {
            tasks[idx].output = output
        }
    }

    public func removeTask(_ id: UUID) {
        tasks.removeAll { $0.id == id }
    }

    /// 현재 실행 가능한 task (의존성 모두 completed + 자기 status pending).
    public var readyTasks: [HarnessTask] {
        tasks.filter { $0.isReady(allTasks: tasks) }
    }

    // MARK: - Telemetry

    /// 누적 토큰 추정 (각 entry tokenCount 합 — nil은 utf8 byte / 4로 추정).
    public var estimatedTotalTokens: Int {
        conversationLog.reduce(0) { sum, entry in
            sum + (entry.tokenCount ?? entry.content.utf8.count / 4)
        }
    }

    /// 모델 별 응답 횟수 (Phase 5 UI에서 사용).
    public var agentResponseCounts: [AgentKind: Int] {
        var counts: [AgentKind: Int] = [:]
        for entry in conversationLog where entry.role == .agent {
            if let kind = entry.agentKind {
                counts[kind, default: 0] += 1
            }
        }
        return counts
    }
}
