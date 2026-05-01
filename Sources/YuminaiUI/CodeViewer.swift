import SwiftUI
import AppKit
import Highlightr

/// Syntax-highlighted code viewer (ADR-038 E1).
///
/// **참조**: Highlightr (Highlight.js wrap, 100+ 언어, MIT)
/// - 외부 의존성으로 추가 (lock-in 완화: CodeViewer가 Highlightr 직접 노출 X)
///
/// **단순화**:
/// - read-only viewer만 (editor는 raw TextEditor 유지 — editable highlight는 v1.0+)
/// - large file (>100KB) 자동 fallback to plain text (highlight 비용 회피)
/// - 워크스페이스 dark/light 자동 (NSAppearance 따라감)
public struct CodeViewer: View {
    public let code: String
    public let language: String?
    public let maxHighlightBytes: Int

    public init(
        code: String,
        language: String? = nil,
        maxHighlightBytes: Int = 100_000
    ) {
        self.code = code
        self.language = language
        self.maxHighlightBytes = maxHighlightBytes
    }

    public var body: some View {
        ScrollView([.horizontal, .vertical]) {
            content
                .padding(Theme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .background(Theme.Color.bg)
    }

    @ViewBuilder
    private var content: some View {
        if code.utf8.count > maxHighlightBytes {
            // Large file — plain text (highlight 비용 회피)
            Text(code)
                .font(Theme.Typography.mono)
                .foregroundStyle(Theme.Color.text)
        } else if let attr = Self.highlightedAttributedString(code: code, language: language) {
            Text(attr)
        } else {
            Text(code)
                .font(Theme.Typography.mono)
                .foregroundStyle(Theme.Color.text)
        }
    }

    /// 알려진 확장자 → Highlight.js 언어 식별자.
    public static func languageHint(for ext: String) -> String? {
        let lower = ext.lowercased()
        switch lower {
        case "swift": return "swift"
        case "ts", "tsx": return "typescript"
        case "js", "jsx", "mjs": return "javascript"
        case "py": return "python"
        case "rs": return "rust"
        case "go": return "go"
        case "java": return "java"
        case "kt", "kts": return "kotlin"
        case "rb": return "ruby"
        case "php": return "php"
        case "c", "h": return "c"
        case "cpp", "cc", "hpp", "hh", "cxx": return "cpp"
        case "cs": return "csharp"
        case "json": return "json"
        case "yml", "yaml": return "yaml"
        case "toml": return "ini"
        case "md", "markdown": return "markdown"
        case "html", "htm": return "html"
        case "css": return "css"
        case "scss", "sass": return "scss"
        case "sh", "bash", "zsh": return "bash"
        case "sql": return "sql"
        case "xml", "plist": return "xml"
        case "diff", "patch": return "diff"
        case "dockerfile": return "dockerfile"
        case "lua": return "lua"
        case "scala": return "scala"
        case "r": return "r"
        case "vue": return "vue"
        case "svelte": return "svelte"
        case "elm": return "elm"
        case "clj", "cljs": return "clojure"
        case "ex", "exs": return "elixir"
        case "erl": return "erlang"
        case "hs": return "haskell"
        case "ml", "mli": return "ocaml"
        case "fs", "fsi": return "fsharp"
        case "dart": return "dart"
        case "nim": return "nim"
        case "zig": return "zig"
        default: return nil
        }
    }

    // MARK: - Highlightr (lock-in 완화: 외부 노출 X)

    /// 한 번만 생성된 Highlightr 인스턴스 (스레드 안전 — 단일 사용처).
    private static let highlightr: Highlightr? = {
        let h = Highlightr()
        // Theme — 다크 친화 default. NSAppearance 따라가는 건 다음 단계
        h?.setTheme(to: "atom-one-dark")
        return h
    }()

    public static func highlightedAttributedString(code: String, language: String?) -> AttributedString? {
        guard let highlightr = highlightr else { return nil }
        let nsAttr: NSAttributedString?
        if let language, !language.isEmpty {
            nsAttr = highlightr.highlight(code, as: language)
        } else {
            nsAttr = highlightr.highlight(code)
        }
        guard let nsAttr else { return nil }
        // NSAttributedString → AttributedString
        return try? AttributedString(nsAttr, including: \.appKit)
    }
}
