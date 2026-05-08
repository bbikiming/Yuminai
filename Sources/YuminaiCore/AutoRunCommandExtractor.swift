import Foundation

/// **ADR-134** — AutoRun turn 응답에서 실행 가능한 명령 패턴을 추출한다.
///
/// ## 목적
/// LLM 응답 텍스트 안에 포함된 코드 블록(bash/sh/zsh) 또는 인라인 명령에서
/// `gh`, `glab`, `git`, `rm`, `DROP TABLE` 등 CommandPolicyMatrix 평가 대상
/// 명령을 추출해 반환한다.
///
/// ## 추출 방식
/// 1. fenced code block (```bash, ```sh, ```zsh, ```shell) 내 첫 줄 각각 추출
/// 2. 인라인 백틱 내 텍스트 중 known-tool prefix 시작 명령 추출
/// 3. 중복 제거 후 반환
///
/// ## 한계
/// - LLM이 명령을 plain text로 서술한 경우는 미감지 (tool_use JSON이 없으므로)
/// - 오탐 가능성 있음 — CommandPolicy는 보수적 기본값을 사용하므로 안전
public enum AutoRunCommandExtractor {

    // MARK: - Known tool prefixes for inline extraction

    private static let knownPrefixes: [String] = [
        "gh ", "glab ", "git ", "rm ", "rmdir ",
        "DROP TABLE", "DROP DATABASE", "DELETE FROM", "TRUNCATE",
        "kill ", "shutdown", "reboot", "dd if=", "mkfs",
        "npm run", "npm exec", "npx ",
    ]

    // MARK: - Public API

    /// LLM 응답 텍스트에서 명령 후보 목록을 추출한다.
    ///
    /// - Parameter text: LLM 응답 전문.
    /// - Returns: 명령 문자열 배열 (중복 제거됨).
    public static func extract(from text: String) -> [String] {
        var commands: [String] = []
        commands += extractFromCodeBlocks(text)
        commands += extractFromInlineCode(text)
        // 중복 제거
        var seen = Set<String>()
        return commands.filter { seen.insert($0).inserted }
    }

    // MARK: - Private

    /// fenced code block에서 명령 추출.
    private static func extractFromCodeBlocks(_ text: String) -> [String] {
        // ```bash / ```sh / ```zsh / ```shell / ``` (언어 없음)
        let pattern = #"```(?:bash|sh|zsh|shell|)?\s*\n([\s\S]*?)```"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        var result: [String] = []
        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let blockRange = match.range(at: 1)
            guard blockRange.location != NSNotFound else { continue }
            let block = nsText.substring(with: blockRange)
            // 각 줄을 개별 명령으로 추출
            let lines = block.components(separatedBy: "\n")
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                // 빈 줄, 주석 제외
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                result.append(trimmed)
            }
        }
        return result
    }

    /// 인라인 백틱에서 known-tool 명령 추출.
    private static func extractFromInlineCode(_ text: String) -> [String] {
        let pattern = #"`([^`]+)`"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        var result: [String] = []
        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let range = match.range(at: 1)
            guard range.location != NSNotFound else { continue }
            let code = nsText.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            if isKnownCommand(code) {
                result.append(code)
            }
        }
        return result
    }

    /// known prefix로 시작하는 명령인지 확인.
    private static func isKnownCommand(_ text: String) -> Bool {
        knownPrefixes.contains { text.hasPrefix($0) }
    }
}
