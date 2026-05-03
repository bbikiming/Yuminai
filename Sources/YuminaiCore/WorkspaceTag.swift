import Foundation

/// **ADR-078 Phase 4** — 워크스페이스 태그 (다중 적용 가능, smart folder의 발전형).
///
/// ## Folder vs Tag 차이
/// - **Folder**: mutually exclusive (한 워크스페이스 = 0~1 폴더)
/// - **Tag**: many-to-many (한 워크스페이스 = 0~N 태그, 한 태그 = 0~N 워크스페이스)
///
/// ## 근거
/// - **Apple Finder Tags** (https://support.apple.com/en-us/102641): 다중 tag로 cross-cutting 분류
/// - **GitHub Labels**: 다중 label로 PR/issue cross-cutting 분류
/// - **NN/g "Faceted Classification"**: 단일 hierarchy(folder)보다 multi-dimensional(tag)이
///   복잡한 도메인에서 더 효율적
///
/// ## 사용 예
/// - 색상별 분류: "긴급", "일상", "보류"
/// - 클라이언트별: "ClientA", "ClientB"
/// - 기술 스택: "iOS", "Web", "ML"
/// - 폴더(클라이언트)와 tag(상태) 조합으로 다차원 navigation
public struct WorkspaceTag: Sendable, Codable, Hashable, Identifiable {
    public let id: UUID
    public var name: String
    /// Theme.Color.folderColor lookup용 semantic 색상 (folder와 동일 palette 공유).
    public var colorName: String

    public init(
        id: UUID = UUID(),
        name: String,
        colorName: String = "blue"
    ) {
        self.id = id
        self.name = name
        self.colorName = colorName
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.colorName = try c.decodeIfPresent(String.self, forKey: .colorName) ?? "blue"
    }
}

/// **ADR-078 Phase 4** — 워크스페이스 ↔ 태그 매핑 (many-to-many).
///
/// `[workspaceId: Set<tagId>]` 형식. 양방향 lookup은 helper 메서드로.
public struct WorkspaceTagAssignments: Sendable, Codable, Hashable {
    /// workspace ID → 적용된 tag IDs.
    public var workspaceToTags: [UUID: Set<UUID>]

    public init(workspaceToTags: [UUID: Set<UUID>] = [:]) {
        self.workspaceToTags = workspaceToTags
    }

    /// 특정 워크스페이스에 적용된 tag IDs.
    public func tags(for workspaceId: UUID) -> Set<UUID> {
        workspaceToTags[workspaceId] ?? []
    }

    /// 특정 tag가 적용된 워크스페이스 IDs.
    public func workspaces(withTag tagId: UUID) -> [UUID] {
        workspaceToTags
            .filter { $0.value.contains(tagId) }
            .map { $0.key }
    }

    /// 워크스페이스에 tag 추가.
    public mutating func add(tag tagId: UUID, to workspaceId: UUID) {
        var existing = workspaceToTags[workspaceId] ?? []
        existing.insert(tagId)
        workspaceToTags[workspaceId] = existing
    }

    /// 워크스페이스에서 tag 제거.
    public mutating func remove(tag tagId: UUID, from workspaceId: UUID) {
        guard var existing = workspaceToTags[workspaceId] else { return }
        existing.remove(tagId)
        if existing.isEmpty {
            workspaceToTags.removeValue(forKey: workspaceId)
        } else {
            workspaceToTags[workspaceId] = existing
        }
    }

    /// 워크스페이스 삭제 시 모든 tag assignment도 자동 정리 (orphan 방지).
    public mutating func removeAllAssignments(for workspaceId: UUID) {
        workspaceToTags.removeValue(forKey: workspaceId)
    }

    /// Tag 삭제 시 모든 workspace에서 해당 tag 제거.
    public mutating func removeTagEverywhere(_ tagId: UUID) {
        for (wsId, tagIds) in workspaceToTags {
            var updated = tagIds
            updated.remove(tagId)
            if updated.isEmpty {
                workspaceToTags.removeValue(forKey: wsId)
            } else {
                workspaceToTags[wsId] = updated
            }
        }
    }
}
