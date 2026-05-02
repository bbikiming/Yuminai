import Foundation

// MARK: - ChildClaudeProcess (ADR-053)

/// 격리된 ephemeral Claude/Codex 호출 — 메인 conversation에 영향 없는 1회성 LLM 호출.
///
/// **출처/근거** (ADR-052에서 검증):
/// - Aider `architect_coder.py:23,30,37-39` — `editor_coder = Coder.create(... cur_messages=[], cache_prompts=False)`
/// - Cline `SubagentRunner.ts:243,297,393` — 자체 `apiHandler` + 자체 `conversation: ClineStorageMessage[] = []`
/// - Claude Code Task tool — 각 sub-agent 자체 context window
///
/// **사용 시나리오**:
/// 1. **Decomposition**: `/decompose` 호출 시 메인 conversation cache 보호
/// 2. **Rehearsal**: 완료된 task를 다른 모델로 재실행 → 결과 비교
/// 3. **Multi-agent parallel**: 두 번째 task를 다른 pane에 동시 dispatch
/// 4. **Routing classification (LLM-based)**: 향후 keyword 휴리스틱을 LLM 분류기로 교체 시
///
/// **격리 보장**:
/// - 별도 Process spawn (workspace cwd는 공유, 그러나 session-id는 unique)
/// - prompt 자체에 `<ephemeral>` marker (cache control hint)
/// - 결과는 단일 String + UsageDelta로 반환 (메인 conversation에는 caller 책임으로 import)
/// - 비용 추적은 별도 bucket (CostTracker)
public protocol ChildClaudeProcess: Sendable {
    /// 1회성 prompt 호출 → 결과 collect → process terminate.
    /// caller는 반환된 `ChildProcessOutput`을 main conversation에 적절히 import (또는 무시).
    func runOnce(
        prompt: String,
        in workspace: Workspace,
        agent: AgentKind,
        purpose: ChildProcessPurpose,
        timeoutSeconds: Int
    ) async throws -> ChildProcessOutput
}

/// purpose enum — observability 및 cost bucket 라우팅용.
public enum ChildProcessPurpose: String, Sendable, Hashable, Codable, CaseIterable {
    case decomposition  // /decompose ephemeral
    case rehearsal      // walk-through re-run
    case parallel       // multi-agent parallel second pane
    case routing        // LLM-based routing classifier (향후)

    public var displayLabel: String {
        switch self {
        case .decomposition: return "분해"
        case .rehearsal: return "리허설"
        case .parallel: return "병렬"
        case .routing: return "라우팅"
        }
    }
}

/// 1회성 호출 결과.
public struct ChildProcessOutput: Sendable, Hashable {
    /// agent의 final 응답 텍스트 (toolCall/result 등 모두 join).
    public let resultText: String
    /// 추정 또는 실제 token usage.
    public let inputTokens: Int
    public let outputTokens: Int
    /// 비용 (있으면 LLM cost report, 없으면 estimate).
    public let costUSD: Double
    /// 실행 시간 (ms).
    public let durationMs: Int
    /// process exit code.
    public let exitCode: Int32

    public init(
        resultText: String,
        inputTokens: Int,
        outputTokens: Int,
        costUSD: Double,
        durationMs: Int,
        exitCode: Int32
    ) {
        self.resultText = resultText
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUSD = costUSD
        self.durationMs = durationMs
        self.exitCode = exitCode
    }
}

// MARK: - ChildProcessProgress (ADR-054)

/// 진행 중인 ChildClaudeProcess의 observable state.
/// AppModel.activeChildProcesses에 등록 → UI가 spinner/badge 표시.
public struct ChildProcessProgress: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public let purpose: ChildProcessPurpose
    public let agentRaw: String
    public let startedAt: Date
    public let purposeContext: String  // 예: "task ‘Refactor core’ 분해"
    public var status: Status

    public enum Status: String, Sendable, Hashable, Codable {
        case starting
        case running
        case completed
        case failed
    }

    public init(
        id: UUID = UUID(),
        purpose: ChildProcessPurpose,
        agentRaw: String,
        startedAt: Date = Date(),
        purposeContext: String,
        status: Status = .starting
    ) {
        self.id = id
        self.purpose = purpose
        self.agentRaw = agentRaw
        self.startedAt = startedAt
        self.purposeContext = purposeContext
        self.status = status
    }

    public func elapsedSeconds(now: Date = Date()) -> Int {
        Int(now.timeIntervalSince(startedAt))
    }
}

// MARK: - Mock (테스트용)

/// 테스트/preview용 mock — 실제 process spawn 없이 즉시 fixed 응답 반환.
public actor MockChildClaudeProcess: ChildClaudeProcess {
    /// caller가 미리 등록한 응답들 (purpose별).
    private var responses: [ChildProcessPurpose: String] = [:]
    /// caller가 시뮬레이션할 비용.
    public var simulatedCostUSD: Double = 0.001
    /// caller가 시뮬레이션할 토큰.
    public var simulatedInputTokens: Int = 100
    public var simulatedOutputTokens: Int = 50

    public init() {}

    public func setResponse(_ text: String, for purpose: ChildProcessPurpose) {
        responses[purpose] = text
    }

    public func setSimulatedCost(usd: Double, inputTokens: Int, outputTokens: Int) {
        simulatedCostUSD = usd
        simulatedInputTokens = inputTokens
        simulatedOutputTokens = outputTokens
    }

    public func runOnce(
        prompt: String,
        in workspace: Workspace,
        agent: AgentKind,
        purpose: ChildProcessPurpose,
        timeoutSeconds: Int = 60
    ) async throws -> ChildProcessOutput {
        let canned = responses[purpose] ?? "[mock \(purpose.rawValue) for \(agent.shortLabel)] echo: \(prompt.prefix(60))…"
        return ChildProcessOutput(
            resultText: canned,
            inputTokens: simulatedInputTokens,
            outputTokens: simulatedOutputTokens,
            costUSD: simulatedCostUSD,
            durationMs: 50,
            exitCode: 0
        )
    }
}
