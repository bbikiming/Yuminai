import Foundation
import Testing
@testable import YuminaiTelegram

@Suite("CokacdirChatInspector — chat label")
struct CokacdirChatInspectorTests {
    @Test("positive id == ownerUserId면 .directWithOwner + 친화 title")
    func ownerDirectChat() async throws {
        let temp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: temp) }

        let inspector = CokacdirChatInspector(groupChatDir: temp.path)
        let label = await inspector.label(for: 12345, ownerUserId: 12345)
        #expect(label.kind == .directWithOwner)
        #expect(label.title == "내 1:1 채팅")
    }

    @Test("negative id면 .group")
    func negativeIdIsGroup() async throws {
        let temp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: temp) }

        let inspector = CokacdirChatInspector(groupChatDir: temp.path)
        let label = await inspector.label(for: -100, ownerUserId: 12345)
        #expect(label.kind == .group)
    }

    @Test("group_chat jsonl이 있으면 봇 + 사람 이름 추출")
    func extractsBotsAndHumans() async throws {
        let temp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: temp) }

        let chatId: Int64 = -999
        let logPath = temp.appending(path: "\(chatId).jsonl")
        let lines = [
            #"{"bot":"a_bot","bot_display_name":"Bot Alpha","role":"system"}"#,
            #"{"bot":"a_bot","bot_display_name":"Bot Alpha","role":"user","from":"홍길동(42)"}"#,
            #"{"bot":"b_bot","bot_display_name":"Bot Beta","role":"user","from":"bot:a_bot"}"#
        ]
        try lines.joined(separator: "\n").write(to: logPath, atomically: true, encoding: .utf8)

        let inspector = CokacdirChatInspector(groupChatDir: temp.path)
        let label = await inspector.label(for: chatId, ownerUserId: 99)

        #expect(label.kind == .group)
        // 봇 2개 + 사람 1명 (bot:a_bot은 bot prefix이므로 제외)
        #expect(label.participantNames.contains("🤖 Bot Alpha"))
        #expect(label.participantNames.contains("🤖 Bot Beta"))
        #expect(label.participantNames.contains("홍길동(42)"))
        #expect(!label.participantNames.contains("bot:a_bot"))
        // title에 봇/사람 일부 포함
        #expect(label.title.hasPrefix("그룹 — "))
    }

    @Test("로그 파일이 없으면 빈 participants + 기본 title")
    func missingLogReturnsBasicLabel() async throws {
        let temp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: temp) }

        let inspector = CokacdirChatInspector(groupChatDir: temp.path)
        let label = await inspector.label(for: -777, ownerUserId: 99)
        #expect(label.kind == .group)
        #expect(label.participantNames.isEmpty)
        #expect(label.title == "그룹 채팅")
    }

    @Test("extractParticipants는 limit 내에서 중복 제거 + 순서 유지")
    func extractDedupesAndPreservesOrder() throws {
        let temp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: temp) }

        let logPath = temp.appending(path: "test.jsonl")
        let lines = (0..<10).map { _ in
            #"{"bot":"a","bot_display_name":"Same Bot","from":"홍길동(1)"}"#
        }
        try lines.joined(separator: "\n").write(to: logPath, atomically: true, encoding: .utf8)

        let result = CokacdirChatInspector.extractParticipants(from: logPath.path, limit: 100)
        #expect(result.count == 2)  // 중복 제거 — 1봇 + 1사람
        #expect(result[0] == "🤖 Same Bot")
        #expect(result[1] == "홍길동(1)")
    }

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "cokacdir-inspector-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
