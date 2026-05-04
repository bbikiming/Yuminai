import Foundation
import Testing
@testable import YuminaiCore

/// **ADR-097** — TelegramArtifactStore 유닛 테스트.
@Suite("TelegramArtifactStore (ADR-097)")
struct TelegramArtifactStoreTests {

    // MARK: - store + fetch round-trip

    @Test("diff artifact store + fetch round-trip")
    func diffRoundTrip() async {
        let store = TelegramArtifactStore()
        let artifact = TelegramArtifactStore.Artifact.diff(
            content: "--- a/Foo.swift\n+++ b/Foo.swift\n+var x = 1",
            files: 1,
            added: 1,
            removed: 0,
            workspace: "MyProject"
        )
        let id = await store.store(artifact)
        let fetched = await store.fetch(id)
        #expect(fetched == artifact)
    }

    @Test("log artifact store + fetch round-trip")
    func logRoundTrip() async {
        let store = TelegramArtifactStore()
        let artifact = TelegramArtifactStore.Artifact.log(
            content: "Build complete. 0 errors.",
            title: "Build · Yuminai",
            elapsed: 42.5,
            success: true
        )
        let id = await store.store(artifact)
        let fetched = await store.fetch(id)
        #expect(fetched == artifact)
    }

    // MARK: - TTL 만료

    @Test("TTL 초과 시 fetch nil 반환")
    func ttlExpiry() async throws {
        // ttlSeconds = 0.01 (10ms) — 즉시 만료
        let store = TelegramArtifactStore(ttlSeconds: 0.01)
        let artifact = TelegramArtifactStore.Artifact.log(
            content: "log data",
            title: "Test",
            elapsed: 1.0,
            success: false
        )
        let id = await store.store(artifact)

        // 충분히 기다린 후 fetch
        try await Task.sleep(nanoseconds: 50_000_000)  // 50ms

        let fetched = await store.fetch(id)
        #expect(fetched == nil)
    }

    // MARK: - capacity 초과

    @Test("capacity 초과 시 oldest 삭제")
    func capacityEviction() async {
        let store = TelegramArtifactStore(capacity: 3)

        var ids: [UUID] = []
        for i in 0..<4 {
            let artifact = TelegramArtifactStore.Artifact.log(
                content: "log \(i)",
                title: "T\(i)",
                elapsed: Double(i),
                success: true
            )
            let id = await store.store(artifact)
            ids.append(id)
        }

        // 4번 삽입 → capacity 3 → 첫 번째 항목 evict
        let firstFetched = await store.fetch(ids[0])
        #expect(firstFetched == nil)

        // 나머지 3개는 존재
        let second = await store.fetch(ids[1])
        let third = await store.fetch(ids[2])
        let fourth = await store.fetch(ids[3])
        #expect(second != nil)
        #expect(third != nil)
        #expect(fourth != nil)

        let count = await store.count()
        #expect(count == 3)
    }

    // MARK: - gc() 동작

    @Test("gc() 만료 항목 정리")
    func gcCleansExpired() async throws {
        let store = TelegramArtifactStore(capacity: 50, ttlSeconds: 0.01)
        let artifact = TelegramArtifactStore.Artifact.diff(
            content: "diff content",
            files: 2,
            added: 5,
            removed: 3,
            workspace: nil
        )

        _ = await store.store(artifact)
        _ = await store.store(artifact)

        let beforeGC = await store.count()
        #expect(beforeGC == 2)

        try await Task.sleep(nanoseconds: 50_000_000)  // 50ms — TTL 만료

        await store.gc()

        let afterGC = await store.count()
        #expect(afterGC == 0)
    }

    // MARK: - 동시 store UUID 충돌 없음

    @Test("동시 store 다수 — UUID 충돌 없음")
    func concurrentStoreNoCollision() async {
        let store = TelegramArtifactStore(capacity: 200)

        // 100개 동시 저장
        await withTaskGroup(of: UUID.self) { group in
            for i in 0..<100 {
                group.addTask {
                    let artifact = TelegramArtifactStore.Artifact.log(
                        content: "concurrent \(i)",
                        title: "T\(i)",
                        elapsed: Double(i) * 0.1,
                        success: i % 2 == 0
                    )
                    return await store.store(artifact)
                }
            }
        }

        let count = await store.count()
        #expect(count == 100)
    }

    // MARK: - diff vs log enum case 구별

    @Test("diff vs log enum case 구별")
    func diffVsLogDistinction() async {
        let store = TelegramArtifactStore()

        let diffArtifact = TelegramArtifactStore.Artifact.diff(
            content: "diff",
            files: 1,
            added: 1,
            removed: 0,
            workspace: nil
        )
        let logArtifact = TelegramArtifactStore.Artifact.log(
            content: "log",
            title: "Build",
            elapsed: 5.0,
            success: true
        )

        let diffId = await store.store(diffArtifact)
        let logId = await store.store(logArtifact)

        let fetchedDiff = await store.fetch(diffId)
        let fetchedLog = await store.fetch(logId)

        if case .diff = fetchedDiff { } else {
            Issue.record("Expected diff case but got \(String(describing: fetchedDiff))")
        }
        if case .log = fetchedLog { } else {
            Issue.record("Expected log case but got \(String(describing: fetchedLog))")
        }
    }

    // MARK: - 존재하지 않는 UUID

    @Test("존재하지 않는 UUID fetch — nil 반환")
    func unknownUUIDReturnsNil() async {
        let store = TelegramArtifactStore()
        let randomId = UUID()
        let result = await store.fetch(randomId)
        #expect(result == nil)
    }

    // MARK: - workspace nil 보존

    @Test("diff workspace nil 보존")
    func diffWorkspaceNil() async {
        let store = TelegramArtifactStore()
        let artifact = TelegramArtifactStore.Artifact.diff(
            content: "content",
            files: 0,
            added: 0,
            removed: 0,
            workspace: nil
        )
        let id = await store.store(artifact)
        let fetched = await store.fetch(id)

        if case .diff(_, _, _, _, let ws) = fetched {
            #expect(ws == nil)
        } else {
            Issue.record("Expected diff case")
        }
    }
}
