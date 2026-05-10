import Foundation
import os

/// **ADR-132** — `.harness/rules/` 디렉토리에서 Markdown 파일을 일괄 로드하는 헬퍼.
///
/// 자동 실행 시 LLM system prompt에 워크스페이스 규칙을 주입하는 데 사용된다.
///
/// ## 동작
/// - `.harness/rules/*.md` 파일을 파일명 알파벳 오름차순으로 읽음
/// - 각 파일은 `## <filename>` 섹션 헤더와 함께 이어 붙임
/// - 빈 파일, 없는 디렉토리는 조용히 skip (throw 없음)
///
/// ## 순수 static — 상태 없음, 부수효과는 파일 시스템 읽기뿐
public enum HarnessRulesLoader {

    private static let logger = Logger(subsystem: "ai.yuminai", category: "HarnessRulesLoader")

    // MARK: - Public API

    /// `.harness/rules/` 디렉토리에서 `.md` 파일을 모두 로드해 하나의 문자열로 반환.
    ///
    /// **ADR-153 P1-2** — `excludeFiles` 파라미터로 특정 파일명(확장자 제외)을 로드에서 제외.
    /// AutoRun이 `USER_PROFILE.md`를 제외해 3중 주입 방지에 사용한다.
    ///
    /// - Parameters:
    ///   - workspaceURL: 워크스페이스 루트 URL.
    ///   - excludeFiles: 로드에서 제외할 파일명 목록 (확장자 없이). 예: `["USER_PROFILE"]`.
    /// - Returns: 합쳐진 규칙 문자열. 파일이 없거나 디렉토리 없으면 빈 문자열.
    public static func loadAll(workspaceURL: URL, excludeFiles: [String] = []) async -> String {
        let rulesURL = workspaceURL
            .appendingPathComponent(".harness")
            .appendingPathComponent("rules")

        let fm = FileManager.default
        guard fm.fileExists(atPath: rulesURL.path) else {
            logger.debug(".harness/rules 디렉토리 없음 — skip")
            return ""
        }

        let allFiles = markdownFiles(in: rulesURL)
        let files = allFiles.filter { url in
            let name = url.deletingPathExtension().lastPathComponent
            return !excludeFiles.contains(name)
        }
        guard !files.isEmpty else {
            logger.debug(".harness/rules/*.md 파일 없음 — skip")
            return ""
        }

        var sections: [String] = []
        for fileURL in files {
            let content = readFile(at: fileURL)
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            let filename = fileURL.deletingPathExtension().lastPathComponent
            sections.append("## \(filename)\n\n\(content)")
        }

        guard !sections.isEmpty else { return "" }

        let combined = """
        # 워크스페이스 규칙 (.harness/rules)

        \(sections.joined(separator: "\n\n---\n\n"))
        """
        logger.info(".harness/rules 로드 완료 — \(files.count)개 파일 (제외: \(excludeFiles))")
        return combined
    }

    // MARK: - 내부 헬퍼

    /// 디렉토리 내 `.md` 파일 목록을 파일명 오름차순으로 반환.
    static func markdownFiles(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return contents
            .filter { $0.pathExtension.lowercased() == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// 파일 내용을 UTF-8로 읽기. 실패 시 빈 문자열 반환 (조용히 skip).
    static func readFile(at url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}
