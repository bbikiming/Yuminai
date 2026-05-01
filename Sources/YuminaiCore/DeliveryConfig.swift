import Foundation

/// 워크스페이스의 자동 build/test/lint 정책 (ADR-029, M4 delivery loop).
///
/// **참조**: Aider `--auto-test --auto-lint` 패턴 + Devin step budget hard cap.
///
/// agent turn 완료 시 자동 실행:
/// - testCommand 우선 (실패 시 lintCommand는 skip)
/// - 실패 결과 → 다음 turn 입력에 자동 prepend (mode: 소극적)
/// - max-attempts/max-time hard cap으로 무한 loop 방지
public struct DeliveryConfig: Sendable, Codable, Hashable {
    /// 워크스페이스 디렉토리에서 실행할 build 명령. nil이면 skip.
    public var buildCommand: String?
    /// 테스트 명령. agent turn 완료 시 자동 실행.
    public var testCommand: String?
    /// Lint 명령. testCommand 성공 후에 추가 실행.
    public var lintCommand: String?
    /// 자동 실행 활성. false면 사용자 수동만 (Inspector "변경" 탭에서).
    public var autoRunOnTurnComplete: Bool
    /// agent에 자동으로 실패 결과를 prepend할지 (소극적 fix loop).
    public var autoFeedFailureToAgent: Bool
    /// Hard cap (Devin pattern) — 이 횟수만큼 자동 fix 시도 후 사용자 에스컬레이션.
    public var maxAttempts: Int
    /// 단일 명령 실행 타임아웃 (초).
    public var timeoutSeconds: Int

    public init(
        buildCommand: String? = nil,
        testCommand: String? = nil,
        lintCommand: String? = nil,
        autoRunOnTurnComplete: Bool = false,
        autoFeedFailureToAgent: Bool = true,
        maxAttempts: Int = 3,
        timeoutSeconds: Int = 300
    ) {
        self.buildCommand = buildCommand
        self.testCommand = testCommand
        self.lintCommand = lintCommand
        self.autoRunOnTurnComplete = autoRunOnTurnComplete
        self.autoFeedFailureToAgent = autoFeedFailureToAgent
        self.maxAttempts = maxAttempts
        self.timeoutSeconds = timeoutSeconds
    }

    public static let disabled = DeliveryConfig()

    /// 어느 명령이라도 정의돼 있으면 활성 가능.
    public var hasAnyCommand: Bool {
        !(testCommand?.isEmpty ?? true)
            || !(buildCommand?.isEmpty ?? true)
            || !(lintCommand?.isEmpty ?? true)
    }
}

/// Delivery 실행 결과 — UI 표시 + agent feedback에 사용.
public struct DeliveryResult: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let kind: Kind
    public let command: String
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let durationMs: Int
    public let attempt: Int
    public let timedOut: Bool
    public let startedAt: Date

    public init(
        id: UUID = UUID(),
        kind: Kind,
        command: String,
        exitCode: Int32,
        stdout: String,
        stderr: String,
        durationMs: Int,
        attempt: Int,
        timedOut: Bool = false,
        startedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.command = command
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.durationMs = durationMs
        self.attempt = attempt
        self.timedOut = timedOut
        self.startedAt = startedAt
    }

    public var success: Bool { !timedOut && exitCode == 0 }

    public enum Kind: String, Sendable, Codable, Hashable {
        case build, test, lint

        public var label: String {
            switch self {
            case .build: return "빌드"
            case .test: return "테스트"
            case .lint: return "린트"
            }
        }

        public var icon: String {
            switch self {
            case .build: return "hammer"
            case .test: return "checkmark.shield"
            case .lint: return "magnifyingglass"
            }
        }
    }

    /// 다음 agent turn에 prepend할 텍스트 (실패 시).
    public func failurePromptPrefix() -> String {
        let header = timedOut
            ? "[\(kind.label) 실패 — \(timeoutSeconds())초 타임아웃 (시도 \(attempt))]"
            : "[\(kind.label) 실패 — exit \(exitCode) (시도 \(attempt))]"
        let cmd = "$ \(command)"
        let stderrTail = Self.tail(stderr, lines: 50)
        let stdoutTail = stderrTail.isEmpty ? Self.tail(stdout, lines: 30) : ""
        var sections: [String] = [header, cmd]
        if !stderrTail.isEmpty { sections.append("--- stderr ---\n\(stderrTail)") }
        if !stdoutTail.isEmpty { sections.append("--- stdout ---\n\(stdoutTail)") }
        sections.append("위 실패를 분석하고 수정해주세요.")
        return sections.joined(separator: "\n\n") + "\n\n"
    }

    private func timeoutSeconds() -> Int { durationMs / 1000 }

    public static func tail(_ text: String, lines: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let allLines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        guard allLines.count > lines else { return trimmed }
        let tailed = allLines.suffix(lines).joined(separator: "\n")
        return "...(앞부분 \(allLines.count - lines)줄 생략)\n\(tailed)"
    }
}
