import Foundation
import Testing
@testable import YuminaiCore

@Suite("TelegramUsageStore (ADR-062 Phase 6)")
struct TelegramUsageStoreTests {
    private func makeStore() -> TelegramUsageStore {
        let suite = "yuminai-tg-usage-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return TelegramUsageStore(defaults: defaults)
    }

    @Test("recordTurnStart 누적")
    func turnStart() async {
        let store = makeStore()
        await store.recordTurnStart(chatId: 100)
        await store.recordTurnStart(chatId: 100)
        await store.recordTurnStart(chatId: 200)
        let snap = await store.snapshot()
        #expect(snap.chatStats["100"]?.turnCount == 2)
        #expect(snap.chatStats["200"]?.turnCount == 1)
        #expect(snap.totalTurns == 3)
    }

    @Test("recordTurnComplete cost + token 누적")
    func turnComplete() async {
        let store = makeStore()
        await store.recordTurnComplete(chatId: 1, costUSD: 0.01, inputTokens: 100, outputTokens: 50)
        await store.recordTurnComplete(chatId: 1, costUSD: 0.02, inputTokens: 200, outputTokens: 100)
        let snap = await store.snapshot()
        let stats = snap.chatStats["1"]
        #expect(abs((stats?.totalCostUSD ?? 0) - 0.03) < 0.0001)
        #expect(stats?.totalInputTokens == 300)
        #expect(stats?.totalOutputTokens == 150)
    }

    @Test("recordCommand 빈도")
    func commandFreq() async {
        let store = makeStore()
        await store.recordCommand("/decompose")
        await store.recordCommand("/decompose")
        await store.recordCommand("/tasks")
        let snap = await store.snapshot()
        #expect(snap.commandStats["/decompose"] == 2)
        #expect(snap.commandStats["/tasks"] == 1)
        #expect(snap.totalCommands == 3)
    }

    @Test("hourly bucket 누적")
    func hourlyBucket() async {
        let store = makeStore()
        await store.recordTurnStart(chatId: 1)
        await store.recordTurnComplete(chatId: 1, costUSD: 0.01, inputTokens: 100, outputTokens: 50)
        let snap = await store.snapshot()
        #expect(snap.hourlyBuckets.count == 1)
        #expect(snap.hourlyBuckets[0].turnCount == 1)
        #expect(abs(snap.hourlyBuckets[0].costUSD - 0.01) < 0.0001)
    }

    @Test("clear 모두 reset")
    func clearAll() async {
        let store = makeStore()
        await store.recordTurnStart(chatId: 1)
        await store.recordCommand("/test")
        await store.clear()
        let snap = await store.snapshot()
        #expect(snap.chatStats.isEmpty)
        #expect(snap.commandStats.isEmpty)
        #expect(snap.hourlyBuckets.isEmpty)
    }

    @Test("recordCommand: prefix 자동 추가")
    func commandPrefix() async {
        let store = makeStore()
        await store.recordCommand("test")  // no /
        let snap = await store.snapshot()
        #expect(snap.commandStats["/test"] == 1)
    }
}
