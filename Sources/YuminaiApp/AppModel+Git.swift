import Foundation
import AppKit
import YuminaiCore
import YuminaiClaudeAdapter
import YuminaiPersistence

// ADR-128 — AppModel.swift 분할: Git 도메인
// Git status/branch, push/pull/fetch, stash, AI 커밋 메시지, GitHub PR 생성/리뷰,
// GitHub Actions, rebase, CodeOwners, conflict resolution, cherry-pick, PR comment, workflow rerun.
extension AppModel {

    // MARK: - ADR-079 Phase 4-5 — Git integration (Claude Code 패턴 단순화)

    /// 현재 워크스페이스의 Git status를 새로 fetch (workspace 선택 시 + commit 후 호출).
    public func refreshGitStatus() async {
        guard let ws = workspaces.first(where: { $0.id == selectedWorkspaceId }) else {
            gitBranch = nil
            gitDirtyStats = nil
            return
        }
        let url = URL(fileURLWithPath: ws.directoryPath)
        let runner = GitRunner(workspaceURL: url)
        guard await runner.isRepository() else {
            gitBranch = nil
            gitDirtyStats = nil
            return
        }
        let manager = GitBranchManager(runner: runner)
        do {
            self.gitBranch = try await manager.currentBranch()
            self.gitDirtyStats = try await manager.dirtyStats()
            self.gitUpstream = try? await manager.upstreamStatus()
        } catch {
            self.gitBranch = nil
            self.gitDirtyStats = nil
            self.gitUpstream = nil
        }
    }

    /// 현재 워크스페이스의 GitBranchManager를 생성 (현재 워크스페이스가 git repo가 아니면 nil).
    public func makeGitManager() async -> GitBranchManager? {
        guard let ws = workspaces.first(where: { $0.id == selectedWorkspaceId }) else { return nil }
        let url = URL(fileURLWithPath: ws.directoryPath)
        let runner = GitRunner(workspaceURL: url)
        guard await runner.isRepository() else { return nil }
        return GitBranchManager(runner: runner)
    }

    /// 브랜치 전환.
    public func switchGitBranch(_ name: String) async {
        guard let manager = await makeGitManager() else { return }
        do {
            try await manager.switchBranch(name)
            await refreshGitStatus()
        } catch {
            self.error = "브랜치 전환 실패: \(error.localizedDescription)"
        }
    }

    /// 새 브랜치 생성.
    public func createGitBranch(_ name: String) async {
        guard let manager = await makeGitManager() else { return }
        do {
            try await manager.createBranch(name)
            await refreshGitStatus()
        } catch {
            self.error = "브랜치 생성 실패: \(error.localizedDescription)"
        }
    }

    /// 현재 변경사항 commit (auto-stage all + Co-Authored-By).
    public func commitChanges(message: String) async {
        guard let manager = await makeGitManager() else { return }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalMessage = trimmed.isEmpty
            ? AutoCommitMessageGenerator.generate(stats: gitDirtyStats ?? DirtyStats(modified: 0, added: 0, deleted: 0, untracked: 0))
            : trimmed
        do {
            let sha = try await manager.commitAll(message: finalMessage)
            self.error = "✓ 커밋 완료: \(sha) — \(finalMessage)"
            await refreshGitStatus()
        } catch {
            self.error = "커밋 실패: \(error.localizedDescription)"
        }
    }

    /// 현재 워크스페이스 브랜치 목록 (UI에서 사용).
    public func gitBranches() async -> [BranchInfo] {
        guard let manager = await makeGitManager() else { return [] }
        return (try? await manager.localBranches()) ?? []
    }

    // MARK: - ADR-081 Phase 1 — Push/Pull/Fetch

    /// fetch + status 갱신 (사용자 manual trigger 또는 commit 후 자동).
    public func gitFetch() async {
        guard let manager = await makeGitManager() else { return }
        gitOperationInProgress = true
        defer { gitOperationInProgress = false }
        do {
            try await manager.fetch()
            await refreshGitStatus()
        } catch {
            self.error = "Git fetch 실패: \(error.localizedDescription)"
        }
    }

    /// pull (rebase 모드, dirty면 throw).
    public func gitPull() async {
        guard let manager = await makeGitManager() else { return }
        gitOperationInProgress = true
        defer { gitOperationInProgress = false }
        do {
            try await manager.pull(rebase: true)
            await refreshGitStatus()
            self.error = "✓ Pull 완료"
        } catch {
            self.error = "Pull 실패: \(error.localizedDescription)"
        }
    }

    /// push (upstream 없으면 자동 -u).
    public func gitPush(force: Bool = false) async {
        guard let manager = await makeGitManager() else { return }
        gitOperationInProgress = true
        defer { gitOperationInProgress = false }
        do {
            try await manager.push(force: force)
            await refreshGitStatus()
            self.error = "✓ Push 완료"
        } catch {
            self.error = "Push 실패: \(error.localizedDescription)"
        }
    }

    // MARK: - ADR-081 Phase 4 — Stash

    public func gitStashes() async -> [StashInfo] {
        guard let manager = await makeGitManager() else { return [] }
        return (try? await manager.stashes()) ?? []
    }

    public func gitCreateStash(message: String) async {
        guard let manager = await makeGitManager() else { return }
        do {
            try await manager.createStash(message: message)
            await refreshGitStatus()
            self.error = "✓ Stash 저장됨"
        } catch {
            self.error = "Stash 실패: \(error.localizedDescription)"
        }
    }

    public func gitApplyStash(_ ref: String) async {
        guard let manager = await makeGitManager() else { return }
        do {
            try await manager.applyStash(ref)
            await refreshGitStatus()
        } catch {
            self.error = "Stash 적용 실패: \(error.localizedDescription)"
        }
    }

    public func gitPopStash(_ ref: String) async {
        guard let manager = await makeGitManager() else { return }
        do {
            try await manager.popStash(ref)
            await refreshGitStatus()
        } catch {
            self.error = "Stash pop 실패: \(error.localizedDescription)"
        }
    }

    public func gitDropStash(_ ref: String) async {
        guard let manager = await makeGitManager() else { return }
        do {
            try await manager.dropStash(ref)
        } catch {
            self.error = "Stash 삭제 실패: \(error.localizedDescription)"
        }
    }

    // MARK: - ADR-081 Phase 2 — AI-generated commit message

    /// 현재 git diff를 Claude에 보내 commit message 생성.
    /// `ChildClaudeProcess` 활용 — 격리 호출, costTracker 자동 추적.
    public func generateCommitMessageWithAI() async -> String? {
        guard let ws = workspaces.first(where: { $0.id == selectedWorkspaceId }) else { return nil }
        let url = URL(fileURLWithPath: ws.directoryPath)
        let runner = GitRunner(workspaceURL: url)
        guard await runner.isRepository() else { return nil }
        let diff = (try? await runner.diff()) ?? ""
        // diff가 너무 크면 truncate (token cost 방지)
        let truncated = String(diff.prefix(8000))
        guard !truncated.isEmpty else { return nil }
        guard let child = childProcess else { return nil }

        let prompt = """
        You are a Git commit message generator following Conventional Commits style.
        Read this diff and produce ONE concise Korean commit message (≤ 72 chars title).

        Format:
        - Use prefix: feat: / fix: / chore: / refactor: / docs: / test:
        - Title in Korean, ≤ 72 chars
        - NO body, NO multi-line, NO Co-Authored-By footer (system adds it)
        - Output ONLY the title line, nothing else

        Diff:
        ```
        \(truncated)
        ```
        """
        do {
            let output = try await child.runOnce(
                prompt: prompt,
                in: ws,
                agent: ws.agentKind,
                purpose: .rehearsal,  // 격리 호출 (메인 conversation 안 건드림)
                timeoutSeconds: 30,
                overrideSettings: nil
            )
            let message = output.resultText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\n")
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return message.isEmpty ? nil : message
        } catch {
            self.error = "AI 메시지 생성 실패: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - ADR-081 Phase 3 — GitHub PR creation

    /// 현재 워크스페이스의 GitHub gh runner.
    public func makeGitHubRunner() async -> GitHubCLIRunner? {
        guard let ws = workspaces.first(where: { $0.id == selectedWorkspaceId }) else { return nil }
        let url = URL(fileURLWithPath: ws.directoryPath)
        return GitHubCLIRunner(
            workspaceURL: url,
            runner: GitHubCLIRunner.makeRunWithCwd(url)
        )
    }

    /// Push + PR 생성 (Claude Code 패턴 — 한 번에).
    public func createPullRequest(title: String, body: String?, draft: Bool = false) async {
        gitOperationInProgress = true
        defer { gitOperationInProgress = false }
        // 1. Push 먼저
        guard let manager = await makeGitManager() else {
            self.error = "Git 저장소가 아니에요"
            return
        }
        do {
            try await manager.push(force: false)
        } catch {
            self.error = "Push 실패: \(error.localizedDescription)"
            return
        }
        // 2. PR 생성
        guard let gh = await makeGitHubRunner() else {
            self.error = "gh CLI를 찾을 수 없어요"
            return
        }
        do {
            let url = try await gh.createPullRequest(title: title, body: body, draft: draft)
            self.error = "✓ PR 생성됨: \(url)"
            // 사용자가 URL을 클릭하기 쉽게 — 자동으로 brower 안 열기 (privacy)
        } catch {
            self.error = "PR 생성 실패: \(error.localizedDescription)"
        }
    }

    /// 현재 브랜치에 이미 PR이 있는지 확인.
    public func existingPRForCurrentBranch() async -> String? {
        guard let gh = await makeGitHubRunner() else { return nil }
        return try? await gh.existingPullRequest()
    }

    // MARK: - ADR-082 Phase 2 — PR review

    public func loadPullRequestDetails() async -> PullRequestDetails? {
        guard let gh = await makeGitHubRunner() else { return nil }
        return try? await gh.pullRequestDetails()
    }

    // MARK: - ADR-082 Phase 3 — GitHub Actions

    public func loadRecentWorkflowRuns(limit: Int = 5) async -> [WorkflowRun] {
        guard let gh = await makeGitHubRunner() else { return [] }
        return (try? await gh.recentWorkflowRuns(limit: limit)) ?? []
    }

    /// 시스템 default browser로 URL 열기 (Apple HIG 표준).
    public func openInBrowser(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - ADR-082 Phase 4 — Rebase

    public func gitRecentCommits(limit: Int) async -> [CommitInfo] {
        guard let manager = await makeGitManager() else { return [] }
        return (try? await manager.recentCommits(limit: limit)) ?? []
    }

    public func gitRebase(count: Int, actions: [String: RebaseAction]) async {
        guard let manager = await makeGitManager() else { return }
        gitOperationInProgress = true
        defer { gitOperationInProgress = false }
        do {
            try await manager.rebase(count: count, actions: actions)
            await refreshGitStatus()
            self.error = "✓ Rebase 완료"
        } catch {
            self.error = "Rebase 실패: \(error.localizedDescription) — `git rebase --abort`로 취소 가능"
        }
    }

    public func gitRebaseAbort() async {
        guard let manager = await makeGitManager() else { return }
        do {
            try await manager.rebaseAbort()
            await refreshGitStatus()
        } catch {
            self.error = "Rebase abort 실패: \(error.localizedDescription)"
        }
    }

    // MARK: - ADR-082 Phase 5 — CodeOwners

    // MARK: - ADR-083 Phase 1 — Conflict resolution

    public func gitConflictedFiles() async -> [String] {
        guard let manager = await makeGitManager() else { return [] }
        return (try? await manager.conflictedFiles()) ?? []
    }

    public func gitConflictBlocks(in path: String) async -> [ConflictBlock] {
        guard let manager = await makeGitManager() else { return [] }
        return (try? await manager.conflictBlocks(in: path)) ?? []
    }

    public func gitResolveConflict(path: String, strategy: ConflictResolution) async {
        guard let manager = await makeGitManager() else { return }
        do {
            try await manager.resolveConflict(path: path, strategy: strategy)
            await refreshGitStatus()
            self.error = "✓ 충돌 해결: \(path) (\(strategy.displayName))"
        } catch {
            self.error = "충돌 해결 실패: \(error.localizedDescription)"
        }
    }

    public func gitMergeAbort() async {
        guard let manager = await makeGitManager() else { return }
        do {
            try await manager.mergeAbort()
            await refreshGitStatus()
            self.error = "✓ Merge 취소됨"
        } catch {
            self.error = "Merge abort 실패: \(error.localizedDescription)"
        }
    }

    // MARK: - ADR-083 Phase 2 — Cherry-pick

    public func gitCommitsOnBranch(_ branch: String, limit: Int = 30) async -> [CommitInfo] {
        guard let manager = await makeGitManager() else { return [] }
        return (try? await manager.commitsOnBranch(branch, limit: limit)) ?? []
    }

    public func gitCherryPick(_ sha: String) async {
        guard let manager = await makeGitManager() else { return }
        do {
            try await manager.cherryPick(sha)
            await refreshGitStatus()
            self.error = "✓ Cherry-pick 완료: \(sha)"
        } catch {
            self.error = "Cherry-pick 실패: \(error.localizedDescription) — 충돌 발생 시 충돌 해결 sheet 사용"
        }
    }

    // MARK: - ADR-083 Phase 3 — PR comment

    public func commentOnCurrentPR(body: String) async {
        guard let gh = await makeGitHubRunner() else { return }
        do {
            try await gh.commentOnPullRequest(body: body)
            self.error = "✓ PR 코멘트 추가됨"
        } catch {
            self.error = "PR 코멘트 실패: \(error.localizedDescription)"
        }
    }

    // MARK: - ADR-083 Phase 4 — Workflow re-run + Repo insights

    public func rerunWorkflow(runId: Int, failedOnly: Bool = false) async {
        guard let gh = await makeGitHubRunner() else { return }
        do {
            try await gh.rerunWorkflow(runId: runId, failedOnly: failedOnly)
            self.error = "✓ Workflow 재실행 시작"
        } catch {
            self.error = "Workflow 재실행 실패: \(error.localizedDescription)"
        }
    }

    public func loadTopContributors(limit: Int = 5) async -> [Contributor] {
        guard let gh = await makeGitHubRunner() else { return [] }
        return (try? await gh.topContributors(limit: limit)) ?? []
    }

    public func loadRepoInfo() async -> RepoInfo? {
        guard let gh = await makeGitHubRunner() else { return nil }
        return try? await gh.repoInfo()
    }

    /// 변경된 파일들의 suggested reviewers (`.github/CODEOWNERS` 기반).
    public func suggestedReviewers() async -> Set<String> {
        guard let ws = workspaces.first(where: { $0.id == selectedWorkspaceId }) else { return [] }
        let url = URL(fileURLWithPath: ws.directoryPath)
        let runner = GitRunner(workspaceURL: url)
        guard await runner.isRepository() else { return [] }
        let manager = GitBranchManager(runner: runner)
        let changedFiles = (try? await runner.changedFiles()) ?? []
        let paths = changedFiles.map { $0.path }
        return (try? await manager.suggestedReviewers(for: paths)) ?? []
    }

    // ADR-128 — `private` 제거: AppModel+Workspace.swift의 exportArchiveToFile()에서 cross-file 접근.
    static func exportTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: Date())
    }

    /// 폴더 삭제 (안의 워크스페이스는 uncategorized로 이동, 삭제 X).
    public func deleteFolder(id: UUID) async {
        preferences.workspaceFolders.removeAll { $0.id == id }
        await savePreferences()
    }

    /// 폴더 expand/collapse 토글.
    public func toggleFolderExpansion(id: UUID) async {
        guard let idx = preferences.workspaceFolders.firstIndex(where: { $0.id == id }) else {
            return
        }
        preferences.workspaceFolders[idx].isExpanded.toggle()
        await savePreferences()
    }

    /// 워크스페이스를 폴더로 이동 (기존 폴더에서 자동 제거 후 새 폴더에 추가).
    /// folderId가 nil이면 모든 폴더에서 제거 (uncategorized로).
    public func moveWorkspace(_ workspaceId: UUID, toFolder folderId: UUID?) async {
        // 기존 모든 폴더에서 제거
        for idx in preferences.workspaceFolders.indices {
            preferences.workspaceFolders[idx].workspaceIds.removeAll { $0 == workspaceId }
        }
        // 새 폴더에 추가 (folderId가 있으면)
        if let folderId,
           let idx = preferences.workspaceFolders.firstIndex(where: { $0.id == folderId }) {
            preferences.workspaceFolders[idx].workspaceIds.append(workspaceId)
        }
        await savePreferences()
    }

    public func selectWorkspace(_ id: UUID?) async {
        await teardownCurrentSession()
        guard let id, let workspace = workspaces.first(where: { $0.id == id }) else {
            return
        }
        await startSession(in: workspace)
        // ADR-079 Phase 4 — 워크스페이스 진입 시 git status 자동 fetch
        await refreshGitStatus()
    }

    private func startSession(in workspace: Workspace) async {
        do {
            let session = Session(workspaceId: workspace.id)
            try await sessionStore.create(session)
            currentSession = session
            messages = []
            currentSessionUsage = .zero

            let agentAdapter = adapter(for: workspace)
            let claudeSession = try await agentAdapter.spawn(in: workspace)
            currentClaudeSession = claudeSession

            let captured = claudeSession
            streamConsumeTask = Task { [weak self] in
                await self?.consumeStream(captured)
            }

            // 멀티-pane: workspace 활성화 시 default primary pane 1개 자동 생성 (ADR-030)
            ensurePrimaryPane(for: workspace, session: claudeSession)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
