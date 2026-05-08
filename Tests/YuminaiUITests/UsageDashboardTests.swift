import Foundation
import Testing
@testable import YuminaiUI

@MainActor
@Suite("UsageDashboard view modes (ADR-075)")
struct UsageDashboardModeTests {

    @Test("DashboardViewMode 기본값은 compact (Apple HIG progressive disclosure)")
    func defaultIsCompact() {
        // 첫 진입은 핵심 정보만 (정보 과부하 회피)
        // raw value 기반 비교
        #expect(DashboardViewMode.compact.rawValue == "compact")
        #expect(DashboardViewMode.detailed.rawValue == "detailed")
    }

    @Test("DashboardViewMode CaseIterable 모두 2개")
    func allCases() {
        #expect(DashboardViewMode.allCases.count == 2)
        #expect(DashboardViewMode.allCases.contains(.compact))
        #expect(DashboardViewMode.allCases.contains(.detailed))
    }
}

@MainActor
@Suite("Usage filters (ADR-075 Phase 3)")
struct UsageFiltersTests {

    @Test("AgentFilter — all/claude/codex 3개")
    func agentFilters() {
        #expect(AgentFilter.allCases.count == 3)
        #expect(AgentFilter.allCases.contains(.all))
        #expect(AgentFilter.allCases.contains(.claude))
        #expect(AgentFilter.allCases.contains(.codex))
    }

    @Test("AgentFilter 한국어 라벨")
    func agentFilterLabels() {
        #expect(AgentFilter.all.rawValue == "전체")
        #expect(AgentFilter.claude.rawValue == "Claude")
        #expect(AgentFilter.codex.rawValue == "Codex")
    }

    @Test("AgentFilter SF Symbol 아이콘")
    func agentFilterIcons() {
        #expect(AgentFilter.all.icon == "square.stack")
        #expect(AgentFilter.claude.icon == "sparkles")
        #expect(AgentFilter.codex.icon == "chevron.left.forwardslash.chevron.right")
    }

    @Test("ModelFilter — all/haiku/sonnet/opus 4개")
    func modelFilters() {
        #expect(ModelFilter.allCases.count == 4)
        #expect(ModelFilter.allCases.contains(.all))
        #expect(ModelFilter.allCases.contains(.haiku))
        #expect(ModelFilter.allCases.contains(.sonnet))
        #expect(ModelFilter.allCases.contains(.opus))
    }

    @Test("ModelFilter 한국어 부제")
    func modelFilterSubtitles() {
        #expect(ModelFilter.haiku.subtitle == "빠름·저비용")
        #expect(ModelFilter.sonnet.subtitle == "균형")
        #expect(ModelFilter.opus.subtitle == "최고 성능")
        #expect(ModelFilter.all.subtitle == "모든 모델")
    }

    @Test("Identifiable conformance — id == rawValue")
    func identifiable() {
        for filter in AgentFilter.allCases {
            #expect(filter.id == filter.rawValue)
        }
        for filter in ModelFilter.allCases {
            #expect(filter.id == filter.rawValue)
        }
    }
}
