import Foundation

/// **ADR-079 Phase 4** — Git 브랜치 관리 + 자동 커밋 (Claude Code 패턴 단순화).
///
/// ## 디자인 철학 (Claude Code 영감)
/// Claude Code의 git workflow는 다음 단계:
/// 1. 작업 시작 시 브랜치 확인 / 새 브랜치 자동 생성
/// 2. 작업 중 변경된 파일 추적 (modified/added/deleted)
/// 3. 작업 완료 시 commit message 자동 생성 + 사용자 confirm
/// 4. Co-Authored-By 푸터 자동 추가
///
/// **Yuminai 단순화**: 4단계 → 3단계로 압축
/// - **Status**: branch + dirty state (실시간)
/// - **Switch**: 브랜치 전환 + 새 브랜치 (popover)
/// - **Auto-commit**: 사용자 1-click → AI가 message 생성 + commit
public actor GitBranchManager {
    public let runner: GitRunner

    public init(runner: GitRunner) {
        self.runner = runner
    }

    // MARK: - Status

    /// 현재 브랜치 이름 (HEAD가 detached면 "detached HEAD").
    public func currentBranch() async throws -> String {
        let result = try await runner.run(["symbolic-ref", "--short", "HEAD"])
        if result.success {
            return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // detached HEAD — short SHA 반환
        let sha = try await runner.run(["rev-parse", "--short", "HEAD"])
        if sha.success {
            return "detached @ \(sha.stdout.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        return "unknown"
    }

    /// 모든 local branch 목록 (current 포함, 정렬: 최근 commit 순).
    public func localBranches() async throws -> [BranchInfo] {
        let format = "%(refname:short)|%(committerdate:relative)|%(HEAD)"
        let raw = try await runner.runOrThrow(["branch", "--list", "--format=\(format)", "--sort=-committerdate"])
        return raw.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { return nil }
            let name = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let relative = String(parts[1]).trimmingCharacters(in: .whitespaces)
            let isCurrent = !String(parts[2]).trimmingCharacters(in: .whitespaces).isEmpty
            return BranchInfo(name: name, lastCommitRelative: relative, isCurrent: isCurrent)
        }
    }

    /// Working tree status — 변경 여부 빠르게 판별.
    /// `git status --porcelain` 1줄 이상 = dirty.
    public func isDirty() async throws -> Bool {
        let result = try await runner.run(["status", "--porcelain"])
        guard result.success else { return false }
        return !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 변경된 파일 통계 (modified / added / deleted / untracked count).
    public func dirtyStats() async throws -> DirtyStats {
        let files = try await runner.changedFiles()
        var modified = 0, added = 0, deleted = 0, untracked = 0
        for file in files {
            switch file.status {
            case .modified: modified += 1
            case .added: added += 1
            case .deleted: deleted += 1
            case .untracked: untracked += 1
            case .renamed, .copied, .unknown: modified += 1
            }
        }
        return DirtyStats(modified: modified, added: added, deleted: deleted, untracked: untracked)
    }

    // MARK: - Branch operations

    /// 브랜치 전환 (uncommitted changes가 있으면 stash 후 switch).
    public func switchBranch(_ name: String, autoStash: Bool = true) async throws {
        if autoStash, try await isDirty() {
            _ = try? await runner.run(["stash", "push", "-u", "-m", "Yuminai auto-stash before branch switch"])
        }
        let result = try await runner.run(["checkout", name])
        if !result.success {
            throw GitRunner.GitError.commandFailed(args: ["checkout", name], exitCode: result.exitCode, stderr: result.stderr)
        }
    }

    /// 새 브랜치 생성 + 전환 (default base = current branch).
    public func createBranch(_ name: String, fromBase: String? = nil) async throws {
        var args = ["checkout", "-b", name]
        if let base = fromBase { args.append(base) }
        let result = try await runner.run(args)
        if !result.success {
            throw GitRunner.GitError.commandFailed(args: args, exitCode: result.exitCode, stderr: result.stderr)
        }
    }

    // MARK: - Commit

    /// 모든 변경사항을 commit (auto-stage all + commit with message).
    /// **Claude Code 패턴**: Co-Authored-By 푸터 자동 추가.
    public func commitAll(
        message: String,
        coAuthorName: String = "Claude (Yuminai)",
        coAuthorEmail: String = "noreply@anthropic.com"
    ) async throws -> String {
        // 1. Stage all (untracked 포함)
        _ = try await runner.run(["add", "--all"])
        // 2. Commit with footer
        let footer = "\n\nCo-Authored-By: \(coAuthorName) <\(coAuthorEmail)>"
        let fullMessage = message.trimmingCharacters(in: .whitespacesAndNewlines) + footer
        let result = try await runner.run(["commit", "-m", fullMessage])
        if !result.success {
            throw GitRunner.GitError.commandFailed(args: ["commit", "-m", "..."], exitCode: result.exitCode, stderr: result.stderr)
        }
        // 3. SHA 반환
        let sha = try await runner.run(["rev-parse", "--short", "HEAD"])
        return sha.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Remote operations (ADR-081 Phase 1)

    /// 원격 저장소 정보 (origin URL).
    public func originURL() async throws -> String? {
        let result = try await runner.run(["remote", "get-url", "origin"])
        guard result.success else { return nil }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 현재 브랜치의 upstream tracking 정보 (ahead/behind count).
    public func upstreamStatus() async throws -> UpstreamStatus? {
        let upstreamResult = try await runner.run(["rev-parse", "--abbrev-ref", "@{upstream}"])
        guard upstreamResult.success else { return nil }
        let upstream = upstreamResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        // ahead/behind count
        let countResult = try await runner.run(["rev-list", "--left-right", "--count", "HEAD...@{upstream}"])
        guard countResult.success else { return UpstreamStatus(upstreamName: upstream, ahead: 0, behind: 0) }
        let parts = countResult.stdout.split(separator: "\t").compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let ahead = parts.first ?? 0
        let behind = parts.count > 1 ? parts[1] : 0
        return UpstreamStatus(upstreamName: upstream, ahead: ahead, behind: behind)
    }

    /// 원격에서 fetch (실제 변경 안 함, ahead/behind 갱신용).
    public func fetch() async throws {
        let result = try await runner.run(["fetch", "--all", "--prune"])
        if !result.success {
            throw GitRunner.GitError.commandFailed(args: ["fetch"], exitCode: result.exitCode, stderr: result.stderr)
        }
    }

    /// pull (rebase 모드 — clean history). uncommitted changes 있으면 throw.
    public func pull(rebase: Bool = true) async throws {
        if try await isDirty() {
            throw GitPullError.dirtyTree
        }
        var args = ["pull"]
        if rebase { args.append("--rebase") }
        let result = try await runner.run(args)
        if !result.success {
            throw GitRunner.GitError.commandFailed(args: args, exitCode: result.exitCode, stderr: result.stderr)
        }
    }

    /// push (현재 브랜치 → upstream). 처음이면 -u 자동 추가.
    public func push(force: Bool = false) async throws {
        // upstream 있는지 확인
        let hasUpstream = (try? await runner.run(["rev-parse", "--abbrev-ref", "@{upstream}"]).success) ?? false
        var args = ["push"]
        if force { args.append("--force-with-lease") }  // safer than --force
        if !hasUpstream {
            // 처음 push — upstream 자동 set
            let branch = try await currentBranch()
            args.append("-u")
            args.append("origin")
            args.append(branch)
        }
        let result = try await runner.run(args)
        if !result.success {
            throw GitRunner.GitError.commandFailed(args: args, exitCode: result.exitCode, stderr: result.stderr)
        }
    }

    // MARK: - Stash (ADR-081 Phase 4)

    /// Stash list (사용자가 명시적으로 만든 것 + auto-stash 모두).
    public func stashes() async throws -> [StashInfo] {
        let format = "%h|%gd|%s|%cr"
        let raw = try await runner.runOrThrow(["stash", "list", "--format=\(format)"])
        return raw.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false)
            guard parts.count == 4 else { return nil }
            return StashInfo(
                shortSha: String(parts[0]),
                ref: String(parts[1]),
                message: String(parts[2]),
                relativeDate: String(parts[3])
            )
        }
    }

    /// Stash 적용 (변경사항 working tree로 복원, stash entry는 유지).
    public func applyStash(_ ref: String) async throws {
        let result = try await runner.run(["stash", "apply", ref])
        if !result.success {
            throw GitRunner.GitError.commandFailed(args: ["stash", "apply", ref], exitCode: result.exitCode, stderr: result.stderr)
        }
    }

    /// Stash 적용 + 삭제 (pop).
    public func popStash(_ ref: String) async throws {
        let result = try await runner.run(["stash", "pop", ref])
        if !result.success {
            throw GitRunner.GitError.commandFailed(args: ["stash", "pop", ref], exitCode: result.exitCode, stderr: result.stderr)
        }
    }

    /// Stash 삭제.
    public func dropStash(_ ref: String) async throws {
        let result = try await runner.run(["stash", "drop", ref])
        if !result.success {
            throw GitRunner.GitError.commandFailed(args: ["stash", "drop", ref], exitCode: result.exitCode, stderr: result.stderr)
        }
    }

    /// 현재 변경사항을 명시적으로 stash (사용자 입력 메시지 포함).
    public func createStash(message: String) async throws {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        var args = ["stash", "push", "-u"]
        if !trimmed.isEmpty {
            args.append(contentsOf: ["-m", trimmed])
        }
        let result = try await runner.run(args)
        if !result.success {
            throw GitRunner.GitError.commandFailed(args: args, exitCode: result.exitCode, stderr: result.stderr)
        }
    }

    // MARK: - Conflict detection (ADR-081 Phase 4)

    /// 현재 working tree에 conflict 있는 파일 목록.
    public func conflictedFiles() async throws -> [String] {
        let result = try await runner.run(["diff", "--name-only", "--diff-filter=U"])
        guard result.success else { return [] }
        return result.stdout.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - ADR-083 Phase 1 — Conflict resolution

    /// 특정 conflicted 파일을 한 쪽 버전으로 resolve.
    /// - `ours`: HEAD (현재 브랜치) 채택
    /// - `theirs`: incoming branch 채택
    public func resolveConflict(path: String, strategy: ConflictResolution) async throws {
        let arg: String
        switch strategy {
        case .ours: arg = "--ours"
        case .theirs: arg = "--theirs"
        }
        let checkout = try await runner.run(["checkout", arg, "--", path])
        if !checkout.success {
            throw GitRunner.GitError.commandFailed(args: ["checkout", arg, "--", path], exitCode: checkout.exitCode, stderr: checkout.stderr)
        }
        let add = try await runner.run(["add", "--", path])
        if !add.success {
            throw GitRunner.GitError.commandFailed(args: ["add", "--", path], exitCode: add.exitCode, stderr: add.stderr)
        }
    }

    /// Conflict 파일 안의 conflict block들 파싱 (시각화용).
    public func conflictBlocks(in path: String) async throws -> [ConflictBlock] {
        let url = await runner.workspaceURL.appendingPathComponent(path)
        guard let data = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return ConflictBlockParser.parse(data)
    }

    /// merge --abort (conflict 시 사용자 escape).
    public func mergeAbort() async throws {
        let result = try await runner.run(["merge", "--abort"])
        if !result.success {
            throw GitRunner.GitError.commandFailed(args: ["merge", "--abort"], exitCode: result.exitCode, stderr: result.stderr)
        }
    }

    // MARK: - ADR-083 Phase 2 — Cherry-pick

    /// 특정 commit을 현재 브랜치로 cherry-pick.
    public func cherryPick(_ sha: String) async throws {
        let result = try await runner.run(["cherry-pick", sha])
        if !result.success {
            throw GitRunner.GitError.commandFailed(args: ["cherry-pick", sha], exitCode: result.exitCode, stderr: result.stderr)
        }
    }

    /// 다른 브랜치의 최근 commit 목록 (cherry-pick source 선택용).
    public func commitsOnBranch(_ branch: String, limit: Int = 30) async throws -> [CommitInfo] {
        let format = "%h|%s|%cr|%an"
        let raw = try await runner.runOrThrow(["log", branch, "--format=\(format)", "-n", "\(limit)", "--no-merges"])
        return raw.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false)
            guard parts.count == 4 else { return nil }
            return CommitInfo(
                shortSha: String(parts[0]),
                message: String(parts[1]),
                relativeDate: String(parts[2]),
                authorName: String(parts[3])
            )
        }
    }

    // MARK: - ADR-082 Phase 4 — Rebase 단순화 (reword/drop/squash)

    /// 마지막 N개 commit을 rebase action 적용.
    /// 사용자가 한 번에 하나만 선택 (interactive rebase의 단순화).
    /// - Parameters:
    ///   - count: rebase 대상 commit 수 (HEAD~N)
    ///   - actions: 각 commit별 [shortSha: action]. 누락된 commit은 "pick" (변경 없음).
    /// - Note: 충돌 발생 시 throw — 사용자가 외부 도구로 해결 후 `git rebase --continue` 필요.
    public func rebase(count: Int, actions: [String: RebaseAction]) async throws {
        guard count > 0 else { return }
        // 1. 대상 commit 목록 fetch (오래된 것부터, rebase script 순서)
        let commits = try await recentCommits(limit: count)
        guard commits.count == count else {
            throw GitRunner.GitError.commandFailed(args: ["rebase"], exitCode: 1, stderr: "expected \(count) commits, got \(commits.count)")
        }
        // 2. rebase script 작성 (rebase는 오래된 commit이 위)
        let script = commits.reversed().map { commit -> String in
            let action = actions[commit.shortSha] ?? .pick
            return "\(action.rawValue) \(commit.shortSha) \(commit.message)"
        }.joined(separator: "\n")
        // 3. GIT_SEQUENCE_EDITOR로 script 강제 주입 + GIT_EDITOR로 reword 메시지 자동 처리
        // 단순화: reword는 메시지 그대로 유지 (commit --amend 안 함)
        let scriptPath = "/tmp/yuminai-rebase-\(UUID().uuidString).txt"
        try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: scriptPath) }

        // GIT_SEQUENCE_EDITOR=cat $scriptPath  → script를 그대로 사용
        // 환경변수로 inline script 전달 — `cp $scriptPath` editor stub
        let editorScript = "/bin/bash -c 'cp \(scriptPath) \"$1\"' --"
        var env = ProcessInfo.processInfo.environment
        env["GIT_SEQUENCE_EDITOR"] = editorScript
        env["GIT_EDITOR"] = "true"  // reword 메시지 자동 confirm (변경 없음)

        // GitRunner의 Run typealias는 env 지원 안 함 → 직접 Process 호출
        let process = Process()
        process.executableURL = await runner.gitPath
        process.arguments = ["-C", await runner.workspaceURL.path, "rebase", "-i", "HEAD~\(count)"]
        process.environment = env
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                process.waitUntilExit()
                cont.resume()
            }
        }
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw GitRunner.GitError.commandFailed(
                args: ["rebase", "-i", "HEAD~\(count)"],
                exitCode: process.terminationStatus,
                stderr: stderr
            )
        }
    }

    /// rebase abort (충돌 발생 시 사용자 escape).
    public func rebaseAbort() async throws {
        let result = try await runner.run(["rebase", "--abort"])
        if !result.success {
            throw GitRunner.GitError.commandFailed(args: ["rebase", "--abort"], exitCode: result.exitCode, stderr: result.stderr)
        }
    }

    // MARK: - ADR-082 Phase 5 — CodeOwners

    /// `.github/CODEOWNERS` 파싱 → 변경된 파일별 owner.
    /// - Returns: owner login set (PR 생성 시 자동 reviewer 추가용).
    public func suggestedReviewers(for paths: [String]) async throws -> Set<String> {
        let codeownersPaths = [".github/CODEOWNERS", "CODEOWNERS", "docs/CODEOWNERS"]
        var content: String?
        let baseURL = await runner.workspaceURL
        for relPath in codeownersPaths {
            let url = baseURL.appendingPathComponent(relPath)
            if let data = try? String(contentsOf: url, encoding: .utf8) {
                content = data
                break
            }
        }
        guard let codeowners = content else { return [] }
        return CodeOwnersParser.match(codeowners: codeowners, paths: paths)
    }

    /// 최근 commit 목록 (HEAD ~ N개).
    public func recentCommits(limit: Int = 10) async throws -> [CommitInfo] {
        let format = "%h|%s|%cr|%an"
        let raw = try await runner.runOrThrow(["log", "--format=\(format)", "-n", "\(limit)"])
        return raw.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false)
            guard parts.count == 4 else { return nil }
            return CommitInfo(
                shortSha: String(parts[0]),
                message: String(parts[1]),
                relativeDate: String(parts[2]),
                authorName: String(parts[3])
            )
        }
    }
}

// MARK: - Data types

public struct BranchInfo: Sendable, Hashable, Identifiable {
    public let name: String
    public let lastCommitRelative: String
    public let isCurrent: Bool

    public var id: String { name }
}

public struct DirtyStats: Sendable, Hashable {
    public let modified: Int
    public let added: Int
    public let deleted: Int
    public let untracked: Int

    public var total: Int { modified + added + deleted + untracked }
    public var isEmpty: Bool { total == 0 }

    public init(modified: Int, added: Int, deleted: Int, untracked: Int) {
        self.modified = modified
        self.added = added
        self.deleted = deleted
        self.untracked = untracked
    }

    /// 한국어 요약 (e.g., "수정 3, 추가 1, 추적 안 됨 2").
    public var summary: String {
        var parts: [String] = []
        if modified > 0 { parts.append("수정 \(modified)") }
        if added > 0 { parts.append("추가 \(added)") }
        if deleted > 0 { parts.append("삭제 \(deleted)") }
        if untracked > 0 { parts.append("추적 안 됨 \(untracked)") }
        return parts.isEmpty ? "변경 없음" : parts.joined(separator: ", ")
    }
}

public struct CommitInfo: Sendable, Hashable, Identifiable {
    public let shortSha: String
    public let message: String
    public let relativeDate: String
    public let authorName: String

    public var id: String { shortSha }
}

/// **ADR-081 Phase 1** — 원격 브랜치 vs 로컬 브랜치 동기화 상태.
public struct UpstreamStatus: Sendable, Hashable {
    public let upstreamName: String
    /// 로컬이 원격보다 ahead (push 가능).
    public let ahead: Int
    /// 로컬이 원격보다 behind (pull 필요).
    public let behind: Int

    public init(upstreamName: String, ahead: Int, behind: Int) {
        self.upstreamName = upstreamName
        self.ahead = ahead
        self.behind = behind
    }

    public var isInSync: Bool { ahead == 0 && behind == 0 }
    public var summary: String {
        if isInSync { return "동기화됨" }
        var parts: [String] = []
        if ahead > 0 { parts.append("↑\(ahead) push 대기") }
        if behind > 0 { parts.append("↓\(behind) pull 필요") }
        return parts.joined(separator: ", ")
    }
}

/// **ADR-081 Phase 4** — Stash 항목.
public struct StashInfo: Sendable, Hashable, Identifiable {
    public let shortSha: String
    /// stash@{0}, stash@{1} 등.
    public let ref: String
    public let message: String
    public let relativeDate: String

    public var id: String { ref }
}

/// **ADR-081 Phase 1** — Pull 시 발생할 수 있는 사용자 친화적 에러.
public enum GitPullError: Error, LocalizedError {
    case dirtyTree

    public var errorDescription: String? {
        switch self {
        case .dirtyTree:
            return "변경된 파일이 있어요. 먼저 커밋하거나 stash로 보관한 뒤 pull하세요."
        }
    }
}

// MARK: - ADR-082 Phase 4-5 — Rebase + CodeOwners types

// MARK: - ADR-083 Phase 1 — Conflict resolution types

/// Conflict 한쪽 채택 strategy.
public enum ConflictResolution: String, Sendable, CaseIterable, Identifiable {
    /// HEAD (현재 브랜치) 채택.
    case ours
    /// Incoming branch 채택.
    case theirs

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ours: return "내 변경 (HEAD)"
        case .theirs: return "받은 변경 (incoming)"
        }
    }
}

/// 단일 conflict block (파일 안 `<<<<<<< / ======= / >>>>>>>` 한 묶음).
public struct ConflictBlock: Sendable, Hashable, Identifiable {
    public let id: Int  // index 순서
    public let oursLines: [String]
    public let theirsLines: [String]
    /// 1-based start line (file 안 `<<<<<<<` 위치).
    public let startLine: Int

    public init(id: Int, oursLines: [String], theirsLines: [String], startLine: Int) {
        self.id = id
        self.oursLines = oursLines
        self.theirsLines = theirsLines
        self.startLine = startLine
    }
}

/// Conflict marker 파서 (`<<<<<<<` ~ `=======` ~ `>>>>>>>`).
public enum ConflictBlockParser {
    public static func parse(_ content: String) -> [ConflictBlock] {
        var blocks: [ConflictBlock] = []
        let lines = content.components(separatedBy: "\n")
        var i = 0
        var blockId = 0
        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("<<<<<<<") {
                let startLine = i + 1  // 1-based
                var ours: [String] = []
                var theirs: [String] = []
                var j = i + 1
                // ======= 까지
                while j < lines.count, !lines[j].hasPrefix("=======") {
                    ours.append(lines[j])
                    j += 1
                }
                if j >= lines.count { break }  // malformed
                j += 1  // skip =======
                while j < lines.count, !lines[j].hasPrefix(">>>>>>>") {
                    theirs.append(lines[j])
                    j += 1
                }
                if j >= lines.count { break }  // malformed
                blocks.append(ConflictBlock(id: blockId, oursLines: ours, theirsLines: theirs, startLine: startLine))
                blockId += 1
                i = j + 1  // skip >>>>>>>
            } else {
                i += 1
            }
        }
        return blocks
    }
}

/// **ADR-082 Phase 4** — Interactive rebase action (단순화 — 5개만).
public enum RebaseAction: String, Sendable, CaseIterable, Identifiable, Hashable {
    /// 그대로 유지 (default).
    case pick = "pick"
    /// 메시지 변경 (commit 자체는 유지).
    case reword = "reword"
    /// 직전 commit과 병합 (이 commit message는 사라짐).
    case squash = "squash"
    /// 직전 commit과 병합 (메시지 X).
    case fixup = "fixup"
    /// commit 삭제 (history에서 제거).
    case drop = "drop"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .pick: return "유지"
        case .reword: return "메시지 변경"
        case .squash: return "위와 합치기"
        case .fixup: return "위와 합치기 (메시지 버림)"
        case .drop: return "삭제"
        }
    }

    public var hint: String {
        switch self {
        case .pick: return "이 commit을 그대로 유지합니다."
        case .reword: return "commit message만 변경합니다."
        case .squash: return "직전 commit과 병합 + 새 message 작성."
        case .fixup: return "직전 commit과 병합 (이 commit message 버림)."
        case .drop: return "이 commit을 history에서 완전히 제거 (위험)."
        }
    }

    public var iconName: String {
        switch self {
        case .pick: return "circle"
        case .reword: return "pencil"
        case .squash: return "arrow.up.to.line.compact"
        case .fixup: return "arrow.up.to.line"
        case .drop: return "trash"
        }
    }
}


// MARK: - Auto-commit message generation (ADR-079 Phase 5)

/// **ADR-079 Phase 5** — DirtyStats 기반 commit message 자동 생성.
/// 사용자가 입력 안 했을 때의 fallback (Claude Code의 conventional commit 패턴).
public enum AutoCommitMessageGenerator {
    /// 변경 내용 기반 commit message (conventional commits 스타일).
    /// e.g., "chore: 5 files modified" / "feat: 3 files added"
    public static func generate(stats: DirtyStats, agent: String = "Yuminai") -> String {
        if stats.isEmpty { return "chore: no changes" }
        // 단일 변경 유형이면 명확한 prefix
        if stats.added > 0 && stats.modified == 0 && stats.deleted == 0 {
            return "feat: \(stats.added)개 파일 추가"
        }
        if stats.deleted > 0 && stats.modified == 0 && stats.added == 0 {
            return "chore: \(stats.deleted)개 파일 삭제"
        }
        if stats.modified > 0 && stats.added == 0 && stats.deleted == 0 {
            return "fix: \(stats.modified)개 파일 수정"
        }
        // 혼합
        return "chore: \(stats.summary)"
    }
}
