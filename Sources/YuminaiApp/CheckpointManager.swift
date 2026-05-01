import Foundation
import os
import YuminaiCore

/// Agent turn 단위로 git checkpoint를 기록하고 변경을 추적 (ADR-027 phase A).
///
/// ## 동작
/// - Agent turn 시작 시 `beginTurn(workspace:)` — HEAD SHA 기록 (가벼운 베이스라인)
/// - Agent turn 종료 시 `endTurn()` — 변경 파일 목록 + diff 캡처
/// - Inspector "변경" 탭이 `pendingChanges`를 표시
/// - 사용자 accept → 그대로 (working tree 보존), reject → `revert(paths:)`
///
/// ## 정책 (사용자 권고: manual accept)
/// - 자동 commit X — 사용자가 명시적으로 accept (추후 git add/commit은 별도 액션)
/// - 자동 reject도 X — 사용자가 명시적으로 reject 클릭
///
/// git 저장소가 아니면 silently no-op (워크스페이스에 .git 없으면 checkpoint 비활성).
public actor CheckpointManager {
    public struct Snapshot: Sendable, Equatable {
        public let workspaceId: UUID
        public let baselineSha: String
        public let startedAt: Date
        public var changedFiles: [ChangedFile]
        public var diff: String

        public init(
            workspaceId: UUID,
            baselineSha: String,
            startedAt: Date,
            changedFiles: [ChangedFile] = [],
            diff: String = ""
        ) {
            self.workspaceId = workspaceId
            self.baselineSha = baselineSha
            self.startedAt = startedAt
            self.changedFiles = changedFiles
            self.diff = diff
        }
    }

    private var current: Snapshot?
    private let logger = Logger(subsystem: "com.yuminai", category: "Checkpoint")

    public init() {}

    /// agent turn 시작 — HEAD SHA 기록.
    public func beginTurn(workspace: Workspace) async {
        let runner = GitRunner(workspaceURL: URL(fileURLWithPath: workspace.directoryPath))
        guard await runner.isRepository() else {
            logger.info("checkpoint skip — not a git repo: \(workspace.directoryPath)")
            current = nil
            return
        }
        do {
            let sha = try await runner.currentHeadSha()
            current = Snapshot(
                workspaceId: workspace.id,
                baselineSha: sha,
                startedAt: Date()
            )
            logger.info("checkpoint begin \(workspace.name) — HEAD=\(sha.prefix(8))")
        } catch {
            logger.error("checkpoint begin 실패: \(error.localizedDescription)")
            current = nil
        }
    }

    /// agent turn 종료 — 변경 파일 + diff 캡처.
    /// turn 동안 변경이 없으면 snapshot은 유지하되 changedFiles=[].
    public func endTurn(workspace: Workspace) async -> Snapshot? {
        guard var snap = current, snap.workspaceId == workspace.id else { return current }

        let runner = GitRunner(workspaceURL: URL(fileURLWithPath: workspace.directoryPath))
        do {
            snap.changedFiles = try await runner.changedFiles()
            snap.diff = (try? await runner.diff()) ?? ""
            current = snap
            logger.info("checkpoint end \(workspace.name) — \(snap.changedFiles.count)개 파일 변경")
            return snap
        } catch {
            logger.error("checkpoint end 실패: \(error.localizedDescription)")
            return snap
        }
    }

    /// 현재 snapshot — Inspector "변경" 탭에서 read.
    public var snapshot: Snapshot? { current }

    /// 변경 파일 (UI 표시용 빠른 read).
    public var pendingChanges: [ChangedFile] {
        current?.changedFiles ?? []
    }

    /// 사용자가 accept — 그대로 두고 snapshot 클리어 (다음 turn까지).
    public func acceptAll() {
        current = nil
        logger.info("checkpoint accept all")
    }

    /// 사용자가 reject — 모든 변경 working tree에서 원복.
    public func rejectAll(workspace: Workspace) async throws {
        let runner = GitRunner(workspaceURL: URL(fileURLWithPath: workspace.directoryPath))
        try await runner.revertAll()
        current = nil
        logger.info("checkpoint reject all — \(workspace.name)")
    }

    /// 일부 path만 reject — 나머지는 보존.
    public func rejectPaths(_ paths: [String], workspace: Workspace) async throws {
        let runner = GitRunner(workspaceURL: URL(fileURLWithPath: workspace.directoryPath))
        try await runner.revert(paths: paths)
        // 남은 변경 갱신
        if var snap = current {
            let remainingPaths = Set(snap.changedFiles.map(\.path)).subtracting(paths)
            snap.changedFiles = snap.changedFiles.filter { remainingPaths.contains($0.path) }
            snap.diff = (try? await runner.diff()) ?? ""
            current = snap
        }
        logger.info("checkpoint reject \(paths.count) paths — \(workspace.name)")
    }

    /// 명시적 reset — workspace 변경 시.
    public func reset() {
        current = nil
    }
}
