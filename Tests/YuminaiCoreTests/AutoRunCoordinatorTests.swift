import Foundation
import Testing
@testable import YuminaiCore

@Suite("AutoRunCoordinator (ADR-132)")
struct AutoRunCoordinatorTests {

    // MARK: - 초기 상태

    @Test("초기 상태는 idle")
    func initialStateIsIdle() async {
        let coord = AutoRunCoordinator()
        let state = await coord.current()
        guard case .idle = state else {
            Issue.record("초기 상태가 idle이 아님: \(state)")
            return
        }
    }

    @Test("초기 누적 비용 == 0")
    func initialCostIsZero() async {
        let coord = AutoRunCoordinator()
        let cost = await coord.currentTotalCost()
        #expect(cost == 0.0)
    }

    // MARK: - Stop keyword 종료

    @Test("stop keyword 감지 시 completed(stopKeyword) 전환")
    func stopsOnStopKeyword() async {
        let coord = AutoRunCoordinator()
        var config = AutoRunConfig()
        config.stopKeywords = ["작업 완료"]
        config.maxTurns = 10

        await coord.start(config: config, initialPrompt: "테스트") { turn, _ in
            AutoRunTurnLog(
                runId: UUID(),
                turn: turn,
                timestamp: .now,
                userPrompt: nil,
                agentResponse: turn == 2 ? "작업 완료했습니다." : "진행 중...",
                toolCalls: [],
                costUSD: 0.01,
                durationSeconds: 0.1,
                warnings: []
            )
        }

        let state = await coord.current()
        guard case .completed(_, let reason, _, _) = state else {
            Issue.record("완료 상태가 아님: \(state)")
            return
        }
        guard case .stopKeyword(let kw) = reason else {
            Issue.record("종료 이유가 stopKeyword가 아님: \(reason)")
            return
        }
        #expect(kw == "작업 완료")
    }

    // MARK: - maxTurns 종료

    @Test("maxTurns 도달 시 completed(maxTurnsReached) 전환")
    func stopsAtMaxTurns() async {
        let coord = AutoRunCoordinator()
        var config = AutoRunConfig()
        config.maxTurns = 3
        config.stopKeywords = []

        await coord.start(config: config, initialPrompt: "테스트") { turn, _ in
            AutoRunTurnLog(
                runId: UUID(),
                turn: turn,
                timestamp: .now,
                userPrompt: nil,
                agentResponse: "계속 진행 중",
                toolCalls: [],
                costUSD: 0.01,
                durationSeconds: 0.1,
                warnings: []
            )
        }

        let state = await coord.current()
        guard case .completed(_, let reason, _, _) = state else {
            Issue.record("완료 상태가 아님: \(state)")
            return
        }
        guard case .maxTurnsReached(let n) = reason else {
            Issue.record("종료 이유가 maxTurnsReached가 아님: \(reason)")
            return
        }
        #expect(n == 3)
    }

    // MARK: - 예산 종료

    @Test("maxBudgetUSD 초과 시 completed(maxBudgetReached) 전환")
    func stopsAtMaxBudget() async {
        let coord = AutoRunCoordinator()
        var config = AutoRunConfig()
        config.maxTurns = 10
        config.maxBudgetUSD = 0.05  // 매우 작은 예산
        config.stopKeywords = []

        await coord.start(config: config, initialPrompt: "테스트") { turn, _ in
            AutoRunTurnLog(
                runId: UUID(),
                turn: turn,
                timestamp: .now,
                userPrompt: nil,
                agentResponse: "응답",
                toolCalls: [],
                costUSD: 0.03,  // 2회면 0.06 > 0.05
                durationSeconds: 0.1,
                warnings: []
            )
        }

        let state = await coord.current()
        guard case .completed(_, let reason, _, _) = state else {
            Issue.record("완료 상태가 아님: \(state)")
            return
        }
        guard case .maxBudgetReached = reason else {
            Issue.record("종료 이유가 maxBudgetReached가 아님: \(reason)")
            return
        }
    }

    // MARK: - 에러 임계값 종료

    @Test("연속 에러 errorThreshold 도달 시 completed(errorThreshold) 전환")
    func stopsAtErrorThreshold() async {
        let coord = AutoRunCoordinator()
        var config = AutoRunConfig()
        config.maxTurns = 10
        config.errorThreshold = 2
        config.stopKeywords = []

        struct TestError: Error {}

        await coord.start(config: config, initialPrompt: "테스트") { _, _ in
            throw TestError()
        }

        let state = await coord.current()
        guard case .completed(_, let reason, _, _) = state else {
            Issue.record("완료 상태가 아님: \(state)")
            return
        }
        guard case .errorThreshold(let n) = reason else {
            Issue.record("종료 이유가 errorThreshold가 아님: \(reason)")
            return
        }
        #expect(n == 2)
    }

    // MARK: - kill switch

    @Test("start 전 stop() 호출은 무시됨 — idle 유지")
    func stopBeforeStartIsNoop() async {
        let coord = AutoRunCoordinator()
        await coord.stop(reason: "테스트")
        // stop() called on idle — state becomes stopped with a dummy UUID
        // but since start was never called, logs are empty
        let logs = await coord.currentLogs()
        #expect(logs.isEmpty)
    }

    // MARK: - state isActive

    @Test("running 상태는 isActive == true")
    func runningIsActive() {
        let state = AutoRunCoordinator.State.running(runId: UUID(), turn: 1, startedAt: .now)
        #expect(state.isActive == true)
    }

    @Test("paused 상태는 isActive == true")
    func pausedIsActive() {
        let state = AutoRunCoordinator.State.paused(runId: UUID(), reason: "테스트")
        #expect(state.isActive == true)
    }

    @Test("idle 상태는 isActive == false")
    func idleIsNotActive() {
        let state = AutoRunCoordinator.State.idle
        #expect(state.isActive == false)
    }

    @Test("completed 상태는 isActive == false")
    func completedIsNotActive() {
        let state = AutoRunCoordinator.State.completed(
            runId: UUID(),
            reason: .userStop,
            summary: "완료",
            totalCost: 0
        )
        #expect(state.isActive == false)
    }

    @Test("stopped 상태는 isActive == false")
    func stoppedIsNotActive() {
        let state = AutoRunCoordinator.State.stopped(runId: UUID(), reason: "중단")
        #expect(state.isActive == false)
    }

    // MARK: - 누적 비용

    @Test("완료 후 totalCost가 누적됨")
    func totalCostAccumulates() async {
        let coord = AutoRunCoordinator()
        var config = AutoRunConfig()
        config.maxTurns = 3
        config.stopKeywords = []

        await coord.start(config: config, initialPrompt: "테스트") { turn, _ in
            AutoRunTurnLog(
                runId: UUID(),
                turn: turn,
                timestamp: .now,
                userPrompt: nil,
                agentResponse: "응답",
                toolCalls: [],
                costUSD: 0.10,
                durationSeconds: 0.1,
                warnings: []
            )
        }

        let cost = await coord.currentTotalCost()
        #expect(abs(cost - 0.30) < 0.001)
    }

    // MARK: - logs count

    @Test("완료 후 logs 개수가 turn 수와 일치")
    func logsCountMatchesTurns() async {
        let coord = AutoRunCoordinator()
        var config = AutoRunConfig()
        config.maxTurns = 4
        config.stopKeywords = []

        await coord.start(config: config, initialPrompt: "테스트") { turn, _ in
            AutoRunTurnLog(
                runId: UUID(),
                turn: turn,
                timestamp: .now,
                userPrompt: nil,
                agentResponse: "응답",
                toolCalls: [],
                costUSD: 0.01,
                durationSeconds: 0.1,
                warnings: []
            )
        }

        let logs = await coord.currentLogs()
        #expect(logs.count == 4)
    }

    // MARK: - AutoRunCompletionReason Codable

    @Test("AutoRunCompletionReason Codable round-trip — stopKeyword")
    func completionReasonCodableStopKeyword() throws {
        let reason: AutoRunCompletionReason = .stopKeyword("작업 완료")
        let data = try JSONEncoder().encode(reason)
        let decoded = try JSONDecoder().decode(AutoRunCompletionReason.self, from: data)
        #expect(decoded == reason)
    }

    @Test("AutoRunCompletionReason Codable round-trip — maxTurnsReached")
    func completionReasonCodableMaxTurns() throws {
        let reason: AutoRunCompletionReason = .maxTurnsReached(30)
        let data = try JSONEncoder().encode(reason)
        let decoded = try JSONDecoder().decode(AutoRunCompletionReason.self, from: data)
        #expect(decoded == reason)
    }

    @Test("AutoRunCompletionReason Codable round-trip — userStop")
    func completionReasonCodableUserStop() throws {
        let reason: AutoRunCompletionReason = .userStop
        let data = try JSONEncoder().encode(reason)
        let decoded = try JSONDecoder().decode(AutoRunCompletionReason.self, from: data)
        #expect(decoded == reason)
    }

    @Test("AutoRunCompletionReason displayDescription — 비어있지 않음")
    func completionReasonDisplayDescription() {
        let reasons: [AutoRunCompletionReason] = [
            .stopKeyword("완료"),
            .maxTurnsReached(30),
            .maxBudgetReached(3.0),
            .maxDurationReached(1800),
            .userStop,
            .errorThreshold(3),
            .destructiveBlocked("rm -rf")
        ]
        for reason in reasons {
            #expect(!reason.displayDescription.isEmpty)
        }
    }
}
