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
        let url = baseURL.appendingPathComponent("sendMessage")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "chat_id": chatId,
            "text": text,
            "parse_mode": "Markdown"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let result = json?["result"] as? [String: Any]
        let messageId = LiveTelegramBot.coerceInt64(result?["message_id"]) ?? 0
        return SentTelegramMessage(messageId: messageId, chatId: chatId)
    }

    public func edit(messageId: Int64, in chatId: Int64, text: String) async throws {
        let url = baseURL.appendingPathComponent("editMessageText")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "chat_id": chatId,
            "message_id": messageId,
            "text": text,
            "parse_mode": "Markdown"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
    }

    public func startPolling() async throws {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    public func stopPolling() async {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            do {
                let updates = try await fetchUpdates(offset: lastUpdateId + 1)
                for update in updates {
                    if update.updateId > lastUpdateId {
                        lastUpdateId = update.updateId
                    }
                    if allowedUserIds.contains(update.userId) {
                        incomingContinuation.yield(update)
                    }
                }
            } catch {
                // 네트워크/일시 에러 — 5초 후 재시도
                try? await Task.sleep(for: .seconds(5))
            }
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
            URLQueryItem(name: "allowed_updates", value: "[\"message\"]")
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
        guard let updateId = coerceInt64(raw["update_id"]),
              let message = raw["message"] as? [String: Any],
              let from = message["from"] as? [String: Any],
              let userId = coerceInt64(from["id"]),
              let chat = message["chat"] as? [String: Any],
              let chatId = coerceInt64(chat["id"])
        else {
            return nil
        }
        return IncomingTelegramMessage(
            updateId: updateId,
            userId: userId,
            chatId: chatId,
            text: message["text"] as? String
        )
    }

    private static func coerceInt64(_ any: Any?) -> Int64? {
        if let v = any as? Int64 { return v }
        if let v = any as? Int { return Int64(v) }
        if let v = any as? NSNumber { return v.int64Value }
        return nil
    }
}
