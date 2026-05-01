import Foundation
import Testing
@testable import YuminaiCore

@Suite("FuzzyFileFilter — Cmd+P 검색")
struct FuzzyFileFilterTests {
    private func candidates(_ pairs: [(String, String)]) -> [FuzzyFileFilter.Candidate] {
        pairs.map { FuzzyFileFilter.Candidate(path: $0.0, name: $0.1) }
    }

    @Test("빈 query는 전체 + path 알파벳 정렬")
    func emptyQueryReturnsAll() {
        let cs = candidates([
            ("z/a.swift", "a.swift"),
            ("a/b.swift", "b.swift"),
            ("m/c.swift", "c.swift")
        ])
        let result = FuzzyFileFilter.filter(query: "", candidates: cs)
        #expect(result.count == 3)
        #expect(result.map(\.path) == ["a/b.swift", "m/c.swift", "z/a.swift"])
        #expect(result.allSatisfy { $0.score == 0 })
    }

    @Test("공백만 query는 빈 query처럼 동작")
    func whitespaceQueryActsAsEmpty() {
        let cs = candidates([("a.swift", "a.swift")])
        let result = FuzzyFileFilter.filter(query: "   ", candidates: cs)
        #expect(result.count == 1)
    }

    @Test("prefix match는 contains보다 더 높은 점수")
    func prefixBeatsContains() {
        let cs = candidates([
            ("a/foo.swift", "foo.swift"),       // prefix
            ("a/zfoo.swift", "zfoo.swift")      // contains
        ])
        let result = FuzzyFileFilter.filter(query: "foo", candidates: cs)
        #expect(result.count == 2)
        #expect(result[0].name == "foo.swift", "prefix가 먼저 와야 함")
    }

    @Test("name match는 path-only match보다 더 높은 점수")
    func nameBeatsPath() {
        let cs = candidates([
            ("auth/Service.swift", "Service.swift"),   // path contains
            ("x/AuthHelper.swift", "AuthHelper.swift") // name contains
        ])
        let result = FuzzyFileFilter.filter(query: "auth", candidates: cs)
        #expect(result.count == 2)
        #expect(result[0].name == "AuthHelper.swift")
    }

    @Test("매치 안 되는 항목은 결과에서 제외")
    func nonMatchExcluded() {
        let cs = candidates([
            ("a.swift", "a.swift"),
            ("b.swift", "b.swift"),
            ("foo.swift", "foo.swift")
        ])
        let result = FuzzyFileFilter.filter(query: "xyz", candidates: cs)
        #expect(result.isEmpty)
    }

    @Test("대소문자 무시")
    func caseInsensitive() {
        let cs = candidates([("a/Foo.SWIFT", "Foo.SWIFT")])
        let result = FuzzyFileFilter.filter(query: "foo", candidates: cs)
        #expect(result.count == 1)
        #expect(result[0].score >= 100)
    }

    @Test("짧은 이름은 가산점 — 같은 prefix면 짧은 이름이 위로")
    func shortNameBonus() {
        let cs = candidates([
            ("a/foo.swift", "foo.swift"),                                   // 9자
            ("a/foobar_supersuperlong.swift", "foobar_supersuperlong.swift") // 28자
        ])
        let result = FuzzyFileFilter.filter(query: "foo", candidates: cs)
        #expect(result[0].name == "foo.swift")
    }

    @Test("flatten은 폴더 재귀 + binary 제외")
    func flattenSkipsBinary() {
        let tree: [FileNode] = [
            .folder(name: "src", path: "src", children: [
                .file(name: "main.swift", path: "src/main.swift", ext: "swift", size: 100, isBinary: false),
                .file(name: "logo.png", path: "src/logo.png", ext: "png", size: 5000, isBinary: true),
                .folder(name: "deep", path: "src/deep", children: [
                    .file(name: "x.ts", path: "src/deep/x.ts", ext: "ts", size: 50, isBinary: false)
                ])
            ]),
            .file(name: "README.md", path: "README.md", ext: "md", size: 200, isBinary: false)
        ]
        let result = FuzzyFileFilter.flatten(tree)
        let names = Set(result.map(\.name))
        #expect(names == ["main.swift", "x.ts", "README.md"])
    }

    @Test("flatten on empty tree → empty array")
    func flattenEmpty() {
        #expect(FuzzyFileFilter.flatten([]).isEmpty)
    }

    @Test("정렬 안정성 — 같은 점수는 입력 순서 무관 (sort by score desc)")
    func ordersByScoreDescending() {
        let cs = candidates([
            ("z/a.swift", "a.swift"),
            ("a/a.swift", "a.swift")
        ])
        let result = FuzzyFileFilter.filter(query: "a", candidates: cs)
        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.score == result[0].score })
    }
}
