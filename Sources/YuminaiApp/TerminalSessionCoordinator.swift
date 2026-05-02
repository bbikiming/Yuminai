import Foundation
import Observation
import AppKit
import YuminaiCore

/// 다중 터미널 세션 lifecycle을 단일 책임으로 분리 (ADR-042 R3.1 — AppModel god-object 분해 1단계).
///
/// **분리 근거**:
/// - AppModel(2226줄)에서 가장 self-contained한 도메인 — 다른 도메인과 cross-coupling 거의 없음
/// - state 7개 + 메서드 13개가 한 클래스에 응집 가능
/// - ADR-040/041 5라운드에서 빠르게 추가됨 → 향후 hibernation, OSC 133, split 강화 등 추가 시 별도 파일에서 진행
///
/// **유지하는 facade 패턴**: AppModel은 `terminals`로 이 coord를 보유하고,
/// 기존 `appModel.terminalSessions` 등 호출자 API는 computed pass-through로 유지 → 호출자 변경 최소화.
///
/// **다음 단계 (ADR-042 R3.2~R3.7)**: WorkspaceFileManager / CommandRunnerCoordinator /
/// AgentPaneCoordinator / DeliveryCoordinator / ObsidianVaultCoordinator / TelegramCoordinator.
@MainActor
@Observable
public final class TerminalSessionCoordinator {
    // MARK: - State (ADR-040 T1, ADR-041 T10/T11/T13/T14)

    /// pane 표시 토글
    public var showPane: Bool = false
    /// 다중 터미널 세션 — 워크스페이스 별 N개. max 10
    public var sessions: [TerminalSession] = []
    /// 활성 세션 id (탭 바에서 highlight + TerminalPane 표시)
    public var activeSessionId: UUID?
    /// 라벨 변경 sheet 트리거 (id 기반)
    public var renameTargetId: UUID?
    /// Split 모드 — 좌우 dual-pane (ADR-041 T14)
    public var splitEnabled: Bool = false
    public var secondarySessionId: UUID?

    public init() {}

    // MARK: - Lifecycle (ADR-040 T1)

    /// 새 터미널 세션 추가 + 활성화. workspace path는 caller가 전달 (coord는 workspace 의존성 X).
    public func createSession(workingDirectory: String, label: String? = nil) {
        let nextLabel = label ?? TerminalSession.defaultLabel(index: sessions.count)
        let session = TerminalSession(label: nextLabel, workingDirectory: workingDirectory)
        sessions.append(session)
        activeSessionId = session.id
        // ADR-043 R4 — max 10→5 hard cap. 비활성 세션도 PTY process 살아있어 메모리 비용 큼.
        if sessions.count > AppLimits.maxTerminalSessions {
            sessions.removeFirst()
        }
    }

    public func setActive(_ id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        activeSessionId = id
        markRead(id)
    }

    /// 세션 close — 활성이 닫히면 인접 세션으로 이동.
    public func close(_ id: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = activeSessionId == id
        sessions.remove(at: idx)
        if wasActive {
            if idx < sessions.count {
                activeSessionId = sessions[idx].id
            } else if idx > 0 {
                activeSessionId = sessions[idx - 1].id
            } else {
                activeSessionId = nil
            }
        }
        // 마지막 세션 close → pane 자동 닫기
        if sessions.isEmpty {
            showPane = false
        }
        // secondary가 close된 경우 split 자동 정리
        if secondarySessionId == id {
            secondarySessionId = sessions.first(where: { $0.id != activeSessionId })?.id
            if secondarySessionId == nil {
                splitEnabled = false
            }
        }
    }

    public func closeActive() {
        guard let id = activeSessionId else { return }
        close(id)
    }

    public func rename(_ id: UUID, to newLabel: String) {
        let trimmed = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].label = trimmed
    }

    public func selectAdjacent(offset: Int) {
        guard !sessions.isEmpty else { return }
        let currentIdx = activeSessionId.flatMap { id in
            sessions.firstIndex(where: { $0.id == id })
        } ?? 0
        let count = sessions.count
        let nextIdx = ((currentIdx + offset) % count + count) % count
        activeSessionId = sessions[nextIdx].id
    }

    /// pane 토글 + 첫 세션 자동 생성 (workingDirectory caller 전달).
    public func togglePane(workingDirectory: String) {
        showPane.toggle()
        if showPane && sessions.isEmpty {
            createSession(workingDirectory: workingDirectory)
        }
    }

    // MARK: - cwd (ADR-041 T11)

    /// NSOpenPanel folder picker로 cwd 변경 — caller가 결과 path를 changeDirectory에 전달.
    /// (NSOpenPanel은 main thread + modal — coord는 dialog UI 책임 X, callback 패턴)
    public func changeDirectory(_ id: UUID, to newPath: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].workingDirectory = newPath
    }

    // MARK: - Activity (ADR-041 T10)

    public func updateActivity(_ id: UUID, _ activity: TerminalSession.Activity) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = activeSessionId == id
        sessions[idx].activity = activity
        // ADR-043 R4 — 비활성 세션의 running/completedRecently 모두 unread 알림.
        // (사용자가 다른 창 보다 돌아왔을 때 "끝났다" 신호 보존 — 3초 timeout 후에도 dot 유지)
        if !wasActive && (activity == .running || activity == .completedRecently) {
            sessions[idx].hasUnreadOutput = true
        }
    }

    public func markRead(_ id: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].hasUnreadOutput = false
    }

    // MARK: - Split (ADR-041 T14)

    /// Split 모드 토글 — secondary 자동 선택 또는 새 세션 생성 (workingDirectory caller 전달).
    public func toggleSplit(workingDirectory: String) {
        splitEnabled.toggle()
        if splitEnabled, secondarySessionId == nil {
            if sessions.count >= 2,
               let activeIdx = sessions.firstIndex(where: { $0.id == activeSessionId }) {
                let nextIdx = (activeIdx + 1) % sessions.count
                secondarySessionId = sessions[nextIdx].id
            } else if sessions.count == 1 {
                createSession(workingDirectory: workingDirectory)
                secondarySessionId = sessions.last?.id
            }
        }
    }

    public func setSecondary(_ id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        secondarySessionId = id
        markRead(id)
    }

    // MARK: - Persistence (ADR-041 T13)

    /// 영속된 세션 list로 전체 교체. activity는 fresh `.idle`로 리셋.
    public func restore(from saved: [TerminalSession]) {
        sessions = saved.map { saved in
            var s = saved
            s.activity = .idle
            s.hasUnreadOutput = false
            return s
        }
        activeSessionId = sessions.first?.id
        // split state는 영속 X — 매 진입 fresh
        splitEnabled = false
        secondarySessionId = nil
    }

    /// 워크스페이스가 변경됐을 때 모든 세션 정리.
    public func clearAll() {
        sessions = []
        activeSessionId = nil
        secondarySessionId = nil
        splitEnabled = false
        showPane = false
    }
}
