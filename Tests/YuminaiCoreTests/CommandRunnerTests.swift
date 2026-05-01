import Foundation
import Testing
import YuminaiCore

@Suite("CommandRunner")
struct CommandRunnerTests {
    @Test("CommandResult success은 exitCode==0")
    func successFlag() {
        let ok = CommandRunner.CommandResult(
            command: "ls", cwd: "/tmp",
            exitCode: 0, stdout: "", stderr: "",
            durationMs: 10
        )
        #expect(ok.success)

        let fail = CommandRunner.CommandResult(
            command: "false", cwd: "/tmp",
            exitCode: 1, stdout: "", stderr: "",
            durationMs: 10
        )
        #expect(!fail.success)
    }

    @Test("mock runner로 결과 조작 가능")
    func mockRunner() async throws {
        let runner = CommandRunner { command, cwd in
            CommandRunner.CommandResult(
                command: command,
                cwd: cwd.path,
                exitCode: 0,
                stdout: "mocked stdout",
                stderr: "",
                durationMs: 5
            )
        }
        let result = try await runner.run(command: "echo hi", in: URL(fileURLWithPath: "/tmp"))
        #expect(result.command == "echo hi")
        #expect(result.stdout == "mocked stdout")
    }

    @Test("mock runner — 실패 결과")
    func mockRunnerFailure() async throws {
        let runner = CommandRunner { _, _ in
            CommandRunner.CommandResult(
                command: "fail",
                cwd: "/tmp",
                exitCode: 127,
                stdout: "",
                stderr: "command not found",
                durationMs: 1
            )
        }
        let result = try await runner.run(command: "fail", in: URL(fileURLWithPath: "/tmp"))
        #expect(!result.success)
        #expect(result.stderr.contains("not found"))
    }
}
