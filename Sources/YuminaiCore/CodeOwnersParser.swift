import Foundation

/// **ADR-082 Phase 5** — `.github/CODEOWNERS` 파일 단순 파서.
///
/// CODEOWNERS 형식 (GitHub 표준):
/// ```
/// # comments
/// *               @global-owner1 @global-owner2
/// /docs/          @docs-team
/// *.swift         @ios-team
/// ```
///
/// 매칭 규칙:
/// - 정확한 path > glob > 와일드카드 우선
/// - **마지막** 매칭 line이 winner (CODEOWNERS spec)
/// - `@user` 또는 `@org/team` 형식 owner 추출
///
/// ## 단순화 (vs GitHub 풀 spec)
/// - `**/` recursive glob 미지원 (단순 prefix + suffix만)
/// - email 형식 미지원
/// - `!negation` 미지원
public enum CodeOwnersParser {
    public struct Rule: Sendable, Hashable {
        public let pattern: String
        public let owners: [String]
    }

    /// CODEOWNERS 텍스트 파싱.
    public static func parse(_ content: String) -> [Rule] {
        var rules: [Rule] = []
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            // comment / 빈 줄 skip
            if line.isEmpty || line.hasPrefix("#") { continue }
            // pattern + owners 분리
            let tokens = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard tokens.count >= 2 else { continue }
            let pattern = tokens[0]
            let owners = Array(tokens.dropFirst()).filter { $0.hasPrefix("@") }
            guard !owners.isEmpty else { continue }
            rules.append(Rule(pattern: pattern, owners: owners))
        }
        return rules
    }

    /// 변경된 paths에 매칭되는 owner set 반환.
    /// - 정책: 각 path마다 마지막 매칭 rule이 winner (GitHub 표준).
    /// - "@" prefix 제거된 login만 반환 (`@user` → `user`).
    public static func match(codeowners: String, paths: [String]) -> Set<String> {
        let rules = parse(codeowners)
        var result: Set<String> = []
        for path in paths {
            // 마지막 매칭 rule이 winner — reverse iterate
            for rule in rules.reversed() where matches(pattern: rule.pattern, path: path) {
                for owner in rule.owners {
                    let stripped = owner.hasPrefix("@") ? String(owner.dropFirst()) : owner
                    result.insert(stripped)
                }
                break  // 첫 매칭 (= 마지막) 후 중단
            }
        }
        return result
    }

    /// Glob pattern 매칭 (단순화: prefix `/`, suffix `*`, exact).
    static func matches(pattern: String, path: String) -> Bool {
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        // 와일드카드만
        if pattern == "*" { return true }
        // 절대 prefix `/docs/` → path가 같은 prefix로 시작하는지
        if pattern.hasSuffix("/") {
            // directory rule
            let prefix = pattern.hasPrefix("/") ? pattern : "/\(pattern)"
            return normalizedPath.hasPrefix(prefix)
        }
        // suffix glob `*.swift`
        if pattern.hasPrefix("*.") {
            let ext = String(pattern.dropFirst(1))  // ".swift"
            return path.hasSuffix(ext)
        }
        // prefix glob `docs/*` (suffix * 처리)
        if pattern.hasSuffix("/*") {
            let prefix = String(pattern.dropLast(2))
            let normPrefix = prefix.hasPrefix("/") ? prefix : "/\(prefix)"
            // 직접 자식만 매칭 (recursive X)
            let nextSlash = normalizedPath.range(of: "/", range: normalizedPath.index(normalizedPath.startIndex, offsetBy: normPrefix.count + 1)..<normalizedPath.endIndex)
            return normalizedPath.hasPrefix(normPrefix + "/") && nextSlash == nil
        }
        // exact path
        let normPattern = pattern.hasPrefix("/") ? pattern : "/\(pattern)"
        return normalizedPath == normPattern
    }
}
