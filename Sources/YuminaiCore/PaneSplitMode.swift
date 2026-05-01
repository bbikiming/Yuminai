import Foundation

/// 워크스페이스 chat 영역 layout (ADR-032 U4).
///
/// 단순화된 split — 한 쪽이 active pane, 다른 쪽은 secondary pane(들) 중 첫 번째.
/// 진짜 N-pane split는 v0.5.
public enum PaneSplitMode: String, Sendable, Codable, CaseIterable, Equatable {
    /// 한 시점에 active pane만 표시 (기본). tab으로 전환.
    case single
    /// 좌/우 split — left = active pane, right = first non-active pane (or active 둘 다).
    case horizontal
    /// 위/아래 split.
    case vertical

    public var label: String {
        switch self {
        case .single: return "단일"
        case .horizontal: return "좌·우"
        case .vertical: return "위·아래"
        }
    }

    public var icon: String {
        switch self {
        case .single: return "rectangle"
        case .horizontal: return "rectangle.split.2x1"
        case .vertical: return "rectangle.split.1x2"
        }
    }
}
