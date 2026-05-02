import Foundation

/// 다중 터미널 세션 단위 (ADR-040 T1).
///
/// **사용 패턴**:
/// - 워크스페이스 별 N개 세션 (default: 1, max: 10)
/// - 각 세션은 자체 SwiftTerm process (독립 zsh) — UI에서 NSViewRepresentable id로 식별
/// - label은 사용자 정의 (default: "터미널 1", "터미널 2"...)
/// - workingDirectory는 세션 별 — 사용자가 일부 터미널만 다른 디렉토리에서 시작 가능 (v1.2+)
///
/// **단순화**:
/// - 세션 자체는 process state를 직접 갖지 않음 — process는 SwiftTerm view 내부에 lifecycle 종속
/// - 세션 close → view dispose → process SIGTERM (SwiftTerm 자동)
public struct TerminalSession: Sendable, Identifiable, Equatable, Hashable, Codable {
    public let id: UUID
    public var label: String
    public var workingDirectory: String
    public let createdAt: Date

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
}
