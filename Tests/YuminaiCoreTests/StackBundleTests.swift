import Foundation
import Testing
@testable import YuminaiCore

@Suite("StackBundle (ADR-113)")
struct StackBundleTests {

    // MARK: - BundleCategory 기본 검증

    @Test("BundleCategory.allCases — 6개 케이스")
    func bundleCategoryHasSixCases() {
        #expect(StackBundle.BundleCategory.allCases.count == 6)
    }

    @Test("모든 BundleCategory에 displayName 비어있지 않음")
    func allBundleCategoryDisplayNamesDefined() {
        for cat in StackBundle.BundleCategory.allCases {
            #expect(!cat.displayName.isEmpty, "displayName 없음: \(cat.rawValue)")
        }
    }

    @Test("모든 BundleCategory에 icon 비어있지 않음")
    func allBundleCategoryIconsDefined() {
        for cat in StackBundle.BundleCategory.allCases {
            #expect(!cat.icon.isEmpty, "icon 없음: \(cat.rawValue)")
        }
    }

    @Test("모든 BundleCategory에 tintColorName 비어있지 않음")
    func allBundleCategoryTintColorsDefined() {
        for cat in StackBundle.BundleCategory.allCases {
            #expect(!cat.tintColorName.isEmpty, "tintColorName 없음: \(cat.rawValue)")
        }
    }

    @Test("BundleCategory Codable round-trip — 모든 케이스")
    func bundleCategoryCodableAllCases() throws {
        for cat in StackBundle.BundleCategory.allCases {
            let encoded = try JSONEncoder().encode(cat)
            let decoded = try JSONDecoder().decode(StackBundle.BundleCategory.self, from: encoded)
            #expect(decoded == cat)
        }
    }

    @Test("BundleCategory.id == rawValue")
    func bundleCategoryIdEqualsRawValue() {
        for cat in StackBundle.BundleCategory.allCases {
            #expect(cat.id == cat.rawValue)
        }
    }

    // MARK: - StackBundle 초기화 + Codable

    @Test("StackBundle 기본 초기화")
    func stackBundleBasicInit() {
        let bundle = StackBundle(
            displayName: "테스트 번들",
            summary: "테스트 요약",
            category: .fullstackWeb,
            stackTags: ["react", "tailwind"],
            resourceIds: [],
            recommendedFor: "테스트 개발자",
            estimatedSetupTime: "30분"
        )
        #expect(bundle.displayName == "테스트 번들")
        #expect(bundle.category == .fullstackWeb)
        #expect(bundle.stackTags == ["react", "tailwind"])
        #expect(bundle.officialBadge == false)
    }

    @Test("StackBundle Codable round-trip")
    func stackBundleCodableRoundTrip() throws {
        let id = UUID()
        let bundle = StackBundle(
            id: id,
            displayName: "Next.js 번들",
            summary: "Next.js + Tailwind",
            category: .fullstackWeb,
            stackTags: ["nextjs", "tailwind"],
            resourceIds: [UUID()],
            recommendedFor: "풀스택 개발자",
            estimatedSetupTime: "1시간",
            officialBadge: true
        )

        let data = try JSONEncoder().encode(bundle)
        let decoded = try JSONDecoder().decode(StackBundle.self, from: data)

        #expect(decoded.id == bundle.id)
        #expect(decoded.displayName == bundle.displayName)
        #expect(decoded.summary == bundle.summary)
        #expect(decoded.category == bundle.category)
        #expect(decoded.stackTags == bundle.stackTags)
        #expect(decoded.resourceIds == bundle.resourceIds)
        #expect(decoded.recommendedFor == bundle.recommendedFor)
        #expect(decoded.estimatedSetupTime == bundle.estimatedSetupTime)
        #expect(decoded.officialBadge == true)
    }

    @Test("StackBundle Hashable — 같은 id면 Set에서 하나")
    func stackBundleHashableSet() {
        let id = UUID()
        let a = StackBundle(
            id: id, displayName: "A", summary: "s", category: .fullstackWeb,
            stackTags: [], resourceIds: [], recommendedFor: "x", estimatedSetupTime: "1h"
        )
        let b = StackBundle(
            id: id, displayName: "B", summary: "t", category: .mobileApp,
            stackTags: [], resourceIds: [], recommendedFor: "y", estimatedSetupTime: "2h"
        )
        let set = Set([a, b])
        #expect(set.count == 1)
    }

    @Test("StackBundle.resourceCountDisplay — 자료 수 표시")
    func resourceCountDisplay() {
        let bundle = StackBundle(
            displayName: "번들", summary: "요약", category: .aiApp,
            stackTags: [], resourceIds: [UUID(), UUID(), UUID()],
            recommendedFor: "개발자", estimatedSetupTime: "1시간"
        )
        #expect(bundle.resourceCountDisplay == "3개 자료")
    }

    // MARK: - StackBundleCatalog 검증

    @Test("StackBundleCatalog.curated 비어있지 않음")
    func curatedNotEmpty() {
        #expect(!StackBundleCatalog.curated.isEmpty)
    }

    @Test("ADR-113 — StackBundleCatalog.curated 8개 이상")
    func curatedHasEightPlus() {
        #expect(StackBundleCatalog.curated.count >= 8)
    }

    @Test("StackBundleCatalog.curated — 모든 id 고유")
    func curatedAllIdsUnique() {
        let ids = StackBundleCatalog.curated.map { $0.id }
        let unique = Set(ids)
        #expect(ids.count == unique.count)
    }

    @Test("StackBundleCatalog.curated — 모든 displayName 비어있지 않음")
    func curatedAllDisplayNamesNotEmpty() {
        for bundle in StackBundleCatalog.curated {
            #expect(!bundle.displayName.isEmpty, "id: \(bundle.id)")
        }
    }

    @Test("StackBundleCatalog.curated — 모든 summary 비어있지 않음")
    func curatedAllSummariesNotEmpty() {
        for bundle in StackBundleCatalog.curated {
            #expect(!bundle.summary.isEmpty, "id: \(bundle.id)")
        }
    }

    @Test("StackBundleCatalog.curated — 모든 stackTags 비어있지 않음")
    func curatedAllStackTagsNotEmpty() {
        for bundle in StackBundleCatalog.curated {
            #expect(!bundle.stackTags.isEmpty, "id: \(bundle.id)")
        }
    }

    @Test("StackBundleCatalog.curated — 모든 resourceIds 비어있지 않음")
    func curatedAllResourceIdsNotEmpty() {
        for bundle in StackBundleCatalog.curated {
            #expect(!bundle.resourceIds.isEmpty, "번들 '\(bundle.displayName)'에 resourceId 없음")
        }
    }

    @Test("StackBundleCatalog.curated — 모든 recommendedFor 비어있지 않음")
    func curatedAllRecommendedForNotEmpty() {
        for bundle in StackBundleCatalog.curated {
            #expect(!bundle.recommendedFor.isEmpty, "id: \(bundle.id)")
        }
    }

    @Test("StackBundleCatalog.curated — 모든 estimatedSetupTime 비어있지 않음")
    func curatedAllEstimatedSetupTimeNotEmpty() {
        for bundle in StackBundleCatalog.curated {
            #expect(!bundle.estimatedSetupTime.isEmpty, "id: \(bundle.id)")
        }
    }

    @Test("ADR-113 — 모든 번들의 resourceIds가 CommunityCatalog에 존재")
    func allBundleResourceIdsExistInCatalog() {
        let catalogIds = Set(CommunityCatalog.curated.map { $0.id })
        for bundle in StackBundleCatalog.curated {
            for resourceId in bundle.resourceIds {
                #expect(
                    catalogIds.contains(resourceId),
                    "번들 '\(bundle.displayName)'의 resourceId \(resourceId)가 CommunityCatalog에 없음"
                )
            }
        }
    }

    @Test("ADR-113 — resolvedResources — 존재하는 자료만 반환")
    func resolvedResourcesReturnsExistingOnly() {
        for bundle in StackBundleCatalog.curated {
            let resolved = bundle.resolvedResources
            #expect(resolved.count <= bundle.resourceIds.count)
            // 모든 resolved 자료가 CommunityCatalog에 있어야 함
            for resource in resolved {
                let exists = CommunityCatalog.curated.contains { $0.id == resource.id }
                #expect(exists, "resolve된 자료 \(resource.id)가 CommunityCatalog에 없음")
            }
        }
    }

    // MARK: - StackBundleCatalog 필터링

    @Test("StackBundleCatalog.bundles(for:) — fullstackWeb 번들 있음")
    func bundlesForFullstackWeb() {
        let bundles = StackBundleCatalog.bundles(for: .fullstackWeb)
        #expect(!bundles.isEmpty)
        for bundle in bundles {
            #expect(bundle.category == .fullstackWeb)
        }
    }

    @Test("StackBundleCatalog.bundles(for:) — mobileApp 번들 있음")
    func bundlesForMobileApp() {
        let bundles = StackBundleCatalog.bundles(for: .mobileApp)
        #expect(!bundles.isEmpty)
        for bundle in bundles {
            #expect(bundle.category == .mobileApp)
        }
    }

    @Test("StackBundleCatalog.bundles(for:) — interactive3D 번들 있음")
    func bundlesForInteractive3D() {
        let bundles = StackBundleCatalog.bundles(for: .interactive3D)
        #expect(!bundles.isEmpty)
    }

    @Test("StackBundleCatalog.bundles(for:) — aiApp 번들 있음")
    func bundlesForAiApp() {
        let bundles = StackBundleCatalog.bundles(for: .aiApp)
        #expect(!bundles.isEmpty)
    }

    @Test("StackBundleCatalog.officialBundles — 공식 배지 번들만 반환")
    func officialBundlesOnlyOfficial() {
        let officials = StackBundleCatalog.officialBundles
        for bundle in officials {
            #expect(bundle.officialBadge == true)
        }
    }
}
