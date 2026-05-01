import Foundation
import Testing
@testable import YuminaiCore

@Suite("GitRunner — porcelain parsing")
struct GitRunnerPorcelainTests {
    @Test("단일 modified 파일")
    func singleModified() {
        let raw = " M Sources/Foo.swift\u{0}"
        let result = GitRunner.parsePorcelain(raw)
        #expect(result.count == 1)
        #expect(result[0].path == "Sources/Foo.swift")
        #expect(result[0].status == .modified)
    }

    @Test("untracked 파일 ?? 인식")
    func untracked() {
        let raw = "?? new_file.txt\u{0}"
        let result = GitRunner.parsePorcelain(raw)
        #expect(result.count == 1)
        #expect(result[0].status == .untracked)
        #expect(result[0].path == "new_file.txt")
    }

    @Test("여러 파일 NUL-separated")
    func multipleFiles() {
        let raw = " M a.swift\u{0}A  b.swift\u{0} D c.swift\u{0}"
        let result = GitRunner.parsePorcelain(raw)
        #expect(result.count == 3)
        #expect(result.map(\.status) == [.modified, .added, .deleted])
    }

    @Test("renamed는 다음 entry가 old-path이므로 skip")
    func renamedSkipsOldPath() {
        let raw = "R  new.swift\u{0}old.swift\u{0} M unrelated.swift\u{0}"
        let result = GitRunner.parsePorcelain(raw)
        #expect(result.count == 2)
        #expect(result[0].status == .renamed)
        #expect(result[0].path == "new.swift")
        #expect(result[1].path == "unrelated.swift")
    }

    @Test("빈 입력은 빈 결과")
    func empty() {
        #expect(GitRunner.parsePorcelain("").isEmpty)
    }

    @Test("ChangedFile.Status 한글 라벨")
    func koreanLabels() {
        #expect(ChangedFile.Status.modified.label == "수정")
        #expect(ChangedFile.Status.added.label == "추가")
        #expect(ChangedFile.Status.deleted.label == "삭제")
        #expect(ChangedFile.Status.untracked.label == "새 파일")
    }
}

@Suite("GitRunner — mock runner")
struct GitRunnerMockTests {
    @Test("mock runner로 changedFiles 호출 시 git status 인자 전달")
    func changedFilesCallsStatus() async throws {
        actor CallRecorder {
            var calls: [(URL, [String])] = []
            func record(_ url: URL, _ args: [String]) { calls.append((url, args)) }
        }
        let recorder = CallRecorder()

        let runner = GitRunner(
            gitPath: URL(fileURLWithPath: "/usr/bin/git"),
            workspaceURL: URL(fileURLWithPath: "/tmp/test"),
            runner: { url, args in
                await recorder.record(url, args)
                return GitRunner.ProcessResult(
                    exitCode: 0,
                    stdout: " M foo.swift\u{0}",
                    stderr: ""
                )
            }
        )

        // FileManager check 회피 — gitPath가 실제 존재해야 통과
        // /usr/bin/git가 없는 환경 대비 — skip if not exists
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/git") else { return }

        let files = try await runner.changedFiles()
        #expect(files.count == 1)
        #expect(files[0].path == "foo.swift")

        let calls = await recorder.calls
        #expect(calls.count == 1)
        #expect(calls[0].1.contains("status"))
        #expect(calls[0].1.contains("--porcelain=v1"))
    }
}
