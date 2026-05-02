import Foundation
import Observation
import YuminaiCore

/// AgentPane state holder (ADR-042 R3.4 — minimal extraction).
///
/// **분리 범위 (현실적 트레이드오프)**:
/// - state holder만 추출: agentPanes, activePaneId, message/settings/usage dicts, chain hops
/// - lifecycle (addPane/removePane/setActive/renamePane) + streaming + dispatch는 AppModel 잔존
///   (ClaudeStreamSession + sendMessage + mention dispatch가 깊이 entangled)
/// - 추후 R3.4.2에서 session lifecycle을 coord로 더 옮기려면 protocol 의존성 정리 선행 필요
///
/// **Facade 패턴**: AppModel이 `panes` 보유 + 기존 호출자 API computed pass-through.
@MainActor
@Observable
public final class AgentPaneCoordinator {
    // MARK: - Pane state

    public var panes: [AgentPane] = []
    public var activeId: UUID?
    public var messages: [UUID: [Message]] = [:]
    public var settings: [UUID: SessionSettings] = [:]
    public var usage: [UUID: UsageStats] = [:]
    /// 영속된 panes 메타. workspace 재진입 시 복원 (ADR-031, T1).
    /// 빈 배열이면 AppModel이 default primary 1개 자동 생성. session/messages는 복원 X (메타만).

    // MARK: - Chain state (ADR-034)

    /// agent → agent 자동 dispatch hop count (사용자 turn 시 0 reset).
    public var chainHops: Int = 0
    /// chain에 방문한 pane id (같은 pane 재방문 방지)
    public var chainVisited: Set<UUID> = []

    public init() {}

    // MARK: - Active pane projection

    public var activePane: AgentPane? {
        panes.first { $0.id == activeId }
    }

    /// 활성 pane의 messages.
    public var activeMessages: [Message] {
        guard let id = activeId else { return [] }
        return messages[id] ?? []
    }

    public var activeSettings: SessionSettings {
        guard let id = activeId else { return .default }
        return settings[id] ?? .default
    }

    public var activeUsage: UsageStats {
        guard let id = activeId else { return .zero }
        return usage[id] ?? .zero
    }

    public var chainActive: Bool { chainHops > 0 }

    /// active pane의 messages mutable accessor (sendMessage 등 호출).
    public func appendMessageToActive(_ message: Message) {
        guard let id = activeId else { return }
        var arr = messages[id] ?? []
        arr.append(message)
        messages[id] = arr
    }

    public func setActiveMessages(_ newMessages: [Message]) {
        guard let id = activeId else { return }
        messages[id] = newMessages
    }

    public func mutateActiveMessages(_ block: (inout [Message]) -> Void) {
        guard let id = activeId else { return }
        var arr = messages[id] ?? []
        block(&arr)
        messages[id] = arr
    }

    public func setActiveSettings(_ newSettings: SessionSettings) {
        guard let id = activeId else { return }
        settings[id] = newSettings
    }

    public func setActiveUsage(_ newUsage: UsageStats) {
        guard let id = activeId else { return }
        usage[id] = newUsage
    }
}
