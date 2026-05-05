import Foundation
import Testing
@testable import YuminaiCore

@Suite("CommunityResource (ADR-112)")
struct CommunityResourceTests {

    // MARK: - Codable round-trip (기존 호환)

    @Test("Codable round-trip — 모든 기존 필드 보존")
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

    // MARK: - ADR-112 신규 필드 Codable round-trip

    @Test("Codable round-trip — Language.korean 보존")
    func codableRoundTripLanguageKorean() throws {
        let resource = CommunityResource(
            category: .claudeMd,
            displayName: "한국어 자료",
            author: "kr-author",
            summary: "한국어 요약",
            starsApprox: 500,
            repoURL: URL(string: "https://github.com/test/repo")!,
            language: .korean
        )
        let data = try JSONEncoder().encode(resource)
        let decoded = try JSONDecoder().decode(CommunityResource.self, from: data)
        #expect(decoded.language == .korean)
    }

    @Test("Codable round-trip — Language.multilingual 보존")
    func codableRoundTripLanguageMultilingual() throws {
        let resource = CommunityResource(
            category: .workflow,
            displayName: "다국어 자료",
            author: "author",
            summary: "다국어 요약",
            starsApprox: 200,
            repoURL: URL(string: "https://github.com/test/repo")!,
            language: .multilingual
        )
        let data = try JSONEncoder().encode(resource)
        let decoded = try JSONDecoder().decode(CommunityResource.self, from: data)
        #expect(decoded.language == .multilingual)
    }

    @Test("Codable round-trip — officialBadge true 보존")
    func codableRoundTripOfficialBadge() throws {
        let resource = CommunityResource(
            category: .mcp,
            displayName: "공식 자료",
            author: "anthropics",
            summary: "요약",
            starsApprox: 10000,
            repoURL: URL(string: "https://github.com/test/repo")!,
            officialBadge: true,
            recommendedRank: 95
        )
        let data = try JSONEncoder().encode(resource)
        let decoded = try JSONDecoder().decode(CommunityResource.self, from: data)
        #expect(decoded.officialBadge == true)
        #expect(decoded.recommendedRank == 95)
    }

    @Test("Codable round-trip — useCase nil 보존")
    func codableRoundTripNilUseCase() throws {
        let resource = CommunityResource(
            category: .styleGuide,
            displayName: "스타일 가이드",
            author: "author",
            summary: "요약",
            starsApprox: 100,
            repoURL: URL(string: "https://github.com/test/repo")!,
            useCase: nil
        )
        let data = try JSONEncoder().encode(resource)
        let decoded = try JSONDecoder().decode(CommunityResource.self, from: data)
        #expect(decoded.useCase == nil)
    }

    @Test("Codable round-trip — useCase 문자열 보존")
    func codableRoundTripUseCase() throws {
        let resource = CommunityResource(
            category: .architecture,
            displayName: "설계 자료",
            author: "author",
            summary: "요약",
            starsApprox: 100,
            repoURL: URL(string: "https://github.com/test/repo")!,
            useCase: "마이크로서비스 설계 시 참고"
        )
        let data = try JSONEncoder().encode(resource)
        let decoded = try JSONDecoder().decode(CommunityResource.self, from: data)
        #expect(decoded.useCase == "마이크로서비스 설계 시 참고")
    }

    // MARK: - 하위 호환성 (ADR-112 신규 필드 없는 구 JSON decode)

    @Test("하위 호환 — 신규 필드 없는 구 JSON도 디코딩 성공")
    func backwardCompatOldJSON() throws {
        // ADR-112 이전 JSON (language, useCase, officialBadge, recommendedRank 없음)
        let oldJSON = """
        {
          "id": "00000000-0000-0000-0000-AABBCCDDEEFF",
          "category": "claudeMd",
          "displayName": "구버전 자료",
          "author": "old-author",
          "summary": "구버전 요약",
          "starsApprox": 100,
          "repoURL": "https://github.com/test/repo",
          "tags": ["old"],
          "recommendedFor": ["defined"]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CommunityResource.self, from: oldJSON)
        #expect(decoded.displayName == "구버전 자료")
        // 신규 필드는 기본값으로 채워져야 함
        #expect(decoded.language == .english)
        #expect(decoded.officialBadge == false)
        #expect(decoded.recommendedRank == 50)
        #expect(decoded.useCase == nil)
    }

    // MARK: - Category displayName (기존 + 신규)

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

    @Test("ADR-112 신규 — Category.styleGuide displayName 정의됨")
    func styleGuideDisplayName() {
        #expect(!CommunityResource.Category.styleGuide.displayName.isEmpty)
        #expect(CommunityResource.Category.styleGuide.displayName == "디자인 가이드")
    }

    @Test("ADR-112 신규 — Category.workflow displayName 정의됨")
    func workflowDisplayName() {
        #expect(!CommunityResource.Category.workflow.displayName.isEmpty)
        #expect(CommunityResource.Category.workflow.displayName == "워크플로우")
    }

    @Test("ADR-112 신규 — Category.architecture displayName 정의됨")
    func architectureDisplayName() {
        #expect(!CommunityResource.Category.architecture.displayName.isEmpty)
        #expect(CommunityResource.Category.architecture.displayName == "시스템 설계")
    }

    @Test("ADR-112 신규 — Category.promptPattern displayName 정의됨")
    func promptPatternDisplayName() {
        #expect(!CommunityResource.Category.promptPattern.displayName.isEmpty)
        #expect(CommunityResource.Category.promptPattern.displayName == "프롬프트 패턴")
    }

    @Test("ADR-112 신규 — Category.rules displayName 정의됨")
    func rulesDisplayName() {
        #expect(!CommunityResource.Category.rules.displayName.isEmpty)
        #expect(CommunityResource.Category.rules.displayName == "에디터 규칙")
    }

    @Test("ADR-112 신규 — Category.mcp displayName 정의됨")
    func mcpDisplayName() {
        #expect(!CommunityResource.Category.mcp.displayName.isEmpty)
        #expect(CommunityResource.Category.mcp.displayName == "MCP 서버")
    }

    @Test("모든 Category에 icon 정의됨 (9개 카테고리)")
    func allCategoryIconsDefined() {
        for category in CommunityResource.Category.allCases {
            #expect(!category.icon.isEmpty, "icon 없음: \(category.rawValue)")
        }
    }

    @Test("ADR-112 — Category 9개 케이스 확인")
    func categoryHasNineCases() {
        // ADR-113: 6개 신규 카테고리 추가 → 15개
        #expect(CommunityResource.Category.allCases.count == 15)
    }

    @Test("Category.id == rawValue")
    func categoryIdEqualsRawValue() {
        for category in CommunityResource.Category.allCases {
            #expect(category.id == category.rawValue)
        }
    }

    @Test("모든 Category에 tintColorName 정의됨")
    func allCategoryTintColorsDefined() {
        for category in CommunityResource.Category.allCases {
            #expect(!category.tintColorName.isEmpty, "tintColor 없음: \(category.rawValue)")
        }
    }

    @Test("모든 Category에 categoryDescription 정의됨")
    func allCategoryDescriptionsDefined() {
        for category in CommunityResource.Category.allCases {
            #expect(!category.categoryDescription.isEmpty, "description 없음: \(category.rawValue)")
        }
    }

    @Test("Category.categoryRank — 모든 카테고리 0-14 범위 (ADR-113: 15개)")
    func categoryRankRange() {
        for category in CommunityResource.Category.allCases {
            #expect(category.categoryRank >= 0 && category.categoryRank <= 14, "rank 범위 초과: \(category.rawValue)")
        }
    }

    // MARK: - Language enum

    @Test("Language.allCases — 3개 케이스")
    func languageHasThreeCases() {
        #expect(CommunityResource.Language.allCases.count == 3)
    }

    @Test("Language.korean.flag == 🇰🇷")
    func koreanFlag() {
        #expect(CommunityResource.Language.korean.flag == "🇰🇷")
    }

    @Test("Language.english.flag == 🇬🇧")
    func englishFlag() {
        #expect(CommunityResource.Language.english.flag == "🇬🇧")
    }

    @Test("Language.multilingual.flag == 🌐")
    func multilingualFlag() {
        #expect(CommunityResource.Language.multilingual.flag == "🌐")
    }

    @Test("Language Codable round-trip — 모든 케이스")
    func languageCodableAllCases() throws {
        for lang in CommunityResource.Language.allCases {
            let encoded = try JSONEncoder().encode(lang)
            let decoded = try JSONDecoder().decode(CommunityResource.Language.self, from: encoded)
            #expect(decoded == lang)
        }
    }

    // MARK: - CommunityCatalog 기본 검증

    @Test("CommunityCatalog.curated 비어있지 않음")
    func curatedNotEmpty() {
        #expect(!CommunityCatalog.curated.isEmpty)
    }

    @Test("ADR-112 — CommunityCatalog.curated 25개 이상")
    func curatedHasTwentyFivePlus() {
        #expect(CommunityCatalog.curated.count >= 25)
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

    @Test("CommunityCatalog.curated — recommendedRank 0-100 범위")
    func allItemsHaveValidRecommendedRank() {
        for resource in CommunityCatalog.curated {
            #expect(resource.recommendedRank >= 0 && resource.recommendedRank <= 100, "id: \(resource.id)")
        }
    }

    // MARK: - ADR-112 카테고리 분포 검증

    @Test("ADR-112 — claudeMd 카테고리 3개 이상")
    func claudeMdResourcesThreePlus() {
        let items = CommunityCatalog.resources(for: .claudeMd)
        #expect(items.count >= 3)
    }

    @Test("ADR-112 — mcp 카테고리 최소 1개")
    func mcpResourcesOnePlus() {
        let items = CommunityCatalog.resources(for: .mcp)
        #expect(items.count >= 1)
    }

    @Test("ADR-112 — workflow 카테고리 최소 1개")
    func workflowResourcesOnePlus() {
        let items = CommunityCatalog.resources(for: .workflow)
        #expect(items.count >= 1)
    }

    @Test("ADR-112 — architecture 카테고리 최소 1개")
    func architectureResourcesOnePlus() {
        let items = CommunityCatalog.resources(for: .architecture)
        #expect(items.count >= 1)
    }

    @Test("ADR-112 — promptPattern 카테고리 최소 1개")
    func promptPatternResourcesOnePlus() {
        let items = CommunityCatalog.resources(for: .promptPattern)
        #expect(items.count >= 1)
    }

    @Test("ADR-112 — rules 카테고리 최소 1개")
    func rulesResourcesOnePlus() {
        let items = CommunityCatalog.resources(for: .rules)
        #expect(items.count >= 1)
    }

    @Test("ADR-112 — styleGuide 카테고리 최소 1개")
    func styleGuideResourcesOnePlus() {
        let items = CommunityCatalog.resources(for: .styleGuide)
        #expect(items.count >= 1)
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

    @Test("CommunityCatalog.resources(for:category) — mcp 필터")
    func filterByMcp() {
        let items = CommunityCatalog.resources(for: .mcp)
        #expect(!items.isEmpty)
        for item in items {
            #expect(item.category == .mcp)
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

    // MARK: - ADR-112 공식 배지 + 언어 필터

    @Test("ADR-112 — officialResources 최소 1개 (Anthropic 공식)")
    func officialResourcesNotEmpty() {
        let officials = CommunityCatalog.officialResources
        #expect(!officials.isEmpty)
        for r in officials {
            #expect(r.officialBadge == true)
        }
    }

    @Test("ADR-112 — 언어별 필터 — english 자료 있음")
    func languageFilterEnglish() {
        let items = CommunityCatalog.resources(for: .english)
        #expect(!items.isEmpty)
    }

    @Test("ADR-112 — sorted(by:) — recommendedRank 내림차순")
    func sortedByRecommendedRank() {
        let items = CommunityCatalog.sorted(by: CommunityCatalog.curated)
        for i in 0..<(items.count - 1) {
            #expect(items[i].recommendedRank >= items[i + 1].recommendedRank)
        }
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

    // MARK: - 초기화 기본값 검증 (ADR-112)

    @Test("ADR-112 — 기본값: language = .english")
    func defaultLanguageIsEnglish() {
        let resource = CommunityResource(
            category: .claudeMd,
            displayName: "Test",
            author: "author",
            summary: "summary",
            starsApprox: 100,
            repoURL: URL(string: "https://github.com/test/repo")!
        )
        #expect(resource.language == .english)
    }

    @Test("ADR-112 — 기본값: officialBadge = false")
    func defaultOfficialBadgeIsFalse() {
        let resource = CommunityResource(
            category: .claudeMd,
            displayName: "Test",
            author: "author",
            summary: "summary",
            starsApprox: 100,
            repoURL: URL(string: "https://github.com/test/repo")!
        )
        #expect(resource.officialBadge == false)
    }

    @Test("ADR-112 — 기본값: recommendedRank = 50")
    func defaultRecommendedRankIsFifty() {
        let resource = CommunityResource(
            category: .claudeMd,
            displayName: "Test",
            author: "author",
            summary: "summary",
            starsApprox: 100,
            repoURL: URL(string: "https://github.com/test/repo")!
        )
        #expect(resource.recommendedRank == 50)
    }

    @Test("ADR-112 — 기본값: useCase = nil")
    func defaultUseCaseIsNil() {
        let resource = CommunityResource(
            category: .claudeMd,
            displayName: "Test",
            author: "author",
            summary: "summary",
            starsApprox: 100,
            repoURL: URL(string: "https://github.com/test/repo")!
        )
        #expect(resource.useCase == nil)
    }

    // MARK: - ADR-113 신규 카테고리 검증

    @Test("ADR-113 — Category.webFramework displayName 정의됨")
    func webFrameworkDisplayName() {
        #expect(!CommunityResource.Category.webFramework.displayName.isEmpty)
        #expect(CommunityResource.Category.webFramework.displayName == "웹 프레임워크")
    }

    @Test("ADR-113 — Category.mobileFramework displayName 정의됨")
    func mobileFrameworkDisplayName() {
        #expect(!CommunityResource.Category.mobileFramework.displayName.isEmpty)
        #expect(CommunityResource.Category.mobileFramework.displayName == "모바일 프레임워크")
    }

    @Test("ADR-113 — Category.graphics3D displayName 정의됨")
    func graphics3DDisplayName() {
        #expect(!CommunityResource.Category.graphics3D.displayName.isEmpty)
        #expect(CommunityResource.Category.graphics3D.displayName == "3D 그래픽스")
    }

    @Test("ADR-113 — Category.backend displayName 정의됨")
    func backendDisplayName() {
        #expect(!CommunityResource.Category.backend.displayName.isEmpty)
        #expect(CommunityResource.Category.backend.displayName == "백엔드")
    }

    @Test("ADR-113 — Category.database displayName 정의됨")
    func databaseDisplayName() {
        #expect(!CommunityResource.Category.database.displayName.isEmpty)
        #expect(CommunityResource.Category.database.displayName == "데이터베이스")
    }

    @Test("ADR-113 — Category.devops displayName 정의됨")
    func devopsDisplayName() {
        #expect(!CommunityResource.Category.devops.displayName.isEmpty)
        #expect(CommunityResource.Category.devops.displayName == "DevOps")
    }

    @Test("ADR-113 — 신규 카테고리 모두 icon 비어있지 않음")
    func newCategoryIconsDefined() {
        let newCategories: [CommunityResource.Category] = [
            .webFramework, .mobileFramework, .graphics3D, .backend, .database, .devops
        ]
        for cat in newCategories {
            #expect(!cat.icon.isEmpty, "icon 없음: \(cat.rawValue)")
        }
    }

    @Test("ADR-113 — 신규 카테고리 categoryDescription 비어있지 않음")
    func newCategoryDescriptionsDefined() {
        let newCategories: [CommunityResource.Category] = [
            .webFramework, .mobileFramework, .graphics3D, .backend, .database, .devops
        ]
        for cat in newCategories {
            #expect(!cat.categoryDescription.isEmpty, "description 없음: \(cat.rawValue)")
        }
    }

    @Test("ADR-113 — CommunityCatalog.curated 60개 이상")
    func curatedHasSixtyPlus() {
        #expect(CommunityCatalog.curated.count >= 60)
    }

    @Test("ADR-113 — webFramework 카테고리 최소 5개")
    func webFrameworkResourcesFivePlus() {
        let items = CommunityCatalog.resources(for: .webFramework)
        #expect(items.count >= 5)
    }

    @Test("ADR-113 — mobileFramework 카테고리 최소 3개")
    func mobileFrameworkResourcesThreePlus() {
        let items = CommunityCatalog.resources(for: .mobileFramework)
        #expect(items.count >= 3)
    }

    @Test("ADR-113 — graphics3D 카테고리 최소 3개")
    func graphics3DResourcesThreePlus() {
        let items = CommunityCatalog.resources(for: .graphics3D)
        #expect(items.count >= 3)
    }

    @Test("ADR-113 — backend 카테고리 최소 3개")
    func backendResourcesThreePlus() {
        let items = CommunityCatalog.resources(for: .backend)
        #expect(items.count >= 3)
    }

    @Test("ADR-113 — database 카테고리 최소 3개")
    func databaseResourcesThreePlus() {
        let items = CommunityCatalog.resources(for: .database)
        #expect(items.count >= 3)
    }

    @Test("ADR-113 — devops 카테고리 최소 3개")
    func devopsResourcesThreePlus() {
        let items = CommunityCatalog.resources(for: .devops)
        #expect(items.count >= 3)
    }

    @Test("ADR-113 — 신규 카테고리 자료 모두 https repoURL 보유")
    func newCategoryResourcesHaveHttpsRepoURL() {
        let newCategories: [CommunityResource.Category] = [
            .webFramework, .mobileFramework, .graphics3D, .backend, .database, .devops
        ]
        for cat in newCategories {
            for resource in CommunityCatalog.resources(for: cat) {
                #expect(resource.repoURL.scheme == "https", "id: \(resource.id)")
            }
        }
    }

    @Test("ADR-113 — 신규 카테고리 rawURL은 https이거나 nil")
    func newCategoryRawURLIsHttpsOrNil() {
        let newCategories: [CommunityResource.Category] = [
            .webFramework, .mobileFramework, .graphics3D, .backend, .database, .devops
        ]
        for cat in newCategories {
            for resource in CommunityCatalog.resources(for: cat) {
                if let rawURL = resource.rawURL {
                    #expect(rawURL.scheme == "https", "rawURL scheme 오류: \(resource.id)")
                }
            }
        }
    }
}
