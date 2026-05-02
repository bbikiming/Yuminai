import Foundation
import Testing
@testable import YuminaiCore

@Suite("ConversationEntry — log entry 모델 (ADR-047 Phase 1)")
struct ConversationEntryTests {
    @Test("기본 init은 user role")
    func userEntry() {
        let e = ConversationEntry(role: .user, content: "hello")
        #expect(e.role == .user)
        #expect(e.agentKind == nil)
        #expect(e.attachments.isEmpty)
        #expect(e.taskId == nil)
    }

    @Test("agent entry는 agentKind 포함")
    func agentEntry() {
        let e = ConversationEntry(role: .agent, agentKind: .codex, content: "code", tokenCount: 50)
        #expect(e.role == .agent)
        #expect(e.agentKind == .codex)
        #expect(e.tokenCount == 50)
    }

    @Test("Codable round-trip 보존")
    func codableRoundTrip() throws {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let e = ConversationEntry(
            id: id, timestamp: date, role: .agent, agentKind: .claude,
            content: "test", attachments: ["@/file.swift"],
            taskId: UUID(), tokenCount: 100
        )
        let data = try JSONEncoder().encode(e)
        let decoded = try JSONDecoder().decode(ConversationEntry.self, from: data)
        #expect(decoded == e)
    }
}

@Suite("ModelCapabilityMatrix — task 추정 + 모델 추천 (ADR-047 Phase 1)")
struct ModelCapabilityMatrixTests {
    @Test("planning/codeReview/refactoring/debugging은 Claude")
    func claudeTasks() {
        for kind in [TaskKind.planning, .codeReview, .refactoring, .debugging, .generalChat] {
            #expect(ModelCapabilityMatrix.recommend(for: kind) == .claude)
        }
    }

    @Test("codeGeneration은 Codex")
    func codexTask() {
        #expect(ModelCapabilityMatrix.recommend(for: .codeGeneration) == .codex)
    }

    @Test("longContextSearch는 현재 Claude (Gemini 향후)")
    func longContextFallback() {
        #expect(ModelCapabilityMatrix.recommend(for: .longContextSearch) == .claude)
    }

    @Test("unknown은 Claude default")
    func unknownTask() {
        #expect(ModelCapabilityMatrix.recommend(for: .unknown) == .claude)
    }

    @Test("inferTaskKind — 한국어 keyword 매칭")
    func inferKorean() {
        #expect(ModelCapabilityMatrix.inferTaskKind(from: "이 함수 구현해줘") == .codeGeneration)
        #expect(ModelCapabilityMatrix.inferTaskKind(from: "코드 리뷰 부탁해") == .codeReview)
        #expect(ModelCapabilityMatrix.inferTaskKind(from: "버그 고쳐") == .debugging)
        #expect(ModelCapabilityMatrix.inferTaskKind(from: "어떻게 설계할지 계획") == .planning)
        #expect(ModelCapabilityMatrix.inferTaskKind(from: "DB 어디서 찾을 수 있어") == .longContextSearch)
    }

    @Test("inferTaskKind — 영어 keyword 매칭")
    func inferEnglish() {
        #expect(ModelCapabilityMatrix.inferTaskKind(from: "implement a parser") == .codeGeneration)
        #expect(ModelCapabilityMatrix.inferTaskKind(from: "please review my code") == .codeReview)
        #expect(ModelCapabilityMatrix.inferTaskKind(from: "fix this bug") == .debugging)
        #expect(ModelCapabilityMatrix.inferTaskKind(from: "how to approach this") == .planning)
    }

    @Test("inferTaskKind — fallback은 generalChat")
    func inferFallback() {
        #expect(ModelCapabilityMatrix.inferTaskKind(from: "안녕하세요") == .generalChat)
        #expect(ModelCapabilityMatrix.inferTaskKind(from: "thanks") == .generalChat)
    }

    @Test("strengthSummary는 모델 별 한국어 한 줄")
    func strengthSummary() {
        let claudeStr = ModelCapabilityMatrix.strengthSummary(for: .claude)
        let codexStr = ModelCapabilityMatrix.strengthSummary(for: .codex)
        #expect(!claudeStr.isEmpty && claudeStr != codexStr)
        #expect(claudeStr.contains("추론") || claudeStr.contains("리팩터링"))
        #expect(codexStr.contains("코드"))
    }
}

@Suite("HandoffPromptBuilder — 모델 전환 catch-up prompt (ADR-047 Phase 1)")
struct HandoffPromptBuilderTests {
    private func makeLog(count: Int) -> [ConversationEntry] {
        (0..<count).map { i in
            let role: ConversationEntry.Role = (i % 2 == 0) ? .user : .agent
            return ConversationEntry(
                role: role,
                agentKind: role == .agent ? .claude : nil,
                content: "메시지 \(i)"
            )
        }
    }

    @Test("빈 log도 prompt 생성됨 (header + instruction만)")
    func emptyLog() {
        let out = HandoffPromptBuilder.build(log: [], targetModel: .codex)
        #expect(out.promptText.contains(AgentKind.codex.shortLabel))
        #expect(out.promptText.contains("강점"))
        #expect(out.includedEntryIds.isEmpty)
    }

    @Test("log < verbatim cap이면 모두 verbatim 섹션")
    func smallLogAllVerbatim() {
        let log = makeLog(count: 3)
        let out = HandoffPromptBuilder.build(log: log, targetModel: .codex, recentEntriesVerbatim: 5)
        #expect(out.includedEntryIds.count == 3)
        #expect(out.promptText.contains("최근 대화"))
        #expect(!out.promptText.contains("이전 대화 요약"))
    }

    @Test("log > verbatim cap이면 오래된 것 요약 + 최근 verbatim")
    func mixedLog() {
        let log = makeLog(count: 8)
        let out = HandoffPromptBuilder.build(log: log, targetModel: .claude, recentEntriesVerbatim: 5)
        #expect(out.promptText.contains("이전 대화 요약 (오래된 3개)"))
        #expect(out.promptText.contains("최근 대화 (verbatim, 5개)"))
        #expect(out.includedEntryIds.count == 8)
    }

    @Test("targetModel 강점이 prompt에 포함")
    func includesModelStrength() {
        let out = HandoffPromptBuilder.build(log: [], targetModel: .codex)
        let codexStrength = ModelCapabilityMatrix.strengthSummary(for: .codex)
        #expect(out.promptText.contains(codexStrength))
    }

    @Test("currentTask 있으면 task section 포함")
    func includesTask() {
        let task = HarnessTask(title: "리팩터", description: "AppModel 분해", status: .running)
        let out = HandoffPromptBuilder.build(log: [], targetModel: .claude, currentTask: task)
        #expect(out.promptText.contains("현재 작업"))
        #expect(out.promptText.contains("리팩터"))
        #expect(out.promptText.contains("AppModel 분해"))
        #expect(out.promptText.contains("running"))
    }

    @Test("estimatedTokens는 prompt utf8 byte / 4")
    func estimatedTokensReasonable() {
        let log = makeLog(count: 3)
        let out = HandoffPromptBuilder.build(log: log, targetModel: .claude)
        #expect(out.estimatedTokens > 0)
        #expect(out.estimatedTokens == out.promptText.utf8.count / 4)
    }

    @Test("토큰 예산 초과 시 요약 섹션 제거")
    func tokenBudgetTrimsSummary() {
        // 매우 작은 budget으로 — 요약 섹션이 제거돼야 함
        let log = makeLog(count: 20)
        let out = HandoffPromptBuilder.build(
            log: log, targetModel: .claude,
            recentEntriesVerbatim: 5, tokenBudget: 100
        )
        // 요약 섹션이 제거됨 (verbatim과 header만)
        #expect(!out.promptText.contains("이전 대화 요약"))
    }
}

@Suite("HarnessTask — task graph 단위 (ADR-047 Phase 1)")
struct HarnessTaskTests {
    @Test("기본 task는 pending status")
    func defaultStatus() {
        let t = HarnessTask(title: "x", description: "y")
        #expect(t.status == .pending)
        #expect(t.assignedAgent == nil)
        #expect(t.dependencies.isEmpty)
        #expect(t.entryRefs.isEmpty)
    }

    @Test("의존성 모두 completed면 isReady=true")
    func readyWhenDepsCompleted() {
        let dep1 = HarnessTask(title: "1", description: "x", status: .completed)
        let dep2 = HarnessTask(title: "2", description: "y", status: .completed)
        let target = HarnessTask(title: "3", description: "z", dependencies: [dep1.id, dep2.id])
        #expect(target.isReady(allTasks: [dep1, dep2, target]))
    }

    @Test("의존성 중 하나라도 pending이면 isReady=false")
    func notReadyWhenDepPending() {
        let dep = HarnessTask(title: "dep", description: "x", status: .pending)
        let target = HarnessTask(title: "target", description: "y", dependencies: [dep.id])
        #expect(!target.isReady(allTasks: [dep, target]))
    }

    @Test("의존성 없으면 즉시 ready")
    func noDependenciesIsReady() {
        let t = HarnessTask(title: "x", description: "y")
        #expect(t.isReady(allTasks: [t]))
    }

    @Test("이미 running/completed/failed면 isReady=false")
    func nonPendingNotReady() {
        for status in [TaskStatus.running, .completed, .failed] {
            let t = HarnessTask(title: "x", description: "y", status: status)
            #expect(!t.isReady(allTasks: [t]))
        }
    }

    @Test("Codable round-trip 보존")
    func codableRoundTrip() throws {
        let id = UUID()
        let depId = UUID()
        let t = HarnessTask(
            id: id, title: "리팩터", description: "AppModel 분해",
            status: .running, assignedAgent: .claude,
            dependencies: [depId], output: "분석 완료",
            entryRefs: [UUID(), UUID()]
        )
        let data = try JSONEncoder().encode(t)
        let decoded = try JSONDecoder().decode(HarnessTask.self, from: data)
        #expect(decoded == t)
    }
}
