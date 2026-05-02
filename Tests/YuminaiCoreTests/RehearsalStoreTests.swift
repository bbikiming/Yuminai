import Foundation
import Testing
@testable import YuminaiCore

@Suite("TaskSnapshot/RehearsalRun (ADR-052)")
struct RehearsalTypesTests {
    @Test("TaskSnapshot Codable round-trip")
    func snapshotRoundTrip() throws {
        // ISO8601 fractional precision 손실 방지 — clean integer seconds boundary
        let cleanDate = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let snapshot = TaskSnapshot(
            taskId: UUID(),
            createdAt: cleanDate,
            taskTitle: "Refactor",
            taskDescription: "Refactor core",
            originalAgentRaw: "claude",
            originalSettings: TaskSnapshot.SettingsSummary(
                modelLabel: "Sonnet 4.5",
                mode: "medium",
                permissionMode: "default"
            ),
            projectContextSummary: "Swift macOS",
            entries: [],
            originalOutput: "Done"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TaskSnapshot.self, from: data)
        #expect(decoded == snapshot)
    }

    @Test("RehearsalRun status transitions")
    func runStatusTransitions() {
        var run = RehearsalRun(
            snapshotId: UUID(),
            taskId: UUID(),
            replayAgentRaw: "codex",
            status: .pending,
            estimatedCostUSD: 0.01
        )
        #expect(run.status == .pending)
        run.status = .running
        #expect(run.status == .running)
        run.status = .completed
        run.completedAt = Date()
        run.resultText = "Result"
        #expect(run.status == .completed)
        #expect(run.resultText == "Result")
    }

    @Test("All RehearsalRun.Status cases distinct")
    func statusCases() {
        let cases: [RehearsalRun.Status] = [.pending, .running, .completed, .failed, .cancelled]
        let unique = Set(cases.map(\.rawValue))
        #expect(unique.count == cases.count)
    }
}

@Suite("RehearsalStore (ADR-052)")
struct RehearsalStoreTests {
    private func makeTempStore() -> (RehearsalStore, URL) {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("yuminai-rehearsal-test-\(UUID().uuidString)", isDirectory: true)
        let store = RehearsalStore(baseURL: temp)
        return (store, temp)
    }

    @Test("saveSnapshot then loadSnapshot returns same")
    func saveLoadSnapshot() async throws {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let taskId = UUID()
        let snapshot = TaskSnapshot(
            taskId: taskId,
            taskTitle: "T",
            taskDescription: "D",
            originalAgentRaw: "claude",
            originalSettings: TaskSnapshot.SettingsSummary(
                modelLabel: "S", mode: "m", permissionMode: "p"
            ),
            projectContextSummary: "ctx",
            entries: [],
            originalOutput: nil
        )
        await store.saveSnapshot(snapshot)
        let loaded = await store.loadSnapshot(taskId: taskId)
        #expect(loaded?.taskTitle == "T")
    }

    @Test("saveRun then loadRuns returns array")
    func saveLoadRuns() async {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let taskId = UUID()
        let run = RehearsalRun(
            snapshotId: UUID(),
            taskId: taskId,
            replayAgentRaw: "codex",
            status: .pending,
            estimatedCostUSD: 0.001
        )
        await store.saveRun(run)
        let loaded = await store.loadRuns(taskId: taskId)
        #expect(loaded.count == 1)
        #expect(loaded.first?.replayAgentRaw == "codex")
    }

    @Test("multiple runs for same task")
    func multipleRunsSameTask() async {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let taskId = UUID()
        for kind in ["claude", "codex"] {
            let run = RehearsalRun(
                snapshotId: UUID(),
                taskId: taskId,
                replayAgentRaw: kind,
                status: .completed,
                estimatedCostUSD: 0.01
            )
            await store.saveRun(run)
        }
        let loaded = await store.loadRuns(taskId: taskId)
        #expect(loaded.count == 2)
    }
}
