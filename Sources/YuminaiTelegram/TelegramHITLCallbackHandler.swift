import Foundation
import YuminaiCore

/// **ADR-094 Phase 3** — Telegram inline button callback을 HITL 응답으로 변환.
///
/// `callbackData` 형식: `"hitl:approve:{uuid}"` 또는 `"hitl:reject:{uuid}"`
///
/// TelegramCommandPump의 메시지 루프에서 callbackData가 "hitl:" prefix일 때 호출된다.
public struct TelegramHITLCallbackHandler: Sendable {

    public init() {}

    /// callback_data 문자열이 HITL prefix인지 확인.
    public func isHITLCallback(_ data: String) -> Bool {
        data.hasPrefix("hitl:")
    }

    /// callback_data를 파싱해 (action, UUID)를 반환. 파싱 실패 시 nil.
    public func parse(_ data: String) -> (action: HITLAction, id: UUID)? {
        // 형식: "hitl:approve:<uuid>" or "hitl:reject:<uuid>"
        let parts = data.split(separator: ":", maxSplits: 2)
        guard parts.count == 3,
              parts[0] == "hitl",
              let action = HITLAction(rawValue: String(parts[1])),
              let id = UUID(uuidString: String(parts[2]))
        else {
            return nil
        }
        return (action, id)
    }

    /// HITL callback을 처리해 coordinator에 응답을 주입하고 ack 텍스트를 반환.
    public func handle(
        message: IncomingTelegramMessage,
        coordinator: TelegramHITLCoordinator
    ) async -> String? {
        guard let cbData = message.callbackData,
              isHITLCallback(cbData),
              let (action, id) = parse(cbData)
        else {
            return nil
        }

        let by = message.callbackData != nil
            ? "user:\(message.userId)"
            : "user:\(message.userId)"

        let response: TelegramHITLCoordinator.HITLResponse
        switch action {
        case .approve:
            response = .approved(by: by)
        case .reject:
            response = .rejected(by: by)
        }

        await coordinator.respond(id: id, response: response)
        return action == .approve ? "✅ Approved" : "❌ Rejected"
    }

    /// HITL callback_data용 action 종류.
    public enum HITLAction: String, Sendable {
        case approve
        case reject

        /// InlineButton callbackData 형식으로 인코딩.
        public func callbackData(for requestId: UUID) -> String {
            "hitl:\(rawValue):\(requestId.uuidString)"
        }
    }
}
