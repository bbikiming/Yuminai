import Foundation
import Testing
@testable import YuminaiCore

/// **ADR-133** — CommandPolicyMatrix 단위 테스트.
/// Codable 왕복 / 사용자 패턴 우선순위 / 정규식 매칭.
@Suite("CommandPolicyMatrix (ADR-133)")
struct CommandPolicyMatrixTests {

    // MARK: - Codable 왕복

    @Test("CommandPolicyMatrix Codable 왕복")
    func codableRoundtrip() throws {
        let matrix = CommandPolicyMatrix(
            allowList: ["gh pr list", "git status"],
            allowPatterns: [#"^gh\s+pr\s+create"#],
            denyPatterns: [#"^gh\s+repo\s+delete"#],
            autoApprovePermissions: false
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(matrix)
        let decoded = try JSONDecoder().decode(CommandPolicyMatrix.self, from: data)
        #expect(decoded.allowList == matrix.allowList)
        #expect(decoded.allowPatterns == matrix.allowPatterns)
        #expect(decoded.denyPatterns == matrix.denyPatterns)
        #expect(decoded.autoApprovePermissions == false)
    }

    // MARK: - 기본값

    @Test("CommandPolicyMatrix.default 기본 allowList 비어 있지 않음")
    func defaultAllowListNotEmpty() {
        #expect(!CommandPolicyMatrix.default.allowList.isEmpty)
    }

    @Test("CommandPolicyMatrix.default 기본 denyPatterns 비어 있지 않음")
    func defaultDenyPatternsNotEmpty() {
        #expect(!CommandPolicyMatrix.default.denyPatterns.isEmpty)
    }

    @Test("CommandPolicyMatrix.default autoApprovePermissions = true")
    func defaultAutoApprove() {
        #expect(CommandPolicyMatrix.default.autoApprovePermissions == true)
    }

    // MARK: - 사용자 패턴 우선순위

    @Test("사용자 deny 패턴이 allow보다 우선")
    func userDenyBeatsAllow() {
        var matrix = CommandPolicyMatrix.default
        // 기본 allowList에 있는 패턴을 deny에 추가
        matrix.denyPatterns.append("gh pr list")
        // deny가 allowList보다 먼저 평가되므로 deny
        #expect(matrix.policy(for: "gh pr list") == .deny)
    }

    @Test("사용자 allowPattern이 requireConfirmation을 override")
    func userAllowOverridesDefault() {
        var matrix = CommandPolicyMatrix.default
        // 기본에 없는 명령 추가
        matrix.allowPatterns.append(#"^gh\s+workflow\s+run\b"#)
        #expect(matrix.policy(for: "gh workflow run deploy.yml") == .allow)
    }

    // MARK: - 정규식 매칭

    @Test("정규식 패턴 대소문자 무시")
    func patternCaseInsensitive() {
        let matrix = CommandPolicyMatrix(
            allowList: [],
            allowPatterns: [#"^GIT\s+STATUS"#],
            denyPatterns: [],
            autoApprovePermissions: true
        )
        #expect(matrix.policy(for: "git status") == .allow)
    }

    @Test("복잡한 정규식 매칭 — gh read 계열")
    func complexRegexGhRead() {
        let matrix = CommandPolicyMatrix.default
        // gh codespace list → allow (allowPatterns)
        #expect(matrix.policy(for: "gh codespace list") == .allow)
    }

    @Test("allowList prefix 매칭 — 추가 인자 포함해도 allow")
    func allowListPrefixMatchWithArgs() {
        let matrix = CommandPolicyMatrix.default
        #expect(matrix.policy(for: "gh pr list --state open --limit 20") == .allow)
    }

    // MARK: - 빈 매트릭스

    @Test("allowList/allowPatterns 비어있으면 모두 requireConfirmation")
    func emptyAllowListRequiresConfirmation() {
        let matrix = CommandPolicyMatrix(
            allowList: [],
            allowPatterns: [],
            denyPatterns: [],
            autoApprovePermissions: true
        )
        #expect(matrix.policy(for: "git status") == .requireConfirmation)
    }

    @Test("denyPatterns 비어있으면 deny 없음")
    func emptyDenyNoDeny() {
        let matrix = CommandPolicyMatrix(
            allowList: ["git status"],
            allowPatterns: [],
            denyPatterns: [],
            autoApprovePermissions: true
        )
        #expect(matrix.policy(for: "git reset --hard") != .deny)
    }

    // MARK: - CommandPolicy Codable

    @Test("CommandPolicy allow Codable 왕복")
    func commandPolicyCodable() throws {
        let policy = CommandPolicy.allow
        let data = try JSONEncoder().encode(policy)
        let decoded = try JSONDecoder().decode(CommandPolicy.self, from: data)
        #expect(decoded == .allow)
    }

    @Test("CommandPolicy deny Codable 왕복")
    func commandPolicyDenyCodable() throws {
        let data = try JSONEncoder().encode(CommandPolicy.deny)
        let decoded = try JSONDecoder().decode(CommandPolicy.self, from: data)
        #expect(decoded == .deny)
    }

    @Test("CommandPolicy unknown string decodes to requireConfirmation")
    func commandPolicyUnknownDecodesFallback() throws {
        let json = #"{"type":"unknown_future_value"}"#
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(CommandPolicy.self, from: data)
        #expect(decoded == .requireConfirmation)
    }
}
