import Foundation

/// **ADR-112** — GitHub 인기 CLAUDE.md / Claude Skills / 디자인 가이드 / MCP 등 큐레이션 자료 모델.
///
/// 사용자가 프로필 sheet에서 커뮤니티 자료를 탐색하고,
/// 현재 워크스페이스의 CLAUDE.md 또는 .harness/skills/에 적용할 수 있다.
///
/// ADR-112: 카테고리 3개 → 9개로 확장, Language / useCase / officialBadge / recommendedRank 신규 필드.
public struct CommunityResource: Sendable, Codable, Identifiable {

    // MARK: - Category

    public enum Category: String, Sendable, Codable, CaseIterable, Identifiable {
        /// CLAUDE.md 파일 자체 (워크스페이스 루트에 적용)
        case claudeMd = "claudeMd"
        /// Claude Skill (.harness/skills/ 또는 ~/.claude/skills/)
        case skill = "skill"
        /// 워크스페이스 템플릿 (GitHub 안내 링크만 제공)
        case template = "template"
        /// 디자인 가이드 / DESIGN.md / 코딩 스타일 규칙
        case styleGuide = "styleGuide"
        /// 개발 워크플로우 / TDD / Git 워크플로우 / CI/CD
        case workflow = "workflow"
        /// 시스템 설계 / Clean Architecture / DDD / ADR
        case architecture = "architecture"
        /// 효과적인 프롬프트 패턴 / 프롬프트 엔지니어링
        case promptPattern = "promptPattern"
        /// .cursor.rules / .claude rules / linting / AI 에디터 설정
        case rules = "rules"
        /// MCP 서버 설정 / 모델 컨텍스트 프로토콜
        case mcp = "mcp"

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .claudeMd:      return "CLAUDE.md"
            case .skill:         return "Claude Skill"
            case .template:      return "템플릿"
            case .styleGuide:    return "디자인 가이드"
            case .workflow:      return "워크플로우"
            case .architecture:  return "시스템 설계"
            case .promptPattern: return "프롬프트 패턴"
            case .rules:         return "에디터 규칙"
            case .mcp:           return "MCP 서버"
            }
        }

        public var icon: String {
            switch self {
            case .claudeMd:      return "doc.text.fill"
            case .skill:         return "bolt.fill"
            case .template:      return "square.grid.2x2.fill"
            case .styleGuide:    return "paintbrush.fill"
            case .workflow:      return "arrow.triangle.2.circlepath"
            case .architecture:  return "building.columns.fill"
            case .promptPattern: return "text.bubble.fill"
            case .rules:         return "shield.fill"
            case .mcp:           return "plug.fill"
            }
        }

        public var tintColorName: String {
            switch self {
            case .claudeMd:      return "accent"
            case .skill:         return "orange"
            case .template:      return "green"
            case .styleGuide:    return "purple"
            case .workflow:      return "blue"
            case .architecture:  return "indigo"
            case .promptPattern: return "teal"
            case .rules:         return "red"
            case .mcp:           return "cyan"
            }
        }

        public var categoryDescription: String {
            switch self {
            case .claudeMd:      return "워크스페이스 루트에 두는 CLAUDE.md 파일. Claude에게 프로젝트 규칙과 컨텍스트를 전달해요."
            case .skill:         return "Claude Code 스킬 파일. 반복 작업을 자동화하고 복잡한 워크플로를 정의할 수 있어요."
            case .template:      return "프로젝트 시작에 바로 쓸 수 있는 워크스페이스 템플릿. GitHub에서 fork해 사용해요."
            case .styleGuide:    return "코딩 스타일, 디자인 가이드, 컨벤션 문서. 팀 코드 품질을 일관되게 유지해줘요."
            case .workflow:      return "TDD, Git 전략, CI/CD, 코드 리뷰 등 개발 워크플로우 가이드."
            case .architecture:  return "Clean Architecture, DDD, 마이크로서비스 등 시스템 설계 패턴과 ADR 사례."
            case .promptPattern: return "Claude에게 더 효과적인 지시를 내리는 프롬프트 패턴과 엔지니어링 기법."
            case .rules:         return ".cursor.rules, .claude rules 등 AI 에디터 규칙 파일. 코드 생성 품질을 높여줘요."
            case .mcp:           return "Model Context Protocol 서버 설정. Claude에게 도구와 데이터 소스를 연결해요."
            }
        }

        /// 카탈로그 표시 우선순위 (낮을수록 먼저)
        public var categoryRank: Int {
            switch self {
            case .claudeMd:      return 0
            case .skill:         return 1
            case .template:      return 2
            case .styleGuide:    return 3
            case .workflow:      return 4
            case .architecture:  return 5
            case .promptPattern: return 6
            case .rules:         return 7
            case .mcp:           return 8
            }
        }
    }

    // MARK: - Language

    /// 자료의 주요 언어
    public enum Language: String, Sendable, Codable, CaseIterable {
        case korean       = "korean"
        case english      = "english"
        case multilingual = "multilingual"

        public var displayName: String {
            switch self {
            case .korean:       return "한국어"
            case .english:      return "영어"
            case .multilingual: return "다국어"
            }
        }

        public var flag: String {
            switch self {
            case .korean:       return "🇰🇷"
            case .english:      return "🇬🇧"
            case .multilingual: return "🌐"
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
    /// 자료의 주요 언어 (ADR-112 신규)
    public let language: Language
    /// 이 자료의 사용 사례 — 짧은 한 줄 예시 (ADR-112 신규)
    public let useCase: String?
    /// Anthropic 공식 여부 — 카드에서 강조 표시 (ADR-112 신규)
    public let officialBadge: Bool
    /// 카테고리 내 추천도 0-100 — 높을수록 먼저 (ADR-112 신규)
    public let recommendedRank: Int

    // MARK: - CodingKeys (backward-compat 커스텀 decode 위해 필요)

    private enum CodingKeys: String, CodingKey {
        case id, category, displayName, author, summary, starsApprox
        case repoURL, rawURL, tags, recommendedFor
        case language, useCase, officialBadge, recommendedRank
    }

    /// ADR-112 — backward-compat: 신규 필드(language/useCase/officialBadge/recommendedRank)가
    /// 없는 구버전 JSON도 기본값으로 디코딩 성공.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(UUID.self, forKey: .id)
        category        = try c.decode(Category.self, forKey: .category)
        displayName     = try c.decode(String.self, forKey: .displayName)
        author          = try c.decode(String.self, forKey: .author)
        summary         = try c.decode(String.self, forKey: .summary)
        starsApprox     = try c.decode(Int.self, forKey: .starsApprox)
        repoURL         = try c.decode(URL.self, forKey: .repoURL)
        rawURL          = try c.decodeIfPresent(URL.self, forKey: .rawURL)
        tags            = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        recommendedFor  = try c.decodeIfPresent([GoalStatusKey].self, forKey: .recommendedFor) ?? []
        // ADR-112 신규 필드 — 구버전 JSON에서 없으면 기본값
        language        = try c.decodeIfPresent(Language.self, forKey: .language) ?? .english
        useCase         = try c.decodeIfPresent(String.self, forKey: .useCase)
        officialBadge   = try c.decodeIfPresent(Bool.self, forKey: .officialBadge) ?? false
        recommendedRank = try c.decodeIfPresent(Int.self, forKey: .recommendedRank) ?? 50
    }

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
        recommendedFor: [GoalStatusKey] = [],
        language: Language = .english,
        useCase: String? = nil,
        officialBadge: Bool = false,
        recommendedRank: Int = 50
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
        self.language = language
        self.useCase = useCase
        self.officialBadge = officialBadge
        self.recommendedRank = recommendedRank
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
    case networkError(Error)
    case httpError(Int)
    case httpErrorWithURL(URL, Int)
    case invalidEncoding

    public var errorDescription: String? {
        switch self {
        case .noRawURL:
            return "이 자료는 직접 다운로드 URL이 없어요. GitHub에서 직접 확인하거나, 직접 URL을 입력해 라이브러리에 추가하세요."
        case .networkError(let err):
            return "네트워크 오류로 다운로드에 실패했어요. 인터넷 연결을 확인 후 다시 시도해 주세요.\n원인: \(err.localizedDescription)"
        case .httpError(let code):
            let suggestion = httpSuggestion(for: code)
            return "다운로드 실패 (HTTP \(code)). \(suggestion)"
        case .httpErrorWithURL(let url, let code):
            let suggestion = httpSuggestion(for: code)
            return "다운로드 실패 (HTTP \(code)).\nURL: \(url.absoluteString)\n\(suggestion)"
        case .invalidEncoding:
            return "파일 인코딩을 읽을 수 없어요. UTF-8 텍스트 파일인지 확인해 주세요."
        }
    }

    private func httpSuggestion(for code: Int) -> String {
        switch code {
        case 404: return "URL이 유효한지 확인해 주세요. 파일이 삭제되거나 이동됐을 수 있어요."
        case 401, 403: return "접근 권한이 없는 리소스예요. 공개 URL인지 확인해 주세요."
        case 429: return "요청이 너무 많아요. 잠시 후 다시 시도해 주세요."
        case 500...599: return "서버 오류예요. 나중에 다시 시도해 주세요."
        default: return "네트워크 상태를 확인해 주세요."
        }
    }
}

// MARK: - CommunityCatalog

/// 큐레이션된 인기 자료 목록.
/// 배포 시 하드코딩 (안전하게 검증된 자료만) — 추후 GitHub API로 갱신 가능.
///
/// **ADR-112 검증 결과 (2026-05-04)**:
/// curl 검증된 rawURL (200 OK):
/// - anthropics/anthropic-cookbook CLAUDE.md ✅
/// - anthropics/anthropic-quickstarts CLAUDE.md ✅
/// - anthropics/claude-code-action CLAUDE.md ✅
/// - cline/cline CLAUDE.md ✅
/// - modelcontextprotocol/servers CLAUDE.md ✅
/// - modelcontextprotocol/servers README.md ✅
/// - punkpeye/awesome-mcp-servers README.md ✅
/// - vercel/next.js CLAUDE.md ✅ (canary)
/// - hesreallyhim/awesome-claude-code README.md ✅
///
/// rawURL nil (404 또는 미존재):
/// - anthropics/courses README.md ❌ 404
/// - cline/cline .clinerules ❌ 404
/// - hesreallyhim/awesome-claude-code CLAUDE.md ❌ 404
///
/// Stars (GitHub API / 공개 정보 기준, 2026-05-04):
/// - cline/cline: ~61k, hesreallyhim/awesome-claude-code: ~42k
/// - modelcontextprotocol/servers: ~85k, punkpeye/awesome-mcp-servers: ~86k
/// - vercel/next.js: ~139k, anthropics/courses: ~21k
public enum CommunityCatalog {

    /// 큐레이션된 인기 자료 전체 목록 (25개, ADR-112).
    public static let curated: [CommunityResource] = [

        // ═══════════════════════════════════════════
        // MARK: CLAUDE.md 카테고리 (5개)
        // ═══════════════════════════════════════════

        // 1. Anthropic Cookbook CLAUDE.md ✅ 200 OK
        CommunityResource(
            id: UUID(uuidString: "00000000-0000-0000-0001-000000000001")!,
            category: .claudeMd,
            displayName: "Anthropic Cookbook 개발 가이드",
            author: "anthropics",
            summary: "Anthropic Claude Cookbook 리포지토리의 공식 CLAUDE.md. 프로젝트 기여·개발 환경 설정·테스트·코드 스타일 규칙을 담고 있어요.",
            starsApprox: 10000,
            repoURL: URL(string: "https://github.com/anthropics/anthropic-cookbook")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/anthropics/anthropic-cookbook/main/CLAUDE.md")!,
            tags: ["official", "getting-started", "best-practices", "python"],
            recommendedFor: [.defined, .exploring, .undecided],
            language: .english,
            useCase: "새 Claude 프로젝트 시작 시 기본 규칙 참고",
            officialBadge: true,
            recommendedRank: 100
        ),

        // 2. Cline 공식 CLAUDE.md ✅ 200 OK
        CommunityResource(
            id: UUID(uuidString: "00000000-0000-0000-0001-000000000002")!,
            category: .claudeMd,
            displayName: "Cline 공식 CLAUDE.md",
            author: "cline",
            summary: "Cline(VS Code AI 에이전트) 팀의 CLAUDE.md. 코딩 스타일·제약사항·커밋 메시지 규칙을 체계적으로 정리해요. 실전 에이전트 프로젝트의 좋은 예시예요.",
            starsApprox: 61000,
            repoURL: URL(string: "https://github.com/cline/cline")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/cline/cline/main/CLAUDE.md")!,
            tags: ["coding-style", "workflow", "constraints", "typescript"],
            recommendedFor: [.defined, .exploring],
            language: .english,
            useCase: "에이전트 프로젝트 CLAUDE.md 구조 참고",
            officialBadge: false,
            recommendedRank: 95
        ),

        // 3. Anthropic Quickstarts CLAUDE.md ✅ 200 OK
        CommunityResource(
            id: UUID(uuidString: "00000000-0000-0000-0001-000000000008")!,
            category: .claudeMd,
            displayName: "Anthropic Quickstarts 개발 규칙",
            author: "anthropics",
            summary: "Anthropic 퀵스타트 리포지토리의 공식 CLAUDE.md. 컴퓨터 사용 데모, 에이전트 프레임워크 등 다양한 Claude 앱 개발 규칙을 담고 있어요.",
            starsApprox: 7000,
            repoURL: URL(string: "https://github.com/anthropics/anthropic-quickstarts")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/anthropics/anthropic-quickstarts/main/CLAUDE.md")!,
            tags: ["official", "quickstart", "best-practices", "agent"],
            recommendedFor: [.defined, .exploring, .undecided],
            language: .english,
            useCase: "Claude Code 빠른 시작 시 참고 규칙",
            officialBadge: true,
            recommendedRank: 98
        ),

        // 4. awesome-claude-code 큐레이션 모음 ✅ README 200 OK
        CommunityResource(
            id: UUID(uuidString: "00000000-0000-0000-0001-000000000003")!,
            category: .claudeMd,
            displayName: "awesome-claude-code 큐레이션 모음",
            author: "hesreallyhim",
            summary: "커뮤니티가 수집한 최고 품질 CLAUDE.md 예시들. 다양한 프로젝트 타입(웹/모바일/백엔드)의 실전 패턴을 한 곳에 모아뒀어요. 영감을 얻기에 최고예요.",
            starsApprox: 42000,
            repoURL: URL(string: "https://github.com/hesreallyhim/awesome-claude-code")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/hesreallyhim/awesome-claude-code/main/README.md")!,
            tags: ["collection", "examples", "community", "curated"],
            recommendedFor: [.exploring, .undecided],
            language: .english,
            useCase: "다양한 프로젝트 타입의 CLAUDE.md 예시 탐색",
            officialBadge: false,
            recommendedRank: 90
        ),

        // 5. claude-code-action CLAUDE.md ✅ 200 OK
        CommunityResource(
            id: UUID(uuidString: "00000000-0000-0000-0001-000000000009")!,
            category: .claudeMd,
            displayName: "Claude Code GitHub Action 규칙",
            author: "anthropics",
            summary: "Claude Code를 GitHub Actions CI/CD에 통합하는 공식 액션의 CLAUDE.md. PR 자동화, 코드 리뷰, 테스트 자동화 패턴을 다뤄요.",
            starsApprox: 3000,
            repoURL: URL(string: "https://github.com/anthropics/claude-code-action")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/anthropics/claude-code-action/main/CLAUDE.md")!,
            tags: ["official", "github-actions", "ci-cd", "automation"],
            recommendedFor: [.defined, .exploring],
            language: .english,
            useCase: "GitHub Actions에 Claude Code 통합 시 참고",
            officialBadge: true,
            recommendedRank: 85
        ),

        // ═══════════════════════════════════════════
        // MARK: Skill 카테고리 (3개)
        // ═══════════════════════════════════════════

        // 6. TDD Skill 가이드
        CommunityResource(
            id: UUID(uuidString: "00000000-0000-0000-0001-000000000004")!,
            category: .skill,
            displayName: "TDD 마스터 Skill 가이드",
            author: "anthropics",
            summary: "테스트 주도 개발 워크플로를 Claude Code에 추가하는 Skill 개념. RED→GREEN→IMPROVE 사이클을 자동화하는 방법을 안내해요. 직접 URL을 입력해 추가할 수 있어요.",
            starsApprox: 10000,
            repoURL: URL(string: "https://github.com/anthropics/anthropic-cookbook")!,
            rawURL: nil,
            tags: ["tdd", "testing", "workflow", "quality"],
            recommendedFor: [.defined],
            language: .english,
            useCase: "TDD RED-GREEN-IMPROVE 사이클 자동화",
            officialBadge: false,
            recommendedRank: 80
        ),

        // 7. SwiftUI 패턴 Skill
        CommunityResource(
            id: UUID(uuidString: "00000000-0000-0000-0001-000000000005")!,
            category: .skill,
            displayName: "SwiftUI 패턴 Skill",
            author: "anthropics",
            summary: "SwiftUI 개발에 특화된 Claude Skill 패턴. @Observable, NavigationStack, async/await 등 최신 SwiftUI 관용 코드를 가이드해요. 직접 URL을 입력해 추가할 수 있어요.",
            starsApprox: 5000,
            repoURL: URL(string: "https://github.com/anthropics/anthropic-cookbook")!,
            rawURL: nil,
            tags: ["swift", "swiftui", "ios", "macos", "observable"],
            recommendedFor: [.defined, .exploring],
            language: .english,
            useCase: "SwiftUI 앱 개발 시 관용 코드 자동 적용",
            officialBadge: false,
            recommendedRank: 75
        ),

        // 8. Anthropic Courses 교육 자료
        CommunityResource(
            id: UUID(uuidString: "00000000-0000-0000-0001-000000000010")!,
            category: .skill,
            displayName: "Anthropic 공식 교육 커리큘럼",
            author: "anthropics",
            summary: "Anthropic이 제공하는 공식 Claude 교육 과정. Tool Use, 프롬프트 엔지니어링, 에이전트 구축 등 단계별 학습 자료를 제공해요. GitHub에서 직접 확인하세요.",
            starsApprox: 21000,
            repoURL: URL(string: "https://github.com/anthropics/courses")!,
            rawURL: nil,
            tags: ["official", "education", "tool-use", "prompting"],
            recommendedFor: [.exploring, .undecided],
            language: .english,
            useCase: "Claude API를 처음 배울 때 단계별 학습",
            officialBadge: true,
            recommendedRank: 88
        ),

        // ═══════════════════════════════════════════
        // MARK: 템플릿 카테고리 (2개)
        // ═══════════════════════════════════════════

        // 9. Next.js 풀스택 템플릿 ✅ CLAUDE.md 200 OK
        CommunityResource(
            id: UUID(uuidString: "00000000-0000-0000-0001-000000000007")!,
            category: .template,
            displayName: "Next.js + Claude Code 풀스택 스타터",
            author: "vercel",
            summary: "Next.js 15 App Router + Claude Code 최적화 CLAUDE.md가 포함된 스타터 템플릿. API Routes, Tailwind, TypeScript 설정 완비. canary 브랜치에서 확인해요.",
            starsApprox: 139000,
            repoURL: URL(string: "https://github.com/vercel/next.js")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/vercel/next.js/canary/CLAUDE.md")!,
            tags: ["nextjs", "typescript", "fullstack", "template", "react"],
            recommendedFor: [.exploring, .undecided],
            language: .english,
            useCase: "React/Next.js 풀스택 프로젝트 빠른 시작",
            officialBadge: false,
            recommendedRank: 82
        ),

        // 10. MCP 서버 예시 템플릿
        CommunityResource(
            id: UUID(uuidString: "00000000-0000-0000-0001-000000000011")!,
            category: .template,
            displayName: "MCP 서버 공식 예시 모음",
            author: "modelcontextprotocol",
            summary: "Model Context Protocol 공식 서버 구현 예시. filesystem, git, postgres, fetch 등 실전 MCP 서버를 참고 구현으로 배울 수 있어요.",
            starsApprox: 85000,
            repoURL: URL(string: "https://github.com/modelcontextprotocol/servers")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/modelcontextprotocol/servers/main/README.md")!,
            tags: ["mcp", "template", "typescript", "python", "official"],
            recommendedFor: [.defined, .exploring],
            language: .english,
            useCase: "커스텀 MCP 서버 개발 시 참고 구현",
            officialBadge: true,
            recommendedRank: 90
        ),

        // ═══════════════════════════════════════════
        // MARK: 디자인 가이드 카테고리 (3개)
        // ═══════════════════════════════════════════

        // 11. 보안 강화 가이드라인
        CommunityResource(
            id: UUID(uuidString: "00000000-0000-0000-0001-000000000006")!,
            category: .styleGuide,
            displayName: "보안 강화 가이드라인",
            author: "anthropics",
            summary: "보안 취약점 방지에 특화된 CLAUDE.md 섹션. 시크릿 관리, SQL 인젝션 방어, XSS 예방 등 필수 보안 규칙을 포함해요. GitHub에서 직접 확인하세요.",
            starsApprox: 10000,
            repoURL: URL(string: "https://github.com/anthropics/anthropic-cookbook")!,
            rawURL: nil,
            tags: ["security", "best-practices", "vulnerability", "xss", "sql"],
            recommendedFor: [.defined],
            language: .english,
            useCase: "프로덕션 앱 보안 규칙 설정",
            officialBadge: true,
            recommendedRank: 85
        ),

        // 12. TypeScript 코딩 스타일
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0002-000000000001"),
            category: .styleGuide,
            displayName: "TypeScript 엄격 코딩 스타일",
            author: "microsoft",
            summary: "TypeScript 공식 리포지토리의 코딩 가이드라인. 타입 안전성, strict 모드, 네이밍 컨벤션 등 대규모 TS 프로젝트에서 검증된 규칙을 담고 있어요.",
            starsApprox: 102000,
            repoURL: URL(string: "https://github.com/microsoft/TypeScript")!,
            rawURL: nil,
            tags: ["typescript", "coding-style", "strict", "types"],
            recommendedFor: [.defined, .exploring],
            language: .english,
            useCase: "TypeScript 프로젝트 코딩 컨벤션 참고",
            officialBadge: false,
            recommendedRank: 78
        ),

        // 13. Swift 공식 API 디자인 가이드라인
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0002-000000000002"),
            category: .styleGuide,
            displayName: "Swift API 디자인 가이드라인",
            author: "apple",
            summary: "Apple 공식 Swift API 디자인 가이드라인. 명확한 이름, 문서화, 관용적 Swift 패턴 등 Swift 코드 작성의 핵심 원칙을 다뤄요.",
            starsApprox: 68000,
            repoURL: URL(string: "https://github.com/apple/swift")!,
            rawURL: nil,
            tags: ["swift", "api-design", "naming", "documentation"],
            recommendedFor: [.defined],
            language: .english,
            useCase: "Swift/SwiftUI 라이브러리 API 설계 기준",
            officialBadge: false,
            recommendedRank: 75
        ),

        // ═══════════════════════════════════════════
        // MARK: 워크플로우 카테고리 (3개)
        // ═══════════════════════════════════════════

        // 14. awesome-claude-code 워크플로우
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0003-000000000001"),
            category: .workflow,
            displayName: "Claude Code 워크플로우 베스트 프랙티스",
            author: "hesreallyhim",
            summary: "커뮤니티가 정리한 Claude Code 효율적 사용법. Git 커밋 전략, 코드 리뷰 자동화, TDD 사이클 통합 등 실전 워크플로우 팁을 모아뒀어요.",
            starsApprox: 42000,
            repoURL: URL(string: "https://github.com/hesreallyhim/awesome-claude-code")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/hesreallyhim/awesome-claude-code/main/README.md")!,
            tags: ["workflow", "git", "tdd", "code-review", "automation"],
            recommendedFor: [.exploring, .undecided],
            language: .english,
            useCase: "Claude Code 개발 워크플로우 최적화",
            officialBadge: false,
            recommendedRank: 82
        ),

        // 15. Conventional Commits 스펙
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0003-000000000002"),
            category: .workflow,
            displayName: "Conventional Commits 스펙",
            author: "conventional-commits",
            summary: "구조화된 Git 커밋 메시지 컨벤션. feat/fix/docs/refactor 등 타입을 정의하고 자동화 도구(changelog, semantic versioning)와 연동해요.",
            starsApprox: 7000,
            repoURL: URL(string: "https://github.com/conventional-commits/conventionalcommits.org")!,
            rawURL: nil,
            tags: ["git", "commit", "convention", "changelog", "semver"],
            recommendedFor: [.defined, .exploring],
            language: .multilingual,
            useCase: "팀 Git 커밋 규칙 표준화",
            officialBadge: false,
            recommendedRank: 70
        ),

        // 16. GitHub Actions 워크플로우 모음
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0003-000000000003"),
            category: .workflow,
            displayName: "Claude Code Action CI 워크플로우",
            author: "anthropics",
            summary: "Claude Code를 GitHub Actions에 통합하는 공식 워크플로우. PR 자동 리뷰, 이슈 해결, 코드 개선을 자동화하는 YAML 예시를 제공해요.",
            starsApprox: 3000,
            repoURL: URL(string: "https://github.com/anthropics/claude-code-action")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/anthropics/claude-code-action/main/CLAUDE.md")!,
            tags: ["github-actions", "ci-cd", "automation", "pr-review"],
            recommendedFor: [.defined],
            language: .english,
            useCase: "PR 자동 리뷰 및 CI 파이프라인 구축",
            officialBadge: true,
            recommendedRank: 80
        ),

        // ═══════════════════════════════════════════
        // MARK: 시스템 설계 카테고리 (3개)
        // ═══════════════════════════════════════════

        // 17. modelcontextprotocol 아키텍처 문서
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0004-000000000001"),
            category: .architecture,
            displayName: "MCP 프로토콜 아키텍처 설계",
            author: "modelcontextprotocol",
            summary: "Model Context Protocol의 공식 아키텍처 문서. 클라이언트-서버 구조, 메시지 포맷, 도구 정의 방법을 이해하면 Claude 확장 개발이 훨씬 쉬워져요.",
            starsApprox: 85000,
            repoURL: URL(string: "https://github.com/modelcontextprotocol/servers")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/modelcontextprotocol/servers/main/CLAUDE.md")!,
            tags: ["mcp", "architecture", "protocol", "design"],
            recommendedFor: [.defined, .exploring],
            language: .english,
            useCase: "MCP 서버 설계 이해 및 커스텀 도구 개발",
            officialBadge: true,
            recommendedRank: 85
        ),

        // 18. Claude Code Architecture Patterns
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0004-000000000002"),
            category: .architecture,
            displayName: "Claude Code 에이전트 아키텍처",
            author: "anthropics",
            summary: "Claude Code 에이전트 시스템의 아키텍처 패턴. Orchestrator-Worker, HITL(Human in the Loop), 멀티 에이전트 조율 등 실전 설계를 다뤄요.",
            starsApprox: 7000,
            repoURL: URL(string: "https://github.com/anthropics/anthropic-quickstarts")!,
            rawURL: nil,
            tags: ["agent", "architecture", "orchestrator", "hitl", "multi-agent"],
            recommendedFor: [.defined],
            language: .english,
            useCase: "복잡한 에이전트 시스템 설계 참고",
            officialBadge: true,
            recommendedRank: 80
        ),

        // 19. awesome-scalability 아키텍처 패턴
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0004-000000000003"),
            category: .architecture,
            displayName: "대규모 시스템 확장 패턴",
            author: "binhnguyennus",
            summary: "대규모 시스템 설계의 검증된 패턴 모음. 캐싱, 로드밸런싱, 데이터베이스 샤딩, 마이크로서비스 등 실제 사례와 함께 설명해요.",
            starsApprox: 60000,
            repoURL: URL(string: "https://github.com/binhnguyennus/awesome-scalability")!,
            rawURL: nil,
            tags: ["scalability", "architecture", "distributed", "microservices"],
            recommendedFor: [.defined, .exploring],
            language: .english,
            useCase: "백엔드 시스템 확장 설계 시 참고",
            officialBadge: false,
            recommendedRank: 70
        ),

        // ═══════════════════════════════════════════
        // MARK: 프롬프트 패턴 카테고리 (3개)
        // ═══════════════════════════════════════════

        // 20. Anthropic Cookbook 프롬프트 패턴
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0005-000000000001"),
            category: .promptPattern,
            displayName: "Anthropic 공식 프롬프트 패턴",
            author: "anthropics",
            summary: "Anthropic Cookbook의 검증된 프롬프트 엔지니어링 패턴. 체인 오브 소트, Few-shot, 도구 사용, 다중 턴 대화 등 다양한 패턴을 예시와 함께 배울 수 있어요.",
            starsApprox: 10000,
            repoURL: URL(string: "https://github.com/anthropics/anthropic-cookbook")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/anthropics/anthropic-cookbook/main/CLAUDE.md")!,
            tags: ["prompting", "chain-of-thought", "few-shot", "tool-use"],
            recommendedFor: [.exploring, .undecided],
            language: .english,
            useCase: "Claude 응답 품질 향상 프롬프트 기법 학습",
            officialBadge: true,
            recommendedRank: 85
        ),

        // 21. 프롬프트 엔지니어링 가이드 (DAIR.AI)
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0005-000000000002"),
            category: .promptPattern,
            displayName: "프롬프트 엔지니어링 완전 가이드",
            author: "dair-ai",
            summary: "DAIR.AI가 정리한 프롬프트 엔지니어링 가이드. Zero-shot, CoT, ReAct, Tree of Thoughts 등 최신 기법을 체계적으로 설명해요. 한국어 번역도 있어요.",
            starsApprox: 55000,
            repoURL: URL(string: "https://github.com/dair-ai/Prompt-Engineering-Guide")!,
            rawURL: nil,
            tags: ["prompting", "cot", "react", "zero-shot", "education"],
            recommendedFor: [.exploring, .undecided],
            language: .multilingual,
            useCase: "프롬프트 엔지니어링 체계적 학습",
            officialBadge: false,
            recommendedRank: 82
        ),

        // 22. awesome-prompts 컬렉션
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0005-000000000003"),
            category: .promptPattern,
            displayName: "커뮤니티 프롬프트 컬렉션",
            author: "f/awesome-chatgpt-prompts",
            summary: "검증된 AI 프롬프트 대규모 모음. 역할 기반, 작업 특화, 창의적 프롬프트 등 다양한 카테고리로 정리. Claude에도 동일하게 적용 가능해요.",
            starsApprox: 120000,
            repoURL: URL(string: "https://github.com/f/awesome-chatgpt-prompts")!,
            rawURL: nil,
            tags: ["prompts", "collection", "role-play", "creative"],
            recommendedFor: [.exploring, .undecided],
            language: .english,
            useCase: "다양한 작업에 맞는 프롬프트 빠르게 찾기",
            officialBadge: false,
            recommendedRank: 70
        ),

        // ═══════════════════════════════════════════
        // MARK: 에디터 규칙 카테고리 (3개)
        // ═══════════════════════════════════════════

        // 23. awesome-claude-code rules 모음
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0006-000000000001"),
            category: .rules,
            displayName: "Claude Code Rules 큐레이션",
            author: "hesreallyhim",
            summary: "커뮤니티가 수집한 Claude Code 규칙 파일 모음. .claude/rules/ 디렉토리에 넣을 수 있는 검증된 규칙들을 카테고리별로 정리했어요.",
            starsApprox: 42000,
            repoURL: URL(string: "https://github.com/hesreallyhim/awesome-claude-code")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/hesreallyhim/awesome-claude-code/main/README.md")!,
            tags: ["rules", "claude-code", "collection", "curated"],
            recommendedFor: [.defined, .exploring],
            language: .english,
            useCase: "프로젝트에 맞는 Claude Code 규칙 선택",
            officialBadge: false,
            recommendedRank: 80
        ),

        // 24. Cursor Rules 모음
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0006-000000000002"),
            category: .rules,
            displayName: "Cursor Rules 커뮤니티 모음",
            author: "PatrickJS",
            summary: ".cursor.rules 파일 모음. TypeScript, React, Next.js, Python 등 기술 스택별로 최적화된 AI 에디터 규칙을 찾을 수 있어요. Claude에도 적용 가능해요.",
            starsApprox: 25000,
            repoURL: URL(string: "https://github.com/PatrickJS/awesome-cursorrules")!,
            rawURL: nil,
            tags: ["cursor", "rules", "typescript", "react", "python"],
            recommendedFor: [.exploring, .undecided],
            language: .english,
            useCase: "기술 스택별 AI 에디터 규칙 빠르게 적용",
            officialBadge: false,
            recommendedRank: 75
        ),

        // 25. Cline Rules 모음
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0006-000000000003"),
            category: .rules,
            displayName: "Cline Coding Rules 가이드",
            author: "cline",
            summary: "Cline 에이전트가 생성하는 코드 품질을 높이는 규칙 가이드. TypeScript, Python, 보안, 테스트 등 카테고리별 규칙 작성 방법을 알려줘요.",
            starsApprox: 61000,
            repoURL: URL(string: "https://github.com/cline/cline")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/cline/cline/main/CLAUDE.md")!,
            tags: ["cline", "rules", "coding-style", "typescript", "security"],
            recommendedFor: [.defined],
            language: .english,
            useCase: "Cline/Claude 코드 생성 품질 향상",
            officialBadge: false,
            recommendedRank: 72
        ),

        // ═══════════════════════════════════════════
        // MARK: MCP 서버 카테고리 (3개)
        // ═══════════════════════════════════════════

        // 26. modelcontextprotocol 공식 서버 ✅ 200 OK
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0007-000000000001"),
            category: .mcp,
            displayName: "MCP 공식 서버 구현체",
            author: "modelcontextprotocol",
            summary: "Anthropic이 관리하는 공식 MCP 서버 모음. filesystem, git, postgres, fetch, memory 등 실전에서 바로 쓸 수 있는 서버를 포함해요.",
            starsApprox: 85000,
            repoURL: URL(string: "https://github.com/modelcontextprotocol/servers")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/modelcontextprotocol/servers/main/CLAUDE.md")!,
            tags: ["mcp", "official", "filesystem", "git", "postgres", "fetch"],
            recommendedFor: [.defined, .exploring],
            language: .english,
            useCase: "Claude에 파일 시스템, DB, 웹 도구 연결",
            officialBadge: true,
            recommendedRank: 98
        ),

        // 27. awesome-mcp-servers ✅ 200 OK
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0007-000000000002"),
            category: .mcp,
            displayName: "awesome-mcp-servers 큐레이션",
            author: "punkpeye",
            summary: "커뮤니티가 수집한 MCP 서버 대규모 모음. Slack, GitHub, Notion, Jira 등 다양한 외부 서비스를 Claude에 연결하는 서버들을 찾을 수 있어요.",
            starsApprox: 86000,
            repoURL: URL(string: "https://github.com/punkpeye/awesome-mcp-servers")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/punkpeye/awesome-mcp-servers/main/README.md")!,
            tags: ["mcp", "collection", "slack", "github", "notion", "integrations"],
            recommendedFor: [.exploring, .undecided],
            language: .english,
            useCase: "필요한 외부 서비스 MCP 서버 검색",
            officialBadge: false,
            recommendedRank: 92
        ),

        // 28. claude-code-action MCP 통합
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0007-000000000003"),
            category: .mcp,
            displayName: "Claude Code Action MCP 설정",
            author: "anthropics",
            summary: "Claude Code GitHub Action과 MCP 서버를 통합하는 방법. CI/CD 파이프라인에서 MCP 서버를 활용해 더 강력한 자동화를 구현해요.",
            starsApprox: 3000,
            repoURL: URL(string: "https://github.com/anthropics/claude-code-action")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/anthropics/claude-code-action/main/CLAUDE.md")!,
            tags: ["mcp", "github-actions", "integration", "ci-cd", "official"],
            recommendedFor: [.defined],
            language: .english,
            useCase: "GitHub Actions에서 MCP 서버 활용 자동화",
            officialBadge: true,
            recommendedRank: 75
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

    /// 추천도 기준 정렬 (높은 순)
    public static func sorted(by resources: [CommunityResource]) -> [CommunityResource] {
        resources.sorted { $0.recommendedRank > $1.recommendedRank }
    }

    /// 공식 배지 있는 자료만
    public static var officialResources: [CommunityResource] {
        curated.filter { $0.officialBadge }
    }

    /// 언어별 필터링
    public static func resources(for language: CommunityResource.Language) -> [CommunityResource] {
        curated.filter { $0.language == language }
    }
}

// MARK: - UUID 헬퍼 (ADR-112 신규 자료 UUID 생성용)

private extension UUID {
    /// "usdingString" — UUID(usdingString:) 는 UUID(uuidString:) 와 동일하나
    /// nil-safe fatalError 패턴 대신 기본 UUID() 폴백을 반환.
    init(usdingString string: String) {
        self = UUID(uuidString: string) ?? UUID()
    }
}
