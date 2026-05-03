import Foundation
import Testing
@testable import YuminaiCore

@Suite("TelegramResponseMode (ADR-084 Phase 1)")
struct TelegramResponseModeTests {

    @Test("allCases — 4개")
    func allCases() {
        #expect(TelegramResponseMode.allCases.count == 4)
        #expect(TelegramResponseMode.allCases.contains(.minimal))
        #expect(TelegramResponseMode.allCases.contains(.concise))
        #expect(TelegramResponseMode.allCases.contains(.standard))
        #expect(TelegramResponseMode.allCases.contains(.detailed))
    }

    @Test("displayName 한국어")
    func displayNames() {
        #expect(TelegramResponseMode.minimal.displayName == "최소")
        #expect(TelegramResponseMode.concise.displayName == "간결")
        #expect(TelegramResponseMode.standard.displayName == "기본")
        #expect(TelegramResponseMode.detailed.displayName == "상세")
    }

    @Test("estimatedMaxOutputTokens — 단조 증가")
    func tokenEstimateMonotonic() {
        #expect(TelegramResponseMode.minimal.estimatedMaxOutputTokens < TelegramResponseMode.concise.estimatedMaxOutputTokens)
        #expect(TelegramResponseMode.concise.estimatedMaxOutputTokens < TelegramResponseMode.standard.estimatedMaxOutputTokens)
        #expect(TelegramResponseMode.standard.estimatedMaxOutputTokens < TelegramResponseMode.detailed.estimatedMaxOutputTokens)
    }

    @Test("promptInstruction — 모드별 다른 prompt")
    func promptInstructionUnique() {
        let prompts = TelegramResponseMode.allCases.map { $0.promptInstruction }
        let uniquePrompts = Set(prompts)
        #expect(uniquePrompts.count == prompts.count)
    }

    @Test("Codable round trip")
    func roundTrip() throws {
        for mode in TelegramResponseMode.allCases {
            let encoded = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(TelegramResponseMode.self, from: encoded)
            #expect(decoded == mode)
        }
    }
}

@Suite("TelegramTokenBudget (ADR-084 Phase 2)")
struct TelegramTokenBudgetTests {

    @Test("default — 하루 $5 + warn")
    func defaults() {
        let b = TelegramTokenBudget()
        #expect(b.perDayMaxCostUSD == 5.0)
        #expect(b.perTurnMaxOutputTokens == nil)
        #expect(b.overflowAction == .warn)
        #expect(b.perChatDailyMaxUSD.isEmpty)
    }

    @Test("Codable round trip")
    func roundTrip() throws {
        let b = TelegramTokenBudget(
            perTurnMaxOutputTokens: 500,
            perDayMaxCostUSD: 10.0,
            perChatDailyMaxUSD: ["chat-1": 2.0, "chat-2": 3.0],
            overflowAction: .block
        )
        let encoded = try JSONEncoder().encode(b)
        let decoded = try JSONDecoder().decode(TelegramTokenBudget.self, from: encoded)
        #expect(decoded == b)
    }

    @Test("backward-compat — 빈 JSON에서 default")
    func backwardCompat() throws {
        let oldJSON = "{}".data(using: .utf8)!
        let b = try JSONDecoder().decode(TelegramTokenBudget.self, from: oldJSON)
        #expect(b.perDayMaxCostUSD == 5.0)
        #expect(b.overflowAction == .warn)
    }
}

@Suite("TelegramOverflowAction")
struct TelegramOverflowActionTests {

    @Test("3개 action — warn/block/downgrade")
    func allCases() {
        #expect(TelegramOverflowAction.allCases.count == 3)
        for action in TelegramOverflowAction.allCases {
            #expect(!action.displayName.isEmpty)
            #expect(!action.hint.isEmpty)
        }
    }
}

@Suite("TelegramAttachmentPolicy (ADR-084 Phase 3)")
struct TelegramAttachmentPolicyTests {

    @Test("default — 5MB + 일반 텍스트 확장자")
    func defaults() {
        let p = TelegramAttachmentPolicy()
        #expect(p.acceptIncoming == true)
        #expect(p.sendOutgoing == true)
        #expect(p.maxIncomingSizeBytes == 5 * 1024 * 1024)
        #expect(p.allowedExtensions.contains("swift"))
        #expect(p.allowedExtensions.contains("md"))
    }

    @Test("isAllowed — 화이트리스트 매칭")
    func whitelist() {
        let p = TelegramAttachmentPolicy(allowedExtensions: ["txt", "md"])
        #expect(p.isAllowed(filename: "notes.md") == true)
        #expect(p.isAllowed(filename: "doc.txt") == true)
        #expect(p.isAllowed(filename: "image.png") == false)
        // 대문자 무관
        #expect(p.isAllowed(filename: "README.MD") == true)
    }

    @Test("빈 화이트리스트 — 모두 허용")
    func emptyWhitelistAll() {
        let p = TelegramAttachmentPolicy(allowedExtensions: [])
        #expect(p.isAllowed(filename: "any.bin") == true)
    }

    @Test("maxSizeDisplay — 5MB / 500KB")
    func sizeDisplay() {
        let p1 = TelegramAttachmentPolicy(maxIncomingSizeBytes: 5 * 1024 * 1024)
        #expect(p1.maxSizeDisplay == "5 MB")
        let p2 = TelegramAttachmentPolicy(maxIncomingSizeBytes: 500 * 1024)
        #expect(p2.maxSizeDisplay == "500 KB")
    }
}

@Suite("TelegramSkill (ADR-084 Phase 4)")
struct TelegramSkillTests {

    @Test("default skills — 4개")
    func defaultSkills() {
        let defaults = TelegramSkill.defaults
        #expect(defaults.count == 4)
        let triggers = defaults.map { $0.trigger }
        #expect(triggers.contains("test"))
        #expect(triggers.contains("review"))
        #expect(triggers.contains("summary"))
        #expect(triggers.contains("status"))
    }

    @Test("expand — args 없으면 prompt 그대로")
    func expandNoArgs() {
        let skill = TelegramSkill(trigger: "x", displayName: "X", prompt: "do X")
        #expect(skill.expand(args: "") == "do X")
    }

    @Test("expand — args 있으면 추가")
    func expandWithArgs() {
        let skill = TelegramSkill(trigger: "x", displayName: "X", prompt: "do X")
        let result = skill.expand(args: "with foo")
        #expect(result.contains("do X"))
        #expect(result.contains("with foo"))
    }

    @Test("expand — {args} 자리표시자 substitution")
    func expandPlaceholder() {
        let skill = TelegramSkill(trigger: "x", displayName: "X", prompt: "Run {args} test")
        #expect(skill.expand(args: "unit") == "Run unit test")
    }

    @Test("Codable round trip")
    func roundTrip() throws {
        let skill = TelegramSkill(
            trigger: "test",
            displayName: "테스트",
            prompt: "Do test",
            iconName: "checkmark",
            responseMode: .concise
        )
        let encoded = try JSONEncoder().encode(skill)
        let decoded = try JSONDecoder().decode(TelegramSkill.self, from: encoded)
        #expect(decoded == skill)
    }
}

@Suite("AppPreferences ADR-084 fields")
struct AppPreferencesADR084Tests {

    @Test("default — 모든 텔레그램 고도화 필드 default 적용")
    func defaults() {
        let p = AppPreferences()
        #expect(p.telegramResponseMode == .standard)
        #expect(p.telegramTokenBudget.perDayMaxCostUSD == 5.0)
        #expect(p.telegramAttachmentPolicy.acceptIncoming == true)
        #expect(p.telegramSkills.count == 4)  // default 4개
    }

    @Test("backward-compat — 기존 JSON에서도 default skills")
    func backwardCompat() throws {
        let oldJSON = """
        {
            "claudeBinaryPath": "/usr/local/bin/claude",
            "codexBinaryPath": "/usr/local/bin/codex",
            "telegramEnabled": false,
            "telegramAllowedUserIds": [],
            "fontSizeOffset": 0,
            "showInspectorByDefault": false
        }
        """.data(using: .utf8)!
        let p = try JSONDecoder().decode(AppPreferences.self, from: oldJSON)
        #expect(p.telegramResponseMode == .standard)
        #expect(p.telegramSkills.count == 4)  // 기존 사용자도 default skills 받음
    }

    @Test("round-trip — skills 보존")
    func roundTripSkills() throws {
        var p = AppPreferences()
        p.telegramSkills = [
            TelegramSkill(trigger: "custom", displayName: "Custom", prompt: "test")
        ]
        let encoded = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: encoded)
        #expect(decoded.telegramSkills.count == 1)
        #expect(decoded.telegramSkills[0].trigger == "custom")
    }
}
