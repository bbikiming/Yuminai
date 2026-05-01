import Foundation

/// `git` CLI 호출 추상화 (ADR-027 phase A2).
///
/// Yuminai는 git을 단일 진실의 원천으로 사용 — checkpoint = stash, accept = 그대로,
/// reject = restore. `Process` + `Pipe` 단순 wrap. mock injection으로 테스트 가능.
public actor GitRunner {
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

    public enum GitError: Error, LocalizedError, Sendable {
        case notARepository(path: String)
        case commandFailed(args: [String], exitCode: Int32, stderr: String)
        case binaryNotFound(path: String)

        public var errorDescription: String? {
            switch self {
            case .notARepository(let path):
                return "git 저장소가 아니에요: \(path)"
            case .commandFailed(let args, let code, let stderr):
                let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let reason = trimmed.isEmpty ? "exit \(code)" : trimmed
                return "git \(args.joined(separator: " ")) 실패: \(reason)"
            case .binaryNotFound(let path):
                return "git CLI 미발견: \(path)"
            }
        }
    }

    public let gitPath: URL
    public let workspaceURL: URL
    private let runner: Run

    public init(
        gitPath: URL = GitRunner.defaultGitPath(),
        workspaceURL: URL,
        runner: @escaping Run = GitRunner.defaultRun
    ) {
        self.gitPath = gitPath
        self.workspaceURL = workspaceURL
        self.runner = runner
    }

    public static func defaultGitPath() -> URL {
        let candidates = [
            "/usr/bin/git",
            "/opt/homebrew/bin/git",
            "/usr/local/bin/git"
        ]
        let fm = FileManager.default
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: candidates[0])
    }

    /// git 저장소인지 확인 (`.git` 디렉토리 존재).
    public func isRepository() -> Bool {
        var isDir: ObjCBool = false
        let dotGit = workspaceURL.appending(path: ".git")
        let exists = FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDir)
        // .git이 파일일 수도 있음 (worktree) — 두 케이스 모두 OK
        return exists
    }

    public func run(_ args: [String]) async throws -> ProcessResult {
        guard FileManager.default.isExecutableFile(atPath: gitPath.path) else {
            throw GitError.binaryNotFound(path: gitPath.path)
        }
        var fullArgs = ["-C", workspaceURL.path]
        fullArgs.append(contentsOf: args)
        return try await runner(gitPath, fullArgs)
    }

    public func runOrThrow(_ args: [String]) async throws -> String {
        let result = try await run(args)
        guard result.success else {
            throw GitError.commandFailed(args: args, exitCode: result.exitCode, stderr: result.stderr)
        }
        return result.stdout
    }

    /// 변경된 파일 목록 (staged + unstaged + untracked).
    public func changedFiles() async throws -> [ChangedFile] {
        let raw = try await runOrThrow(["status", "--porcelain=v1", "-z", "--untracked-files=all"])
        return Self.parsePorcelain(raw)
    }

    /// HEAD vs working tree diff (untracked 제외).
    public func diff(paths: [String]? = nil) async throws -> String {
        var args = ["diff", "HEAD", "--no-color"]
        if let paths {
            args.append("--")
            args.append(contentsOf: paths)
        }
        return try await runOrThrow(args)
    }

    /// Yuminai checkpoint 시작 — `git stash push -u --keep-index -m <message>` 후 즉시 pop으로
    /// 변경 보존. 실제로는 stash list에 보관되지 않고, `git rev-parse HEAD`만 기록 (light-weight).
    public func currentHeadSha() async throws -> String {
        let raw = try await runOrThrow(["rev-parse", "HEAD"])
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 특정 path의 working tree 변경을 HEAD로 되돌리기 (untracked는 삭제).
    public func revert(paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        // tracked 파일 — checkout
        _ = try? await run(["checkout", "HEAD", "--"] + paths)
        // untracked 파일 — clean
        _ = try? await run(["clean", "-f", "--"] + paths)
    }

    /// 모든 변경 원복.
    public func revertAll() async throws {
        _ = try? await run(["checkout", "HEAD", "--", "."])
        _ = try? await run(["clean", "-fd"])
    }

    // MARK: - Default Process runner

    public static let defaultRun: Run = { url, args in
        let process = Process()
        process.executableURL = url
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }

    // MARK: - Parsing

    /// `git status --porcelain=v1 -z` 결과를 ChangedFile 목록으로 파싱.
    /// NUL-separated entries: `XY <space> <path>` 또는 `R <space> <new-path><NUL><old-path>`.
    static func parsePorcelain(_ raw: String) -> [ChangedFile] {
        let entries = raw.split(separator: "\0", omittingEmptySubsequences: true)
        var result: [ChangedFile] = []
        var i = entries.startIndex
        while i < entries.endIndex {
            let entry = String(entries[i])
            i = entries.index(after: i)
            guard entry.count >= 3 else { continue }
            let xy = String(entry.prefix(2))
            let pathStart = entry.index(entry.startIndex, offsetBy: 3)
            let path = String(entry[pathStart...])

            let status = ChangedFile.Status.from(porcelain: xy)
            // R/C는 다음 entry가 old-path
            if status == .renamed || status == .copied {
                if i < entries.endIndex {
                    i = entries.index(after: i)  // skip old-path
                }
            }
            result.append(ChangedFile(path: path, status: status, porcelain: xy))
        }
        return result
    }
}

public struct ChangedFile: Sendable, Equatable, Identifiable, Hashable {
    public let path: String
    public let status: Status
    public let porcelain: String  // raw XY (예: " M", "??", "MM")

    public var id: String { path }

    public enum Status: String, Sendable, CaseIterable {
        case modified, added, deleted, renamed, copied, untracked, unknown

        static func from(porcelain xy: String) -> Status {
            // 첫 번째 char가 staged status, 두 번째가 unstaged. 우선순위 묶어서 추정.
            let chars = Array(xy)
            if xy == "??" { return .untracked }
            if chars.contains("M") { return .modified }
            if chars.contains("A") { return .added }
            if chars.contains("D") { return .deleted }
            if chars.contains("R") { return .renamed }
            if chars.contains("C") { return .copied }
            return .unknown
        }

        public var label: String {
            switch self {
            case .modified: return "수정"
            case .added: return "추가"
            case .deleted: return "삭제"
            case .renamed: return "이름변경"
            case .copied: return "복사"
            case .untracked: return "새 파일"
            case .unknown: return "?"
            }
        }
    }

    public init(path: String, status: Status, porcelain: String) {
        self.path = path
        self.status = status
        self.porcelain = porcelain
    }
}
