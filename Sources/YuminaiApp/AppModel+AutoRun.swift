import Foundation
import SwiftUI
import os
import YuminaiCore
import YuminaiHarness

// ADR-132 — AppModel 자동 실행 도메인 확장.
extension AppModel {

    // MARK: - 진입점

    /// 자동 실행 시작 — 활성 chat session 컨텍스트에서.
    ///
    /// 1. 설정 로드
    /// 2. `.harness/rules` 주입 (config에 따라)
    ///    **ADR-153 P1-8** — harness rules를 turn-1 user prompt prepend 대신
    ///    `autoRunSystemPromptExtra`를 통해 `--append-system-prompt`로 주입.
    ///    시스템 프롬프트가 turn 간에 고정되어 Anthropic prompt cache 적중률 향상.
    /// 3. AutoRunCoordinator.start() — 매 turn LLM spawn + 응답 분석
    /// 4. State 변경 → UI 알림
    /// 5. 완료/중단 시 macOS 알림
    public func startAutoRun(initialPrompt: String) async {
        let config = preferences.autoRunConfig

        // ADR-153 P1-8 — harness rules를 system prompt extra로 주입 (turn-1 user prompt prepend 제거).
        // ADR-153 P1-2 — USER_PROFILE.md 제외: adapter의 userProfilePrompt로 이미 inject됨.
        //                 3중 주입(system prompt + USER_PROFILE.md + harness rules) 방지.
        if config.autoLoadHarnessRules, let ws = selectedWorkspace {
            let wsURL = URL(fileURLWithPath: ws.directoryPath)
            let harnessRules = await HarnessRulesLoader.loadAll(
                workspaceURL: wsURL,
                excludeFiles: ["USER_PROFILE"]
            )
            // MainActor에서 property 설정 후 session respawn
            await MainActor.run {
                self.autoRunSystemPromptExtra = harnessRules.isEmpty ? nil : harnessRules
            }
        } else {
            await MainActor.run {
                self.autoRunSystemPromptExtra = nil
            }
        }

        // harness rules를 system prompt에 반영하기 위해 session respawn.
        // userProfilePrompt에 autoRunSystemPromptExtra가 합산돼 --append-system-prompt로 전달됨.
        if autoRunSystemPromptExtra != nil, let ws = selectedWorkspace {
            let agentAd = adapter(for: ws)
            let profilePrompt = userProfilePrompt
            if let claudeSession = try? await agentAd.spawn(in: ws, userProfilePrompt: profilePrompt) {
                if let existing = currentClaudeSession {
                    await agentAd.terminate(existing)
                }
                currentClaudeSession = claudeSession
                let captured = claudeSession
                streamConsumeTask?.cancel()
                streamConsumeTask = Task { [weak self] in
                    await self?.consumeStream(captured)
                }
            }
        }

        defer {
            // AutoRun 종료 시 extra 클리어 (다음 일반 spawn에 영향 없도록)
            Task { @MainActor [weak self] in
                self?.autoRunSystemPromptExtra = nil
            }
        }

        // state stream 구독 → autoRunState 갱신
        let coord = autoRunCoordinator
        Task { [weak self] in
            let stream = await coord.stateStream()
            for await newState in stream {
                await MainActor.run {
                    self?.autoRunState = newState
                }
            }
        }

        // 로그 URL 준비
        let runId = UUID()
        let logURL = autoRunLogURL(runId: runId)

        await coord.start(
            config: config,
            initialPrompt: initialPrompt
        ) { [weak self] turn, promptOverride in
            guard let self else { throw AutoRunError.modelDeallocated }
            let prompt = promptOverride ?? "(계속)"
            let turnStart = Date()

            // 실제 메시지 전송 — sendMessage() 패턴과 동일
            // ADR-153 P1-8 — harness rules는 system prompt로 이미 주입됨 (turn-1 prepend 불필요)
            await MainActor.run {
                self.inputText = prompt
            }
            // 50ms 대기 — UI 반영
            try await Task.sleep(nanoseconds: 50_000_000)
            await MainActor.run {
                Task { await self.sendMessage() }
            }

            // 스트리밍 완료 대기
            await self.waitForStreamingToFinish()

            let elapsed = Date().timeIntervalSince(turnStart)
            let lastResponse = await MainActor.run { self.messages.last?.content ?? "" }
            let costDelta = await MainActor.run { self.lastCostDelta }

            // ADR-134 — CommandPolicy wire-up:
            // 응답에서 감지된 tool_use / 명령 패턴을 CommandPolicyMatrix로 평가.
            // 현재는 응답 텍스트에서 코드 블록 내 명령을 추출해 평가한다.
            var warnings: [String] = []
            let detectedCommands = AutoRunCommandExtractor.extract(from: lastResponse)
            let effectivePolicy: CommandPolicyMatrix
            if let runPolicy = config.commandPolicy {
                effectivePolicy = runPolicy
            } else {
                effectivePolicy = await MainActor.run { self.preferences.commandPolicy }
            }
            var blockedCommands: [String] = []
            for cmd in detectedCommands {
                let decision = effectivePolicy.policy(for: cmd)
                switch decision {
                case .deny:
                    blockedCommands.append(cmd)
                    warnings.append("차단된 명령 감지: \(cmd)")
                case .requireConfirmation:
                    warnings.append("확인 필요 명령: \(cmd)")
                case .allow:
                    break
                }
            }
            // .deny 명령이 있으면 경고를 로그에 남기고 AutoRunCoordinator가 Destructive로 인식하도록
            // 응답에 차단 마커를 주입 (AutoRunCoordinator.checkDestructive 패턴 활용)
            let effectiveResponse: String
            if !blockedCommands.isEmpty {
                effectiveResponse = lastResponse + "\n[COMMAND_POLICY_BLOCKED: \(blockedCommands.joined(separator: ", "))]"
            } else {
                effectiveResponse = lastResponse
            }

            let log = AutoRunTurnLog(
                runId: runId,
                turn: turn,
                timestamp: .now,
                userPrompt: turn == 1 ? prompt : nil,
                agentResponse: effectiveResponse,
                toolCalls: detectedCommands,
                costUSD: costDelta,
                durationSeconds: elapsed,
                warnings: warnings
            )

            // 로그 영구 보관
            await self.appendAutoRunLog(log, to: logURL)

            await MainActor.run {
                self.autoRunLogs.append(log)
            }

            return log
        }

        // 완료 처리
        let finalState = await coord.current()
        await MainActor.run {
            self.autoRunState = finalState
        }

        if config.notifyOnComplete {
            await sendAutoRunCompletionNotification(state: finalState, config: config)
        }
    }

    /// 즉시 중단.
    public func stopAutoRun() async {
        await autoRunCoordinator.stop(reason: "사용자 중단")
    }

    /// 일시 정지.
    public func pauseAutoRun() async {
        await autoRunCoordinator.pause()
    }

    /// 재개.
    public func resumeAutoRun() async {
        await autoRunCoordinator.resume()
    }

    // MARK: - Harness 규칙 로드

    /// `.harness/rules/*.md` 일괄 로드. `autoLoadHarnessRules == true`일 때만 호출됨.
    func loadHarnessRules(workspaceURL: URL) async -> String {
        await HarnessRulesLoader.loadAll(workspaceURL: workspaceURL)
    }

    // MARK: - 내부 헬퍼

    /// 스트리밍 완료 대기 (polling — 최대 120초).
    private func waitForStreamingToFinish() async {
        var waited: TimeInterval = 0
        while await MainActor.run(body: { self.isStreaming }) && waited < 120 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            waited += 0.5
        }
    }

    /// 자동 실행 완료 알림 발송.
    private func sendAutoRunCompletionNotification(
        state: AutoRunCoordinator.State,
        config: AutoRunConfig
    ) async {
        guard case .completed(_, _, let summary, _) = state else { return }
        switch config.notifyChannel {
        case .macOS, .both:
            try? await MacOSNotificationSender.send(
                title: "자동 실행 완료",
                body: summary,
                identifier: "autorun.complete.\(UUID().uuidString)"
            )
        default:
            break
        }
    }

    /// 로그 파일 URL — `<workspace>/.harness/auto-run-log/<run-id>.jsonl`.
    private func autoRunLogURL(runId: UUID) -> URL? {
        guard let ws = selectedWorkspace else { return nil }
        let logDir = URL(fileURLWithPath: ws.directoryPath)
            .appendingPathComponent(".harness")
            .appendingPathComponent("auto-run-log")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        return logDir.appendingPathComponent("\(runId.uuidString).jsonl")
    }

    /// turn 로그를 JSONL 파일에 append.
    private func appendAutoRunLog(_ log: AutoRunTurnLog, to url: URL?) async {
        guard let url else { return }
        guard let data = try? JSONEncoder().encode(log),
              let line = String(data: data, encoding: .utf8) else { return }
        let newLine = line + "\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(newLine.utf8))
            try? handle.close()
        } else {
            try? Data(newLine.utf8).write(to: url, options: .atomic)
        }
    }

    /// 선택된 워크스페이스 (편의 접근).
    private var selectedWorkspace: Workspace? {
        guard let id = selectedWorkspaceId else { return nil }
        return workspaces.first { $0.id == id }
    }
}

// MARK: - AutoRun 에러

enum AutoRunError: Error {
    case modelDeallocated
}
