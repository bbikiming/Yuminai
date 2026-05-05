import Foundation

/// **ADR-106** — 사용자 프로필. 이름·직업·목표 등을 저장하고, .harness/rules/USER_PROFILE.md에 자동 주입한다.
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

    // MARK: - 프로퍼티

    /// 표시 이름 (default: "yuminai")
    public var displayName: String
    /// 직업 (예: "iOS 개발자")
    public var jobTitle: String
    /// 주로 하고 싶은 것 (예: "iOS 앱 만들기")
    public var primaryGoal: String
    /// 목표 상태 (정해짐 / 탐색 중 / 미정)
    public var goalStatus: GoalStatus
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
        preferredAgent: AgentKind? = nil,
        additionalContext: String = "",
        profileImagePath: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.displayName = displayName
        self.jobTitle = jobTitle
        self.primaryGoal = primaryGoal
        self.goalStatus = goalStatus
        self.preferredAgent = preferredAgent
        self.additionalContext = additionalContext
        self.profileImagePath = profileImagePath
        self.updatedAt = updatedAt
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

    // MARK: - 하네스 주입 렌더링

    /// .harness/rules/USER_PROFILE.md에 기록할 마크다운 포맷.
    public func renderHarnessRules() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let updatedStr = formatter.string(from: updatedAt)

        let jobLine = jobTitle.isEmpty ? "(미입력)" : jobTitle
        let goalLine = primaryGoal.isEmpty ? "(미입력)" : primaryGoal
        let contextSection = additionalContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "(없음)"
            : additionalContext.trimmingCharacters(in: .whitespacesAndNewlines)

        return """
        # 사용자 프로필

        > 이 파일은 Yuminai가 사용자 정보를 자동으로 동기화한 것입니다.
        > 사용자가 좌측 하단 프로필 카드에서 정보를 변경하면 모든 워크스페이스에 갱신됩니다.

        ## 기본 정보
        - **이름**: \(displayName)
        - **직업**: \(jobLine)

        ## 목표
        - **주로 하고 싶은 것**: \(goalLine)
        - **목표 상태**: \(goalStatus.displayName) — \(goalStatus.subtitle)

        ## 응답 가이드 (LLM에게)
        \(goalStatus.llmGuide)

        ## 추가 컨텍스트
        \(contextSection)

        ---
        *Last updated: \(updatedStr)*
        """
    }
}
