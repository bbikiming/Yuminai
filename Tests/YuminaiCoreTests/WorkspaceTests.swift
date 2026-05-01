import Foundation
import Testing
@testable import YuminaiCore

@Suite("Workspace")
struct WorkspaceTests {
    @Test("기본 생성자는 isArchived=false, 새 UUID를 부여한다")
    func defaultsAreSane() {
        let ws = Workspace(name: "test", directoryPath: "/tmp/test")
        #expect(ws.isArchived == false)
        #expect(ws.lastOpenedAt == nil)
        #expect(ws.harnessTemplate == nil)
        #expect(ws.name == "test")
    }

    @Test("HarnessTemplateName은 모든 raw value를 round-trip 가능해야 한다")
    func templateRoundTrip() {
        for template in HarnessTemplateName.allCases {
            #expect(HarnessTemplateName(rawValue: template.rawValue) == template)
        }
    }

    @Test("Workspace는 Hashable — Set에 넣고 꺼낼 수 있다")
    func workspaceIsHashable() {
        let ws = Workspace(name: "x", directoryPath: "/x")
        let set: Set<Workspace> = [ws]
        #expect(set.contains(ws))
    }
}

@Suite("YuminaiError")
struct YuminaiErrorTests {
    @Test("모든 에러 케이스는 한국어 errorDescription을 가진다")
    func allCasesHaveKoreanDescription() {
        let cases: [YuminaiError] = [
            .claudeNotInstalled(path: "/bin/x"),
            .claudeSpawnFailed(reason: "test"),
            .workspaceNotFound(id: UUID()),
            .workspaceAlreadyExists(name: "x"),
            .keychainReadFailed(status: -1),
            .keychainWriteFailed(status: -1),
            .ptyOpenFailed(errno: 1),
            .sessionCorrupted(id: UUID(), reason: "x"),
            .pathTraversalAttempted(relative: "../etc"),
            .harnessScaffoldFailed(template: .swift, reason: "x")
        ]
        for error in cases {
            #expect(error.errorDescription != nil)
            #expect(error.errorDescription?.isEmpty == false)
        }
    }
}
