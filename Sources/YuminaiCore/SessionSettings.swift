import Foundation

/// Claude CLI의 `--permission-mode` 옵션과 1:1 매칭.
public enum PermissionMode: String, Sendable, Codable, Hashable, CaseIterable {
    case `default` = "default"
    case acceptEdits = "acceptEdits"
    case auto = "auto"
    case bypassPermissions = "bypassPermissions"
    case dontAsk = "dontAsk"
    case plan = "plan"

    public var displayName: String {
        switch self {
        case .default: return "기본"
        case .acceptEdits: return "편집 자동 승인"
        case .auto: return "자동"
        case .bypassPermissions: return "권한 우회"
        case .dontAsk: return "묻지 않음"
        case .plan: return "Plan 모드"
        }
    }

    public var shortDescription: String {
        switch self {
        case .default: return "각 도구 호출마다 확인"
        case .acceptEdits: return "Edit/Write 자동, 위험 작업은 확인"
        case .auto: return "Yuminai가 알아서 분류"
        case .bypassPermissions: return "모든 권한 우회 (위험)"
        case .dontAsk: return "확인 다이얼로그 묻지 않음"
        case .plan: return "실행 없이 계획만 수립"
        }
    }
}

/// Claude CLI의 `--effort` 옵션과 1:1 매칭. 추론 깊이.
public enum EffortLevel: String, Sendable, Codable, Hashable, CaseIterable {
    case low, medium, high, max

    public var displayName: String {
        switch self {
        case .low: return "낮음"
        case .medium: return "중간"
        case .high: return "높음"
        case .max: return "최대"
        }
    }

    public var shortDescription: String {
        switch self {
        case .low: return "빠른 응답, 얕은 추론"
        case .medium: return "균형"
        case .high: return "깊은 추론, 느림"
        case .max: return "최대 깊이, 최대 비용"
        }
    }
}

/// `--model` 별 alias. Claude CLI가 alias를 받아 최신 모델로 매핑한다.
public enum ClaudeModel: String, Sendable, Codable, Hashable, CaseIterable {
    case haiku = "haiku"
    case sonnet = "sonnet"
    case opus = "opus"

    public var displayName: String {
        switch self {
        case .haiku: return "Haiku"
        case .sonnet: return "Sonnet"
        case .opus: return "Opus"
        }
    }

    public var subtitle: String {
        switch self {
        case .haiku: return "빠름·저비용"
        case .sonnet: return "균형"
        case .opus: return "최고 성능"
        }
    }

    /// 1M tokens당 input price (USD, 대략).
    public var inputPricePerMillion: Double {
        switch self {
        case .haiku: return 0.80
        case .sonnet: return 3.00
        case .opus: return 15.00
        }
    }

    /// 1M tokens당 output price (USD, 대략).
    public var outputPricePerMillion: Double {
        switch self {
        case .haiku: return 4.00
        case .sonnet: return 15.00
        case .opus: return 75.00
        }
    }

    /// 컨텍스트 윈도우 토큰 수 (기본).
    public var contextWindowTokens: Int { 200_000 }
}

/// 활성 세션의 Claude 호출 설정. 사용자가 toolbar에서 즉시 변경 가능.
///
/// **ADR-088** — `model` (Claude용) + `codexModel` (Codex용) 분리.
/// AppModel이 active agent에 따라 적절한 model을 어댑터에 전달.
public struct SessionSettings: Sendable, Codable, Hashable {
    public var model: ClaudeModel
    /// **ADR-088** — Codex CLI에 전달할 모델 (active agent == .codex일 때만 사용).
    public var codexModel: CodexModel
    public var permissionMode: PermissionMode
    public var effortLevel: EffortLevel
    public var includeHookEvents: Bool
    public var maxBudgetUSD: Double?

    public init(
        model: ClaudeModel = .sonnet,
        codexModel: CodexModel = .default,
        permissionMode: PermissionMode = .default,
        effortLevel: EffortLevel = .medium,
        includeHookEvents: Bool = true,
        maxBudgetUSD: Double? = nil
    ) {
        self.model = model
        self.codexModel = codexModel
        self.permissionMode = permissionMode
        self.effortLevel = effortLevel
        self.includeHookEvents = includeHookEvents
        self.maxBudgetUSD = maxBudgetUSD
    }

    /// **ADR-088** — backward-compat 디코더 (codexModel 누락 시 default).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.model = try c.decodeIfPresent(ClaudeModel.self, forKey: .model) ?? .sonnet
        self.codexModel = try c.decodeIfPresent(CodexModel.self, forKey: .codexModel) ?? .default
        self.permissionMode = try c.decodeIfPresent(PermissionMode.self, forKey: .permissionMode) ?? .default
        self.effortLevel = try c.decodeIfPresent(EffortLevel.self, forKey: .effortLevel) ?? .medium
        self.includeHookEvents = try c.decodeIfPresent(Bool.self, forKey: .includeHookEvents) ?? true
        self.maxBudgetUSD = try c.decodeIfPresent(Double.self, forKey: .maxBudgetUSD)
    }

    public static let `default` = SessionSettings()
}

/// 사용량 집계. 세션별 + 누적 둘 다 같은 타입.
public struct UsageStats: Sendable, Codable, Hashable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheCreationTokens: Int
    public var cacheReadTokens: Int
    public var costUSD: Double
    public var messageCount: Int

    public init(
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheCreationTokens: Int = 0,
        cacheReadTokens: Int = 0,
        costUSD: Double = 0,
        messageCount: Int = 0
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.costUSD = costUSD
        self.messageCount = messageCount
    }

    public mutating func add(_ other: UsageStats) {
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        cacheCreationTokens += other.cacheCreationTokens
        cacheReadTokens += other.cacheReadTokens
        costUSD += other.costUSD
        messageCount += other.messageCount
    }

    /// 컨텍스트 사용 비율 (0.0 ~ 1.0). input + cache_creation을 활성 컨텍스트로 본다.
    public func contextUsage(maxTokens: Int) -> Double {
        guard maxTokens > 0 else { return 0 }
        let active = inputTokens + cacheCreationTokens
        return min(1.0, Double(active) / Double(maxTokens))
    }

    public var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    public static let zero = UsageStats()
}

/// 편집 동작 관련 사용자 환경 설정.
public struct EditPreferences: Sendable, Codable, Hashable {
    /// Edit/Write 결과를 자동 포맷터로 정리.
    public var autoFormat: Bool
    /// 변경 후 자동으로 git diff 미리보기 표시.
    public var showDiffOnEdit: Bool
    /// 변경 자동 백업 (`.harness/backups/`).
    public var autoBackup: Bool

    public init(
        autoFormat: Bool = true,
        showDiffOnEdit: Bool = true,
        autoBackup: Bool = false
    ) {
        self.autoFormat = autoFormat
        self.showDiffOnEdit = showDiffOnEdit
        self.autoBackup = autoBackup
    }

    public static let `default` = EditPreferences()
}
