import Foundation

// MARK: - NotificationKind

/// **ADR-095 Phase 4** — 알림 종류.
public enum NotificationKind: String, Sendable, Codable, CaseIterable {
    /// HITL 승인 요청 — 사용자가 폰에서 approve/reject해야 하는 작업.
    case hitlApprovalRequest
    /// 작업 완료 (성공).
    case taskCompleteSuccess
    /// 작업 실패.
    case taskCompleteFailure
    /// Rate limit 경고.
    case rateLimitAlert
    /// 일반 정보성 알림.
    case generalAlert
}

// MARK: - DeviceState

/// **ADR-095 Phase 4** — 데스크탑 상태.
///
/// ADR-092 §4.8 기준:
/// - `desktopActive`: 기본값
/// - `desktopIdle`: 5분 무입력 OR `NSWorkspace.didSleepNotification`
/// - `desktopOff`: 명시적 설정 (실제 전원 OFF 감지는 후속 ADR)
///
/// **ADR-096** — `CaseIterable` 추가: UI 매트릭스 테이블 렌더링 + 테스트에서 사용.
public enum DeviceState: String, Sendable, Codable, CaseIterable {
    case desktopActive
    case desktopIdle
    case desktopOff
}

// MARK: - DeliveryChannel

/// **ADR-095 Phase 4** — 알림 전달 채널.
public enum DeliveryChannel: String, Sendable, Codable, CaseIterable {
    /// macOS 시스템 알림만.
    case macOSOnly
    /// Telegram 메시지만.
    case telegramOnly
    /// macOS + Telegram 둘 다.
    case both
    /// 억제 (로그만).
    case suppressed
}

// MARK: - NotificationPolicyMatrix

/// **ADR-095 Phase 4** — 알림 종류 × 디바이스 상태 → 전달 채널 결정 매트릭스.
///
/// ADR-092 §4.8 표를 코드화한 기본값 (`NotificationPolicyMatrix.default`).
///
/// | 알림 | active | idle | off |
/// |---|---|---|---|
/// | hitlApprovalRequest | macOSOnly | both | telegramOnly |
/// | taskCompleteSuccess | macOSOnly | suppressed | telegramOnly |
/// | taskCompleteFailure | both | both | telegramOnly |
/// | rateLimitAlert | macOSOnly | suppressed | telegramOnly |
/// | generalAlert | macOSOnly | macOSOnly | telegramOnly |
public struct NotificationPolicyMatrix: Sendable, Codable, Hashable {
    /// `[알림 종류: [디바이스 상태: 전달 채널]]` 매트릭스.
    public var rules: [NotificationKind: [DeviceState: DeliveryChannel]]

    public init(rules: [NotificationKind: [DeviceState: DeliveryChannel]]) {
        self.rules = rules
    }

    /// ADR-092 §4.8 표 그대로의 기본값.
    public static let `default` = NotificationPolicyMatrix(rules: [
        .hitlApprovalRequest: [
            .desktopActive: .macOSOnly,
            .desktopIdle:   .both,
            .desktopOff:    .telegramOnly
        ],
        .taskCompleteSuccess: [
            .desktopActive: .macOSOnly,
            .desktopIdle:   .suppressed,
            .desktopOff:    .telegramOnly
        ],
        .taskCompleteFailure: [
            .desktopActive: .both,
            .desktopIdle:   .both,
            .desktopOff:    .telegramOnly
        ],
        .rateLimitAlert: [
            .desktopActive: .macOSOnly,
            .desktopIdle:   .suppressed,
            .desktopOff:    .telegramOnly
        ],
        .generalAlert: [
            .desktopActive: .macOSOnly,
            .desktopIdle:   .macOSOnly,
            .desktopOff:    .telegramOnly
        ]
    ])

    /// 주어진 알림 종류와 디바이스 상태에 맞는 전달 채널 반환.
    ///
    /// 매트릭스에 해당 항목이 없으면 `macOSOnly` (안전 기본값) 반환.
    public func channel(for kind: NotificationKind, in state: DeviceState) -> DeliveryChannel {
        rules[kind]?[state] ?? .macOSOnly
    }
}

// MARK: - Codable (Dictionary key workaround)

// NotificationKind + DeviceState를 Dictionary key로 사용하기 위한 Codable 커스텀 구현.
// Swift의 Codable은 enum을 Dictionary key로 사용할 때 String 변환이 필요하다.

extension NotificationPolicyMatrix {
    // Swift의 기본 Codable 합성은 [Enum: [Enum: Enum]] Dictionary를
    // 자동으로 처리하지 못하므로 커스텀 encode/decode를 사용한다.
    private struct Row: Codable {
        let kind: NotificationKind
        let active: DeliveryChannel
        let idle: DeliveryChannel
        let off: DeliveryChannel
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let rows: [Row] = NotificationKind.allCases.map { kind in
            let stateMap = rules[kind] ?? [:]
            return Row(
                kind: kind,
                active: stateMap[.desktopActive] ?? .macOSOnly,
                idle: stateMap[.desktopIdle] ?? .macOSOnly,
                off: stateMap[.desktopOff] ?? .telegramOnly
            )
        }
        try container.encode(rows)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rows = try container.decode([Row].self)
        var rules: [NotificationKind: [DeviceState: DeliveryChannel]] = [:]
        for row in rows {
            rules[row.kind] = [
                .desktopActive: row.active,
                .desktopIdle: row.idle,
                .desktopOff: row.off
            ]
        }
        self.rules = rules
    }
}
