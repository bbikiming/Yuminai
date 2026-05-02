import Foundation

/// 다중 터미널 세션 단위 (ADR-040 T1, ADR-041 T10/T11/T13 확장).
///
/// **사용 패턴**:
/// - 워크스페이스 별 N개 세션 (default: 1, max: 10)
/// - 각 세션은 자체 SwiftTerm process (독립 zsh) — UI에서 NSViewRepresentable id로 식별
/// - label은 사용자 정의 (default: "터미널 1", "터미널 2"...)
/// - workingDirectory는 세션 별 — 사용자가 일부 터미널만 다른 디렉토리에서 시작 가능 (ADR-041 T11)
///
/// **단순화**:
/// - 세션 자체는 process state를 직접 갖지 않음 — process는 SwiftTerm view 내부에 lifecycle 종속
/// - 세션 close → view dispose → process SIGTERM (SwiftTerm 자동)
/// - activity는 휴리스틱 (PTY data 도착 시간 기반) — OSC 133 semantic prompts는 zsh 기본 미지원
public struct TerminalSession: Sendable, Identifiable, Equatable, Hashable, Codable {
    public let id: UUID
    public var label: String
    public var workingDirectory: String
    public let createdAt: Date
    /// 활동 상태 (UI 표시용, 영속 X — Codable에서 제외) — ADR-041 T10
    public var activity: Activity = .idle
    /// 백그라운드(비활성) 상태에서 새 출력이 있었는지 — 알림 dot 표시 — ADR-041 T10
    public var hasUnreadOutput: Bool = false

    public enum Activity: String, Sendable, Equatable, Hashable {
        /// 아무 데이터도 없거나 prompt 대기 상태.
        case idle
        /// 최근 1초 이내에 PTY 출력이 있었음 — 명령 실행 중으로 추정.
        case running
        /// 최근(<3초) 명령 종료 직후 — 짧게 체크 표시 후 idle로.
        case completedRecently
    }

    public init(
        id: UUID = UUID(),
        label: String,
        workingDirectory: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.label = label
        self.workingDirectory = workingDirectory
        self.createdAt = createdAt
    }

    /// 인덱스 기반 default label (생성 순서).
    public static func defaultLabel(index: Int) -> String {
        "터미널 \(index + 1)"
    }

    // MARK: - Codable (activity/hasUnreadOutput는 영속 X — 매 세션 fresh)

    private enum CodingKeys: String, CodingKey {
        case id, label, workingDirectory, createdAt
    }
}
