# ADR-116: 라이브러리/스택 번들 UI 폴리시 + GitHub 검색

**날짜:** 2026-05-04  
**상태:** 승인됨  
**작성자:** Executor (ADR-116)

---

## 배경

사용자 4건의 UI 개선 요청:

1. 사이드바 라이브러리/스택 번들 메뉴 항목에 붙어있는 컬러 이모지(📚 🎁) 제거
2. 라이브러리 "텍스트로 추가" sheet에 파일 업로드 옵션 추가
3. 스택 번들 sheet GUI 요소 라운딩 및 시각 일관성 향상
4. GitHub Search API로 CLAUDE.md 등 자료 검색 + 라이브러리 추가 기능

---

## 결정 사항

### 1. 컬러 이모지 → SF Symbol 단색 변환

**변경 파일:** `Sources/YuminaiUI/SidebarView.swift`

| 이전 | 이후 |
|------|------|
| `"📚 라이브러리"` | `"라이브러리"` + icon: `books.vertical.circle.fill` |
| `"🎁 스택 번들"` | `"스택 번들"` + icon: `shippingbox.circle.fill` |

**이유:** SF Symbol은 시스템 테마(다크모드/라이트모드)에 자동 대응하고, Accessibility 환경에서 더 명확하다. 컬러 이모지는 시스템 렌더링에 따라 크기·색상이 달라져 시각 일관성이 깨진다. SidebarMenuRow는 이미 `icon:` 파라미터를 통해 systemImage를 렌더링하므로, label에서 이모지만 제거하면 된다.

**전체 이모지 grep 결과:** SidebarView 외 다른 주요 이모지 사용처(CommunityResource.swift의 🌐, AppModel의 🛡, TelegramSessionBridge의 🔧)는 시스템 메시지/로그에 사용되거나 CommunityResource.language.flag 속성으로 의미상 필요한 경우여서 이번 ADR 범위에서 제외.

---

### 2. 라이브러리 텍스트/파일 입력 segmented

**변경 파일:** `Sources/YuminaiApp/LibrarySheet.swift`

`AddLibraryTextSheet`에 두 가지 입력 모드를 추가:

- **직접 입력** (기존): 이름 + 카테고리 + 텍스트 에디터 + 태그
- **파일 첨부** (신규): NSOpenPanel로 .md/.txt 파일 선택 → 이름 자동 추출 + 파일 크기 + 첫 5줄 미리보기

공통 필드: 이름(자동 추출 후 편집 가능), 카테고리, 태그.

저장 경로:
- 직접 입력 → `appModel.addToLibraryFromText`
- 파일 첨부 → `appModel.addToLibraryFromURL(localFileURL)` (기존 메서드 재사용)

**이유:** 이미 URL 다운로드 경로가 있으므로 로컬 파일도 동일 경로로 처리 가능. NSOpenPanel의 `allowedContentTypes = [.plainText]`로 파일 타입을 제한해 바이너리 업로드를 차단.

---

### 3. BundleCatalogSheet 시각 일관성

**변경 파일:** `Sources/YuminaiApp/BundleCatalogSheet.swift`

| 요소 | 이전 | 이후 |
|------|------|------|
| 카테고리 섹션 헤더 배경 | 평면 `Theme.Color.bg` | `RoundedRectangle(cornerRadius: Theme.Radius.md)` + 0.5pt 테두리 |
| 카테고리 헤더 카운트 | `"(3)"` 일반 텍스트 | `Capsule()` 배지 (카테고리 컬러) |
| 사이드바 카운트 배지 | 일반 텍스트 | `Capsule()` 배지 (선택 시 tint, 비선택 시 surfaceHi) |

번들 카드 자체는 이미 `GroupBox` + `Capsule()` 조합으로 일관성이 있어 추가 수정 불필요.

---

### 4. GitHubSearchClient (신규)

**신규 파일:** `Sources/YuminaiCore/GitHubSearchClient.swift`

```swift
public actor GitHubSearchClient {
    public func searchRepositories(query: String, perPage: Int = 20) async throws -> [GitHubRepoResult]
    public func searchCode(query: String, perPage: Int = 20) async throws -> [GitHubCodeResult]
}
```

**API 엔드포인트:**
- 리포지토리: `GET /search/repositories?q={query}+sort:stars`
- 코드 파일: `GET /search/code?q={query}`

**rate limit 처리:**
- HTTP 403/429 → `SearchError.rateLimited(resetAt:)`
- `X-RateLimit-Reset` 헤더에서 reset 시각 파싱

**인증:** `init(token:)` 파라미터로 PAT 주입 가능. nil 시 비인증 60 req/h.

**테스트:** `GitHubSearchClient.URLSessionProtocol` 주입 패턴 (TelegramTokenValidator 패턴 참조). 12개 테스트.

---

### 5. GitHubSearchSheet (신규)

**신규 파일:** `Sources/YuminaiApp/GitHubSearchSheet.swift`

**진입점:** `CommunityResourcesPanel.headerSection`에 "GitHub 검색" 버튼 추가.  
**AppModel 플래그:** `showGitHubSearchSheet: Bool`  
**RootView 등록:** `.sheet(isPresented: $bindable.showGitHubSearchSheet)`

**기능:**
- 검색 모드: 리포지토리 / 코드 파일 (segmented control)
- 검색 결과 카드: repo명 + 설명 + stars + 언어 / 파일명 + repo명 + stars
- 라이브러리에 추가: 리포는 CLAUDE.md → README.md 순으로 raw URL 시도; 코드 파일은 직접 rawURL

---

## 검증 기준

- `swift build` 오류 0
- `swift test` — 기존 1220개 + 신규 12개 = 1232개 이상 통과
- 회귀 0 (기존 라이브러리/번들 동작 변경 없음)

## 후속 과제

- GitHub PAT 입력 UI (설정 → GitHub 토큰 섹션)
- GitHub 검색 결과 페이징 (Load more)
- 코드 검색 결과의 리포지토리 스타 수는 API 제한으로 누락될 수 있음 (향후 repo endpoint 보강)
