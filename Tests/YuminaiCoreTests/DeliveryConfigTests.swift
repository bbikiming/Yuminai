import Foundation
import Testing
import YuminaiCore

@Suite("DeliveryConfig")
struct DeliveryConfigTests {
    @Test("기본값은 모든 명령 nil + 자동 실행 OFF")
    func defaults() {
        let cfg = DeliveryConfig()
        #expect(cfg.testCommand == nil)
        #expect(cfg.lintCommand == nil)
        #expect(cfg.buildCommand == nil)
        #expect(cfg.autoRunOnTurnComplete == false)
        #expect(cfg.autoFeedFailureToAgent == true)
        #expect(cfg.maxAttempts == 2)  // ADR-042 R1.H6 — default 3→2 (3번째는 사용자 개입)
        #expect(cfg.timeoutSeconds == 300)
        #expect(cfg.hasAnyCommand == false)
    }

    @Test("hasAnyCommand는 testCommand 하나만 있어도 true")
    func hasAnyCommandTest() {
        var cfg = DeliveryConfig()
        cfg.testCommand = "swift test"
        #expect(cfg.hasAnyCommand)
    }

    @Test("Codable round-trip 동일 값 보존")
    func codableRoundTrip() throws {
        let cfg = DeliveryConfig(
            buildCommand: "swift build",
            testCommand: "swift test --enable-code-coverage",
            lintCommand: "swiftlint --strict",
            autoRunOnTurnComplete: true,
            autoFeedFailureToAgent: true,
            maxAttempts: 5,
            timeoutSeconds: 600
        )
        let data = try JSONEncoder().encode(cfg)
        let decoded = try JSONDecoder().decode(DeliveryConfig.self, from: data)
        #expect(decoded == cfg)
    }
}

@Suite("DeliveryResult — failure prompt")
struct DeliveryResultPromptTests {
    @Test("실패 결과는 한국어 헤더 + stderr tail로 prompt 생성")
    func failurePrompt() {
        let result = DeliveryResult(
            kind: .test,
            command: "swift test",
            exitCode: 1,
            stdout: "Building...",
            stderr: "error: line 42 — type mismatch",
            durationMs: 2300,
            attempt: 1
        )
        let prompt = result.failurePromptPrefix()
        #expect(prompt.contains("[테스트 실패"))
        #expect(prompt.contains("exit 1"))
        #expect(prompt.contains("시도 1"))
        #expect(prompt.contains("$ swift test"))
        #expect(prompt.contains("--- stderr ---"))
        #expect(prompt.contains("type mismatch"))
        #expect(prompt.contains("위 실패를 분석하고 수정해주세요"))
    }

    @Test("타임아웃은 별도 헤더")
    func timeoutPrompt() {
        let result = DeliveryResult(
            kind: .build,
            command: "make",
            exitCode: -9,
            stdout: "",
            stderr: "",
            durationMs: 300_000,
            attempt: 2,
            timedOut: true
        )
        let prompt = result.failurePromptPrefix()
        #expect(prompt.contains("[빌드 실패"))
        #expect(prompt.contains("타임아웃"))
        #expect(prompt.contains("시도 2"))
    }

    @Test("stderr가 비어있으면 stdout tail 사용")
    func stdoutFallback() {
        let result = DeliveryResult(
            kind: .test,
            command: "pytest",
            exitCode: 1,
            stdout: "FAILED tests/test_foo.py::test_bar",
            stderr: "",
            durationMs: 100,
            attempt: 1
        )
        let prompt = result.failurePromptPrefix()
        #expect(prompt.contains("--- stdout ---"))
        #expect(prompt.contains("test_bar"))
        #expect(!prompt.contains("--- stderr ---"))
    }

    @Test("긴 stderr는 마지막 50줄로 truncate + 생략 표시")
    func tailTruncates() {
        let lines = (1...100).map { "line \($0)" }.joined(separator: "\n")
        let tailed = DeliveryResult.tail(lines, lines: 50)
        #expect(tailed.contains("앞부분 50줄 생략"))
        #expect(tailed.contains("line 100"))
        #expect(!tailed.contains("line 1\n"))
    }

    @Test("짧은 텍스트는 그대로")
    func shortTextNoTruncate() {
        let s = "single line"
        #expect(DeliveryResult.tail(s, lines: 50) == s)
    }
}
