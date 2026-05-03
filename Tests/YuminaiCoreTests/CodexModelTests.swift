import Foundation
import Testing
@testable import YuminaiCore

@Suite("CodexModel (ADR-088)")
struct CodexModelTests {

    @Test("default — gpt5")
    func defaultIsGpt5() {
        #expect(CodexModel.default == .gpt5)
        #expect(CodexModel.default.rawIdentifier == "gpt-5")
    }

    @Test("knownCases — 7개의 well-known 모델")
    func knownCasesCount() {
        #expect(CodexModel.knownCases.count == 7)
        #expect(CodexModel.knownCases.contains(.gpt5))
        #expect(CodexModel.knownCases.contains(.gpt5Codex))
        #expect(CodexModel.knownCases.contains(.o3))
        #expect(CodexModel.knownCases.contains(.o4Mini))
        // .custom은 knownCases에 없어야 함
        #expect(!CodexModel.knownCases.contains(where: { if case .custom = $0 { true } else { false } }))
    }

    @Test("rawIdentifier — Codex CLI에 전달할 정확한 string")
    func rawIdentifiers() {
        #expect(CodexModel.gpt5.rawIdentifier == "gpt-5")
        #expect(CodexModel.gpt5Codex.rawIdentifier == "gpt-5-codex")
        #expect(CodexModel.o3.rawIdentifier == "o3")
        #expect(CodexModel.o3Mini.rawIdentifier == "o3-mini")
        #expect(CodexModel.o4Mini.rawIdentifier == "o4-mini")
        #expect(CodexModel.gpt4o.rawIdentifier == "gpt-4o")
        #expect(CodexModel.gpt41.rawIdentifier == "gpt-4.1")
        #expect(CodexModel.custom("gpt-5.4").rawIdentifier == "gpt-5.4")
    }

    @Test("displayName — 사람-친화적")
    func displayNames() {
        #expect(CodexModel.gpt5.displayName == "GPT-5")
        #expect(CodexModel.gpt5Codex.displayName == "GPT-5 Codex")
        #expect(CodexModel.o3.displayName == "o3")
        #expect(CodexModel.custom("foo").displayName == "foo")
    }

    @Test("subtitle — 비어있지 않음")
    func subtitlesNotEmpty() {
        for m in CodexModel.knownCases {
            #expect(!m.subtitle.isEmpty)
        }
    }

    @Test("pricing — known 모델은 양수, custom은 0")
    func pricing() {
        #expect(CodexModel.gpt5.inputPricePerMillion > 0)
        #expect(CodexModel.gpt5.outputPricePerMillion > CodexModel.gpt5.inputPricePerMillion)
        #expect(CodexModel.o3.outputPricePerMillion >= 40.0, "o3는 가장 비싼 변형")
        #expect(CodexModel.custom("anything").inputPricePerMillion == 0)
    }

    @Test("contextWindow — known 모델은 합리적 범위")
    func contextWindows() {
        #expect(CodexModel.gpt5.contextWindowTokens == 400_000)
        #expect(CodexModel.o3.contextWindowTokens == 200_000)
        #expect(CodexModel.gpt4o.contextWindowTokens == 128_000)
        #expect(CodexModel.custom("any").contextWindowTokens == 128_000, "custom은 보수적 default")
    }

    @Test("fromRawIdentifier — known 매칭")
    func fromRawKnown() {
        #expect(CodexModel.fromRawIdentifier("gpt-5") == .gpt5)
        #expect(CodexModel.fromRawIdentifier("o3") == .o3)
        #expect(CodexModel.fromRawIdentifier("gpt-4.1") == .gpt41)
    }

    @Test("fromRawIdentifier — unknown은 .custom으로 wrap")
    func fromRawUnknown() {
        let custom = CodexModel.fromRawIdentifier("gpt-5.4")
        if case .custom(let raw) = custom {
            #expect(raw == "gpt-5.4")
        } else {
            Issue.record("expected .custom")
        }
    }

    @Test("Codable — round-trip preserves identifier")
    func codableRoundTrip() throws {
        for original in CodexModel.knownCases {
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(CodexModel.self, from: data)
            #expect(decoded.rawIdentifier == original.rawIdentifier)
        }
    }

    @Test("Codable — custom round-trip")
    func codableCustomRoundTrip() throws {
        let original = CodexModel.custom("gpt-5.4")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CodexModel.self, from: data)
        #expect(decoded == .custom("gpt-5.4"))
        #expect(decoded.rawIdentifier == "gpt-5.4")
    }

    @Test("Codable — string format decode (config.toml-style)")
    func codableStringFormat() throws {
        // 옛/string 포맷: 단순 string으로 인코딩된 경우 (사용자 ~/.codex/config.toml)
        let json = "\"gpt-5.4\"".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(CodexModel.self, from: json)
        if case .custom(let raw) = decoded {
            #expect(raw == "gpt-5.4")
        } else {
            Issue.record("expected .custom for unknown string")
        }

        let knownJson = "\"gpt-5\"".data(using: .utf8)!
        let knownDecoded = try JSONDecoder().decode(CodexModel.self, from: knownJson)
        #expect(knownDecoded == .gpt5)
    }
}

@Suite("SessionSettings.codexModel (ADR-088)")
struct SessionSettingsCodexModelTests {

    @Test("default — codexModel == .gpt5")
    func defaultCodexModel() {
        let s = SessionSettings.default
        #expect(s.codexModel == .gpt5)
        #expect(s.model == .sonnet, "Claude default 보존")
    }

    @Test("init — codexModel 명시 가능")
    func explicitCodexModel() {
        let s = SessionSettings(model: .opus, codexModel: .gpt5Codex)
        #expect(s.model == .opus)
        #expect(s.codexModel == .gpt5Codex)
    }

    @Test("Codable backward-compat — codexModel 누락 시 .gpt5")
    func backwardCompatCodexModel() throws {
        // 옛 JSON: codexModel 필드 없음
        let json = """
        {
            "model": "opus",
            "permissionMode": "plan",
            "effortLevel": "high",
            "includeHookEvents": true
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SessionSettings.self, from: json)
        #expect(decoded.model == .opus)
        #expect(decoded.codexModel == .gpt5, "신규 필드 누락 시 default")
    }

    @Test("Codable round-trip — codexModel 보존")
    func codableRoundTrip() throws {
        let original = SessionSettings(
            model: .haiku,
            codexModel: .o3,
            permissionMode: .acceptEdits,
            effortLevel: .high
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SessionSettings.self, from: data)
        #expect(decoded.model == .haiku)
        #expect(decoded.codexModel == .o3)
        #expect(decoded.permissionMode == .acceptEdits)
    }
}
