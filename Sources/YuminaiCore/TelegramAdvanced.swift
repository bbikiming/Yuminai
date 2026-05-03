import Foundation

/// **ADR-084 Phase 1** — 텔레그램 외부 turn의 응답 detail 레벨.
///
/// 사용자가 모바일에서 받고 싶은 응답 길이/스타일을 4단계로 선택.
/// `ChildClaudeProcess` 또는 main conversation에서 system prompt에 추가됨.
public enum TelegramResponseMode: String, Sendable, Codable, CaseIterable, Identifiable, Hashable {
    /// 결과만 (✓ 성공 / ✗ 실패 / 한 줄). 이동 중 빠른 확인.
    case minimal
    /// 한 단락 요약. 핵심 결과 + 다음 단계.
    case concise
    /// 표준 (default). 결과 + 주요 변경/이유.
    case standard
    /// 상세 (long-form). 모든 reasoning + 변경 diff 일부.
    case detailed

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .minimal: return "최소"
        case .concise: return "간결"
        case .standard: return "기본"
        case .detailed: return "상세"
        }
    }

    public var hint: String {
        switch self {
        case .minimal: return "결과만 (✓/✗ 한 줄). 이동 중 가장 빠른 확인."
        case .concise: return "한 단락 요약 + 다음 단계. 핵심만."
        case .standard: return "결과 + 주요 변경/이유 (default)."
        case .detailed: return "상세 reasoning + diff 일부. 토큰 소모 큼."
        }
    }

    /// system prompt에 inject할 instruction text.
    public var promptInstruction: String {
        switch self {
        case .minimal:
            return "Reply with ONLY the final result in 1 line. Use ✓ for success or ✗ for failure. NO explanation."
        case .concise:
            return "Reply concisely in ONE paragraph: result + 1 sentence reasoning + next step. Korean."
        case .standard:
            return "Reply in 2-3 paragraphs: result, key changes/reasons, next step. Korean."
        case .detailed:
            return "Reply with detailed reasoning, file changes overview, and next steps. Use markdown sections. Korean."
        }
    }

    /// 추정 max output tokens (서버 cost 추정용).
    public var estimatedMaxOutputTokens: Int {
        switch self {
        case .minimal: return 50
        case .concise: return 250
        case .standard: return 800
        case .detailed: return 3000
        }
    }
}

/// **ADR-084 Phase 2** — 텔레그램 외부 turn 토큰/비용 budget.
///
/// 3단계 cap (각각 독립 적용):
/// - per-turn: 1번 외부 turn 최대 토큰 (input + output)
/// - per-day: 하루 누적 최대 비용 (USD, 자정 reset)
/// - per-chat: 특정 chat의 일별 quota (chat ID별 분리)
public struct TelegramTokenBudget: Sendable, Codable, Hashable {
    /// 1턴당 max output tokens. nil = 모드별 default.
    public var perTurnMaxOutputTokens: Int?
    /// 하루 누적 max USD. nil = 무제한.
    public var perDayMaxCostUSD: Double?
    /// chat별 일별 max USD. chatId(string) → max.
    public var perChatDailyMaxUSD: [String: Double]
    /// 초과 시 동작.
    public var overflowAction: TelegramOverflowAction

    public init(
        perTurnMaxOutputTokens: Int? = nil,
        perDayMaxCostUSD: Double? = 5.0,  // default 하루 $5
        perChatDailyMaxUSD: [String: Double] = [:],
        overflowAction: TelegramOverflowAction = .warn
    ) {
        self.perTurnMaxOutputTokens = perTurnMaxOutputTokens
        self.perDayMaxCostUSD = perDayMaxCostUSD
        self.perChatDailyMaxUSD = perChatDailyMaxUSD
        self.overflowAction = overflowAction
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.perTurnMaxOutputTokens = try c.decodeIfPresent(Int.self, forKey: .perTurnMaxOutputTokens)
        self.perDayMaxCostUSD = try c.decodeIfPresent(Double.self, forKey: .perDayMaxCostUSD) ?? 5.0
        self.perChatDailyMaxUSD = try c.decodeIfPresent([String: Double].self, forKey: .perChatDailyMaxUSD) ?? [:]
        self.overflowAction = try c.decodeIfPresent(TelegramOverflowAction.self, forKey: .overflowAction) ?? .warn
    }
}

public enum TelegramOverflowAction: String, Sendable, Codable, CaseIterable, Identifiable {
    /// 경고 메시지 + 진행 (사용자 알림만).
    case warn
    /// 외부 turn 전면 차단 (다음 자정까지).
    case block
    /// minimal 모드로 강제 전환 (계속 사용 가능).
    case downgrade

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .warn: return "경고만"
        case .block: return "차단"
        case .downgrade: return "최소 모드로 전환"
        }
    }

    public var hint: String {
        switch self {
        case .warn: return "한도 초과 시 텔레그램에 ⚠ 알림 + 계속 진행."
        case .block: return "한도 초과 시 외부 turn 차단 (다음 자정까지). 안전 우선."
        case .downgrade: return "한도 초과 시 응답 모드를 ‘최소’로 자동 전환. 비용 절감 + 진행."
        }
    }
}

// MARK: - Phase 3 — 첨부파일

/// **ADR-084 Phase 3** — 첨부파일 처리 정책.
public struct TelegramAttachmentPolicy: Sendable, Codable, Hashable {
    /// 사용자가 보낸 첨부파일 받기 (downloadFile API).
    public var acceptIncoming: Bool
    /// Claude가 만든 파일을 텔레그램으로 전송 (sendDocument API).
    public var sendOutgoing: Bool
    /// 받을 max 크기 (bytes). default 5MB.
    public var maxIncomingSizeBytes: Int
    /// 받을 file type 화이트리스트 (확장자 lowercase, 점 없이). 빈 set이면 모두 허용.
    public var allowedExtensions: Set<String>

    public init(
        acceptIncoming: Bool = true,
        sendOutgoing: Bool = true,
        maxIncomingSizeBytes: Int = 5 * 1024 * 1024,  // 5MB
        allowedExtensions: Set<String> = ["txt", "md", "json", "swift", "ts", "js", "py", "yaml", "toml", "log"]
    ) {
        self.acceptIncoming = acceptIncoming
        self.sendOutgoing = sendOutgoing
        self.maxIncomingSizeBytes = maxIncomingSizeBytes
        self.allowedExtensions = allowedExtensions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.acceptIncoming = try c.decodeIfPresent(Bool.self, forKey: .acceptIncoming) ?? true
        self.sendOutgoing = try c.decodeIfPresent(Bool.self, forKey: .sendOutgoing) ?? true
        self.maxIncomingSizeBytes = try c.decodeIfPresent(Int.self, forKey: .maxIncomingSizeBytes) ?? (5 * 1024 * 1024)
        self.allowedExtensions = try c.decodeIfPresent(Set<String>.self, forKey: .allowedExtensions)
            ?? ["txt", "md", "json", "swift", "ts", "js", "py", "yaml", "toml", "log"]
    }

    /// 파일 확장자가 허용되는지 (whitelist 기반).
    public func isAllowed(filename: String) -> Bool {
        if allowedExtensions.isEmpty { return true }
        let ext = (filename as NSString).pathExtension.lowercased()
        return allowedExtensions.contains(ext)
    }

    /// human-readable max size (e.g., "5 MB").
    public var maxSizeDisplay: String {
        let mb = Double(maxIncomingSizeBytes) / 1_048_576
        if mb >= 1 {
            return String(format: "%.0f MB", mb)
        }
        let kb = Double(maxIncomingSizeBytes) / 1024
        return String(format: "%.0f KB", kb)
    }
}

// MARK: - Phase 4 — Skills & Templates

/// **ADR-084 Phase 4** — 텔레그램 사용자 정의 skill (자주 쓰는 prompt template).
///
/// 사용자가 텔레그램에서 `/{trigger}` 입력 시 `prompt` template으로 확장.
/// 예: trigger="test", prompt="현재 워크스페이스의 모든 테스트를 실행해줘"
public struct TelegramSkill: Sendable, Codable, Hashable, Identifiable {
    public let id: UUID
    /// `/test`, `/리뷰` 등의 trigger (slash 제외).
    public var trigger: String
    /// 사용자 친화적 이름 (메뉴 표시용).
    public var displayName: String
    /// LLM에 전달할 prompt (template — `{args}`로 인자 참조 가능).
    public var prompt: String
    /// SF Symbol 아이콘.
    public var iconName: String
    /// 응답 모드 override (nil = global 설정 사용).
    public var responseMode: TelegramResponseMode?

    public init(
        id: UUID = UUID(),
        trigger: String,
        displayName: String,
        prompt: String,
        iconName: String = "wand.and.stars",
        responseMode: TelegramResponseMode? = nil
    ) {
        self.id = id
        self.trigger = trigger
        self.displayName = displayName
        self.prompt = prompt
        self.iconName = iconName
        self.responseMode = responseMode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.trigger = try c.decode(String.self, forKey: .trigger)
        self.displayName = try c.decode(String.self, forKey: .displayName)
        self.prompt = try c.decode(String.self, forKey: .prompt)
        self.iconName = try c.decodeIfPresent(String.self, forKey: .iconName) ?? "wand.and.stars"
        self.responseMode = try c.decodeIfPresent(TelegramResponseMode.self, forKey: .responseMode)
    }

    /// `/{trigger} {args}` 입력을 prompt + args로 확장.
    public func expand(args: String) -> String {
        if prompt.contains("{args}") {
            return prompt.replacingOccurrences(of: "{args}", with: args)
        }
        return args.isEmpty ? prompt : "\(prompt)\n\n사용자 입력: \(args)"
    }

    /// **default 4개 skills** — 신규 사용자에게 즉시 유용.
    public static let defaults: [TelegramSkill] = [
        TelegramSkill(
            trigger: "test",
            displayName: "테스트 실행",
            prompt: "현재 워크스페이스의 테스트를 실행하고 결과를 알려줘. 실패한 테스트가 있으면 핵심 에러 메시지만 요약.",
            iconName: "checkmark.shield",
            responseMode: .concise
        ),
        TelegramSkill(
            trigger: "review",
            displayName: "코드 리뷰",
            prompt: "최근 변경 (git diff HEAD)을 코드 리뷰해줘. 보안/성능/스타일 관점에서 핵심 이슈만.",
            iconName: "magnifyingglass.circle",
            responseMode: .standard
        ),
        TelegramSkill(
            trigger: "summary",
            displayName: "오늘 작업 요약",
            prompt: "오늘 한 작업을 git log + 변경 파일 기반으로 요약해줘. 한 단락.",
            iconName: "doc.text",
            responseMode: .concise
        ),
        TelegramSkill(
            trigger: "status",
            displayName: "상태 확인",
            prompt: "현재 워크스페이스의 git 상태 (브랜치/변경/upstream)와 진행 중인 작업을 한 눈에 알려줘.",
            iconName: "info.circle",
            responseMode: .minimal
        )
    ]
}
