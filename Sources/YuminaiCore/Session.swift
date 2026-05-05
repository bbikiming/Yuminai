import Foundation

/// 한 워크스페이스 안의 한 대화 단위.
public struct Session: Sendable, Identifiable, Hashable {
    public let id: UUID
    public let workspaceId: UUID
    public let startedAt: Date
    public let endedAt: Date?
    public let title: String?

    public init(
        id: UUID = UUID(),
        workspaceId: UUID,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        title: String? = nil
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.title = title
    }
}

/// **ADR-115 P1-2** — LLM 응답에 참고 자료/프로필 attribution 정보를 첨부하는 모델.
///
/// assistant 메시지 하단에 "어떤 자료를 참고했는지" 표시해 사용자 신뢰를 높인다.
/// backward-compat: Message.attribution은 옵션 타입 + decodeIfPresent.
public struct MessageAttribution: Sendable, Codable, Hashable {
    /// 참고한 라이브러리 자료 display 이름 목록 (빈 배열이면 자료 미첨부).
    public let attachedLibraryItems: [String]
    /// 사용자 프로필 스냅샷 요약 (예: "iOS 개발자 · 앱 만들기"). nil이면 프로필 미적용.
    public let profileSnapshotSummary: String?
    /// attribution 생성 시각.
    public let recordedAt: Date

    public init(
        attachedLibraryItems: [String],
        profileSnapshotSummary: String?,
        recordedAt: Date = Date()
    ) {
        self.attachedLibraryItems = attachedLibraryItems
        self.profileSnapshotSummary = profileSnapshotSummary
        self.recordedAt = recordedAt
    }

    /// 표시할 내용이 하나라도 있으면 true.
    public var isEmpty: Bool {
        attachedLibraryItems.isEmpty && (profileSnapshotSummary?.isEmpty ?? true)
    }

    /// 사용자에게 보여줄 1-2줄 요약 (UI footer용).
    public var displaySummary: String {
        var parts: [String] = []
        if !attachedLibraryItems.isEmpty {
            let names = attachedLibraryItems.prefix(3).joined(separator: ", ")
            let more = attachedLibraryItems.count > 3 ? " 외 \(attachedLibraryItems.count - 3)개" : ""
            parts.append("참고 자료: \(names)\(more)")
        }
        if let profile = profileSnapshotSummary, !profile.isEmpty {
            parts.append("프로필: \(profile)")
        }
        return parts.joined(separator: " · ")
    }
}

/// 세션 안의 단일 메시지. 사용자 입력 또는 Claude 응답.
/// **ADR-089** — ChatSession 영속화를 위해 Codable 추가.
/// **ADR-115 P1-2** — attribution 필드 추가 (backward-compat, optional).
public struct Message: Sendable, Identifiable, Hashable, Codable {
    public let id: UUID
    public let sessionId: UUID
    public let role: Role
    public let content: String
    public let timestamp: Date
    public let rawANSI: String?
    /// **ADR-115 P1-2** — LLM 응답 attribution (참고 자료/프로필). nil이면 미첨부 (구버전 호환).
    public let attribution: MessageAttribution?

    public init(
        id: UUID = UUID(),
        sessionId: UUID,
        role: Role,
        content: String,
        timestamp: Date = Date(),
        rawANSI: String? = nil,
        attribution: MessageAttribution? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.rawANSI = rawANSI
        self.attribution = attribution
    }

    // MARK: - Codable (backward-compat)

    private enum CodingKeys: String, CodingKey {
        case id, sessionId, role, content, timestamp, rawANSI, attribution
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        sessionId = try c.decode(UUID.self, forKey: .sessionId)
        role = try c.decode(Role.self, forKey: .role)
        content = try c.decode(String.self, forKey: .content)
        timestamp = try c.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        rawANSI = try c.decodeIfPresent(String.self, forKey: .rawANSI)
        attribution = try c.decodeIfPresent(MessageAttribution.self, forKey: .attribution)
    }

    public enum Role: String, Sendable, Codable, Hashable, CaseIterable {
        case user
        case assistant
        case system
        case tool
    }
}
