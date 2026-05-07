import Foundation
import Testing
import YuminaiCore

@Suite("SetupTool")
struct SetupToolTests {

    @Test("모든 case에 displayName이 정의됨")
    func allCasesHaveDisplayName() {
        for tool in SetupTool.allCases {
            #expect(!tool.displayName.isEmpty, "displayName 비어있음: \(tool.rawValue)")
        }
    }

    @Test("모든 case에 purpose(친화 설명)가 정의됨")
    func allCasesHavePurpose() {
        for tool in SetupTool.allCases {
            #expect(!tool.purpose.isEmpty, "purpose 비어있음: \(tool.rawValue)")
        }
    }

    @Test("모든 case에 installCommand가 정의됨")
    func allCasesHaveInstallCommand() {
        for tool in SetupTool.allCases {
            #expect(!tool.installCommand.isEmpty, "installCommand 비어있음: \(tool.rawValue)")
        }
    }

    @Test("모든 case에 docsURL이 유효한 URL임")
    func allCasesHaveDocsURL() {
        for tool in SetupTool.allCases {
            let url = tool.docsURL
            #expect(!url.absoluteString.isEmpty, "docsURL 비어있음: \(tool.rawValue)")
        }
    }

    @Test("모든 case에 detectionPaths가 비어있지 않음")
    func allCasesHaveDetectionPaths() {
        for tool in SetupTool.allCases {
            #expect(!tool.detectionPaths.isEmpty, "detectionPaths 비어있음: \(tool.rawValue)")
        }
    }

    @Test("isRequired는 claudeCode만 true")
    func isRequiredOnlyClaudeCode() {
        #expect(SetupTool.claudeCode.isRequired == true)
        #expect(SetupTool.codexCLI.isRequired == false)
        #expect(SetupTool.cokacdir.isRequired == false)
    }

    @Test("CaseIterable — 3개 케이스")
    func caseCount() {
        // ADR-133: githubCLI + gitlabCLI 추가 → 5개
        #expect(SetupTool.allCases.count == 5)
    }

    @Test("id는 rawValue와 동일")
    func idEqualsRawValue() {
        for tool in SetupTool.allCases {
            #expect(tool.id == tool.rawValue)
        }
    }

    @Test("badgeLabel이 필수/선택/권장 중 하나")
    func badgeLabelValues() {
        let validBadges: Set<String> = ["필수", "선택", "권장"]
        for tool in SetupTool.allCases {
            #expect(validBadges.contains(tool.badgeLabel), "잘못된 badgeLabel: \(tool.badgeLabel)")
        }
    }
}
