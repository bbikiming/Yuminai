import Foundation

/// **ADR-133** — 명령 실행 정책 (GitHub/GitLab 자동화 권한 위임).
///
/// AutoRun + 일반 명령 실행 시 gh/glab/git 명령에 대한
/// 자동 승인(allow) / HITL 확인(requireConfirmation) / 차단(deny) 정책을 정의한다.
///
/// ## 설계 원칙
/// - 순수 struct/enum — 부수효과 없음, 불변 입력 → 불변 출력
/// - 기본값은 보수적 (write 작업은 모두 confirmation)
/// - 사용자 정의 패턴이 기본 패턴보다 우선
public enum CommandPolicy: Sendable, Codable, Hashable {
    /// 자동 승인 — 사용자 확인 없이 바로 실행.
    case allow
    /// HITL 확인 필요 — AutoRun 일시정지 후 사용자 승인 대기.
    case requireConfirmation
    /// 차단 — HITLActionGuard.deny와 동일. destructive 명령.
    case deny

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .allow: try c.encode("allow", forKey: .type)
        case .requireConfirmation: try c.encode("requireConfirmation", forKey: .type)
        case .deny: try c.encode("deny", forKey: .type)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "allow": self = .allow
        case "deny": self = .deny
        default: self = .requireConfirmation
        }
    }

    /// 사용자 친화 레이블.
    public var displayName: String {
        switch self {
        case .allow: return "자동 승인"
        case .requireConfirmation: return "확인 필요"
        case .deny: return "차단"
        }
    }

    /// 아이콘 SF Symbol.
    public var icon: String {
        switch self {
        case .allow: return "checkmark.circle.fill"
        case .requireConfirmation: return "exclamationmark.circle.fill"
        case .deny: return "xmark.circle.fill"
        }
    }
}

// MARK: - CommandPolicyMatrix

/// `gh`, `glab`, `git`, `npm`, `bash`/`sh` 등 도구별 정책 매트릭스.
///
/// ## 우선순위 (높은 순)
/// 1. denyPatterns (차단) — HITLActionGuard.dangerousPatterns 포함
/// 2. 사용자 정의 allowPatterns
/// 3. 기본 allowList / allowPatterns
/// 4. 기본 정책: requireConfirmation
///
/// ## 안전 기본값 (`.default`)
/// - gh/glab read 명령 (list/view/status) → allow
/// - gh pr create / issue create → allow
/// - gh pr merge / release create / workflow run → requireConfirmation
/// - gh repo delete / secret set → deny
/// - git push --force / reset --hard / clean -f → deny (HITLActionGuard)
public struct CommandPolicyMatrix: Sendable, Codable, Hashable {

    // MARK: - 프로퍼티

    /// 정확 매칭 자동 승인 목록 (예: "gh pr list").
    public var allowList: [String]

    /// 정규식 자동 승인 패턴 (예: "^gh\\s+(repo|pr|issue)\\s+(view|list|status)").
    public var allowPatterns: [String]

    /// 차단 패턴 — HITLActionGuard.dangerousPatterns + 사용자 추가.
    public var denyPatterns: [String]

    /// 권한 요청 자동 승인 (AutoRunConfig.autoApprovePermissions 연동).
    public var autoApprovePermissions: Bool

    // MARK: - 기본값

    /// 안전 기본값 — ADR-132와 호환.
    public static let `default`: CommandPolicyMatrix = CommandPolicyMatrix(
        allowList: defaultAllowList,
        allowPatterns: defaultAllowPatterns,
        denyPatterns: defaultDenyPatterns,
        autoApprovePermissions: true
    )

    // MARK: - init

    public init(
        allowList: [String] = CommandPolicyMatrix.defaultAllowList,
        allowPatterns: [String] = CommandPolicyMatrix.defaultAllowPatterns,
        denyPatterns: [String] = CommandPolicyMatrix.defaultDenyPatterns,
        autoApprovePermissions: Bool = true
    ) {
        self.allowList = allowList
        self.allowPatterns = allowPatterns
        self.denyPatterns = denyPatterns
        self.autoApprovePermissions = autoApprovePermissions
    }

    // MARK: - 정책 평가

    /// `command`에 대한 실행 정책을 반환한다.
    ///
    /// ## 평가 순서
    /// 1. denyPatterns 매칭 → `.deny`
    /// 2. allowList 정확 매칭 → `.allow`
    /// 3. allowPatterns 정규식 매칭 → `.allow`
    /// 4. 기본 → `.requireConfirmation`
    public func policy(for command: String) -> CommandPolicy {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. 차단 패턴 최우선
        for pattern in denyPatterns {
            if matches(trimmed, pattern: pattern) {
                return .deny
            }
        }

        // 2. 정확 매칭 자동 승인
        if allowList.contains(where: { trimmed.hasPrefix($0) }) {
            return .allow
        }

        // 3. 정규식 자동 승인
        for pattern in allowPatterns {
            if matches(trimmed, pattern: pattern) {
                return .allow
            }
        }

        // 4. 기본: 확인 필요
        return .requireConfirmation
    }

    // MARK: - 편의 평가 (static)

    /// `command`에 대해 `.default` 매트릭스로 정책을 평가한다.
    public static func evaluate(_ command: String) -> CommandPolicy {
        CommandPolicyMatrix.default.policy(for: command)
    }

    // MARK: - Private

    private func matches(_ text: String, pattern: String) -> Bool {
        (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]))
            .map { regex in
                let range = NSRange(text.startIndex..., in: text)
                return regex.firstMatch(in: text, options: [], range: range) != nil
            } ?? false
    }
}

// MARK: - 기본 패턴 상수

extension CommandPolicyMatrix {

    // MARK: Allow List (정확 prefix 매칭)

    /// GitHub/GitLab read-only 명령 자동 승인 목록.
    public static let defaultAllowList: [String] = [
        // gh — 읽기 전용
        "gh repo view",
        "gh repo list",
        "gh repo clone",
        "gh pr list",
        "gh pr view",
        "gh pr status",
        "gh pr checks",
        "gh pr diff",
        "gh issue list",
        "gh issue view",
        "gh issue status",
        "gh run list",
        "gh run view",
        "gh workflow list",
        "gh workflow view",
        "gh release list",
        "gh release view",
        "gh api",
        "gh auth status",
        "gh status",
        // glab — 읽기 전용
        "glab repo view",
        "glab mr list",
        "glab mr view",
        "glab mr status",
        "glab issue list",
        "glab issue view",
        "glab pipeline list",
        "glab pipeline status",
        "glab release list",
        "glab auth status",
        // git — 읽기 전용
        "git status",
        "git log",
        "git diff",
        "git branch",
        "git fetch",
        "git stash list",
        "git show",
        "git remote -v",
    ]

    // MARK: Allow Patterns (정규식)

    /// 자동 승인 정규식 패턴.
    public static let defaultAllowPatterns: [String] = [
        // gh 읽기 계열 — view/list/status/checks
        #"^gh\s+(repo|pr|issue|run|workflow|release|gist|codespace)\s+(view|list|status|checks|diff)\b"#,
        // gh pr create / issue create (사용자 의도 명확)
        #"^gh\s+(pr|issue)\s+create\b"#,
        // gh pr comment (읽기+쓰기 혼합이지만 비파괴)
        #"^gh\s+pr\s+comment\b"#,
        // gh issue comment
        #"^gh\s+issue\s+comment\b"#,
        // glab 읽기 계열
        #"^glab\s+(mr|issue|pipeline|release)\s+(view|list|status|approve)\b"#,
        // glab mr create (사용자 의도 명확)
        #"^glab\s+mr\s+create\b"#,
        // git 읽기 계열
        #"^git\s+(status|log|diff|show|branch|fetch|stash list|remote -v|ls-files|describe)\b"#,
    ]

    // MARK: Deny Patterns (차단 — HITLActionGuard + gh/glab 위험)

    /// 차단 정규식 패턴.
    /// HITLActionGuard.dangerousPatterns + GitHub/GitLab 위험 명령.
    public static let defaultDenyPatterns: [String] = [
        // --- git 강제 파괴 (HITLActionGuard 동기화) ---
        #"git\s+push\s+(?:-f\b|--force\b)"#,
        #"git\s+reset\s+--hard\b"#,
        #"git\s+clean\s+-[a-z]*f[a-z]*"#,
        #"git\s+checkout\s+--\s"#,

        // --- 파일 시스템 삭제 (HITLActionGuard 동기화) ---
        #"rm\s+-[a-z]*r[a-z]*\s"#,
        #"rm\s+-[a-z]*f[a-z]*\s"#,
        #"rmdir\s+--ignore-fail"#,

        // --- 데이터베이스 파괴 (HITLActionGuard 동기화) ---
        #"DROP\s+TABLE\b"#,
        #"DROP\s+DATABASE\b"#,
        #"DELETE\s+FROM\b"#,
        #"TRUNCATE\s+(?:TABLE\s+)?\w"#,

        // --- 시스템 제어 (HITLActionGuard 동기화) ---
        #"\bkill\s+-9\b"#,
        #"\b(?:shutdown|reboot|halt)\b"#,
        #"\bdd\s+if="#,
        #">\s*/dev/sd[a-z]"#,
        #"\bmkfs\b"#,

        // --- gh 위험 명령 ---
        #"^gh\s+repo\s+delete\b"#,
        #"^gh\s+secret\s+set\b"#,
        #"^gh\s+secret\s+delete\b"#,
        #"^gh\s+repo\s+archive\b"#,

        // --- glab 위험 명령 ---
        #"^glab\s+project\s+delete\b"#,
        #"^glab\s+variable\s+set\b"#,
        #"^glab\s+variable\s+delete\b"#,
    ]
}
