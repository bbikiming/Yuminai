import Foundation
import Testing
@testable import YuminaiCore

@Suite("CodeOwnersParser (ADR-082 Phase 5)")
struct CodeOwnersParserTests {

    @Test("빈 content — 빈 result")
    func empty() {
        let owners = CodeOwnersParser.match(codeowners: "", paths: ["src/main.swift"])
        #expect(owners.isEmpty)
    }

    @Test("comment + 빈 줄 무시")
    func commentsAndBlanks() {
        let content = """
        # this is a comment

        # another
        *  @global-owner
        """
        let owners = CodeOwnersParser.match(codeowners: content, paths: ["any.swift"])
        #expect(owners == ["global-owner"])
    }

    @Test("와일드카드 * 매칭")
    func wildcard() {
        let content = "* @global-owner1 @global-owner2"
        let owners = CodeOwnersParser.match(codeowners: content, paths: ["src/foo.swift"])
        #expect(owners == ["global-owner1", "global-owner2"])
    }

    @Test("디렉토리 prefix 매칭 (/docs/)")
    func directoryPrefix() {
        let content = """
        * @global
        /docs/ @docs-team
        """
        let owners = CodeOwnersParser.match(codeowners: content, paths: ["docs/intro.md"])
        // 마지막 매칭 (= /docs/) winner
        #expect(owners == ["docs-team"])
    }

    @Test("suffix glob (*.swift)")
    func suffixGlob() {
        let content = """
        * @global
        *.swift @ios-team
        """
        let owners = CodeOwnersParser.match(codeowners: content, paths: ["src/View.swift"])
        #expect(owners == ["ios-team"])
    }

    @Test("매칭 없으면 빈 result")
    func noMatch() {
        let content = "/docs/ @docs-team"
        let owners = CodeOwnersParser.match(codeowners: content, paths: ["src/main.swift"])
        #expect(owners.isEmpty)
    }

    @Test("@ prefix 자동 제거 (login만 반환)")
    func stripAtPrefix() {
        let content = "* @user1 @org/team-a"
        let owners = CodeOwnersParser.match(codeowners: content, paths: ["any"])
        #expect(owners.contains("user1"))
        #expect(owners.contains("org/team-a"))
    }

    @Test("여러 path → owner union")
    func multiplePaths() {
        let content = """
        *.swift @ios-team
        /docs/ @docs-team
        """
        let owners = CodeOwnersParser.match(
            codeowners: content,
            paths: ["src/View.swift", "docs/README.md"]
        )
        #expect(owners.contains("ios-team"))
        #expect(owners.contains("docs-team"))
    }

    @Test("parse — Rule 추출 (pattern + owners)")
    func parseRules() {
        let content = """
        * @global
        *.swift @ios-team @backup
        """
        let rules = CodeOwnersParser.parse(content)
        #expect(rules.count == 2)
        #expect(rules[0].pattern == "*")
        #expect(rules[1].owners == ["@ios-team", "@backup"])
    }
}

@Suite("RebaseAction (ADR-082 Phase 4)")
struct RebaseActionTests {

    @Test("allCases — 5개 (pick/reword/squash/fixup/drop)")
    func allCases() {
        #expect(RebaseAction.allCases.count == 5)
        #expect(RebaseAction.allCases.contains(.pick))
        #expect(RebaseAction.allCases.contains(.drop))
    }

    @Test("rawValue — git 표준 매칭")
    func rawValues() {
        #expect(RebaseAction.pick.rawValue == "pick")
        #expect(RebaseAction.reword.rawValue == "reword")
        #expect(RebaseAction.squash.rawValue == "squash")
        #expect(RebaseAction.fixup.rawValue == "fixup")
        #expect(RebaseAction.drop.rawValue == "drop")
    }

    @Test("displayName 한국어")
    func displayNames() {
        #expect(RebaseAction.pick.displayName == "유지")
        #expect(RebaseAction.drop.displayName == "삭제")
    }

    @Test("hint 모두 한국어")
    func hintsKorean() {
        for action in RebaseAction.allCases {
            #expect(!action.hint.isEmpty)
        }
    }

    @Test("Identifiable — id == rawValue")
    func identifiable() {
        for action in RebaseAction.allCases {
            #expect(action.id == action.rawValue)
        }
    }
}

@Suite("PullRequestDetails (ADR-082 Phase 2)")
struct PullRequestDetailsTests {

    @Test("stateDisplay — 한국어 매핑")
    func stateDisplay() {
        let openPR = makePR(state: "OPEN", isDraft: false)
        #expect(openPR.stateDisplay == "열림")
        let draftPR = makePR(state: "OPEN", isDraft: true)
        #expect(draftPR.stateDisplay == "초안")
        let closedPR = makePR(state: "CLOSED", isDraft: false)
        #expect(closedPR.stateDisplay == "닫힘")
        let mergedPR = makePR(state: "MERGED", isDraft: false)
        #expect(mergedPR.stateDisplay == "병합됨")
    }

    @Test("allChecksPass — 모두 SUCCESS면 true")
    func allChecksPassTrue() {
        let pr = makePR(state: "OPEN", isDraft: false, checks: [
            PullRequestDetails.PRCheck(name: "test", conclusion: "SUCCESS", status: "COMPLETED"),
            PullRequestDetails.PRCheck(name: "lint", conclusion: "SUCCESS", status: "COMPLETED")
        ])
        #expect(pr.allChecksPass == true)
    }

    @Test("allChecksPass — FAILURE 있으면 false")
    func allChecksPassFalse() {
        let pr = makePR(state: "OPEN", isDraft: false, checks: [
            PullRequestDetails.PRCheck(name: "test", conclusion: "SUCCESS", status: "COMPLETED"),
            PullRequestDetails.PRCheck(name: "lint", conclusion: "FAILURE", status: "COMPLETED")
        ])
        #expect(pr.allChecksPass == false)
        #expect(pr.failedChecks == 1)
    }

    @Test("pendingChecks count")
    func pendingCount() {
        let pr = makePR(state: "OPEN", isDraft: false, checks: [
            PullRequestDetails.PRCheck(name: "test", conclusion: nil, status: "IN_PROGRESS"),
            PullRequestDetails.PRCheck(name: "lint", conclusion: nil, status: "QUEUED"),
            PullRequestDetails.PRCheck(name: "build", conclusion: "SUCCESS", status: "COMPLETED")
        ])
        #expect(pr.pendingChecks == 2)
    }

    @Test("nil checks — allChecksPass true (vacuous)")
    func nilChecks() {
        let pr = makePR(state: "OPEN", isDraft: false, checks: nil)
        #expect(pr.allChecksPass == true)
        #expect(pr.failedChecks == 0)
        #expect(pr.pendingChecks == 0)
    }

    private func makePR(
        state: String,
        isDraft: Bool,
        checks: [PullRequestDetails.PRCheck]? = nil
    ) -> PullRequestDetails {
        PullRequestDetails(
            number: 1,
            title: "test",
            url: "https://example.com",
            state: state,
            isDraft: isDraft,
            body: nil,
            author: PullRequestDetails.PRAuthor(login: "tester"),
            headRefName: "feature",
            baseRefName: "main",
            reviewDecision: nil,
            statusCheckRollup: checks,
            comments: nil
        )
    }
}

@Suite("WorkflowRun (ADR-082 Phase 3)")
struct WorkflowRunTests {

    @Test("displayStatus — completed + success → 성공")
    func displaySuccess() {
        let run = WorkflowRun(
            databaseId: 1, displayTitle: "Test",
            workflowName: "CI", status: "completed", conclusion: "success",
            headBranch: "main", createdAt: "2026-01-01", url: "https://example.com"
        )
        #expect(run.displayStatus == "성공")
        #expect(run.isSuccess == true)
        #expect(run.isInProgress == false)
        #expect(run.isFailure == false)
    }

    @Test("displayStatus — failure")
    func displayFailure() {
        let run = WorkflowRun(
            databaseId: 1, displayTitle: "Test",
            workflowName: "CI", status: "completed", conclusion: "failure",
            headBranch: "main", createdAt: "2026-01-01", url: "https://example.com"
        )
        #expect(run.displayStatus == "실패")
        #expect(run.isFailure == true)
    }

    @Test("displayStatus — in_progress")
    func displayInProgress() {
        let run = WorkflowRun(
            databaseId: 1, displayTitle: "Test",
            workflowName: "CI", status: "in_progress", conclusion: nil,
            headBranch: "main", createdAt: "2026-01-01", url: "https://example.com"
        )
        #expect(run.displayStatus == "진행 중")
        #expect(run.isInProgress == true)
    }

    @Test("Identifiable — id == databaseId")
    func identifiable() {
        let run = WorkflowRun(
            databaseId: 12345, displayTitle: "Test",
            workflowName: "CI", status: "queued", conclusion: nil,
            headBranch: "main", createdAt: "2026-01-01", url: ""
        )
        #expect(run.id == 12345)
    }
}
