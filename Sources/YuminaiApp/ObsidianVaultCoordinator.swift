import Foundation
import Observation
import YuminaiCore
import YuminaiObsidian

/// Obsidian Vault state holder (ADR-042 R3.6 minimal extraction).
///
/// **분리 범위**: state holder만. lifecycle/watcher/search 메서드는 AppModel 잔존
/// (VaultWatcher, fullTextSearchTask, vaultActor 의존성 깊음 — R3.6.2에서 분리 가능).
///
/// **Facade 패턴**: AppModel.vault 보유.
@MainActor
@Observable
public final class ObsidianVaultCoordinator {
    public var vault: ObsidianVault?
    public var tree: [VaultNode] = []
    public var selectedNote: Note?
    public var searchQuery: String = ""
    public var fullTextEnabled: Bool = false
    public var fullTextHits: [SearchHit] = []

    // 노트 편집
    public var isEditing: Bool = false
    public var editingDraft: String = ""
    public var externalChangeDetected: Bool = false

    public var noteIsDirty: Bool {
        isEditing && editingDraft != (selectedNote?.body ?? "")
    }

    // NotePicker (Composer)
    public var showNotePicker: Bool = false
    public var notePickerQuery: String = ""

    // Wiki disambig
    public var disambigCandidates: [VaultNode] = []
    public var disambigOriginalName: String = ""
    public var showDisambigSheet: Bool = false

    // Note creation
    public var showCreateNoteSheet: Bool = false

    // Favorites + Recents
    public var favorites: Set<String> = []
    public var recents: [String] = []

    public var isConfigured: Bool { vault != nil }
    public var rootPath: String? { vault?.rootURL.path }

    public init() {}
}
