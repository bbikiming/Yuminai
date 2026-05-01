import Foundation
import Testing
import YuminaiCore
@testable import YuminaiClaudeAdapter

@Suite("MockClaudeAdapter")
struct MockClaudeAdapterTests {
    @Test("스크립트된 이벤트 시퀀스를 순서대로 방출하고 종료한다")
    func emitsScriptedSequence() async throws {
        let events: [ClaudeEvent] = [
            .text("hello"),
            .text(" world"),
            .completed(exitCode: 0)
        ]
        let adapter = MockClaudeAdapter(scriptedEvents: events)
        let session = try await adapter.spawn(
            in: Workspace(name: "t", directoryPath: "/tmp")
        )

        var collected: [ClaudeEvent] = []
        for try await event in session.events {
            collected.append(event)
        }

        #expect(collected == events)
    }

    @Test("send는 Mock에서 무해하게 무시된다")
    func sendIsNoOp() async throws {
        let adapter = MockClaudeAdapter(scriptedEvents: [.completed(exitCode: 0)])
        let session = try await adapter.spawn(in: Workspace(name: "t", directoryPath: "/tmp"))
        try await session.send("ignored")
        // 예외 없으면 통과
    }
}

@Suite("ProcessEnvironment")
struct ProcessEnvironmentTests {
    @Test("PATH에 Homebrew와 ~/.local/bin이 포함된다")
    func pathIncludesCommonBinaries() {
        let env = ProcessEnvironment.augmented(base: ["PATH": "/usr/bin"])
        let path = env["PATH"] ?? ""
        #expect(path.contains("/opt/homebrew/bin"))
        #expect(path.contains(".local/bin"))
        #expect(path.contains("/usr/bin"))
    }

    @Test("HOME이 없으면 NSHomeDirectory()로 채운다")
    func homeIsBackfilled() {
        let env = ProcessEnvironment.augmented(base: [:])
        #expect(env["HOME"] != nil)
        #expect(env["HOME"]?.isEmpty == false)
    }

    @Test("TERM은 항상 xterm-256color")
    func termIsSet() {
        let env = ProcessEnvironment.augmented(base: [:])
        #expect(env["TERM"] == "xterm-256color")
    }
}
