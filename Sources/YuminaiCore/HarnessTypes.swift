import Foundation

// MARK: - SharedConversationLog (ADR-047 Phase 1)

/// 모든 모델이 동일하게 참조하는 conversation timeline.
///
/// **목적**: 모델 전환 시 컨텍스트 보존. Claude session → Codex session으로 전환해도
/// 같은 timeline을 보고 catch up 가능 (HandoffPromptBuilder가 이 log를 읽음).
///
/// **저장 정책**: 메모리 우선 (Phase 1) → SwiftData 영속 (Phase 4).
/// 워크스페이스 별 단일 log — pane 분리 없음 (multi-pane은 entry.agentKind로 추적).
public struct ConversationEntry: Identifiable, Sendable, Codable, Hashable {
    public let id: UUID
    public let timestamp: Date
    public let role: Role
    /// `.agent` 일 때 어느 모델이 응답했는지. user/system은 nil.
    public let agentKind: AgentKind?
    public let content: String
    public let attachments: [String]
    /// TaskGraph 노드 참조 (Phase 4+ — Phase 1에는 nil 가능).
    public let taskId: UUID?
    /// 추정 토큰 수 (caller가 측정 후 기록 — Phase 1에는 nil 가능).
    public let tokenCount: Int?

    public enum Role: String, Sendable, Codable, Hashable {
        case user
        case agent
        case system  // handoff prompt, transition note 등
    }

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        role: Role,
        agentKind: AgentKind? = nil,
        content: String,
        attachments: [String] = [],
        taskId: UUID? = nil,
        tokenCount: Int? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.role = role
        self.agentKind = agentKind
        self.content = content
        self.attachments = attachments
        self.taskId = taskId
        self.tokenCount = tokenCount
    }
}

// MARK: - ModelCapabilityMatrix (ADR-047 Phase 1)

/// Task 종류 → 추천 모델.
public enum TaskKind: String, Sendable, Codable, Hashable, CaseIterable {
    case planning           // → Claude (reasoning 강함)
    case codeGeneration     // → Codex (code-focused)
    case codeReview         // → Claude
    case refactoring        // → Claude
    case debugging          // → Claude
    case longContextSearch  // → Gemini (향후)
    case generalChat        // → Claude (default)
    case unknown            // → 사용자 활성 모델 default
}

public enum ModelCapabilityMatrix {
    /// Task → 추천 AgentKind.
    /// 향후 Gemini/GPT 추가 시 case 확장.
    public static func recommend(for task: TaskKind) -> AgentKind {
        switch task {
        case .planning, .codeReview, .refactoring, .debugging, .generalChat:
            return .claude
        case .codeGeneration:
            return .codex
        case .longContextSearch:
            // Gemini가 향후 추가되면 .gemini 반환. 현재는 Claude (long context Sonnet)
            return .claude
        case .unknown:
            // 명시적 추천 없음 — caller가 사용자 활성 모델 사용
            return .claude
        }
    }

    /// 사용자 입력 텍스트 → TaskKind 추정 (휴리스틱).
    /// 정확한 분류는 Phase 3에서 LLM-based classification으로 대체 가능.
    public static func inferTaskKind(from userText: String) -> TaskKind {
        let lower = userText.lowercased()
        // 명시적 keyword 매칭 (한국어 + 영어)
        let codeGenKeywords = ["구현", "코딩", "작성해줘", "implement", "write a function", "create a class", "write code", "코드 작성"]
        let reviewKeywords = ["리뷰", "review", "검토", "improve", "개선", "리팩터", "refactor"]
        let debugKeywords = ["버그", "에러", "fix", "디버그", "debug", "안 돌아가", "doesn't work", "고쳐"]
        let planKeywords = ["계획", "plan", "어떻게", "how to", "설계", "architect", "approach"]
        let searchKeywords = ["찾아", "search", "검색", "어디", "where is"]

        if codeGenKeywords.contains(where: lower.contains) { return .codeGeneration }
        if reviewKeywords.contains(where: lower.contains) { return .codeReview }
        if debugKeywords.contains(where: lower.contains) { return .debugging }
        if planKeywords.contains(where: lower.contains) { return .planning }
        if searchKeywords.contains(where: lower.contains) { return .longContextSearch }
        return .generalChat
    }

    /// 모델 별 강점 한 줄 (handoff prompt에 포함).
    public static func strengthSummary(for kind: AgentKind) -> String {
        switch kind {
        case .claude:
            return "추론, 리팩터링, 코드 리뷰, 계획 수립에 강함"
        case .codex:
            return "빠른 코드 생성, 자동완성, 작은 단위 작업에 강함"
        }
    }
}

// MARK: - HandoffPromptBuilder (ADR-047 Phase 1)

/// 모델 전환 시 catch-up prompt 생성.
///
/// **알고리즘**:
/// 1. 최근 N entries (default 5)는 전체 보존
/// 2. 그 이전 entries는 요약 (사용자 메시지는 첫 80자, agent 응답은 첫 줄 + 요약)
/// 3. 토큰 예산 (default 4000) 내 압축 — 초과 시 더 오래된 것부터 제거
/// 4. 새 모델 instruction (target 모델 강점 강조)
public enum HandoffPromptBuilder {
    public struct Output: Equatable, Hashable, Sendable {
        public let promptText: String
        /// 추정 토큰 수 (utf8 byte / 4).
        public let estimatedTokens: Int
        /// 어떤 entries를 포함했는지 (id list — debug/audit용).
        public let includedEntryIds: [UUID]
    }

    public static func build(
        log: [ConversationEntry],
        targetModel: AgentKind,
        currentTask: HarnessTask? = nil,
        projectProfile: ProjectProfile? = nil,
        recentEntriesVerbatim: Int = 5,
        tokenBudget: Int = 4000
    ) -> Output {
        var sections: [String] = []

        // Header — 새 모델에 역할 설명
        let strength = ModelCapabilityMatrix.strengthSummary(for: targetModel)
        sections.append("# 컨텍스트 인계 (Handoff)\n당신은 \(targetModel.shortLabel) 모델입니다 — \(strength).\n이 대화는 다른 모델 또는 사용자가 진행하던 것이며, 당신이 이어받습니다.")

        // ADR-048 — Project profile (system context)
        if let profile = projectProfile {
            let summary = profile.systemContextSummary()
            if summary != "(프로필 미설정)" {
                sections.append("## 프로젝트 컨텍스트\n\(summary)")
            }
        }

        // Current task (있으면)
        if let task = currentTask {
            sections.append("## 현재 작업\n- 제목: \(task.title)\n- 설명: \(task.description)\n- 상태: \(task.status.rawValue)")
            if let output = task.output, !output.isEmpty {
                sections.append("- 이전 진행 결과: \(output)")
            }
        }

        // Conversation log (최근 verbatim + 이전 요약)
        let totalEntries = log.count
        let verbatimCount = min(recentEntriesVerbatim, totalEntries)
        let summarizedCount = totalEntries - verbatimCount

        var includedIds: [UUID] = []

        if summarizedCount > 0 {
            sections.append("## 이전 대화 요약 (오래된 \(summarizedCount)개)")
            let summarized = log.prefix(summarizedCount)
            let summaryLines = summarized.map { entry -> String in
                includedIds.append(entry.id)
                return summarizeEntry(entry)
            }
            sections.append(summaryLines.joined(separator: "\n"))
        }

        if verbatimCount > 0 {
            sections.append("## 최근 대화 (verbatim, \(verbatimCount)개)")
            let recent = log.suffix(verbatimCount)
            let recentBlock = recent.map { entry -> String in
                includedIds.append(entry.id)
                return formatEntry(entry)
            }.joined(separator: "\n\n")
            sections.append(recentBlock)
        }

        // Instruction
        sections.append("## 응답 가이드\n위 컨텍스트를 바탕으로 사용자의 다음 입력에 응답해주세요. \(targetModel.shortLabel)의 강점을 살려주세요.")

        var prompt = sections.joined(separator: "\n\n")
        var estimatedTokens = prompt.utf8.count / 4

        // Token budget 초과 시 — 오래된 요약부터 제거 (recent verbatim은 보존)
        if estimatedTokens > tokenBudget && summarizedCount > 0 {
            // 단순화: 요약 섹션 통째로 제거 + 재계산
            sections.removeAll { $0.hasPrefix("## 이전 대화 요약") }
            // 요약 다음 sections (block)도 제거
            // 안전: rebuild without 요약 섹션
            prompt = sections.joined(separator: "\n\n")
            estimatedTokens = prompt.utf8.count / 4
        }

        return Output(
            promptText: prompt,
            estimatedTokens: estimatedTokens,
            includedEntryIds: includedIds
        )
    }

    private static func summarizeEntry(_ entry: ConversationEntry) -> String {
        let prefix: String
        switch entry.role {
        case .user: prefix = "사용자"
        case .agent: prefix = "[\(entry.agentKind?.shortLabel ?? "?")]"
        case .system: prefix = "시스템"
        }
        let firstLine = entry.content.split(separator: "\n").first.map(String.init) ?? entry.content
        let cap = String(firstLine.prefix(80))
        return "- \(prefix): \(cap)"
    }

    private static func formatEntry(_ entry: ConversationEntry) -> String {
        let prefix: String
        switch entry.role {
        case .user: prefix = "### 사용자"
        case .agent: prefix = "### [\(entry.agentKind?.shortLabel ?? "?")]"
        case .system: prefix = "### 시스템"
        }
        return "\(prefix)\n\(entry.content)"
    }
}

// MARK: - TaskGraph (ADR-047 Phase 1 minimal)

public enum TaskStatus: String, Sendable, Codable, Hashable, CaseIterable {
    case pending
    case running
    case completed
    case failed
}

/// Harness task — 사용자 큰 task의 단위. Phase 4+에서 자동 분해.
public struct HarnessTask: Identifiable, Sendable, Codable, Hashable {
    public let id: UUID
    public let title: String
    public let description: String
    public var status: TaskStatus
    public var assignedAgent: AgentKind?
    public var dependencies: [UUID]
    public var output: String?
    /// 이 task를 진행하면서 생성된 conversation entry IDs.
    public var entryRefs: [UUID]
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        description: String,
        status: TaskStatus = .pending,
        assignedAgent: AgentKind? = nil,
        dependencies: [UUID] = [],
        output: String? = nil,
        entryRefs: [UUID] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.status = status
        self.assignedAgent = assignedAgent
        self.dependencies = dependencies
        self.output = output
        self.entryRefs = entryRefs
        self.createdAt = createdAt
    }

    /// 의존성 모두 completed면 true (실행 가능 상태).
    public func isReady(allTasks: [HarnessTask]) -> Bool {
        guard status == .pending else { return false }
        for depId in dependencies {
            guard let dep = allTasks.first(where: { $0.id == depId }) else { return false }
            if dep.status != .completed { return false }
        }
        return true
    }
}
