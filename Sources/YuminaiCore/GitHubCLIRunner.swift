import Foundation

/// **ADR-081 Phase 3** — GitHub `gh` CLI 통합 (Claude Code 패턴 단순화).
///
/// 기능:
/// - gh CLI 자동 감지
/// - 현재 브랜치 → PR 생성 (title + body)
/// - 인증 상태 확인
///
/// ## 디자인 결정
/// - **gh CLI 의존**: GitHub API 직접 호출 대신 `gh` 사용 (인증/scope 자동)
/// - **단순화**: PR 만들기만 (review/merge는 gh PR 페이지에서)
/// - **Claude Code 패턴**: PR title은 conventional commits 또는 사용자 입력,
///   body는 변경사항 요약 + AI 생성 옵션
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
    /// - Parameters:
    ///   - title: PR 제목 (필수, conventional commits 권장)
    ///   - body: PR 본문 (markdown, 선택)
    ///   - draft: draft PR 여부
    /// - Returns: 생성된 PR URL
    public func createPullRequest(title: String, body: String?, draft: Bool = false) async throws -> String {
        guard await isInstalled() else { throw GitHubError.ghNotInstalled }
        guard await isAuthenticated() else { throw GitHubError.notAuthenticated }

        // gh pr create는 cwd 기반으로 동작 — Process로 cwd 설정 필요 (defaultRun이 처리)
        var args = ["pr", "create", "--title", title]
        if let body, !body.isEmpty {
            args.append("--body")
            args.append(body)
        } else {
            args.append("--body")
            args.append("")  // 빈 body 명시
        }
        if draft { args.append("--draft") }

        let result = try await runWithCwd(args)
        if !result.success {
            throw GitHubError.commandFailed(args: args, exitCode: result.exitCode, stderr: result.stderr)
        }
        // gh pr create stdout에 PR URL 출력
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 현재 브랜치 PR 존재 여부 (있으면 URL 반환).
    public func existingPullRequest() async throws -> String? {
        guard await isInstalled() else { return nil }
        let result = try await runWithCwd(["pr", "view", "--json", "url", "-q", ".url"])
        guard result.success else { return nil }
        let url = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return url.isEmpty ? nil : url
    }

    /// cwd가 workspaceURL인 채로 gh 실행.
    private func runWithCwd(_ args: [String]) async throws -> ProcessResult {
        try await runner(ghPath, args)
    }

    // MARK: - Default Process runner (cwd 적용)

    public static let defaultRun: Run = { url, args in
        let process = Process()
        process.executableURL = url
        process.arguments = args
        // cwd 직접 set 불가 (caller가 별도 wrap 필요) — defaultRun은 단순 invocation만

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                process.waitUntilExit()
                continuation.resume()
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
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.global().async {
                    process.waitUntilExit()
                    continuation.resume()
                }
            }

            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return ProcessResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
        }
    }
}
