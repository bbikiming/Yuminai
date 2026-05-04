import Foundation
import YuminaiCore

/// Telegram Bot API HTTPS 클라이언트.
///
/// - 알림 송신: `send(_:to:)` / `edit(...)`
/// - 모바일 명령 수신: `incoming` + `startPolling()` (long polling, 앱 실행 중일 때만)
///
/// 화이트리스트(`allowedUserIds`)에 없는 user의 메시지는 silently drop.
///
/// **ADR-085** — Codex 협업 검수 반영:
/// - Rate limiter (per-chat token bucket)
/// - Retry policy (exponential backoff + jitter + Retry-After 존중)
/// - Health monitor (connection state observable)
/// - Idempotency tracker (update_id + message hash dedup)
/// - Error log (ring buffer)
public final actor LiveTelegramBot: TelegramClient {
    private let token: String
    private let allowedUserIds: Set<Int64>
    private let session: URLSession
    private let baseURL: URL

    // ADR-085 안정성 인프라 (모두 actor — concurrent safe)
    public let rateLimiter: TelegramRateLimiter
    public let healthMonitor: TelegramHealthMonitor
    public let errorLog: TelegramErrorLog
    public let idempotency: TelegramIdempotencyTracker
    public let retryPolicy: TelegramRetryPolicy
    /// **ADR-086 Phase 2** — Network failure 시 메시지 보관 → 복구 시 재전송.
    public let offlineQueue: TelegramOfflineQueue

    private var pollingTask: Task<Void, Never>?
    private var lastUpdateId: Int64 = 0
    /// ADR-045 R1.H4 — auth 영구 실패 (401/403/404) 시 polling 중단 + 사용자 알림용 fatal 상태.
    /// `fatalAuthError`는 외부에서 read 가능 — UI가 "Bot 토큰 만료" 안내.
    public private(set) var fatalAuthError: String?

    public nonisolated let incoming: AsyncStream<IncomingTelegramMessage>
    private nonisolated let incomingContinuation: AsyncStream<IncomingTelegramMessage>.Continuation

    public init(
        token: String,
        allowedUserIds: Set<Int64>,
        session: URLSession = .shared,
        retryPolicy: TelegramRetryPolicy = .default
    ) {
        self.token = token
        self.allowedUserIds = allowedUserIds
        self.session = session
        self.baseURL = URL(string: "https://api.telegram.org/bot\(token)")
            ?? URL(string: "https://api.telegram.org")!
        self.retryPolicy = retryPolicy
        self.rateLimiter = TelegramRateLimiter()
        self.healthMonitor = TelegramHealthMonitor()
        self.errorLog = TelegramErrorLog()
        self.idempotency = TelegramIdempotencyTracker()
        self.offlineQueue = TelegramOfflineQueue()

        var cont: AsyncStream<IncomingTelegramMessage>.Continuation!
        self.incoming = AsyncStream<IncomingTelegramMessage> { c in cont = c }
        self.incomingContinuation = cont
    }

    public func send(_ text: String, to chatId: Int64) async throws -> SentTelegramMessage {
        // ADR-085 — Rate limiter 적용 (per-chat token bucket)
        await rateLimiter.acquire(chatId: chatId)
        // ADR-085 — Retry policy 적용 (exponential backoff + jitter)
        return try await withRetry(operation: "send", chatId: chatId) {
            // ADR-045 R1.M2 — Markdown escape 누락으로 응답 누락 방지
            do {
                return try await self.sendInternal(text: text, to: chatId, parseMode: "MarkdownV2", escape: true)
            } catch let nsError as NSError where nsError.domain == "TelegramBot" && nsError.code == 400 {
                // 400 Bad Request — Markdown 파싱 실패 → plain text 재시도 (이건 retry policy 외)
                return try await self.sendInternal(text: text, to: chatId, parseMode: nil, escape: false)
            }
        }
    }

    /// **ADR-086 Phase 2** — `send()`를 시도하되, network 오류 발생 시 offline queue에 enqueue.
    /// botId는 호출자가 제공해야 (멀티 봇 식별용; 단일 봇 모드면 zero UUID).
    /// - Returns: `SentTelegramMessage` (성공) 또는 `nil` (queue됨).
    @discardableResult
    public func sendOrEnqueue(_ text: String, to chatId: Int64, botId: UUID = UUID()) async -> SentTelegramMessage? {
        do {
            let result = try await send(text, to: chatId)
            // 성공 시 큐 flush 시도 (network 복구 후 자연스러운 retry trigger)
            await flushOfflineQueueIfPossible()
            return result
        } catch {
            // Network 또는 transient error → enqueue
            let pending = PendingTelegramMessage(
                botId: botId,
                chatId: chatId,
                text: text
            )
            await offlineQueue.enqueue(pending)
            return nil
        }
    }

    /// **ADR-086 Phase 2** — Offline queue를 flush. 성공한 메시지는 제거, 실패는 attempt + 1.
    /// - Returns: (sent, dropped) tuple.
    @discardableResult
    public func flushOfflineQueueIfPossible() async -> (sent: Int, dropped: Int) {
        return await offlineQueue.flush { [weak self] msg in
            guard let self else { return false }
            do {
                _ = try await self.send(msg.text, to: msg.chatId)
                return true
            } catch {
                return false
            }
        }
    }

    /// **ADR-085** — 재시도 가능한 operation wrapper.
    /// - Auth 실패 (401/403/404) → 즉시 throw (retry 무의미)
    /// - 429 → Retry-After 존중
    /// - 5xx / network → exponential backoff retry
    /// - 그 외 → 즉시 throw
    private func withRetry<T>(
        operation: String,
        chatId: Int64? = nil,
        block: () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 0..<retryPolicy.maxAttempts {
            do {
                let result = try await block()
                return result
            } catch let nsError as NSError {
                lastError = nsError
                // Auth 실패는 retry 무의미
                if nsError.domain == "TelegramBot",
                   [401, 403, 404, 400].contains(nsError.code) {
                    let entry = TelegramErrorClassifier.classify(nsError)
                    await errorLog.record(entry)
                    throw nsError
                }
                // Retry 가능 — log + sleep
                let entry = TelegramErrorClassifier.classify(nsError)
                await errorLog.record(entry)
                await healthMonitor.recordTransientFailure(entry.userFacingMessage)
                if !retryPolicy.shouldRetry(attempt: attempt) {
                    throw nsError
                }
                // Retry-After header 추출 (429 케이스)
                let retryAfter = (nsError.userInfo["Retry-After"] as? Double)
                let delay = retryPolicy.delay(forAttempt: attempt, retryAfterSeconds: retryAfter)
                try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    private func sendInternal(text: String, to chatId: Int64, parseMode: String?, escape: Bool) async throws -> SentTelegramMessage {
        let url = baseURL.appendingPathComponent("sendMessage")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "chat_id": chatId,
            "text": escape ? Self.escapeMarkdownV2(text) : text
        ]
        if let parseMode { body["parse_mode"] = parseMode }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let result = json?["result"] as? [String: Any]
        let messageId = LiveTelegramBot.coerceInt64(result?["message_id"]) ?? 0
        return SentTelegramMessage(messageId: messageId, chatId: chatId)
    }

    /// **ADR-056 Phase 2** — inline keyboard 첨부 메시지.
    /// reply_markup.inline_keyboard 필드로 전달 — 사용자가 클릭하면 callback_query update.
    public func sendWithKeyboard(
        _ text: String,
        to chatId: Int64,
        buttons: [[InlineButton]]
    ) async throws -> SentTelegramMessage {
        do {
            return try await sendWithKeyboardInternal(text: text, to: chatId, buttons: buttons, parseMode: "MarkdownV2", escape: true)
        } catch let nsError as NSError where nsError.domain == "TelegramBot" && nsError.code == 400 {
            return try await sendWithKeyboardInternal(text: text, to: chatId, buttons: buttons, parseMode: nil, escape: false)
        }
    }

    private func sendWithKeyboardInternal(
        text: String,
        to chatId: Int64,
        buttons: [[InlineButton]],
        parseMode: String?,
        escape: Bool
    ) async throws -> SentTelegramMessage {
        let url = baseURL.appendingPathComponent("sendMessage")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // inline_keyboard: [[ {text, callback_data} ]]
        let keyboard = buttons.map { row in
            row.map { ["text": $0.text, "callback_data": $0.callbackData] }
        }
        let replyMarkup: [String: Any] = ["inline_keyboard": keyboard]
        var body: [String: Any] = [
            "chat_id": chatId,
            "text": escape ? Self.escapeMarkdownV2(text) : text,
            "reply_markup": replyMarkup
        ]
        if let parseMode { body["parse_mode"] = parseMode }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let result = json?["result"] as? [String: Any]
        let messageId = LiveTelegramBot.coerceInt64(result?["message_id"]) ?? 0
        return SentTelegramMessage(messageId: messageId, chatId: chatId)
    }

    /// **ADR-057 Phase 1** — Telegram bot API answerCallbackQuery.
    /// 사용자가 inline keyboard 클릭 시 ✓ 표시 (또는 작은 toast 텍스트).
    public func answerCallback(_ callbackQueryId: String, text: String?) async throws {
        let url = baseURL.appendingPathComponent("answerCallbackQuery")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["callback_query_id": callbackQueryId]
        if let text { body["text"] = String(text.prefix(200)) }  // Telegram 한도
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
    }

    public func edit(messageId: Int64, in chatId: Int64, text: String) async throws {
        do {
            try await editInternal(messageId: messageId, in: chatId, text: text, parseMode: "MarkdownV2", escape: true)
        } catch let nsError as NSError where nsError.domain == "TelegramBot" && nsError.code == 400 {
            try await editInternal(messageId: messageId, in: chatId, text: text, parseMode: nil, escape: false)
        }
    }

    private func editInternal(messageId: Int64, in chatId: Int64, text: String, parseMode: String?, escape: Bool) async throws {
        let url = baseURL.appendingPathComponent("editMessageText")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "chat_id": chatId,
            "message_id": messageId,
            "text": escape ? Self.escapeMarkdownV2(text) : text
        ]
        if let parseMode { body["parse_mode"] = parseMode }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
    }

    /// ADR-045 R1.M2 — MarkdownV2 reserved char escape.
    /// 공식: _ * [ ] ( ) ~ ` > # + - = | { } . !
    /// code block 내부는 escape 안 함 (``` ... ``` 페어 보존).
    nonisolated static func escapeMarkdownV2(_ text: String) -> String {
        let reserved: Set<Character> = ["_", "*", "[", "]", "(", ")", "~", "`", ">", "#", "+", "-", "=", "|", "{", "}", ".", "!", "\\"]
        var output = ""
        output.reserveCapacity(text.count + text.count / 4)
        var inCodeBlock = false
        var inInlineCode = false
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            // Code block 페어 (``` ... ```) 보존
            if c == "`" {
                let remaining = text.distance(from: i, to: text.endIndex)
                if remaining >= 3 && text[i...].hasPrefix("```") {
                    inCodeBlock.toggle()
                    output.append("```")
                    i = text.index(i, offsetBy: 3)
                    continue
                }
                if !inCodeBlock {
                    inInlineCode.toggle()
                    output.append("`")
                    i = text.index(after: i)
                    continue
                }
            }
            // Code block / inline code 내부는 escape 안 함 (단, ``` 자체는 escape 필요 X)
            if inCodeBlock || inInlineCode {
                output.append(c)
            } else if reserved.contains(c) {
                output.append("\\")
                output.append(c)
            } else {
                output.append(c)
            }
            i = text.index(after: i)
        }
        return output
    }

    public func startPolling() async throws {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    public func stopPolling() async {
        pollingTask?.cancel()
        // ADR-045 R1.M6 — long-poll 진행 중인 task 완료 대기 (race 방지)
        // 단, cancel 후에도 30초 long-poll이 끝날 때까지 대기하면 너무 오래 걸리므로 timeout 적용
        let task = pollingTask
        pollingTask = nil
        if let task {
            // 최대 1초 대기 — long-poll은 cancel 신호 받으면 빠르게 끝남
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await task.value }
                group.addTask { try? await Task.sleep(for: .seconds(1)) }
                _ = await group.next()
                group.cancelAll()
            }
        }
    }

    private func pollLoop() async {
        var consecutiveFailures = 0
        while !Task.isCancelled {
            do {
                let updates = try await fetchUpdates(offset: lastUpdateId + 1)
                consecutiveFailures = 0  // 성공 시 reset

                var processed = 0
                for update in updates {
                    if update.updateId > lastUpdateId {
                        lastUpdateId = update.updateId
                    }
                    // ADR-085 Phase 1 — Idempotency check (update_id dedup)
                    let isNew = await idempotency.acquire(updateId: update.updateId)
                    guard isNew else { continue }

                    // ADR-045 — bot reflection 방지
                    guard !update.isFromBot else { continue }
                    if allowedUserIds.contains(update.userId) {
                        // ADR-085 Phase 1 — message hash dedup (1분 window)
                        let hash = "\(update.chatId)|\(update.text ?? "")|\(Int(update.receivedAt.timeIntervalSince1970 / 60))"
                        if await idempotency.acquireMessageHash(hash) {
                            incomingContinuation.yield(update)
                            processed += 1
                        }
                    }
                }
                // ADR-085 Phase 2 — health 성공 기록
                await healthMonitor.recordSuccess(updatesProcessed: processed)
            } catch let nsError as NSError {
                // ADR-045 R1.H4 — auth 영구 실패는 polling 중단
                if nsError.domain == "TelegramBot",
                   [401, 403, 404].contains(nsError.code) {
                    let reason = telegramFatalReason(code: nsError.code)
                    fatalAuthError = reason
                    let entry = TelegramErrorClassifier.classify(nsError)
                    await errorLog.record(entry)
                    await healthMonitor.recordPermanentFailure(reason)
                    return  // polling 중단
                }
                // ADR-085 Phase 1 — Exponential backoff + jitter (fixed 5초 X)
                let entry = TelegramErrorClassifier.classify(nsError)
                await errorLog.record(entry)
                await healthMonitor.recordTransientFailure(entry.userFacingMessage)
                let retryAfter = nsError.userInfo["Retry-After"] as? Double
                let delay = retryPolicy.delay(forAttempt: consecutiveFailures, retryAfterSeconds: retryAfter)
                consecutiveFailures += 1
                try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
            } catch {
                let entry = TelegramErrorClassifier.classify(error)
                await errorLog.record(entry)
                await healthMonitor.recordTransientFailure(entry.userFacingMessage)
                let delay = retryPolicy.delay(forAttempt: consecutiveFailures)
                consecutiveFailures += 1
                try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
            }
        }
    }

    private nonisolated func telegramFatalReason(code: Int) -> String {
        switch code {
        case 401: return "Telegram bot 토큰이 invalid (Unauthorized). BotFather에서 새 토큰 발급 후 설정에서 교체하세요."
        case 403: return "Telegram bot이 차단 또는 제거됨 (Forbidden). 사용자가 봇을 다시 시작하거나 chat에서 추가 후 재시도."
        case 404: return "Telegram API 경로 오류 (Not Found). 토큰 형식이 올바른지 확인."
        default: return "Telegram auth 실패 (\(code))"
        }
    }

    private func fetchUpdates(offset: Int64) async throws -> [IncomingTelegramMessage] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("getUpdates"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "timeout", value: "30"),
            // ADR-056 Phase 2 — message + callback_query (inline keyboard 클릭) 모두 받음
            URLQueryItem(name: "allowed_updates", value: "[\"message\",\"callback_query\"]")
        ]
        guard let url = components?.url else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 60

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let array = json?["result"] as? [[String: Any]] else { return [] }

        return array.compactMap(LiveTelegramBot.parseUpdate)
    }

    private nonisolated func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard 200...299 ~= http.statusCode else {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            // ADR-085 — Retry-After header를 NSError userInfo에 포함 (retry policy가 활용)
            var userInfo: [String: Any] = [NSLocalizedDescriptionKey: body]
            if let retryAfter = TelegramErrorClassifier.retryAfterSeconds(from: http.allHeaderFields) {
                userInfo["Retry-After"] = retryAfter
            }
            // 429 응답은 Telegram이 JSON body에 parameters.retry_after 줄 수 있음
            if http.statusCode == 429,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let params = json["parameters"] as? [String: Any],
               let retryAfter = params["retry_after"] as? Double {
                userInfo["Retry-After"] = retryAfter
            }
            throw NSError(
                domain: "TelegramBot",
                code: http.statusCode,
                userInfo: userInfo
            )
        }
    }

    // MARK: - ADR-094 Phase 3 — BotFather setMyCommands

    /// Telegram setMyCommands API 호출.
    /// `commands` 배열의 command는 "/" prefix 없이 전달 (Telegram 규격).
    /// command 최대 32자, description 최대 256자로 자동 truncate.
    public func setMyCommands(_ commands: [(command: String, description: String)]) async throws {
        let url = baseURL.appendingPathComponent("setMyCommands")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let mapped = commands.map { pair -> [String: String] in
            let cmd = String(pair.command.prefix(32))
            let desc = String(pair.description.prefix(256))
            return ["command": cmd, "description": desc]
        }
        let body: [String: Any] = ["commands": mapped]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard json?["ok"] as? Bool == true else {
            throw NSError(domain: "TelegramBot", code: -1, userInfo: [NSLocalizedDescriptionKey: "setMyCommands: ok=false"])
        }
    }

    private static func parseUpdate(_ raw: [String: Any]) -> IncomingTelegramMessage? {
        guard let updateId = coerceInt64(raw["update_id"]) else { return nil }
        // ADR-056 Phase 2 + ADR-057 Phase 1 — callback_query parse (callbackQueryId 포함)
        if let callback = raw["callback_query"] as? [String: Any],
           let from = callback["from"] as? [String: Any],
           let userId = coerceInt64(from["id"]),
           let message = callback["message"] as? [String: Any],
           let chat = message["chat"] as? [String: Any],
           let chatId = coerceInt64(chat["id"]) {
            let isBot = (from["is_bot"] as? Bool) ?? false
            let callbackData = callback["data"] as? String
            let callbackQueryId = callback["id"] as? String  // ADR-057
            return IncomingTelegramMessage(
                updateId: updateId,
                userId: userId,
                chatId: chatId,
                text: nil,
                isFromBot: isBot,
                callbackData: callbackData,
                callbackQueryId: callbackQueryId
            )
        }
        // 일반 message
        guard let message = raw["message"] as? [String: Any],
              let from = message["from"] as? [String: Any],
              let userId = coerceInt64(from["id"]),
              let chat = message["chat"] as? [String: Any],
              let chatId = coerceInt64(chat["id"])
        else {
            return nil
        }
        // ADR-045 — bot reflection 방지 (다른 봇이 보낸 메시지 차단)
        let isBot = (from["is_bot"] as? Bool) ?? false
        return IncomingTelegramMessage(
            updateId: updateId,
            userId: userId,
            chatId: chatId,
            text: message["text"] as? String,
            isFromBot: isBot
        )
    }

    private static func coerceInt64(_ any: Any?) -> Int64? {
        if let v = any as? Int64 { return v }
        if let v = any as? Int { return Int64(v) }
        if let v = any as? NSNumber { return v.int64Value }
        return nil
    }
}
