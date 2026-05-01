import Foundation
import os
import YuminaiCore

/// Workspace의 build/test/lint 명령을 자동으로 실행하고 결과를 capture하는 actor (ADR-029, M4).
///
/// **참조**: Aider `--auto-test --auto-lint` + Devin step budget hard cap.
///
/// ## 동작
/// - `runIfConfigured(workspace:trigger:)` — autoRunOnTurnComplete=true면 자동 실행
/// - `runOnce(workspace:kind:command:)` — 사용자 수동 호출
/// - test → lint 순서, 실패 시 lint skip
/// - timeoutSeconds 후 SIGTERM → 0.5s → SIGKILL
/// - 같은 workspace에서 재진입 방지 (mutex)
public actor DeliveryRunner {
    private var inFlight: Set<UUID> = []
    private var attempts: [UUID: Int] = [:]  // workspace.id → 현재 attempt count
    private let logger = Logger(subsystem: "com.yuminai", category: "Delivery")

    public init() {}

    public enum Trigger: Sendable {
        case turnComplete  // agent turn 완료 hook
        case manual        // 사용자 명시적
    }

    /// 자동 실행 — autoRunOnTurnComplete + hasAnyCommand이면 진행.
    /// Hard cap (Devin) — maxAttempts 초과면 skip + 사용자 에스컬레이션 메시지.
    public func runIfConfigured(workspace: Workspace, trigger: Trigger) async -> [DeliveryResult] {
        let cfg = workspace.deliveryConfig
        guard cfg.hasAnyCommand else { return [] }
        if trigger == .turnComplete && !cfg.autoRunOnTurnComplete { return [] }

        let attempt = (attempts[workspace.id] ?? 0) + 1
        if attempt > cfg.maxAttempts {
            logger.info("delivery skip — max attempts (\(cfg.maxAttempts)) 도달")
            // 카운터 리셋 — 사용자가 다음에 새로 시도할 수 있게
            attempts[workspace.id] = 0
            return [escalateResult(workspace: workspace, attempt: attempt)]
        }
        attempts[workspace.id] = attempt

        guard !inFlight.contains(workspace.id) else {
            logger.info("delivery 재진입 방지 — \(workspace.name)")
            return []
        }
        inFlight.insert(workspace.id)
        defer { inFlight.remove(workspace.id) }

        var results: [DeliveryResult] = []
        let workingDir = URL(fileURLWithPath: workspace.directoryPath)

        if let cmd = cfg.testCommand?.trimmingCharacters(in: .whitespaces), !cmd.isEmpty {
            let result = await runShell(
                command: cmd,
                kind: .test,
                workingDir: workingDir,
                timeoutSeconds: cfg.timeoutSeconds,
                attempt: attempt
            )
            results.append(result)
            if !result.success {
                // test 실패 시 lint skip (다음 turn에 fix 후 다시)
                return results
            }
        }

        if let cmd = cfg.lintCommand?.trimmingCharacters(in: .whitespaces), !cmd.isEmpty {
            let result = await runShell(
                command: cmd,
                kind: .lint,
                workingDir: workingDir,
                timeoutSeconds: cfg.timeoutSeconds,
                attempt: attempt
            )
            results.append(result)
        }

        // 모두 성공 시 attempts 리셋 (다음 자유로운 try)
        if results.allSatisfy(\.success) {
            attempts[workspace.id] = 0
        }

        return results
    }

    /// 사용자 수동 1회 실행 (Inspector "변경" 탭 등에서).
    public func runOnce(
        workspace: Workspace,
        kind: DeliveryResult.Kind,
        command: String
    ) async -> DeliveryResult {
        let workingDir = URL(fileURLWithPath: workspace.directoryPath)
        return await runShell(
            command: command,
            kind: kind,
            workingDir: workingDir,
            timeoutSeconds: workspace.deliveryConfig.timeoutSeconds,
            attempt: 0
        )
    }

    public func resetAttempts(for workspaceId: UUID) {
        attempts[workspaceId] = 0
    }

    // MARK: - Internal shell runner

    /// `/bin/zsh -lc "<command>"` 로 spawn — 사용자 zsh env 그대로.
    private func runShell(
        command: String,
        kind: DeliveryResult.Kind,
        workingDir: URL,
        timeoutSeconds: Int,
        attempt: Int
    ) async -> DeliveryResult {
        let started = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = workingDir

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // 데이터 capture — readability handler로 누적
        let stdoutBuffer = ConcurrentStringBuffer()
        let stderrBuffer = ConcurrentStringBuffer()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            if let s = String(data: data, encoding: .utf8) {
                stdoutBuffer.append(s)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            if let s = String(data: data, encoding: .utf8) {
                stderrBuffer.append(s)
            }
        }

        do {
            try process.run()
        } catch {
            return DeliveryResult(
                kind: kind,
                command: command,
                exitCode: -1,
                stdout: "",
                stderr: "프로세스 시작 실패: \(error.localizedDescription)",
                durationMs: Int(Date().timeIntervalSince(started) * 1000),
                attempt: attempt,
                timedOut: false,
                startedAt: started
            )
        }

        // timeout watchdog
        let timeoutTask = Task<Bool, Never> { [process] in
            try? await Task.sleep(for: .seconds(timeoutSeconds))
            if process.isRunning {
                process.terminate()
                try? await Task.sleep(for: .milliseconds(500))
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
                return true
            }
            return false
        }

        // 종료 대기 — Process.waitUntilExit는 blocking이므로 background로
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                process.waitUntilExit()
                cont.resume()
            }
        }
        let timedOut = await timeoutTask.value
        if !timedOut { timeoutTask.cancel() }

        // readability handler 정리 — process 종료 후에도 잠시 buffer flush 대기
        try? await Task.sleep(for: .milliseconds(50))
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let stdout = stdoutBuffer.snapshot()
        let stderr = stderrBuffer.snapshot()

        let result = DeliveryResult(
            kind: kind,
            command: command,
            exitCode: timedOut ? -9 : process.terminationStatus,
            stdout: stdout,
            stderr: stderr,
            durationMs: Int(Date().timeIntervalSince(started) * 1000),
            attempt: attempt,
            timedOut: timedOut,
            startedAt: started
        )

        logger.info("\(kind.rawValue) \(result.success ? "OK" : "FAIL") attempt=\(attempt) ms=\(result.durationMs)")
        return result
    }

    private func escalateResult(workspace: Workspace, attempt: Int) -> DeliveryResult {
        DeliveryResult(
            kind: .test,
            command: workspace.deliveryConfig.testCommand ?? "",
            exitCode: -1,
            stdout: "",
            stderr: "최대 자동 시도(\(workspace.deliveryConfig.maxAttempts))를 초과했어요. 사용자가 직접 수정하거나 ‘다시 시도’를 눌러주세요.",
            durationMs: 0,
            attempt: attempt,
            timedOut: false
        )
    }
}

/// readability handler에서 thread-safe하게 누적 — Pipe handler는 background queue에서 호출됨.
final class ConcurrentStringBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = ""

    func append(_ s: String) {
        lock.lock()
        data.append(s)
        lock.unlock()
    }

    func snapshot() -> String {
        lock.lock()
        let copy = data
        lock.unlock()
        return copy
    }
}
