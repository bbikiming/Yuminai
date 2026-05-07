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
    /// 3. AutoRunCoordinator.start() — 매 turn LLM spawn + 응답 분석
    /// 4. State 변경 → UI 알림
    /// 5. 완료/중단 시 macOS 알림
    public func startAutoRun(initialPrompt: String) async {
        let config = preferences.autoRunConfig

        // Harness 규칙 로드 (let으로 고정 — Sendable closure capture용)
        let systemPromptExtra: String
        if config.autoLoadHarnessRules, let ws = selectedWorkspace {
            let wsURL = URL(fileURLWithPath: ws.directoryPath)
            systemPromptExtra = await HarnessRulesLoader.loadAll(workspaceURL: wsURL)
        } else {
            systemPromptExtra = ""
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

            // 첫 turn에만 harness 규칙을 prompt 앞에 prepend
            let effectivePrompt: String
            if !systemPromptExtra.isEmpty && turn == 1 {
                effectivePrompt = systemPromptExtra + "\n\n---\n\n" + prompt
            } else {
                effectivePrompt = prompt
            }

            // 실제 메시지 전송 — sendMessage() 패턴과 동일
            await MainActor.run {
                self.inputText = effectivePrompt
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

            let log = AutoRunTurnLog(
                runId: runId,
                turn: turn,
                timestamp: .now,
                userPrompt: turn == 1 ? prompt : nil,
                agentResponse: lastResponse,
                toolCalls: [],
                costUSD: costDelta,
                durationSeconds: elapsed,
                warnings: []
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
