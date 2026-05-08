import Foundation
import Testing
@testable import YuminaiUI

@MainActor
@Suite("CodeViewer.languageHint — 확장자 → Highlight.js id")
struct CodeViewerLanguageHintTests {
    @Test("주요 언어 확장자 매핑")
    func mainLanguages() {
        #expect(CodeViewer.languageHint(for: "swift") == "swift")
        #expect(CodeViewer.languageHint(for: "ts") == "typescript")
        #expect(CodeViewer.languageHint(for: "tsx") == "typescript")
        #expect(CodeViewer.languageHint(for: "js") == "javascript")
        #expect(CodeViewer.languageHint(for: "jsx") == "javascript")
        #expect(CodeViewer.languageHint(for: "py") == "python")
        #expect(CodeViewer.languageHint(for: "rs") == "rust")
        #expect(CodeViewer.languageHint(for: "go") == "go")
    }

    @Test("대소문자 무시")
    func caseInsensitive() {
        #expect(CodeViewer.languageHint(for: "SWIFT") == "swift")
        #expect(CodeViewer.languageHint(for: "Py") == "python")
        #expect(CodeViewer.languageHint(for: "TSX") == "typescript")
    }

    @Test("C/C++ family 모두 매핑")
    func cppFamily() {
        #expect(CodeViewer.languageHint(for: "c") == "c")
        #expect(CodeViewer.languageHint(for: "h") == "c")
        #expect(CodeViewer.languageHint(for: "cpp") == "cpp")
        #expect(CodeViewer.languageHint(for: "hpp") == "cpp")
        #expect(CodeViewer.languageHint(for: "cc") == "cpp")
        #expect(CodeViewer.languageHint(for: "cxx") == "cpp")
    }

    @Test("config 파일 (toml→ini, yaml, json)")
    func configFormats() {
        #expect(CodeViewer.languageHint(for: "toml") == "ini")
        #expect(CodeViewer.languageHint(for: "yaml") == "yaml")
        #expect(CodeViewer.languageHint(for: "yml") == "yaml")
        #expect(CodeViewer.languageHint(for: "json") == "json")
    }

    @Test("shell variants (sh/bash/zsh) → bash")
    func shellAlias() {
        #expect(CodeViewer.languageHint(for: "sh") == "bash")
        #expect(CodeViewer.languageHint(for: "bash") == "bash")
        #expect(CodeViewer.languageHint(for: "zsh") == "bash")
    }

    @Test("markdown variants (md, markdown)")
    func markdownAlias() {
        #expect(CodeViewer.languageHint(for: "md") == "markdown")
        #expect(CodeViewer.languageHint(for: "markdown") == "markdown")
    }

    @Test("plist는 xml hint로 처리 (Apple plist는 XML)")
    func plistIsXml() {
        #expect(CodeViewer.languageHint(for: "plist") == "xml")
        #expect(CodeViewer.languageHint(for: "xml") == "xml")
    }

    @Test("미지원 확장자는 nil")
    func unsupportedReturnsNil() {
        #expect(CodeViewer.languageHint(for: "unknownext") == nil)
        #expect(CodeViewer.languageHint(for: "") == nil)
        #expect(CodeViewer.languageHint(for: "weirdo") == nil)
    }

    @Test("less common 함수형/시스템 언어들도 매핑")
    func functionalLanguages() {
        #expect(CodeViewer.languageHint(for: "hs") == "haskell")
        #expect(CodeViewer.languageHint(for: "ml") == "ocaml")
        #expect(CodeViewer.languageHint(for: "ex") == "elixir")
        #expect(CodeViewer.languageHint(for: "exs") == "elixir")
        #expect(CodeViewer.languageHint(for: "erl") == "erlang")
        #expect(CodeViewer.languageHint(for: "clj") == "clojure")
        #expect(CodeViewer.languageHint(for: "cljs") == "clojure")
    }

    @Test("frontend 컴포넌트 형식 (vue/svelte)")
    func frontendComponents() {
        #expect(CodeViewer.languageHint(for: "vue") == "vue")
        #expect(CodeViewer.languageHint(for: "svelte") == "svelte")
    }
}
