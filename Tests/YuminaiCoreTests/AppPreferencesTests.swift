import Foundation
import Testing
@testable import YuminaiCore

@Suite("AppPreferences (ADR-071 — beginnerMode)")
struct AppPreferencesBeginnerModeTests {
    @Test("init() default — 신규 사용자는 초보자 모드")
    func newUserDefaultsToBeginnerMode() {
        let prefs = AppPreferences()
        #expect(prefs.beginnerMode == true)
    }

    @Test("decode without beginnerMode field — 기존 사용자는 고급 모드")
    func existingUserDefaultsToAdvanced() throws {
        // 기존 prefs JSON에 beginnerMode 필드가 없음 (ADR-071 이전 사용자)
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

        let prefs = try JSONDecoder().decode(AppPreferences.self, from: oldJSON)
        // 기존 사용자는 이미 고급 옵션 사용 중일 가능성 → false default
        #expect(prefs.beginnerMode == false)
    }

    @Test("decode with beginnerMode=true — 명시적 true 보존")
    func explicitTrueIsPreserved() throws {
        let json = """
        {
            "claudeBinaryPath": "/usr/local/bin/claude",
            "codexBinaryPath": "/usr/local/bin/codex",
            "telegramEnabled": false,
            "telegramAllowedUserIds": [],
            "fontSizeOffset": 0,
            "showInspectorByDefault": false,
            "beginnerMode": true
        }
        """.data(using: .utf8)!

        let prefs = try JSONDecoder().decode(AppPreferences.self, from: json)
        #expect(prefs.beginnerMode == true)
    }

    @Test("encode + decode round trip preserves beginnerMode")
    func roundTrip() throws {
        var original = AppPreferences()
        original.beginnerMode = false
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: encoded)
        #expect(decoded.beginnerMode == false)
    }

    @Test("init explicit beginnerMode=false — 사용자 명시 토글")
    func explicitInit() {
        let prefs = AppPreferences(beginnerMode: false)
        #expect(prefs.beginnerMode == false)
    }
}
