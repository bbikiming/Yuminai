import Foundation
import YuminaiCore

/// **ADR-095 Phase 4** — `/start` 메시지 자동 감지 actor.
///
/// Onboarding Step 2에서 토큰을 받으면 즉시 `startDetecting(token:)` 호출하여
/// Telegram `getUpdates` long-polling을 시작하고, `/start` 메시지를 보낸 사용자를
/// `AsyncStream<Detection>`으로 emit한다.
///
/// wizard sheet가 닫히면 `stop()`을 호출하여 polling 중단.
///
/// **URLSession 주입**: `TelegramURLSessionProtocol` (= `YuminaiCore.TelegramURLSessionProtocol`)을 받아
/// 테스트 시 mock 교체 가능.
public actor TelegramFirstMessageDetector {

    // MARK: - Detection 결과

    /// `/start` 메시지를 보낸 사용자 정보.
    public struct Detection: Sendable, Equatable, Identifiable {
        public let id: UUID
        public let userId: Int64
        public let username: String?
        public let firstName: String
        public let chatId: Int64
        public let receivedAt: Date

        public init(
            id: UUID = UUID(),
            userId: Int64,
            username: String?,
            firstName: String,
            chatId: Int64,
            receivedAt: Date = Date()
        ) {
            self.id = id
            self.userId = userId
            self.username = username
            self.firstName = firstName
            self.chatId = chatId
            self.receivedAt = receivedAt
        }
    }

    // MARK: - 내부 상태

    private let session: any TelegramURLSessionProtocol
    private var pollingTask: Task<Void, Never>?
    private var continuation: AsyncStream<Detection>.Continuation?

    // MARK: - Init

    public init(session: any TelegramURLSessionProtocol = URLSession.shared) {
        self.session = session
    }

    // MARK: - Public API

    /// 토큰 받아서 임시 polling 시작 → 첫 `/start` 메시지 감지 → AsyncStream emit.
    ///
    /// - Parameter token: Telegram 봇 토큰 (유효한 형식이어야 함)
    /// - Returns: `AsyncStream<Detection>` — `/start`를 보낸 사용자마다 emit
    public func startDetecting(token: String) async throws -> AsyncStream<Detection> {
        // 이전 polling 중단
        pollingTask?.cancel()
        continuation?.finish()

        let trimmed = token.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw TelegramNetworkError.invalidTokenFormat("토큰이 비어있습니다")
        }

        let (stream, cont) = AsyncStream<Detection>.makeStream()
        self.continuation = cont

        let capturedSession = session
        let capturedContinuation = cont

        pollingTask = Task { [weak self] in
            await Self.runPolling(
                token: trimmed,
                session: capturedSession,
                continuation: capturedContinuation,
                actorRef: self
            )
        }

        return stream
    }

    /// polling 중단 및 stream 종료.
    public func stop() async {
        pollingTask?.cancel()
        pollingTask = nil
        continuation?.finish()
        continuation = nil
    }

    // MARK: - Polling 루프

    private static func runPolling(
        token: String,
        session: any TelegramURLSessionProtocol,
        continuation: AsyncStream<Detection>.Continuation,
        actorRef: TelegramFirstMessageDetector?
    ) async {
        var offset: Int = 0

        while !Task.isCancelled {
            do {
                let updates = try await fetchUpdates(
                    token: token,
                    offset: offset,
                    session: session
                )

                for update in updates {
                    if let maxId = updates.map(\.updateId).max() {
                        offset = maxId + 1
                    }

                    // /start 메시지만 감지
                    guard let message = update.message,
                          let text = message.text,
                          text.trimmingCharacters(in: .whitespaces).hasPrefix("/start")
                    else { continue }

                    let from = message.from
                    let detection = Detection(
                        userId: from?.id ?? message.chat.id,
                        username: from?.username,
                        firstName: from?.firstName ?? "Unknown",
                        chatId: message.chat.id,
                        receivedAt: Date(timeIntervalSince1970: TimeInterval(message.date))
                    )
                    continuation.yield(detection)
                }

            } catch is CancellationError {
                break
            } catch {
                // 네트워크 오류는 무시하고 재시도 (1초 대기)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }

        continuation.finish()
    }

    // MARK: - getUpdates API 호출

    private static func fetchUpdates(
        token: String,
        offset: Int,
        session: any TelegramURLSessionProtocol
    ) async throws -> [TelegramUpdate] {
        let urlString = "https://api.telegram.org/bot\(token)/getUpdates?offset=\(offset)&timeout=30&allowed_updates=[\"message\"]"
        guard let url = URL(string: urlString) else {
            throw TelegramNetworkError.invalidTokenFormat("URL 구성 실패")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 35.0  // long-polling 30s + 여유 5s

        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode != 200 {
            throw TelegramNetworkError.httpError(httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(TelegramUpdatesResponse.self, from: data)
        guard decoded.ok else {
            throw TelegramNetworkError.apiError(decoded.description ?? "getUpdates 실패")
        }

        return decoded.result ?? []
    }
}

// MARK: - Private response types

private struct TelegramUpdatesResponse: Decodable {
    let ok: Bool
    let result: [TelegramUpdate]?
    let description: String?
}

private struct TelegramUpdate: Decodable {
    let updateId: Int
    let message: TelegramUpdateMessage?

    enum CodingKeys: String, CodingKey {
        case updateId = "update_id"
        case message
    }
}

private struct TelegramUpdateMessage: Decodable {
    let messageId: Int
    let from: TelegramUpdateUser?
    let chat: TelegramUpdateChat
    let date: Int
    let text: String?

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case from, chat, date, text
    }
}

private struct TelegramUpdateUser: Decodable {
    let id: Int64
    let firstName: String
    let username: String?

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case username
    }
}

private struct TelegramUpdateChat: Decodable {
    let id: Int64
}
