import Foundation

/// 큰 task를 sub-task로 자동 분해하는 LLM helper (ADR-049 Phase 4).
///
/// **설계**:
/// - Claude를 통해 JSON 출력 요청 (LLM이 정확한 schema로 응답)
/// - prompt: 사용자 요청 + ProjectProfile + 분해 가이드
/// - 응답 parse → [HarnessTask] 배열
/// - 비용 명시 (LLM 호출 1회 — opt-in 권장)
///
/// **caller 책임**:
/// - 실제 LLM 호출은 caller (AppModel)가 별도 ClaudeStreamSession spawn
///   (현재 구조에서 task decomposition을 active session에서 하면 컨텍스트 오염 → 별도 ephemeral session 권장)
/// - 또는 `/decompose` 명령으로 user-initiated
///
/// **Schema**:
/// ```json
/// {
///   "tasks": [
///     {
///       "title": "...",
///       "description": "...",
///       "agentRecommendation": "claude" | "codex",
///       "dependencies": [<task index>]
///     }
///   ]
/// }
/// ```
public enum TaskDecomposer {
    /// 분해 LLM에게 보낼 prompt 생성.
    public static func buildPrompt(userRequest: String, projectProfile: ProjectProfile?) -> String {
        var sections: [String] = []
        sections.append("# 작업 분해 요청")
        sections.append("사용자 요청을 sub-task 단위로 분해해주세요. 각 sub-task는 30분~2시간 단위.")

        if let profile = projectProfile {
            let summary = profile.systemContextSummary()
            if summary != "(프로필 미설정)" {
                sections.append("## 프로젝트 컨텍스트\n\(summary)")
            }
        }

        sections.append("## 사용자 요청\n\(userRequest)")

        sections.append("""
        ## 출력 형식
        반드시 다음 JSON schema로만 응답:
        ```json
        {
          "tasks": [
            {
              "title": "짧은 제목 (40자 이내)",
              "description": "상세 설명 (200자 이내)",
              "agentRecommendation": "claude" | "codex",
              "dependencies": [task_index_array]
            }
          ]
        }
        ```

        ## 가이드
        - 5개 이내 sub-task로 분해 (너무 잘게 X)
        - dependencies는 선행 task의 0-based index (예: task[1]이 task[0]에 depend → [0])
        - agent 선택 기준: codex = 단순 코드 생성 / claude = reasoning, planning, refactoring, code review
        - 첫 task는 의존성 없음 (빈 배열)

        JSON만 응답. 다른 텍스트 일절 X.
        """)

        return sections.joined(separator: "\n\n")
    }

    /// LLM JSON 응답을 [HarnessTask]로 parse.
    /// `defaultAgent`: agentRecommendation이 invalid면 이걸 fallback.
    public static func parseTasks(jsonResponse: String, defaultAgent: AgentKind = .claude) -> [HarnessTask] {
        // 응답에서 ```json ... ``` 페어 추출 (LLM이 종종 fence로 wrap)
        let extracted = extractJSON(from: jsonResponse)
        guard let data = extracted.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let taskArray = json["tasks"] as? [[String: Any]] else {
            return []
        }
        // 1차 pass: index → UUID 매핑 만들기
        var indexToId: [Int: UUID] = [:]
        for i in 0..<taskArray.count {
            indexToId[i] = UUID()
        }
        // 2차 pass: HarnessTask 생성
        var tasks: [HarnessTask] = []
        for (i, dict) in taskArray.enumerated() {
            let title = (dict["title"] as? String) ?? "Task \(i + 1)"
            let description = (dict["description"] as? String) ?? ""
            let agentStr = (dict["agentRecommendation"] as? String) ?? ""
            let agent = AgentKind(rawValue: agentStr) ?? defaultAgent
            let depIndices = (dict["dependencies"] as? [Int]) ?? []
            let depIds = depIndices.compactMap { indexToId[$0] }
            let task = HarnessTask(
                id: indexToId[i] ?? UUID(),
                title: title,
                description: description,
                status: .pending,
                assignedAgent: agent,
                dependencies: depIds
            )
            tasks.append(task)
        }
        return tasks
    }

    /// LLM 응답에서 JSON 추출 — ```json ... ``` 페어 우선, 없으면 전체.
    private static func extractJSON(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // ```json ... ``` 패턴
        if let startRange = trimmed.range(of: "```json"),
           let endRange = trimmed.range(of: "```", range: startRange.upperBound..<trimmed.endIndex) {
            return String(trimmed[startRange.upperBound..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // 그냥 ``` ... ``` 패턴
        if let startRange = trimmed.range(of: "```"),
           let endRange = trimmed.range(of: "```", range: startRange.upperBound..<trimmed.endIndex) {
            return String(trimmed[startRange.upperBound..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }
}
