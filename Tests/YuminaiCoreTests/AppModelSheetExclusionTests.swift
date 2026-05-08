import Foundation
import Testing

/// **ADR-125 P0-1** — `AppModel.dismissAllSheets()` mutual exclusion 회귀 가드.
///
/// `AppModel`은 executable target이라 `@testable import` 불가.
/// 대신 소스 파일을 직접 읽어 `dismissAllSheets()` 함수 바디가
/// ADR-111 ~ ADR-117에서 추가된 sheet 필드를 포함하는지 구조적으로 검증한다.
///
/// ### 목적
/// 새 sheet 필드가 추가될 때 `dismissAllSheets()`에 추가를 잊으면 이 테스트가 실패한다.
/// 이는 CI에서 mutual exclusion 깨짐을 조기에 감지하는 회귀 가드다.
@Suite("AppModel dismissAllSheets mutual exclusion guard (ADR-125)")
struct AppModelSheetExclusionTests {

    // MARK: - 헬퍼

    /// Package root를 찾는다 — `Package.swift`가 있는 디렉터리를 기준으로 상위 탐색.
    /// **ADR-148** — `#filePath`(소스 컴파일 경로)에서 Package.swift 자동 탐색.
    /// 절대 경로 hardcode 제거 (CI 환경 호환: /Users/runner/work/Yuminai/Yuminai 등).
    private func packageRoot(file: StaticString = #filePath) throws -> URL {
        let fileURL = URL(fileURLWithPath: "\(file)")
        var dir = fileURL.deletingLastPathComponent()
        let fm = FileManager.default
        // 최대 5단계 위로 올라가며 Package.swift 탐색 (Tests/<Suite>Tests/<File>.swift → root)
        for _ in 0..<5 {
            if fm.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        throw TestFailure("Package.swift를 #filePath 기준 상위 5단계에서 찾을 수 없음 (시작: \(file))")
    }

    /// `AppModel.swift`에서 `dismissAllSheets()` 함수 바디 문자열을 추출한다.
    private func dismissAllSheetsBody() throws -> String {
        let root = try packageRoot()
        let appModelURL = root.appendingPathComponent("Sources/YuminaiApp/AppModel.swift")
        let source = try String(contentsOf: appModelURL, encoding: .utf8)

        // dismissAllSheets 함수 바디 추출 (시작 ~ 닫는 중괄호 줄까지)
        guard let startRange = source.range(of: "public func dismissAllSheets()") else {
            throw TestFailure("dismissAllSheets() 함수를 AppModel.swift에서 찾을 수 없음")
        }
        let bodyStart = source[startRange.lowerBound...]

        // 닫는 `}` 와 그 바로 다음 줄 (`presentExclusiveSheet`)까지 slicing
        guard let endRange = bodyStart.range(of: "\n    public func presentExclusiveSheet") else {
            throw TestFailure("presentExclusiveSheet 함수를 찾을 수 없음 — dismissAllSheets 끝 감지 실패")
        }
        return String(bodyStart[bodyStart.startIndex..<endRange.lowerBound])
    }

    // MARK: - 기존 sheet (회귀 기준선)

    @Test("dismissAllSheets — showCreateWorkspaceSheet 포함")
    func includesCreateWorkspaceSheet() throws {
        let body = try dismissAllSheetsBody()
        #expect(body.contains("showCreateWorkspaceSheet"))
    }

    @Test("dismissAllSheets — showSetupWizard 포함 (ADR-104)")
    func includesSetupWizard() throws {
        let body = try dismissAllSheetsBody()
        #expect(body.contains("showSetupWizard"))
    }

    // MARK: - ADR-111 ~ ADR-117 추가된 sheet (P0-1 핵심 검증)

    @Test("dismissAllSheets — showLibrarySheet 포함 (ADR-111, P0-1)")
    func includesLibrarySheet() throws {
        let body = try dismissAllSheetsBody()
        #expect(body.contains("showLibrarySheet"))
    }

    @Test("dismissAllSheets — showCatalogSheet 포함 (ADR-112, P0-1)")
    func includesCatalogSheet() throws {
        let body = try dismissAllSheetsBody()
        #expect(body.contains("showCatalogSheet"))
    }

    @Test("dismissAllSheets — showBundleCatalogSheet 포함 (ADR-113, P0-1)")
    func includesBundleCatalogSheet() throws {
        let body = try dismissAllSheetsBody()
        #expect(body.contains("showBundleCatalogSheet"))
    }

    @Test("dismissAllSheets — showGitHubSearchSheet 포함 (ADR-116, P0-1)")
    func includesGitHubSearchSheet() throws {
        let body = try dismissAllSheetsBody()
        #expect(body.contains("showGitHubSearchSheet"))
    }

    @Test("dismissAllSheets — showCommunityResourcesSheet 포함 (ADR-117, P0-1)")
    func includesCommunityResourcesSheet() throws {
        let body = try dismissAllSheetsBody()
        #expect(body.contains("showCommunityResourcesSheet"))
    }

    // MARK: - P1-1 dead code 제거 검증

    @Test("AppModel.swift에 showGitHubPATSheet 필드가 없음 (P1-1 dead code 제거)")
    func noGitHubPATSheetField() throws {
        let root = try packageRoot()
        let appModelURL = root.appendingPathComponent("Sources/YuminaiApp/AppModel.swift")
        let source = try String(contentsOf: appModelURL, encoding: .utf8)
        // 필드 선언(var showGitHubPATSheet)이 없어야 한다
        #expect(!source.contains("var showGitHubPATSheet"))
    }
}

// MARK: - 내부 에러 타입

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { self.description = message }
}
