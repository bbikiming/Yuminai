import Foundation
import Testing
@testable import YuminaiCore

@Suite("iCloudPreferencesSync (ADR-079 Phase 3 + ADR-080)")
struct iCloudPreferencesSyncTests {

    @Test("기본 init — disabled")
    func defaultDisabled() {
        let sync = iCloudPreferencesSync()
        #expect(sync.isEnabled == false)
    }

    @Test("setEnabled 토글")
    func setEnabled() {
        let sync = iCloudPreferencesSync()
        sync.setEnabled(true)
        #expect(sync.isEnabled == true)
        sync.setEnabled(false)
        #expect(sync.isEnabled == false)
    }

    @Test("disabled 상태에선 push() no-op (KVS 안 만짐)")
    func disabledPushNoOp() {
        let sync = iCloudPreferencesSync(isEnabled: false)
        let snapshot = iCloudPreferencesSync.SyncSnapshot(
            pinnedWorkspaceIds: [UUID()],
            workspaceFolders: [],
            workspaceTags: [],
            tagAssignments: WorkspaceTagAssignments(),
            activeTagFilters: [],
            smartFilters: [],
            enabledSmartFolders: [],
            beginnerMode: false,
            hasCompletedOnboarding: true
        )
        sync.push(snapshot)  // KVS 호출 없음 (실제로는 silent return)
        // 호출 자체가 throw 안 하면 OK
    }

    @Test("disabled 상태에선 pull() = nil")
    func disabledPullNil() {
        let sync = iCloudPreferencesSync(isEnabled: false)
        #expect(sync.pull() == nil)
    }

    @Test("SyncSnapshot Codable round trip")
    func snapshotRoundTrip() throws {
        let snapshot = iCloudPreferencesSync.SyncSnapshot(
            pinnedWorkspaceIds: [UUID(), UUID()],
            workspaceFolders: [WorkspaceFolder(name: "test", colorName: "blue")],
            workspaceTags: [WorkspaceTag(name: "test")],
            tagAssignments: WorkspaceTagAssignments(),
            activeTagFilters: [UUID()],
            smartFilters: [SmartFilter(name: "긴급")],
            enabledSmartFolders: [.recentWeek],
            beginnerMode: true,
            hasCompletedOnboarding: false
        )
        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(iCloudPreferencesSync.SyncSnapshot.self, from: encoded)
        #expect(decoded == snapshot)
    }

    @Test("iCloudSyncKey allCases 9개 (정의된 키와 일치)")
    func syncKeyCount() {
        #expect(iCloudSyncKey.allCases.count == 9)
        let raws = iCloudSyncKey.allCases.map { $0.rawValue }
        #expect(raws.contains("pinnedWorkspaceIds"))
        #expect(raws.contains("smartFilters"))
        #expect(raws.contains("hasCompletedOnboarding"))
    }
}
