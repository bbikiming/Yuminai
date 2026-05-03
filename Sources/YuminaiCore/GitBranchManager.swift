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
