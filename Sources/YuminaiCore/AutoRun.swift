import Foundation

// MARK: - AutoRunConfig

/// **ADR-132** — 자동 실행 설정.
///
/// Claude Code의 `--dangerously-skip-permissions` 풍 자동화를 Yuminai 내부에서
/// 안전하게 구현하기 위한 설정 구조체.
///
/// ## 안전 원칙
/// - `stopOnDestructive`는 기본 `true` — HITLActionGuard와 통합해 위험 명령 차단
/// - `maxTurns`/`maxBudgetUSD`/`maxDurationSeconds` hard cap이 항상 적용됨
/// - `autoApprovePermissions`는 destructive 제외
public struct AutoRunConfig: Sendable, Codable, Hashable {

    // MARK: - 기본 제어

    /// 마스터 토글 — 자동 실행 활성 여부.
    public var enabled: Bool

    /// 최대 turn 수 (1~200). 200 초과는 hard cap으로 차단.
    public var maxTurns: Int

    /// 최대 예산 USD (0.1~50.0).
    public var maxBudgetUSD: Double

    /// 최대 지속 시간 초 (60~14400 = 4시간 hard cap).
    public var maxDurationSeconds: TimeInterval

    // MARK: - 안전장치

    /// HITLActionGuard로 위험 명령 감지 시 자동 일시정지 (default true — 절대 false 권장 안 함).
    public var stopOnDestructive: Bool

    /// 에러 연속 N회 시 자동 중단.
    public var errorThreshold: Int

    // MARK: - 종료 신호

    /// 응답에서 이 문구 등장 시 자동 종료.
    public var stopKeywords: [String]

    // MARK: - 권한

    /// 권한 요청 자동 승인 (HITL bypass — destructive 제외).
    public var autoApprovePermissions: Bool

    // MARK: - 명령 정책 (ADR-133)

    /// 실행 명령 정책 매트릭스 (per-run override).
    /// nil이면 AppPreferences.commandPolicy (글로벌 설정) 사용.
    public var commandPolicy: CommandPolicyMatrix?

    // MARK: - Harness 통합

    /// `.harness/rules/*.md` 자동 로드 + LLM system prompt 주입.
    public var autoLoadHarnessRules: Bool

    /// `.harness/skills/` 자동 첨부.
    public var autoLoadHarnessSkills: Bool

    // MARK: - 알림

    /// 완료 시 알림.
    public var notifyOnComplete: Bool

    /// 알림 채널.
    public var notifyChannel: NotifyChannel

    // MARK: - Hard caps (절대 초과 불가)

    /// 절대 최대 turn 수 — 설정값이 이를 초과하면 이 값으로 자동 clamp.
    public static let absoluteMaxTurns: Int = 200

    /// 절대 최대 지속 시간 초 (4시간).
    public static let absoluteMaxDurationSeconds: TimeInterval = 14_400

    // MARK: - NotifyChannel

    public enum NotifyChannel: String, Sendable, Codable, CaseIterable, Hashable {
        case macOS
        case telegram
        case both

        public var displayName: String {
            switch self {
            case .macOS: return "macOS 알림"
            case .telegram: return "텔레그램"
            case .both: return "macOS + 텔레그램"
            }
        }
    }

    // MARK: - init

    public init(
        enabled: Bool = false,
        maxTurns: Int = 30,
        maxBudgetUSD: Double = 3.0,
        maxDurationSeconds: TimeInterval = 1800,
        stopOnDestructive: Bool = true,
        errorThreshold: Int = 3,
        stopKeywords: [String] = ["작업 완료", "DONE", "✅ 완료", "ALL DONE"],
        autoApprovePermissions: Bool = true,
        commandPolicy: CommandPolicyMatrix? = nil,
        autoLoadHarnessRules: Bool = true,
        autoLoadHarnessSkills: Bool = false,
        notifyOnComplete: Bool = true,
        notifyChannel: NotifyChannel = .macOS
    ) {
        self.enabled = enabled
        // Hard cap 적용
        self.maxTurns = min(maxTurns, Self.absoluteMaxTurns)
        self.maxBudgetUSD = maxBudgetUSD
        self.maxDurationSeconds = min(maxDurationSeconds, Self.absoluteMaxDurationSeconds)
        self.stopOnDestructive = stopOnDestructive
        self.errorThreshold = errorThreshold
        self.stopKeywords = stopKeywords
        self.autoApprovePermissions = autoApprovePermissions
        self.commandPolicy = commandPolicy
        self.autoLoadHarnessRules = autoLoadHarnessRules
        self.autoLoadHarnessSkills = autoLoadHarnessSkills
        self.notifyOnComplete = notifyOnComplete
        self.notifyChannel = notifyChannel
    }

    /// 기본 설정값.
    public static let `default`: AutoRunConfig = AutoRunConfig()

    // MARK: - Codable (backward-compat)

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        let rawTurns = try c.decodeIfPresent(Int.self, forKey: .maxTurns) ?? 30
        self.maxTurns = min(rawTurns, Self.absoluteMaxTurns)
        self.maxBudgetUSD = try c.decodeIfPresent(Double.self, forKey: .maxBudgetUSD) ?? 3.0
        let rawDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .maxDurationSeconds) ?? 1800
        self.maxDurationSeconds = min(rawDuration, Self.absoluteMaxDurationSeconds)
        self.stopOnDestructive = try c.decodeIfPresent(Bool.self, forKey: .stopOnDestructive) ?? true
        self.errorThreshold = try c.decodeIfPresent(Int.self, forKey: .errorThreshold) ?? 3
        self.stopKeywords = try c.decodeIfPresent([String].self, forKey: .stopKeywords) ?? ["작업 완료", "DONE", "✅ 완료", "ALL DONE"]
        self.autoApprovePermissions = try c.decodeIfPresent(Bool.self, forKey: .autoApprovePermissions) ?? true
        self.commandPolicy = try c.decodeIfPresent(CommandPolicyMatrix.self, forKey: .commandPolicy)
        self.autoLoadHarnessRules = try c.decodeIfPresent(Bool.self, forKey: .autoLoadHarnessRules) ?? true
        self.autoLoadHarnessSkills = try c.decodeIfPresent(Bool.self, forKey: .autoLoadHarnessSkills) ?? false
        self.notifyOnComplete = try c.decodeIfPresent(Bool.self, forKey: .notifyOnComplete) ?? true
        self.notifyChannel = try c.decodeIfPresent(NotifyChannel.self, forKey: .notifyChannel) ?? .macOS
    }
}

// MARK: - AutoRunTurnLog

/// 자동 실행 중 개별 turn 로그 — `.harness/auto-run-log/<run-id>.jsonl`에 영구 보관.
public struct AutoRunTurnLog: Sendable, Codable, Hashable {
    /// 실행 세션 UUID.
    public let runId: UUID
    /// Turn 번호 (1-based).
    public let turn: Int
    /// 기록 시각.
    public let timestamp: Date
    /// 이 turn의 사용자 프롬프트 (첫 turn은 initialPrompt, 이후는 nil 또는 auto-chain prompt).
    public let userPrompt: String?
    /// LLM 응답 (전체 텍스트).
    public let agentResponse: String
    /// 감지된 도구 호출 목록.
    public let toolCalls: [String]
    /// 이 turn의 비용 (USD).
    public let costUSD: Double
    /// 이 turn의 소요 시간 (초).
    public let durationSeconds: TimeInterval
    /// 경고 메시지 목록 (예: 예산 근접, destructive 감지 등).
    public let warnings: [String]

    public init(
        runId: UUID,
        turn: Int,
        timestamp: Date,
        userPrompt: String?,
        agentResponse: String,
        toolCalls: [String],
        costUSD: Double,
        durationSeconds: TimeInterval,
        warnings: [String]
    ) {
        self.runId = runId
        self.turn = turn
        self.timestamp = timestamp
        self.userPrompt = userPrompt
        self.agentResponse = agentResponse
        self.toolCalls = toolCalls
        self.costUSD = costUSD
        self.durationSeconds = durationSeconds
        self.warnings = warnings
    }
}

// MARK: - AutoRunCompletionReason

/// 자동 실행 종료 원인.
public enum AutoRunCompletionReason: Sendable, Equatable, Codable {
    /// stop keyword 감지로 정상 완료.
    case stopKeyword(String)
    /// 최대 turn 도달.
    case maxTurnsReached(Int)
    /// 최대 예산 도달.
    case maxBudgetReached(Double)
    /// 최대 지속 시간 도달.
    case maxDurationReached(TimeInterval)
    /// 사용자 수동 중단.
    case userStop
    /// 연속 에러 임계값 초과.
    case errorThreshold(Int)
    /// Destructive 명령 감지로 차단.
    case destructiveBlocked(String)

    // MARK: - Display

    /// 사용자 친화 설명 (한국어).
    public var displayDescription: String {
        switch self {
        case .stopKeyword(let kw):
            return "종료 신호 감지 (\"\(kw)\")"
        case .maxTurnsReached(let n):
            return "최대 진행 횟수 도달 (\(n)회)"
        case .maxBudgetReached(let usd):
            return "최대 예산 도달 ($\(String(format: "%.2f", usd)))"
        case .maxDurationReached(let sec):
            let mins = Int(sec / 60)
            return "최대 지속 시간 도달 (\(mins)분)"
        case .userStop:
            return "사용자 중단"
        case .errorThreshold(let n):
            return "연속 에러 \(n)회 초과"
        case .destructiveBlocked(let cmd):
            return "위험 명령 차단: \(cmd)"
        }
    }

    // MARK: - Codable

    private enum CodingKey: String, Swift.CodingKey {
        case type, value, doubleValue, intervalValue
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKey.self)
        switch self {
        case .stopKeyword(let s):
            try c.encode("stopKeyword", forKey: .type)
            try c.encode(s, forKey: .value)
        case .maxTurnsReached(let n):
            try c.encode("maxTurnsReached", forKey: .type)
            try c.encode(n, forKey: .value)
        case .maxBudgetReached(let d):
            try c.encode("maxBudgetReached", forKey: .type)
            try c.encode(d, forKey: .doubleValue)
        case .maxDurationReached(let t):
            try c.encode("maxDurationReached", forKey: .type)
            try c.encode(t, forKey: .intervalValue)
        case .userStop:
            try c.encode("userStop", forKey: .type)
        case .errorThreshold(let n):
            try c.encode("errorThreshold", forKey: .type)
            try c.encode(n, forKey: .value)
        case .destructiveBlocked(let s):
            try c.encode("destructiveBlocked", forKey: .type)
            try c.encode(s, forKey: .value)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKey.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "stopKeyword":
            self = .stopKeyword(try c.decode(String.self, forKey: .value))
        case "maxTurnsReached":
            self = .maxTurnsReached(try c.decode(Int.self, forKey: .value))
        case "maxBudgetReached":
            self = .maxBudgetReached(try c.decode(Double.self, forKey: .doubleValue))
        case "maxDurationReached":
            self = .maxDurationReached(try c.decode(TimeInterval.self, forKey: .intervalValue))
        case "userStop":
            self = .userStop
        case "errorThreshold":
            self = .errorThreshold(try c.decode(Int.self, forKey: .value))
        case "destructiveBlocked":
            self = .destructiveBlocked(try c.decode(String.self, forKey: .value))
        default:
            self = .userStop
        }
    }
}
