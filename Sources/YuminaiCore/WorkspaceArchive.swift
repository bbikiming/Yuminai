import Foundation

/// **ADR-078 Phase 5** — 워크스페이스 + 폴더 + 핀 + 태그 백업/복원 archive 형식.
///
/// ## 목적
/// - 사용자가 새 PC로 이전하거나 백업을 위해 모든 워크스페이스 메타데이터를 export
/// - 다른 PC에서 import 시 conflict resolution (skip / replace / merge)
///
/// ## 포함되는 데이터
/// - **Workspaces**: 메타데이터 (이름, 경로, 프로필) — 실제 파일 X
/// - **Folders**: 폴더 구조 + 색상 + 아이콘
/// - **Pins**: 핀된 워크스페이스 IDs (순서 유지)
/// - **Tags**: 태그 정의 + 워크스페이스 ↔ 태그 매핑
/// - **Smart folder 활성화**: 사용자 preference
///
/// ## 포함되지 않는 데이터 (보안 + 크기)
/// - 채팅 세션 (sensitive)
/// - 시크릿 (Anthropic API key, Telegram token — Keychain)
/// - 워크스페이스 안 실제 파일 (이미 사용자 디렉토리에 존재)
///
/// ## Format
/// - **JSON**, version-tagged for forward-compat
/// - File extension: `.yuminai.json`
public struct WorkspaceArchive: Sendable, Codable, Hashable {
    /// Schema 버전 — 향후 변경 시 migration 분기.
    public static let currentVersion: Int = 1
    public let version: Int
    /// Export 시점.
    public let exportedAt: Date
    /// Yuminai 앱 버전 (디버깅용).
    public let appVersion: String

    public let workspaces: [Workspace]
    public let folders: [WorkspaceFolder]
    public let pinnedWorkspaceIds: [UUID]
    public let tags: [WorkspaceTag]
    public let tagAssignments: WorkspaceTagAssignments
    public let enabledSmartFolders: Set<SmartFolderKind>

    public init(
        version: Int = WorkspaceArchive.currentVersion,
        exportedAt: Date = Date(),
        appVersion: String = "1.0.0",
        workspaces: [Workspace],
        folders: [WorkspaceFolder],
        pinnedWorkspaceIds: [UUID],
        tags: [WorkspaceTag],
        tagAssignments: WorkspaceTagAssignments,
        enabledSmartFolders: Set<SmartFolderKind>
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.workspaces = workspaces
        self.folders = folders
        self.pinnedWorkspaceIds = pinnedWorkspaceIds
        self.tags = tags
        self.tagAssignments = tagAssignments
        self.enabledSmartFolders = enabledSmartFolders
    }

    /// Pretty-printed JSON encode (encode(to:) Codable conformance와 충돌 회피용 별도 함수).
    public func toJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// JSON decode + version 호환성 검증.
    public static func fromJSON(_ data: Data) throws -> WorkspaceArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(WorkspaceArchive.self, from: data)
        // version 호환 체크
        guard archive.version <= WorkspaceArchive.currentVersion else {
            throw WorkspaceArchiveError.unsupportedVersion(archive.version)
        }
        return archive
    }
}

public enum WorkspaceArchiveError: Error, LocalizedError {
    case unsupportedVersion(Int)
    case decodeFailure(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let v):
            return "Yuminai \(v) 버전 archive입니다. 현재 앱이 지원하지 않는 형식입니다. 앱을 업데이트한 후 다시 시도하세요."
        case .decodeFailure(let msg):
            return "Archive 파일을 읽을 수 없습니다: \(msg)"
        }
    }
}

/// **ADR-078 Phase 5** — Import 시 충돌 해결 전략.
public enum WorkspaceImportStrategy: String, Sendable, CaseIterable, Identifiable {
    /// 같은 이름의 워크스페이스가 있으면 skip (기존 유지).
    case skipExisting
    /// 같은 이름이 있어도 ID 새로 생성하여 추가 (이름 중복 발생 가능).
    case mergeAll
    /// 같은 이름이 있으면 archive 데이터로 덮어쓰기 (위험).
    case replaceExisting

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .skipExisting:    return "기존 항목 유지 (안전)"
        case .mergeAll:        return "모두 추가 (이름 중복 가능)"
        case .replaceExisting: return "기존 덮어쓰기 (위험)"
        }
    }

    public var hint: String {
        switch self {
        case .skipExisting:    return "이미 같은 이름의 워크스페이스가 있으면 archive 데이터를 무시합니다."
        case .mergeAll:        return "모든 archive 데이터를 새 ID로 추가합니다. 같은 이름이 여러 개 생길 수 있어요."
        case .replaceExisting: return "같은 이름의 기존 워크스페이스를 archive 데이터로 덮어씁니다. 기존 메타데이터가 사라질 수 있어요."
        }
    }
}

/// **ADR-078 Phase 5** — Import 결과 요약.
public struct WorkspaceImportResult: Sendable, Hashable {
    public var workspacesAdded: Int = 0
    public var workspacesSkipped: Int = 0
    public var workspacesReplaced: Int = 0
    public var foldersAdded: Int = 0
    public var tagsAdded: Int = 0

    public init(
        workspacesAdded: Int = 0,
        workspacesSkipped: Int = 0,
        workspacesReplaced: Int = 0,
        foldersAdded: Int = 0,
        tagsAdded: Int = 0
    ) {
        self.workspacesAdded = workspacesAdded
        self.workspacesSkipped = workspacesSkipped
        self.workspacesReplaced = workspacesReplaced
        self.foldersAdded = foldersAdded
        self.tagsAdded = tagsAdded
    }

    /// 사용자에게 보여줄 한국어 요약.
    public var summary: String {
        var parts: [String] = []
        if workspacesAdded > 0 { parts.append("워크스페이스 \(workspacesAdded)개 추가") }
        if workspacesSkipped > 0 { parts.append("\(workspacesSkipped)개 건너뜀") }
        if workspacesReplaced > 0 { parts.append("\(workspacesReplaced)개 덮어씀") }
        if foldersAdded > 0 { parts.append("폴더 \(foldersAdded)개") }
        if tagsAdded > 0 { parts.append("태그 \(tagsAdded)개") }
        return parts.isEmpty ? "변경 없음" : parts.joined(separator: ", ")
    }
}
