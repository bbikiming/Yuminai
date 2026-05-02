import Foundation

// MARK: - RoutingDecisionRecord (ADR-052)

/// 자동 routing 1회의 immutable 결정 기록.
///
/// **출처/근거**:
/// - LangSmith `Run`/`Trace`/`Thread` 모델 (https://docs.smith.langchain.com/observability/concepts)
/// - Langfuse `Observation` immutable record (https://langfuse.com/docs/observability/data-model)
/// - Phoenix Span schema with `openinference.span.kind=AGENT`
///   (https://arize.com/docs/phoenix/tracing/concepts-tracing/what-are-traces)
/// - OTel GenAI semconv 1.41 — `gen_ai.*` 속성 (https://opentelemetry.io/docs/specs/semconv/gen-ai/gen-ai-spans/)
/// - Mitchell et al. "Model Cards for Model Reporting", FAT* '19 — Decision Card 패턴
///
/// **Privacy 원칙** (rules/security.md + OTel "Opt-In + sensitive" 가이드):
/// - 기본은 raw user prompt 미저장. `redactedPrompt`는 80자 prefix만.
/// - 풀 prompt 보존이 필요하면 `rawPrompt`에 caller 책임으로 저장 (UI에서 toggle).
public struct RoutingDecisionRecord: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let timestamp: Date
    public let workspaceId: UUID?
    public let workspaceName: String?

    /// 분류 결과 (TaskKind.rawValue)
    public let taskKindRaw: String
    /// XAI: matched keyword (있으면) — Mitchell의 model card "trigger" 필드와 동치
    public let matchedKeyword: String?
    /// task fingerprint (sha256 16자 prefix) — 같은 종류 task 그룹화용
    public let taskFingerprint: String

    /// 후보 모델들 (현재는 ModelCapabilityMatrix 결과 1개지만 confidence 비교용 배열 형태 보존)
    public let candidates: [Candidate]
    /// 최종 선택된 모델 (rawValue)
    public let selectedAgentRaw: String
    /// 이전 active model (rawValue) — 전환 정황 분석용
    public let previousAgentRaw: String

    /// 자연어 사유 — 사용자에게 표시 ("‘구현해줘’ keyword 감지 → codeGeneration")
    public let reasonSummary: String
    /// reason codes — 시스템 레벨 분석용 (filter/aggregation)
    public let reasonCodes: [String]

    /// outcome — 사용자가 cancel했는지, 실제 적용됐는지
    public let outcome: Outcome

    /// 추정 handoff prompt 토큰 수
    public let estimatedHandoffTokens: Int

    /// redacted prompt (첫 80자) — 사용자 화면에 안전하게 표시
    public let redactedPrompt: String
    /// raw prompt 보존 toggle (default false). preferences.routingLogRawPrompts에 따라 true.
    public let rawPrompt: String?

    public struct Candidate: Codable, Sendable, Hashable {
        public let agentRaw: String
        /// score [0,1] — 현재 단순 휴리스틱은 0.5/1.0 binary, 향후 LLM-based scoring 가능
        public let score: Double
        public let reasonCodes: [String]

        public init(agentRaw: String, score: Double, reasonCodes: [String]) {
            self.agentRaw = agentRaw
            self.score = score
            self.reasonCodes = reasonCodes
        }
    }

    public enum Outcome: String, Codable, Sendable, Hashable {
        case applied         // routing 적용됨
        case cancelled       // 사용자가 countdown 중 취소
        case skipped         // 추천 모델 == 현재 모델 (전환 X)
        case failed          // pane 없음 등 실패
    }

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        workspaceId: UUID?,
        workspaceName: String?,
        taskKindRaw: String,
        matchedKeyword: String?,
        taskFingerprint: String,
        candidates: [Candidate],
        selectedAgentRaw: String,
        previousAgentRaw: String,
        reasonSummary: String,
        reasonCodes: [String],
        outcome: Outcome,
        estimatedHandoffTokens: Int,
        redactedPrompt: String,
        rawPrompt: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.workspaceId = workspaceId
        self.workspaceName = workspaceName
        self.taskKindRaw = taskKindRaw
        self.matchedKeyword = matchedKeyword
        self.taskFingerprint = taskFingerprint
        self.candidates = candidates
        self.selectedAgentRaw = selectedAgentRaw
        self.previousAgentRaw = previousAgentRaw
        self.reasonSummary = reasonSummary
        self.reasonCodes = reasonCodes
        self.outcome = outcome
        self.estimatedHandoffTokens = estimatedHandoffTokens
        self.redactedPrompt = redactedPrompt
        self.rawPrompt = rawPrompt
    }

    /// task fingerprint 계산 — `{taskKind, lang, length_bucket}` 결합 hash 16자.
    /// 같은 종류 task 그룹화에 사용 (counterfactual aggregation).
    public static func computeFingerprint(taskKind: String, languageHint: String?, promptLength: Int) -> String {
        let bucket: String
        switch promptLength {
        case 0..<50: bucket = "xs"
        case 50..<200: bucket = "s"
        case 200..<800: bucket = "m"
        case 800..<3000: bucket = "l"
        default: bucket = "xl"
        }
        let lang = languageHint ?? "?"
        let combined = "\(taskKind)|\(lang)|\(bucket)"
        // 단순 hash — Foundation의 hashValue가 process마다 다르므로 SHA256 같은 고정 hash가 이상적이지만
        // 외부 의존 없이 안정성 확보 위해 djb2 알고리즘 사용
        var hash: UInt64 = 5381
        for byte in combined.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return String(hash, radix: 16).prefix(16).description
    }
}

// MARK: - RoutingDecisionLogStore

/// Routing decision log 영속 store (NDJSON daily rotation).
///
/// **저장 정책** (Langfuse v4 immutability + Honeycomb wide-event 패턴):
/// - 1 record = 1 NDJSON line, append-only
/// - 일자별 rotation: `~/Library/Application Support/Yuminai/routing-log/YYYY-MM-DD.ndjson`
/// - 파일 권한 0600 (security.md 준수)
/// - 메모리 cap: recent N days (default 7) 만 in-memory, 그 이전은 lazy load
///
/// **단일 사용자 macOS 환경 가정**: SQLite/DB 미사용, in-memory dict 충분 (~100k records까지).
public actor RoutingDecisionLogStore {
    public static let directoryURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSString(string: "~/Library/Application Support").expandingTildeInPath)
        return appSupport.appendingPathComponent("Yuminai/routing-log", isDirectory: true)
    }()

    private let directoryURL: URL
    private let dateFormatter: DateFormatter
    private let isoFormatter: ISO8601DateFormatter
    private var memoryCache: [RoutingDecisionRecord] = []
    private let memoryCapDays: Int

    public init(directoryURL: URL = RoutingDecisionLogStore.directoryURL, memoryCapDays: Int = 7) {
        self.directoryURL = directoryURL
        self.memoryCapDays = memoryCapDays
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd"
        self.dateFormatter.timeZone = TimeZone(identifier: "UTC")
        self.isoFormatter = ISO8601DateFormatter()
    }

    /// 1개 record 추가 — NDJSON으로 disk + memoryCache 업데이트.
    public func append(_ record: RoutingDecisionRecord) async {
        do {
            try ensureDirectoryExists()
            let fileURL = fileURL(for: record.timestamp)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let line = try encoder.encode(record)
            var lineWithNewline = Data()
            lineWithNewline.append(line)
            lineWithNewline.append(0x0A)  // \n

            if FileManager.default.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: lineWithNewline)
            } else {
                try lineWithNewline.write(to: fileURL, options: .atomic)
                // 권한 0600 (single-user only)
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: fileURL.path
                )
            }
            memoryCache.append(record)
            // memory cap 적용 — 너무 오래된 건 prune
            pruneMemoryCache()
        } catch {
            // 영속 실패는 silent — 사용자 main flow 차단 X (observability는 best-effort)
            // 향후 telemetry layer 추가 시 여기서 metric 발행
            #if DEBUG
            print("[RoutingDecisionLogStore] persist failed: \(error)")
            #endif
        }
    }

    /// recent N days records 로드 — app launch 시 호출 권장.
    public func loadRecent(days: Int) async -> [RoutingDecisionRecord] {
        do {
            try ensureDirectoryExists()
            let calendar = Calendar.current
            let now = Date()
            var allRecords: [RoutingDecisionRecord] = []
            for offset in 0..<days {
                guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
                let url = fileURL(for: date)
                if FileManager.default.fileExists(atPath: url.path) {
                    let records = try loadFile(at: url)
                    allRecords.append(contentsOf: records)
                }
            }
            allRecords.sort { $0.timestamp > $1.timestamp }
            memoryCache = allRecords
            return allRecords
        } catch {
            return []
        }
    }

    /// in-memory cache 반환 (loadRecent 호출 후).
    public func cached() -> [RoutingDecisionRecord] {
        memoryCache
    }

    /// fingerprint별 records 그룹화 — counterfactual A/B 분석용.
    public func recordsGroupedByFingerprint() -> [String: [RoutingDecisionRecord]] {
        Dictionary(grouping: memoryCache, by: \.taskFingerprint)
    }

    /// agent별 카운트 — UI 통계용.
    public func countByAgent() -> [String: Int] {
        var counts: [String: Int] = [:]
        for r in memoryCache where r.outcome == .applied {
            counts[r.selectedAgentRaw, default: 0] += 1
        }
        return counts
    }

    /// JSON export — 사용자가 ShareLink로 공유 시.
    /// 기본은 redacted (raw prompt 제거).
    public func exportJSON(includeRawPrompts: Bool = false) -> Data? {
        let toExport: [RoutingDecisionRecord] = memoryCache.map { record in
            if includeRawPrompts { return record }
            return RoutingDecisionRecord(
                id: record.id,
                timestamp: record.timestamp,
                workspaceId: record.workspaceId,
                workspaceName: record.workspaceName,
                taskKindRaw: record.taskKindRaw,
                matchedKeyword: record.matchedKeyword,
                taskFingerprint: record.taskFingerprint,
                candidates: record.candidates,
                selectedAgentRaw: record.selectedAgentRaw,
                previousAgentRaw: record.previousAgentRaw,
                reasonSummary: record.reasonSummary,
                reasonCodes: record.reasonCodes,
                outcome: record.outcome,
                estimatedHandoffTokens: record.estimatedHandoffTokens,
                redactedPrompt: record.redactedPrompt,
                rawPrompt: nil
            )
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(toExport)
    }

    // MARK: - Internal

    private func ensureDirectoryExists() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directoryURL.path) {
            try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    private func fileURL(for date: Date) -> URL {
        let dateString = dateFormatter.string(from: date)
        return directoryURL.appendingPathComponent("\(dateString).ndjson")
    }

    private func loadFile(at url: URL) throws -> [RoutingDecisionRecord] {
        let data = try Data(contentsOf: url)
        guard let string = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var records: [RoutingDecisionRecord] = []
        for line in string.split(separator: "\n") {
            let lineData = Data(line.utf8)
            if let record = try? decoder.decode(RoutingDecisionRecord.self, from: lineData) {
                records.append(record)
            }
        }
        return records
    }

    private func pruneMemoryCache() {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: -memoryCapDays, to: Date()) else { return }
        memoryCache.removeAll { $0.timestamp < cutoff }
    }
}
