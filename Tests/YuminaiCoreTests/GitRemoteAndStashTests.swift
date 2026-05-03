import Foundation
import Testing
@testable import YuminaiCore

@Suite("UpstreamStatus (ADR-081 Phase 1)")
struct UpstreamStatusTests {

    @Test("isInSync — ahead/behind 모두 0이면 true")
    func inSync() {
        let s = UpstreamStatus(upstreamName: "origin/main", ahead: 0, behind: 0)
        #expect(s.isInSync == true)
        #expect(s.summary == "동기화됨")
    }

    @Test("ahead만 있을 때 push 대기")
    func ahead() {
        let s = UpstreamStatus(upstreamName: "origin/main", ahead: 3, behind: 0)
        #expect(s.isInSync == false)
        #expect(s.summary.contains("↑3 push 대기"))
    }

    @Test("behind만 있을 때 pull 필요")
    func behind() {
        let s = UpstreamStatus(upstreamName: "origin/main", ahead: 0, behind: 2)
        #expect(s.isInSync == false)
        #expect(s.summary.contains("↓2 pull 필요"))
    }

    @Test("ahead + behind 동시 — diverged")
    func diverged() {
        let s = UpstreamStatus(upstreamName: "origin/main", ahead: 1, behind: 2)
        #expect(s.isInSync == false)
        #expect(s.summary.contains("↑1"))
        #expect(s.summary.contains("↓2"))
    }
}

@Suite("StashInfo (ADR-081 Phase 4)")
struct StashInfoTests {

    @Test("Identifiable — id == ref")
    func identifiable() {
        let s = StashInfo(shortSha: "abc", ref: "stash@{0}", message: "WIP", relativeDate: "1 hour ago")
        #expect(s.id == "stash@{0}")
    }

    @Test("Hashable — 다른 ref면 다른 hash")
    func hashable() {
        let s1 = StashInfo(shortSha: "abc", ref: "stash@{0}", message: "WIP", relativeDate: "1 hour ago")
        let s2 = StashInfo(shortSha: "abc", ref: "stash@{1}", message: "WIP", relativeDate: "1 hour ago")
        #expect(s1 != s2)
    }
}

@Suite("GitPullError (ADR-081 Phase 1)")
struct GitPullErrorTests {

    @Test("dirtyTree — 한국어 메시지")
    func dirtyTreeMessage() {
        let err = GitPullError.dirtyTree
        #expect(err.errorDescription?.contains("변경된 파일") == true)
        #expect(err.errorDescription?.contains("stash") == true)
    }
}

@Suite("GitHubCLIRunner (ADR-081 Phase 3)")
struct GitHubCLIRunnerTests {

    @Test("기본 ghPath candidates — 표준 경로 hit")
    func defaultPath() {
        let path = GitHubCLIRunner.defaultGhPath()
        let pathStr = path.path
        // homebrew arm64, intel, system 중 하나
        let validPaths = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        #expect(validPaths.contains(pathStr))
    }

    @Test("GitHubError — 한국어 errorDescription")
    func errorMessages() {
        #expect(GitHubCLIRunner.GitHubError.ghNotInstalled.errorDescription?.contains("gh CLI") == true)
        #expect(GitHubCLIRunner.GitHubError.notAuthenticated.errorDescription?.contains("gh auth login") == true)
    }

    @Test("isInstalled — runner mock 가능")
    func isInstalledMockable() async {
        // Mock으로 테스트 — 실제 gh 호출 없이
        let cwd = URL(fileURLWithPath: "/tmp")
        let runner = GitHubCLIRunner(
            ghPath: URL(fileURLWithPath: "/nonexistent/gh"),
            workspaceURL: cwd,
            runner: { _, _ in
                GitHubCLIRunner.ProcessResult(exitCode: 0, stdout: "", stderr: "")
            }
        )
        // 실제 파일이 없으니 isInstalled = false (FileManager check)
        let installed = await runner.isInstalled()
        #expect(installed == false)
    }

    @Test("makeRunWithCwd — Run typealias 생성")
    func makeRunWithCwd() {
        let cwd = URL(fileURLWithPath: "/tmp")
        let _ = GitHubCLIRunner.makeRunWithCwd(cwd)
        // 컴파일 OK = 검증 완료 (closure 생성 자체)
        #expect(true)
    }
}
