import Foundation
import Testing
@testable import YuminaiCore

@Suite("RoutingLearningStore (ADR-055 #5)")
struct RoutingLearningStoreTests {
    private func makeStore() -> RoutingLearningStore {
        let suiteName = "yuminai-routing-learn-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return RoutingLearningStore(defaults: defaults)
    }

    @Test("recordCancel: 1회 cancel은 mute 안 함")
    func singleCancelDoesNotMute() async {
        let store = makeStore()
        await store.recordCancel(keyword: "구현")
        #expect(await store.isMuted("구현") == false)
        let snap = await store.snapshot()
        #expect(snap.cancelCounts["구현"] == 1)
    }

    @Test("recordCancel: 임계값(3회) 도달 시 자동 mute")
    func thresholdAutoMutes() async {
        let store = makeStore()
        for _ in 0..<RoutingLearningStore.muteThreshold {
            await store.recordCancel(keyword: "버그")
        }
        #expect(await store.isMuted("버그"))
    }

    @Test("setMuted: 명시적 mute / unmute")
    func explicitMute() async {
        let store = makeStore()
        await store.setMuted("test", muted: true)
        #expect(await store.isMuted("test"))
        await store.setMuted("test", muted: false)
        #expect(await store.isMuted("test") == false)
    }

    @Test("addCustomKeyword: taskKind에 추가")
    func addCustomKeyword() async {
        let store = makeStore()
        await store.addCustomKeyword("스펙", for: "planning")
        let kws = await store.customKeywords(for: "planning")
        #expect(kws == ["스펙"])
    }

    @Test("addCustomKeyword: 중복 무시")
    func duplicateIgnored() async {
        let store = makeStore()
        await store.addCustomKeyword("스펙", for: "planning")
        await store.addCustomKeyword("스펙", for: "planning")
        let kws = await store.customKeywords(for: "planning")
        #expect(kws.count == 1)
    }

    @Test("removeCustomKeyword 정상 동작")
    func removeCustomKeyword() async {
        let store = makeStore()
        await store.addCustomKeyword("a", for: "debugging")
        await store.addCustomKeyword("b", for: "debugging")
        await store.removeCustomKeyword("a", for: "debugging")
        let kws = await store.customKeywords(for: "debugging")
        #expect(kws == ["b"])
    }

    @Test("empty keyword recordCancel 무시")
    func emptyKeywordIgnored() async {
        let store = makeStore()
        await store.recordCancel(keyword: "")
        let snap = await store.snapshot()
        #expect(snap.cancelCounts.isEmpty)
    }
}

@Suite("ModelCapabilityMatrix.classifyTaskKind learning (ADR-055 #5)")
struct ClassifierLearningTests {
    @Test("muted keyword는 매칭 제외")
    func mutedKeywordExcluded() {
        let result = ModelCapabilityMatrix.classifyTaskKind(
            "구현해 줘",
            mutedKeywords: ["구현"],
            customKeywords: [:]
        )
        // "구현"이 muted면 codeGeneration 매칭 X → generalChat fallback
        #expect(result.kind == .generalChat)
        #expect(result.matchedKeyword == nil)
    }

    @Test("custom keyword 우선 매칭")
    func customKeywordPrecedence() {
        let result = ModelCapabilityMatrix.classifyTaskKind(
            "스펙 작성해 줘",
            mutedKeywords: [],
            customKeywords: ["planning": ["스펙"]]
        )
        #expect(result.kind == .planning)
        #expect(result.matchedKeyword == "스펙")
    }

    @Test("base keyword 그대로 (mute X custom X)")
    func baseKeywordWorks() {
        let result = ModelCapabilityMatrix.classifyTaskKind("리뷰 부탁")
        #expect(result.kind == .codeReview)
        #expect(result.matchedKeyword == "리뷰")
    }

    @Test("muted + custom 함께")
    func mutedAndCustom() {
        let result = ModelCapabilityMatrix.classifyTaskKind(
            "디버그 진행",
            mutedKeywords: ["디버그"],
            customKeywords: ["debugging": ["진행"]]
        )
        // "디버그" muted, "진행"은 custom이라 debugging match
        #expect(result.kind == .debugging)
        #expect(result.matchedKeyword == "진행")
    }
}

@Suite("ProjectProfile.systemPromptAppendix (ADR-055 #1)")
struct ProjectProfileAppendixTests {
    @Test("empty profile은 nil 반환")
    func emptyReturnsNil() {
        let profile = ProjectProfile.empty
        #expect(profile.systemPromptAppendix() == nil)
    }

    @Test("최소 정보만 있어도 appendix 반환")
    func minimalAppendix() {
        var profile = ProjectProfile.empty
        profile.platform = .web
        let appendix = profile.systemPromptAppendix()
        #expect(appendix != nil)
        #expect(appendix?.contains("프로젝트 컨텍스트") == true)
    }

    @Test("frameworks가 정렬되어 cache key 안정")
    func frameworksSorted() {
        var p1 = ProjectProfile.empty
        p1.platform = .web
        p1.frameworks = ["React", "Tailwind"]

        var p2 = ProjectProfile.empty
        p2.platform = .web
        p2.frameworks = ["Tailwind", "React"]  // 다른 순서

        // 같은 string이어야 cache hit
        #expect(p1.systemPromptAppendix() == p2.systemPromptAppendix())
    }

    @Test("결정적 ordering (같은 입력 → 같은 출력)")
    func deterministicOrdering() {
        var profile = ProjectProfile.empty
        profile.platform = .web
        profile.primaryLanguage = .typescript
        profile.frameworks = ["Next.js", "Tailwind"]
        profile.hasBackend = true
        profile.backendLanguage = .go
        profile.testFramework = "Jest"
        profile.notes = "edge runtime"

        // 100번 호출해도 같은 결과
        let first = profile.systemPromptAppendix()
        for _ in 0..<10 {
            #expect(profile.systemPromptAppendix() == first)
        }
    }
}
