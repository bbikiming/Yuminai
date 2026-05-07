import Foundation

/// **ADR-111** — 자료 라이브러리 항목.
///
/// 사용자가 커뮤니티 자료 또는 직접 입력으로 가져온 자료를 전역 라이브러리에 저장.
/// 디스크 경로: `~/Library/Application Support/Yuminai/library/<id>.md`
public struct ResourceLibraryItem: Sendable, Codable, Hashable, Identifiable {

    // MARK: - 출처

    /// 자료의 원본 출처.
    public enum Source: Sendable, Codable, Hashable {
        /// 커뮤니티 카탈로그에서 다운로드 (resourceId: CommunityResource.id).
        case community(resourceId: UUID, originalURL: URL?)
        /// 사용자가 직접 URL로 가져옴.
        case userImport(originalURL: URL)
        /// 사용자가 직접 텍스트 입력.
        case userText

        private enum CodingKeys: String, CodingKey {
            case type, resourceId, originalURL
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let type = try c.decode(String.self, forKey: .type)
            switch type {
            case "community":
                let resourceId = try c.decode(UUID.self, forKey: .resourceId)
                let url = try c.decodeIfPresent(URL.self, forKey: .originalURL)
                self = .community(resourceId: resourceId, originalURL: url)
            case "userImport":
                let url = try c.decode(URL.self, forKey: .originalURL)
                self = .userImport(originalURL: url)
            default:
                self = .userText
            }
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .community(let resourceId, let url):
                try c.encode("community", forKey: .type)
                try c.encode(resourceId, forKey: .resourceId)
                try c.encodeIfPresent(url, forKey: .originalURL)
            case .userImport(let url):
                try c.encode("userImport", forKey: .type)
                try c.encode(url, forKey: .originalURL)
            case .userText:
                try c.encode("userText", forKey: .type)
            }
        }

        /// 출처 표시 레이블.
        public var displayLabel: String {
            switch self {
            case .community: return "커뮤니티"
            case .userImport: return "URL 가져오기"
            case .userText: return "직접 입력"
            }
        }

        /// 출처 아이콘 이름 (SF Symbols).
        public var iconName: String {
            switch self {
            case .community: return "archivebox.fill"
            case .userImport: return "link"
            case .userText: return "keyboard"
            }
        }
    }

    // MARK: - 프로퍼티

    public let id: UUID
    /// 사용자 표시 이름 (변경 가능).
    public var displayName: String
    /// 카테고리 (CommunityResource.Category와 공유).
    public let category: CommunityResource.Category
    /// 출처 정보.
    public let source: Source
    /// 자료 본문 (markdown). 디스크에도 별도 저장.
    public var content: String
    /// 태그 목록.
    public var tags: [String]
    /// 라이브러리에 추가된 날짜.
    public let addedAt: Date
    /// 사용자 메모 (선택).
    public var notes: String

    /// UTF-8 byte size — 간결한 용량 표시용.
    public var byteSize: Int { content.utf8.count }

    /// byte size를 사람이 읽기 쉬운 문자열로 반환 (예: "1.2 KB", "34 B").
    public var byteSizeDisplay: String {
        let b = byteSize
        if b < 1024 { return "\(b) B" }
        if b < 1024 * 1024 {
            let kb = Double(b) / 1024.0
            return String(format: "%.1f KB", kb)
        }
        let mb = Double(b) / (1024.0 * 1024.0)
        return String(format: "%.1f MB", mb)
    }

    // MARK: - 초기화

    public init(
        id: UUID = UUID(),
        displayName: String,
        category: CommunityResource.Category,
        source: Source,
        content: String,
        tags: [String] = [],
        addedAt: Date = Date(),
        notes: String = ""
    ) {
        self.id = id
        self.displayName = displayName
        self.category = category
        self.source = source
        self.content = content
        self.tags = tags
        self.addedAt = addedAt
        self.notes = notes
    }
}

// MARK: - Hashable + Equatable (id 기반)

extension ResourceLibraryItem {
    public static func == (lhs: ResourceLibraryItem, rhs: ResourceLibraryItem) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - LibraryItemError

/// 라이브러리 작업 중 발생할 수 있는 오류.
public enum LibraryItemError: Error, LocalizedError {
    case noRawURL
    case networkError(URL, Error)
    case httpError(URL, Int)
    case encodingError(URL)
    case diskWriteError(URL, Error)

    public var errorDescription: String? {
        switch self {
        case .noRawURL:
            return "이 자료는 다운로드 URL이 없어요. URL을 직접 입력해 추가할 수 있어요."
        case .networkError(let url, let underlying):
            return "네트워크 오류로 다운로드에 실패했어요.\nURL: \(url.absoluteString)\n원인: \(underlying.localizedDescription)\n잠시 후 다시 시도해 주세요."
        case .httpError(let url, let code):
            let suggestion: String
            switch code {
            case 404:
                suggestion = "URL이 유효한지 확인해 주세요."
            case 401, 403:
                suggestion = "접근 권한이 없는 리소스예요."
            case 429:
                suggestion = "요청이 너무 많아요. 잠시 후 다시 시도해 주세요."
            case 500...599:
                suggestion = "서버 오류예요. 나중에 다시 시도해 주세요."
            default:
                suggestion = "네트워크 상태를 확인해 주세요."
            }
            return "HTTP \(code) 오류.\nURL: \(url.absoluteString)\n\(suggestion)"
        case .encodingError(let url):
            return "파일 인코딩을 읽을 수 없어요.\nURL: \(url.absoluteString)\n파일이 UTF-8 텍스트인지 확인해 주세요."
        case .diskWriteError(let path, let underlying):
            return "디스크 저장에 실패했어요.\n경로: \(path.path)\n원인: \(underlying.localizedDescription)"
        }
    }
}
