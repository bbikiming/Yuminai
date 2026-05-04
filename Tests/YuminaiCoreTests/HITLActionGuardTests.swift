import Foundation
import Testing
@testable import YuminaiCore

/// **ADR-098 P0-1** — HITLActionGuard 단위 테스트.
@Suite("HITLActionGuard (ADR-098 P0-1)")
struct HITLActionGuardTests {

    // MARK: - shouldRequestApproval — dangerous commands

    @Test("git push --force 는 위험")
    func gitPushForce() {
        #expect(HITLActionGuard.shouldRequestApproval(command: "git push --force origin main"))
    }

    @Test("git push -f 는 위험")
    func gitPushShortForce() {
        #expect(HITLActionGuard.shouldRequestApproval(command: "git push -f"))
    }

    @Test("git reset --hard 는 위험")
    func gitResetHard() {
        #expect(HITLActionGuard.shouldRequestApproval(command: "git reset --hard HEAD~1"))
    }

    @Test("rm -rf 는 위험")
    func rmRecursiveForce() {
        #expect(HITLActionGuard.shouldRequestApproval(command: "rm -rf /tmp/mydir"))
    }

    @Test("rm -r 는 위험")
    func rmRecursive() {
        #expect(HITLActionGuard.shouldRequestApproval(command: "rm -r ./dist"))
    }

    @Test("DROP TABLE 는 위험 (대소문자 무시)")
    func dropTable() {
        #expect(HITLActionGuard.shouldRequestApproval(command: "DROP TABLE users"))
    }

    @Test("drop database 는 위험 (소문자)")
    func dropDatabaseLower() {
        #expect(HITLActionGuard.shouldRequestApproval(command: "drop database mydb"))
    }

    @Test("DELETE FROM 는 위험")
    func deleteFrom() {
        #expect(HITLActionGuard.shouldRequestApproval(command: "DELETE FROM orders WHERE 1=1"))
    }

    @Test("kill -9 는 위험")
    func killNine() {
        #expect(HITLActionGuard.shouldRequestApproval(command: "kill -9 12345"))
    }

    @Test("git clean -fd 는 위험")
    func gitCleanFd() {
        #expect(HITLActionGuard.shouldRequestApproval(command: "git clean -fd"))
    }

    @Test("shutdown 은 위험")
    func shutdown() {
        #expect(HITLActionGuard.shouldRequestApproval(command: "shutdown -h now"))
    }

    // MARK: - shouldRequestApproval — safe commands

    @Test("git push (일반) 는 안전")
    func gitPushSafe() {
        #expect(!HITLActionGuard.shouldRequestApproval(command: "git push origin main"))
    }

    @Test("git status 는 안전")
    func gitStatus() {
        #expect(!HITLActionGuard.shouldRequestApproval(command: "git status"))
    }

    @Test("swift test 는 안전")
    func swiftTest() {
        #expect(!HITLActionGuard.shouldRequestApproval(command: "swift test"))
    }

    @Test("ls 는 안전")
    func lsCommand() {
        #expect(!HITLActionGuard.shouldRequestApproval(command: "ls -la"))
    }

    @Test("SELECT 는 안전")
    func selectQuery() {
        #expect(!HITLActionGuard.shouldRequestApproval(command: "SELECT * FROM users"))
    }

    @Test("echo 는 안전")
    func echoCommand() {
        #expect(!HITLActionGuard.shouldRequestApproval(command: "echo 'hello world'"))
    }

    // MARK: - category

    @Test("git push --force → force-push 카테고리")
    func categoryForcePush() {
        #expect(HITLActionGuard.category(for: "git push --force origin main") == "force-push")
    }

    @Test("rm -rf → rm-recursive 카테고리")
    func categoryRmRecursive() {
        let cat = HITLActionGuard.category(for: "rm -rf /tmp")
        // rm -rf 는 rm-recursive 또는 rm-force 중 하나
        #expect(cat == "rm-recursive" || cat == "rm-force")
    }

    @Test("git reset --hard → git-reset 카테고리")
    func categoryGitReset() {
        #expect(HITLActionGuard.category(for: "git reset --hard") == "git-reset")
    }

    @Test("안전 명령은 nil 카테고리")
    func categoryNilForSafe() {
        #expect(HITLActionGuard.category(for: "swift build") == nil)
    }

    @Test("DROP TABLE → drop-table 카테고리")
    func categoryDropTable() {
        #expect(HITLActionGuard.category(for: "DROP TABLE sessions") == "drop-table")
    }
}
