import Foundation
import Testing
@testable import YuminaiCore

@Suite("TaskDecomposer — LLM 자동 분해 (ADR-049 Phase 4)")
struct TaskDecomposerTests {
    @Test("buildPrompt는 사용자 요청 + JSON schema 포함")
    func buildPromptBasics() {
        let prompt = TaskDecomposer.buildPrompt(userRequest: "로그인 페이지 만들어", projectProfile: nil)
        #expect(prompt.contains("로그인 페이지 만들어"))
        #expect(prompt.contains("JSON"))
        #expect(prompt.contains("\"tasks\""))
        #expect(prompt.contains("\"title\""))
        #expect(prompt.contains("\"agentRecommendation\""))
        #expect(prompt.contains("\"dependencies\""))
    }

    @Test("buildPrompt는 ProjectProfile 포함")
    func buildPromptWithProfile() {
        let profile = ProjectProfile(
            platform: .web,
            primaryLanguage: .typescript,
            frameworks: ["Next.js"]
        )
        let prompt = TaskDecomposer.buildPrompt(userRequest: "x", projectProfile: profile)
        #expect(prompt.contains("프로젝트 컨텍스트"))
        #expect(prompt.contains("웹"))
        #expect(prompt.contains("TypeScript"))
        #expect(prompt.contains("Next.js"))
    }

    @Test("buildPrompt — empty profile은 컨텍스트 섹션 생략")
    func buildPromptEmptyProfile() {
        let prompt = TaskDecomposer.buildPrompt(userRequest: "x", projectProfile: .empty)
        #expect(!prompt.contains("프로젝트 컨텍스트"))
    }

    @Test("parseTasks — 정상 JSON")
    func parseValid() {
        let json = """
        {
          "tasks": [
            {"title":"plan","description":"design API","agentRecommendation":"claude","dependencies":[]},
            {"title":"implement","description":"write code","agentRecommendation":"codex","dependencies":[0]},
            {"title":"test","description":"write tests","agentRecommendation":"codex","dependencies":[1]}
          ]
        }
        """
        let tasks = TaskDecomposer.parseTasks(jsonResponse: json)
        #expect(tasks.count == 3)
        #expect(tasks[0].title == "plan")
        #expect(tasks[0].assignedAgent == .claude)
        #expect(tasks[0].dependencies.isEmpty)
        #expect(tasks[1].assignedAgent == .codex)
        #expect(tasks[1].dependencies == [tasks[0].id])
        #expect(tasks[2].dependencies == [tasks[1].id])
    }

    @Test("parseTasks — ```json ... ``` fence 추출")
    func parseFromFence() {
        let response = """
        Here are the tasks:
        ```json
        {"tasks":[{"title":"a","description":"","agentRecommendation":"claude","dependencies":[]}]}
        ```
        """
        let tasks = TaskDecomposer.parseTasks(jsonResponse: response)
        #expect(tasks.count == 1)
        #expect(tasks[0].title == "a")
    }

    @Test("parseTasks — invalid JSON은 빈 배열")
    func parseInvalid() {
        let tasks = TaskDecomposer.parseTasks(jsonResponse: "not json at all")
        #expect(tasks.isEmpty)
    }

    @Test("parseTasks — agentRecommendation invalid면 default fallback")
    func parseInvalidAgent() {
        let json = """
        {"tasks":[{"title":"x","description":"","agentRecommendation":"bogus","dependencies":[]}]}
        """
        let tasks = TaskDecomposer.parseTasks(jsonResponse: json, defaultAgent: .codex)
        #expect(tasks.count == 1)
        #expect(tasks[0].assignedAgent == .codex)
    }

    @Test("parseTasks — 빈 tasks 배열")
    func parseEmpty() {
        let tasks = TaskDecomposer.parseTasks(jsonResponse: "{\"tasks\":[]}")
        #expect(tasks.isEmpty)
    }
}
