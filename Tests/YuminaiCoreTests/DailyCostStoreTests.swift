import Foundation
import Testing
@testable import YuminaiCore

@Suite("DailyCostStore (ADR-060 Phase 1 + 4)")
struct DailyCostStoreTests {
    private func makeStore() -> DailyCostStore {
        let suite = "yuminai-cost-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return DailyCostStore(defaults: defaults)
    }

    @Test("workspace cost 누적")
    func workspaceCostAccumulate() async {
        let store = makeStore()
        let wsId = UUID()
        await store.addCost(workspaceId: wsId, usd: 0.10)
        await store.addCost(workspaceId: wsId, usd: 0.05)
        let cost = await store.cost(workspaceId: wsId)
        #expect(abs(cost - 0.15) < 0.0001)
    }

    @Test("다른 workspace는 별도 누적")
    func separateWorkspaces() async {
        let store = makeStore()
        let ws1 = UUID()
        let ws2 = UUID()
        await store.addCost(workspaceId: ws1, usd: 1.0)
        await store.addCost(workspaceId: ws2, usd: 2.0)
        #expect(abs((await store.cost(workspaceId: ws1)) - 1.0) < 0.0001)
        #expect(abs((await store.cost(workspaceId: ws2)) - 2.0) < 0.0001)
    }

    @Test("cache trend bucket 누적")
    func cacheTrendAccumulate() async {
        let store = makeStore()
        await store.addCacheSample(read: 1000, uncachedInput: 500)
        await store.addCacheSample(read: 2000, uncachedInput: 100)
        let snap = await store.snapshot()
        // 같은 hour bucket이라 한 record로 누적
        #expect(snap.cacheTrend.count == 1)
        #expect(snap.cacheTrend[0].readTokens == 3000)
        #expect(snap.cacheTrend[0].uncachedInputTokens == 600)
    }

    @Test("CacheHitSample.hitRatio")
    func sampleHitRatio() {
        let s = CacheHitSample(timestamp: Date(), readTokens: 800, uncachedInputTokens: 200)
        #expect(abs(s.hitRatio - 0.8) < 0.0001)
    }

    @Test("CacheHitSample 0 division 안전")
    func sampleZeroDivision() {
        let s = CacheHitSample(timestamp: Date(), readTokens: 0, uncachedInputTokens: 0)
        #expect(s.hitRatio == 0)
    }
}
