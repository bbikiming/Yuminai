import Foundation
import SwiftData
import YuminaiCore

/// `Session` 도메인 struct의 SwiftData 영속 표현.
///
/// 메시지는 cascade 관계. 세션 본문(Claude의 컨텍스트)은 Claude CLI가 sole source —
/// 여기엔 UI 표시/검색용 캐시만 저장 (ADR-010 참조).
@Model
public final class SessionModel {
    @Attribute(.unique) public var id: UUID
    public var workspaceId: UUID
    public var startedAt: Date
    public var endedAt: Date?
    public var title: String?

    @Relationship(deleteRule: .cascade, inverse: \MessageModel.session)
    public var messages: [MessageModel]

    public init(
        id: UUID,
        workspaceId: UUID,
        startedAt: Date,
        endedAt: Date? = nil,
        title: String? = nil
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.title = title
        self.messages = []
    }

    public convenience init(from core: Session) {
        self.init(
            id: core.id,
            workspaceId: core.workspaceId,
            startedAt: core.startedAt,
            endedAt: core.endedAt,
            title: core.title
        )
    }

    public var toCoreSession: Session {
        Session(
            id: id,
            workspaceId: workspaceId,
            startedAt: startedAt,
            endedAt: endedAt,
            title: title
        )
    }
}
