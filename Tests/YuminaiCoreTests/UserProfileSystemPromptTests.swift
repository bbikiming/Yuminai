import Foundation
import Testing
@testable import YuminaiCore

/// **ADR-108** — UserProfile.renderForSystemPrompt() + renderForCLAUDEMd() 검증.
@Suite("UserProfile ADR-108 System Prompt Injection")
struct UserProfileSystemPromptTests {

    // MARK: - renderForSystemPrompt: nil 반환 조건

    @Test("isEmpty 프로필 — renderForSystemPrompt() nil 반환")
    func emptyProfileReturnsNil() {
        let profile = UserProfile.default
        #expect(profile.renderForSystemPrompt() == nil)
    }

    @Test("displayName만 'yuminai' — renderForSystemPrompt() nil 반환 (실질 필드 없음)")
    func defaultDisplayNameOnlyReturnsNil() {
        let profile = UserProfile(displayName: "yuminai")
        #expect(profile.renderForSystemPrompt() == nil)
    }

    // MARK: - renderForSystemPrompt: 실질 필드별 포함 여부

    @Test("jobTitle 입력 시 직업 포함")
    func includesJobTitle() {
        let profile = UserProfile(jobTitle: "iOS 개발자")
        let result = profile.renderForSystemPrompt()
        #expect(result != nil)
        #expect(result!.contains("iOS 개발자"))
        #expect(result!.contains("직업:"))
    }

    @Test("primaryGoal 입력 시 목표 포함")
    func includesPrimaryGoal() {
        let profile = UserProfile(primaryGoal: "앱 만들기")
        let result = profile.renderForSystemPrompt()
        #expect(result != nil)
        #expect(result!.contains("앱 만들기"))
        #expect(result!.contains("목표:"))
    }

    @Test("goalStatus displayName 항상 포함 (실질 필드가 있는 경우)")
    func includesGoalStatusWhenNonEmpty() {
        for status in UserProfile.GoalStatus.allCases {
            let profile = UserProfile(jobTitle: "개발자", goalStatus: status)
            let result = profile.renderForSystemPrompt()
            #expect(result != nil)
            #expect(result!.contains(status.displayName))
        }
    }

    @Test("비 'yuminai' 표시 이름 포함")
    func includesCustomDisplayName() {
        let profile = UserProfile(displayName: "김유민", jobTitle: "개발자")
        let result = profile.renderForSystemPrompt()
        #expect(result != nil)
        #expect(result!.contains("김유민"))
        #expect(result!.contains("이름:"))
    }

    @Test("[사용자 프로필] 접두사 포함")
    func hasProfilePrefix() {
        let profile = UserProfile(jobTitle: "개발자")
        let result = profile.renderForSystemPrompt()
        #expect(result!.hasPrefix("[사용자 프로필]"))
    }

    // MARK: - renderForSystemPrompt: 200자 제한

    @Test("결과는 200자 이내")
    func resultIsWithin200Chars() {
        let profile = UserProfile(
            displayName: "가나다라마바사아자차카타파하가나다라마바사아자차카타파하",
            jobTitle: "가나다라마바사아자차카타파하 iOS SwiftUI Combine MVVM Clean Architecture 개발자",
            primaryGoal: "가나다라마바사아자차카타파하 앱 만들기 SwiftUI 완전 정복",
            additionalContext: "가나다라마바사아자차카타파하 추가 컨텍스트 어쩌구저쩌구"
        )
        let result = profile.renderForSystemPrompt()
        #expect(result != nil)
        #expect(result!.count <= 200)
    }

    @Test("짧은 프로필은 200자 미만 — 말줄임 없음")
    func shortProfileNoTruncation() {
        let profile = UserProfile(jobTitle: "개발자", primaryGoal: "앱 만들기")
        let result = profile.renderForSystemPrompt()
        #expect(result != nil)
        #expect(!result!.hasSuffix("…") || result!.count < 200)
    }

    // MARK: - renderForSystemPrompt: 결정적 ordering (cache 친화적)

    @Test("같은 프로필로 호출 시 동일 문자열 반환 (결정적)")
    func deterministicOutput() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let profile = UserProfile(
            displayName: "김유민",
            jobTitle: "iOS 개발자",
            primaryGoal: "앱 만들기",
            goalStatus: .defined,
            updatedAt: date
        )
        let result1 = profile.renderForSystemPrompt()
        let result2 = profile.renderForSystemPrompt()
        #expect(result1 == result2)
    }

    // MARK: - renderForCLAUDEMd

    @Test("renderForCLAUDEMd — 이름 포함")
    func claudeMdIncludesName() {
        let profile = UserProfile(displayName: "김유민", jobTitle: "iOS 개발자")
        let result = profile.renderForCLAUDEMd()
        #expect(result.contains("김유민"))
    }

    @Test("renderForCLAUDEMd — 직업 포함")
    func claudeMdIncludesJob() {
        let profile = UserProfile(jobTitle: "iOS 개발자")
        let result = profile.renderForCLAUDEMd()
        #expect(result.contains("iOS 개발자"))
    }

    @Test("renderForCLAUDEMd — goalStatus displayName 포함")
    func claudeMdIncludesGoalStatus() {
        let profile = UserProfile(jobTitle: "개발자", goalStatus: .exploring)
        let result = profile.renderForCLAUDEMd()
        #expect(result.contains(UserProfile.GoalStatus.exploring.displayName))
    }

    @Test("renderForCLAUDEMd — 자동 동기화 안내 문구 포함")
    func claudeMdHasAutoSyncNotice() {
        let profile = UserProfile(jobTitle: "개발자")
        let result = profile.renderForCLAUDEMd()
        #expect(result.contains("Yuminai가 자동으로 동기화"))
    }

    @Test("renderForCLAUDEMd — 응답 가이드 포함")
    func claudeMdHasResponseGuide() {
        let profile = UserProfile(jobTitle: "개발자", goalStatus: .defined)
        let result = profile.renderForCLAUDEMd()
        #expect(result.contains("응답 가이드"))
    }

    @Test("renderForCLAUDEMd — additionalContext 비어있으면 추가 컨텍스트 섹션 미출력")
    func claudeMdNoAdditionalContextSection() {
        let profile = UserProfile(jobTitle: "개발자", additionalContext: "")
        let result = profile.renderForCLAUDEMd()
        #expect(!result.contains("추가 컨텍스트"))
    }

    @Test("renderForCLAUDEMd — additionalContext 있으면 추가 컨텍스트 섹션 출력")
    func claudeMdHasAdditionalContext() {
        let profile = UserProfile(jobTitle: "개발자", additionalContext: "Swift 5년차")
        let result = profile.renderForCLAUDEMd()
        #expect(result.contains("추가 컨텍스트"))
        #expect(result.contains("Swift 5년차"))
    }
}
