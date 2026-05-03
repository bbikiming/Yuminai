import Foundation

/// **ADR-077 Phase 3** — Smart folders (자동 그룹화 폴더).
///
/// ## 일반 폴더 vs Smart 폴더
/// - **일반 폴더 (`WorkspaceFolder`)**: 사용자가 명시적으로 추가/제거 (manual)
/// - **Smart 폴더 (`SmartFolderKind`)**: 조건 기반 자동 계산 (automatic)
///   - 조건 변경 시 자동 갱신 (e.g., 7일 지나면 "최근 7일"에서 빠짐)
///
/// ## 근거
/// - **macOS Finder Smart Folders** (https://support.apple.com/en-us/102935): 검색 조건 저장
/// - **Apple Mail VIP Inbox**: 자동 필터링 그룹
/// - **NN/g "Faceted Search"**: 사용자 조건으로 자동 필터링이 manual 분류보다 효율적
///
/// ## Smart folder 종류
/// 1. **`recentWeek`**: 최근 7일 안에 lastOpenedAt 있는 워크스페이스
/// 2. **`telegramBound`**: 텔레그램에 연결된 워크스페이스
/// 3. **`hasPinned`**: 핀된 워크스페이스 (이미 핀 그룹과 중복 — 옵션, default OFF)
/// 4. **`hasArchived`**: archived 워크스페이스 (배경 정리용)
public enum SmartFolderKind: String, Sendable, Codable, CaseIterable, Hashable, Identifiable {
    case recentWeek
    case telegramBound
    case archived

    public var id: String { rawValue }

    /// 한국어 라벨 (사이드바 표시).
    public var displayName: String {
        switch self {
        case .recentWeek:    return "최근 7일"
        case .telegramBound: return "텔레그램 연결됨"
        case .archived:      return "보관함"
        }
    }

    /// SF Symbol 아이콘.
    public var iconName: String {
        switch self {
        case .recentWeek:    return "clock.arrow.circlepath"
        case .telegramBound: return "paperplane.fill"
        case .archived:      return "archivebox.fill"
        }
    }

    /// Semantic 색상 이름 (Theme.Color.folderColor에서 lookup).
    public var colorName: String {
        switch self {
        case .recentWeek:    return "blue"
        case .telegramBound: return "accent"
        case .archived:      return "gray"
        }
    }

    /// 사용자에게 보여줄 짧은 설명 (HelpHint 등).
    public var hint: String {
        switch self {
        case .recentWeek:    return "최근 7일 안에 사용한 워크스페이스를 자동으로 보여줍니다."
        case .telegramBound: return "텔레그램에 연결된 워크스페이스를 자동으로 보여줍니다."
        case .archived:      return "보관함에 넣은 워크스페이스를 자동으로 보여줍니다."
        }
    }

    /// **default 활성화** smart folder들. 신규 사용자에게 즉시 보임.
    public static let defaultEnabled: Set<SmartFolderKind> = [.recentWeek]
}

/// **ADR-077 Phase 3** — 워크스페이스가 smart folder 조건에 부합하는지 평가.
///
/// 외부 의존성 (Workspace의 lastOpenedAt 등)을 closure로 받아 pure 함수로 유지 → testable.
public enum SmartFolderEvaluator {
    /// 7일 (초 단위).
    public static let recentWindowSeconds: TimeInterval = 7 * 24 * 60 * 60

    /// 워크스페이스가 `recentWeek` 조건 부합 여부.
    public static func isRecent(lastOpenedAt: Date?, now: Date = Date()) -> Bool {
        guard let lastOpenedAt else { return false }
        return now.timeIntervalSince(lastOpenedAt) < recentWindowSeconds
    }

    /// 워크스페이스가 텔레그램 연결됨 여부 (legacy bound + multi-chat bindings 모두 확인).
    public static func isTelegramBound(
        workspaceId: UUID,
        boundId: UUID?,
        chatBindings: [String: UUID]
    ) -> Bool {
        if boundId == workspaceId { return true }
        return chatBindings.values.contains(workspaceId)
    }
}
