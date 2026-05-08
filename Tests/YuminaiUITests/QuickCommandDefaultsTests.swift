import Foundation
import Testing
@testable import YuminaiCore
@testable import YuminaiUI

@MainActor
@Suite("QuickCommand.defaults — custom + sanitize")
struct QuickCommandDefaultsTests {
    @Test("custom 모두 제공 시 sparkles icon으로 default와 git 사이에 들어감")
    func customAppearsBetweenDefaultsAndGit() {
        let result = QuickCommand.defaults(
            test: "swift test",
            build: "swift build",
            lint: nil,
            custom: [
                CustomQuickCommand(label: "서버", command: "npm run dev"),
                CustomQuickCommand(label: "마이그", command: "npm run migrate")
            ]
        )
        let labels = result.map(\.label)
        // 순서: 테스트, 빌드, [custom들], git status, git diff, git log -5
        #expect(labels.firstIndex(of: "서버")! > labels.firstIndex(of: "테스트")!)
        #expect(labels.firstIndex(of: "서버")! < labels.firstIndex(of: "git status")!)
        #expect(labels.contains("마이그"))

        let serverItem = result.first { $0.label == "서버" }!
        #expect(serverItem.icon == "sparkles")
    }

    @Test("빈 command custom은 skip (sanitize 보조 방어)")
    func emptyCommandSkipped() {
        let result = QuickCommand.defaults(
            test: nil,
            build: nil,
            lint: nil,
            custom: [
                CustomQuickCommand(label: "유효", command: "echo ok"),
                CustomQuickCommand(label: "빈것", command: ""),
                CustomQuickCommand(label: "공백만", command: "   ")
            ]
        )
        let customLabels = result.filter { $0.icon == "sparkles" }.map(\.label)
        #expect(customLabels == ["유효"])
    }

    @Test("빈 label은 command로 fallback display")
    func emptyLabelFallsBackToCommand() {
        let result = QuickCommand.defaults(
            test: nil, build: nil, lint: nil,
            custom: [CustomQuickCommand(label: "", command: "ls -la")]
        )
        let custom = result.first { $0.icon == "sparkles" }!
        #expect(custom.label == "ls -la")
        #expect(custom.command == "ls -la")
    }

    @Test("test/build/lint 모두 nil이어도 git defaults는 항상 표시")
    func gitDefaultsAlwaysPresent() {
        let result = QuickCommand.defaults(test: nil, build: nil, lint: nil, custom: [])
        let labels = result.map(\.label)
        #expect(labels.contains("git status"))
        #expect(labels.contains("git diff"))
        #expect(labels.contains("git log -5"))
        #expect(result.count == 3)
    }

    @Test("custom 빈 배열 + 모든 명령 빈 string도 안전")
    func defensiveEmpty() {
        let result = QuickCommand.defaults(test: "", build: "", lint: "", custom: [])
        // test/build/lint 빈 string은 if-let 외부 isEmpty check로 skip
        let nonGit = result.filter { !$0.label.hasPrefix("git") }
        #expect(nonGit.isEmpty)
    }
}
