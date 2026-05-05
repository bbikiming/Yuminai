import Foundation
import YuminaiCore

/// 단일 워크스페이스 세션을 텔레그램으로 양방향 연결하는 bridge.
///
/// AppModel이 ClaudeEvent를 받을 때마다 `consume(event:)`를 호출하면
/// bridge가 텔레그램에 chunk 단위로 forwarding한다. 짧은 텍스트는 버퍼링했다가
/// flush할 때 한 메시지로 묶어 보낸다 (Telegram API rate limit 회피).
public actor TelegramSessionBridge {
    public struct Configuration: Sendable {
        public let chatId: Int64
        public var workspaceName: String
        public var forwardAssistant: Bool
        public var forwardToolCalls: Bool
        /// 한 메시지 최대 크기 — Telegram 4096 한도, 안전 마진 포함.
        public let maxChunkSize: Int
        /// 부분 텍스트 flush 간격.
        public let flushInterval: Duration

        public init(
            chatId: Int64,
            workspaceName: String,
            forwardAssistant: Bool = true,
            forwardToolCalls: Bool = true,
            maxChunkSize: Int = 3500,
            flushInterval: Duration = .milliseconds(800)
        ) {
            self.chatId = chatId
            self.workspaceName = workspaceName
            self.forwardAssistant = forwardAssistant
            self.forwardToolCalls = forwardToolCalls
            self.maxChunkSize = maxChunkSize
            self.flushInterval = flushInterval
        }
    }

    private let client: any TelegramClient
    private var config: Configuration

    private var assistantBuffer = ""
    private var flushTask: Task<Void, Never>?
    private var turnStartedAt: Date?
    private var toolCount = 0
    private var lastFailureSent: Bool = false
    /// ADR-045 R2.H3 — 외부 chat에서 명령 들어오면 그 chat을 응답 destination으로 (multi-chat).
    /// nil이면 config.chatId fallback. .completed 후 자동 클리어.
    private var requestChatId: Int64?
    /// **ADR-055 #2 + ADR-056 Phase 1** — turn 단위 streaming message id + 누적 텍스트.
    /// editMessageText는 전체 텍스트로 교체하므로 caller가 누적된 전체를 보내야 함.
    private var streamingMessageId: Int64?
    private var streamingAccumulated: String = ""
    /// edit 누적이 가능한 max size (Telegram 4096 한도, 안전 마진).
    /// 이 크기 넘으면 새 메시지로 split + 새 streaming session 시작.
    private static let editAccumulatedMax = 3500
    /// **ADR-098 P0-1** — HITL coordinator. 주입 시 destructive action이 차단+승인 흐름으로 전환.
    /// nil이면 기존 "알림만" 동작 유지.
    private var hitlCoordinator: TelegramHITLCoordinator?
    /// **ADR-098 P0-1** — HITL timeout (seconds). 기본 60s.
    private var hitlTimeoutSeconds: Int = 60
    /// **ADR-098 P0-1** — HITL 대기 중인 turn의 continuation 차단 여부.
    /// coordinator.request()가 suspend하는 동안 나머지 이벤트 처리를 막지 않도록
    /// bridge 자체가 blocked 상태임을 기록한다.
    private var pendingHITLTask: Task<TelegramHITLCoordinator.HITLResponse, Never>?
    /// **ADR-098 P1-1** — diff/log artifact store. 주입 시 notifyDiffArtifact/notifyLogArtifact가
    /// store에 저장 → UUID로 deep link 생성 → "📂 View Full in Yuminai" 링크 첨부.
    /// nil이면 artifact 발송 메서드는 즉시 반환 (legacy fallback).
    private var artifactStore: TelegramArtifactStore?
    /// **ADR-114-B** — HITL이 reject/timeout/cancelled로 끝났을 때 외부에 자동 취소를 요청하는 콜백.
    /// 주입되면 bridge가 destructive toolCall에 대한 HITL 응답을 받은 직후 호출 →
    /// AppModel이 `cancelBoundTurn()`으로 Claude 프로세스를 종료하도록 트리거.
    /// nil이면 기존 동작 유지 (사용자가 직접 `/cancel` 입력해야 함).
    private var onHITLCancelRequired: HITLCancelCallback?

    /// **ADR-114-B** — HITL 자동 취소 콜백 타입.
    public typealias HITLCancelCallback = @Sendable () async -> Void

    public init(client: any TelegramClient, configuration: Configuration) {
        self.client = client
        self.config = configuration
    }

    /// **ADR-098 P0-1** — HITL coordinator 주입. `makeSessionBridge` 직후 호출.
    public func setHITLCoordinator(_ coordinator: TelegramHITLCoordinator?, timeoutSeconds: Int = 60) {
        self.hitlCoordinator = coordinator
        self.hitlTimeoutSeconds = timeoutSeconds
    }

    /// **ADR-098 P1-1** — artifact store 주입. nil이면 artifact 발송이 비활성화된다.
    public func setArtifactStore(_ store: TelegramArtifactStore?) {
        self.artifactStore = store
    }

    /// **ADR-114-B** — HITL 자동 취소 콜백 주입.
    /// HITL 응답이 rejected/timeout/cancelled일 때 콜백을 호출 → AppModel이
    /// `cancelBoundTurn()`을 통해 진행 중인 Claude turn을 종료한다.
    /// nil로 호출하면 자동 취소가 비활성화되며 기존 "결과만 알림" 동작으로 복귀한다.
    public func setOnHITLCancelRequired(_ callback: HITLCancelCallback?) {
        self.onHITLCancelRequired = callback
    }

    public func updateConfiguration(_ config: Configuration) {
        self.config = config
    }

    /// ADR-045 R2.H3 — 외부 chat에서 turn 시작 시 그 chat을 응답 대상으로.
    public func setRequestChatId(_ chatId: Int64?) {
        self.requestChatId = chatId
    }

    // MARK: - Lifecycle

    /// 새 사용자 turn 시작 — 버퍼/카운터 초기화 + "▶ 시작" 알림.
    public func notifyTurnStart(userText: String) async {
        await flushAssistantBuffer()
        turnStartedAt = Date()
        toolCount = 0
        lastFailureSent = false
        // ADR-055 #2 + ADR-056 Phase 1 — 새 turn마다 streaming session reset
        streamingMessageId = nil
        streamingAccumulated = ""
        let preview = String(userText.prefix(100))
        await send("▶ 시작 — \(config.workspaceName)\n> \(preview)")
    }

    /// AppModel이 ClaudeEvent를 받을 때마다 호출.
    public func consume(event: ClaudeEvent) async {
        switch event {
        case .text(let text):
            guard config.forwardAssistant else { return }
            assistantBuffer.append(text)
            scheduleFlush()
        case .toolCall(let name, let input):
            guard config.forwardToolCalls else { return }
            toolCount += 1
            await flushAssistantBuffer()
            // ADR-045 R2.H1 + ADR-056 Phase 2 + ADR-098 P0-1
            // Destructive tool 감지 시 HITL coordinator가 주입돼 있으면 차단+승인 흐름 진입.
            // coordinator가 없으면 기존 "알림만" 동작 유지.
            if Self.isDestructiveToolCall(name: name, input: input) {
                let summary = Self.summarizeToolCall(name: name, input: input, maxLen: 200)
                let target = requestChatId ?? config.chatId
                streamingMessageId = nil
                streamingAccumulated = ""

                if let coordinator = hitlCoordinator {
                    // **ADR-098 P0-1** — HITL 차단 흐름: inline button + 60s timeout + 응답 대기
                    let approveData = "hitl:approve:\(UUID().uuidString)"  // placeholder — coordinator가 실제 UUID 생성
                    // coordinator.request()는 suspend — 응답 올 때까지 이 turn이 진행 불가
                    let workspaceName: String? = config.workspaceName.isEmpty ? nil : config.workspaceName
                    let response = await coordinator.request(
                        action: summary,
                        workspace: workspaceName,
                        diffPreview: nil,
                        timeout: hitlTimeoutSeconds
                    )
                    // HITL 결과 처리
                    // **ADR-114-B** — rejected/timeout/cancelled 시 onHITLCancelRequired 콜백 호출 →
                    // AppModel이 `cancelBoundTurn()`으로 Claude 프로세스 자동 종료.
                    // 콜백 미주입 시 기존 동작 유지 (사용자가 직접 `/cancel` 필요).
                    switch response {
                    case .approved(let by):
                        await send("✅ 승인됨 (by \(by)) — 작업 진행")
                    case .rejected(let by):
                        await send("❌ 거절됨 (by \(by)) — 작업 취소됨")
                        await onHITLCancelRequired?()
                    case .timeout:
                        await send("⏱ HITL 응답 시간 초과 (\(hitlTimeoutSeconds)s) — 작업 자동 취소됨")
                        await onHITLCancelRequired?()
                    case .cancelled:
                        await send("🛑 HITL 취소됨 — 작업 중단됨")
                        await onHITLCancelRequired?()
                    }
                } else {
                    // HITL coordinator 미주입 — 기존 동작: 알림 + cancel/status 버튼
                    let buttons = [[
                        InlineButton(text: "🛑 중단 (cancel)", callbackData: "cancel"),
                        InlineButton(text: "📊 상태", callbackData: "status")
                    ]]
                    _ = try? await client.sendWithKeyboard(
                        "🚨 위험한 작업 감지 — \(summary)\n버튼으로 즉시 결정하세요.",
                        to: target,
                        buttons: buttons
                    )
                }
            } else {
                let summary = Self.summarizeToolCall(name: name, input: input)
                await send("🔧 \(summary)")
            }
        case .toolResult(let success, _):
            guard config.forwardToolCalls else { return }
            if !success {
                await send("⚠ 도구 실패")
            }
        case .statusChange:
            break
        case .usage:
            break
        case .completed(let exitCode):
            await flushAssistantBuffer()
            let elapsed = turnStartedAt.map { Date().timeIntervalSince($0) } ?? 0
            let elapsedStr = String(format: "%.1fs", elapsed)
            if exitCode == 0 {
                // ADR-056 Phase 2 — 완료 알림에 [diff] [status] [cost] 버튼
                let target = requestChatId ?? config.chatId
                let buttons = [[
                    InlineButton(text: "📋 diff", callbackData: "diff"),
                    InlineButton(text: "📊 status", callbackData: "status"),
                    InlineButton(text: "💰 cost", callbackData: "cost")
                ]]
                _ = try? await client.sendWithKeyboard(
                    "✅ 완료 (\(elapsedStr), 도구 \(toolCount)회)",
                    to: target,
                    buttons: buttons
                )
                streamingMessageId = nil
                streamingAccumulated = ""
            } else if !lastFailureSent {
                await send("❌ 실패 — exit \(exitCode) (\(elapsedStr))")
                lastFailureSent = true
            }
            turnStartedAt = nil
            // ADR-045 R2.H3 — turn 종료 시 request chat 클리어 (다음 turn은 다시 config.chatId or new request)
            requestChatId = nil
        }
    }

    /// 임의의 안내 메시지 전송 (예: /status 응답, bind 알림).
    public func sendNotice(_ text: String) async {
        await flushAssistantBuffer()
        await send(text)
    }

    /// **ADR-059 Phase 4** — task 별 ▶ 실행 버튼 메시지 전송 (multi-row inline keyboard).
    /// caller가 ready task list를 전달 → 각 task 별 [▶ task title] 버튼 1개씩.
    /// callback_data 형식: "task:run:<UUID>"
    public func sendTaskButtons(_ tasks: [(id: UUID, title: String)]) async {
        guard !tasks.isEmpty else { return }
        await flushAssistantBuffer()
        let target = requestChatId ?? config.chatId
        // 한 행에 1개 버튼 (title이 길어서 가로 배치 어려움)
        let rows: [[InlineButton]] = tasks.prefix(8).map { task in
            // 제목 길면 30자 truncate
            let label = task.title.count > 30 ? String(task.title.prefix(30)) + "…" : task.title
            return [InlineButton(text: "▶ \(label)", callbackData: "task:run:\(task.id.uuidString)")]
        }
        _ = try? await client.sendWithKeyboard(
            "📋 Ready task 실행 버튼:",
            to: target,
            buttons: rows
        )
        streamingMessageId = nil
        streamingAccumulated = ""
    }

    /// 활성 turn 중단 안내.
    public func notifyCancelled() async {
        await flushAssistantBuffer()
        await send("🛑 진행 중인 turn 중단됨")
        turnStartedAt = nil
    }

    /// **ADR-055 HIGH 3** — ChildProcess (decomp/rehearsal/parallel) 시작 알림.
    /// 외부 사용자도 격리 호출이 시작됐음을 즉시 인지 — typing indicator 역할.
    public func notifyChildProcessStart(purpose: String, agent: String, context: String) async {
        await flushAssistantBuffer()
        let icon: String
        switch purpose {
        case "decomposition": icon = "📋"
        case "rehearsal": icon = "🔄"
        case "parallel": icon = "⚡"
        case "routing": icon = "🔀"
        default: icon = "⚙️"
        }
        await send("\(icon) \(purpose) 시작 — \(agent)\n  \(context)")
    }

    /// **ADR-055 HIGH 3** — ChildProcess 완료 결과 forward.
    /// resultText는 chunked로 전송 (code block 페어 보존). cost/duration은 footer에.
    public func notifyChildProcessComplete(
        purpose: String,
        agent: String,
        resultText: String,
        durationMs: Int,
        costUSD: Double,
        success: Bool
    ) async {
        await flushAssistantBuffer()
        let icon = success ? "✅" : "❌"
        let footer = "\n\n_(\(purpose) · \(agent) · \(durationMs)ms · $\(String(format: "%.4f", costUSD)))_"

        // resultText를 chunked 처리 (긴 응답은 자동 분할)
        let trimmed = resultText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            await send("\(icon) \(purpose) 완료\(footer)")
            return
        }
        let header = "\(icon) \(purpose) 결과 (\(agent))\n"
        let combined = header + trimmed + footer
        for chunk in Self.chunked(combined, maxSize: config.maxChunkSize) {
            await send(chunk)
        }
    }

    /// **ADR-098 P1-1** — diff artifact를 store + formatter + deep link 경로로 발송.
    ///
    /// `TelegramSendHelper.sendDiffPreview`를 사용 → store에 저장하고 UUID로
    /// `yuminai://diff/<uuid>` 딥링크가 본문 마크다운에 포함된다.
    /// store가 주입되지 않았으면 발송하지 않고 종료한다.
    ///
    /// - Parameters:
    ///   - diff: raw git diff 문자열
    ///   - files: 변경 파일 수
    ///   - added: 추가 라인 수
    ///   - removed: 삭제 라인 수
    ///   - workspace: 워크스페이스 이름 (옵션)
    /// - Returns: 저장된 artifact UUID. store 미주입 시 nil.
    @discardableResult
    public func notifyDiffArtifact(
        diff: String,
        files: Int,
        added: Int,
        removed: Int,
        workspace: String?
    ) async -> UUID? {
        guard let store = artifactStore else { return nil }
        await flushAssistantBuffer()
        let target = requestChatId ?? config.chatId
        do {
            let id = try await TelegramSendHelper.sendDiffPreview(
                diff: diff,
                files: files,
                added: added,
                removed: removed,
                workspace: workspace,
                workspaceName: config.workspaceName.isEmpty ? nil : config.workspaceName,
                to: target,
                store: store,
                client: client
            )
            // streaming session reset — 다음 assistant text는 새 메시지부터.
            streamingMessageId = nil
            streamingAccumulated = ""
            return id
        } catch {
            return nil
        }
    }

    /// **ADR-098 P1-1** — build/test log artifact를 store + formatter + deep link 경로로 발송.
    ///
    /// `TelegramSendHelper.sendBuildLog`를 사용 → store에 저장하고 UUID로
    /// `yuminai://log/<uuid>` 딥링크가 본문 마크다운에 포함된다.
    ///
    /// - Parameters:
    ///   - log: 전체 로그 문자열
    ///   - title: 로그 제목 (예: "swift test")
    ///   - elapsed: 소요 시간 (초)
    ///   - success: 성공 여부
    /// - Returns: 저장된 artifact UUID. store 미주입 시 nil.
    @discardableResult
    public func notifyLogArtifact(
        log: String,
        title: String,
        elapsed: TimeInterval,
        success: Bool
    ) async -> UUID? {
        guard let store = artifactStore else { return nil }
        await flushAssistantBuffer()
        let target = requestChatId ?? config.chatId
        do {
            let id = try await TelegramSendHelper.sendBuildLog(
                log: log,
                title: title,
                elapsed: elapsed,
                success: success,
                to: target,
                workspaceName: config.workspaceName.isEmpty ? nil : config.workspaceName,
                store: store,
                client: client
            )
            streamingMessageId = nil
            streamingAccumulated = ""
            return id
        } catch {
            return nil
        }
    }

    /// bind 종료 시 cleanup.
    public func reset() async {
        flushTask?.cancel()
        flushTask = nil
        await flushAssistantBuffer()
        assistantBuffer = ""
        turnStartedAt = nil
        toolCount = 0
    }

    // MARK: - Internal

    private func scheduleFlush() {
        // 버퍼가 chunk 크기를 넘으면 즉시 flush
        if assistantBuffer.count >= config.maxChunkSize {
            Task { await flushAssistantBuffer() }
            return
        }
        // 그 외에는 debounce
        flushTask?.cancel()
        let interval = config.flushInterval
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            await self?.flushAssistantBuffer()
        }
    }

    private func flushAssistantBuffer() async {
        flushTask?.cancel()
        flushTask = nil
        let text = assistantBuffer
        guard !text.isEmpty else { return }
        assistantBuffer = ""
        // ADR-056 Phase 1 — 진짜 edit-in-place 누적
        // 1. accumulated + new text가 max 이내 → editMessageText로 한 메시지 갱신
        // 2. 넘으면 → 현재 메시지 마무리 + 새 메시지로 분리 (split)
        await appendStreaming(text)
    }

    /// **ADR-056 Phase 1** — 진짜 edit-in-place: accumulated 텍스트에 추가 후
    /// 한도 이내면 editMessageText로 갱신, 넘으면 새 메시지로 split.
    private func appendStreaming(_ chunk: String) async {
        let target = requestChatId ?? config.chatId
        let combined = streamingAccumulated + chunk

        // 누적이 한도 이내 + streaming session 있음 → edit
        if let msgId = streamingMessageId, combined.count <= Self.editAccumulatedMax {
            do {
                try await client.edit(messageId: msgId, in: target, text: combined)
                streamingAccumulated = combined
                return
            } catch {
                // edit 실패 — 새 메시지로 fallback
                streamingMessageId = nil
                streamingAccumulated = ""
            }
        }

        // streaming session 없음 또는 한도 초과 → 새 메시지로 시작
        // 한도 초과 시 chunked 분할
        let chunks = Self.chunked(chunk, maxSize: config.maxChunkSize)
        for piece in chunks {
            do {
                let sent = try await client.send(piece, to: target)
                // 첫 piece는 새 streaming session으로 등록 (다음 chunk는 edit으로 누적)
                streamingMessageId = sent.messageId
                streamingAccumulated = piece
            } catch {
                // silent fail
            }
        }
    }

    private func send(_ text: String) async {
        // ADR-045 R2.H3 — 외부 chat에서 turn 시작했으면 그 chat에 응답 (multi-chat).
        // ADR-056 Phase 1 — 별개 메시지 send (status / tool / completion 등)는 streaming session 깨고 새로 시작.
        let target = requestChatId ?? config.chatId
        _ = try? await client.send(text, to: target)
        // streaming session reset — 다음 assistant text가 새 message로 시작
        streamingMessageId = nil
        streamingAccumulated = ""
    }

    // MARK: - Helpers

    /// 텍스트를 maxSize 이하 chunk로 분할. 가능하면 줄바꿈 경계에서 자른다.
    /// ADR-046 M7 — code block (``` ... ```) 페어 보존: 분할 시 ``` 카운트가 홀수면
    /// 다음 chunk 시작 시 같은 언어 표식으로 다시 열고, 현재 chunk는 ```로 닫는다.
    static func chunked(_ text: String, maxSize: Int) -> [String] {
        guard text.count > maxSize else { return [text] }
        var chunks: [String] = []
        var remaining = text[text.startIndex..<text.endIndex]
        var carryOver: String = ""  // 이전 chunk가 code block을 열어둔 채 끝났으면 다음 chunk 시작에 ```lang 추가
        while !remaining.isEmpty {
            if remaining.count <= maxSize {
                chunks.append(carryOver + String(remaining))
                break
            }
            let cutoffIdx = remaining.index(remaining.startIndex, offsetBy: maxSize)
            // 마지막 줄바꿈/공백 찾기 (자연스러운 경계)
            let scanRange = remaining.startIndex..<cutoffIdx
            let breakIdx = remaining.range(of: "\n", options: .backwards, range: scanRange)?.lowerBound
                ?? remaining.range(of: " ", options: .backwards, range: scanRange)?.lowerBound
                ?? cutoffIdx
            let piece = String(remaining[remaining.startIndex..<breakIdx])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // 이번 piece의 ``` 페어 검사 — 홀수면 닫고, 다음 piece에 다시 열어야 함
            let combinedPiece = carryOver + piece
            let codeFenceCount = combinedPiece.components(separatedBy: "```").count - 1
            if codeFenceCount % 2 == 1 {
                // 현재 piece에 ``` 닫기 추가
                chunks.append(combinedPiece + "\n```")
                // 다음 piece 시작 시 ```언어 (또는 단순 ```)로 재오픈
                // 마지막 ``` 다음의 언어 표식 추출 (예: "```swift\n..." → "swift")
                let lang = extractLastFenceLanguage(combinedPiece)
                carryOver = "```\(lang)\n"
            } else {
                chunks.append(combinedPiece)
                carryOver = ""
            }
            // breakIdx 다음으로 이동 (구분자 skip)
            let next = remaining.index(after: breakIdx)
            remaining = remaining[next..<remaining.endIndex]
        }
        return chunks.filter { !$0.isEmpty }
    }

    /// 마지막 ``` 직후의 언어 표식 추출. 없으면 "" (단순 ```).
    private static func extractLastFenceLanguage(_ text: String) -> String {
        guard let lastFenceRange = text.range(of: "```", options: .backwards) else { return "" }
        let afterFence = text[lastFenceRange.upperBound...]
        // 첫 줄의 비공백 문자가 언어 표식
        let firstLine = afterFence.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        let lang = firstLine.trimmingCharacters(in: .whitespaces)
        return lang
    }

    /// ADR-046 M3 — tool 종류별 풍부한 summary.
    /// Bash → command, Edit/Write → 파일경로 + 첫줄, Read/Grep → 대상 path.
    /// 일반 input은 첫 줄 + maxLen cap.
    static func summarizeToolCall(name: String, input: String, maxLen: Int = 80) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return name
        }
        let lower = name.lowercased()
        // JSON input parse 시도 — Claude Code tool input은 JSON 객체
        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            switch lower {
            case "bash", "shell":
                if let cmd = json["command"] as? String {
                    return "\(name) — \(truncate(cmd.replacingOccurrences(of: "\n", with: " "), max: maxLen))"
                }
            case "edit":
                let path = (json["file_path"] as? String) ?? "?"
                let oldStr = (json["old_string"] as? String) ?? ""
                let newStr = (json["new_string"] as? String) ?? ""
                let oldLines = oldStr.split(separator: "\n").count
                let newLines = newStr.split(separator: "\n").count
                let fileName = (path as NSString).lastPathComponent
                let preview = newStr.split(separator: "\n").first.map(String.init) ?? ""
                let firstLine = truncate(preview, max: 50)
                return "\(name) \(fileName) (-\(oldLines) +\(newLines))\n  \(firstLine)"
            case "write":
                let path = (json["file_path"] as? String) ?? "?"
                let content = (json["content"] as? String) ?? ""
                let lines = content.split(separator: "\n").count
                let fileName = (path as NSString).lastPathComponent
                let preview = content.split(separator: "\n").first.map(String.init) ?? ""
                return "\(name) \(fileName) (\(lines)줄 새 작성)\n  \(truncate(preview, max: 50))"
            case "read":
                if let path = json["file_path"] as? String {
                    return "\(name) \((path as NSString).lastPathComponent)"
                }
            case "grep":
                let pattern = (json["pattern"] as? String) ?? "?"
                let path = (json["path"] as? String) ?? ""
                let pathSuffix = path.isEmpty ? "" : " in \((path as NSString).lastPathComponent)"
                return "\(name) /\(truncate(pattern, max: 40))/\(pathSuffix)"
            case "glob":
                if let pattern = json["pattern"] as? String {
                    return "\(name) \(truncate(pattern, max: maxLen))"
                }
            case "webfetch", "websearch":
                if let url = (json["url"] as? String) ?? (json["query"] as? String) {
                    return "\(name) \(truncate(url, max: maxLen))"
                }
            default:
                break
            }
        }
        // Fallback — 첫 줄 + maxLen
        let firstLine = trimmed.split(separator: "\n").first.map(String.init) ?? trimmed
        return "\(name) — \(truncate(firstLine, max: maxLen))"
    }

    private static func truncate(_ text: String, max: Int) -> String {
        text.count > max ? String(text.prefix(max)) + "…" : text
    }

    /// ADR-045 R2.H1 — destructive tool 검출 (휴리스틱).
    /// 이름 매칭 + Bash인 경우 input 키워드 검사.
    static func isDestructiveToolCall(name: String, input: String) -> Bool {
        let lowerName = name.lowercased()
        let lowerInput = input.lowercased()
        // 직접 destructive tool 이름
        if lowerName == "bash" || lowerName == "shell" {
            // 알려진 위험 패턴
            let danger = [
                "rm -rf", "rm -r ", "rm -fr",
                "git reset --hard", "git push --force", "git push -f",
                "git clean -fd", "git checkout --",
                "drop table", "drop database", "truncate ",
                "chmod -r 777", "kill -9",
                "dd if=", " > /dev/sd", "mkfs",
                "shutdown", "reboot ", "halt"
            ]
            return danger.contains { lowerInput.contains($0) }
        }
        return false
    }
}
