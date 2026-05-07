import Foundation
import Testing
@testable import YuminaiCore

/// **ADR-133** — CommandPolicy.evaluate() 단위 테스트.
@Suite("CommandPolicy (ADR-133)")
struct CommandPolicyTests {

    // MARK: - allow — gh 읽기 명령

    @Test("gh repo view → allow")
    func ghRepoView() {
        #expect(CommandPolicyMatrix.evaluate("gh repo view anthropics/claude-code") == .allow)
    }

    @Test("gh pr list → allow")
    func ghPRList() {
        #expect(CommandPolicyMatrix.evaluate("gh pr list") == .allow)
    }

    @Test("gh issue view → allow")
    func ghIssueView() {
        #expect(CommandPolicyMatrix.evaluate("gh issue view 123") == .allow)
    }

    @Test("gh run list → allow")
    func ghRunList() {
        #expect(CommandPolicyMatrix.evaluate("gh run list") == .allow)
    }

    @Test("gh auth status → allow")
    func ghAuthStatus() {
        #expect(CommandPolicyMatrix.evaluate("gh auth status") == .allow)
    }

    // MARK: - allow — glab 읽기 명령

    @Test("glab mr list → allow")
    func glabMrList() {
        #expect(CommandPolicyMatrix.evaluate("glab mr list") == .allow)
    }

    @Test("glab pipeline list → allow")
    func glabPipelineList() {
        #expect(CommandPolicyMatrix.evaluate("glab pipeline list") == .allow)
    }

    @Test("glab auth status → allow")
    func glabAuthStatus() {
        #expect(CommandPolicyMatrix.evaluate("glab auth status") == .allow)
    }

    // MARK: - allow — git 읽기 명령

    @Test("git status → allow")
    func gitStatus() {
        #expect(CommandPolicyMatrix.evaluate("git status") == .allow)
    }

    @Test("git log → allow")
    func gitLog() {
        #expect(CommandPolicyMatrix.evaluate("git log --oneline -10") == .allow)
    }

    @Test("git diff → allow")
    func gitDiff() {
        #expect(CommandPolicyMatrix.evaluate("git diff HEAD~1") == .allow)
    }

    // MARK: - allow — pr/issue create (사용자 의도 명확)

    @Test("gh pr create → allow")
    func ghPRCreate() {
        #expect(CommandPolicyMatrix.evaluate("gh pr create --title 'fix: bug'") == .allow)
    }

    @Test("gh issue create → allow")
    func ghIssueCreate() {
        #expect(CommandPolicyMatrix.evaluate("gh issue create --title 'bug report'") == .allow)
    }

    @Test("glab mr create → allow")
    func glabMrCreate() {
        #expect(CommandPolicyMatrix.evaluate("glab mr create --title 'feat: feature'") == .allow)
    }

    // MARK: - deny — git 파괴적 명령 (HITLActionGuard 동기화)

    @Test("git push --force → deny")
    func gitPushForce() {
        #expect(CommandPolicyMatrix.evaluate("git push --force origin main") == .deny)
    }

    @Test("git push -f → deny")
    func gitPushShortForce() {
        #expect(CommandPolicyMatrix.evaluate("git push -f") == .deny)
    }

    @Test("git reset --hard → deny")
    func gitResetHard() {
        #expect(CommandPolicyMatrix.evaluate("git reset --hard HEAD~1") == .deny)
    }

    @Test("rm -rf → deny")
    func rmRecursiveForce() {
        #expect(CommandPolicyMatrix.evaluate("rm -rf /tmp/mydir") == .deny)
    }

    @Test("DROP TABLE → deny")
    func dropTable() {
        #expect(CommandPolicyMatrix.evaluate("DROP TABLE users") == .deny)
    }

    @Test("kill -9 → deny")
    func killNine() {
        #expect(CommandPolicyMatrix.evaluate("kill -9 12345") == .deny)
    }

    // MARK: - deny — gh 위험 명령

    @Test("gh repo delete → deny")
    func ghRepoDelete() {
        #expect(CommandPolicyMatrix.evaluate("gh repo delete myorg/myrepo") == .deny)
    }

    @Test("gh secret set → deny")
    func ghSecretSet() {
        #expect(CommandPolicyMatrix.evaluate("gh secret set MY_TOKEN") == .deny)
    }

    // MARK: - deny — glab 위험 명령

    @Test("glab project delete → deny")
    func glabProjectDelete() {
        #expect(CommandPolicyMatrix.evaluate("glab project delete myproject") == .deny)
    }

    @Test("glab variable set → deny")
    func glabVariableSet() {
        #expect(CommandPolicyMatrix.evaluate("glab variable set MY_SECRET") == .deny)
    }

    // MARK: - requireConfirmation — 알 수 없는 명령

    @Test("unknown command → requireConfirmation")
    func unknownCommand() {
        #expect(CommandPolicyMatrix.evaluate("some-unknown-tool --do-stuff") == .requireConfirmation)
    }

    @Test("gh pr merge → requireConfirmation (write, 기본 패턴 미정의)")
    func ghPRMerge() {
        // gh pr merge는 기본 allowList/allowPatterns에 없음 → requireConfirmation
        #expect(CommandPolicyMatrix.evaluate("gh pr merge 123") == .requireConfirmation)
    }

    // MARK: - 대소문자 무시

    @Test("DROP table 소문자 → deny")
    func dropTableLowercase() {
        #expect(CommandPolicyMatrix.evaluate("drop table users") == .deny)
    }

    // MARK: - CommandPolicy 프로퍼티

    @Test("allow.displayName")
    func allowDisplayName() {
        #expect(CommandPolicy.allow.displayName == "자동 승인")
    }

    @Test("deny.icon")
    func denyIcon() {
        #expect(CommandPolicy.deny.icon == "xmark.circle.fill")
    }
}
