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

    public init(client: any TelegramClient, configuration: Configuration) {
        self.client = client
        self.config = configuration
    }

    public func updateConfiguration(_ config: Configuration) {
        self.config = config
    }

    // MARK: - Lifecycle

    /// 새 사용자 turn 시작 — 버퍼/카운터 초기화 + "▶ 시작" 알림.
    public func notifyTurnStart(userText: String) async {
        await flushAssistantBuffer()
        turnStartedAt = Date()
        toolCount = 0
        lastFailureSent = false
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
            let summary = Self.summarizeToolCall(name: name, input: input)
            await send("🔧 \(summary)")
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
        for chunk in Self.chunked(text, maxSize: config.maxChunkSize) {
            await send(chunk)
        }
    }

    private func send(_ text: String) async {
        _ = try? await client.send(text, to: config.chatId)
    }

    // MARK: - Helpers

    /// 텍스트를 maxSize 이하 chunk로 분할. 가능하면 줄바꿈 경계에서 자른다.
    static func chunked(_ text: String, maxSize: Int) -> [String] {
        guard text.count > maxSize else { return [text] }
        var chunks: [String] = []
        var remaining = text[text.startIndex..<text.endIndex]
        while !remaining.isEmpty {
            if remaining.count <= maxSize {
                chunks.append(String(remaining))
                break
            }
            let cutoffIdx = remaining.index(remaining.startIndex, offsetBy: maxSize)
            // 마지막 줄바꿈/공백 찾기 (자연스러운 경계)
            let scanRange = remaining.startIndex..<cutoffIdx
            let breakIdx = remaining.range(of: "\n", options: .backwards, range: scanRange)?.lowerBound
                ?? remaining.range(of: " ", options: .backwards, range: scanRange)?.lowerBound
                ?? cutoffIdx
            let piece = remaining[remaining.startIndex..<breakIdx]
            chunks.append(String(piece).trimmingCharacters(in: .whitespacesAndNewlines))
            // breakIdx 다음으로 이동 (구분자 skip)
            let next = remaining.index(after: breakIdx)
            remaining = remaining[next..<remaining.endIndex]
        }
        return chunks.filter { !$0.isEmpty }
    }

    static func summarizeToolCall(name: String, input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return name
        }
        // input 첫 줄만 + 80자 cap
        let firstLine = trimmed.split(separator: "\n").first.map(String.init) ?? trimmed
        let capped = firstLine.count > 80 ? String(firstLine.prefix(80)) + "…" : firstLine
        return "\(name) — \(capped)"
    }
}
