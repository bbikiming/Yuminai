import Foundation
import Testing
@testable import YuminaiCore

/// **ADR-095 Phase 4** — TelegramDeepLinkRouter 유닛 테스트.
@Suite("TelegramDeepLinkRouter (ADR-095 Phase 4)")
struct TelegramDeepLinkRouterTests {

    private let sampleUUID = UUID(uuidString: "12345678-abcd-ef12-3456-789012345678")!

    // MARK: - URL 생성

    @Test("diff URL 생성")
    func diffURLGeneration() {
        let link = TelegramDeepLink.diff(id: sampleUUID)
        let url = link.url
        #expect(url.scheme == "yuminai")
        #expect(url.host == "diff")
        #expect(url.path == "/12345678-abcd-ef12-3456-789012345678")
    }

    @Test("log URL 생성")
    func logURLGeneration() {
        let link = TelegramDeepLink.log(id: sampleUUID)
        let url = link.url
        #expect(url.scheme == "yuminai")
        #expect(url.host == "log")
        #expect(url.path.contains("12345678"))
    }

    @Test("workspace URL 생성")
    func workspaceURLGeneration() {
        let link = TelegramDeepLink.workspace(id: sampleUUID)
        let url = link.url
        #expect(url.scheme == "yuminai")
        #expect(url.host == "workspace")
    }

    @Test("chat URL 생성 — 음수 chatId도 지원")
    func chatURLGeneration() {
        let link = TelegramDeepLink.chat(id: -100123456789)
        let url = link.url
        #expect(url.scheme == "yuminai")
        #expect(url.host == "chat")
        #expect(url.path == "/-100123456789")
    }

    @Test("approve URL 생성")
    func approveURLGeneration() {
        let link = TelegramDeepLink.approve(requestId: sampleUUID)
        let url = link.url
        #expect(url.host == "approve")
    }

    @Test("reject URL 생성")
    func rejectURLGeneration() {
        let link = TelegramDeepLink.reject(requestId: sampleUUID)
        let url = link.url
        #expect(url.host == "reject")
    }

    // MARK: - Round-trip (URL 생성 → 파싱)

    @Test("diff round-trip")
    func diffRoundTrip() {
        let original = TelegramDeepLink.diff(id: sampleUUID)
        let parsed = TelegramDeepLink.parse(original.url)
        #expect(parsed == original)
    }

    @Test("log round-trip")
    func logRoundTrip() {
        let original = TelegramDeepLink.log(id: sampleUUID)
        let parsed = TelegramDeepLink.parse(original.url)
        #expect(parsed == original)
    }

    @Test("workspace round-trip")
    func workspaceRoundTrip() {
        let original = TelegramDeepLink.workspace(id: sampleUUID)
        let parsed = TelegramDeepLink.parse(original.url)
        #expect(parsed == original)
    }

    @Test("chat round-trip — 양수 chatId")
    func chatRoundTripPositive() {
        let original = TelegramDeepLink.chat(id: 123456789)
        let parsed = TelegramDeepLink.parse(original.url)
        #expect(parsed == original)
    }

    @Test("chat round-trip — 음수 chatId")
    func chatRoundTripNegative() {
        let original = TelegramDeepLink.chat(id: -100123456789)
        let parsed = TelegramDeepLink.parse(original.url)
        #expect(parsed == original)
    }

    @Test("approve round-trip")
    func approveRoundTrip() {
        let original = TelegramDeepLink.approve(requestId: sampleUUID)
        let parsed = TelegramDeepLink.parse(original.url)
        #expect(parsed == original)
    }

    @Test("reject round-trip")
    func rejectRoundTrip() {
        let original = TelegramDeepLink.reject(requestId: sampleUUID)
        let parsed = TelegramDeepLink.parse(original.url)
        #expect(parsed == original)
    }

    // MARK: - 잘못된 형식 처리

    @Test("다른 scheme이면 nil 반환")
    func wrongSchemeReturnsNil() {
        let url = URL(string: "https://example.com/diff/\(sampleUUID)")!
        #expect(TelegramDeepLink.parse(url) == nil)
    }

    @Test("알 수 없는 host이면 nil 반환")
    func unknownHostReturnsNil() {
        let url = URL(string: "yuminai://unknown/\(sampleUUID)")!
        #expect(TelegramDeepLink.parse(url) == nil)
    }

    @Test("UUID가 아닌 path이면 nil 반환 (diff)")
    func invalidUUIDPathReturnsNil() {
        let url = URL(string: "yuminai://diff/not-a-uuid")!
        #expect(TelegramDeepLink.parse(url) == nil)
    }

    @Test("chat — 숫자가 아닌 path이면 nil 반환")
    func invalidChatIdReturnsNil() {
        let url = URL(string: "yuminai://chat/abc")!
        #expect(TelegramDeepLink.parse(url) == nil)
    }

    @Test("path 없는 URL이면 nil 반환")
    func emptyPathReturnsNil() {
        // path가 없으면 UUID 파싱 실패 → nil
        let url = URL(string: "yuminai://diff/")!
        #expect(TelegramDeepLink.parse(url) == nil)
    }
}
