import Foundation
import Testing
@testable import YuminaiCore

@Suite("ConflictBlockParser (ADR-083 Phase 1)")
struct ConflictBlockParserTests {

    @Test("빈 content — 빈 result")
    func emptyContent() {
        let blocks = ConflictBlockParser.parse("")
        #expect(blocks.isEmpty)
    }

    @Test("conflict marker 없으면 빈 result")
    func noMarkers() {
        let content = """
        line 1
        line 2
        line 3
        """
        let blocks = ConflictBlockParser.parse(content)
        #expect(blocks.isEmpty)
    }

    @Test("단일 conflict block 파싱")
    func singleBlock() {
        let content = """
        before
        <<<<<<< HEAD
        ours line 1
        ours line 2
        =======
        theirs line 1
        >>>>>>> incoming
        after
        """
        let blocks = ConflictBlockParser.parse(content)
        #expect(blocks.count == 1)
        #expect(blocks[0].oursLines == ["ours line 1", "ours line 2"])
        #expect(blocks[0].theirsLines == ["theirs line 1"])
        #expect(blocks[0].startLine == 2)  // 1-based
    }

    @Test("다중 conflict block")
    func multipleBlocks() {
        let content = """
        <<<<<<< HEAD
        a
        =======
        b
        >>>>>>> incoming
        normal
        <<<<<<< HEAD
        x
        =======
        y
        z
        >>>>>>> incoming
        """
        let blocks = ConflictBlockParser.parse(content)
        #expect(blocks.count == 2)
        #expect(blocks[0].id == 0)
        #expect(blocks[1].id == 1)
        #expect(blocks[1].theirsLines == ["y", "z"])
    }

    @Test("malformed (시작만 있고 끝 없음) — 무시")
    func malformed() {
        let content = """
        <<<<<<< HEAD
        ours
        =======
        theirs
        """  // closing marker 없음
        let blocks = ConflictBlockParser.parse(content)
        #expect(blocks.isEmpty)
    }

    @Test("ours 빈 변경")
    func emptyOurs() {
        let content = """
        <<<<<<< HEAD
        =======
        theirs only
        >>>>>>> incoming
        """
        let blocks = ConflictBlockParser.parse(content)
        #expect(blocks.count == 1)
        #expect(blocks[0].oursLines.isEmpty)
        #expect(blocks[0].theirsLines == ["theirs only"])
    }
}

@Suite("ConflictResolution (ADR-083 Phase 1)")
struct ConflictResolutionTests {

    @Test("allCases — ours/theirs 2개")
    func allCases() {
        #expect(ConflictResolution.allCases.count == 2)
        #expect(ConflictResolution.allCases.contains(.ours))
        #expect(ConflictResolution.allCases.contains(.theirs))
    }

    @Test("displayName 한국어")
    func displayNames() {
        #expect(ConflictResolution.ours.displayName.contains("내 변경"))
        #expect(ConflictResolution.theirs.displayName.contains("받은 변경"))
    }

    @Test("Identifiable — id == rawValue")
    func identifiable() {
        for r in ConflictResolution.allCases {
            #expect(r.id == r.rawValue)
        }
    }
}

@Suite("Contributor + RepoInfo (ADR-083 Phase 4)")
struct RepoInsightsTests {

    @Test("Contributor Identifiable — id == login")
    func contributorIdentifiable() {
        let c = Contributor(login: "user1", contributions: 100, avatarURL: "")
        #expect(c.id == "user1")
    }

    @Test("RepoInfo Codable round trip")
    func repoInfoRoundTrip() throws {
        let info = RepoInfo(
            name: "yuminai",
            nameWithOwner: "user/yuminai",
            description: "test",
            stargazerCount: 10,
            forkCount: 2,
            openIssuesCount: 1,
            updatedAt: "2026-01-01",
            url: "https://github.com/user/yuminai"
        )
        let encoded = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(RepoInfo.self, from: encoded)
        #expect(decoded == info)
    }
}
