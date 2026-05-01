import Foundation

/// Obsidian wiki link / 임베드를 swift-markdown-ui가 이해하는 표준 markdown으로 변환.
public enum MarkdownPreprocessor {

    /// `[[Page]]` → `[Page](yuminai-note://Page)`
    /// `[[Page|Display]]` → `[Display](yuminai-note://Page)`
    /// `![[image.png]]` → `![image.png](file:///vault/image.png)` (이미지 확장자만)
    /// `![[Note]]` → `[[Note]]` fallback (노트 임베드는 v0.3)
    public static func process(
        _ markdown: String,
        vaultRoot: URL? = nil,
        imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "svg", "webp", "pdf"]
    ) -> String {
        var output = markdown

        // 1) 이미지 임베드 ![[file.ext]]
        output = processEmbeds(output, vaultRoot: vaultRoot, imageExtensions: imageExtensions)

        // 2) wiki link [[Page]] / [[Page|Display]]
        output = processWikiLinks(output)

        return output
    }

    // MARK: - Wiki link

    static let wikiLinkRegex: NSRegularExpression = {
        // [[ Page ]] 또는 [[ Page | Display ]]
        try! NSRegularExpression(
            pattern: #"\[\[([^\]\|]+)(?:\|([^\]]+))?\]\]"#,
            options: []
        )
    }()

    static func processWikiLinks(_ markdown: String) -> String {
        let ns = markdown as NSString
        let range = NSRange(location: 0, length: ns.length)
        let matches = wikiLinkRegex.matches(in: markdown, options: [], range: range)
        guard !matches.isEmpty else { return markdown }

        var result = ""
        var cursor = 0
        for m in matches {
            let matchRange = m.range
            // 이전 영역 보존
            if matchRange.location > cursor {
                result += ns.substring(with: NSRange(location: cursor, length: matchRange.location - cursor))
            }
            let pageRange = m.range(at: 1)
            let displayRange = m.range(at: 2)
            let page = ns.substring(with: pageRange).trimmingCharacters(in: .whitespaces)
            let display = displayRange.location != NSNotFound
                ? ns.substring(with: displayRange).trimmingCharacters(in: .whitespaces)
                : page
            // URL encode page
            let encoded = page.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? page
            result += "[\(display)](yuminai-note://\(encoded))"
            cursor = matchRange.location + matchRange.length
        }
        if cursor < ns.length {
            result += ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
        }
        return result
    }

    // MARK: - Embed

    static let embedRegex: NSRegularExpression = {
        // ![[ file.ext ]]
        try! NSRegularExpression(
            pattern: #"\!\[\[([^\]]+)\]\]"#,
            options: []
        )
    }()

    static func processEmbeds(_ markdown: String, vaultRoot: URL?, imageExtensions: Set<String>) -> String {
        let ns = markdown as NSString
        let range = NSRange(location: 0, length: ns.length)
        let matches = embedRegex.matches(in: markdown, options: [], range: range)
        guard !matches.isEmpty else { return markdown }

        var result = ""
        var cursor = 0
        for m in matches {
            let matchRange = m.range
            if matchRange.location > cursor {
                result += ns.substring(with: NSRange(location: cursor, length: matchRange.location - cursor))
            }
            let inner = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let ext = (inner as NSString).pathExtension.lowercased()

            if imageExtensions.contains(ext) {
                if let root = vaultRoot {
                    let fileURL = root.appending(path: inner)
                    let urlString = fileURL.absoluteString
                    result += "![\(inner)](\(urlString))"
                } else {
                    // vault root 없으면 그대로 보존
                    result += "![\(inner)](\(inner))"
                }
            } else {
                // 노트 임베드는 wiki link로 fallback
                let encoded = inner.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? inner
                result += "[\(inner)](yuminai-note://\(encoded))"
            }

            cursor = matchRange.location + matchRange.length
        }
        if cursor < ns.length {
            result += ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
        }
        return result
    }
}
