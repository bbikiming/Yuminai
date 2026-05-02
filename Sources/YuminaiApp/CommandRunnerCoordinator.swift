import Foundation
import Observation
import AppKit
import YuminaiCore

/// CommandRunner block 누적 + share/copy 단일 책임 (ADR-042 R3.3).
///
/// **분리 근거**: 가장 작은 coord (state 3개 + 메서드 4개). AppModel god-object 분해의 low-risk 단계.
/// CommandRunner actor는 의존성 주입.
///
/// **Facade 패턴**: AppModel은 `commands` 보유 + 기존 호출자 API computed pass-through.
@MainActor
@Observable
public final class CommandRunnerCoordinator {
    public var showPane: Bool = false
    public var blocks: [CommandRunner.CommandResult] = []
    public var isRunning: Bool = false

    public var lastError: String?

    private let runner: CommandRunner

    public init(runner: CommandRunner = CommandRunner()) {
        self.runner = runner
    }

    /// 명령 실행 + block 누적. cwd는 caller가 주입 (workspace 의존성 X).
    public func run(_ command: String, in workingDir: URL) async {
        isRunning = true
        defer { isRunning = false }
        do {
            let result = try await runner.run(command: command, in: workingDir)
            blocks.append(result)
            if blocks.count > AppLimits.maxCommandBlocks {
                blocks.removeFirst(blocks.count - AppLimits.maxCommandBlocks)
            }
        } catch {
            lastError = "명령 실행 실패: \(error.localizedDescription)"
        }
    }

    public func clear() {
        blocks = []
    }

    /// stdout/stderr를 클립보드에 복사 (ADR-040 T8).
    public func copyOutput(_ text: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    /// Block을 agent prompt prefix로 변환 (ADR-040 T8 + ADR-042 R1.C1 tail 적용).
    /// caller가 enqueueComposerPrefix 호출 (composer는 외부 의존성).
    public func buildShareToAgentPrefix(_ block: CommandRunner.CommandResult) -> String {
        let header = block.success
            ? "[명령 결과 — exit \(block.exitCode)]"
            : "[명령 실패 — exit \(block.exitCode)]"
        var sections: [String] = [header, "$ \(block.command)"]
        let stdoutTail = DeliveryResult.tail(block.stdout, lines: 30)
        let stderrTail = DeliveryResult.tail(block.stderr, lines: 50)
        if !stdoutTail.isEmpty { sections.append("--- stdout ---\n\(stdoutTail)") }
        if !stderrTail.isEmpty { sections.append("--- stderr ---\n\(stderrTail)") }
        return sections.joined(separator: "\n\n") + "\n\n"
    }
}
