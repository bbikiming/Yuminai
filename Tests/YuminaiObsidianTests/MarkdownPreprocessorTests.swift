import Foundation
import Testing
@testable import YuminaiObsidian

@Suite("MarkdownPreprocessor — wiki links")
struct WikiLinkPreprocessorTests {
    @Test("[[Page]] → [Page](yuminai-note://Page)")
    func basicWikiLink() {
        let result = MarkdownPreprocessor.processWikiLinks("see [[MyPage]] here")
        #expect(result == "see [MyPage](yuminai-note://MyPage) here")
    }

    @Test("[[Page|Display]] → [Display](yuminai-note://Page)")
    func wikiLinkWithDisplay() {
        let result = MarkdownPreprocessor.processWikiLinks("[[MyPage|My Display]]")
        #expect(result == "[My Display](yuminai-note://MyPage)")
    }

    @Test("페이지 이름의 공백은 percent encoding")
    func pageNameWithSpace() {
        let result = MarkdownPreprocessor.processWikiLinks("[[Daily 2026-05-01]]")
        #expect(result.contains("yuminai-note://Daily%202026-05-01"))
    }

    @Test("여러 wiki link 동시 처리")
    func multipleWikiLinks() {
        let input = "[[A]] and [[B]] and [[C|see]]"
        let result = MarkdownPreprocessor.processWikiLinks(input)
        #expect(result.contains("[A](yuminai-note://A)"))
        #expect(result.contains("[B](yuminai-note://B)"))
        #expect(result.contains("[see](yuminai-note://C)"))
    }

    @Test("wiki link가 아닌 텍스트는 보존")
    func nonWikiLinkPreserved() {
        let input = "regular [link](https://example.com) and `code`"
        let result = MarkdownPreprocessor.processWikiLinks(input)
        #expect(result == input)
    }
}

@Suite("MarkdownPreprocessor — embeds")
struct EmbedPreprocessorTests {
    @Test("이미지 임베드 ![[image.png]] → ![image.png](file://...)")
    func imageEmbed() {
        let root = URL(fileURLWithPath: "/tmp/vault")
        let result = MarkdownPreprocessor.processEmbeds(
            "![[diagram.png]]",
            vaultRoot: root,
            imageExtensions: ["png"]
        )
        #expect(result.hasPrefix("![diagram.png]("))
        #expect(result.contains("file:///tmp/vault/diagram.png"))
    }

    @Test("이미지 확장자 다양 (jpg/jpeg/svg/webp)")
    func variousImageExtensions() {
        let root = URL(fileURLWithPath: "/tmp/vault")
        let exts: Set<String> = ["png", "jpg", "jpeg", "gif", "svg", "webp", "pdf"]
        for ext in exts {
            let result = MarkdownPreprocessor.processEmbeds(
                "![[file.\(ext)]]",
                vaultRoot: root,
                imageExtensions: exts
            )
            #expect(result.hasPrefix("!["), "ext \(ext) failed: \(result)")
        }
    }

    @Test("노트 임베드 ![[Note]] (확장자 없음) → wiki link로 fallback")
    func noteEmbedFallback() {
        let root = URL(fileURLWithPath: "/tmp/vault")
        let result = MarkdownPreprocessor.processEmbeds(
            "![[MyNote]]",
            vaultRoot: root,
            imageExtensions: ["png", "jpg"]
        )
        #expect(result.contains("yuminai-note://MyNote"))
        // ![ prefix 아님 (이미지 아님)
        #expect(result.hasPrefix("[MyNote]"))
    }

    @Test("vaultRoot nil이면 원본 path 보존")
    func noVaultRoot() {
        let result = MarkdownPreprocessor.processEmbeds(
            "![[diagram.png]]",
            vaultRoot: nil,
            imageExtensions: ["png"]
        )
        #expect(result == "![diagram.png](diagram.png)")
    }
}

@Suite("MarkdownPreprocessor — full process")
struct FullProcessTests {
    @Test("wiki link + image embed 동시 처리")
    func combined() {
        let root = URL(fileURLWithPath: "/tmp/vault")
        let input = "Reference [[Other Note]] and ![[image.png]] here"
        let result = MarkdownPreprocessor.process(input, vaultRoot: root)
        #expect(result.contains("[Other Note](yuminai-note://Other%20Note)"))
        #expect(result.contains("file:///tmp/vault/image.png"))
    }
}
