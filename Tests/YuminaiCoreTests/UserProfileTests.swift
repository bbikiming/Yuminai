import Foundation
import Testing
@testable import YuminaiCore

@Suite("UserProfile (ADR-106)")
struct UserProfileTests {

    // MARK: - 기본값 + isEmpty

    @Test("default 프로필은 isEmpty == true")
    func defaultProfileIsEmpty() {
        let profile = UserProfile.default
        #expect(profile.isEmpty == true)
    }

    @Test("displayName만 있는 경우 isEmpty == true (직업/목표가 비어있으므로)")
    func displayNameOnlyIsEmpty() {
        let profile = UserProfile(displayName: "김유민")
        #expect(profile.isEmpty == true)
    }

    @Test("jobTitle 입력 시 isEmpty == false")
    func jobTitleMakesNotEmpty() {
        let profile = UserProfile(jobTitle: "iOS 개발자")
        #expect(profile.isEmpty == false)
    }

    @Test("primaryGoal 입력 시 isEmpty == false")
    func primaryGoalMakesNotEmpty() {
        let profile = UserProfile(primaryGoal: "앱 만들기")
        #expect(profile.isEmpty == false)
    }

    @Test("additionalContext 입력 시 isEmpty == false")
    func additionalContextMakesNotEmpty() {
        let profile = UserProfile(additionalContext: "Swift 5년차")
        #expect(profile.isEmpty == false)
    }

    @Test("profileImagePath 있으면 isEmpty == false")
    func profileImagePathMakesNotEmpty() {
        let profile = UserProfile(profileImagePath: "/some/path.jpg")
        #expect(profile.isEmpty == false)
    }

    // MARK: - GoalStatus 모든 케이스

    @Test("GoalStatus.defined — displayName/subtitle/icon 정의됨")
    func definedStatusProperties() {
        let s = UserProfile.GoalStatus.defined
        #expect(!s.displayName.isEmpty)
        #expect(!s.subtitle.isEmpty)
        #expect(!s.icon.isEmpty)
    }

    @Test("GoalStatus.exploring — displayName/subtitle/icon 정의됨")
    func exploringStatusProperties() {
        let s = UserProfile.GoalStatus.exploring
        #expect(!s.displayName.isEmpty)
        #expect(!s.subtitle.isEmpty)
        #expect(!s.icon.isEmpty)
    }

    @Test("GoalStatus.undecided — displayName/subtitle/icon 정의됨")
    func undecidedStatusProperties() {
        let s = UserProfile.GoalStatus.undecided
        #expect(!s.displayName.isEmpty)
        #expect(!s.subtitle.isEmpty)
        #expect(!s.icon.isEmpty)
    }

    @Test("GoalStatus.id == rawValue")
    func goalStatusId() {
        for status in UserProfile.GoalStatus.allCases {
            #expect(status.id == status.rawValue)
        }
    }

    // MARK: - Codable round-trip

    @Test("Codable round-trip — 모든 필드 보존")
    func codableRoundTrip() throws {
        let original = UserProfile(
            displayName: "김유민",
            jobTitle: "iOS 개발자",
            primaryGoal: "앱 만들기",
            goalStatus: .exploring,
            preferredAgent: .claude,
            additionalContext: "Swift 5년차",
            profileImagePath: "/some/path.jpg",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: data)

        #expect(decoded.displayName == original.displayName)
        #expect(decoded.jobTitle == original.jobTitle)
        #expect(decoded.primaryGoal == original.primaryGoal)
        #expect(decoded.goalStatus == original.goalStatus)
        #expect(decoded.preferredAgent == original.preferredAgent)
        #expect(decoded.additionalContext == original.additionalContext)
        #expect(decoded.profileImagePath == original.profileImagePath)
        #expect(decoded.updatedAt == original.updatedAt)
    }

    @Test("Codable round-trip — preferredAgent nil 보존")
    func codableRoundTripNilAgent() throws {
        let original = UserProfile(preferredAgent: nil)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: data)
        #expect(decoded.preferredAgent == nil)
    }

    // MARK: - renderHarnessRules

    @Test("renderHarnessRules — displayName 포함")
    func renderIncludesDisplayName() {
        let profile = UserProfile(displayName: "김유민")
        let rendered = profile.renderHarnessRules()
        #expect(rendered.contains("김유민"))
    }

    @Test("renderHarnessRules — jobTitle 포함")
    func renderIncludesJobTitle() {
        let profile = UserProfile(jobTitle: "iOS 개발자")
        let rendered = profile.renderHarnessRules()
        #expect(rendered.contains("iOS 개발자"))
    }

    @Test("renderHarnessRules — primaryGoal 포함")
    func renderIncludesPrimaryGoal() {
        let profile = UserProfile(primaryGoal: "앱 만들기")
        let rendered = profile.renderHarnessRules()
        #expect(rendered.contains("앱 만들기"))
    }

    @Test("renderHarnessRules — goalStatus.displayName 포함")
    func renderIncludesGoalStatusDisplayName() {
        for status in UserProfile.GoalStatus.allCases {
            let profile = UserProfile(goalStatus: status)
            let rendered = profile.renderHarnessRules()
            #expect(rendered.contains(status.displayName))
        }
    }

    @Test("renderHarnessRules — goalStatus.subtitle 포함")
    func renderIncludesGoalStatusSubtitle() {
        for status in UserProfile.GoalStatus.allCases {
            let profile = UserProfile(goalStatus: status)
            let rendered = profile.renderHarnessRules()
            #expect(rendered.contains(status.subtitle))
        }
    }

    @Test("renderHarnessRules — additionalContext 포함")
    func renderIncludesAdditionalContext() {
        let profile = UserProfile(additionalContext: "Swift 5년차 개발자")
        let rendered = profile.renderHarnessRules()
        #expect(rendered.contains("Swift 5년차 개발자"))
    }

    @Test("renderHarnessRules — 빈 jobTitle은 (미입력) 표시")
    func renderEmptyJobTitle() {
        let profile = UserProfile(jobTitle: "")
        let rendered = profile.renderHarnessRules()
        #expect(rendered.contains("(미입력)"))
    }

    @Test("renderHarnessRules — updatedAt ISO8601 포함")
    func renderIncludesUpdatedAt() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let profile = UserProfile(updatedAt: date)
        let rendered = profile.renderHarnessRules()
        // ISO8601 포맷은 "2023-"로 시작
        #expect(rendered.contains("2023-"))
    }

    // MARK: - Hashable + Equatable

    @Test("같은 값이면 == true")
    func equalityCheck() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let a = UserProfile(displayName: "A", updatedAt: date)
        let b = UserProfile(displayName: "A", updatedAt: date)
        #expect(a == b)
    }

    @Test("다른 displayName이면 != true")
    func inequalityCheck() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let a = UserProfile(displayName: "A", updatedAt: date)
        let b = UserProfile(displayName: "B", updatedAt: date)
        #expect(a != b)
    }

    // MARK: - AppPreferences backward-compat

    @Test("AppPreferences decode without userProfile — .default 적용")
    func appPrefsBackwardCompat() throws {
        let oldJSON = """
        {
            "claudeBinaryPath": "/usr/local/bin/claude",
            "codexBinaryPath": "/usr/local/bin/codex",
            "telegramEnabled": false,
            "telegramAllowedUserIds": [],
            "fontSizeOffset": 0,
            "showInspectorByDefault": false
        }
        """.data(using: .utf8)!

        let prefs = try JSONDecoder().decode(AppPreferences.self, from: oldJSON)
        #expect(prefs.userProfile == UserProfile.default)
        #expect(prefs.userProfile.isEmpty == true)
    }
}
