import Foundation
import Testing
import SwiftUI
@testable import YuminaiUI
@testable import YuminaiCore

/// **ADR-126** — CategoryColors (swiftUIColor) 단위 테스트.
///
/// 16 케이스 모두 색상이 정의되어 있고 `default` fallback이 없음을 보장.
/// TDD: 새 카테고리를 `CommunityResource.Category`에 추가하면 이 스위트가 자동으로 실패 → 색상 추가를 강제.
@Suite("CategoryColors (ADR-126)")
struct CategoryColorsTests {

    // MARK: - 16 케이스 색상 정의 검증

    @Test("claudeMd → Theme.Color.accent")
    func claudeMdColor() {
        #expect(CommunityResource.Category.claudeMd.swiftUIColor == Theme.Color.accent)
    }

    @Test("skill → orange")
    func skillColor() {
        #expect(CommunityResource.Category.skill.swiftUIColor == .orange)
    }

    @Test("template → Theme.Color.success")
    func templateColor() {
        #expect(CommunityResource.Category.template.swiftUIColor == Theme.Color.success)
    }

    @Test("styleGuide → purple")
    func styleGuideColor() {
        #expect(CommunityResource.Category.styleGuide.swiftUIColor == .purple)
    }

    @Test("workflow → blue")
    func workflowColor() {
        #expect(CommunityResource.Category.workflow.swiftUIColor == .blue)
    }

    @Test("architecture → indigo")
    func architectureColor() {
        #expect(CommunityResource.Category.architecture.swiftUIColor == .indigo)
    }

    @Test("promptPattern → teal")
    func promptPatternColor() {
        #expect(CommunityResource.Category.promptPattern.swiftUIColor == .teal)
    }

    @Test("rules → red")
    func rulesColor() {
        #expect(CommunityResource.Category.rules.swiftUIColor == .red)
    }

    @Test("mcp → cyan")
    func mcpColor() {
        #expect(CommunityResource.Category.mcp.swiftUIColor == .cyan)
    }

    @Test("webFramework → blue")
    func webFrameworkColor() {
        #expect(CommunityResource.Category.webFramework.swiftUIColor == .blue)
    }

    @Test("mobileFramework → pink")
    func mobileFrameworkColor() {
        #expect(CommunityResource.Category.mobileFramework.swiftUIColor == .pink)
    }

    @Test("graphics3D → purple")
    func graphics3DColor() {
        #expect(CommunityResource.Category.graphics3D.swiftUIColor == .purple)
    }

    @Test("backend → Theme.Color.success")
    func backendColor() {
        #expect(CommunityResource.Category.backend.swiftUIColor == Theme.Color.success)
    }

    @Test("database → orange")
    func databaseColor() {
        #expect(CommunityResource.Category.database.swiftUIColor == .orange)
    }

    @Test("devops → gray")
    func devopsColor() {
        #expect(CommunityResource.Category.devops.swiftUIColor == .gray)
    }

    // MARK: - 전체 케이스 커버리지 (default fallback 방지)

    @Test("allCases 16개 — default fallback 없이 모두 색상 정의됨")
    func allCasesCovered() {
        // CommunityResource.Category.allCases — ADR-133에서 4 케이스 추가 (19개)
        #expect(CommunityResource.Category.allCases.count == 19)
        // 각 케이스에 swiftUIColor 접근이 컴파일 오류 없이 성공해야 함
        for category in CommunityResource.Category.allCases {
            // swiftUIColor 접근만으로 컴파일러가 exhaustive switch를 강제 — 반환 값 사용
            let _ = category.swiftUIColor
        }
    }

    // MARK: - LibraryFilterCategory coreCategory 16 케이스 커버리지

    @Test("LibraryFilterCategory.allCases — all 포함 총 16 케이스")
    func filterCategoryAllCases() {
        // all (1) + 19 core categories = 20 (ADR-133: 4 신규 케이스 추가)
        #expect(CommunityResource.LibraryFilterCategory.allCases.count == 20)
    }

    @Test("LibraryFilterCategory.all → coreCategory nil")
    func filterCategoryAllIsNil() {
        #expect(CommunityResource.LibraryFilterCategory.all.coreCategory == nil)
    }

    @Test("LibraryFilterCategory 비-all 케이스 모두 coreCategory 비-nil")
    func filterCategoryNonAllHaveCore() {
        let nonAll = CommunityResource.LibraryFilterCategory.allCases.filter { $0 != .all }
        for filter in nonAll {
            #expect(filter.coreCategory != nil, "'\(filter.rawValue)' coreCategory가 nil임")
        }
    }

    @Test("LibraryFilterCategory 모든 rawValue 고유")
    func filterCategoryUniqueRawValues() {
        let rawValues = CommunityResource.LibraryFilterCategory.allCases.map { $0.rawValue }
        #expect(Set(rawValues).count == rawValues.count)
    }
}
