import Foundation

/// **ADR-113** — 검증된 스택 조합 번들.
///
/// 사용자가 새 프로젝트를 시작할 때 개별 자료를 하나씩 추가하는 대신,
/// 검증된 "스택 조합"을 한 번에 가져올 수 있다.
/// 예: "Next.js + Tailwind + Supabase 풀스택 번들" → 관련 자료 4-6개 한번에 추가.
///
/// `resourceIds`는 `CommunityCatalog.curated`에 존재하는 UUID를 참조한다.
/// 번들 추가 시 AppModel이 해당 id를 찾아 자동으로 라이브러리에 추가한다.
public struct StackBundle: Sendable, Codable, Hashable, Identifiable {

    // MARK: - BundleCategory

    public enum BundleCategory: String, Sendable, Codable, CaseIterable, Identifiable {
        case fullstackWeb    = "fullstackWeb"     // 풀스택 웹
        case mobileApp       = "mobileApp"        // 모바일 앱
        case interactive3D   = "interactive3D"    // 3D 인터랙티브
        case aiApp           = "aiApp"            // AI 앱
        case dataApp         = "dataApp"          // 데이터 앱
        case backendInfra    = "backendInfra"     // 백엔드 + 인프라

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .fullstackWeb:   return "풀스택 웹"
            case .mobileApp:      return "모바일 앱"
            case .interactive3D:  return "3D 인터랙티브"
            case .aiApp:          return "AI 앱"
            case .dataApp:        return "데이터 앱"
            case .backendInfra:   return "백엔드 + 인프라"
            }
        }

        public var icon: String {
            switch self {
            case .fullstackWeb:   return "globe"
            case .mobileApp:      return "iphone"
            case .interactive3D:  return "cube.fill"
            case .aiApp:          return "brain.head.profile"
            case .dataApp:        return "chart.bar.fill"
            case .backendInfra:   return "server.rack"
            }
        }

        public var tintColorName: String {
            switch self {
            case .fullstackWeb:   return "blue"
            case .mobileApp:      return "pink"
            case .interactive3D:  return "purple"
            case .aiApp:          return "accent"
            case .dataApp:        return "orange"
            case .backendInfra:   return "green"
            }
        }
    }

    // MARK: - 프로퍼티

    public let id: UUID
    /// 번들 이름 (예: "Next.js + Tailwind + Supabase 풀스택")
    public let displayName: String
    /// 1-2줄 한국어 요약
    public let summary: String
    /// 번들 카테고리
    public let category: BundleCategory
    /// 스택 태그 (예: ["nextjs", "tailwind", "supabase"])
    public let stackTags: [String]
    /// 이 번들에 포함된 CommunityResource UUID 목록 (CommunityCatalog.curated 참조)
    public let resourceIds: [UUID]
    /// 추천 사용자 (예: "MVP를 빠르게 만들고 싶은 풀스택 개발자")
    public let recommendedFor: String
    /// 예상 셋업 시간 (예: "30분 ~ 1시간")
    public let estimatedSetupTime: String
    /// 공식 추천 여부
    public let officialBadge: Bool

    // MARK: - 초기화

    public init(
        id: UUID = UUID(),
        displayName: String,
        summary: String,
        category: BundleCategory,
        stackTags: [String],
        resourceIds: [UUID],
        recommendedFor: String,
        estimatedSetupTime: String,
        officialBadge: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.summary = summary
        self.category = category
        self.stackTags = stackTags
        self.resourceIds = resourceIds
        self.recommendedFor = recommendedFor
        self.estimatedSetupTime = estimatedSetupTime
        self.officialBadge = officialBadge
    }

    // MARK: - 헬퍼

    /// 번들에 포함된 자료 수를 표시 문자열로 반환
    public var resourceCountDisplay: String {
        "\(resourceIds.count)개 자료"
    }

    /// CommunityCatalog에서 이 번들에 포함된 실제 CommunityResource 배열 반환
    public var resolvedResources: [CommunityResource] {
        let all = CommunityCatalog.curated
        return resourceIds.compactMap { id in
            all.first { $0.id == id }
        }
    }
}

// MARK: - Equatable (id 기반)

extension StackBundle {
    public static func == (lhs: StackBundle, rhs: StackBundle) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - StackBundleCatalog

/// **ADR-113** — 큐레이션된 스택 번들 카탈로그 (8개).
///
/// 각 번들의 `resourceIds`는 `CommunityCatalog.curated`의 UUID를 참조한다.
/// UUID 매핑 (ADR-113 정의):
/// - Next.js App Router 가이드:       0008-0001
/// - SvelteKit 가이드:                0008-0002
/// - React 공식 가이드:               0008-0003
/// - Svelte README:                   0008-0004
/// - Tailwind CSS:                    0008-0005
/// - shadcn/ui:                       0008-0006
/// - Cursor Rules(웹):                0008-0007
/// - Zustand:                         0008-0008
/// - React Native:                    0009-0001
/// - Expo:                            0009-0002
/// - Flutter:                         0009-0003
/// - Cursor Rules(모바일):            0009-0004
/// - Vercel AI SDK(모바일):           0009-0005
/// - Three.js:                        0010-0001
/// - Drei:                            0010-0002
/// - D3.js:                           0010-0003
/// - Vercel AI SDK(3D):               0010-0004
/// - FastAPI:                         0011-0001
/// - Vercel AI SDK(백엔드):           0011-0002
/// - MCP 백엔드:                      0011-0003
/// - Claude Code 백엔드 모음:         0011-0004
/// - Claude 에이전트 퀵스타트:        0011-0006
/// - Drizzle ORM:                     0012-0001
/// - Supabase:                        0012-0002
/// - Prisma:                          0012-0003
/// - PostgreSQL MCP:                  0012-0004
/// - Kubernetes:                      0013-0001
/// - Claude Code GitHub Actions:      0013-0002
/// - Docker MCP:                      0013-0003
/// - DevOps 모음:                     0013-0004
/// - Vercel AI SDK(DevOps):           0013-0006
/// - Anthropic Cookbook:              0001-0001
/// - Vercel Next.js CLAUDE.md(기존):  0001-0007
/// - MCP 공식 서버:                   0007-0001
/// - Vercel AI SDK(기존 app):         0009-0005
public enum StackBundleCatalog {

    private static func uid(_ s: String) -> UUID {
        UUID(uuidString: s) ?? UUID()
    }

    /// 큐레이션된 번들 목록 (8개, ADR-113).
    public static let curated: [StackBundle] = [

        // ───────────────────────────────────────────
        // 1. Next.js 풀스택 모던 웹
        // ───────────────────────────────────────────
        StackBundle(
            id: uid("AA000001-0000-0000-0000-000000000001"),
            displayName: "Next.js 풀스택 모던 웹",
            summary: "Next.js 15 App Router + Tailwind + shadcn/ui + Supabase + TypeScript. MVP부터 프로덕션까지 검증된 풀스택 웹 스택이에요.",
            category: .fullstackWeb,
            stackTags: ["nextjs", "tailwind", "shadcn", "supabase", "typescript"],
            resourceIds: [
                uid("00000000-0000-0000-0008-000000000001"), // Next.js CLAUDE.md
                uid("00000000-0000-0000-0008-000000000005"), // Tailwind CSS
                uid("00000000-0000-0000-0008-000000000006"), // shadcn/ui
                uid("00000000-0000-0000-0012-000000000002"), // Supabase
                uid("00000000-0000-0000-0001-000000000007"), // Next.js 스타터 템플릿
            ],
            recommendedFor: "MVP를 빠르게 만들고 싶은 풀스택 개발자",
            estimatedSetupTime: "30분 ~ 1시간",
            officialBadge: true
        ),

        // ───────────────────────────────────────────
        // 2. React + Zustand 프론트엔드 SPA
        // ───────────────────────────────────────────
        StackBundle(
            id: uid("AA000001-0000-0000-0000-000000000002"),
            displayName: "React + Zustand SPA 스타터",
            summary: "React 19 + Zustand 상태 관리 + Tailwind + shadcn/ui. 순수 프론트엔드 SPA를 체계적으로 구성하는 스택이에요.",
            category: .fullstackWeb,
            stackTags: ["react", "zustand", "tailwind", "shadcn", "typescript"],
            resourceIds: [
                uid("00000000-0000-0000-0008-000000000003"), // React 공식
                uid("00000000-0000-0000-0008-000000000008"), // Zustand
                uid("00000000-0000-0000-0008-000000000005"), // Tailwind
                uid("00000000-0000-0000-0008-000000000006"), // shadcn/ui
                uid("00000000-0000-0000-0008-000000000007"), // Cursor Rules 웹
            ],
            recommendedFor: "백엔드 없이 React SPA를 빠르게 구성하려는 개발자",
            estimatedSetupTime: "20 ~ 40분"
        ),

        // ───────────────────────────────────────────
        // 3. SvelteKit 풀스택 시작
        // ───────────────────────────────────────────
        StackBundle(
            id: uid("AA000001-0000-0000-0000-000000000003"),
            displayName: "SvelteKit + Drizzle 풀스택",
            summary: "SvelteKit + Drizzle ORM + Supabase PostgreSQL + Tailwind. Svelte 5 Runes 반응성과 타입 안전 DB를 결합한 경량 풀스택이에요.",
            category: .fullstackWeb,
            stackTags: ["sveltekit", "svelte", "drizzle", "supabase", "tailwind"],
            resourceIds: [
                uid("00000000-0000-0000-0008-000000000002"), // SvelteKit
                uid("00000000-0000-0000-0008-000000000004"), // Svelte 컴파일러
                uid("00000000-0000-0000-0012-000000000001"), // Drizzle ORM
                uid("00000000-0000-0000-0012-000000000002"), // Supabase
                uid("00000000-0000-0000-0008-000000000005"), // Tailwind
            ],
            recommendedFor: "React 대신 Svelte로 가볍고 빠른 풀스택을 원하는 개발자",
            estimatedSetupTime: "30 ~ 60분"
        ),

        // ───────────────────────────────────────────
        // 4. React Native + Expo 모바일 앱
        // ───────────────────────────────────────────
        StackBundle(
            id: uid("AA000001-0000-0000-0000-000000000004"),
            displayName: "React Native + Expo 모바일 앱",
            summary: "React Native + Expo SDK + Zustand + Expo Router. iOS/Android 동시 개발을 위한 검증된 모바일 앱 스타터 스택이에요.",
            category: .mobileApp,
            stackTags: ["react-native", "expo", "zustand", "typescript", "ios", "android"],
            resourceIds: [
                uid("00000000-0000-0000-0009-000000000001"), // React Native
                uid("00000000-0000-0000-0009-000000000002"), // Expo
                uid("00000000-0000-0000-0008-000000000008"), // Zustand (상태 관리)
                uid("00000000-0000-0000-0009-000000000004"), // Cursor Rules 모바일
            ],
            recommendedFor: "iOS/Android 앱을 JavaScript로 한 번에 개발하려는 개발자",
            estimatedSetupTime: "40 ~ 90분"
        ),

        // ───────────────────────────────────────────
        // 5. Flutter 크로스플랫폼 앱
        // ───────────────────────────────────────────
        StackBundle(
            id: uid("AA000001-0000-0000-0000-000000000005"),
            displayName: "Flutter 크로스플랫폼 앱",
            summary: "Flutter + Dart + Riverpod 상태 관리. iOS/Android/Web/Desktop을 하나의 코드베이스로 커버하는 Google 공식 크로스플랫폼 스택이에요.",
            category: .mobileApp,
            stackTags: ["flutter", "dart", "riverpod", "cross-platform"],
            resourceIds: [
                uid("00000000-0000-0000-0009-000000000003"), // Flutter
                uid("00000000-0000-0000-0009-000000000004"), // Cursor Rules 모바일
            ],
            recommendedFor: "Dart로 iOS/Android/Web 앱을 동시에 개발하려는 개발자",
            estimatedSetupTime: "1 ~ 2시간"
        ),

        // ───────────────────────────────────────────
        // 6. Three.js 인터랙티브 3D 웹
        // ───────────────────────────────────────────
        StackBundle(
            id: uid("AA000001-0000-0000-0000-000000000006"),
            displayName: "Three.js + R3F 인터랙티브 3D",
            summary: "Three.js + React Three Fiber + Drei 헬퍼. 웹에서 3D 씬, 물리 시뮬레이션, 인터랙티브 경험을 선언적으로 구현하는 스택이에요.",
            category: .interactive3D,
            stackTags: ["threejs", "r3f", "drei", "webgl", "react"],
            resourceIds: [
                uid("00000000-0000-0000-0010-000000000001"), // Three.js
                uid("00000000-0000-0000-0010-000000000002"), // Drei
                uid("00000000-0000-0000-0008-000000000003"), // React 공식
                uid("00000000-0000-0000-0010-000000000005"), // Cursor Rules 3D
            ],
            recommendedFor: "웹에서 인터랙티브 3D 경험을 만들고 싶은 개발자",
            estimatedSetupTime: "1 ~ 3시간"
        ),

        // ───────────────────────────────────────────
        // 7. Next.js + Vercel AI SDK — AI 풀스택 앱
        // ───────────────────────────────────────────
        StackBundle(
            id: uid("AA000001-0000-0000-0000-000000000007"),
            displayName: "AI 풀스택 앱 (Next.js + Vercel AI)",
            summary: "Next.js + Vercel AI SDK + Anthropic Claude + Supabase. AI 스트리밍, 도구 호출, 대화 히스토리 저장까지 갖춘 AI 앱 풀스택이에요.",
            category: .aiApp,
            stackTags: ["nextjs", "vercel-ai", "anthropic", "claude", "streaming"],
            resourceIds: [
                uid("00000000-0000-0000-0008-000000000001"), // Next.js
                uid("00000000-0000-0000-0009-000000000005"), // Vercel AI SDK
                uid("00000000-0000-0000-0001-000000000001"), // Anthropic Cookbook
                uid("00000000-0000-0000-0012-000000000002"), // Supabase (대화 저장)
                uid("00000000-0000-0000-0001-000000000008"), // Anthropic Quickstarts
            ],
            recommendedFor: "Claude API로 AI 앱을 빠르게 출시하려는 개발자",
            estimatedSetupTime: "1 ~ 2시간",
            officialBadge: true
        ),

        // ───────────────────────────────────────────
        // 8. FastAPI + Supabase + Docker 백엔드
        // ───────────────────────────────────────────
        StackBundle(
            id: uid("AA000001-0000-0000-0000-000000000008"),
            displayName: "FastAPI + Supabase 백엔드 API",
            summary: "FastAPI + Supabase PostgreSQL + Prisma ORM + Docker. Python 비동기 REST API 서버를 컨테이너화해 배포까지 완성하는 백엔드 스택이에요.",
            category: .backendInfra,
            stackTags: ["fastapi", "python", "supabase", "postgresql", "docker"],
            resourceIds: [
                uid("00000000-0000-0000-0011-000000000001"), // FastAPI
                uid("00000000-0000-0000-0012-000000000002"), // Supabase
                uid("00000000-0000-0000-0012-000000000003"), // Prisma
                uid("00000000-0000-0000-0013-000000000003"), // Docker MCP
                uid("00000000-0000-0000-0013-000000000002"), // GitHub Actions
            ],
            recommendedFor: "Python 비동기 백엔드를 빠르게 구축·배포하려는 개발자",
            estimatedSetupTime: "1 ~ 2시간"
        ),

        // ───────────────────────────────────────────
        // 9. 데이터 시각화 앱 (D3 + React)
        // ───────────────────────────────────────────
        StackBundle(
            id: uid("AA000001-0000-0000-0000-000000000009"),
            displayName: "데이터 시각화 앱 (D3 + React)",
            summary: "D3.js + React + Tailwind + Supabase. 인터랙티브 대시보드와 데이터 시각화 앱을 빠르게 구성하는 스택이에요.",
            category: .dataApp,
            stackTags: ["d3", "react", "tailwind", "supabase", "charts"],
            resourceIds: [
                uid("00000000-0000-0000-0010-000000000003"), // D3.js
                uid("00000000-0000-0000-0008-000000000003"), // React
                uid("00000000-0000-0000-0008-000000000005"), // Tailwind
                uid("00000000-0000-0000-0012-000000000002"), // Supabase
            ],
            recommendedFor: "데이터 분석·시각화 대시보드를 구축하려는 개발자",
            estimatedSetupTime: "1 ~ 3시간"
        ),
    ]

    /// 카테고리별 필터링
    public static func bundles(for category: StackBundle.BundleCategory) -> [StackBundle] {
        curated.filter { $0.category == category }
    }

    /// 공식 배지 번들만
    public static var officialBundles: [StackBundle] {
        curated.filter { $0.officialBadge }
    }

    /// **ADR-115 P1-4** — ProjectProfile의 detected stack으로 매칭 번들 추천.
    ///
    /// 매칭 알고리즘:
    /// 1. `projectProfile.frameworks`를 소문자로 정규화 → StackBundle.stackTags와 교집합 계산.
    /// 2. platform + primaryLanguage를 tag 목록에 추가해 더 넓은 매칭 지원.
    /// 3. 교집합 크기가 큰 번들 순으로 정렬 → 상위 `limit`개 반환.
    /// 4. 교집합이 0인 번들은 제외 (의미 없는 추천 방지).
    ///
    /// - Parameters:
    ///   - profile: 감지된 ProjectProfile
    ///   - limit: 최대 반환 수 (기본 3)
    /// - Returns: 교집합 크기 내림차순 StackBundle 배열 (빈 배열 가능)
    public static func findMatching(for profile: ProjectProfile, limit: Int = 3) -> [StackBundle] {
        // profile에서 후보 키워드 수집 (소문자 정규화)
        var profileTags: Set<String> = []

        // frameworks — 쉼표/공백 분리 후 소문자 정규화
        for fw in profile.frameworks {
            let normalized = fw.lowercased()
                .replacingOccurrences(of: ".js", with: "js")  // Next.js → nextjs
                .replacingOccurrences(of: " ", with: "-")     // React Native → react-native
            profileTags.insert(normalized)
            // 원본도 추가 (partial 매칭)
            profileTags.insert(fw.lowercased())
        }

        // platform → tag
        switch profile.platform {
        case .web:                         profileTags.insert("web")
        case .iosApp:                      profileTags.formUnion(["ios", "swift", "swiftui"])
        case .androidApp:                  profileTags.formUnion(["android", "kotlin"])
        case .mobile:                      profileTags.formUnion(["mobile", "react-native", "flutter"])
        case .backend:                     profileTags.insert("backend")
        case .macosApp:                    profileTags.formUnion(["macos", "swift"])
        case .dataScience:                 profileTags.formUnion(["data", "python"])
        default:                           break
        }

        // primaryLanguage → tag
        switch profile.primaryLanguage {
        case .typescript:   profileTags.insert("typescript")
        case .javascript:   profileTags.insert("javascript")
        case .python:       profileTags.insert("python")
        case .swift:        profileTags.insert("swift")
        case .dart:         profileTags.formUnion(["dart", "flutter"])
        case .kotlin:       profileTags.insert("kotlin")
        default:            break
        }

        guard !profileTags.isEmpty else { return [] }

        // 번들별 교집합 크기 계산
        let scored: [(bundle: StackBundle, score: Int)] = curated.compactMap { bundle in
            let bundleTags = Set(bundle.stackTags.map { $0.lowercased() })
            let intersect = profileTags.intersection(bundleTags).count
            guard intersect > 0 else { return nil }
            return (bundle, intersect)
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map(\.bundle)
    }
}
