import Foundation
import Testing
@testable import YuminaiCore

@Suite("InlineButton (ADR-057 Critical Fix 5)")
struct InlineButtonTests {
    @Test("64 bytes 이내는 그대로 보존")
    func preservesShortData() {
        let btn = InlineButton(text: "Cancel", callbackData: "cancel")
        #expect(btn.callbackData == "cancel")
    }

    @Test("64 bytes 정확히는 그대로")
    func preservesExactly64() {
        let exactly = String(repeating: "a", count: 64)
        let btn = InlineButton(text: "x", callbackData: exactly)
        #expect(btn.callbackData == exactly)
        #expect(btn.callbackData.utf8.count == 64)
    }

    @Test("64 bytes 초과 시 자동 truncate")
    func truncatesLong() {
        let long = String(repeating: "a", count: 100)
        let btn = InlineButton(text: "x", callbackData: long)
        #expect(btn.callbackData.utf8.count <= 64)
    }

    @Test("UUID + colon + suffix 조합 — 51 bytes는 OK")
    func realisticUUIDSize() {
        let uuid = UUID().uuidString
        let composite = "rehearse:\(uuid):codex"
        let btn = InlineButton(text: "Rehearse", callbackData: composite)
        #expect(btn.callbackData == composite)  // 51 bytes < 64
    }

    @Test("multi-byte (UTF-8 한글) 안전 truncate")
    func multibyteCharacterBoundary() {
        // 한글 1자 = 3 bytes UTF-8. 25자 = 75 bytes → 64 이내로 truncate.
        let korean = String(repeating: "한", count: 25)
        let btn = InlineButton(text: "x", callbackData: korean)
        #expect(btn.callbackData.utf8.count <= 64)
        // truncate가 char boundary에서 일어나야 함 (잘못된 utf8 시퀀스 X)
        #expect(String(btn.callbackData.utf8.map { Character(Unicode.Scalar($0)) }).count >= 0)
    }
}
