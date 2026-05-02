import Foundation
import Testing
@testable import YuminaiCore

@Suite("RoutingDecisionRecord (ADR-052)")
struct RoutingDecisionRecordTests {
    @Test("computeFingerprint: same task kind/lang/length bucket → same hash")
    func sameInputsSameFingerprint() {
        let a = RoutingDecisionRecord.computeFingerprint(
            taskKind: "codeGeneration",
            languageHint: "swift",
            promptLength: 100
        )
        let b = RoutingDecisionRecord.computeFingerprint(
            taskKind: "codeGeneration",
            languageHint: "swift",
            promptLength: 110  // 같은 'small' bucket (50..200)
        )
        #expect(a == b)
        #expect(a.count <= 16)
    }

    @Test("computeFingerprint: different bucket → different hash")
    func differentBucketDifferentFingerprint() {
        let small = RoutingDecisionRecord.computeFingerprint(
            taskKind: "codeGeneration",
            languageHint: "swift",
            promptLength: 100  // small
        )
        let large = RoutingDecisionRecord.computeFingerprint(
            taskKind: "codeGeneration",
            languageHint: "swift",
            promptLength: 1000  // large
        )
        #expect(small != large)
    }

    @Test("computeFingerprint: nil language defaults to '?'")
    func nilLanguageHandled() {
        let withNil = RoutingDecisionRecord.computeFingerprint(
            taskKind: "planning",
            languageHint: nil,
            promptLength: 50
        )
        #expect(!withNil.isEmpty)
    }

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        // ISO8601 dateEncodingStrategy가 fractional seconds를 무시하므로 시작 시점 Date를
        // 명시적으로 정수 초 boundary로 reset
        let cleanDate = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let original = RoutingDecisionRecord(
            timestamp: cleanDate,
            workspaceId: UUID(),
            workspaceName: "TestWorkspace",
            taskKindRaw: "codeGeneration",
            matchedKeyword: "구현",
            taskFingerprint: "abc123",
            candidates: [
                RoutingDecisionRecord.Candidate(agentRaw: "claude", score: 0.5, reasonCodes: ["fallback"]),
                RoutingDecisionRecord.Candidate(agentRaw: "codex", score: 1.0, reasonCodes: ["match"])
            ],
            selectedAgentRaw: "codex",
            previousAgentRaw: "claude",
            reasonSummary: "test reason",
            reasonCodes: ["kind_codeGeneration", "keyword_match"],
            outcome: .applied,
            estimatedHandoffTokens: 4000,
            redactedPrompt: "구현해줘 함수를...",
            rawPrompt: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RoutingDecisionRecord.self, from: data)
        #expect(decoded == original)
    }

    @Test("Outcome enum has all 4 cases")
    func outcomeCases() {
        let outcomes: [RoutingDecisionRecord.Outcome] = [.applied, .cancelled, .skipped, .failed]
        #expect(outcomes.count == 4)
    }
}

@Suite("RoutingDecisionLogStore (ADR-052)")
struct RoutingDecisionLogStoreTests {
    private func makeTempStore() -> (RoutingDecisionLogStore, URL) {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("yuminai-test-\(UUID().uuidString)", isDirectory: true)
        let store = RoutingDecisionLogStore(directoryURL: temp, memoryCapDays: 7)
        return (store, temp)
    }

    @Test("append → cached() returns the record")
    func appendAndCached() async {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let record = RoutingDecisionRecord(
            workspaceId: nil,
            workspaceName: nil,
            taskKindRaw: "planning",
            matchedKeyword: nil,
            taskFingerprint: "xyz",
            candidates: [],
            selectedAgentRaw: "claude",
            previousAgentRaw: "codex",
            reasonSummary: "test",
            reasonCodes: [],
            outcome: .applied,
            estimatedHandoffTokens: 0,
            redactedPrompt: "test"
        )
        await store.append(record)
        let cached = await store.cached()
        #expect(cached.count == 1)
        #expect(cached.first?.id == record.id)
    }

    @Test("loadRecent reads back appended records")
    func appendThenLoad() async {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        for i in 0..<3 {
            let r = RoutingDecisionRecord(
                workspaceId: nil,
                workspaceName: "ws\(i)",
                taskKindRaw: "planning",
                matchedKeyword: nil,
                taskFingerprint: "f\(i)",
                candidates: [],
                selectedAgentRaw: "claude",
                previousAgentRaw: "codex",
                reasonSummary: "test \(i)",
                reasonCodes: [],
                outcome: .applied,
                estimatedHandoffTokens: 0,
                redactedPrompt: "p\(i)"
            )
            await store.append(r)
        }
        let loaded = await store.loadRecent(days: 7)
        #expect(loaded.count == 3)
    }

    @Test("exportJSON without raw prompts redacts")
    func exportRedacts() async {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let record = RoutingDecisionRecord(
            workspaceId: nil,
            workspaceName: nil,
            taskKindRaw: "planning",
            matchedKeyword: nil,
            taskFingerprint: "x",
            candidates: [],
            selectedAgentRaw: "claude",
            previousAgentRaw: "codex",
            reasonSummary: "r",
            reasonCodes: [],
            outcome: .applied,
            estimatedHandoffTokens: 0,
            redactedPrompt: "redacted",
            rawPrompt: "FULL SENSITIVE PROMPT"
        )
        await store.append(record)
        let data = await store.exportJSON(includeRawPrompts: false)
        let json = String(data: data ?? Data(), encoding: .utf8) ?? ""
        #expect(!json.contains("FULL SENSITIVE PROMPT"))
        #expect(json.contains("redacted"))
    }

    @Test("recordsGroupedByFingerprint groups correctly")
    func groupByFingerprint() async {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        for fingerprint in ["a", "a", "b"] {
            let r = RoutingDecisionRecord(
                workspaceId: nil, workspaceName: nil,
                taskKindRaw: "planning", matchedKeyword: nil,
                taskFingerprint: fingerprint, candidates: [],
                selectedAgentRaw: "claude", previousAgentRaw: "codex",
                reasonSummary: "r", reasonCodes: [],
                outcome: .applied, estimatedHandoffTokens: 0,
                redactedPrompt: "p"
            )
            await store.append(r)
        }
        let grouped = await store.recordsGroupedByFingerprint()
        #expect(grouped["a"]?.count == 2)
        #expect(grouped["b"]?.count == 1)
    }
}
