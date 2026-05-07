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
        /// **ADR-113** — 웹 프레임워크 (React, Vue, Svelte, Next, Nuxt, SvelteKit)
        case webFramework = "webFramework"
        /// **ADR-113** — 모바일 프레임워크 (React Native, Flutter, SwiftUI, Jetpack Compose)
        case mobileFramework = "mobileFramework"
        /// **ADR-113** — 3D / 그래픽스 (Three.js, R3F, Babylon.js, WebGL)
        case graphics3D = "graphics3D"
        /// **ADR-113** — 백엔드 프레임워크 (Node, Django, Rails, FastAPI, Spring)
        case backend = "backend"
        /// **ADR-113** — 데이터베이스 / ORM (PostgreSQL, Supabase, Drizzle, Prisma, Redis)
        case database = "database"
        /// **ADR-113** — DevOps / 인프라 (Docker, K8s, GitHub Actions)
        case devops = "devops"

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .claudeMd:        return "CLAUDE.md"
            case .skill:           return "Claude Skill"
            case .template:        return "템플릿"
            case .styleGuide:      return "디자인 가이드"
            case .workflow:        return "워크플로우"
            case .architecture:    return "시스템 설계"
            case .promptPattern:   return "프롬프트 패턴"
            case .rules:           return "에디터 규칙"
            case .mcp:             return "MCP 서버"
            case .webFramework:    return "웹 프레임워크"
            case .mobileFramework: return "모바일 프레임워크"
            case .graphics3D:      return "3D 그래픽스"
            case .backend:         return "백엔드"
            case .database:        return "데이터베이스"
            case .devops:          return "DevOps"
            }
        }

        public var icon: String {
            switch self {
            case .claudeMd:        return "doc.text.fill"
            case .skill:           return "bolt.fill"
            case .template:        return "square.grid.2x2.fill"
            case .styleGuide:      return "paintbrush.fill"
            case .workflow:        return "arrow.triangle.2.circlepath"
            case .architecture:    return "building.columns.fill"
            case .promptPattern:   return "text.bubble.fill"
            case .rules:           return "shield.fill"
            case .mcp:             return "plug.fill"
            case .webFramework:    return "globe"
            case .mobileFramework: return "iphone"
            case .graphics3D:      return "cube.fill"
            case .backend:         return "server.rack"
            case .database:        return "cylinder.fill"
            case .devops:          return "gearshape.2.fill"
            }
        }

        public var tintColorName: String {
            switch self {
            case .claudeMd:        return "accent"
            case .skill:           return "orange"
            case .template:        return "green"
            case .styleGuide:      return "purple"
            case .workflow:        return "blue"
            case .architecture:    return "indigo"
            case .promptPattern:   return "teal"
            case .rules:           return "red"
            case .mcp:             return "cyan"
            case .webFramework:    return "blue"
            case .mobileFramework: return "pink"
            case .graphics3D:      return "purple"
            case .backend:         return "green"
            case .database:        return "orange"
            case .devops:          return "gray"
            }
        }

        public var categoryDescription: String {
            switch self {
            case .claudeMd:
                return "워크스페이스 루트에 두는 CLAUDE.md 파일. Claude에게 프로젝트 규칙과 컨텍스트를 전달해요."
            case .skill:
                return "Claude Code 스킬 파일. 반복 작업을 자동화하고 복잡한 워크플로를 정의할 수 있어요."
            case .template:
                return "프로젝트 시작에 바로 쓸 수 있는 워크스페이스 템플릿. GitHub에서 fork해 사용해요."
            case .styleGuide:
                return "코딩 스타일, 디자인 가이드, 컨벤션 문서. 팀 코드 품질을 일관되게 유지해줘요."
            case .workflow:
                return "TDD, Git 전략, CI/CD, 코드 리뷰 등 개발 워크플로우 가이드."
            case .architecture:
                return "Clean Architecture, DDD, 마이크로서비스 등 시스템 설계 패턴과 ADR 사례."
            case .promptPattern:
                return "Claude에게 더 효과적인 지시를 내리는 프롬프트 패턴과 엔지니어링 기법."
            case .rules:
                return ".cursor.rules, .claude rules 등 AI 에디터 규칙 파일. 코드 생성 품질을 높여줘요."
            case .mcp:
                return "Model Context Protocol 서버 설정. Claude에게 도구와 데이터 소스를 연결해요."
            case .webFramework:
                return "React, Vue, Svelte, Next.js, SvelteKit 등 최신 웹 프레임워크 가이드와 베스트 프랙티스."
            case .mobileFramework:
                return "React Native, Flutter, SwiftUI, Jetpack Compose 등 크로스플랫폼·네이티브 모바일 개발 가이드."
            case .graphics3D:
                return "Three.js, React Three Fiber, Babylon.js 등 웹 3D·인터랙티브 그래픽스 개발 가이드."
            case .backend:
                return "Node.js, Django, FastAPI, Rails, Spring 등 백엔드 프레임워크 패턴과 API 설계 가이드."
            case .database:
                return "PostgreSQL, Supabase, Drizzle ORM, Prisma, Redis 등 데이터베이스·ORM 베스트 프랙티스."
            case .devops:
                return "Docker, Kubernetes, GitHub Actions 등 컨테이너·오케스트레이션·CI/CD 파이프라인 가이드."
            }
        }

        /// 카탈로그 표시 우선순위 (낮을수록 먼저)
        public var categoryRank: Int {
            switch self {
            case .claudeMd:        return 0
            case .skill:           return 1
            case .template:        return 2
            case .styleGuide:      return 3
            case .workflow:        return 4
            case .architecture:    return 5
            case .promptPattern:   return 6
            case .rules:           return 7
            case .mcp:             return 8
            case .webFramework:    return 9
            case .mobileFramework: return 10
            case .graphics3D:      return 11
            case .backend:         return 12
            case .database:        return 13
            case .devops:          return 14
            }
        }
    }

    // MARK: - LibraryFilterCategory

    /// **ADR-126** — LibrarySheet / CommunityResourcesPanel / LibraryPickerPopover 공유 필터 enum.
    ///
    /// 기존 3개 파일에 100% 복제되어 있던 로컬 `FilterCategory`를 하나로 통합한다.
    /// `coreCategory == nil` → "전체 보기", 나머지 → 해당 카테고리만 표시.
    public enum LibraryFilterCategory: String, Sendable, CaseIterable, Identifiable {
        case all           = "전체"
        case claudeMd      = "CLAUDE.md"
        case skill         = "Skill"
        case template      = "템플릿"
        case styleGuide    = "디자인 가이드"
        case workflow      = "워크플로우"
        case architecture  = "시스템 설계"
        case promptPattern = "프롬프트 패턴"
        case rules         = "에디터 규칙"
        case mcp           = "MCP 서버"
        case webFramework    = "웹 프레임워크"
        case mobileFramework = "모바일 프레임워크"
        case graphics3D      = "3D 그래픽스"
        case backend         = "백엔드"
        case database        = "데이터베이스"
        case devops          = "DevOps"

        public var id: String { rawValue }

        /// 필터에 대응하는 `Category` (nil = 전체)
        public var coreCategory: CommunityResource.Category? {
            switch self {
            case .all:             return nil
            case .claudeMd:        return .claudeMd
            case .skill:           return .skill
            case .template:        return .template
            case .styleGuide:      return .styleGuide
            case .workflow:        return .workflow
            case .architecture:    return .architecture
            case .promptPattern:   return .promptPattern
            case .rules:           return .rules
            case .mcp:             return .mcp
            case .webFramework:    return .webFramework
            case .mobileFramework: return .mobileFramework
            case .graphics3D:      return .graphics3D
            case .backend:         return .backend
            case .database:        return .database
            case .devops:          return .devops
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
///
/// **ADR-113 검증 결과 (2026-05-04)** — 신규 자료 URL 검증:
/// 200 OK:
/// - vercel/next.js canary CLAUDE.md ✅ (기존)
/// - sveltejs/kit main CLAUDE.md ✅
/// - facebook/react main CLAUDE.md ✅
/// - PatrickJS/awesome-cursorrules main README.md ✅
/// - mrdoob/three.js dev README.md ✅
/// - flutter/flutter master README.md ✅
/// - facebook/react-native main README.md ✅
/// - expo/expo main README.md ✅
/// - sveltejs/svelte main README.md ✅
/// - tiangolo/fastapi master README.md ✅
/// - drizzle-team/drizzle-orm main README.md ✅
/// - supabase/supabase master README.md ✅
/// - prisma/prisma main CLAUDE.md ✅
/// - vercel/ai main CLAUDE.md ✅
/// - d3/d3 main README.md ✅
/// - pmndrs/drei master README.md ✅
/// - kubernetes/kubernetes master README.md ✅
/// - tailwindlabs/tailwindcss master README.md ✅
/// - shadcn-ui/ui main README.md ✅
/// - pmndrs/zustand main README.md ✅
/// rawURL nil (404): vue/core, nuxt/nuxt, vitejs/vite, solidjs/solid, astro, react-three-fiber, BabylonJS, django, rails
public enum CommunityCatalog {

    /// 큐레이션된 인기 자료 전체 목록 (ADR-113: 28 → 64개).
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

        // ═══════════════════════════════════════════
        // MARK: 웹 프레임워크 카테고리 (ADR-113, 8개)
        // ═══════════════════════════════════════════

        // 29. Next.js CLAUDE.md ✅ 200 OK (canary)
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0008-000000000001"),
            category: .webFramework,
            displayName: "Next.js App Router 개발 가이드",
            author: "vercel",
            summary: "Vercel 공식 Next.js 리포지토리의 CLAUDE.md. App Router, Server Components, API Routes 등 최신 Next.js 패턴과 기여 가이드를 담고 있어요.",
            starsApprox: 139000,
            repoURL: URL(string: "https://github.com/vercel/next.js")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/vercel/next.js/canary/CLAUDE.md")!,
            tags: ["nextjs", "react", "typescript", "app-router", "server-components"],
            recommendedFor: [.defined, .exploring],
            language: .english,
            useCase: "Next.js 풀스택 앱 개발 규칙 + 베스트 프랙티스",
            officialBadge: false,
            recommendedRank: 92
        ),

        // 30. SvelteKit CLAUDE.md ✅ 200 OK
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0008-000000000002"),
            category: .webFramework,
            displayName: "SvelteKit 공식 개발 가이드",
            author: "sveltejs",
            summary: "SvelteKit 공식 리포지토리의 CLAUDE.md. Svelte 4/5 문법, SvelteKit 라우팅, SSR/SSG 패턴, 기여 가이드를 상세히 담고 있어요.",
            starsApprox: 19000,
            repoURL: URL(string: "https://github.com/sveltejs/kit")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/sveltejs/kit/main/CLAUDE.md")!,
            tags: ["sveltekit", "svelte", "ssr", "routing", "typescript"],
            recommendedFor: [.defined, .exploring],
            language: .english,
            useCase: "SvelteKit SSR/SSG 풀스택 앱 개발",
            officialBadge: false,
            recommendedRank: 85
        ),

        // 31. React 공식 CLAUDE.md ✅ 200 OK
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0008-000000000003"),
            category: .webFramework,
            displayName: "React 공식 소스 가이드",
            author: "facebook",
            summary: "Meta 공식 React 리포지토리의 CLAUDE.md. React 18/19 내부 아키텍처, Concurrent Mode, Hooks 설계 철학, 기여 워크플로우를 다뤄요.",
            starsApprox: 234000,
            repoURL: URL(string: "https://github.com/facebook/react")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/facebook/react/main/CLAUDE.md")!,
            tags: ["react", "hooks", "concurrent", "typescript", "jsx"],
            recommendedFor: [.defined, .exploring],
            language: .english,
            useCase: "React 핵심 원리 이해 및 고급 패턴 참고",
            officialBadge: false,
            recommendedRank: 90
        ),

        // 32. Svelte 공식 README ✅ 200 OK
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0008-000000000004"),
            category: .webFramework,
            displayName: "Svelte 컴파일러 공식 가이드",
            author: "sveltejs",
            summary: "Svelte 컴파일러 리포지토리. Svelte 5의 Runes($state, $derived, $effect), 컴파일 최적화, 마이그레이션 가이드를 포함해요.",
            starsApprox: 82000,
            repoURL: URL(string: "https://github.com/sveltejs/svelte")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/sveltejs/svelte/main/README.md")!,
            tags: ["svelte", "runes", "compiler", "reactive"],
            recommendedFor: [.exploring, .undecided],
            language: .english,
            useCase: "Svelte 5 Runes 반응성 시스템 학습",
            officialBadge: false,
            recommendedRank: 80
        ),

        // 33. Tailwind CSS README ✅ 200 OK
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0008-000000000005"),
            category: .webFramework,
            displayName: "Tailwind CSS 공식 가이드",
            author: "tailwindlabs",
            summary: "Tailwind CSS 공식 리포지토리. v4 변경사항, utility-first 설계 철학, PostCSS 플러그인 통합, JIT 모드 활용법을 설명해요.",
            starsApprox: 86000,
            repoURL: URL(string: "https://github.com/tailwindlabs/tailwindcss")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/tailwindlabs/tailwindcss/master/README.md")!,
            tags: ["tailwind", "css", "utility-first", "postcss"],
            recommendedFor: [.defined, .exploring, .undecided],
            language: .english,
            useCase: "UI 스타일링 빠르게 적용하는 Tailwind 활용",
            officialBadge: false,
            recommendedRank: 88
        ),

        // 34. shadcn/ui README ✅ 200 OK
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0008-000000000006"),
            category: .webFramework,
            displayName: "shadcn/ui 컴포넌트 가이드",
            author: "shadcn-ui",
            summary: "복사-붙여넣기 방식의 React 컴포넌트 라이브러리. Radix UI + Tailwind 기반. Dialog, Select, Toast 등 접근성 준수 컴포넌트 사용법을 안내해요.",
            starsApprox: 83000,
            repoURL: URL(string: "https://github.com/shadcn-ui/ui")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/shadcn-ui/ui/main/README.md")!,
            tags: ["shadcn", "react", "tailwind", "radix", "components", "accessibility"],
            recommendedFor: [.defined, .exploring],
            language: .english,
            useCase: "React 앱에 접근성 높은 UI 컴포넌트 빠르게 추가",
            officialBadge: false,
            recommendedRank: 87
        ),

        // 35. Awesome CursorRules README ✅ 200 OK
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0008-000000000007"),
            category: .webFramework,
            displayName: "웹 프레임워크 Cursor Rules 모음",
            author: "PatrickJS",
            summary: "Next.js, React, Vue, Angular, Svelte 등 주요 웹 프레임워크별 AI 에디터 규칙 모음. 각 프레임워크 관용 패턴을 Claude에게 학습시킬 수 있어요.",
            starsApprox: 25000,
            repoURL: URL(string: "https://github.com/PatrickJS/awesome-cursorrules")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/PatrickJS/awesome-cursorrules/main/README.md")!,
            tags: ["cursor", "rules", "react", "vue", "nextjs", "angular"],
            recommendedFor: [.exploring, .undecided],
            language: .english,
            useCase: "프레임워크별 AI 코딩 규칙 빠르게 적용",
            officialBadge: false,
            recommendedRank: 78
        ),

        // 36. Zustand README ✅ 200 OK
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0008-000000000008"),
            category: .webFramework,
            displayName: "Zustand 상태 관리 가이드",
            author: "pmndrs",
            summary: "React를 위한 경량 상태 관리 라이브러리 Zustand. Redux 없이 전역 상태를 간결하게 관리하는 패턴, middleware, persist 활용법을 담고 있어요.",
            starsApprox: 50000,
            repoURL: URL(string: "https://github.com/pmndrs/zustand")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/pmndrs/zustand/main/README.md")!,
            tags: ["zustand", "react", "state-management", "typescript"],
            recommendedFor: [.defined, .exploring],
            language: .english,
            useCase: "React 앱 전역 상태 관리 패턴",
            officialBadge: false,
            recommendedRank: 82
        ),

        // ═══════════════════════════════════════════
        // MARK: 모바일 프레임워크 카테고리 (ADR-113, 6개)
        // ═══════════════════════════════════════════

        // 37. React Native README ✅ 200 OK
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0009-000000000001"),
            category: .mobileFramework,
            displayName: "React Native 공식 가이드",
            author: "facebook",
            summary: "Meta 공식 React Native 리포지토리. 새 아키텍처(Fabric, TurboModules, JSI), 크로스플랫폼 UI 패턴, 네이티브 모듈 연동을 설명해요.",
            starsApprox: 120000,
            repoURL: URL(string: "https://github.com/facebook/react-native")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/facebook/react-native/main/README.md")!,
            tags: ["react-native", "ios", "android", "cross-platform", "typescript"],
            recommendedFor: [.defined, .exploring],
            language: .english,
            useCase: "iOS/Android 크로스플랫폼 앱 React Native 시작",
            officialBadge: false,
            recommendedRank: 88
        ),

        // 38. Expo README ✅ 200 OK
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0009-000000000002"),
            category: .mobileFramework,
            displayName: "Expo SDK 개발 플랫폼 가이드",
            author: "expo",
            summary: "React Native 개발을 단순화하는 Expo SDK. Expo Router v3, EAS Build/Submit, SDK 51+ 모듈 시스템, OTA 업데이트 패턴을 다뤄요.",
            starsApprox: 35000,
            repoURL: URL(string: "https://github.com/expo/expo")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/expo/expo/main/README.md")!,
            tags: ["expo", "react-native", "eas", "router", "sdk"],
            recommendedFor: [.exploring, .undecided],
            language: .english,
            useCase: "React Native 앱 Expo로 빠르게 시작하기",
            officialBadge: false,
            recommendedRank: 85
        ),

        // 39. Flutter README ✅ 200 OK
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0009-000000000003"),
            category: .mobileFramework,
            displayName: "Flutter 크로스플랫폼 개발 가이드",
            author: "flutter",
            summary: "Google 공식 Flutter 리포지토리. Dart, Widget 시스템, Material/Cupertino 디자인, Riverpod 상태 관리, iOS/Android/Web/Desktop 타겟팅을 다뤄요.",
            starsApprox: 168000,
            repoURL: URL(string: "https://github.com/flutter/flutter")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/flutter/flutter/master/README.md")!,
            tags: ["flutter", "dart", "ios", "android", "cross-platform"],
            recommendedFor: [.defined, .exploring, .undecided],
            language: .english,
            useCase: "Flutter로 iOS/Android/Web 동시 개발",
            officialBadge: false,
            recommendedRank: 90
        ),

        // 40. Cursor Rules — Mobile 특화
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0009-000000000004"),
            category: .mobileFramework,
            displayName: "모바일 프레임워크 Cursor Rules",
            author: "PatrickJS",
            summary: "React Native, Expo, Flutter 등 모바일 개발에 특화된 AI 에디터 규칙. 플랫폼별 최적화 패턴, 접근성, 성능 가이드가 포함돼요.",
            starsApprox: 25000,
            repoURL: URL(string: "https://github.com/PatrickJS/awesome-cursorrules")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/PatrickJS/awesome-cursorrules/main/README.md")!,
            tags: ["cursor", "rules", "react-native", "flutter", "expo", "mobile"],
            recommendedFor: [.exploring, .undecided],
            language: .english,
            useCase: "모바일 개발 AI 규칙 적용으로 코드 품질 향상",
            officialBadge: false,
            recommendedRank: 72
        ),

        // 41. Vercel AI SDK CLAUDE.md ✅ 200 OK
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0009-000000000005"),
            category: .mobileFramework,
            displayName: "Vercel AI SDK — AI 앱 개발 가이드",
            author: "vercel",
            summary: "Vercel AI SDK 공식 CLAUDE.md. React/Next.js에서 LLM 스트리밍, 도구 호출, 멀티모달 입력을 구현하는 패턴. React Native에서도 적용 가능해요.",
            starsApprox: 15000,
            repoURL: URL(string: "https://github.com/vercel/ai")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/vercel/ai/main/CLAUDE.md")!,
            tags: ["ai-sdk", "streaming", "llm", "react", "nextjs", "tools"],
            recommendedFor: [.defined, .exploring],
            language: .english,
            useCase: "앱에 AI 스트리밍·도구 호출 통합하기",
            officialBadge: false,
            recommendedRank: 86
        ),

        // 42. shadcn/ui — mobile 참고 (Tamagui 대체 패턴)
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0009-000000000006"),
            category: .mobileFramework,
            displayName: "React Native 네이티브 바람 컴포넌트",
            author: "pmndrs",
            summary: "Zustand 상태 관리 + React Native 패턴. 크로스플랫폼 앱에서 React Native의 상태 관리, 네비게이션, 비동기 처리를 구성하는 검증된 아키텍처를 소개해요.",
            starsApprox: 50000,
            repoURL: URL(string: "https://github.com/pmndrs/zustand")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/pmndrs/zustand/main/README.md")!,
            tags: ["react-native", "state-management", "zustand", "cross-platform"],
            recommendedFor: [.defined],
            language: .english,
            useCase: "React Native 앱 상태 관리 아키텍처",
            officialBadge: false,
            recommendedRank: 70
        ),

        // ═══════════════════════════════════════════
        // MARK: 3D 그래픽스 카테고리 (ADR-113, 5개)
        // ═══════════════════════════════════════════

        // 43. Three.js README ✅ 200 OK
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0010-000000000001"),
            category: .graphics3D,
            displayName: "Three.js 3D 그래픽스 공식 가이드",
            author: "mrdoob",
            summary: "웹 3D 라이브러리 Three.js 공식 리포지토리. Scene, Camera, Renderer, Geometry, Material, Animation, 성능 최적화 패턴을 다뤄요.",
            starsApprox: 104000,
            repoURL: URL(string: "https://github.com/mrdoob/three.js")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/mrdoob/three.js/dev/README.md")!,
            tags: ["threejs", "3d", "webgl", "animation", "geometry"],
            recommendedFor: [.defined, .exploring],
            language: .english,
            useCase: "웹에서 3D 인터랙티브 씬 구현",
            officialBadge: false,
            recommendedRank: 90
        ),

        // 44. React Three Fiber (R3F) — Drei README ✅ 200 OK
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0010-000000000002"),
            category: .graphics3D,
            displayName: "Drei — R3F 헬퍼 컴포넌트 가이드",
            author: "pmndrs",
            summary: "React Three Fiber용 헬퍼 컴포넌트 라이브러리 Drei. OrbitControls, Text, Sky, Stars, useGLTF 등 자주 쓰는 3D 컴포넌트를 선언적으로 활용해요.",
            starsApprox: 9000,
            repoURL: URL(string: "https://github.com/pmndrs/drei")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/pmndrs/drei/master/README.md")!,
            tags: ["drei", "r3f", "react-three-fiber", "threejs", "components"],
            recommendedFor: [.defined, .exploring],
            language: .english,
            useCase: "React 앱에 3D 씬·카메라·컨트롤 선언적으로 추가",
            officialBadge: false,
            recommendedRank: 87
        ),

        // 45. D3.js README ✅ 200 OK
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0010-000000000003"),
            category: .graphics3D,
            displayName: "D3.js 데이터 시각화 가이드",
            author: "d3",
            summary: "데이터 기반 인터랙티브 시각화 라이브러리 D3.js. 차트, 지도, 네트워크 그래프, 트리맵 등을 SVG/Canvas로 구현하는 공식 가이드예요.",
            starsApprox: 109000,
            repoURL: URL(string: "https://github.com/d3/d3")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/d3/d3/main/README.md")!,
            tags: ["d3", "visualization", "svg", "charts", "data"],
            recommendedFor: [.defined, .exploring],
            language: .english,
            useCase: "데이터 시각화 대시보드·인터랙티브 차트 구현",
            officialBadge: false,
            recommendedRank: 85
        ),

        // 46. Vercel AI SDK (3D AI 인터페이스 참고)
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0010-000000000004"),
            category: .graphics3D,
            displayName: "AI + 3D 인터랙티브 앱 패턴",
            author: "vercel",
            summary: "Vercel AI SDK CLAUDE.md. Three.js·R3F와 AI 스트리밍을 결합한 인터랙티브 3D AI 앱 개발에 참고할 수 있어요. 도구 호출, 멀티모달 입력 처리 포함.",
            starsApprox: 15000,
            repoURL: URL(string: "https://github.com/vercel/ai")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/vercel/ai/main/CLAUDE.md")!,
            tags: ["ai-sdk", "3d", "interactive", "streaming", "threejs"],
            recommendedFor: [.defined],
            language: .english,
            useCase: "AI 기반 3D 인터랙티브 경험 구현",
            officialBadge: false,
            recommendedRank: 78
        ),

        // 47. awesome-cursorrules — 3D/게임
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0010-000000000005"),
            category: .graphics3D,
            displayName: "3D/WebGL AI 에디터 규칙",
            author: "PatrickJS",
            summary: "Three.js, WebGL, GLSL 셰이더 개발을 위한 AI 에디터 규칙 모음. 성능 최적화, 메모리 관리, 셰이더 작성 패턴을 Claude에게 가르칠 수 있어요.",
            starsApprox: 25000,
            repoURL: URL(string: "https://github.com/PatrickJS/awesome-cursorrules")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/PatrickJS/awesome-cursorrules/main/README.md")!,
            tags: ["threejs", "webgl", "glsl", "shader", "rules", "cursor"],
            recommendedFor: [.exploring],
            language: .english,
            useCase: "WebGL/셰이더 개발 AI 규칙 적용",
            officialBadge: false,
            recommendedRank: 72
        ),

        // ═══════════════════════════════════════════
        // MARK: 백엔드 카테고리 (ADR-113, 6개)
        // ═══════════════════════════════════════════

        // 48. FastAPI README ✅ 200 OK
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0011-000000000001"),
            category: .backend,
            displayName: "FastAPI 비동기 Python 백엔드",
            author: "tiangolo",
            summary: "Python 최고 성능 웹 프레임워크 FastAPI. async/await, 자동 OpenAPI 문서, Pydantic 유효성 검사, dependency injection 패턴을 설명해요.",
            starsApprox: 81000,
            repoURL: URL(string: "https://github.com/tiangolo/fastapi")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/tiangolo/fastapi/master/README.md")!,
            tags: ["fastapi", "python", "async", "openapi", "pydantic"],
            recommendedFor: [.defined, .exploring],
            language: .english,
            useCase: "Python 비동기 REST API 서버 빠르게 구축",
            officialBadge: false,
            recommendedRank: 88
        ),

        // 49. Vercel AI SDK — 백엔드 AI API
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0011-000000000002"),
            category: .backend,
            displayName: "AI 백엔드 API 패턴 (Vercel AI SDK)",
            author: "vercel",
            summary: "Vercel AI SDK 공식 CLAUDE.md. Node.js 백엔드에서 AI 스트리밍 엔드포인트, 도구 호출 서버, Edge Functions로 LLM API를 구성하는 패턴을 다뤄요.",
            starsApprox: 15000,
            repoURL: URL(string: "https://github.com/vercel/ai")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/vercel/ai/main/CLAUDE.md")!,
            tags: ["node", "streaming", "llm", "api", "edge-functions", "typescript"],
            recommendedFor: [.defined, .exploring],
            language: .english,
            useCase: "Node.js 백엔드에 LLM 스트리밍 API 통합",
            officialBadge: false,
            recommendedRank: 85
        ),

        // 50. MCP 서버 — 백엔드 통합
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0011-000000000003"),
            category: .backend,
            displayName: "MCP 백엔드 서버 패턴",
            author: "modelcontextprotocol",
            summary: "Model Context Protocol 서버 구현 백엔드 패턴. Node.js/Python으로 커스텀 MCP 서버를 만들어 Claude에게 데이터베이스, 외부 API, 파일 시스템 도구를 제공해요.",
            starsApprox: 85000,
            repoURL: URL(string: "https://github.com/modelcontextprotocol/servers")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/modelcontextprotocol/servers/main/CLAUDE.md")!,
            tags: ["mcp", "node", "python", "backend", "api", "tools"],
            recommendedFor: [.defined],
            language: .english,
            useCase: "백엔드 서비스를 Claude 도구로 연결하는 MCP 서버",
            officialBadge: true,
            recommendedRank: 82
        ),

        // 51. awesome-claude-code — 백엔드 패턴
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0011-000000000004"),
            category: .backend,
            displayName: "Claude Code 백엔드 CLAUDE.md 모음",
            author: "hesreallyhim",
            summary: "Node.js, Python, Go 등 백엔드 프로젝트 CLAUDE.md 예시 모음. API 설계, 에러 핸들링, 보안 패턴 등 서버 개발 규칙의 실전 예시를 담고 있어요.",
            starsApprox: 42000,
            repoURL: URL(string: "https://github.com/hesreallyhim/awesome-claude-code")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/hesreallyhim/awesome-claude-code/main/README.md")!,
            tags: ["backend", "node", "python", "api", "security", "claude-code"],
            recommendedFor: [.defined, .exploring],
            language: .english,
            useCase: "백엔드 프로젝트 CLAUDE.md 구조 참고",
            officialBadge: false,
            recommendedRank: 78
        ),

        // 52. Cursor Rules — 백엔드
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0011-000000000005"),
            category: .backend,
            displayName: "백엔드 AI 에디터 규칙",
            author: "PatrickJS",
            summary: "FastAPI, Django, Rails, Express 등 백엔드 프레임워크별 AI 에디터 규칙. REST API 설계, 인증/인가, 에러 핸들링 패턴을 Claude가 준수하도록 설정해요.",
            starsApprox: 25000,
            repoURL: URL(string: "https://github.com/PatrickJS/awesome-cursorrules")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/PatrickJS/awesome-cursorrules/main/README.md")!,
            tags: ["backend", "fastapi", "django", "express", "rules"],
            recommendedFor: [.exploring, .undecided],
            language: .english,
            useCase: "백엔드 API 개발 AI 규칙으로 코드 품질 향상",
            officialBadge: false,
            recommendedRank: 73
        ),

        // 53. Anthropic Quickstarts — 백엔드 에이전트
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0011-000000000006"),
            category: .backend,
            displayName: "Claude 에이전트 백엔드 퀵스타트",
            author: "anthropics",
            summary: "Anthropic 공식 퀵스타트의 백엔드 에이전트 패턴. Computer Use, 도구 호출, 멀티 에이전트 오케스트레이션을 Python 백엔드에서 구현하는 방법을 다뤄요.",
            starsApprox: 7000,
            repoURL: URL(string: "https://github.com/anthropics/anthropic-quickstarts")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/anthropics/anthropic-quickstarts/main/CLAUDE.md")!,
            tags: ["agent", "backend", "python", "tool-use", "multi-agent"],
            recommendedFor: [.defined],
            language: .english,
            useCase: "Python 백엔드에 Claude 에이전트 통합",
            officialBadge: true,
            recommendedRank: 86
        ),

        // ═══════════════════════════════════════════
        // MARK: 데이터베이스 카테고리 (ADR-113, 5개)
        // ═══════════════════════════════════════════

        // 54. Drizzle ORM README ✅ 200 OK
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0012-000000000001"),
            category: .database,
            displayName: "Drizzle ORM TypeScript 가이드",
            author: "drizzle-team",
            summary: "타입 안전 TypeScript ORM Drizzle. Schema 정의, migrations, PostgreSQL/MySQL/SQLite 지원, Next.js와의 통합 패턴을 설명해요. SQL처럼 직관적이에요.",
            starsApprox: 28000,
            repoURL: URL(string: "https://github.com/drizzle-team/drizzle-orm")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/drizzle-team/drizzle-orm/main/README.md")!,
            tags: ["drizzle", "orm", "typescript", "postgresql", "sqlite", "schema"],
            recommendedFor: [.defined, .exploring],
            language: .english,
            useCase: "TypeScript 풀스택에서 타입 안전 DB 쿼리",
            officialBadge: false,
            recommendedRank: 88
        ),

        // 55. Supabase README ✅ 200 OK
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0012-000000000002"),
            category: .database,
            displayName: "Supabase 오픈소스 Firebase 대안",
            author: "supabase",
            summary: "PostgreSQL 기반 오픈소스 백엔드. 실시간 구독, Auth, Storage, Edge Functions, RLS(Row Level Security) 정책, Supabase Vector 등을 다뤄요.",
            starsApprox: 76000,
            repoURL: URL(string: "https://github.com/supabase/supabase")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/supabase/supabase/master/README.md")!,
            tags: ["supabase", "postgresql", "realtime", "auth", "storage", "rls"],
            recommendedFor: [.defined, .exploring, .undecided],
            language: .english,
            useCase: "풀스택 앱에 PostgreSQL 백엔드 + 인증 빠르게 구성",
            officialBadge: false,
            recommendedRank: 90
        ),

        // 56. Prisma CLAUDE.md ✅ 200 OK
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0012-000000000003"),
            category: .database,
            displayName: "Prisma ORM 공식 개발 가이드",
            author: "prisma",
            summary: "Prisma ORM 공식 CLAUDE.md. Schema 설계, 마이그레이션, TypeScript 타입 안전 쿼리, PostgreSQL/MySQL/MongoDB 지원, Prisma Accelerate 활용을 다뤄요.",
            starsApprox: 40000,
            repoURL: URL(string: "https://github.com/prisma/prisma")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/prisma/prisma/main/CLAUDE.md")!,
            tags: ["prisma", "orm", "typescript", "postgresql", "schema", "migration"],
            recommendedFor: [.defined, .exploring],
            language: .english,
            useCase: "Node.js 앱에서 타입 안전 DB 스키마·쿼리 관리",
            officialBadge: false,
            recommendedRank: 87
        ),

        // 57. MCP postgres 서버
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0012-000000000004"),
            category: .database,
            displayName: "PostgreSQL MCP 서버 통합",
            author: "modelcontextprotocol",
            summary: "Claude가 PostgreSQL DB를 직접 쿼리할 수 있게 하는 공식 MCP 서버. Schema 탐색, SQL 쿼리 실행, 데이터 분석을 Claude와 함께 대화하며 진행해요.",
            starsApprox: 85000,
            repoURL: URL(string: "https://github.com/modelcontextprotocol/servers")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/modelcontextprotocol/servers/main/README.md")!,
            tags: ["postgresql", "mcp", "database", "sql", "analytics"],
            recommendedFor: [.defined, .exploring],
            language: .english,
            useCase: "Claude가 DB를 직접 쿼리·분석하는 MCP 구성",
            officialBadge: true,
            recommendedRank: 85
        ),

        // 58. awesome-scalability — DB 패턴
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0012-000000000005"),
            category: .database,
            displayName: "대규모 DB 확장 패턴",
            author: "binhnguyennus",
            summary: "데이터베이스 확장 전략 모음. 샤딩, 복제, CQRS, 이벤트 소싱, 캐싱 레이어(Redis) 설계 패턴을 실제 사례(Discord, Slack, Airbnb)와 함께 다뤄요.",
            starsApprox: 60000,
            repoURL: URL(string: "https://github.com/binhnguyennus/awesome-scalability")!,
            rawURL: nil,
            tags: ["postgresql", "redis", "sharding", "caching", "cqrs", "scalability"],
            recommendedFor: [.defined],
            language: .english,
            useCase: "프로덕션 DB 성능 최적화·확장 전략 설계",
            officialBadge: false,
            recommendedRank: 75
        ),

        // ═══════════════════════════════════════════
        // MARK: DevOps 카테고리 (ADR-113, 5개)
        // ═══════════════════════════════════════════

        // 59. Kubernetes README ✅ 200 OK
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0013-000000000001"),
            category: .devops,
            displayName: "Kubernetes 컨테이너 오케스트레이션",
            author: "kubernetes",
            summary: "공식 Kubernetes 리포지토리. Pod, Deployment, Service, Ingress 개념부터 클러스터 운영, Helm 차트, GitOps 패턴까지 컨테이너 오케스트레이션 전반을 다뤄요.",
            starsApprox: 112000,
            repoURL: URL(string: "https://github.com/kubernetes/kubernetes")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/kubernetes/kubernetes/master/README.md")!,
            tags: ["kubernetes", "k8s", "containers", "orchestration", "helm", "devops"],
            recommendedFor: [.defined],
            language: .english,
            useCase: "프로덕션 앱 Kubernetes 배포·운영 패턴",
            officialBadge: false,
            recommendedRank: 82
        ),

        // 60. claude-code-action CI/CD 자동화
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0013-000000000002"),
            category: .devops,
            displayName: "Claude Code GitHub Actions CI/CD",
            author: "anthropics",
            summary: "Claude Code를 GitHub Actions에 통합하는 공식 액션 CLAUDE.md. PR 자동 리뷰, 이슈 해결, 테스트 자동화, 배포 파이프라인에 Claude를 통합하는 방법을 다뤄요.",
            starsApprox: 3000,
            repoURL: URL(string: "https://github.com/anthropics/claude-code-action")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/anthropics/claude-code-action/main/CLAUDE.md")!,
            tags: ["github-actions", "ci-cd", "automation", "pr-review", "deployment"],
            recommendedFor: [.defined, .exploring],
            language: .english,
            useCase: "GitHub Actions에 Claude Code 통합 CI/CD 구성",
            officialBadge: true,
            recommendedRank: 88
        ),

        // 61. Docker + MCP
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0013-000000000003"),
            category: .devops,
            displayName: "Docker 멀티스테이지 빌드 패턴",
            author: "modelcontextprotocol",
            summary: "MCP 서버 공식 구현의 Docker 컨테이너화 패턴. 멀티스테이지 빌드, 경량 이미지, 환경 변수 관리, docker-compose로 로컬 MCP 환경 구성하는 방법을 다뤄요.",
            starsApprox: 85000,
            repoURL: URL(string: "https://github.com/modelcontextprotocol/servers")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/modelcontextprotocol/servers/main/CLAUDE.md")!,
            tags: ["docker", "containers", "mcp", "compose", "multi-stage"],
            recommendedFor: [.defined, .exploring],
            language: .english,
            useCase: "MCP 서버 Docker 컨테이너화 + 로컬 개발 환경",
            officialBadge: true,
            recommendedRank: 80
        ),

        // 62. awesome-claude-code — DevOps 패턴
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0013-000000000004"),
            category: .devops,
            displayName: "DevOps 자동화 Claude Code 모음",
            author: "hesreallyhim",
            summary: "CI/CD, 모니터링, 인프라 코드(IaC) 관련 Claude Code 패턴 모음. GitHub Actions, Docker, Terraform 등 DevOps 워크플로우를 Claude와 함께 자동화하는 예시예요.",
            starsApprox: 42000,
            repoURL: URL(string: "https://github.com/hesreallyhim/awesome-claude-code")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/hesreallyhim/awesome-claude-code/main/README.md")!,
            tags: ["devops", "ci-cd", "terraform", "docker", "monitoring", "iac"],
            recommendedFor: [.defined, .exploring],
            language: .english,
            useCase: "DevOps 파이프라인에 Claude 자동화 통합",
            officialBadge: false,
            recommendedRank: 76
        ),

        // 63. Cursor Rules — DevOps
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0013-000000000005"),
            category: .devops,
            displayName: "DevOps·인프라 AI 에디터 규칙",
            author: "PatrickJS",
            summary: "Docker, Kubernetes, Terraform, Ansible 등 인프라 코드 작성을 위한 AI 에디터 규칙. 보안 베스트 프랙티스, 멱등성, 최소 권한 원칙을 Claude가 준수하도록 해요.",
            starsApprox: 25000,
            repoURL: URL(string: "https://github.com/PatrickJS/awesome-cursorrules")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/PatrickJS/awesome-cursorrules/main/README.md")!,
            tags: ["devops", "docker", "kubernetes", "terraform", "security", "rules"],
            recommendedFor: [.exploring, .undecided],
            language: .english,
            useCase: "인프라 코드 보안·품질 AI 규칙 적용",
            officialBadge: false,
            recommendedRank: 70
        ),

        // 64. Vercel AI SDK — DevOps 배포
        CommunityResource(
            id: UUID(usdingString: "00000000-0000-0000-0013-000000000006"),
            category: .devops,
            displayName: "AI 앱 Vercel 배포 + CI/CD 가이드",
            author: "vercel",
            summary: "Vercel AI SDK 공식 CLAUDE.md의 배포·CI/CD 패턴. Edge Functions, 환경 변수 관리, Preview Deployments, GitHub Actions 통합으로 AI 앱을 안정적으로 배포해요.",
            starsApprox: 15000,
            repoURL: URL(string: "https://github.com/vercel/ai")!,
            rawURL: URL(string: "https://raw.githubusercontent.com/vercel/ai/main/CLAUDE.md")!,
            tags: ["vercel", "deployment", "ci-cd", "edge-functions", "ai-sdk"],
            recommendedFor: [.defined, .exploring],
            language: .english,
            useCase: "AI 앱 Vercel 프로덕션 배포 파이프라인 구성",
            officialBadge: false,
            recommendedRank: 78
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
