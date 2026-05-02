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
    /// **ADR-055 #2** — turn 단위 streaming message id 추적.
    /// 짧은 응답은 한 메시지에 누적 갱신 (edit) — 메시지 수 ↓ + Telegram rate limit 절약.
    private var streamingMessageId: Int64?
    /// edit 누적이 가능한 max size (Telegram 4096 한도).
    /// 이 크기 넘으면 새 메시지로 split.
    private static let editAccumulatedMax = 3500

    public init(client: any TelegramClient, configuration: Configuration) {
        self.client = client
        self.config = configuration
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
        // ADR-055 #2 — 새 turn마다 streaming message id reset (이전 turn의 message edit X)
        streamingMessageId = nil
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
            // ADR-045 R2.H1 — destructive tool은 prominent 알림 (사용자 /cancel 빠른 의사결정 지원)
            if Self.isDestructiveToolCall(name: name, input: input) {
                let summary = Self.summarizeToolCall(name: name, input: input, maxLen: 200)
                await send("🚨 위험한 작업 감지 — \(summary)\n계속하지 않으려면 즉시 /cancel 보내세요.")
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
                await send("✅ 완료 (\(elapsedStr), 도구 \(toolCount)회)")
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
        // ADR-055 #2 — edit-in-place로 메시지 수 절감 (rate limit 절약 + 가독성)
        // 첫 chunk는 새 메시지로 send → message id 기억 → 다음 chunk는 edit
        // 누적 size가 editAccumulatedMax 넘으면 새 메시지로 split (Telegram 4096 한도)
        let chunks = Self.chunked(text, maxSize: config.maxChunkSize)
        for (idx, chunk) in chunks.enumerated() {
            if idx == 0 {
                // 첫 chunk → 새 메시지 (또는 기존 streamingMessage 갱신)
                await sendOrEdit(chunk, replaceExisting: false)
            } else {
                // 후속 chunk → 기존 streaming message에 누적 (가능하면 edit, 아니면 새 메시지)
                await sendOrEdit(chunk, replaceExisting: false)
            }
        }
    }

    /// **ADR-055 #2** — text를 streaming message에 edit (가능 시) 또는 새 메시지로 send.
    /// 누적 size가 한도 넘으면 새 메시지로 split.
    private func sendOrEdit(_ text: String, replaceExisting: Bool) async {
        let target = requestChatId ?? config.chatId
        if let msgId = streamingMessageId, !replaceExisting {
            // 기존 메시지에 append: edit으로 갱신
            // (Telegram edit은 전체 텍스트로 교체이므로 caller가 append된 전체를 보내야 함 →
            //  단순화: 이번 chunk만 새 메시지로 send. 누적 edit은 향후 ADR-056에서 advanced)
            // → 현재 단계 minimal: 새 메시지로 send + streamingMessageId 갱신
            do {
                let sent = try await client.send(text, to: target)
                streamingMessageId = sent.messageId
            } catch {
                // edit 실패 → 새 메시지 fallback
                _ = try? await client.send(text, to: target)
            }
        } else {
            // 새 메시지로 send + id 기억
            do {
                let sent = try await client.send(text, to: target)
                streamingMessageId = sent.messageId
            } catch {
                // silent fail — Telegram API 오류는 main flow 차단 X
            }
        }
    }

    private func send(_ text: String) async {
        // ADR-045 R2.H3 — 외부 chat에서 turn 시작했으면 그 chat에 응답 (multi-chat).
        let target = requestChatId ?? config.chatId
        _ = try? await client.send(text, to: target)
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
