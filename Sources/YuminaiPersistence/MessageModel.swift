import Foundation
import SwiftData
import YuminaiCore

/// `Message`의 SwiftData 영속 표현. Claude CLI가 컨텍스트 sole source이고 여기는 UI 캐시.
@Model
public final class MessageModel {
    @Attribute(.unique) public var id: UUID
    public var roleRaw: String
    public var content: String
    public var timestamp: Date
    public var rawANSI: String?

    public var session: SessionModel?

    public init(
        id: UUID,
        roleRaw: String,
        content: String,
        timestamp: Date,
        rawANSI: String? = nil,
        session: SessionModel? = nil
    ) {
        self.id = id
        self.roleRaw = roleRaw
        self.content = content
        self.timestamp = timestamp
        self.rawANSI = rawANSI
        self.session = session
    }

    public convenience init(from core: Message, session: SessionModel? = nil) {
        self.init(
            id: core.id,
            roleRaw: core.role.rawValue,
            content: core.content,
            timestamp: core.timestamp,
            rawANSI: core.rawANSI,
            session: session
        )
    }

    public var toCoreMessage: Message {
        Message(
            id: id,
            sessionId: session?.id ?? UUID(),
            role: Message.Role(rawValue: roleRaw) ?? .system,
            content: content,
            timestamp: timestamp,
            rawANSI: rawANSI
        )
    }
}
