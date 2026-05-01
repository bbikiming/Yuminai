import Foundation

/// 노트 편집 모드의 split mode (B4).
public enum EditorSplitMode: String, CaseIterable, Sendable, Equatable {
    case editor, split, preview

    public var label: String {
        switch self {
        case .editor: return "편집"
        case .split: return "분할"
        case .preview: return "미리보기"
        }
    }

    public var icon: String {
        switch self {
        case .editor: return "pencil"
        case .split: return "rectangle.split.2x1"
        case .preview: return "eye"
        }
    }
}
