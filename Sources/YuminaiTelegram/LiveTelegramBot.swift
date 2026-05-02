import Foundation
import YuminaiCore

/// Telegram Bot API HTTPS 클라이언트.
///
/// - 알림 송신: `send(_:to:)` / `edit(...)`
/// - 모바일 명령 수신: `incoming` + `startPolling()` (long polling, 앱 실행 중일 때만)
///
/// 화이트리스트(`allowedUserIds`)에 없는 user의 메시지는 silently drop.
public final actor LiveTelegramBot: TelegramClient {
    private let token: String
    private let allowedUserIds: Set<Int64>
    private let session: URLSession
    private let baseURL: URL

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
        session: URLSession = .shared
    ) {
        self.token = token
        self.allowedUserIds = allowedUserIds
        self.session = session
        // baseURL이 nil이 될 일이 없는 형식이지만 force-unwrap 회피
        self.baseURL = URL(string: "https://api.telegram.org/bot\(token)")
            ?? URL(string: "https://api.telegram.org")!

        var cont: AsyncStream<IncomingTelegramMessage>.Continuation!
        self.incoming = AsyncStream<IncomingTelegramMessage> { c in cont = c }
        self.incomingContinuation = cont
    }

    public func send(_ text: String, to chatId: Int64) async throws -> SentTelegramMessage {
        // ADR-045 R1.M2 — Markdown escape 누락으로 응답 누락 방지
        // 1차 시도: MarkdownV2 (escape 적용) → 실패 시 plain text fallback
        do {
            return try await sendInternal(text: text, to: chatId, parseMode: "MarkdownV2", escape: true)
        } catch let nsError as NSError where nsError.domain == "TelegramBot" && nsError.code == 400 {
            // 400 Bad Request — Markdown 파싱 실패 가능 → plain text로 재시도
            return try await sendInternal(text: text, to: chatId, parseMode: nil, escape: false)
        }
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
        while !Task.isCancelled {
            do {
                let updates = try await fetchUpdates(offset: lastUpdateId + 1)
                for update in updates {
                    if update.updateId > lastUpdateId {
                        lastUpdateId = update.updateId
                    }
                    // ADR-045 — bot reflection 방지 (allowlist 통과해도 추가 검증)
                    guard !update.isFromBot else { continue }
                    if allowedUserIds.contains(update.userId) {
                        incomingContinuation.yield(update)
                    }
                }
            } catch let nsError as NSError {
                // ADR-045 R1.H4 — auth 영구 실패는 polling 중단 (5초 retry spam 방지)
                if nsError.domain == "TelegramBot",
                   [401, 403, 404].contains(nsError.code) {
                    let reason = telegramFatalReason(code: nsError.code)
                    fatalAuthError = reason
                    return  // polling 중단
                }
                // 네트워크/일시 에러 (5xx, 429 rate limit, network timeout) — 5초 후 재시도
                try? await Task.sleep(for: .seconds(5))
            } catch {
                try? await Task.sleep(for: .seconds(5))
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
            throw NSError(
                domain: "TelegramBot",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: body]
            )
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
