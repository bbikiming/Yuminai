import Foundation

// MARK: - TaskSnapshot (ADR-052)

/// 완료된 task의 immutable snapshot — 다른 model로 rehearsal 재실행 시 입력 보존.
///
/// **출처/근거**:
/// - Promptfoo `tests[].vars` immutable input pattern
///   (https://www.promptfoo.dev/docs/configuration/guide/)
/// - Braintrust Dataset + Eval API
///   (https://www.braintrust.dev/docs/guides/evals)
/// - LangSmith Datasets + Experiments
///   (https://docs.smith.langchain.com/observability/concepts)
/// - Jest snapshot pattern (`__snapshots__/*.snap`, immutable + explicit `--updateSnapshot`)
///
/// **불변성 원칙** (rules/coding-style.md): snapshot은 절대 mutate되지 않음. 새 RehearsalRun이
/// snapshotId만 참조하는 별도 record.
public struct TaskSnapshot: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let taskId: UUID
    public let createdAt: Date
    /// snapshot 시점의 task title (task가 변경되어도 보존)
    public let taskTitle: String
    /// snapshot 시점의 task description
    public let taskDescription: String
    /// 원래 사용된 모델 (rawValue)
    public let originalAgentRaw: String
    /// 원래 사용된 SessionSettings 요약 (모델명, max_tokens 등)
    public let originalSettings: SettingsSummary
    /// 원래 ProjectProfile context summary (system prompt에 들어간 것)
    public let projectContextSummary: String
    /// snapshot에 포함된 ConversationEntry들 (verbatim — full context replay)
    public let entries: [ConversationEntry]
    /// 원래 task output (있으면)
    public let originalOutput: String?

    public init(
        id: UUID = UUID(),
        taskId: UUID,
        createdAt: Date = Date(),
        taskTitle: String,
        taskDescription: String,
        originalAgentRaw: String,
        originalSettings: SettingsSummary,
        projectContextSummary: String,
        entries: [ConversationEntry],
        originalOutput: String?
    ) {
        self.id = id
        self.taskId = taskId
        self.createdAt = createdAt
        self.taskTitle = taskTitle
        self.taskDescription = taskDescription
        self.originalAgentRaw = originalAgentRaw
        self.originalSettings = originalSettings
        self.projectContextSummary = projectContextSummary
        self.entries = entries
        self.originalOutput = originalOutput
    }

    public struct SettingsSummary: Codable, Sendable, Hashable {
        public let modelLabel: String
        public let mode: String
        public let permissionMode: String

        public init(modelLabel: String, mode: String, permissionMode: String) {
            self.modelLabel = modelLabel
            self.mode = mode
            self.permissionMode = permissionMode
        }
    }
}

// MARK: - RehearsalRun (ADR-052)

/// snapshot을 다른 모델로 재실행한 결과 — 별도 immutable record.
///
/// **저장 위치**: `~/Library/Application Support/Yuminai/rehearsals/{taskId}/{runId}.json`
/// (production conversation과 물리적으로 분리해 사용자 혼동 방지)
///
/// **상태**: pending → running → completed/failed (Promptfoo의 status 유사)
public struct RehearsalRun: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let snapshotId: UUID
    public let taskId: UUID
    public let startedAt: Date
    public var completedAt: Date?
    /// rehearsal에 사용한 모델 (snapshot.originalAgentRaw와 다른 게 정상)
    public let replayAgentRaw: String
    public var status: Status
    /// LLM 응답 텍스트 (success 시)
    public var resultText: String?
    /// 오류 메시지 (failed 시)
    public var errorMessage: String?
    /// 추정 비용 (사전 계산) — actual은 별도 metric 시스템에서 추적
    public let estimatedCostUSD: Double
    /// 실제 latency (ms)
    public var durationMs: Int?

    public enum Status: String, Codable, Sendable, Hashable {
        case pending
        case running
        case completed
        case failed
        case cancelled
    }

    public init(
        id: UUID = UUID(),
        snapshotId: UUID,
        taskId: UUID,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        replayAgentRaw: String,
        status: Status = .pending,
        resultText: String? = nil,
        errorMessage: String? = nil,
        estimatedCostUSD: Double = 0.0,
        durationMs: Int? = nil
    ) {
        self.id = id
        self.snapshotId = snapshotId
        self.taskId = taskId
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.replayAgentRaw = replayAgentRaw
        self.status = status
        self.resultText = resultText
        self.errorMessage = errorMessage
        self.estimatedCostUSD = estimatedCostUSD
        self.durationMs = durationMs
    }
}

// MARK: - RehearsalStore

/// Rehearsal snapshot/run 영속 store. file-based (per-task directory).
public actor RehearsalStore {
    public static let baseURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSString(string: "~/Library/Application Support").expandingTildeInPath)
        return appSupport.appendingPathComponent("Yuminai/rehearsals", isDirectory: true)
    }()

    private let baseURL: URL
    /// in-memory cache by taskId — UI 빠른 read용
    private var runsByTask: [UUID: [RehearsalRun]] = [:]
    private var snapshotsByTask: [UUID: TaskSnapshot] = [:]

    public init(baseURL: URL = RehearsalStore.baseURL) {
        self.baseURL = baseURL
    }

    /// snapshot 저장 (task당 1개만 유지 — 가장 최근 task 상태).
    public func saveSnapshot(_ snapshot: TaskSnapshot) async {
        do {
            try ensureDirectoryExists(forTaskId: snapshot.taskId)
            let url = snapshotURL(forTaskId: snapshot.taskId)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            snapshotsByTask[snapshot.taskId] = snapshot
        } catch {
            #if DEBUG
            print("[RehearsalStore] saveSnapshot failed: \(error)")
            #endif
        }
    }

    /// run 저장 — append-only.
    public func saveRun(_ run: RehearsalRun) async {
        do {
            try ensureDirectoryExists(forTaskId: run.taskId)
            let url = runURL(forTaskId: run.taskId, runId: run.id)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(run)
            try data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            var existing = runsByTask[run.taskId] ?? []
            // 같은 id면 update
            if let idx = existing.firstIndex(where: { $0.id == run.id }) {
                existing[idx] = run
            } else {
                existing.append(run)
            }
            runsByTask[run.taskId] = existing
        } catch {
            #if DEBUG
            print("[RehearsalStore] saveRun failed: \(error)")
            #endif
        }
    }

    public func loadSnapshot(taskId: UUID) async -> TaskSnapshot? {
        if let cached = snapshotsByTask[taskId] { return cached }
        let url = snapshotURL(forTaskId: taskId)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(TaskSnapshot.self, from: data)
            snapshotsByTask[taskId] = snapshot
            return snapshot
        } catch {
            return nil
        }
    }

    public func loadRuns(taskId: UUID) async -> [RehearsalRun] {
        if let cached = runsByTask[taskId] { return cached }
        let dirURL = baseURL.appendingPathComponent(taskId.uuidString)
        guard FileManager.default.fileExists(atPath: dirURL.path) else { return [] }
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
            let runFiles = contents.filter { $0.lastPathComponent.hasPrefix("run-") && $0.pathExtension == "json" }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var runs: [RehearsalRun] = []
            for file in runFiles {
                if let data = try? Data(contentsOf: file),
                   let run = try? decoder.decode(RehearsalRun.self, from: data) {
                    runs.append(run)
                }
            }
            runs.sort { $0.startedAt > $1.startedAt }
            runsByTask[taskId] = runs
            return runs
        } catch {
            return []
        }
    }

    /// 모든 cached snapshot/run 반환 (UI 화면 갱신용).
    public func cachedRuns(forTaskId id: UUID) -> [RehearsalRun] {
        runsByTask[id] ?? []
    }

    // MARK: - Internal

    private func ensureDirectoryExists(forTaskId id: UUID) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: baseURL.path) {
            try fm.createDirectory(at: baseURL, withIntermediateDirectories: true)
        }
        let dir = baseURL.appendingPathComponent(id.uuidString, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private func snapshotURL(forTaskId id: UUID) -> URL {
        baseURL.appendingPathComponent(id.uuidString).appendingPathComponent("snapshot.json")
    }

    private func runURL(forTaskId id: UUID, runId: UUID) -> URL {
        baseURL.appendingPathComponent(id.uuidString).appendingPathComponent("run-\(runId.uuidString).json")
    }
}
