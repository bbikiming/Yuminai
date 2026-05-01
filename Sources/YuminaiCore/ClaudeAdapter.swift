import Foundation

/// Claude Code CLI를 자식 프로세스로 spawn하고 GUI에 stream으로 노출하는 추상화.
///
/// 구현체는 `YuminaiClaudeAdapter` 모듈에 있다(`LiveClaudeAdapter`, `MockClaudeAdapter`).
public protocol ClaudeAdapter: Sendable {
    /// 워크스페이스 디렉토리에서 Claude CLI를 실행하고 입출력 세션을 반환한다.
    func spawn(in workspace: Workspace) async throws -> any ClaudeStreamSession

    /// 진행 중인 세션을 graceful 종료(SIGTERM → 0.5s → SIGKILL)한다.
    func terminate(_ session: any ClaudeStreamSession) async

    /// 다음 `spawn`부터 적용될 활성 세션 설정 갱신.
    func updateSettings(_ settings: SessionSettings) async

    /// 현재 활성 세션 설정.
    func currentSettings() async -> SessionSettings
}

/// Claude CLI와의 단일 stream 세션.
public protocol ClaudeStreamSession: Sendable {
    /// CLI에서 도착하는 이벤트 스트림. consumer가 cancel하면 graceful 종료가 트리거된다.
    var events: AsyncThrowingStream<ClaudeEvent, any Error> { get }

    /// stdin으로 사용자 텍스트 전송.
    func send(_ text: String) async throws
}

/// CLI 출력에서 파싱한 의미 있는 도메인 이벤트.
public enum ClaudeEvent: Sendable, Equatable {
    case text(String)
    case toolCall(name: String, input: String)
    case toolResult(success: Bool, output: String)
    case statusChange(StatusKind)
    case completed(exitCode: Int32)
    case usage(UsageDelta)

    public enum StatusKind: Sendable, Equatable {
        case thinking
        case executing
        case idle
    }

    /// 한 메시지 사이클(또는 result)에서 보고된 토큰/비용 변화.
    public struct UsageDelta: Sendable, Equatable, Codable, Hashable {
        public let inputTokens: Int
        public let outputTokens: Int
        public let cacheCreationTokens: Int
        public let cacheReadTokens: Int
        public let costUSD: Double?

        public init(
            inputTokens: Int = 0,
            outputTokens: Int = 0,
            cacheCreationTokens: Int = 0,
            cacheReadTokens: Int = 0,
            costUSD: Double? = nil
        ) {
            self.inputTokens = inputTokens
            self.outputTokens = outputTokens
            self.cacheCreationTokens = cacheCreationTokens
            self.cacheReadTokens = cacheReadTokens
            self.costUSD = costUSD
        }

        public func merging(cost: Double?) -> UsageDelta {
            UsageDelta(
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheCreationTokens: cacheCreationTokens,
                cacheReadTokens: cacheReadTokens,
                costUSD: cost ?? costUSD
            )
        }
    }
}
