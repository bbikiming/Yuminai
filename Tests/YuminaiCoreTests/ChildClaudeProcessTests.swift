import Foundation
import Testing
@testable import YuminaiCore

@Suite("ChildProcessPurpose (ADR-053)")
struct ChildProcessPurposeTests {
    @Test("All purposes have non-empty displayLabel")
    func displayLabels() {
        for purpose in ChildProcessPurpose.allCases {
            #expect(!purpose.displayLabel.isEmpty)
        }
    }

    @Test("rawValue stable for persistence")
    func rawValueStable() {
        #expect(ChildProcessPurpose.decomposition.rawValue == "decomposition")
        #expect(ChildProcessPurpose.rehearsal.rawValue == "rehearsal")
        #expect(ChildProcessPurpose.parallel.rawValue == "parallel")
        #expect(ChildProcessPurpose.routing.rawValue == "routing")
    }
}

@Suite("ChildProcessOutput (ADR-053)")
struct ChildProcessOutputTests {
    @Test("constructor preserves all fields")
    func constructor() {
        let out = ChildProcessOutput(
            resultText: "OK",
            inputTokens: 100,
            outputTokens: 50,
            costUSD: 0.0042,
            durationMs: 250,
            exitCode: 0
        )
        #expect(out.resultText == "OK")
        #expect(out.inputTokens == 100)
        #expect(out.outputTokens == 50)
        #expect(out.costUSD == 0.0042)
        #expect(out.durationMs == 250)
        #expect(out.exitCode == 0)
    }

    @Test("Hashable equality on identical fields")
    func hashable() {
        let a = ChildProcessOutput(resultText: "x", inputTokens: 1, outputTokens: 1, costUSD: 0, durationMs: 0, exitCode: 0)
        let b = ChildProcessOutput(resultText: "x", inputTokens: 1, outputTokens: 1, costUSD: 0, durationMs: 0, exitCode: 0)
        #expect(a == b)
    }
}

@Suite("MockChildClaudeProcess (ADR-053)")
struct MockChildClaudeProcessTests {
    @Test("default response is generated when no canned set")
    func defaultResponse() async throws {
        let mock = MockChildClaudeProcess()
        let workspace = Workspace(name: "T", directoryPath: "/tmp")
        let out = try await mock.runOnce(
            prompt: "test prompt",
            in: workspace,
            agent: .claude,
            purpose: .decomposition,
            timeoutSeconds: 30
        )
        #expect(out.resultText.contains("[mock decomposition for"))
        #expect(out.resultText.contains("test prompt"))
        #expect(out.exitCode == 0)
    }

    @Test("setResponse returns canned text")
    func cannedResponse() async throws {
        let mock = MockChildClaudeProcess()
        await mock.setResponse("{\"tasks\": []}", for: .decomposition)
        let workspace = Workspace(name: "T", directoryPath: "/tmp")
        let out = try await mock.runOnce(
            prompt: "ignored",
            in: workspace,
            agent: .claude,
            purpose: .decomposition,
            timeoutSeconds: 30
        )
        #expect(out.resultText == "{\"tasks\": []}")
    }

    @Test("setSimulatedCost: tokens and cost honored")
    func simulatedCost() async throws {
        let mock = MockChildClaudeProcess()
        await mock.setSimulatedCost(usd: 0.123, inputTokens: 500, outputTokens: 200)
        let workspace = Workspace(name: "T", directoryPath: "/tmp")
        let out = try await mock.runOnce(
            prompt: "x",
            in: workspace,
            agent: .codex,
            purpose: .rehearsal,
            timeoutSeconds: 30
        )
        #expect(out.costUSD == 0.123)
        #expect(out.inputTokens == 500)
        #expect(out.outputTokens == 200)
    }

    @Test("different purposes return different default responses")
    func purposeSwitching() async throws {
        let mock = MockChildClaudeProcess()
        let ws = Workspace(name: "T", directoryPath: "/tmp")
        let dOut = try await mock.runOnce(prompt: "x", in: ws, agent: .claude, purpose: .decomposition, timeoutSeconds: 5)
        let rOut = try await mock.runOnce(prompt: "x", in: ws, agent: .claude, purpose: .rehearsal, timeoutSeconds: 5)
        #expect(dOut.resultText.contains("decomposition"))
        #expect(rOut.resultText.contains("rehearsal"))
    }
}

@Suite("CostTracker.parallel bucket (ADR-053)")
struct CostTrackerParallelTests {
    @Test("parallel bucket exists and accumulates")
    @MainActor
    func parallelBucket() {
        let tracker = CostTracker()
        tracker.add(.parallel, usd: 0.05)
        tracker.add(.parallel, usd: 0.03)
        let snap = tracker.snapshot()
        #expect(abs(snap.parallel - 0.08) < 0.00001)
        #expect(abs(snap.total - 0.08) < 0.00001)
    }

    @Test("Bucket.allCases includes parallel")
    func allCasesIncludesParallel() {
        let cases = CostTracker.Bucket.allCases.map(\.rawValue)
        #expect(cases.contains("parallel"))
        #expect(cases.contains("decomposition"))
        #expect(cases.contains("rehearsal"))
        #expect(cases.contains("routing"))
        #expect(cases.contains("main"))
    }

    @Test("formatted snapshot includes all 5 buckets")
    @MainActor
    func formattedFiveBuckets() {
        let tracker = CostTracker()
        tracker.add(.main, usd: 0.10)
        tracker.add(.parallel, usd: 0.05)
        let formatted = tracker.snapshot().formatted()
        #expect(formatted.contains("Main:"))
        #expect(formatted.contains("Decomp:"))
        #expect(formatted.contains("Rehearsal:"))
        #expect(formatted.contains("Routing:"))
        #expect(formatted.contains("Parallel:"))
        #expect(formatted.contains("Total:"))
    }
}
