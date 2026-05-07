import Foundation
import os

/// **ADR-132** — 자동 실행 오케스트레이터.
///
/// 상태 머신:
/// ```
/// idle → running → completed/stopped
///              ↓↑
///           paused
/// ```
///
/// ## 안전장치
/// - `stopOnDestructive`: HITLActionGuard 패턴 매칭 → paused + 사용자 승인 대기
/// - `maxTurns` / `maxBudgetUSD` / `maxDurationSeconds`: hard limit 도달 시 자동 종료
/// - `errorThreshold`: 연속 N회 실패 → 자동 종료
/// - kill switch: `stop(reason:)` 어느 상태에서든 즉시 종료
///
/// ## 사용 패턴
/// ```swift
/// let coord = AutoRunCoordinator()
/// await coord.start(config: config, initialPrompt: prompt) { turn, prompt in
///     // LLM 호출 — AppModel.sendMessage 등
///     return AutoRunTurnLog(...)
/// }
/// ```
public actor AutoRunCoordinator {

    // MARK: - State

    /// 자동 실행 상태.
    public enum State: Sendable, Equatable {
        case idle
        case running(runId: UUID, turn: Int, startedAt: Date)
        case paused(runId: UUID, reason: String)
        case completed(runId: UUID, reason: AutoRunCompletionReason, summary: String, totalCost: Double)
        case stopped(runId: UUID, reason: String)

        /// 실행 중 여부 (running 또는 paused).
        public var isActive: Bool {
            switch self {
            case .running, .paused: return true
            case .idle, .completed, .stopped: return false
            }
        }

        /// 실행 중인 run ID.
        public var runId: UUID? {
            switch self {
            case .running(let id, _, _): return id
            case .paused(let id, _): return id
            case .completed(let id, _, _, _): return id
            case .stopped(let id, _): return id
            case .idle: return nil
            }
        }
    }

    // MARK: - 내부 상태

    private var state: State = .idle
    private var continuations: [UUID: AsyncStream<State>.Continuation] = [:]

    // 실행 제어
    private var shouldStop: Bool = false
    private var isPaused: Bool = false
    private var pauseReason: String = ""
    private var resumeSignal: CheckedContinuation<Void, Never>? = nil

    // 로그
    private(set) public var logs: [AutoRunTurnLog] = []
    private var totalCostAccumulated: Double = 0
    private var consecutiveErrors: Int = 0

    private static let logger = Logger(subsystem: "ai.yuminai", category: "AutoRunCoordinator")

    // MARK: - init

    public init() {}

    // MARK: - Public API

    /// 자동 실행 시작.
    ///
    /// - Parameters:
    ///   - config: 실행 설정.
    ///   - initialPrompt: 첫 번째 turn에 보낼 프롬프트.
    ///   - executeTurn: 매 turn 실행 콜백 (turn 번호, 프롬프트) → `AutoRunTurnLog`.
    ///                  nil 프롬프트 = 이전 응답 기반 자동 계속 진행.
    public func start(
        config: AutoRunConfig,
        initialPrompt: String,
        executeTurn: @escaping @Sendable (Int, String?) async throws -> AutoRunTurnLog
    ) async {
        guard case .idle = state else {
            Self.logger.warning("start() called while not idle — ignored")
            return
        }

        let runId = UUID()
        let startedAt = Date()
        shouldStop = false
        isPaused = false
        logs = []
        totalCostAccumulated = 0
        consecutiveErrors = 0

        updateState(.running(runId: runId, turn: 1, startedAt: startedAt))
        Self.logger.info("자동 실행 시작 — runId=\(runId.uuidString), maxTurns=\(config.maxTurns)")

        var completionReason: AutoRunCompletionReason? = nil

        for turn in 1...config.maxTurns {
            // kill switch 확인
            if shouldStop {
                break
            }

            // 예산 확인
            if totalCostAccumulated >= config.maxBudgetUSD {
                completionReason = .maxBudgetReached(config.maxBudgetUSD)
                break
            }

            // 시간 확인
            let elapsed = Date().timeIntervalSince(startedAt)
            if elapsed >= config.maxDurationSeconds {
                completionReason = .maxDurationReached(config.maxDurationSeconds)
                break
            }

            // pause 대기
            if isPaused {
                updateState(.paused(runId: runId, reason: pauseReason))
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    self.resumeSignal = cont
                }
                if shouldStop { break }
                updateState(.running(runId: runId, turn: turn, startedAt: startedAt))
            }

            updateState(.running(runId: runId, turn: turn, startedAt: startedAt))

            // 실행
            let prompt: String? = turn == 1 ? initialPrompt : nil
            do {
                let log = try await executeTurn(turn, prompt)
                logs.append(log)
                totalCostAccumulated += log.costUSD
                consecutiveErrors = 0

                // Destructive 감지
                if config.stopOnDestructive, let category = checkDestructive(log.agentResponse) {
                    Self.logger.warning("Destructive 감지: \(category)")
                    isPaused = true
                    pauseReason = "위험 명령 감지: \(category)"
                    updateState(.paused(runId: runId, reason: pauseReason))
                    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                        self.resumeSignal = cont
                    }
                    if shouldStop {
                        completionReason = .destructiveBlocked(category)
                        break
                    }
                    continue
                }

                // Stop keyword 감지
                if let kw = checkStopKeyword(log.agentResponse, keywords: config.stopKeywords) {
                    Self.logger.info("Stop keyword 감지: \(kw)")
                    completionReason = .stopKeyword(kw)
                    break
                }

            } catch {
                consecutiveErrors += 1
                Self.logger.error("Turn \(turn) 실패 (\(self.consecutiveErrors)/\(config.errorThreshold)): \(error.localizedDescription)")
                if consecutiveErrors >= config.errorThreshold {
                    completionReason = .errorThreshold(config.errorThreshold)
                    break
                }
            }

            // 마지막 turn 도달
            if turn == config.maxTurns {
                completionReason = .maxTurnsReached(config.maxTurns)
            }
        }

        if shouldStop && completionReason == nil {
            updateState(.stopped(runId: runId, reason: "사용자 중단"))
        } else {
            let reason = completionReason ?? .maxTurnsReached(config.maxTurns)
            let summary = buildSummary(reason: reason, totalCost: totalCostAccumulated, turnCount: logs.count)
            updateState(.completed(runId: runId, reason: reason, summary: summary, totalCost: totalCostAccumulated))
            Self.logger.info("자동 실행 완료 — reason=\(reason.displayDescription), totalCost=$\(self.totalCostAccumulated, format: .fixed(precision: 4))")
        }
    }

    /// 즉시 중단 (kill switch).
    public func stop(reason: String = "사용자 중단") async {
        shouldStop = true
        // pause 중이면 resume해서 루프 탈출
        if let cont = resumeSignal {
            resumeSignal = nil
            cont.resume()
        }
        let currentRunId = state.runId ?? UUID()
        updateState(.stopped(runId: currentRunId, reason: reason))
        Self.logger.info("자동 실행 중단 — reason: \(reason)")
    }

    /// 일시 정지.
    public func pause(reason: String = "사용자 일시 정지") async {
        guard case .running(let runId, _, _) = state else { return }
        isPaused = true
        pauseReason = reason
        updateState(.paused(runId: runId, reason: reason))
    }

    /// 재개. 누적 limits는 리셋하지 않음.
    public func resume() async {
        guard case .paused = state else { return }
        isPaused = false
        if let cont = resumeSignal {
            resumeSignal = nil
            cont.resume()
        }
    }

    /// 현재 상태 반환.
    public func current() -> State {
        state
    }

    /// 현재 누적 비용 반환.
    public func currentTotalCost() -> Double {
        totalCostAccumulated
    }

    /// 현재 로그 스냅샷 반환.
    public func currentLogs() -> [AutoRunTurnLog] {
        logs
    }

    /// 상태 변경 AsyncStream.
    public func stateStream() -> AsyncStream<State> {
        let streamId = UUID()
        return AsyncStream { continuation in
            self.continuations[streamId] = continuation
            continuation.onTermination = { [streamId] _ in
                Task { [weak self, streamId] in
                    await self?.removeContinuation(id: streamId)
                }
            }
        }
    }

    // MARK: - 내부

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func updateState(_ newState: State) {
        state = newState
        for cont in continuations.values {
            cont.yield(newState)
        }
    }

    /// HITLActionGuard 패턴으로 응답에서 destructive 카테고리 감지.
    private func checkDestructive(_ response: String) -> String? {
        HITLActionGuard.category(for: response)
    }

    /// 응답에서 stop keyword 탐색.
    private func checkStopKeyword(_ response: String, keywords: [String]) -> String? {
        for kw in keywords where response.contains(kw) {
            return kw
        }
        return nil
    }

    /// 완료 요약 문자열 생성.
    private func buildSummary(reason: AutoRunCompletionReason, totalCost: Double, turnCount: Int) -> String {
        let costStr = String(format: "$%.4f", totalCost)
        return "\(turnCount)회 실행 완료 · 총 비용 \(costStr) · \(reason.displayDescription)"
    }
}
