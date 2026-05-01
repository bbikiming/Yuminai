import Foundation
import Testing
@testable import YuminaiTelegram

@Suite("CokacdirImporter")
struct CokacdirImporterTests {
    @Test("두 봇이 있는 bot_settings.json 파싱")
    func parsesTwoBots() throws {
        let json = #"""
        {
          "hash_a": {
            "display_name": "스튜디오 코덱스",
            "username": "yuseok_co_m_bot",
            "token": "11111:AAAAA",
            "owner_user_id": 6149432260,
            "last_sessions": {
              "-4965668271": "/path/a",
              "6149432260": "/path/me"
            }
          },
          "hash_b": {
            "display_name": "스튜디오 클로드",
            "username": "yuseok_cl_s_bot",
            "token": "22222:BBBBB",
            "owner_user_id": 6149432260,
            "last_sessions": {
              "6149432260": "/path/me-claude"
            }
          }
        }
        """#
        let bots = try CokacdirImporter.parse(data: Data(json.utf8))
        #expect(bots.count == 2)

        let claude = bots.first { $0.displayName == "스튜디오 클로드" }
        #expect(claude != nil)
        #expect(claude?.token == "22222:BBBBB")
        #expect(claude?.username == "yuseok_cl_s_bot")
        #expect(claude?.handle == "@yuseok_cl_s_bot")
        #expect(claude?.ownerUserId == 6149432260)
        #expect(claude?.suggestedChatIds == [6149432260])
    }

    @Test("display_name 알파벳순 정렬")
    func sortedAlphabetically() throws {
        let json = #"""
        {
          "h1": {"display_name": "Zebra", "token": "z"},
          "h2": {"display_name": "Alpha", "token": "a"},
          "h3": {"display_name": "Mango", "token": "m"}
        }
        """#
        let bots = try CokacdirImporter.parse(data: Data(json.utf8))
        let names = bots.map(\.displayName)
        #expect(names == ["Alpha", "Mango", "Zebra"])
    }

    @Test("token이 없으면 봇은 무시")
    func skipsBotsWithoutToken() throws {
        let json = #"""
        {
          "h1": {"display_name": "No Token"},
          "h2": {"display_name": "Has Token", "token": "abc"}
        }
        """#
        let bots = try CokacdirImporter.parse(data: Data(json.utf8))
        #expect(bots.count == 1)
        #expect(bots[0].displayName == "Has Token")
    }

    @Test("display_name 없으면 hash 앞 8자로 fallback")
    func defaultDisplayName() throws {
        let json = #"""
        {
          "abcdef1234567890": {"token": "x"}
        }
        """#
        let bots = try CokacdirImporter.parse(data: Data(json.utf8))
        #expect(bots.count == 1)
        #expect(bots[0].displayName == "Bot abcdef12")
    }

    @Test("suggestedChatIds는 abs 작은 순 (owner positive 우선)")
    func chatIdsSortedByAbsoluteValue() throws {
        let json = #"""
        {
          "h1": {
            "display_name": "X",
            "token": "x",
            "last_sessions": {
              "-4965668271": "p",
              "100": "q",
              "-50": "r"
            }
          }
        }
        """#
        let bots = try CokacdirImporter.parse(data: Data(json.utf8))
        #expect(bots[0].suggestedChatIds == [-50, 100, -4965668271])
    }

    @Test("invalid JSON은 invalidJSON throw")
    func invalidJsonThrows() throws {
        #expect(throws: CokacdirImportError.self) {
            _ = try CokacdirImporter.parse(data: Data("not json".utf8))
        }
    }

    @Test("loadBots — 파일 없으면 notFound")
    func missingFileThrows() async {
        let importer = CokacdirImporter(botSettingsPath: "/nonexistent/cokacdir/bot_settings.json")
        await #expect(throws: CokacdirImportError.self) {
            _ = try await importer.loadBots()
        }
    }

    @Test("loadBots — 실제 파일 read 후 parse")
    func endToEndLoad() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appending(path: "cokacdir-importer-tests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: temp) }

        let json = #"""
        {
          "hX": {
            "display_name": "Test Bot",
            "username": "test_bot",
            "token": "999:XYZ",
            "owner_user_id": 42,
            "last_sessions": {"42": "/path"}
          }
        }
        """#
        try Data(json.utf8).write(to: temp)

        let importer = CokacdirImporter(botSettingsPath: temp.path)
        let bots = try await importer.loadBots()
        #expect(bots.count == 1)
        #expect(bots[0].token == "999:XYZ")
    }
}
