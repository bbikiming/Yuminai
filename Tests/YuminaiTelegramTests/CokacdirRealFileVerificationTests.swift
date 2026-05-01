import Foundation
import Testing
@testable import YuminaiTelegram

/// 실제 ~/.cokacdir/workspace/bot_settings.json을 파싱해 import 가능 여부만 검증.
/// 토큰은 print하지 않고 display_name + chat 후보 수만 노출.
///
/// 파일이 없으면 skip — CI에서 안 깨짐.
@Suite("CokacdirImporter — real file (skip if missing)")
struct CokacdirRealFileVerificationTests {
    @Test("실제 bot_settings.json 파싱 가능 + 봇 메타만 출력 (토큰 X)")
    func parsesRealFile() async throws {
        let home = NSString(string: "~").expandingTildeInPath
        let candidates = [
            "\(home)/.cokacdir/bot_settings.json",
            "\(home)/.cokacdir/workspace/bot_settings.json"
        ]
        let path = candidates.first(where: FileManager.default.fileExists(atPath:)) ?? candidates[0]
        guard FileManager.default.fileExists(atPath: path) else {
            print("⊘ skip — \(path) 미존재")
            return
        }

        let importer = CokacdirImporter(botSettingsPath: path)
        let bots = try await importer.loadBots()

        print("✓ \(bots.count)개 봇 import 가능:")
        for bot in bots {
            let handle = bot.username.isEmpty ? "(no handle)" : "@\(bot.username)"
            let chatHint = bot.suggestedChatIds.isEmpty
                ? "no chat candidates"
                : "\(bot.suggestedChatIds.count) chat 후보"
            print("  · \(bot.displayName) \(handle) — owner=\(bot.ownerUserId) — \(chatHint)")
        }

        #expect(bots.count > 0)
        for bot in bots {
            #expect(!bot.token.isEmpty, "토큰이 비어있음: \(bot.displayName)")
            #expect(bot.ownerUserId > 0, "owner_user_id 누락: \(bot.displayName)")
        }
    }
}
