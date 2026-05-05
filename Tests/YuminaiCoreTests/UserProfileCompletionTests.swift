import Foundation
import Testing
@testable import YuminaiCore

@Suite("UserProfileCompletionHelper (ADR-108-B)")
struct UserProfileCompletionHelperTests {

    // MARK: - 기본 정보 섹션

    @Test("displayName 입력 시 basic 섹션 완료")
    func basicCompletedWhenDisplayNameFilled() {
        let state = UserProfileCompletionHelper.completionState(
            displayName: "김유민",
            jobTitle: "",
            primaryGoal: "",
            goalContext: .default,
            additionalContext: "",
            preferredAgent: nil
        )
        #expect(state.isComplete(section: .basic) == true)
    }

    @Test("displayName 비어있으면 basic 섹션 미완료")
    func basicIncompleteWhenDisplayNameEmpty() {
        let state = UserProfileCompletionHelper.completionState(
            displayName: "   ",
            jobTitle: "개발자",
            primaryGoal: "",
            goalContext: .default,
            additionalContext: "",
            preferredAgent: nil
        )
        #expect(state.isComplete(section: .basic) == false)
    }

    // MARK: - 직업/목표 섹션

    @Test("jobTitle 입력 시 job 섹션 완료")
    func jobCompletedWhenJobTitleFilled() {
        let state = UserProfileCompletionHelper.completionState(
            displayName: "",
            jobTitle: "iOS 개발자",
            primaryGoal: "",
            goalContext: .default,
            additionalContext: "",
            preferredAgent: nil
        )
        #expect(state.isComplete(section: .job) == true)
    }

    @Test("primaryGoal 입력 시 job 섹션 완료")
    func jobCompletedWhenPrimaryGoalFilled() {
        let state = UserProfileCompletionHelper.completionState(
            displayName: "",
            jobTitle: "",
            primaryGoal: "앱 만들기",
            goalContext: .default,
            additionalContext: "",
            preferredAgent: nil
        )
        #expect(state.isComplete(section: .job) == true)
    }

    @Test("jobTitle + primaryGoal 모두 비어있으면 job 섹션 미완료")
    func jobIncompleteWhenBothEmpty() {
        let state = UserProfileCompletionHelper.completionState(
            displayName: "이름",
            jobTitle: "",
            primaryGoal: "",
            goalContext: .default,
            additionalContext: "",
            preferredAgent: nil
        )
        #expect(state.isComplete(section: .job) == false)
    }

    // MARK: - 목표 상태 섹션

    @Test("GoalContext에 키워드 입력 시 goalStatus 섹션 완료")
    func goalStatusCompletedWhenContextHasContent() {
        var ctx = UserProfile.GoalContext.default
        ctx.interestKeywords = "SwiftUI"
        let state = UserProfileCompletionHelper.completionState(
            displayName: "",
            jobTitle: "",
            primaryGoal: "",
            goalContext: ctx,
            additionalContext: "",
            preferredAgent: nil
        )
        #expect(state.isComplete(section: .goalStatus) == true)
    }

    @Test("GoalContext가 모두 비어있으면 goalStatus 섹션 미완료")
    func goalStatusIncompleteWhenContextEmpty() {
        let state = UserProfileCompletionHelper.completionState(
            displayName: "이름",
            jobTitle: "개발자",
            primaryGoal: "앱",
            goalContext: .default,
            additionalContext: "",
            preferredAgent: nil
        )
        #expect(state.isComplete(section: .goalStatus) == false)
    }

    // MARK: - 선호 설정 섹션

    @Test("additionalContext 입력 시 preferences 섹션 완료")
    func preferencesCompletedWhenContextFilled() {
        let state = UserProfileCompletionHelper.completionState(
            displayName: "",
            jobTitle: "",
            primaryGoal: "",
            goalContext: .default,
            additionalContext: "Swift 5년차",
            preferredAgent: nil
        )
        #expect(state.isComplete(section: .preferences) == true)
    }

    @Test("preferredAgent 선택 시 preferences 섹션 완료")
    func preferencesCompletedWhenAgentSelected() {
        let state = UserProfileCompletionHelper.completionState(
            displayName: "",
            jobTitle: "",
            primaryGoal: "",
            goalContext: .default,
            additionalContext: "",
            preferredAgent: .claude
        )
        #expect(state.isComplete(section: .preferences) == true)
    }

    @Test("additionalContext + preferredAgent 모두 없으면 preferences 미완료")
    func preferencesIncompleteWhenBothEmpty() {
        let state = UserProfileCompletionHelper.completionState(
            displayName: "이름",
            jobTitle: "개발자",
            primaryGoal: "앱",
            goalContext: .default,
            additionalContext: "   ",
            preferredAgent: nil
        )
        #expect(state.isComplete(section: .preferences) == false)
    }

    // MARK: - incompleteCount

    @Test("모든 섹션 미완료 시 incompleteCount == 4")
    func allIncompleteCount() {
        let state = UserProfileCompletionHelper.completionState(
            displayName: "",
            jobTitle: "",
            primaryGoal: "",
            goalContext: .default,
            additionalContext: "",
            preferredAgent: nil
        )
        #expect(state.incompleteCount == 4)
    }

    @Test("모든 섹션 완료 시 incompleteCount == 0")
    func allCompleteCount() {
        var ctx = UserProfile.GoalContext.default
        ctx.interestKeywords = "Swift"
        let state = UserProfileCompletionHelper.completionState(
            displayName: "김유민",
            jobTitle: "개발자",
            primaryGoal: "",
            goalContext: ctx,
            additionalContext: "메모",
            preferredAgent: nil
        )
        #expect(state.incompleteCount == 0)
    }
}
