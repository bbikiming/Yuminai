import Foundation
import YuminaiCore

/// Telegram에서 받은 사용자 메시지를 라우터에 위임하고, 응답이 있으면 봇으로 반송.
///
/// `start()`로 polling 시작, `stop()`으로 정리. 라우터가 nil 반환 시 묵시적으로 무시
/// (예: 잘못된 형식의 명령).
public final actor TelegramCommandPump {
    private let client: any TelegramClient
    private let router: any TelegramCommandRouter
    private var consumeTask: Task<Void, Never>?

    public init(client: any TelegramClient, router: any TelegramCommandRouter) {
        self.client = client
        self.router = router
    }

    public func start() async throws {
        try await client.startPolling()
        guard consumeTask == nil else { return }
        let stream = client.incoming
        let router = self.router
        let client = self.client
        consumeTask = Task {
            for await message in stream {
                if Task.isCancelled { break }
                // ADR-057 Critical Fix 2 — callback 들어오면 즉시 ✓ 응답 (silent fail 방지)
                // (handler 처리 전에 ack — Telegram은 callback에 응답 없으면 사용자 화면에 spinning 표시)
                if let cbId = message.callbackQueryId {
                    _ = try? await client.answerCallback(cbId, text: nil)
                }
                let response = await router.handle(message)
                if let response {
                    _ = try? await client.send(response, to: message.chatId)
                }
            }
        }
    }

    public func stop() async {
        await client.stopPolling()
        consumeTask?.cancel()
        consumeTask = nil
    }
}

/// Telegram에서 받은 메시지를 명령으로 해석하는 책임.
///
/// 단순 echo부터 워크스페이스 활성화 / Claude에 명령 전달까지 다양한 구현 가능.
/// 구체 구현은 `YuminaiApp` 모듈 또는 사용자 코드에서.
public protocol TelegramCommandRouter: Sendable {
    /// - Returns: 봇이 사용자에게 송신할 텍스트. nil이면 응답 없음.
    func handle(_ message: IncomingTelegramMessage) async -> String?
}

/// 가장 단순한 라우터: 받은 메시지를 그대로 echo.
public struct EchoCommandRouter: TelegramCommandRouter {
    public init() {}

    public func handle(_ message: IncomingTelegramMessage) async -> String? {
        guard let text = message.text else { return nil }
        return "echo: \(text)"
    }
}
