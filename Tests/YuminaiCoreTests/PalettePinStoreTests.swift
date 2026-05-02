import Foundation
import Testing
@testable import YuminaiCore

@Suite("PalettePinStore (ADR-052)")
struct PalettePinStoreTests {
    private func makeStore() -> PalettePinStore {
        // unique suite name to avoid test pollution
        let suiteName = "yuminai-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return PalettePinStore(defaults: defaults)
    }

    @Test("togglePin: add then remove")
    func togglePin() async {
        let store = makeStore()
        await store.togglePin("harness.toggle.routing")
        #expect(await store.isPinned("harness.toggle.routing"))
        await store.togglePin("harness.toggle.routing")
        #expect(await store.isPinned("harness.toggle.routing") == false)
    }

    @Test("pin is no-op for empty actionId")
    func emptyActionIdIgnored() async {
        let store = makeStore()
        await store.togglePin("")
        let snap = await store.snapshot()
        #expect(snap.pinnedIds.isEmpty)
    }

    @Test("pin preserves order")
    func pinOrderPreserved() async {
        let store = makeStore()
        await store.pin("a")
        await store.pin("b")
        await store.pin("c")
        let snap = await store.snapshot()
        #expect(snap.pinnedIds == ["a", "b", "c"])
    }

    @Test("recordUse increments counter; recentIds returns ordered")
    func recordUseAndRecent() async {
        let store = makeStore()
        await store.recordUse("a")
        await store.recordUse("b")
        await store.recordUse("a")  // a 더 최근
        let recent = await store.recentIds(limit: 5)
        #expect(recent.first == "a")
    }

    @Test("recentIds caps at PalettePinStore.recentCap")
    func recentCapped() async {
        let store = makeStore()
        for i in 0..<60 {
            await store.recordUse("action.\(i)")
        }
        let snap = await store.snapshot()
        #expect(snap.recentCounters.count <= PalettePinStore.recentCap)
    }

    @Test("clearRecents resets counter")
    func clearRecentsResets() async {
        let store = makeStore()
        await store.recordUse("a")
        await store.recordUse("b")
        await store.clearRecents()
        let snap = await store.snapshot()
        #expect(snap.recentCounters.isEmpty)
        #expect(snap.monotonicCounter == 0)
    }

    @Test("reorderPins keeps only valid IDs and appends missing")
    func reorderPins() async {
        let store = makeStore()
        await store.pin("a")
        await store.pin("b")
        await store.pin("c")
        await store.reorderPins(["c", "a"])  // b missing, will be appended
        let snap = await store.snapshot()
        #expect(snap.pinnedIds == ["c", "a", "b"])
    }
}

@Suite("CmdkScore fuzzy ranking (ADR-052)")
struct CmdkScoreTests {
    @Test("empty query returns 1.0")
    func emptyQuery() {
        #expect(CmdkScore.score(text: "anything", query: "") == 1.0)
    }

    @Test("empty text returns 0.0")
    func emptyText() {
        #expect(CmdkScore.score(text: "", query: "x") == 0.0)
    }

    @Test("prefix match → 1.0")
    func prefixMatch() {
        #expect(CmdkScore.score(text: "command palette", query: "command") == 1.0)
    }

    @Test("word-boundary jump (space) → 0.9")
    func spaceWordJump() {
        #expect(CmdkScore.score(text: "command palette", query: "palette") == 0.9)
    }

    @Test("non-space word boundary (dash/dot) → 0.8")
    func dashWordJump() {
        #expect(CmdkScore.score(text: "harness.toggle.routing", query: "toggle") == 0.8)
    }

    @Test("contains-anywhere → 0.7")
    func containsScore() {
        // "ole" appears mid-word in "tolerance" — no word boundary, no prefix
        let score = CmdkScore.score(text: "tolerance", query: "ole")
        #expect(score == 0.7)
    }

    @Test("subsequence partial match → 0.4")
    func subsequenceMatch() {
        // chars 'c','m','d' present in order in "command" but not contiguously
        let score = CmdkScore.score(text: "command", query: "cmd")
        #expect(score == 0.4)
    }
}

@Suite("CostTracker (ADR-052)")
struct CostTrackerTests {
    @Test("initial buckets are zero")
    @MainActor
    func initialZero() {
        let tracker = CostTracker()
        let snap = tracker.snapshot()
        #expect(snap.main == 0)
        #expect(snap.decomposition == 0)
        #expect(snap.rehearsal == 0)
        #expect(snap.routing == 0)
        #expect(snap.total == 0)
    }

    @Test("add accumulates per bucket independently")
    @MainActor
    func addPerBucket() {
        let tracker = CostTracker()
        tracker.add(.main, usd: 0.10)
        tracker.add(.decomposition, usd: 0.02)
        tracker.add(.main, usd: 0.05)  // 누적
        let snap = tracker.snapshot()
        // floating-point epsilon (Double 누산은 정확하지 않음)
        #expect(abs(snap.main - 0.15) < 0.00001)
        #expect(abs(snap.decomposition - 0.02) < 0.00001)
        #expect(abs(snap.total - 0.17) < 0.00001)
    }

    @Test("reset zero-out specific bucket")
    @MainActor
    func resetSpecific() {
        let tracker = CostTracker()
        tracker.add(.main, usd: 1.0)
        tracker.add(.rehearsal, usd: 0.5)
        tracker.reset(.main)
        let snap = tracker.snapshot()
        #expect(snap.main == 0)
        #expect(snap.rehearsal == 0.5)
    }

    @Test("estimateCostUSD: Sonnet 4.5 pricing")
    func estimatePricing() {
        // 1M input tokens at $3/MTok → $3.00
        let cost = CostTracker.estimateCostUSD(inputTokens: 1_000_000, outputTokens: 0)
        #expect(abs(cost - 3.0) < 0.001)

        // 1M output tokens at $15/MTok → $15.00
        let outCost = CostTracker.estimateCostUSD(inputTokens: 0, outputTokens: 1_000_000)
        #expect(abs(outCost - 15.0) < 0.001)
    }

    // MARK: - ADR-059 Phase 1 cache stats

    @Test("addCacheStats accumulates")
    @MainActor
    func cacheStatsAccumulate() {
        let tracker = CostTracker()
        tracker.addCacheStats(read: 1000, creation: 500, uncachedInput: 200)
        tracker.addCacheStats(read: 2000, creation: 0, uncachedInput: 100)
        #expect(tracker.totalCacheReadTokens == 3000)
        #expect(tracker.totalCacheCreationTokens == 500)
        #expect(tracker.totalUncachedInputTokens == 300)
    }

    @Test("cumulativeCacheHitRatio 정확 계산")
    @MainActor
    func cacheHitRatioCalc() {
        let tracker = CostTracker()
        tracker.addCacheStats(read: 800, creation: 0, uncachedInput: 200)
        // 800 / (800 + 200) = 0.8
        #expect(abs(tracker.cumulativeCacheHitRatio - 0.8) < 0.0001)
    }

    @Test("cacheHitRatio: 누적 0이면 0 반환 (no division by zero)")
    @MainActor
    func cacheHitRatioZero() {
        let tracker = CostTracker()
        #expect(tracker.cumulativeCacheHitRatio == 0)
    }

    @Test("addCacheStats: 음수 input은 0으로 처리")
    @MainActor
    func negativeInputClamped() {
        let tracker = CostTracker()
        tracker.addCacheStats(read: -100, creation: -50, uncachedInput: -10)
        #expect(tracker.totalCacheReadTokens == 0)
        #expect(tracker.totalCacheCreationTokens == 0)
        #expect(tracker.totalUncachedInputTokens == 0)
    }
}
