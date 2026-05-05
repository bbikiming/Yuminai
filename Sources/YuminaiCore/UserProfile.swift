import Foundation

/// **ADR-106** — 사용자 프로필. 이름·직업·목표 등을 저장하고, .harness/rules/USER_PROFILE.md에 자동 주입한다.
/// **ADR-107** — GoalContext 추가: 목표 상태별 세부 컨텍스트를 수집해 하네스에 더 풍부한 가이드를 주입.
public struct UserProfile: Sendable, Codable, Hashable {

    // MARK: - GoalStatus

    public enum GoalStatus: String, Sendable, Codable, CaseIterable, Identifiable {
        case defined    // 이미 분명한 목표가 있음
        case exploring  // 여러 가지를 탐색 중
        case undecided  // 아직 정하지 않음

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .defined:   return "이미 분명한 목표가 있어요"
            case .exploring: return "여러 가지를 탐색 중이에요"
            case .undecided: return "아직 정하지 않았어요"
            }
        }

        public var subtitle: String {
            switch self {
            case .defined:   return "목표가 명확하니 바로 실행해 드릴게요"
            case .exploring: return "여러 선택지와 트레이드오프를 함께 살펴볼게요"
            case .undecided: return "흥미와 강점을 함께 탐색하고 작은 시도부터 제안할게요"
            }
        }

        public var icon: String {
            switch self {
            case .defined:   return "scope"
            case .exploring: return "map.fill"
            case .undecided: return "questionmark.circle.fill"
            }
        }

        /// LLM 응답 가이드 (시스템 프롬프트 주입용).
        var llmGuide: String {
            switch self {
            case .defined:
                return "사용자는 명확한 목표가 있어요. 답변은 직접적이고 행동 지향적으로."
            case .exploring:
                return "사용자는 여러 옵션을 비교 중이에요. 트레이드오프와 선택지를 제시하세요."
            case .undecided:
                return "사용자는 아직 무엇을 할지 정하지 않았어요. 먼저 흥미와 강점을 함께 탐색하고, 작은 시도부터 제안하세요."
            }
        }
    }

    // MARK: - GoalContext (ADR-107)

    /// 목표 상태별 추가 컨텍스트. 상태마다 다른 필드를 활성화해 LLM 가이드를 강화한다.
    public struct GoalContext: Sendable, Codable, Hashable {
        // defined 전용
        /// 마감/목표 시점 (자유 입력). 예: "2026년 6월", "3개월 안에"
        public var targetDeadline: String
        /// 가장 큰 장애물. 예: "시간 부족", "기술 학습 필요"
        public var biggestObstacle: String

        // exploring 전용
        /// 탐색 중인 옵션들 (한 줄에 하나)
        public var exploringOptions: String
        /// 비교 기준. 예: "학습 곡선, 시장 수요, 재미"
        public var explorationCriteria: String

        // undecided 전용
        /// 강점/잘하는 것. 예: "분석, 디자인 감각, 글쓰기"
        public var strengths: String
        /// 관심사/즐거운 것. 예: "영화, 운동, 새로운 기술"
        public var interests: String
        /// 이전 경험 (간단한 자기소개)
        public var pastExperience: String

        // 공통 (모든 status)
        /// 관심 키워드 (콤마 구분). 예: "SwiftUI, AI, 마케팅"
        public var interestKeywords: String

        public init(
            targetDeadline: String = "",
            biggestObstacle: String = "",
            exploringOptions: String = "",
            explorationCriteria: String = "",
            strengths: String = "",
            interests: String = "",
            pastExperience: String = "",
            interestKeywords: String = ""
        ) {
            self.targetDeadline = targetDeadline
            self.biggestObstacle = biggestObstacle
            self.exploringOptions = exploringOptions
            self.explorationCriteria = explorationCriteria
            self.strengths = strengths
            self.interests = interests
            self.pastExperience = pastExperience
            self.interestKeywords = interestKeywords
        }

        public static let `default` = GoalContext()

        /// 입력된 필드가 하나라도 있으면 true.
        public var hasContent: Bool {
            [targetDeadline, biggestObstacle, exploringOptions, explorationCriteria,
             strengths, interests, pastExperience, interestKeywords]
                .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }

    // MARK: - 프로퍼티

    /// 표시 이름 (default: "yuminai")
    public var displayName: String
    /// 직업 (예: "iOS 개발자")
    public var jobTitle: String
    /// 주로 하고 싶은 것 (예: "iOS 앱 만들기")
    public var primaryGoal: String
    /// 목표 상태 (정해짐 / 탐색 중 / 미정)
    public var goalStatus: GoalStatus
    /// 목표 상태별 추가 컨텍스트 (ADR-107)
    public var goalContext: GoalContext
    /// 선호 에이전트 (nil = 자동)
    public var preferredAgent: AgentKind?
    /// 자유 메모 (LLM에 추가 컨텍스트)
    public var additionalContext: String
    /// 프로필 이미지 파일 경로 (선택)
    public var profileImagePath: String?
    /// 마지막 갱신 시각
    public var updatedAt: Date

    // MARK: - 초기화

    public init(
        displayName: String = "yuminai",
        jobTitle: String = "",
        primaryGoal: String = "",
        goalStatus: GoalStatus = .undecided,
        goalContext: GoalContext = .default,
        preferredAgent: AgentKind? = nil,
        additionalContext: String = "",
        profileImagePath: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.displayName = displayName
        self.jobTitle = jobTitle
        self.primaryGoal = primaryGoal
        self.goalStatus = goalStatus
        self.goalContext = goalContext
        self.preferredAgent = preferredAgent
        self.additionalContext = additionalContext
        self.profileImagePath = profileImagePath
        self.updatedAt = updatedAt
    }

    // MARK: - Codable (backward-compat)

    private enum CodingKeys: String, CodingKey {
        case displayName, jobTitle, primaryGoal, goalStatus, goalContext
        case preferredAgent, additionalContext, profileImagePath, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? "yuminai"
        jobTitle = try c.decodeIfPresent(String.self, forKey: .jobTitle) ?? ""
        primaryGoal = try c.decodeIfPresent(String.self, forKey: .primaryGoal) ?? ""
        goalStatus = try c.decodeIfPresent(GoalStatus.self, forKey: .goalStatus) ?? .undecided
        goalContext = try c.decodeIfPresent(GoalContext.self, forKey: .goalContext) ?? .default
        preferredAgent = try c.decodeIfPresent(AgentKind.self, forKey: .preferredAgent)
        additionalContext = try c.decodeIfPresent(String.self, forKey: .additionalContext) ?? ""
        profileImagePath = try c.decodeIfPresent(String.self, forKey: .profileImagePath)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    /// 기본값 (프로필을 한 번도 입력하지 않은 상태).
    public static let `default` = UserProfile()

    // MARK: - 헬퍼

    /// 프로필이 비어있는지 (사용자가 한 번도 입력하지 않은 상태).
    public var isEmpty: Bool {
        jobTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && primaryGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && additionalContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && profileImagePath == nil
    }

    // MARK: - ADR-108: LLM system prompt 주입용 렌더링

    /// LLM system prompt에 inject할 컴팩트 한 문단 (cache 친화적).
    /// - 모든 실질 필드가 비어있으면 nil 반환 (주입 불필요).
    /// - 필드 순서는 결정적 (항상 동일) → Anthropic prompt cache key 안정화.
    /// - 200자 이내 권장.
    public func renderForSystemPrompt() -> String? {
        guard !isEmpty else { return nil }

        var parts: [String] = []

        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty && name != "yuminai" {
            parts.append("이름: \(name)")
        }

        let job = jobTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !job.isEmpty {
            parts.append("직업: \(job)")
        }

        let goal = primaryGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        if !goal.isEmpty {
            parts.append("목표: \(goal)")
        }

        parts.append("상태: \(goalStatus.displayName)")

        let ctx = additionalContext.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ctx.isEmpty {
            // 추가 컨텍스트는 앞 60자만 포함 (200자 한도 내)
            let truncated = ctx.count > 60 ? String(ctx.prefix(60)) + "…" : ctx
            parts.append("메모: \(truncated)")
        }

        let joined = "[사용자 프로필] " + parts.joined(separator: " · ")
        // 200자 초과 시 말줄임 처리
        if joined.count > 200 {
            return String(joined.prefix(197)) + "…"
        }
        return joined
    }

    /// CLAUDE.md marker 섹션 내에 들어갈 본문 (## 사용자 프로필 이하).
    /// CLAUDEMdMerger가 begin/end marker 사이에 이 내용을 삽입한다.
    public func renderForCLAUDEMd() -> String {
        let jobLine = jobTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let goalLine = primaryGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        let ctxLine = additionalContext.trimmingCharacters(in: .whitespacesAndNewlines)

        var lines: [String] = [
            "> 이 섹션은 Yuminai가 자동으로 동기화해요. 직접 편집하면 다음 갱신 시 덮어쓰기됩니다.",
            "",
            "## 사용자 프로필",
            "- 이름: \(displayName)",
        ]

        if !jobLine.isEmpty {
            lines.append("- 직업: \(jobLine)")
        }
        if !goalLine.isEmpty {
            lines.append("- 주로 하고 싶은 것: \(goalLine)")
        }
        lines.append("- 목표 상태: \(goalStatus.displayName)")

        if !ctxLine.isEmpty {
            lines.append("")
            lines.append("## 추가 컨텍스트")
            lines.append(ctxLine)
        }

        lines.append("")
        lines.append("## 응답 가이드")
        lines.append(goalStatus.llmGuide)

        return lines.joined(separator: "\n")
    }

    // MARK: - 하네스 주입 렌더링

    /// .harness/rules/USER_PROFILE.md에 기록할 마크다운 포맷.
    /// ADR-107: goalContext 필드를 목표 상태별로 다르게 출력한다 (빈 필드 제외).
    public func renderHarnessRules() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let updatedStr = formatter.string(from: updatedAt)

        let jobLine = jobTitle.isEmpty ? "(미입력)" : jobTitle
        let goalLine = primaryGoal.isEmpty ? "(미입력)" : primaryGoal
        let contextSection = additionalContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "(없음)"
            : additionalContext.trimmingCharacters(in: .whitespacesAndNewlines)

        var parts: [String] = []

        parts.append("""
        # 사용자 프로필

        > 이 파일은 Yuminai가 사용자 정보를 자동으로 동기화한 것입니다.
        > 사용자가 좌측 하단 프로필 카드에서 정보를 변경하면 모든 워크스페이스에 갱신됩니다.

        ## 기본 정보
        - **이름**: \(displayName)
        - **직업**: \(jobLine)

        ## 목표
        - **주로 하고 싶은 것**: \(goalLine)
        - **목표 상태**: \(goalStatus.displayName) — \(goalStatus.subtitle)
        """)

        // 목표 상태별 추가 컨텍스트 섹션
        let goalContextSection = renderGoalContextSection()
        if !goalContextSection.isEmpty {
            parts.append(goalContextSection)
        }

        // 공통: 관심 키워드
        let keywords = goalContext.interestKeywords.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keywords.isEmpty {
            parts.append("## 관심 키워드\n\(keywords)")
        }

        parts.append("""
        ## 응답 가이드 (LLM에게)
        \(goalStatus.llmGuide)
        \(renderLLMContextGuide())

        ## 추가 컨텍스트
        \(contextSection)

        ---
        *Last updated: \(updatedStr)*
        """)

        return parts.joined(separator: "\n\n")
    }

    /// 목표 상태별 추가 컨텍스트 섹션 (빈 필드 제외).
    private func renderGoalContextSection() -> String {
        var lines: [String] = []

        switch goalStatus {
        case .defined:
            let deadline = goalContext.targetDeadline.trimmingCharacters(in: .whitespacesAndNewlines)
            let obstacle = goalContext.biggestObstacle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !deadline.isEmpty { lines.append("- **목표 시점**: \(deadline)") }
            if !obstacle.isEmpty { lines.append("- **현재 가장 큰 장애물**: \(obstacle)") }

        case .exploring:
            let options = goalContext.exploringOptions.trimmingCharacters(in: .whitespacesAndNewlines)
            let criteria = goalContext.explorationCriteria.trimmingCharacters(in: .whitespacesAndNewlines)
            if !options.isEmpty { lines.append("- **탐색 중인 옵션들**:\n\(options)") }
            if !criteria.isEmpty { lines.append("- **비교 기준**: \(criteria)") }

        case .undecided:
            let strengths = goalContext.strengths.trimmingCharacters(in: .whitespacesAndNewlines)
            let interests = goalContext.interests.trimmingCharacters(in: .whitespacesAndNewlines)
            let experience = goalContext.pastExperience.trimmingCharacters(in: .whitespacesAndNewlines)
            if !strengths.isEmpty { lines.append("- **강점/잘하는 것**: \(strengths)") }
            if !interests.isEmpty { lines.append("- **관심사**: \(interests)") }
            if !experience.isEmpty { lines.append("- **이전 경험**:\n\(experience)") }
        }

        guard !lines.isEmpty else { return "" }
        return "## 목표 상세\n" + lines.joined(separator: "\n")
    }

    /// 목표 상태 + GoalContext를 반영한 LLM 응답 가이드 추가 텍스트.
    private func renderLLMContextGuide() -> String {
        var hints: [String] = []

        switch goalStatus {
        case .defined:
            let deadline = goalContext.targetDeadline.trimmingCharacters(in: .whitespacesAndNewlines)
            let obstacle = goalContext.biggestObstacle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !deadline.isEmpty {
                hints.append("- 마감일(\(deadline))을 역산해서 우선순위를 제안하세요.")
            }
            if !obstacle.isEmpty {
                hints.append("- '\(obstacle)'이 가장 큰 장애물입니다. 이를 해소하는 실전 팁을 우선 제공하세요.")
            }

        case .exploring:
            let criteria = goalContext.explorationCriteria.trimmingCharacters(in: .whitespacesAndNewlines)
            if !criteria.isEmpty {
                hints.append("- 비교 기준('\(criteria)')에 맞춰 각 옵션의 트레이드오프를 정리해 주세요.")
            }
            hints.append("- 여러 선택지를 표나 비교 목록으로 정리하면 좋아요.")

        case .undecided:
            let strengths = goalContext.strengths.trimmingCharacters(in: .whitespacesAndNewlines)
            let interests = goalContext.interests.trimmingCharacters(in: .whitespacesAndNewlines)
            if !strengths.isEmpty || !interests.isEmpty {
                hints.append("- 강점(\(strengths.isEmpty ? "미입력" : strengths))과 관심사(\(interests.isEmpty ? "미입력" : interests))를 토대로 작은 첫 시도를 제안하세요.")
            }
            hints.append("- 큰 결정보다 '오늘 당장 해볼 수 있는 것'을 먼저 제시하세요.")
        }

        guard !hints.isEmpty else { return "" }
        return hints.joined(separator: "\n")
    }
}
