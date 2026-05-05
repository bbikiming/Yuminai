# ADR-122 — GitHub 크롤링/검색 기능 구조 및 안정성 강화

**날짜:** 2026-05-04
**상태:** 완료
**기반:** ADR-116 (GitHubSearchClient 초기), ADR-118 (검색 UI 고도화), ADR-119 (PAT 지원)

---

## 1. 배경 — 현재 한계 (ADR-118/119 기반)

| 한계 항목 | 설명 |
|-----------|------|
| Rate limit | `X-RateLimit-Reset` 헤더만 파싱, Remaining/Limit 무시 |
| 재시도 없음 | 5xx 서버 에러, 네트워크 timeout 시 즉시 fail |
| 캐시 없음 | 동일 검색 반복 시 매번 API 호출 |
| Pagination 없음 | 1페이지(최대 100개)만 표시 |
| Request cancellation 없음 | 검색어 빠르게 변경 시 이전 request도 끝까지 수행 |
| 단일 파일 수집만 | 리포지토리의 여러 관련 파일 자동 수집 불가 |
| 검색 history 없음 | 반복 검색 시 재입력 필요 |

---

## 2. Phase별 구현 결정

### Phase 1: 안정성 강화

#### 1-1. GitHubRetryPolicy
- `Sources/YuminaiCore/GitHubRetryPolicy.swift` (신규, 77줄)
- Exponential backoff + full jitter (AWS Architecture Blog 권고)
- 공식: `delay = min(maxDelay, baseDelay * 2^attempt + jitter)`
- 프리셋: `.default` (3회, 1~10s), `.fast` (테스트용), `.aggressive` (5회, 2~30s)
- `isRetryable(statusCode:)`: 5xx, 408, 429 → retry / 401, 403, 404, 422 → 즉시 실패

#### 1-2. Rate Limit 정확한 파싱
- `GitHubRateLimit` struct: limit, remaining, resetAt, resetIn, isLimited, displayText
- 모든 응답 헤더 파싱: `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`, `Retry-After`
- `currentRateLimit()` async 메서드로 UI에서 실시간 접근

#### 1-3. GitHubSearchCache
- `Sources/YuminaiCore/GitHubSearchCache.swift` (신규, 94줄)
- actor 기반 in-memory 캐시 (동시성 안전)
- TTL 기본 5분 (300초), capacity 기본 50개
- `CacheKey`: endpoint + query + perPage + page 조합
- `gc()`: 만료 + capacity 초과 정리
- set 시 capacity 초과하면 자동 gc() 호출

#### 1-4. Pagination
- `GitHubSearchPage<T>`: items, totalCount, currentPage, perPage, hasMore 계산 프로퍼티
- `searchRepositories(query:perPage:page:)`, `searchCode(query:perPage:page:)` page 파라미터 추가
- UI에서 [더 보기] 버튼으로 page+1 추가 fetch + 결과 append

#### 1-5. Request Cancellation
- `GitHubSearchSheet`에 `@State private var searchTask: Task<Void, Never>?`
- `performSearch()` 시 이전 searchTask?.cancel() 호출
- `GitHubSearchClient.fetch()` 내 `Task.checkCancellation()` 통합
- 취소 시 `.cancelled` 에러로 조용히 처리

#### 1-6. 에러 분류 강화
- `.rateLimited(retryAfter:resetAt:)`: retryAfter 별도 추적
- `.forbidden(String)`: 403 non-rate-limit 케이스
- `.invalidQuery(String)`: 422 검색어 형식 오류
- `.serverError(Int)`: 5xx 통합
- `.decodingError(String)`: JSON 디코딩 실패
- `.cancelled`: Task cancellation
- `recoveryHint`: 사용자 다음 액션 안내 (한국어)

---

### Phase 2: GitHubCrawler

- `Sources/YuminaiCore/GitHubCrawler.swift` (신규, 156줄)
- actor 기반, `GitHubSearchClient` 의존
- `crawlRepository(owner:repo:branch:customPaths:)` — 11개 기본 경로 병렬 fetch

기본 시도 경로:
| 경로 | 카테고리 |
|------|----------|
| CLAUDE.md | .claudeMd |
| AGENTS.md | .claudeMd |
| .cursorrules | .rules |
| .github/copilot-instructions.md | .rules |
| .windsurfrules | .rules |
| README.md | .template |
| .github/CONTRIBUTING.md | .workflow |
| docs/architecture.md | .architecture |
| docs/ARCHITECTURE.md | .architecture |
| DESIGN.md | .styleGuide |
| .claude/CLAUDE.md | .claudeMd |

- 각 경로 404면 skip, 200이면 `CrawledFile` 포함
- `withTaskGroup`으로 병렬 fetch (성능 최적화)
- `GitHubRepoMetadata` 조회 (실패 시 nil, crawl은 계속)
- 결과 파일은 defaultCrawlPaths 순서대로 정렬 (재현성)

---

### Phase 3: 검색 History + 즐겨찾기

- `Sources/YuminaiCore/GitHubSearchHistory.swift` (신규, 79줄)
- `GitHubSearchHistoryEntry`: id, query, mode, resultCount, searchedAt (Codable)
- `GitHubSearchFavorite`: id, query, mode, label, savedAt (Codable)
- `GitHubSearchHistoryBuffer.append(_:to:capacity:)`: ring buffer (중복 제거, 최신 우선)

`AppPreferences` 신규 필드:
```swift
public var githubSearchHistory: [GitHubSearchHistoryEntry]   // ring buffer 50개
public var githubSearchFavorites: [GitHubSearchFavorite]
```

`AppModel` 신규 메서드:
- `addSearchHistory(query:mode:resultCount:)` — 검색 후 자동 호출
- `clearSearchHistory()`
- `saveSearchAsFavorite(query:mode:label:)`
- `removeSearchFavorite(_:)` — 즐겨찾기 삭제

---

### Phase 4: UI 강화

`GitHubSearchSheet.swift` 확장:

| 항목 | 구현 |
|------|------|
| 검색 취소 버튼 | 검색 중 [취소] 버튼, Task cancel |
| Rate limit 배너 | "API 60회 중 12회 남음 · 28분 후 리셋" |
| Pagination [더 보기] | 결과 끝에 버튼, page+1 추가 fetch |
| History dropdown | TextField 탭 시 최근 5개 표시 |
| 즐겨찾기 sheet | 헤더 ⭐ 버튼 → 저장된 검색어 목록 |
| Crawl 버튼 | 리포 카드에 [전체 크롤링] → GitHubCrawler |

---

## 3. Retry / Cache / Pagination / Cancellation 정책

### Retry
- 재시도 가능: 5xx, 408, 429 (Retry-After 헤더 우선 적용)
- 재시도 불가: 401, 403, 404, 422, cancellation
- 최대 3회 (기본), 각 시도 사이 exponential backoff + jitter

### Cache
- TTL 5분 (같은 검색어는 5분 이내 재사용)
- capacity 50개 (초과 시 가장 오래된 항목 제거)
- `forceRefresh: Bool` 옵션으로 캐시 무시 가능

### Pagination
- 기본 perPage: 30
- GitHub API `total_count` 기반 `hasMore` 계산
- 클라이언트에서 page별 독립 캐시 (page 1과 page 2는 별도 캐시 엔트리)

### Cancellation
- Swift `Task.checkCancellation()` 활용
- 취소된 요청은 `.cancelled` 에러, UI는 조용히 처리

---

## 4. Crawler 동작 + 시도 경로

1. `withTaskGroup`으로 모든 경로 병렬 fetch
2. 각 경로: `raw.githubusercontent.com/{owner}/{repo}/{branch}/{path}` 요청
3. 200 → `CrawledFile` 생성 (path, category, content, size, downloadURL)
4. 404 → nil 반환 (skip)
5. 결과를 `defaultCrawlPaths` 순서대로 정렬 후 반환
6. `attemptedPaths`는 시도 여부 무관 전체 경로 포함

---

## 5. History / Favorite 영구 저장

- `AppPreferences.githubSearchHistory`: `[GitHubSearchHistoryEntry]` (Codable)
- 영속: `AppPreferencesStore` (UserDefaults 또는 파일)가 자동 직렬화
- Ring buffer: 50개 초과 시 오래된 항목 제거, 중복 query+mode는 최신으로 교체
- Backward-compat: 기존 JSON에 필드 없으면 `[]` (decodeIfPresent ?? [])

---

## 6. UI 강화 항목

- Rate limit 배너: 남은 횟수가 전체 1/4 미만이거나 한도 초과 시 강조 색상
- History dropdown: TextField 탭 시 표시, 검색 실행하면 즉시 닫힘
- Favorites sheet: `.onDelete`로 스와이프 삭제, 탭으로 즉시 재검색
- Crawl 버튼: 성공 시 카드에 "라이브러리에 있음" 배지로 전환

---

## 7. 검증 + 후속

### 테스트 결과
- `GitHubRetryPolicyTests`: 11 테스트 통과
- `GitHubSearchCacheTests`: 10 테스트 통과
- `GitHubRateLimitTests`: 6 테스트 통과
- `GitHubCrawlerTests`: 13 테스트 통과
- `GitHubSearchHistoryTests`: 11 테스트 통과
- `GitHubSearchClientTests`: 기존 + 신규 pagination/rateLimit 테스트 통과
- 전체: 1303 tests passed (회귀 0)

### 수동 검증 가이드
```bash
cd /Users/bbikiming/Documents/vibe_coding/Yuminai
swift build
swift test   # 1303 passed

# 앱 빌드 (선택)
./App/build_app_bundle.sh
```

### 후속 과제 (ADR-123 이후)
- 즐겨찾기 추가 UI (현재는 삭제만 구현, ⭐ 추가 버튼 미완)
- 검색 히스토리 전체 초기화 UI
- GitHubCrawler의 GitHub API 메타데이터 실제 통합 (현재 fetchRawContent 호출 → API endpoint)
- 오프라인 캐시 (disk 영속)
