import Foundation

/// 단일 명령 실행 + 결과 capture (ADR-036 C4, Warp-style block 대안).
///
/// **참조**: Warp는 PTY parser로 prompt 인식 + block grouping. SwiftTerm wrap 비용 큼 →
/// **단순화**: NSTask로 명령 1회 실행 + stdout/stderr 누적. 진짜 PTY는 v0.8+
public actor CommandRunner {
    public typealias Run = @Sendable (String, URL) async throws -> CommandResult

    public struct CommandResult: Sendable, Equatable, Identifiable {
        public let id: UUID
        public let command: String
        public let cwd: String
        public let exitCode: Int32
        public let stdout: String
        public let stderr: String
        public let durationMs: Int
        public let startedAt: Date

        public init(
            id: UUID = UUID(),
            command: String,
            cwd: String,
            exitCode: Int32,
            stdout: String,
            stderr: String,
            durationMs: Int,
            startedAt: Date = Date()
        ) {
            self.id = id
            self.command = command
            self.cwd = cwd
            self.exitCode = exitCode
            self.stdout = stdout
            self.stderr = stderr
            self.durationMs = durationMs
            self.startedAt = startedAt
        }

        public var success: Bool { exitCode == 0 }
    }

    private let runner: Run

    public init(runner: @escaping Run = CommandRunner.defaultRun) {
        self.runner = runner
    }

    public func run(command: String, in workingDir: URL) async throws -> CommandResult {
        try await runner(command, workingDir)
    }

    /// `/bin/zsh -lc <command>` 로 spawn.
    public static let defaultRun: Run = { command, workingDir in
        let started = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = workingDir

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        // synchronous read (단순화 — 짧은 명령용)
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return CommandResult(
            command: command,
            cwd: workingDir.path,
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            durationMs: Int(Date().timeIntervalSince(started) * 1000),
            startedAt: started
        )
    }
}
