import Foundation
import Testing
@testable import YuminaiCore

@Suite("InMemoryKeychainStore")
struct InMemoryKeychainStoreTests {
    @Test("set한 값이 get으로 동일하게 반환된다")
    func setAndGet() async throws {
        let store = InMemoryKeychainStore()
        try await store.set("hello", for: "k1")
        let got = try await store.get("k1")
        #expect(got == "hello")
    }

    @Test("미설정 키는 nil을 반환한다")
    func missingKeyIsNil() async throws {
        let store = InMemoryKeychainStore()
        let got = try await store.get("missing")
        #expect(got == nil)
    }

    @Test("같은 키에 set하면 upsert된다")
    func upsert() async throws {
        let store = InMemoryKeychainStore()
        try await store.set("first", for: "k")
        try await store.set("second", for: "k")
        #expect(try await store.get("k") == "second")
    }

    @Test("remove 후 get은 nil")
    func removeWorks() async throws {
        let store = InMemoryKeychainStore()
        try await store.set("v", for: "k")
        try await store.remove("k")
        #expect(try await store.get("k") == nil)
    }

    @Test("없는 키 remove는 idempotent")
    func removeIsIdempotent() async throws {
        let store = InMemoryKeychainStore()
        try await store.remove("never-set")
    }
}

@Suite("AppPreferences")
struct AppPreferencesTests {
    @Test("기본 생성자는 합리적 기본값")
    func defaults() {
        let prefs = AppPreferences()
        #expect(prefs.defaultSessionSettings.model == .sonnet)
        #expect(prefs.defaultSessionSettings.permissionMode == .default)
        #expect(prefs.defaultSessionSettings.effortLevel == .medium)
        #expect(prefs.telegramEnabled == false)
        #expect(prefs.fontSizeOffset == 0)
        #expect(prefs.telegramAlertPolicy.sendOnComplete == true)
    }

    @Test("Codable round-trip이 동일 값을 보존한다")
    func codableRoundTrip() throws {
        let original = AppPreferences(
            claudeBinaryPath: "/x",
            defaultSessionSettings: SessionSettings(
                model: .opus,
                permissionMode: .acceptEdits,
                effortLevel: .high,
                includeHookEvents: false,
                maxBudgetUSD: 10
            ),
            editPreferences: EditPreferences(
                autoFormat: false,
                showDiffOnEdit: false,
                autoBackup: true
            ),
            obsidianVaultPath: "/y",
            telegramEnabled: true,
            telegramAllowedUserIds: [1, 2, 3],
            telegramChatId: 12345,
            telegramAlertPolicy: TelegramAlertPolicy(
                sendOnComplete: false,
                sendOnError: true,
                sendOnDecisionRequired: true
            ),
            fontSizeOffset: 2,
            showInspectorByDefault: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: data)
        #expect(decoded == original)
    }
}

@Suite("UsageStats")
struct UsageStatsTests {
    @Test("add는 모든 필드를 누적한다")
    func addAccumulates() {
        var stats = UsageStats(inputTokens: 10, outputTokens: 20, costUSD: 0.001, messageCount: 1)
        stats.add(UsageStats(inputTokens: 5, outputTokens: 8, costUSD: 0.0005, messageCount: 1))
        #expect(stats.inputTokens == 15)
        #expect(stats.outputTokens == 28)
        #expect(stats.costUSD == 0.0015)
        #expect(stats.messageCount == 2)
    }

    @Test("contextUsage는 0~1로 정규화된다")
    func contextUsageClamps() {
        let stats = UsageStats(inputTokens: 50_000, cacheCreationTokens: 10_000)
        let ratio = stats.contextUsage(maxTokens: 200_000)
        #expect(ratio == 0.30)

        let overflow = UsageStats(inputTokens: 300_000)
        #expect(overflow.contextUsage(maxTokens: 200_000) == 1.0)

        let zero = UsageStats(inputTokens: 100)
        #expect(zero.contextUsage(maxTokens: 0) == 0)
    }
}
