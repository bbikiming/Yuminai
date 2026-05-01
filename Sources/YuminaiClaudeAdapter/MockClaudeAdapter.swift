import Foundation
import YuminaiCore

/// 테스트용 ClaudeAdapter. 미리 정의된 이벤트 시퀀스를 그대로 방출한다.
///
/// 실 Claude CLI를 실행하지 않으므로 단위 테스트에서 안전하고 빠르다.
public final actor MockClaudeAdapter: ClaudeAdapter {
    private let scriptedEvents: [ClaudeEvent]
    private let delayPerEvent: Duration
    private var settings: SessionSettings

    public init(
        scriptedEvents: [ClaudeEvent] = [.text("mock"), .completed(exitCode: 0)],
        delayPerEvent: Duration = .milliseconds(1),
        settings: SessionSettings = .default
    ) {
        self.scriptedEvents = scriptedEvents
        self.delayPerEvent = delayPerEvent
        self.settings = settings
    }

    public func spawn(in workspace: Workspace) async throws -> any ClaudeStreamSession {
        ScriptedSession(events: scriptedEvents, delayPerEvent: delayPerEvent)
    }

    public func terminate(_ session: any ClaudeStreamSession) async {
        // Scripted session은 자체 종료. no-op.
    }

    public func updateSettings(_ settings: SessionSettings) async {
        self.settings = settings
    }

    public func currentSettings() async -> SessionSettings {
        settings
    }
}

/// Mock 어댑터 내부에서 사용하는 사전 스크립트 세션.
final class ScriptedSession: ClaudeStreamSession, @unchecked Sendable {
    let events: AsyncThrowingStream<ClaudeEvent, any Error>
    private let continuation: AsyncThrowingStream<ClaudeEvent, any Error>.Continuation

    init(events: [ClaudeEvent], delayPerEvent: Duration) {
        var cont: AsyncThrowingStream<ClaudeEvent, any Error>.Continuation!
        self.events = AsyncThrowingStream { c in cont = c }
        self.continuation = cont

        Task { [continuation, events, delayPerEvent] in
            for event in events {
                try? await Task.sleep(for: delayPerEvent)
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    func send(_ text: String) async throws {
        // Mock은 입력 무시
    }
}
