import Foundation

/// **ADR-108-B** — UserProfileSheet 섹션 완성도 계산 헬퍼.
///
/// UI와 분리하여 testable한 순수 함수 헬퍼.
/// UserProfileSheet.completionState 프로퍼티가 이 헬퍼를 호출한다.
public enum UserProfileSection: String, CaseIterable, Sendable {
    case basic       = "기본 정보"
    case job         = "직업과 하고 싶은 것"
    case goalStatus  = "목표 상태"
    case preferences = "선호 설정"
}

/// 각 섹션의 완성도 상태.
public struct UserProfileCompletionState: Sendable {
    /// 완성된 섹션 집합
    public let completedSections: Set<UserProfileSection>

    /// 완성 안 된 섹션 수
    public var incompleteCount: Int {
        UserProfileSection.allCases.count - completedSections.count
    }

    /// 특정 섹션이 완료됐는지.
    public func isComplete(section: UserProfileSection) -> Bool {
        completedSections.contains(section)
    }
}

public enum UserProfileCompletionHelper {

    /// 각 섹션의 완성도를 계산한다.
    ///
    /// - 기본 정보: displayName이 입력됨
    /// - 직업/목표: jobTitle 또는 primaryGoal 중 하나 입력
    /// - 목표 상태: GoalContext에 하나 이상 입력
    /// - 선호 설정: additionalContext 입력 또는 preferredAgent 선택
    public static func completionState(
        displayName: String,
        jobTitle: String,
        primaryGoal: String,
        goalContext: UserProfile.GoalContext,
        additionalContext: String,
        preferredAgent: AgentKind?
    ) -> UserProfileCompletionState {
        var completed = Set<UserProfileSection>()

        if !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            completed.insert(.basic)
        }

        let jobFilled = !jobTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let goalFilled = !primaryGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if jobFilled || goalFilled {
            completed.insert(.job)
        }

        if goalContext.hasContent {
            completed.insert(.goalStatus)
        }

        let ctxFilled = !additionalContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if ctxFilled || preferredAgent != nil {
            completed.insert(.preferences)
        }

        return UserProfileCompletionState(completedSections: completed)
    }
}
