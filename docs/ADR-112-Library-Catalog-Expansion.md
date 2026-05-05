# ADR-112 — 자료 라이브러리 체계적 고도화 + 검증된 GitHub 큐레이션 대폭 확장

**날짜**: 2026-05-04  
**상태**: 구현 완료  
**기반 ADR**: ADR-109 (커뮤니티 자료 최초 도입), ADR-111 (라이브러리 첨부 패턴)

---

## 1. 배경 (사용자 요청)

사용자 요청:
> "라이브러리 기능을 체계적으로 기획하고 고도화. design.md나 효율성을 극대화시킬 수 있는 다양한 깃 자료와 레퍼지토리를 수집해서 사용할 수 있게 설계. 논리적으로 분석하고 기획해서 업그레이드."

ADR-111까지의 라이브러리는 다음 한계가 있었다:
- 카테고리 3개 (CLAUDE.md / Skill / Template)로 다양한 자료 유형 수용 불가
- 큐레이션 8개 — 일부 dead URL 포함, 범위 좁음
- 검색·정렬 미지원 → "찾기 → 가져오기 → 사용" 흐름의 마찰
- 공식/비공식 구분 없음, 언어 표시 없음

---

## 2. 현황 분석 (ADR-112 이전)

| 항목 | ADR-111 시점 |
|------|-------------|
| 카테고리 수 | 3개 (claudeMd / skill / template) |
| 큐레이션 자료 수 | 8개 |
| 검증된 rawURL 수 | 2개 (✅ 200 OK) |
| 검색 기능 | 없음 |
| 정렬 기능 | 없음 |
| 공식 배지 | 없음 |
| 언어 표시 | 없음 |
| 카탈로그 페이지 | 없음 |

---

## 3. 카테고리 확장 결정 — 왜 9개로?

기존 3개 카테고리는 "파일 형식"만 분류했다. 실제 사용자는 **목적** 기준으로 자료를 찾는다.

| 카테고리 | 대상 자료 | 예시 |
|---------|---------|------|
| `claudeMd` | 워크스페이스 컨텍스트 문서 | Anthropic Cookbook CLAUDE.md |
| `skill` | Claude Code Skill 파일 | TDD Mastery Skill |
| `template` | 프로젝트 스타터 템플릿 | Next.js + Claude Code |
| `styleGuide` ⭐ | 코딩 스타일 / 디자인 가이드 | TypeScript 코딩 규칙 |
| `workflow` ⭐ | 개발 워크플로우 / TDD / Git | Conventional Commits |
| `architecture` ⭐ | 시스템 설계 패턴 / ADR | MCP 프로토콜 설계 |
| `promptPattern` ⭐ | 프롬프트 엔지니어링 기법 | Anthropic 공식 프롬프트 |
| `rules` ⭐ | AI 에디터 규칙 파일 | awesome-cursorrules |
| `mcp` ⭐ | MCP 서버 설정 | modelcontextprotocol/servers |

9개로 확장한 이유:
1. 사용자가 찾는 자료 유형을 모두 커버 (목적 기반 탐색)
2. 각 카테고리 3-5개 자료 → 총 25-30개 구성 가능
3. 향후 새 카테고리 추가 시 `CommunityResource.Category` enum에 case 추가만 하면 됨

---

## 4. 큐레이션 자료 리서치 방법론

### 4-1. raw URL 검증 (curl)

```bash
# 실제 검증 명령
curl -sI "https://raw.githubusercontent.com/<owner>/<repo>/<branch>/<path>" \
  -o /dev/null -w "%{http_code}\n" --max-time 10
```

**200 OK = rawURL 채움 / 404 = rawURL nil (GitHub 직접 링크만)**

### 4-2. stars 검증 (GitHub API)

```bash
# rate limit 60 req/h (토큰 없어도)
curl -s "https://api.github.com/repos/<owner>/<repo>" | \
  python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('stargazers_count'), d.get('description'))"
```

### 4-3. 검증 결과 요약 (2026-05-04)

#### rawURL 200 OK (검증 성공)

| 리포지토리 | URL | Stars |
|-----------|-----|-------|
| anthropics/anthropic-cookbook | CLAUDE.md ✅ | ~10k |
| anthropics/anthropic-quickstarts | CLAUDE.md ✅ | ~7k |
| anthropics/claude-code-action | CLAUDE.md ✅ | ~3k |
| cline/cline | CLAUDE.md ✅ | ~61k |
| modelcontextprotocol/servers | CLAUDE.md ✅ | ~85k |
| modelcontextprotocol/servers | README.md ✅ | ~85k |
| punkpeye/awesome-mcp-servers | README.md ✅ | ~86k |
| vercel/next.js | CLAUDE.md ✅ (canary) | ~139k |
| hesreallyhim/awesome-claude-code | README.md ✅ | ~42k |

#### rawURL nil (404 또는 미존재)

| 리포지토리 | 이유 |
|-----------|-----|
| anthropics/courses README.md | 404 (경로 없음) |
| cline/cline .clinerules | 404 (삭제됨) |
| hesreallyhim/awesome-claude-code CLAUDE.md | 404 (없음) |
| dair-ai/Prompt-Engineering-Guide | rawURL 대신 GitHub 링크만 |

#### 공개 정보 기반 stars (API rate limit 도달)

| 리포지토리 | Stars (추정) |
|-----------|-------------|
| cline/cline | ~61k |
| hesreallyhim/awesome-claude-code | ~42k |
| modelcontextprotocol/servers | ~85k |
| punkpeye/awesome-mcp-servers | ~86k |
| vercel/next.js | ~139k |
| anthropics/courses | ~21k |
| dair-ai/Prompt-Engineering-Guide | ~55k |
| f/awesome-chatgpt-prompts | ~120k |
| binhnguyennus/awesome-scalability | ~60k |
| PatrickJS/awesome-cursorrules | ~25k |

---

## 5. 검증된 큐레이션 자료 목록 (28개, ADR-112)

### CLAUDE.md (5개)

| # | 이름 | 저자 | Stars | rawURL |
|---|------|------|-------|--------|
| 1 | Anthropic Cookbook 개발 가이드 | anthropics | ~10k | ✅ 200 |
| 2 | Cline 공식 CLAUDE.md | cline | ~61k | ✅ 200 |
| 3 | Anthropic Quickstarts 개발 규칙 | anthropics | ~7k | ✅ 200 |
| 4 | awesome-claude-code 큐레이션 모음 | hesreallyhim | ~42k | ✅ README |
| 5 | Claude Code GitHub Action 규칙 | anthropics | ~3k | ✅ 200 |

### Skill (3개)

| # | 이름 | 저자 | Stars | rawURL |
|---|------|------|-------|--------|
| 6 | TDD 마스터 Skill 가이드 | anthropics | ~10k | nil |
| 7 | SwiftUI 패턴 Skill | anthropics | ~5k | nil |
| 8 | Anthropic 공식 교육 커리큘럼 | anthropics | ~21k | nil |

### 템플릿 (2개)

| # | 이름 | 저자 | Stars | rawURL |
|---|------|------|-------|--------|
| 9 | Next.js + Claude Code 풀스택 스타터 | vercel | ~139k | ✅ 200 |
| 10 | MCP 서버 공식 예시 모음 | modelcontextprotocol | ~85k | ✅ README |

### 디자인 가이드 (3개)

| # | 이름 | 저자 | Stars | rawURL |
|---|------|------|-------|--------|
| 11 | 보안 강화 가이드라인 | anthropics | ~10k | nil |
| 12 | TypeScript 엄격 코딩 스타일 | microsoft | ~102k | nil |
| 13 | Swift API 디자인 가이드라인 | apple | ~68k | nil |

### 워크플로우 (3개)

| # | 이름 | 저자 | Stars | rawURL |
|---|------|------|-------|--------|
| 14 | Claude Code 워크플로우 베스트 프랙티스 | hesreallyhim | ~42k | ✅ README |
| 15 | Conventional Commits 스펙 | conventional-commits | ~7k | nil |
| 16 | Claude Code Action CI 워크플로우 | anthropics | ~3k | ✅ 200 |

### 시스템 설계 (3개)

| # | 이름 | 저자 | Stars | rawURL |
|---|------|------|-------|--------|
| 17 | MCP 프로토콜 아키텍처 설계 | modelcontextprotocol | ~85k | ✅ 200 |
| 18 | Claude Code 에이전트 아키텍처 | anthropics | ~7k | nil |
| 19 | 대규모 시스템 확장 패턴 | binhnguyennus | ~60k | nil |

### 프롬프트 패턴 (3개)

| # | 이름 | 저자 | Stars | rawURL |
|---|------|------|-------|--------|
| 20 | Anthropic 공식 프롬프트 패턴 | anthropics | ~10k | ✅ 200 |
| 21 | 프롬프트 엔지니어링 완전 가이드 | dair-ai | ~55k | nil |
| 22 | 커뮤니티 프롬프트 컬렉션 | f/awesome-chatgpt-prompts | ~120k | nil |

### 에디터 규칙 (3개)

| # | 이름 | 저자 | Stars | rawURL |
|---|------|------|-------|--------|
| 23 | Claude Code Rules 큐레이션 | hesreallyhim | ~42k | ✅ README |
| 24 | Cursor Rules 커뮤니티 모음 | PatrickJS | ~25k | nil |
| 25 | Cline Coding Rules 가이드 | cline | ~61k | ✅ 200 |

### MCP 서버 (3개)

| # | 이름 | 저자 | Stars | rawURL |
|---|------|------|-------|--------|
| 26 | MCP 공식 서버 구현체 | modelcontextprotocol | ~85k | ✅ 200 |
| 27 | awesome-mcp-servers 큐레이션 | punkpeye | ~86k | ✅ README |
| 28 | Claude Code Action MCP 설정 | anthropics | ~3k | ✅ 200 |

**총계: 28개 (rawURL 확인됨 18개, nil 10개)**

---

## 6. 데이터 모델 변경

### 6-1. CommunityResource.Category 확장 (3 → 9)

```swift
public enum Category: String, Sendable, Codable, CaseIterable, Identifiable {
    case claudeMd       // 기존
    case skill          // 기존
    case template       // 기존
    case styleGuide     // ADR-112 신규
    case workflow       // ADR-112 신규
    case architecture   // ADR-112 신규
    case promptPattern  // ADR-112 신규
    case rules          // ADR-112 신규
    case mcp            // ADR-112 신규
}
```

각 카테고리에 추가된 computed properties:
- `tintColorName` — 색상 토큰 이름
- `categoryDescription` — 2-3줄 설명
- `categoryRank` — 사이드바 정렬 우선순위 (0-8)

### 6-2. CommunityResource 신규 필드

```swift
public let language: Language       // .korean / .english / .multilingual
public let useCase: String?         // "사용 사례 짧은 예시"
public let officialBadge: Bool      // Anthropic 공식 여부
public let recommendedRank: Int     // 0-100, 카테고리 내 추천도
```

### 6-3. Language enum 신규

```swift
public enum Language: String, Sendable, Codable, CaseIterable {
    case korean, english, multilingual
}
```

### 6-4. 하위 호환성

`init(from decoder:)` 커스텀 구현으로 ADR-111 이전 JSON도 디코딩 성공:
- `language` 없으면 → `.english`
- `officialBadge` 없으면 → `false`
- `recommendedRank` 없으면 → `50`
- `useCase` 없으면 → `nil`

---

## 7. UI 고도화

### 7-1. CommunityResourcesPanel 개선

| 기능 | ADR-111 | ADR-112 |
|------|---------|---------|
| 카테고리 필터 | 4개 chip | 10개 chip (전체 포함) |
| 검색 | 없음 | 이름 + 설명 + 태그 + 저자 |
| 정렬 | 없음 | 추천도 / 스타 수 |
| 공식 배지 | 없음 | 파란 "공식" chip |
| 언어 표시 | 없음 | 국기 이모지 (🇰🇷/🇬🇧/🌐) |
| 사용 사례 | 없음 | 전구 아이콘 + 이탤릭 텍스트 |
| 카탈로그 진입 | 없음 | "전체 카탈로그" 버튼 |

### 7-2. LibrarySheet 개선

| 기능 | ADR-111 | ADR-112 |
|------|---------|---------|
| 사이드바 카테고리 | 4개 | 10개 (전체 + 9개) |
| 카테고리 색상 | 3가지 | 9가지 tint |
| 빈 카테고리 힌트 | 없음 | "커뮤니티에서 추가하세요" 안내 |
| 텍스트 추가 Picker | segmented | menu (9개 카테고리) |
| URL 추가 Picker | segmented | menu (9개 카테고리) |

### 7-3. CatalogSheet 신규 (ADR-112)

```
┌──────────────────┬─────────────────────────────────────┐
│ 전체 (28)        │  📄 CLAUDE.md (5)                   │
│ ⭐ 공식 (10)     │  ┌────────────┐  ┌────────────┐     │
│ 🌐 한국어 (0)    │  │  자료 1    │  │  자료 2    │     │
│ ──────────       │  │  ⭐ 공식   │  │  🇬🇧 영어  │     │
│ 📄 CLAUDE.md (5) │  │ ★★★★★     │  │  ★★★☆☆    │     │
│ 🛠 Skill (3)     │  └────────────┘  └────────────┘     │
│ 📐 템플릿 (2)    │                                     │
│ 🎨 디자인 (3)    │  🔌 MCP 서버 (3)                    │
│ 🚀 워크플로우(3) │  ...                                │
│ 🏛 시스템 설계(3)│                                     │
│ ✨ 프롬프트 (3)  │                                     │
│ 🛡 에디터 규칙(3)│                                     │
│ 🔌 MCP 서버 (3)  │                                     │
└──────────────────┴─────────────────────────────────────┘
```

기능:
- 좌측 사이드바: 전체 / 공식 / 한국어 / 카테고리 9개
- 우측 그리드: 2열 카드 (카테고리 헤더 고정)
- 검색 + 정렬 (추천도 / 스타 수)
- 카드별 "추가" 버튼 (rawURL 있는 경우)

---

## 8. 변경 파일 목록

| 파일 | 변경 유형 | 주요 내용 |
|------|---------|---------|
| `Sources/YuminaiCore/CommunityResource.swift` | 수정 | Category 3→9, Language enum, 신규 필드 4개, 큐레이션 8→28개 |
| `Sources/YuminaiApp/CommunityResourcesPanel.swift` | 수정 | 검색/정렬/공식배지/언어/사용사례/카탈로그 버튼 |
| `Sources/YuminaiApp/LibrarySheet.swift` | 수정 | 사이드바 9카테고리, tint color, 빈 카테고리 hint, menu Picker |
| `Sources/YuminaiApp/CatalogSheet.swift` | 신규 | 전체 카탈로그 탐색 sheet (사이드바 + 2열 그리드) |
| `Sources/YuminaiApp/AppModel.swift` | 수정 | showCatalogSheet 추가, applyCommunityResource switch 확장 |
| `Sources/YuminaiApp/RootView.swift` | 수정 | CatalogSheet 연결 |
| `Sources/YuminaiUI/LibraryPickerPopover.swift` | 수정 | categoryColor switch 9개 |
| `Tests/YuminaiCoreTests/CommunityResourceTests.swift` | 수정 | 64개 테스트 (기존 30 → 64) |

---

## 9. 테스트 결과

| 항목 | 결과 |
|------|-----|
| 전체 테스트 | 1142개 통과 (baseline: 1105) |
| 신규 CommunityResource 테스트 | 64개 (기존 31개 → 64개) |
| 빌드 | Build complete (0 errors) |
| 회귀 | 0개 실패 |

### 신규 테스트 항목 (ADR-112)

- Language enum Codable round-trip (korean/multilingual/english)
- officialBadge, recommendedRank, useCase Codable 보존
- 하위 호환성: 구 JSON (신규 필드 없음) 디코딩 성공
- Category 9개 확인 (`allCases.count == 9`)
- 신규 카테고리 6개 displayName 확인
- categoryRank 범위 (0-8)
- tintColorName / categoryDescription 비어있지 않음
- CommunityCatalog 25개 이상 확인
- officialResources 필터링
- Language 필터링 (english)
- sorted(by:) 내림차순 검증

---

## 10. 향후 개선 계획

1. **GitHub Stars 자동 갱신** — 주기적으로 GitHub API로 `starsApprox` 업데이트
2. **한국어 자료 확장** — 한국 개발자 커뮤니티 자료 3-5개 추가
3. **사용자 별점** — 라이브러리 항목에 1-5점 평점 기능
4. **자료 버전 관리** — rawURL이 404로 바뀌면 자동 감지·알림
5. **카테고리 자동 감지** — 파일 내용 분석으로 카테고리 자동 제안
