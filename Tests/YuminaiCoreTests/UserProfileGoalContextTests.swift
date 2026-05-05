import Foundation
import Testing
@testable import YuminaiCore

/// **ADR-107** — GoalContext 모델 + status별 renderHarnessRules 출력 검증.
@Suite("UserProfile GoalContext (ADR-107)")
struct UserProfileGoalContextTests {

    // MARK: - GoalContext 기본값

    @Test("GoalContext.default — 모든 필드 빈 문자열")
    func goalContextDefaultIsEmpty() {
        let ctx = UserProfile.GoalContext.default
        #expect(ctx.targetDeadline.isEmpty)
        #expect(ctx.biggestObstacle.isEmpty)
        #expect(ctx.exploringOptions.isEmpty)
        #expect(ctx.explorationCriteria.isEmpty)
        #expect(ctx.strengths.isEmpty)
        #expect(ctx.interests.isEmpty)
        #expect(ctx.pastExperience.isEmpty)
        #expect(ctx.interestKeywords.isEmpty)
    }

    @Test("GoalContext.default — hasContent == false")
    func goalContextDefaultHasNoContent() {
        #expect(UserProfile.GoalContext.default.hasContent == false)
    }

    @Test("GoalContext — 필드 하나라도 입력 시 hasContent == true")
    func goalContextHasContentWhenAnyFieldSet() {
        var ctx = UserProfile.GoalContext.default
        ctx.interestKeywords = "SwiftUI"
        #expect(ctx.hasContent == true)
    }

    // MARK: - Codable round-trip

    @Test("GoalContext Codable round-trip — 모든 필드 보존")
    func goalContextCodableRoundTrip() throws {
        let original = UserProfile.GoalContext(
            targetDeadline: "2026년 6월",
            biggestObstacle: "시간 부족",
            exploringOptions: "SwiftUI\nReact",
            explorationCriteria: "학습 곡선, 재미",
            strengths: "분석력",
            interests: "영화",
            pastExperience: "5년 iOS 경력",
            interestKeywords: "SwiftUI, AI"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UserProfile.GoalContext.self, from: data)

        #expect(decoded.targetDeadline == original.targetDeadline)
        #expect(decoded.biggestObstacle == original.biggestObstacle)
        #expect(decoded.exploringOptions == original.exploringOptions)
        #expect(decoded.explorationCriteria == original.explorationCriteria)
        #expect(decoded.strengths == original.strengths)
        #expect(decoded.interests == original.interests)
        #expect(decoded.pastExperience == original.pastExperience)
        #expect(decoded.interestKeywords == original.interestKeywords)
    }

    // MARK: - UserProfile backward-compat (goalContext 없는 구 JSON)

    @Test("UserProfile decode without goalContext — .default 적용")
    func userProfileBackwardCompatWithoutGoalContext() throws {
        let oldJSON = """
        {
            "displayName": "김유민",
            "jobTitle": "iOS 개발자",
            "primaryGoal": "앱 만들기",
            "goalStatus": "defined",
            "additionalContext": "",
            "updatedAt": "2024-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let profile = try decoder.decode(UserProfile.self, from: oldJSON)
        #expect(profile.goalContext == UserProfile.GoalContext.default)
        #expect(profile.goalContext.hasContent == false)
    }

    // MARK: - renderHarnessRules — defined 상태

    @Test("renderHarnessRules defined — targetDeadline 입력 시 '목표 시점' 포함")
    func renderDefinedWithDeadline() {
        var ctx = UserProfile.GoalContext.default
        ctx.targetDeadline = "2026년 6월"
        let profile = UserProfile(goalStatus: .defined, goalContext: ctx)
        let rendered = profile.renderHarnessRules()
        #expect(rendered.contains("목표 시점"))
        #expect(rendered.contains("2026년 6월"))
    }

    @Test("renderHarnessRules defined — biggestObstacle 입력 시 '가장 큰 장애물' 포함")
    func renderDefinedWithObstacle() {
        var ctx = UserProfile.GoalContext.default
        ctx.biggestObstacle = "SwiftUI 학습 시간 부족"
        let profile = UserProfile(goalStatus: .defined, goalContext: ctx)
        let rendered = profile.renderHarnessRules()
        #expect(rendered.contains("가장 큰 장애물"))
        #expect(rendered.contains("SwiftUI 학습 시간 부족"))
    }

    @Test("renderHarnessRules defined — 마감일 LLM 가이드 포함")
    func renderDefinedDeadlineLLMGuide() {
        var ctx = UserProfile.GoalContext.default
        ctx.targetDeadline = "3개월 안에"
        let profile = UserProfile(goalStatus: .defined, goalContext: ctx)
        let rendered = profile.renderHarnessRules()
        #expect(rendered.contains("역산"))
    }

    // MARK: - renderHarnessRules — exploring 상태

    @Test("renderHarnessRules exploring — exploringOptions 입력 시 '탐색 중인 옵션' 포함")
    func renderExploringWithOptions() {
        var ctx = UserProfile.GoalContext.default
        ctx.exploringOptions = "SwiftUI\nReact"
        let profile = UserProfile(goalStatus: .exploring, goalContext: ctx)
        let rendered = profile.renderHarnessRules()
        #expect(rendered.contains("탐색 중인 옵션"))
        #expect(rendered.contains("SwiftUI"))
    }

    @Test("renderHarnessRules exploring — explorationCriteria 입력 시 '비교 기준' 포함")
    func renderExploringWithCriteria() {
        var ctx = UserProfile.GoalContext.default
        ctx.explorationCriteria = "학습 곡선, 재미"
        let profile = UserProfile(goalStatus: .exploring, goalContext: ctx)
        let rendered = profile.renderHarnessRules()
        #expect(rendered.contains("비교 기준"))
        #expect(rendered.contains("학습 곡선"))
    }

    // MARK: - renderHarnessRules — undecided 상태

    @Test("renderHarnessRules undecided — strengths 입력 시 '강점' 포함")
    func renderUndecidedWithStrengths() {
        var ctx = UserProfile.GoalContext.default
        ctx.strengths = "분석력, 디자인 감각"
        let profile = UserProfile(goalStatus: .undecided, goalContext: ctx)
        let rendered = profile.renderHarnessRules()
        #expect(rendered.contains("강점"))
        #expect(rendered.contains("분석력"))
    }

    @Test("renderHarnessRules undecided — interests 입력 시 '관심사' 포함")
    func renderUndecidedWithInterests() {
        var ctx = UserProfile.GoalContext.default
        ctx.interests = "영화, 운동"
        let profile = UserProfile(goalStatus: .undecided, goalContext: ctx)
        let rendered = profile.renderHarnessRules()
        #expect(rendered.contains("관심사"))
        #expect(rendered.contains("영화"))
    }

    // MARK: - renderHarnessRules — 공통 키워드

    @Test("renderHarnessRules — interestKeywords 입력 시 '관심 키워드' 섹션 포함")
    func renderWithInterestKeywords() {
        var ctx = UserProfile.GoalContext.default
        ctx.interestKeywords = "SwiftUI, AI, 마케팅"
        let profile = UserProfile(goalStatus: .defined, goalContext: ctx)
        let rendered = profile.renderHarnessRules()
        #expect(rendered.contains("관심 키워드"))
        #expect(rendered.contains("SwiftUI, AI, 마케팅"))
    }

    @Test("renderHarnessRules — interestKeywords 비어있으면 '관심 키워드' 섹션 미출력")
    func renderWithoutInterestKeywords() {
        let profile = UserProfile(goalStatus: .defined, goalContext: .default)
        let rendered = profile.renderHarnessRules()
        #expect(!rendered.contains("관심 키워드"))
    }

    // MARK: - renderHarnessRules — 빈 GoalContext

    @Test("renderHarnessRules defined — GoalContext 비어있으면 '목표 상세' 섹션 미출력")
    func renderDefinedEmptyContextNoSection() {
        let profile = UserProfile(goalStatus: .defined, goalContext: .default)
        let rendered = profile.renderHarnessRules()
        #expect(!rendered.contains("목표 상세"))
    }

    @Test("renderHarnessRules exploring — GoalContext 비어있으면 '목표 상세' 섹션 미출력")
    func renderExploringEmptyContextNoSection() {
        let profile = UserProfile(goalStatus: .exploring, goalContext: .default)
        let rendered = profile.renderHarnessRules()
        #expect(!rendered.contains("목표 상세"))
    }

    @Test("renderHarnessRules undecided — GoalContext 비어있으면 '목표 상세' 섹션 미출력")
    func renderUndecidedEmptyContextNoSection() {
        let profile = UserProfile(goalStatus: .undecided, goalContext: .default)
        let rendered = profile.renderHarnessRules()
        #expect(!rendered.contains("목표 상세"))
    }

    // MARK: - 상태별 격리: exploring 필드가 defined에서 미출력

    @Test("renderHarnessRules defined — exploring 전용 필드(탐색 중인 옵션) 미출력")
    func renderDefinedDoesNotIncludeExploringFields() {
        var ctx = UserProfile.GoalContext.default
        ctx.exploringOptions = "React, SwiftUI"
        ctx.targetDeadline = "6월"
        let profile = UserProfile(goalStatus: .defined, goalContext: ctx)
        let rendered = profile.renderHarnessRules()
        // exploring 필드는 defined 상태에서 출력 안 됨
        #expect(!rendered.contains("탐색 중인 옵션"))
        // defined 필드는 출력됨
        #expect(rendered.contains("목표 시점"))
    }

    @Test("renderHarnessRules exploring — defined 전용 필드(목표 시점) 미출력")
    func renderExploringDoesNotIncludeDefinedFields() {
        var ctx = UserProfile.GoalContext.default
        ctx.targetDeadline = "3개월 안에"
        ctx.exploringOptions = "React"
        let profile = UserProfile(goalStatus: .exploring, goalContext: ctx)
        let rendered = profile.renderHarnessRules()
        // defined 필드는 exploring 상태에서 출력 안 됨
        #expect(!rendered.contains("목표 시점"))
        // exploring 필드는 출력됨
        #expect(rendered.contains("탐색 중인 옵션"))
    }
}
