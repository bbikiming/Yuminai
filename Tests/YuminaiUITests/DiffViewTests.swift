import Foundation
import Testing
@testable import YuminaiUI

@Suite("DiffReviewView — line kind")
struct DiffLineKindTests {
    @Test("+로 시작하면 added")
    func added() {
        #expect(DiffReviewView.lineKind("+    let x = 1") == .added)
    }

    @Test("-로 시작하면 removed")
    func removed() {
        #expect(DiffReviewView.lineKind("-    let x = 0") == .removed)
    }

    @Test("@@로 시작하면 hunkHeader")
    func hunkHeader() {
        #expect(DiffReviewView.lineKind("@@ -1,3 +1,4 @@") == .hunkHeader)
    }

    @Test("diff --git 메타 라인")
    func diffMeta() {
        #expect(DiffReviewView.lineKind("diff --git a/foo.swift b/foo.swift") == .hunkHeader)
        #expect(DiffReviewView.lineKind("--- a/foo.swift") == .hunkHeader)
        #expect(DiffReviewView.lineKind("+++ b/foo.swift") == .hunkHeader)
        #expect(DiffReviewView.lineKind("index abc..def 100644") == .hunkHeader)
    }

    @Test("일반 컨텍스트 라인")
    func contextLine() {
        #expect(DiffReviewView.lineKind("    let unchanged = true") == .context)
    }

    @Test("빈 라인은 context")
    func emptyLine() {
        #expect(DiffReviewView.lineKind("") == .context)
    }
}

@Suite("DiffReviewView — extractHunks")
struct DiffExtractHunksTests {
    @Test("단일 파일 diff 추출")
    func singleFile() {
        let diff = """
        diff --git a/foo.swift b/foo.swift
        index abc..def 100644
        --- a/foo.swift
        +++ b/foo.swift
        @@ -1,3 +1,4 @@
         line1
        -line2 old
        +line2 new
        +line3 added
         line4
        """
        let hunks = DiffReviewView.extractHunks(from: diff, path: "foo.swift")
        #expect(hunks.count > 0)
        #expect(hunks.contains(where: { $0.contains("@@ -1,3 +1,4 @@") }))
        #expect(hunks.contains(where: { $0 == "+line2 new" }))
    }

    @Test("여러 파일 중 특정 파일만 추출")
    func multipleFiles() {
        let diff = """
        diff --git a/a.swift b/a.swift
        index 11..22 100644
        --- a/a.swift
        +++ b/a.swift
        @@ -1 +1 @@
        -aa
        +AA
        diff --git a/b.swift b/b.swift
        index 33..44 100644
        --- a/b.swift
        +++ b/b.swift
        @@ -1 +1 @@
        -bb
        +BB
        """
        let hunks = DiffReviewView.extractHunks(from: diff, path: "b.swift")
        // a.swift hunks 제외, b.swift만
        #expect(hunks.contains(where: { $0.contains("b.swift") }))
        #expect(hunks.contains(where: { $0 == "+BB" }))
        #expect(!hunks.contains(where: { $0 == "+AA" }))
    }

    @Test("매칭 없는 path는 빈 결과")
    func noMatch() {
        let diff = "diff --git a/x.swift b/x.swift\n--- a/x.swift\n+++ b/x.swift\n@@ -1 +1 @@\n+x"
        let hunks = DiffReviewView.extractHunks(from: diff, path: "missing.swift")
        #expect(hunks.isEmpty)
    }

    @Test("빈 diff는 빈 결과")
    func emptyDiff() {
        #expect(DiffReviewView.extractHunks(from: "", path: "foo").isEmpty)
    }
}
