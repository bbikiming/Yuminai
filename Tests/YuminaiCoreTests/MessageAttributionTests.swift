import Foundation
import Testing
@testable import YuminaiCore

/// **ADR-115 P1-2** — MessageAttribution 모델 테스트.
@Suite("MessageAttribution (ADR-115 P1-2)")
struct MessageAttributionTests {

    // MARK: - isEmpty

    @Test("라이브러리+프로필 없으면 isEmpty == true")
    func emptyWhenNoContent() {
        let attr = MessageAttribution(
            attachedLibraryItems: [],
            profileSnapshotSummary: nil
        )
        #expect(attr.isEmpty == true)
    }

    @Test("라이브러리만 있으면 isEmpty == false")
    func notEmptyWithLibrary() {
        let attr = MessageAttribution(
            attachedLibraryItems: ["Next.js 가이드"],
            profileSnapshotSummary: nil
        )
        #expect(attr.isEmpty == false)
    }

    @Test("프로필만 있으면 isEmpty == false")
    func notEmptyWithProfile() {
        let attr = MessageAttribution(
            attachedLibraryItems: [],
            profileSnapshotSummary: "iOS 개발자 · 앱 만들기"
        )
        #expect(attr.isEmpty == false)
    }

    @Test("profileSnapshotSummary가 빈 문자열이면 isEmpty == true")
    func emptyStringProfileCountsAsEmpty() {
        let attr = MessageAttribution(
            attachedLibraryItems: [],
            profileSnapshotSummary: ""
        )
        #expect(attr.isEmpty == true)
    }

    // MARK: - displaySummary

    @Test("라이브러리 1개 — displaySummary에 이름 포함")
    func displaySummaryOneLibrary() {
        let attr = MessageAttribution(
            attachedLibraryItems: ["Tailwind CSS 가이드"],
            profileSnapshotSummary: nil
        )
        #expect(attr.displaySummary.contains("참고 자료:"))
        #expect(attr.displaySummary.contains("Tailwind CSS 가이드"))
    }

    @Test("라이브러리 4개 — 3개 표시 + 외 1개")
    func displaySummaryFourLibrariesTruncates() {
        let attr = MessageAttribution(
            attachedLibraryItems: ["A", "B", "C", "D"],
            profileSnapshotSummary: nil
        )
        #expect(attr.displaySummary.contains("외 1개"))
    }

    @Test("프로필 있으면 '프로필:' 포함")
    func displaySummaryWithProfile() {
        let attr = MessageAttribution(
            attachedLibraryItems: [],
            profileSnapshotSummary: "iOS 개발자 · 앱 만들기"
        )
        #expect(attr.displaySummary.contains("프로필:"))
        #expect(attr.displaySummary.contains("iOS 개발자"))
    }

    @Test("라이브러리 + 프로필 모두 있으면 둘 다 포함")
    func displaySummaryBothFields() {
        let attr = MessageAttribution(
            attachedLibraryItems: ["Next.js"],
            profileSnapshotSummary: "웹 개발자"
        )
        let summary = attr.displaySummary
        #expect(summary.contains("참고 자료:"))
        #expect(summary.contains("프로필:"))
    }

    // MARK: - Codable round-trip

    @Test("Codable 라운드트립 — 모든 필드 보존")
    func codableRoundTrip() throws {
        let recordedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let attr = MessageAttribution(
            attachedLibraryItems: ["React 공식", "Tailwind"],
            profileSnapshotSummary: "풀스택 개발자",
            recordedAt: recordedAt
        )
        let data = try JSONEncoder().encode(attr)
        let decoded = try JSONDecoder().decode(MessageAttribution.self, from: data)
        #expect(decoded.attachedLibraryItems == ["React 공식", "Tailwind"])
        #expect(decoded.profileSnapshotSummary == "풀스택 개발자")
        #expect(decoded.recordedAt == recordedAt)
    }

    @Test("Codable 라운드트립 — nil 필드 처리")
    func codableRoundTripNilFields() throws {
        let attr = MessageAttribution(
            attachedLibraryItems: [],
            profileSnapshotSummary: nil
        )
        let data = try JSONEncoder().encode(attr)
        let decoded = try JSONDecoder().decode(MessageAttribution.self, from: data)
        #expect(decoded.attachedLibraryItems.isEmpty)
        #expect(decoded.profileSnapshotSummary == nil)
    }

    // MARK: - Message backward-compat

    @Test("기존 Message JSON (attribution 없음) 디코딩 성공")
    func messageBackwardCompatWithoutAttribution() throws {
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "sessionId": "00000000-0000-0000-0000-000000000002",
            "role": "assistant",
            "content": "Hello",
            "timestamp": 1700000000.0
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        #expect(decoded.attribution == nil)
        #expect(decoded.content == "Hello")
    }

    @Test("attribution 있는 Message 디코딩 성공")
    func messageWithAttributionDecoding() throws {
        let attr = MessageAttribution(
            attachedLibraryItems: ["Svelte"],
            profileSnapshotSummary: "프론트엔드 개발자"
        )
        let msg = Message(
            id: UUID(),
            sessionId: UUID(),
            role: .assistant,
            content: "응답입니다",
            attribution: attr
        )
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        #expect(decoded.attribution?.attachedLibraryItems == ["Svelte"])
        #expect(decoded.attribution?.profileSnapshotSummary == "프론트엔드 개발자")
    }
}
