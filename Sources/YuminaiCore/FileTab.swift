import Foundation

/// Multi-tab 파일 편집을 위한 단일 tab state (ADR-038 E2).
///
/// **사용 패턴**:
/// - 사용자가 파일 트리에서 파일 클릭 → 새 tab 추가 (또는 이미 있으면 활성화)
/// - tab 닫으면 unsaved 변경 있으면 confirm
/// - active tab의 path/draft/dirty가 FilesPanel viewer/editor에 반영
public struct FileTab: Sendable, Identifiable, Equatable, Hashable {
    public let id: UUID
    public let path: String
    /// 디스크에서 읽어온 본문 (read 시점)
    public var savedContents: String
    /// 사용자가 편집 중인 draft
    public var draft: String
    /// 편집 모드인지 (false면 viewer)
    public var isEditing: Bool

    public init(
        id: UUID = UUID(),
        path: String,
        savedContents: String,
        draft: String? = nil,
        isEditing: Bool = false
    ) {
        self.id = id
        self.path = path
        self.savedContents = savedContents
        self.draft = draft ?? savedContents
        self.isEditing = isEditing
    }

    public var isDirty: Bool {
        isEditing && draft != savedContents
    }

    /// 파일 이름 (path의 마지막 component).
    public var displayName: String {
        (path as NSString).lastPathComponent
    }
}
