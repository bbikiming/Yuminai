import Foundation

/// **ADR-081 Phase 3 + ADR-082 Phase 2-3** — GitHub `gh` CLI 통합.
public actor GitHubCLIRunner {
    public typealias Run = @Sendable (URL, [String]) async throws -> ProcessResult

    public struct ProcessResult: Sendable, Equatable {
        public let exitCode: Int32
        public let stdout: String
        public let stderr: String

        public init(exitCode: Int32, stdout: String, stderr: String) {
            self.exitCode = exitCode
            self.stdout = stdout
            self.stderr = stderr
        }

        public var success: Bool { exitCode == 0 }
    }

    public enum GitHubError: Error, LocalizedError, Sendable {
        case ghNotInstalled
        case notAuthenticated
        case commandFailed(args: [String], exitCode: Int32, stderr: String)

        public var errorDescription: String? {
            switch self {
            case .ghNotInstalled:
                return "gh CLI가 설치되지 않았어요. `brew install gh` 후 다시 시도하세요."
            case .notAuthenticated:
                return "GitHub 인증이 필요해요. 터미널에서 `gh auth login` 실행 후 다시 시도하세요."
            case .commandFailed(let args, let code, let stderr):
                let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let reason = trimmed.isEmpty ? "exit \(code)" : trimmed
                return "gh \(args.joined(separator: " ")) 실패: \(reason)"
            }
        }
    }

    public let ghPath: URL
    public let workspaceURL: URL
    private let runner: Run

    public init(
        ghPath: URL = GitHubCLIRunner.defaultGhPath(),
        workspaceURL: URL,
        runner: @escaping Run = GitHubCLIRunner.defaultRun
    ) {
        self.ghPath = ghPath
        self.workspaceURL = workspaceURL
        self.runner = runner
    }

    public static func defaultGhPath() -> URL {
        let candidates = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: candidates[0])
    }

    /// gh CLI 설치 여부.
    public func isInstalled() async -> Bool {
        FileManager.default.isExecutableFile(atPath: ghPath.path)
    }

    /// 인증 상태 확인 (`gh auth status`).
    public func isAuthenticated() async -> Bool {
        guard await isInstalled() else { return false }
        let result = (try? await runner(ghPath, ["auth", "status"])) ?? ProcessResult(exitCode: 1, stdout: "", stderr: "")
        return result.success
    }

    /// 현재 브랜치로 PR 생성 (push 자동 포함).
    public func createPullRequest(title: String, body: String?, draft: Bool = false) async throws -> String {
        guard await isInstalled() else { throw GitHubError.ghNotInstalled }
        guard await isAuthenticated() else { throw GitHubError.notAuthenticated }

        var args = ["pr", "create", "--title", title]
        if let body, !body.isEmpty {
            args.append("--body")
            args.append(body)
        } else {
            args.append("--body")
            args.append("")
        }
        if draft { args.append("--draft") }

        let result = try await runner(ghPath, args)
        if !result.success {
            throw GitHubError.commandFailed(args: args, exitCode: result.exitCode, stderr: result.stderr)
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 현재 브랜치 PR 존재 여부 (있으면 URL 반환).
    public func existingPullRequest() async throws -> String? {
        guard await isInstalled() else { return nil }
        let result = try await runner(ghPath, ["pr", "view", "--json", "url", "-q", ".url"])
        guard result.success else { return nil }
        let url = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return url.isEmpty ? nil : url
    }

    // MARK: - ADR-082 Phase 2 — PR review

    public func pullRequestDetails() async throws -> PullRequestDetails? {
        guard await isInstalled() else { return nil }
        let fields = "number,title,url,state,isDraft,body,author,headRefName,baseRefName,reviewDecision,statusCheckRollup,comments"
        let result = try await runner(ghPath, ["pr", "view", "--json", fields])
        guard result.success else { return nil }
        guard let data = result.stdout.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PullRequestDetails.self, from: data)
    }

    // MARK: - ADR-082 Phase 3 — GitHub Actions

    public func recentWorkflowRuns(limit: Int = 5) async throws -> [WorkflowRun] {
        guard await isInstalled() else { return [] }
        let fields = "databaseId,displayTitle,workflowName,status,conclusion,headBranch,createdAt,url"
        let result = try await runner(ghPath, ["run", "list", "--limit", "\(limit)", "--json", fields])
        guard result.success else { return [] }
        guard let data = result.stdout.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([WorkflowRun].self, from: data)) ?? []
    }

    // MARK: - ADR-083 Phase 3 — PR comment

    /// 현재 브랜치 PR에 comment 추가.
    public func commentOnPullRequest(body: String) async throws {
        guard await isInstalled() else { throw GitHubError.ghNotInstalled }
        guard await isAuthenticated() else { throw GitHubError.notAuthenticated }
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let result = try await runner(ghPath, ["pr", "comment", "--body", body])
        if !result.success {
            throw GitHubError.commandFailed(args: ["pr", "comment"], exitCode: result.exitCode, stderr: result.stderr)
        }
    }

    // MARK: - ADR-083 Phase 4 — Workflow re-run

    /// 특정 workflow run 재실행 (failed runs 우선).
    public func rerunWorkflow(runId: Int, failedOnly: Bool = false) async throws {
        guard await isInstalled() else { throw GitHubError.ghNotInstalled }
        var args = ["run", "rerun", "\(runId)"]
        if failedOnly { args.append("--failed") }
        let result = try await runner(ghPath, args)
        if !result.success {
            throw GitHubError.commandFailed(args: args, exitCode: result.exitCode, stderr: result.stderr)
        }
    }

    // MARK: - ADR-083 Phase 4 — Repo insights

    /// Top contributors (last 30 days).
    public func topContributors(limit: Int = 5) async throws -> [Contributor] {
        guard await isInstalled() else { return [] }
        // gh api repos/OWNER/REPO/contributors는 분석 시간이 걸림 — 단순화 위해 commits 기반
        // git shortlog -sne로 top contributors 가능하지만 git 호출 필요
        // 여기선 GitHub stats API 활용: repos/{owner}/{repo}/stats/contributors
        let result = try await runner(ghPath, ["api", "repos/{owner}/{repo}/contributors", "--paginate=false"])
        guard result.success else { return [] }
        guard let data = result.stdout.data(using: .utf8) else { return [] }
        let raw = (try? JSONDecoder().decode([RawContributor].self, from: data)) ?? []
        return raw.prefix(limit).map {
            Contributor(login: $0.login, contributions: $0.contributions, avatarURL: $0.avatar_url)
        }
    }

    /// Repo basic info (stars / forks / open issues).
    public func repoInfo() async throws -> RepoInfo? {
        guard await isInstalled() else { return nil }
        let fields = "name,nameWithOwner,description,stargazerCount,forkCount,openIssuesCount,updatedAt,url"
        let result = try await runner(ghPath, ["repo", "view", "--json", fields])
        guard result.success else { return nil }
        guard let data = result.stdout.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(RepoInfo.self, from: data)
    }

    private struct RawContributor: Decodable {
        let login: String
        let contributions: Int
        let avatar_url: String
    }
}

// MARK: - ADR-083 Phase 4 — Repo insights types

public struct Contributor: Sendable, Hashable, Identifiable {
    public let login: String
    public let contributions: Int
    public let avatarURL: String

    public var id: String { login }

    public init(login: String, contributions: Int, avatarURL: String) {
        self.login = login
        self.contributions = contributions
        self.avatarURL = avatarURL
    }
}

public struct RepoInfo: Sendable, Codable, Hashable {
    public let name: String
    public let nameWithOwner: String
    public let description: String?
    public let stargazerCount: Int
    public let forkCount: Int
    public let openIssuesCount: Int
    public let updatedAt: String
    public let url: String
}

// MARK: - Default runners (extension to keep actor body clean)

public extension GitHubCLIRunner {

    static let defaultRun: Run = { url, args in
        let process = Process()
        process.executableURL = url
        process.arguments = args

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

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return ProcessResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    /// **ADR-081 Phase 3** — Helper that sets cwd before running gh.
    public static func makeRunWithCwd(_ cwd: URL) -> Run {
        return { url, args in
            let process = Process()
            process.executableURL = url
            process.arguments = args
            process.currentDirectoryURL = cwd

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

            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return ProcessResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
        }
    }
}

// MARK: - PR / Workflow data types (ADR-082 Phase 2-3)

public struct PullRequestDetails: Sendable, Codable, Hashable {
    public let number: Int
    public let title: String
    public let url: String
    public let state: String
    public let isDraft: Bool
    public let body: String?
    public let author: PRAuthor
    public let headRefName: String
    public let baseRefName: String
    public let reviewDecision: String?
    public let statusCheckRollup: [PRCheck]?
    public let comments: [PRComment]?

    public struct PRAuthor: Sendable, Codable, Hashable {
        public let login: String
    }

    public struct PRCheck: Sendable, Codable, Hashable {
        public let name: String
        public let conclusion: String?
        public let status: String?
    }

    public struct PRComment: Sendable, Codable, Hashable {
        public let author: PRAuthor
        public let body: String
    }

    public var stateDisplay: String {
        switch state {
        case "OPEN": return isDraft ? "초안" : "열림"
        case "CLOSED": return "닫힘"
        case "MERGED": return "병합됨"
        default: return state
        }
    }

    public var allChecksPass: Bool {
        guard let checks = statusCheckRollup else { return true }
        return checks.allSatisfy { $0.conclusion == "SUCCESS" || $0.conclusion == "SKIPPED" }
    }

    public var pendingChecks: Int {
        guard let checks = statusCheckRollup else { return 0 }
        return checks.filter { $0.status == "IN_PROGRESS" || $0.status == "QUEUED" }.count
    }

    public var failedChecks: Int {
        guard let checks = statusCheckRollup else { return 0 }
        return checks.filter { $0.conclusion == "FAILURE" }.count
    }
}

public struct WorkflowRun: Sendable, Codable, Hashable, Identifiable {
    public let databaseId: Int
    public let displayTitle: String
    public let workflowName: String
    public let status: String
    public let conclusion: String?
    public let headBranch: String
    public let createdAt: String
    public let url: String

    public var id: Int { databaseId }

    public var displayStatus: String {
        if status == "completed" {
            switch conclusion {
            case "success": return "성공"
            case "failure": return "실패"
            case "cancelled": return "취소됨"
            case "skipped": return "건너뜀"
            default: return conclusion ?? "완료"
            }
        }
        switch status {
        case "queued": return "대기 중"
        case "in_progress": return "진행 중"
        default: return status
        }
    }

    public var isInProgress: Bool {
        status == "in_progress" || status == "queued"
    }

    public var isFailure: Bool {
        status == "completed" && conclusion == "failure"
    }

    public var isSuccess: Bool {
        status == "completed" && conclusion == "success"
    }
}
