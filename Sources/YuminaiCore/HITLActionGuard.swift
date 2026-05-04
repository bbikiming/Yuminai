import Foundation

/// **ADR-098 P0-1** — Destructive action 패턴 매칭 헬퍼.
///
/// `TelegramSessionBridge`의 `isDestructiveToolCall`과 독립적으로 존재하며,
/// `/run <cmd>` 명령어 경로에서도 동일한 위험 패턴을 감지할 수 있도록 한다.
///
/// ## 설계 원칙
/// - 순수 struct — 부수효과 없음, 불변 입력 → 불변 출력
/// - 정규식 기반 패턴 매칭 (대소문자 무시)
/// - `TelegramSessionBridge.isDestructiveToolCall`의 패턴 집합과 동기화
public struct HITLActionGuard: Sendable {

    // MARK: - Dangerous patterns

    /// 위험 명령으로 분류하는 정규식 패턴 목록.
    /// 패턴은 대소문자를 무시하고 매칭된다.
    public static let dangerousPatterns: [(pattern: String, category: String)] = [
        // git — 강제 push / 히스토리 파괴
        (#"git\s+push\s+(?:-f\b|--force\b)"#,          "force-push"),
        (#"git\s+reset\s+--hard\b"#,                    "git-reset"),
        (#"git\s+clean\s+-[a-z]*f[a-z]*"#,             "git-clean"),
        (#"git\s+checkout\s+--\s"#,                     "git-checkout"),

        // 파일 시스템 삭제
        (#"rm\s+-[a-z]*r[a-z]*\s"#,                    "rm-recursive"),
        (#"rm\s+-[a-z]*f[a-z]*\s"#,                    "rm-force"),
        (#"rmdir\s+--ignore-fail"#,                     "rmdir"),

        // 데이터베이스 파괴
        (#"DROP\s+TABLE\b"#,                            "drop-table"),
        (#"DROP\s+DATABASE\b"#,                         "drop-database"),
        (#"DELETE\s+FROM\b"#,                           "delete-from"),
        (#"TRUNCATE\s+(?:TABLE\s+)?\w"#,               "truncate"),

        // 권한 변경
        (#"chmod\s+(?:-R\s+)?[0-7]{3,4}\b"#,           "chmod"),
        (#"chown\s+-R\b"#,                              "chown-recursive"),

        // 시스템 제어
        (#"\bkill\s+-9\b"#,                             "kill-9"),
        (#"\b(?:shutdown|reboot|halt)\b"#,              "system-control"),
        (#"\bdd\s+if="#,                                "dd"),
        (#">\s*/dev/sd[a-z]"#,                         "disk-overwrite"),
        (#"\bmkfs\b"#,                                  "mkfs"),
    ]

    // MARK: - Public API

    /// `command`가 위험 패턴과 일치하면 `true`를 반환한다.
    ///
    /// - Parameter command: 검사할 쉘 명령어 문자열.
    /// - Returns: 하나 이상의 위험 패턴에 일치하면 `true`.
    public static func shouldRequestApproval(command: String) -> Bool {
        category(for: command) != nil
    }

    /// `command`가 일치하는 위험 카테고리 이름을 반환한다.
    /// 위험 패턴과 일치하지 않으면 `nil`.
    ///
    /// - Parameter command: 검사할 쉘 명령어 문자열.
    /// - Returns: 카테고리 이름 (예: "force-push", "rm-recursive"), 또는 `nil`.
    public static func category(for command: String) -> String? {
        for (pattern, cat) in dangerousPatterns {
            if matches(command, pattern: pattern) {
                return cat
            }
        }
        return nil
    }

    // MARK: - Private

    private static func matches(_ text: String, pattern: String) -> Bool {
        (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]))
            .map { regex in
                let range = NSRange(text.startIndex..., in: text)
                return regex.firstMatch(in: text, options: [], range: range) != nil
            } ?? false
    }
}
