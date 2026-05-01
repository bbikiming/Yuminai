import Foundation

/// Yuminai 워크스페이스에서 활성화할 코딩 에이전트 종류.
///
/// 같은 프로젝트 폴더 안에서 다른 에이전트들이 유기적으로 협업할 수 있는 시스템(ADR-026)의
/// 첫 단계 — 워크스페이스 단위로 에이전트를 전환할 수 있게 한다. 차기 라운드에서는 같은
/// 워크스페이스에 여러 에이전트 패널을 동시 표시 + 인터-에이전트 메시지 패싱.
public enum AgentKind: String, Sendable, Codable, CaseIterable, Hashable {
    case claude
    case codex

    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }

    public var shortLabel: String {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex"
        }
    }

    public var icon: String {
        switch self {
        case .claude: return "sparkles"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        }
    }

    public var hint: String {
        switch self {
        case .claude: return "Anthropic Claude Code CLI — 설계·검토·문서화에 강함"
        case .codex: return "OpenAI Codex CLI — 빠른 코드 생성·실행에 강함"
        }
    }

    public static let `default`: AgentKind = .claude
}
