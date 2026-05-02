import Foundation
import Testing
@testable import YuminaiCore

@Suite("ChatBindingAuditLog (ADR-061 Phase 4)")
struct ChatBindingAuditLogTests {
    private func makeTempLog() -> (ChatBindingAuditLog, URL) {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("yuminai-binding-test-\(UUID().uuidString)", isDirectory: true)
        let log = ChatBindingAuditLog(directoryURL: temp)
        return (log, temp)
    }

    @Test("record + recent")
    func recordAndRecent() async {
        let (log, dir) = makeTempLog()
        defer { try? FileManager.default.removeItem(at: dir) }
        let entry = ChatBindingAuditEntry(
            chatId: 12345,
            userId: 67890,
            action: .bind,
            workspaceId: UUID(),
            workspaceName: "TestWS"
        )
        await log.record(entry)
        let recent = await log.recent()
        #expect(recent.count == 1)
        #expect(recent.first?.workspaceName == "TestWS")
    }

    @Test("disk persist + reload")
    func persistReload() async {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("yuminai-binding-persist-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        // 첫 instance에 record
        let log1 = ChatBindingAuditLog(directoryURL: temp)
        let entry = ChatBindingAuditEntry(
            chatId: 100,
            userId: 200,
            action: .bind,
            workspaceId: UUID(),
            workspaceName: "ReloadTest"
        )
        await log1.record(entry)
        // 새 instance가 disk에서 load
        let log2 = ChatBindingAuditLog(directoryURL: temp)
        let recent = await log2.recent()
        #expect(recent.count == 1)
        #expect(recent.first?.chatId == 100)
    }

    @Test("memory cap 적용")
    func memoryCap() async {
        let (log, dir) = makeTempLog()
        defer { try? FileManager.default.removeItem(at: dir) }
        // memoryCap (500) 보다 많이 추가
        for i in 0..<600 {
            let e = ChatBindingAuditEntry(
                chatId: Int64(i),
                userId: 1,
                action: .bind,
                workspaceId: nil,
                workspaceName: "ws\(i)"
            )
            await log.record(e)
        }
        let snap = await log.snapshot()
        #expect(snap.count <= ChatBindingAuditLog.memoryCap)
    }

    @Test("Action enum 3개 case")
    func actionCases() {
        let cases: [ChatBindingAuditEntry.Action] = [.bind, .unbind, .rebind]
        #expect(cases.count == 3)
    }
}

@Suite("RoutingLearningStore.performAutoUnmute (ADR-061 Phase 3)")
struct AutoUnmuteTests {
    private func makeStore() -> RoutingLearningStore {
        let suite = "yuminai-unmute-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return RoutingLearningStore(defaults: defaults)
    }

    @Test("최근 mute는 unmute 안 됨")
    func recentMutePreserved() async {
        let store = makeStore()
        await store.setMuted("recent", muted: true)
        let unmuted = await store.performAutoUnmute()
        #expect(unmuted.isEmpty)
        #expect(await store.isMuted("recent"))
    }

    @Test("performAutoUnmute는 빈 array 반환 가능 (mute 없음)")
    func emptyMutes() async {
        let store = makeStore()
        let unmuted = await store.performAutoUnmute()
        #expect(unmuted.isEmpty)
    }
}
