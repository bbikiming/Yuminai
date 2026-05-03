import SwiftUI
import UniformTypeIdentifiers

/// **ADR-077 Phase 1** — 워크스페이스 drag and drop infrastructure.
///
/// ## 설계 결정
/// - **Transferable 프로토콜** (iOS 16+/macOS 13+): SwiftUI 표준 drag-drop
/// - **UTType** custom: `com.yuminai.workspace.id` — Yuminai 앱 안에서만 drop 가능
///   (Finder 등 외부 drop 차단 — 보안 + UX 명확성)
/// - **UUID payload만**: 워크스페이스 ID만 transfer, 전체 객체는 callback에서 lookup
///
/// ## 근거
/// - **Apple HIG "Drag and Drop"** (https://developer.apple.com/design/human-interface-guidelines/drag-and-drop):
///   "Use drag and drop to move data within an app or between apps"
///   "Provide visual feedback to indicate valid drop targets"
/// - **WCAG 2.2 SC 2.5.7 Dragging Movements** (AA, NEW): drag 동작에 대안 제공
///   → context menu "폴더로 이동"이 alternative (이미 ADR-076에 있음)
public struct WorkspaceDragPayload: Codable, Transferable {
    public let workspaceId: UUID

    public init(workspaceId: UUID) {
        self.workspaceId = workspaceId
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .yuminaiWorkspace)
    }
}

public extension UTType {
    /// **ADR-077 Phase 1** — Yuminai workspace drag UTType.
    /// `com.yuminai.workspace.id`로 외부 앱과 충돌 X.
    static let yuminaiWorkspace = UTType(exportedAs: "com.yuminai.workspace.id")
}

/// **ADR-077 Phase 4** — Pin 순서 reorder용 drag payload.
/// workspaceId + 현재 위치 (pinned 안에서 reorder 시 활용).
public struct WorkspacePinReorderPayload: Codable, Transferable {
    public let workspaceId: UUID
    public let currentIndex: Int

    public init(workspaceId: UUID, currentIndex: Int) {
        self.workspaceId = workspaceId
        self.currentIndex = currentIndex
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .yuminaiPinReorder)
    }
}

public extension UTType {
    /// **ADR-077 Phase 4** — Pin 그룹 안 reorder UTType.
    static let yuminaiPinReorder = UTType(exportedAs: "com.yuminai.pin.reorder")
}
