import Foundation
import Testing
@testable import YuminaiCore

// MARK: - TelegramBotRegistry

@Suite("TelegramBotRegistry (ADR-086 Phase 3)")
struct TelegramBotRegistryTests {

    @Test("addBot — 새 봇 추가 성공")
    func addBot() async {
        let registry = TelegramBotRegistry()
        let config = TelegramBotConfig(
            displayName: "테스트 봇",
            username: "test_bot",
            keychainKey: "telegram.bot.test"
        )
        await registry.addBot(config)
        let bots = await registry.bots
        #expect(bots.count == 1)
        #expect(bots.first?.displayName == "테스트 봇")
    }

    @Test("addBot — 중복 ID 추가 무시")
    func duplicateBotIgnored() async {
        let registry = TelegramBotRegistry()
        let id = UUID()
        let bot1 = TelegramBotConfig(id: id, displayName: "봇1", username: "bot1", keychainKey: "k1")
        let bot2 = TelegramBotConfig(id: id, displayName: "봇2", username: "bot2", keychainKey: "k2")
        await registry.addBot(bot1)
        await registry.addBot(bot2)
        let bots = await registry.bots
        #expect(bots.count == 1)
        #expect(bots.first?.displayName == "봇1")
    }

    @Test("removeBot — 봇 제거 + binding cascade")
    func removeBotCascade() async {
        let registry = TelegramBotRegistry()
        let botId = UUID()
        let bot = TelegramBotConfig(id: botId, displayName: "봇", username: "bot", keychainKey: "k")
        await registry.addBot(bot)
        let binding = BotChatBinding(botId: botId, chatId: 123, activeWorkspaceId: nil)
        await registry.addBinding(binding)

        await registry.removeBot(id: botId)

        let bots = await registry.bots
        let bindings = await registry.bindings
        #expect(bots.isEmpty)
        #expect(bindings.isEmpty, "binding이 cascade delete 되어야 함")
    }

    @Test("addBinding — 같은 botId+chatId면 update")
    func addBindingUpdate() async {
        let registry = TelegramBotRegistry()
        let botId = UUID()
        let chatId: Int64 = 12345
        let wsId1 = UUID()
        let wsId2 = UUID()

        let b1 = BotChatBinding(botId: botId, chatId: chatId, activeWorkspaceId: wsId1)
        await registry.addBinding(b1)
        let b2 = BotChatBinding(botId: botId, chatId: chatId, activeWorkspaceId: wsId2)
        await registry.addBinding(b2)

        let all = await registry.bindings
        #expect(all.count == 1)
        #expect(all.first?.activeWorkspaceId == wsId2)
    }

    @Test("switchWorkspace — allowed list에 있으면 active 변경")
    func switchWorkspaceAllowed() async {
        let registry = TelegramBotRegistry()
        let botId = UUID()
        let chatId: Int64 = 100
        let ws1 = UUID()
        let ws2 = UUID()
        let binding = BotChatBinding(
            botId: botId,
            chatId: chatId,
            activeWorkspaceId: ws1,
            allowedWorkspaceIds: [ws1, ws2]
        )
        await registry.addBinding(binding)

        await registry.switchWorkspace(botId: botId, chatId: chatId, to: ws2)
        let updated = await registry.binding(botId: botId, chatId: chatId)
        #expect(updated?.activeWorkspaceId == ws2)
    }

    @Test("switchWorkspace — allowed list 비어있으면 모두 허용")
    func switchWorkspaceAllAllowed() async {
        let registry = TelegramBotRegistry()
        let botId = UUID()
        let chatId: Int64 = 100
        let ws1 = UUID()
        let wsNew = UUID()
        let binding = BotChatBinding(
            botId: botId,
            chatId: chatId,
            activeWorkspaceId: ws1,
            allowedWorkspaceIds: []  // 비어있음 = 모두 허용
        )
        await registry.addBinding(binding)
        await registry.switchWorkspace(botId: botId, chatId: chatId, to: wsNew)
        let updated = await registry.binding(botId: botId, chatId: chatId)
        #expect(updated?.activeWorkspaceId == wsNew)
    }

    @Test("switchWorkspace — allowed list에 없으면 무시")
    func switchWorkspaceDenied() async {
        let registry = TelegramBotRegistry()
        let botId = UUID()
        let chatId: Int64 = 100
        let ws1 = UUID()
        let ws2 = UUID()
        let wsForbidden = UUID()
        let binding = BotChatBinding(
            botId: botId,
            chatId: chatId,
            activeWorkspaceId: ws1,
            allowedWorkspaceIds: [ws1, ws2]
        )
        await registry.addBinding(binding)

        await registry.switchWorkspace(botId: botId, chatId: chatId, to: wsForbidden)
        let updated = await registry.binding(botId: botId, chatId: chatId)
        #expect(updated?.activeWorkspaceId == ws1, "허용되지 않은 workspace로는 변경 안 됨")
    }

    @Test("removeGroup — 그룹 안 봇들은 ungrouped로")
    func removeGroupReassignBots() async {
        let registry = TelegramBotRegistry()
        let groupId = UUID()
        let group = TelegramBotGroup(id: groupId, displayName: "팀A")
        await registry.addGroup(group)
        let bot = TelegramBotConfig(
            displayName: "봇1",
            username: "u1",
            keychainKey: "k1",
            groupId: groupId
        )
        await registry.addBot(bot)

        await registry.removeGroup(id: groupId)

        let bots = await registry.bots
        #expect(bots.first?.groupId == nil, "그룹 삭제 후 봇은 ungrouped여야 함")
    }

    @Test("effectiveResponseMode — 그룹 override 우선")
    func effectiveResponseMode() async {
        let registry = TelegramBotRegistry()
        let groupId = UUID()
        let botId = UUID()
        await registry.addGroup(TelegramBotGroup(
            id: groupId,
            displayName: "G",
            responseModeOverride: .minimal
        ))
        await registry.addBot(TelegramBotConfig(
            id: botId, displayName: "B", username: "b", keychainKey: "k", groupId: groupId
        ))
        let mode = await registry.effectiveResponseMode(botId: botId, globalDefault: .standard)
        #expect(mode == .minimal, "group override가 적용되어야 함")
    }
}

// MARK: - TelegramOfflineQueue

@Suite("TelegramOfflineQueue (ADR-086 Phase 2)")
struct TelegramOfflineQueueTests {

    @Test("enqueue + count")
    func enqueueCount() async {
        let queue = TelegramOfflineQueue()
        let msg = PendingTelegramMessage(botId: UUID(), chatId: 1, text: "hi")
        await queue.enqueue(msg)
        let count = await queue.count()
        #expect(count == 1)
    }

    @Test("maxQueueSize — 큐 가득 차면 oldest drop")
    func dropOldest() async {
        let queue = TelegramOfflineQueue(maxAttempts: 3, maxQueueSize: 3)
        let bot = UUID()
        for i in 0..<5 {
            await queue.enqueue(PendingTelegramMessage(botId: bot, chatId: 1, text: "msg\(i)"))
        }
        let all = await queue.all()
        #expect(all.count == 3)
        #expect(all.first?.text == "msg2", "oldest 2개 drop, msg2부터 남아야 함")
    }

    @Test("flush — 성공한 메시지는 제거")
    func flushSuccess() async {
        let queue = TelegramOfflineQueue()
        await queue.enqueue(PendingTelegramMessage(botId: UUID(), chatId: 1, text: "a"))
        await queue.enqueue(PendingTelegramMessage(botId: UUID(), chatId: 1, text: "b"))

        let result = await queue.flush { _ in true }
        #expect(result.sent == 2)
        #expect(result.dropped == 0)
        let remaining = await queue.count()
        #expect(remaining == 0)
    }

    @Test("flush — maxAttempts 도달 시 dropped")
    func flushDropped() async {
        let queue = TelegramOfflineQueue(maxAttempts: 2, maxQueueSize: 10)
        await queue.enqueue(PendingTelegramMessage(botId: UUID(), chatId: 1, text: "x"))
        // 2번 실패 → attempt가 2가 되면 drop
        _ = await queue.flush { _ in false }
        _ = await queue.flush { _ in false }
        let remaining = await queue.count()
        #expect(remaining == 0, "max attempts 도달했으니 큐에서 제거되어야 함")
    }

    @Test("clear — 모든 메시지 제거")
    func clear() async {
        let queue = TelegramOfflineQueue()
        for _ in 0..<5 {
            await queue.enqueue(PendingTelegramMessage(botId: UUID(), chatId: 1, text: "x"))
        }
        await queue.clear()
        let count = await queue.count()
        #expect(count == 0)
    }
}

// MARK: - RateLimitAlertConfig + Tracker

@Suite("RateLimitAlertTracker (ADR-086 Phase 2)")
struct RateLimitAlertTrackerTests {

    @Test("default config — 80% threshold / 1h cooldown")
    func defaultConfig() {
        let cfg = RateLimitAlertConfig()
        #expect(cfg.thresholdRatio == 0.8)
        #expect(cfg.notifyViaTelegram == true)
        #expect(cfg.cooldownSeconds == 3600)
    }

    @Test("shouldAlert — threshold 미만이면 false")
    func belowThreshold() async {
        let tracker = RateLimitAlertTracker(config: RateLimitAlertConfig())
        await tracker.report(usedToday: 3.0, dailyBudget: 5.0)  // 60% < 80%
        let should = await tracker.shouldAlert()
        #expect(!should)
    }

    @Test("shouldAlert — threshold 도달 시 true (첫 호출)")
    func aboveThreshold() async {
        let tracker = RateLimitAlertTracker(config: RateLimitAlertConfig())
        await tracker.report(usedToday: 4.5, dailyBudget: 5.0)  // 90%
        let should = await tracker.shouldAlert()
        #expect(should)
    }

    @Test("cooldown — 알림 후 cooldown 동안 false")
    func cooldown() async {
        let cfg = RateLimitAlertConfig(thresholdRatio: 0.5, notifyViaTelegram: true, cooldownSeconds: 100)
        let tracker = RateLimitAlertTracker(config: cfg)
        await tracker.report(usedToday: 4.0, dailyBudget: 5.0)
        let now = Date()
        let first = await tracker.shouldAlert(now: now)
        #expect(first)
        await tracker.markAlerted(now: now)
        // cooldown 안 지났음 (50초 후)
        let second = await tracker.shouldAlert(now: now.addingTimeInterval(50))
        #expect(!second)
        // cooldown 지난 후
        let third = await tracker.shouldAlert(now: now.addingTimeInterval(101))
        #expect(third)
    }

    @Test("notifyViaTelegram=false → 항상 false")
    func disabled() async {
        let cfg = RateLimitAlertConfig(thresholdRatio: 0.1, notifyViaTelegram: false)
        let tracker = RateLimitAlertTracker(config: cfg)
        await tracker.report(usedToday: 5.0, dailyBudget: 5.0)  // 100%
        let should = await tracker.shouldAlert()
        #expect(!should)
    }

    @Test("makeAlertMessage — 한국어 메시지 포함")
    func alertMessage() async {
        let tracker = RateLimitAlertTracker(config: RateLimitAlertConfig())
        await tracker.report(usedToday: 4.5, dailyBudget: 5.0)
        let msg = await tracker.makeAlertMessage()
        #expect(msg.contains("90%"))
        #expect(msg.contains("4.50"))
        #expect(msg.contains("5.00"))
        #expect(msg.contains("자정"))
    }
}

// MARK: - TelegramUpdateMode

@Suite("TelegramUpdateMode (ADR-086 Phase 5)")
struct TelegramUpdateModeTests {

    @Test("allCases — longPoll + webhook")
    func allCases() {
        let cases = TelegramUpdateMode.allCases
        #expect(cases.count == 2)
        #expect(cases.contains(.longPoll))
        #expect(cases.contains(.webhook))
    }

    @Test("displayName + hint 비어있지 않음")
    func displayProperties() {
        for mode in TelegramUpdateMode.allCases {
            #expect(!mode.displayName.isEmpty)
            #expect(!mode.hint.isEmpty)
        }
    }

    @Test("Codable round-trip")
    func codable() throws {
        let original = TelegramUpdateMode.webhook
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TelegramUpdateMode.self, from: encoded)
        #expect(decoded == .webhook)
    }
}

// MARK: - TelegramBotConfig Codable backward-compat

@Suite("TelegramBotConfig Codable")
struct TelegramBotConfigCodableTests {

    @Test("Round-trip — 모든 필드 보존")
    func roundTrip() throws {
        let original = TelegramBotConfig(
            displayName: "프로덕션 봇",
            username: "prod_bot",
            keychainKey: "telegram.prod",
            groupId: UUID(),
            allowedUserIds: [123, 456],
            enabled: true,
            iconName: "bolt.fill",
            colorName: "purple",
            notes: "핵심 운영"
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TelegramBotConfig.self, from: encoded)
        #expect(decoded.displayName == original.displayName)
        #expect(decoded.username == original.username)
        #expect(decoded.keychainKey == original.keychainKey)
        #expect(decoded.groupId == original.groupId)
        #expect(decoded.allowedUserIds == original.allowedUserIds)
        #expect(decoded.enabled == original.enabled)
        #expect(decoded.notes == original.notes)
    }

    @Test("decodeIfPresent — 신규 필드 missing 시 default")
    func backwardCompat() throws {
        // 옛 JSON: id + displayName + username + keychainKey만 있음
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "displayName": "Legacy",
            "username": "legacy_bot",
            "keychainKey": "telegram.legacy"
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(TelegramBotConfig.self, from: json)
        #expect(decoded.displayName == "Legacy")
        #expect(decoded.allowedUserIds.isEmpty)
        #expect(decoded.enabled == true)  // default
        #expect(decoded.notes.isEmpty)
    }
}
