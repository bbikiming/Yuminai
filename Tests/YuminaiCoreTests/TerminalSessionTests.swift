import Foundation
import Testing
@testable import YuminaiCore

@Suite("TerminalSession (ADR-040 T1)")
struct TerminalSessionTests {
    @Test("기본 init은 새 UUID + 현재 시각")
    func basicInit() {
        let s = TerminalSession(label: "터미널 1", workingDirectory: "/tmp")
        #expect(s.label == "터미널 1")
        #expect(s.workingDirectory == "/tmp")
        #expect(s.createdAt.timeIntervalSinceNow > -2)
    }

    @Test("Identity는 id 기반 (label 같아도 다른 세션)")
    func identityIsId() {
        let a = TerminalSession(label: "x", workingDirectory: "/")
        let b = TerminalSession(label: "x", workingDirectory: "/")
        #expect(a != b)
        #expect(a.id != b.id)
    }

    @Test("Codable round-trip 보존 (영속화 가능)")
    func codableRoundTrip() throws {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let s = TerminalSession(id: id, label: "메인", workingDirectory: "/Users/x", createdAt: date)
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(TerminalSession.self, from: data)
        #expect(decoded == s)
        #expect(decoded.id == id)
    }

    @Test("defaultLabel은 1-based index")
    func defaultLabelIndex() {
        #expect(TerminalSession.defaultLabel(index: 0) == "터미널 1")
        #expect(TerminalSession.defaultLabel(index: 4) == "터미널 5")
    }

    @Test("Hashable — Set 중복 제거")
    func hashableSet() {
        let s = TerminalSession(label: "x", workingDirectory: "/")
        let set: Set<TerminalSession> = [s, s]
        #expect(set.count == 1)
    }

    @Test("label/workingDirectory mutable")
    func mutableFields() {
        var s = TerminalSession(label: "old", workingDirectory: "/old")
        s.label = "new"
        s.workingDirectory = "/new"
        #expect(s.label == "new")
        #expect(s.workingDirectory == "/new")
    }
}
