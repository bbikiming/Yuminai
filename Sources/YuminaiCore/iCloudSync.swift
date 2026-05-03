import Foundation

/// **ADR-079 Phase 3** — iCloud preferences sync (NSUbiquitousKeyValueStore).
///
/// ## 설계 결정
/// - **NSUbiquitousKeyValueStore** 채택 (CloudKit 아님):
///   - preferences는 작은 데이터 (~수 KB) → 1MB limit 충분
///   - 자동 동기화 (manual schema 정의 X)
///   - 별도 entitlement 필요 (`com.apple.developer.ubiquity-kvstore-identifier`)
/// - **CloudKit 미채택**:
///   - workspaces (SwiftData) sync는 별도 ADR (CKShare 등 복잡)
///   - 이번 Phase는 preferences만
///
/// ## 동기화 항목
/// - pinnedWorkspaceIds (UUID array)
/// - workspaceFolders (encoded JSON)
/// - workspaceTags + tagAssignments
/// - smartFilters
/// - enabledSmartFolders
/// - beginnerMode + hasCompletedOnboarding
///
/// ## 미동기화 항목 (의도적)
/// - claudeBinaryPath, codexBinaryPath (PC 별 다름)
/// - telegramChatId, telegramAllowedUserIds (PC별 봇 다를 수 있음)
/// - 시크릿 (Keychain — iCloud Keychain 자동 동기화 활용)
///
/// ## 근거
/// - **Apple "Designing for iCloud"**: KVS = small/preferences, CloudKit = large/structured
/// - **Apple HIG "Sync"**: 사용자 명시 opt-in (privacy)
public enum iCloudSyncKey: String, CaseIterable {
    case pinnedWorkspaceIds = "pinnedWorkspaceIds"
    case workspaceFolders = "workspaceFolders"
    case workspaceTags = "workspaceTags"
    case tagAssignments = "tagAssignments"
    case activeTagFilters = "activeTagFilters"
    case smartFilters = "smartFilters"
    case enabledSmartFolders = "enabledSmartFolders"
    case beginnerMode = "beginnerMode"
    case hasCompletedOnboarding = "hasCompletedOnboarding"
}

/// **ADR-079 Phase 3** — NSUbiquitousKeyValueStore wrapper.
/// 사용자가 iCloud sync를 켜면 preferences 변경 시 KVS에 저장.
/// 다른 PC에서 KVS 변경 감지하면 local preferences로 import.
public final class iCloudPreferencesSync: @unchecked Sendable {
    /// 사용자가 iCloud sync 활성화 여부 (AppPreferences 별도 필드).
    public private(set) var isEnabled: Bool

    public init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }

    public func setEnabled(_ enabled: Bool) {
        self.isEnabled = enabled
    }

    /// preferences를 KVS에 push (사용자 변경 후 호출).
    /// - Parameter snapshot: 동기화할 preferences subset.
    public func push(_ snapshot: SyncSnapshot) {
        guard isEnabled else { return }
        let store = NSUbiquitousKeyValueStore.default
        let encoder = JSONEncoder()
        do {
            store.set(try encoder.encode(snapshot.pinnedWorkspaceIds), forKey: iCloudSyncKey.pinnedWorkspaceIds.rawValue)
            store.set(try encoder.encode(snapshot.workspaceFolders), forKey: iCloudSyncKey.workspaceFolders.rawValue)
            store.set(try encoder.encode(snapshot.workspaceTags), forKey: iCloudSyncKey.workspaceTags.rawValue)
            store.set(try encoder.encode(snapshot.tagAssignments), forKey: iCloudSyncKey.tagAssignments.rawValue)
            store.set(try encoder.encode(snapshot.activeTagFilters), forKey: iCloudSyncKey.activeTagFilters.rawValue)
            store.set(try encoder.encode(snapshot.smartFilters), forKey: iCloudSyncKey.smartFilters.rawValue)
            store.set(try encoder.encode(snapshot.enabledSmartFolders), forKey: iCloudSyncKey.enabledSmartFolders.rawValue)
            store.set(snapshot.beginnerMode, forKey: iCloudSyncKey.beginnerMode.rawValue)
            store.set(snapshot.hasCompletedOnboarding, forKey: iCloudSyncKey.hasCompletedOnboarding.rawValue)
            store.synchronize()
        } catch {
            // Encode 실패는 silent (logging 별도)
        }
    }

    /// KVS에서 preferences pull (외부 변경 감지 후 호출).
    /// - Returns: 동기화 가능한 snapshot (nil이면 KVS empty).
    public func pull() -> SyncSnapshot? {
        guard isEnabled else { return nil }
        let store = NSUbiquitousKeyValueStore.default
        let decoder = JSONDecoder()
        guard let pinnedData = store.data(forKey: iCloudSyncKey.pinnedWorkspaceIds.rawValue) else { return nil }
        do {
            let pinned = try decoder.decode([UUID].self, from: pinnedData)
            let folders: [WorkspaceFolder] = (try? store.data(forKey: iCloudSyncKey.workspaceFolders.rawValue).map { try decoder.decode([WorkspaceFolder].self, from: $0) }) ?? []
            let tags: [WorkspaceTag] = (try? store.data(forKey: iCloudSyncKey.workspaceTags.rawValue).map { try decoder.decode([WorkspaceTag].self, from: $0) }) ?? []
            let tagAssignments: WorkspaceTagAssignments = (try? store.data(forKey: iCloudSyncKey.tagAssignments.rawValue).map { try decoder.decode(WorkspaceTagAssignments.self, from: $0) }) ?? WorkspaceTagAssignments()
            let activeFilters: Set<UUID> = (try? store.data(forKey: iCloudSyncKey.activeTagFilters.rawValue).map { try decoder.decode(Set<UUID>.self, from: $0) }) ?? []
            let smartFilters: [SmartFilter] = (try? store.data(forKey: iCloudSyncKey.smartFilters.rawValue).map { try decoder.decode([SmartFilter].self, from: $0) }) ?? []
            let smartFolders: Set<SmartFolderKind> = (try? store.data(forKey: iCloudSyncKey.enabledSmartFolders.rawValue).map { try decoder.decode(Set<SmartFolderKind>.self, from: $0) }) ?? []
            let beginnerMode = store.bool(forKey: iCloudSyncKey.beginnerMode.rawValue)
            let onboarding = store.bool(forKey: iCloudSyncKey.hasCompletedOnboarding.rawValue)
            return SyncSnapshot(
                pinnedWorkspaceIds: pinned,
                workspaceFolders: folders,
                workspaceTags: tags,
                tagAssignments: tagAssignments,
                activeTagFilters: activeFilters,
                smartFilters: smartFilters,
                enabledSmartFolders: smartFolders,
                beginnerMode: beginnerMode,
                hasCompletedOnboarding: onboarding
            )
        } catch {
            return nil
        }
    }

    /// 동기화 가능한 preferences subset.
    public struct SyncSnapshot: Sendable, Codable, Hashable {
        public let pinnedWorkspaceIds: [UUID]
        public let workspaceFolders: [WorkspaceFolder]
        public let workspaceTags: [WorkspaceTag]
        public let tagAssignments: WorkspaceTagAssignments
        public let activeTagFilters: Set<UUID>
        public let smartFilters: [SmartFilter]
        public let enabledSmartFolders: Set<SmartFolderKind>
        public let beginnerMode: Bool
        public let hasCompletedOnboarding: Bool

        public init(
            pinnedWorkspaceIds: [UUID],
            workspaceFolders: [WorkspaceFolder],
            workspaceTags: [WorkspaceTag],
            tagAssignments: WorkspaceTagAssignments,
            activeTagFilters: Set<UUID>,
            smartFilters: [SmartFilter],
            enabledSmartFolders: Set<SmartFolderKind>,
            beginnerMode: Bool,
            hasCompletedOnboarding: Bool
        ) {
            self.pinnedWorkspaceIds = pinnedWorkspaceIds
            self.workspaceFolders = workspaceFolders
            self.workspaceTags = workspaceTags
            self.tagAssignments = tagAssignments
            self.activeTagFilters = activeTagFilters
            self.smartFilters = smartFilters
            self.enabledSmartFolders = enabledSmartFolders
            self.beginnerMode = beginnerMode
            self.hasCompletedOnboarding = hasCompletedOnboarding
        }
    }
}
