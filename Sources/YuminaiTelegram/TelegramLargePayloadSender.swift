import Foundation
import YuminaiCore

/// **ADR-097** — 메시지 크기에 따라 `send` vs `sendDocument` 자동 선택.
///
/// 규칙:
/// - text byteCount < 4000: `client.send(text, to:)`
/// - 4000 ≤ size < 5MB: `client.send(truncated + warning, to:)`
/// - size ≥ 5MB: `client.sendDocument(fileName:data:caption:to:)`
/// - 50MB+: 에러 throw (Telegram 한도)
///
/// `TelegramMessageFormatter.shouldSendAsDocument(byteCount:)` 활용 (ADR-095).
public enum TelegramLargePayloadSender {

    // MARK: - Constants

    /// Telegram 메시지 4096자 제한의 보수적 마진.
    static let smallThreshold = 4000
    /// 5MB — sendDocument 전환 기준.
    static let largeThreshold = 5 * 1024 * 1024
    /// 50MB — Telegram 최대 파일 크기.
    static let absoluteMax = 50 * 1024 * 1024

    // MARK: - Routing Decision

    /// 메시지 크기에 따른 라우팅 결정.
    public enum RoutingDecision: Sendable, Equatable {
        case send           // < 4000 bytes
        case sendTruncated  // 4000 ..< 5MB
        case sendDocument   // >= 5MB
    }

    public static func routingDecision(byteCount: Int) -> RoutingDecision {
        if byteCount >= largeThreshold {
            return .sendDocument
        } else if byteCount >= smallThreshold {
            return .sendTruncated
        } else {
            return .send
        }
    }

    // MARK: - Send or Attach

    /// 메시지 크기에 따라 send/sendDocument를 자동으로 선택한다.
    ///
    /// - Parameters:
    ///   - text: 전송할 전체 텍스트.
    ///   - fileName: sendDocument 시 사용할 파일명 (확장자 포함).
    ///   - caption: sendDocument caption (짧은 preview, 1024자 이하).
    ///   - chatId: 대상 chat ID.
    ///   - client: TelegramClient 구현체.
    /// - Throws: 50MB 초과 시 에러.
    @discardableResult
    public static func sendOrAttach(
        text: String,
        fileName: String,
        caption: String,
        to chatId: Int64,
        client: any TelegramClient
    ) async throws -> SentTelegramMessage {
        guard let data = text.data(using: .utf8) else {
            throw TelegramLargePayloadError.encodingFailed
        }

        let byteCount = data.count

        if byteCount >= absoluteMax {
            throw TelegramLargePayloadError.exceedsAbsoluteMax(byteCount: byteCount)
        }

        switch routingDecision(byteCount: byteCount) {
        case .send:
            return try await client.send(text, to: chatId)

        case .sendTruncated:
            let truncated = TelegramMessageFormatter.enforceMaxBytes(text, maxBytes: smallThreshold - 100)
            let warned = truncated + "\n\n⚠️ 메시지가 길어 일부 생략됨"
            return try await client.send(warned, to: chatId)

        case .sendDocument:
            return try await client.sendDocument(
                fileName: fileName,
                data: data,
                caption: String(caption.prefix(1024)),
                to: chatId
            )
        }
    }
}

// MARK: - Error

public enum TelegramLargePayloadError: Error, Sendable, Equatable {
    case encodingFailed
    case exceedsAbsoluteMax(byteCount: Int)
}
