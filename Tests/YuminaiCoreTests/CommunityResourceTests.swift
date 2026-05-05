import Foundation
import Testing
@testable import YuminaiCore

@Suite("CommunityResource (ADR-109)")
struct CommunityResourceTests {

    // MARK: - Codable round-trip

    @Test("Codable round-trip — 모든 필드 보존")
    func codableRoundTrip() throws {
        let resource = CommunityResource(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            category: .claudeMd,
            displayName: "테스트 자료",
            author: "testAuthor",
            summary: "테스트 요약",
            starsApprox: 1234,
            repoURL: URL(string: "https://github.com/test/repo")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/test/repo/main/CLAUDE.md")!,
            tags: ["tdd", "swift"],
            recommendedFor: [.defined, .exploring]
        )

        let data = try JSONEncoder().encode(resource)
        let decoded = try JSONDecoder().decode(CommunityResource.self, from: data)

        #expect(decoded.id == resource.id)
        #expect(decoded.category == resource.category)
        #expect(decoded.displayName == resource.displayName)
        #expect(decoded.author == resource.author)
        #expect(decoded.summary == resource.summary)
        #expect(decoded.starsApprox == resource.starsApprox)
        #expect(decoded.repoURL == resource.repoURL)
        #expect(decoded.rawURL == resource.rawURL)
        #expect(decoded.tags == resource.tags)
        #expect(decoded.recommendedFor == resource.recommendedFor)
    }

    @Test("Codable round-trip — rawURL nil 보존")
    func codableRoundTripNilRawURL() throws {
        let resource = CommunityResource(
            category: .template,
            displayName: "템플릿",
            author: "author",
            summary: "요약",
            starsApprox: 100,
            repoURL: URL(string: "https://github.com/test/repo")!,
            rawURL: nil
        )
        let data = try JSONEncoder().encode(resource)
        let decoded = try JSONDecoder().decode(CommunityResource.self, from: data)
        #expect(decoded.rawURL == nil)
    }

    @Test("Codable round-trip — recommendedFor 빈 배열 보존")
    func codableRoundTripEmptyRecommendedFor() throws {
        let resource = CommunityResource(
            category: .skill,
            displayName: "스킬",
            author: "author",
            summary: "요약",
            starsApprox: 50,
            repoURL: URL(string: "https://github.com/test/repo")!,
            recommendedFor: []
        )
        let data = try JSONEncoder().encode(resource)
        let decoded = try JSONDecoder().decode(CommunityResource.self, from: data)
        #expect(decoded.recommendedFor.isEmpty)
    }

    // MARK: - Category displayName

    @Test("Category.claudeMd — displayName 정의됨")
    func claudeMdDisplayName() {
        #expect(!CommunityResource.Category.claudeMd.displayName.isEmpty)
        #expect(CommunityResource.Category.claudeMd.displayName == "CLAUDE.md")
    }

    @Test("Category.skill — displayName 정의됨")
    func skillDisplayName() {
        #expect(!CommunityResource.Category.skill.displayName.isEmpty)
        #expect(CommunityResource.Category.skill.displayName == "Claude Skill")
    }

    @Test("Category.template — displayName 정의됨")
    func templateDisplayName() {
        #expect(!CommunityResource.Category.template.displayName.isEmpty)
        #expect(CommunityResource.Category.template.displayName == "템플릿")
    }

    @Test("모든 Category에 icon 정의됨")
    func allCategoryIconsDefined() {
        for category in CommunityResource.Category.allCases {
            #expect(!category.icon.isEmpty)
        }
    }

    @Test("Category.id == rawValue")
    func categoryIdEqualsRawValue() {
        for category in CommunityResource.Category.allCases {
            #expect(category.id == category.rawValue)
        }
    }

    // MARK: - CommunityCatalog

    @Test("CommunityCatalog.curated 비어있지 않음")
    func curatedNotEmpty() {
        #expect(!CommunityCatalog.curated.isEmpty)
    }

    @Test("CommunityCatalog.curated — 5개 이상 자료 포함")
    func curatedHasFivePlus() {
        #expect(CommunityCatalog.curated.count >= 5)
    }

    @Test("CommunityCatalog.curated — 모든 항목에 displayName 비어있지 않음")
    func allItemsHaveDisplayName() {
        for resource in CommunityCatalog.curated {
            #expect(!resource.displayName.isEmpty, "id: \(resource.id)")
        }
    }

    @Test("CommunityCatalog.curated — 모든 항목에 author 비어있지 않음")
    func allItemsHaveAuthor() {
        for resource in CommunityCatalog.curated {
            #expect(!resource.author.isEmpty, "id: \(resource.id)")
        }
    }

    @Test("CommunityCatalog.curated — 모든 항목에 summary 비어있지 않음")
    func allItemsHaveSummary() {
        for resource in CommunityCatalog.curated {
            #expect(!resource.summary.isEmpty, "id: \(resource.id)")
        }
    }

    @Test("CommunityCatalog.curated — repoURL 유효한 https URL")
    func allItemsHaveValidRepoURL() {
        for resource in CommunityCatalog.curated {
            #expect(resource.repoURL.scheme == "https", "id: \(resource.id)")
            #expect(resource.repoURL.host != nil, "id: \(resource.id)")
        }
    }

    @Test("CommunityCatalog.curated — rawURL이 있으면 https URL")
    func rawURLIsHttpsWhenPresent() {
        for resource in CommunityCatalog.curated {
            if let rawURL = resource.rawURL {
                #expect(rawURL.scheme == "https", "id: \(resource.id)")
                #expect(rawURL.host != nil, "id: \(resource.id)")
            }
        }
    }

    @Test("CommunityCatalog.curated — 모든 항목 id 고유")
    func allItemsHaveUniqueIds() {
        let ids = CommunityCatalog.curated.map { $0.id }
        let uniqueIds = Set(ids)
        #expect(ids.count == uniqueIds.count)
    }

    @Test("CommunityCatalog.curated — starsApprox 0 이상")
    func allItemsHaveNonNegativeStars() {
        for resource in CommunityCatalog.curated {
            #expect(resource.starsApprox >= 0, "id: \(resource.id)")
        }
    }

    // MARK: - Category 필터링

    @Test("CommunityCatalog.resources(for:category) — claudeMd 필터")
    func filterByClaudeMd() {
        let items = CommunityCatalog.resources(for: .claudeMd)
        #expect(!items.isEmpty)
        for item in items {
            #expect(item.category == .claudeMd)
        }
    }

    @Test("CommunityCatalog.resources(for:category) — skill 필터")
    func filterBySkill() {
        let items = CommunityCatalog.resources(for: .skill)
        #expect(!items.isEmpty)
        for item in items {
            #expect(item.category == .skill)
        }
    }

    @Test("CommunityCatalog.resources(for:goalStatus) — defined 필터 반환값 비어있지 않음")
    func filterByGoalStatusDefined() {
        let items = CommunityCatalog.resources(for: .defined)
        #expect(!items.isEmpty)
    }

    @Test("CommunityCatalog.resources(for:goalStatus) — undecided 필터 반환값 비어있지 않음")
    func filterByGoalStatusUndecided() {
        let items = CommunityCatalog.resources(for: .undecided)
        #expect(!items.isEmpty)
    }

    // MARK: - starsDisplay 헬퍼

    @Test("starsDisplay — 999 이하는 숫자 그대로")
    func starsDisplayBelowThousand() {
        let resource = CommunityResource(
            category: .claudeMd,
            displayName: "Test",
            author: "author",
            summary: "summary",
            starsApprox: 999,
            repoURL: URL(string: "https://github.com/test/repo")!
        )
        #expect(resource.starsDisplay == "999")
    }

    @Test("starsDisplay — 1000은 1k")
    func starsDisplayThousand() {
        let resource = CommunityResource(
            category: .claudeMd,
            displayName: "Test",
            author: "author",
            summary: "summary",
            starsApprox: 1000,
            repoURL: URL(string: "https://github.com/test/repo")!
        )
        #expect(resource.starsDisplay == "1k")
    }

    @Test("starsDisplay — 1200은 1.2k")
    func starsDisplayTwelveHundred() {
        let resource = CommunityResource(
            category: .claudeMd,
            displayName: "Test",
            author: "author",
            summary: "summary",
            starsApprox: 1200,
            repoURL: URL(string: "https://github.com/test/repo")!
        )
        #expect(resource.starsDisplay == "1.2k")
    }

    @Test("starsDisplay — 12000은 12k")
    func starsDisplayTwelveThousand() {
        let resource = CommunityResource(
            category: .claudeMd,
            displayName: "Test",
            author: "author",
            summary: "summary",
            starsApprox: 12000,
            repoURL: URL(string: "https://github.com/test/repo")!
        )
        #expect(resource.starsDisplay == "12k")
    }

    // MARK: - Hashable + Identifiable

    @Test("같은 id면 Hashable Set에서 하나로 처리")
    func hashableSet() {
        let id = UUID()
        let a = CommunityResource(id: id, category: .claudeMd, displayName: "A", author: "x", summary: "s", starsApprox: 10, repoURL: URL(string: "https://github.com/a/b")!)
        let b = CommunityResource(id: id, category: .skill, displayName: "B", author: "y", summary: "t", starsApprox: 20, repoURL: URL(string: "https://github.com/c/d")!)
        let set = Set([a, b])
        #expect(set.count == 1)
    }

    @Test("id는 Identifiable 요건 충족")
    func identifiable() {
        let resource = CommunityResource(
            category: .skill,
            displayName: "Test",
            author: "author",
            summary: "summary",
            starsApprox: 100,
            repoURL: URL(string: "https://github.com/test/repo")!
        )
        #expect(resource.id == resource.id)
    }
}
