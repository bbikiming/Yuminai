import Foundation
import Testing
import YuminaiCore

@Suite("MentionParser")
struct MentionParserTests {
    let parser = MentionParser()

    @Test("@codex로 시작하면 target=@codex + body=나머지")
    func basicMention() {
        let result = parser.parse("@codex 이 함수 검토해줘")
        #expect(result?.target == "@codex")
        #expect(result?.body == "이 함수 검토해줘")
    }

    @Test("앞 공백 trim")
    func leadingWhitespace() {
        let result = parser.parse("   @claude 안녕  ")
        #expect(result?.target == "@claude")
        #expect(result?.body == "안녕")
    }

    @Test("줄바꿈도 separator 인식")
    func newlineSeparator() {
        let result = parser.parse("@codex\n첫째줄\n둘째줄")
        #expect(result?.target == "@codex")
        #expect(result?.body == "첫째줄\n둘째줄")
    }

    @Test("@ 시작 안 하면 nil")
    func noMentionPrefix() {
        #expect(parser.parse("일반 텍스트") == nil)
        #expect(parser.parse("@은 중간에 — 무시") != nil)  // 시작이면 인식
    }

    @Test("@ 한 글자만은 nil")
    func bareAtSign() {
        #expect(parser.parse("@ 본문") == nil)
        #expect(parser.parse("@") == nil)
    }

    @Test("mention만 있고 body 없으면 nil")
    func mentionOnlyNoBody() {
        #expect(parser.parse("@codex") == nil)
        #expect(parser.parse("@codex   ") == nil)
    }

    @Test("body가 multi-line이어도 보존")
    func multilineBody() {
        let text = "@codex\n```swift\nlet x = 1\n```\n검토해줘"
        let result = parser.parse(text)
        #expect(result?.target == "@codex")
        #expect(result?.body.contains("```swift") == true)
        #expect(result?.body.contains("검토해줘") == true)
    }

    @Test("normalizedTarget은 @ 제거 + lowercase")
    func normalize() {
        #expect(MentionParser.normalizedTarget("@CODEX") == "codex")
        #expect(MentionParser.normalizedTarget("@Claude") == "claude")
        #expect(MentionParser.normalizedTarget("codex") == "codex")  // @ 없어도 OK
    }
}
