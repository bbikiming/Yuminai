import Foundation

/// **ADR-095 Phase 4** — `yuminai://` URL scheme 라우터.
///
/// 지원 경로:
/// - `yuminai://diff/{uuid}` — diff 뷰어 열기
/// - `yuminai://log/{uuid}` — 로그 뷰어 열기
/// - `yuminai://workspace/{uuid}` — 워크스페이스 선택
/// - `yuminai://chat/{int64}` — 특정 chat으로 이동
/// - `yuminai://approve/{uuid}` — HITL 승인
/// - `yuminai://reject/{uuid}` — HITL 거부
///
/// **macOS 시스템 등록**: SwiftPM executable 특성상 `.app` 번들 없이는 시스템 URL scheme 등록 불가.
/// dispatch 로직은 완비됨. 실제 시스템 등록은 정식 `.app` 번들 전환 시 처리.
public enum TelegramDeepLink: Sendable, Equatable {
    /// Git diff 뷰어 — `yuminai://diff/{uuid}`
    case diff(id: UUID)
    /// 빌드/테스트 로그 뷰어 — `yuminai://log/{uuid}`
    case log(id: UUID)
    /// 특정 워크스페이스로 이동 — `yuminai://workspace/{uuid}`
    case workspace(id: UUID)
    /// 특정 Telegram chat으로 이동 — `yuminai://chat/{int64}`
    case chat(id: Int64)
    /// HITL 승인 — `yuminai://approve/{requestId}`
    case approve(requestId: UUID)
    /// HITL 거부 — `yuminai://reject/{requestId}`
    case reject(requestId: UUID)

    // MARK: - URL 생성

    /// 이 deep link에 해당하는 `yuminai://` URL.
    public var url: URL {
        var components = URLComponents()
        components.scheme = "yuminai"
        switch self {
        case .diff(let id):
            components.host = "diff"
            components.path = "/\(id.uuidString.lowercased())"
        case .log(let id):
            components.host = "log"
            components.path = "/\(id.uuidString.lowercased())"
        case .workspace(let id):
            components.host = "workspace"
            components.path = "/\(id.uuidString.lowercased())"
        case .chat(let chatId):
            components.host = "chat"
            components.path = "/\(chatId)"
        case .approve(let requestId):
            components.host = "approve"
            components.path = "/\(requestId.uuidString.lowercased())"
        case .reject(let requestId):
            components.host = "reject"
            components.path = "/\(requestId.uuidString.lowercased())"
        }
        // URL 생성에 실패하면 fatal — scheme/host/path 모두 안전한 ASCII 문자만 사용
        guard let url = components.url else {
            preconditionFailure("Failed to construct URL for TelegramDeepLink: \(self)")
        }
        return url
    }

    // MARK: - URL 파싱

    /// `yuminai://` URL을 파싱하여 `TelegramDeepLink` 반환.
    ///
    /// 인식할 수 없는 URL이면 `nil` 반환.
    public static func parse(_ url: URL) -> TelegramDeepLink? {
        guard url.scheme?.lowercased() == "yuminai" else { return nil }

        let host = url.host?.lowercased() ?? ""
        // path에서 앞의 "/" 제거
        let pathValue = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path

        switch host {
        case "diff":
            guard let uuid = UUID(uuidString: pathValue) else { return nil }
            return .diff(id: uuid)

        case "log":
            guard let uuid = UUID(uuidString: pathValue) else { return nil }
            return .log(id: uuid)

        case "workspace":
            guard let uuid = UUID(uuidString: pathValue) else { return nil }
            return .workspace(id: uuid)

        case "chat":
            guard let chatId = Int64(pathValue) else { return nil }
            return .chat(id: chatId)

        case "approve":
            guard let uuid = UUID(uuidString: pathValue) else { return nil }
            return .approve(requestId: uuid)

        case "reject":
            guard let uuid = UUID(uuidString: pathValue) else { return nil }
            return .reject(requestId: uuid)

        default:
            return nil
        }
    }
}
