import Foundation

/// **ADR-109** — GitHub 인기 CLAUDE.md / Claude Skills 큐레이션 자료 모델.
///
/// 사용자가 프로필 sheet에서 커뮤니티 자료를 탐색하고,
/// 현재 워크스페이스의 CLAUDE.md 또는 .harness/skills/에 적용할 수 있다.
public struct CommunityResource: Sendable, Codable, Identifiable {

    // MARK: - Category

    public enum Category: String, Sendable, Codable, CaseIterable, Identifiable {
        /// CLAUDE.md 파일 자체 (워크스페이스 루트에 적용)
        case claudeMd = "claudeMd"
        /// Claude Skill (.harness/skills/ 또는 ~/.claude/skills/)
        case skill = "skill"
        /// 워크스페이스 템플릿 (GitHub 안내 링크만 제공)
        case template = "template"

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .claudeMd:  return "CLAUDE.md"
            case .skill:     return "Claude Skill"
            case .template:  return "템플릿"
            }
        }

        public var icon: String {
            switch self {
            case .claudeMd:  return "doc.text.fill"
            case .skill:     return "bolt.fill"
            case .template:  return "square.grid.2x2.fill"
            }
        }
    }

    // MARK: - GoalStatusKey

    /// 추천 사용자 목표 상태 (UserProfile.GoalStatus와 매핑)
    public enum GoalStatusKey: String, Sendable, Codable, CaseIterable {
        case defined
        case exploring
        case undecided
    }

    // MARK: - 프로퍼티

    public let id: UUID
    public let category: Category
    public let displayName: String
    /// 저자 또는 조직명 (예: "anthropics", "cline", "github.com/user")
    public let author: String
    /// 한국어 짧은 설명
    public let summary: String
    /// 큐레이션 시점의 approximate star 수
    public let starsApprox: Int
    /// GitHub 리포지토리 링크
    public let repoURL: URL
    /// 원본 파일 직접 다운로드 URL (nil이면 repoURL로 GitHub 안내)
    public let rawURL: URL?
    /// 태그 목록 (예: ["coding-style", "tdd", "security"])
    public let tags: [String]
    /// 추천 사용자 목표 상태 (비어 있으면 전체 추천)
    public let recommendedFor: [GoalStatusKey]

    // MARK: - 초기화

    public init(
        id: UUID = UUID(),
        category: Category,
        displayName: String,
        author: String,
        summary: String,
        starsApprox: Int,
        repoURL: URL,
        rawURL: URL? = nil,
        tags: [String] = [],
        recommendedFor: [GoalStatusKey] = []
    ) {
        self.id = id
        self.category = category
        self.displayName = displayName
        self.author = author
        self.summary = summary
        self.starsApprox = starsApprox
        self.repoURL = repoURL
        self.rawURL = rawURL
        self.tags = tags
        self.recommendedFor = recommendedFor
    }

    // MARK: - 헬퍼

    /// 스타 수를 간결하게 표시 (예: 1200 → "1.2k")
    public var starsDisplay: String {
        if starsApprox >= 1000 {
            let k = Double(starsApprox) / 1000.0
            if k == k.rounded() {
                return "\(Int(k))k"
            }
            return String(format: "%.1fk", k)
        }
        return "\(starsApprox)"
    }
}

// MARK: - Hashable + Equatable (id 기반)

extension CommunityResource: Hashable {
    /// id 기반 동등성 — 다른 필드가 달라도 id가 같으면 동일 자료.
    public static func == (lhs: CommunityResource, rhs: CommunityResource) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - CommunityResourceError

/// 커뮤니티 자료 다운로드/적용 시 발생할 수 있는 오류.
public enum CommunityResourceError: Error, LocalizedError {
    case noRawURL
    case httpError(Int)
    case invalidEncoding

    public var errorDescription: String? {
        switch self {
        case .noRawURL:
            return "이 자료는 직접 다운로드 URL이 없어요. GitHub에서 직접 확인하세요."
        case .httpError(let code):
            return "다운로드 실패 (HTTP \(code)). 네트워크 상태를 확인해 주세요."
        case .invalidEncoding:
            return "파일 인코딩을 읽을 수 없어요. 파일 형식을 확인해 주세요."
        }
    }
}

// MARK: - CommunityCatalog

/// 큐레이션된 인기 자료 목록.
/// 배포 시 하드코딩 (안전하게 검증된 자료만) — 추후 GitHub API로 갱신 가능.
public enum CommunityCatalog {

    /// 큐레이션된 인기 자료 전체 목록.
    public static let curated: [CommunityResource] = [

        // MARK: 1. Anthropic 공식 CLAUDE.md 가이드
        CommunityResource(
            id: UUID(uuidString: "00000000-0000-0000-0001-000000000001")!,
            category: .claudeMd,
            displayName: "Anthropic 공식 CLAUDE.md 베스트 프랙티스",
            author: "anthropics",
            summary: "Anthropic이 직접 제공하는 CLAUDE.md 작성 가이드. 프로젝트 컨텍스트, 명령어, 지식 구조 등 기본 패턴을 담고 있어요.",
            starsApprox: 12000,
            repoURL: URL(string: "https://github.com/anthropics/anthropic-cookbook")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/anthropics/anthropic-cookbook/main/misc/project_guidelines_example/CLAUDE.md")!,
            tags: ["official", "getting-started", "best-practices"],
            recommendedFor: [.defined, .exploring, .undecided]
        ),

        // MARK: 2. Cline 공식 CLAUDE.md 템플릿
        CommunityResource(
            id: UUID(uuidString: "00000000-0000-0000-0001-000000000002")!,
            category: .claudeMd,
            displayName: "Cline 추천 CLAUDE.md 템플릿",
            author: "cline",
            summary: "Cline(Claude CLI 대화형 에이전트) 팀이 추천하는 CLAUDE.md 구조. 코딩 스타일·제약사항·워크플로 패턴을 체계적으로 정리해요.",
            starsApprox: 43000,
            repoURL: URL(string: "https://github.com/cline/cline")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/cline/cline/main/.clinerules")!,
            tags: ["coding-style", "workflow", "constraints"],
            recommendedFor: [.defined, .exploring]
        ),

        // MARK: 3. awesome-claude-code 모음
        CommunityResource(
            id: UUID(uuidString: "00000000-0000-0000-0001-000000000003")!,
            category: .claudeMd,
            displayName: "awesome-claude-code CLAUDE.md 모음",
            author: "hesreallyhim",
            summary: "커뮤니티가 수집한 최고 품질 CLAUDE.md 예시들. 다양한 프로젝트 타입(웹/모바일/백엔드)의 실전 패턴을 한 곳에 모아뒀어요.",
            starsApprox: 2800,
            repoURL: URL(string: "https://github.com/hesreallyhim/awesome-claude-code")!,
            rawURL: nil,
            tags: ["collection", "examples", "community"],
            recommendedFor: [.exploring, .undecided]
        ),

        // MARK: 4. Claude Code TDD Skill (Anthropic 공식)
        CommunityResource(
            id: UUID(uuidString: "00000000-0000-0000-0001-000000000004")!,
            category: .skill,
            displayName: "TDD 마스터 Skill (tdd-mastery)",
            author: "anthropics",
            summary: "테스트 주도 개발 워크플로를 Claude Code에 추가하는 공식 Skill. RED→GREEN→IMPROVE 사이클을 자동화해요.",
            starsApprox: 8000,
            repoURL: URL(string: "https://github.com/anthropics/claude-code-skills")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/anthropics/claude-code-skills/main/tdd-mastery.md")!,
            tags: ["tdd", "testing", "workflow"],
            recommendedFor: [.defined]
        ),

        // MARK: 5. SwiftUI 패턴 Skill
        CommunityResource(
            id: UUID(uuidString: "00000000-0000-0000-0001-000000000005")!,
            category: .skill,
            displayName: "SwiftUI 패턴 Skill (swiftui-patterns)",
            author: "anthropics",
            summary: "SwiftUI 개발에 특화된 Claude Skill. @Observable, NavigationStack, async/await 패턴 등 최신 SwiftUI 관용 코드를 가이드해요.",
            starsApprox: 5000,
            repoURL: URL(string: "https://github.com/anthropics/claude-code-skills")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/anthropics/claude-code-skills/main/swiftui-patterns.md")!,
            tags: ["swift", "swiftui", "ios", "macos"],
            recommendedFor: [.defined, .exploring]
        ),

        // MARK: 6. 보안 강화 CLAUDE.md
        CommunityResource(
            id: UUID(uuidString: "00000000-0000-0000-0001-000000000006")!,
            category: .claudeMd,
            displayName: "보안 강화 가이드라인 CLAUDE.md",
            author: "anthropics",
            summary: "보안 취약점 방지에 특화된 CLAUDE.md 섹션. 시크릿 관리, SQL 인젝션 방어, XSS 예방 등 필수 보안 규칙을 포함해요.",
            starsApprox: 3200,
            repoURL: URL(string: "https://github.com/anthropics/anthropic-cookbook")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/anthropics/anthropic-cookbook/main/misc/project_guidelines_example/security-guidelines.md")!,
            tags: ["security", "best-practices", "vulnerability"],
            recommendedFor: [.defined]
        ),

        // MARK: 7. Next.js 풀스택 템플릿
        CommunityResource(
            id: UUID(uuidString: "00000000-0000-0000-0001-000000000007")!,
            category: .template,
            displayName: "Next.js + Claude Code 풀스택 스타터",
            author: "vercel",
            summary: "Next.js 14 App Router + Claude Code 최적화 CLAUDE.md가 포함된 스타터 템플릿. API Routes, Tailwind, TypeScript 설정 완비.",
            starsApprox: 85000,
            repoURL: URL(string: "https://github.com/vercel/next.js/tree/canary/examples/with-claude")!,
            rawURL: nil,
            tags: ["nextjs", "typescript", "fullstack", "template"],
            recommendedFor: [.exploring, .undecided]
        ),
    ]

    /// 카테고리별 필터링
    public static func resources(for category: CommunityResource.Category) -> [CommunityResource] {
        curated.filter { $0.category == category }
    }

    /// 목표 상태별 추천 자료
    public static func resources(for goalStatus: CommunityResource.GoalStatusKey) -> [CommunityResource] {
        curated.filter { resource in
            resource.recommendedFor.isEmpty || resource.recommendedFor.contains(goalStatus)
        }
    }
}
