import Foundation

/// **ADR-104** — 첫 실행 설치 wizard에서 검사·설치하는 도구 정의.
///
/// CaseIterable로 모든 도구를 순서대로 순회 가능. 각 도구는 설치 여부
/// 검사 경로(detectionPaths)와 자동 설치 명령(installCommand)을 보유.
public enum SetupTool: String, CaseIterable, Identifiable, Sendable {
    /// Anthropic 공식 코딩 에이전트 — Yuminai의 핵심 의존성.
    case claudeCode
    /// OpenAI 공식 코딩 에이전트 — Codex 모델 사용 시 필요.
    case codexCLI
    /// 텔레그램 봇 빠른 시작 도구.
    case cokacdir

    public var id: String { rawValue }

    /// UI에 표시할 도구 이름.
    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codexCLI: return "Codex CLI"
        case .cokacdir: return "cokacdir"
        }
    }

    /// 친화 설명 (1-2줄). 초보 사용자도 이해할 수 있도록 작성.
    public var purpose: String {
        switch self {
        case .claudeCode:
            return "Anthropic의 공식 코딩 에이전트. Yuminai의 핵심 — 반드시 필요해요."
        case .codexCLI:
            return "OpenAI의 공식 코딩 에이전트. Codex 모델을 쓰려면 설치하세요. 선택 사항."
        case .cokacdir:
            return "텔레그램 봇을 빠르게 시작할 수 있는 도구. 텔레그램으로 원격 작업하려면 권장."
        }
    }

    /// Yuminai 동작에 필수 여부. claudeCode만 true.
    public var isRequired: Bool {
        switch self {
        case .claudeCode: return true
        case .codexCLI: return false
        case .cokacdir: return false
        }
    }

    /// 터미널에서 실행할 설치 명령.
    public var installCommand: String {
        switch self {
        case .claudeCode:
            return "curl -fsSL https://claude.ai/install.sh | bash"
        case .codexCLI:
            return "npm i -g @openai/codex"
        case .cokacdir:
            return "curl -fsSL https://cokacdir.cokac.com/manage.sh | bash && cokacctl"
        }
    }

    /// 공식 문서 URL.
    public var docsURL: URL {
        switch self {
        case .claudeCode:
            return URL(string: "https://docs.anthropic.com/en/docs/claude-code")!
        case .codexCLI:
            return URL(string: "https://github.com/openai/codex")!
        case .cokacdir:
            return URL(string: "https://cokacdir.cokac.com")!
        }
    }

    /// PATH에서 검색할 실행 파일 이름 (which/command -v fallback에 사용).
    /// 사용자 환경마다 설치 경로가 다양하므로 PATH 검색이 가장 신뢰성 높음.
    public var executableName: String {
        switch self {
        case .claudeCode: return "claude"
        case .codexCLI: return "codex"
        case .cokacdir: return "cokacctl"
        }
    }

    /// 설치 여부를 검사할 바이너리 경로 목록 (fast path — PATH 검색 전 우선 검사).
    /// `$HOME`은 런타임에 `ProcessInfo`로 치환해야 함 (SetupChecker 참조).
    /// 모든 경로 미스 시 `executableName`으로 PATH 전체 검색 (login shell).
    public var detectionPaths: [String] {
        switch self {
        case .claudeCode:
            return [
                "/usr/local/bin/claude",
                "/opt/homebrew/bin/claude",
                "$HOME/.claude/bin/claude",
                "$HOME/.claude/local/claude",
                "$HOME/.local/bin/claude",
                "$HOME/bin/claude"
            ]
        case .codexCLI:
            return [
                "/usr/local/bin/codex",
                "/opt/homebrew/bin/codex",
                "$HOME/.npm-global/bin/codex",
                "$HOME/.npm/global/bin/codex",
                "$HOME/.local/bin/codex",
                "$HOME/bin/codex",
                "/opt/homebrew/lib/node_modules/@openai/codex/bin/codex"
            ]
        case .cokacdir:
            return [
                "/usr/local/bin/cokacctl",
                "/opt/homebrew/bin/cokacctl",
                "$HOME/.cokacdir/bin/cokacctl",
                "$HOME/.cokacdir/cokacctl",
                "$HOME/.local/bin/cokacctl",
                "$HOME/bin/cokacctl"
            ]
        }
    }

    /// SF Symbol 아이콘 이름.
    public var iconName: String {
        switch self {
        case .claudeCode: return "sparkles"
        case .codexCLI: return "terminal"
        case .cokacdir: return "paperplane"
        }
    }

    /// 사이드바 배지 레이블 (필수/선택/권장).
    public var badgeLabel: String {
        switch self {
        case .claudeCode: return "필수"
        case .codexCLI: return "선택"
        case .cokacdir: return "권장"
        }
    }
}
