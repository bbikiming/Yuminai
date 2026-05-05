# ADR-118 — 사이드바 아이콘 + GitHub 검색 카드 / 필터 고도화

**날짜**: 2026-05-04
**상태**: 승인됨
**연관 ADR**: ADR-116 (GitHub 검색 초기), ADR-117 (LibraryItemCard 패턴)

---

## 1. 배경

ADR-117 이후 세 가지 이슈가 보고됐다.

| # | 문제 | 영향 |
|---|------|------|
| 1 | 사이드바 "커뮤니티 자료" 아이콘이 보이지 않음 | 항목 식별 불가 |
| 2 | GitHub 검색 카드 디자인이 LibraryItemCard와 불일치 | 시각 일관성 저하 |
| 3 | 검색 결과 정렬/필터 기능 없음 | 대량 결과 탐색 불편 |

---

## 2. 사이드바 SF Symbol 호환성 정책

### 문제

`cube.box.circle.fill`은 iOS 17+ / macOS 14+ 전용 심볼이다.
사용자 환경(macOS 13 Ventura)에서는 fallback이 없어 빈 공간으로 렌더링된다.

### 결정

**모든 사이드바 아이콘을 macOS 11+ 호환 심볼로 제한한다.**

| 항목 | 변경 전 | 변경 후 | 호환성 |
|------|---------|---------|--------|
| 커뮤니티 자료 | `cube.box.circle.fill` | `archivebox.circle.fill` | macOS 11+ |
| Telegram Hub | `paperplane.circle.fill` | (유지) | macOS 11+ |
| 라이브러리 | `books.vertical.circle.fill` | (유지) | macOS 11+ |
| 스택 번들 | `shippingbox.circle.fill` | (유지) | macOS 11+ |
| 사용자 가이드 | `questionmark.circle.fill` | (유지) | macOS 11+ |
| 설정 | `gear` | (유지) | macOS 11+ |

`archivebox.circle.fill` 선택 이유:
- "자료 보관소" 의미가 커뮤니티 자료 맥락과 일치
- `.circle.fill` suffix로 다른 항목들과 시각 통일
- macOS 11 Big Sur 이상에서 렌더링 보장

### 정책 (이후 유지)

신규 SF Symbol 추가 시 반드시 SF Symbols 앱에서 macOS 버전 지원 범위 확인 후 사용한다.
iOS 17+ / macOS 14+ 전용 심볼은 사용 금지.

---

## 3. GitHubSearchSheet 카드 디자인 시스템 (ADR-117 패턴 차용)

### 변경사항

#### 리포 카드 레이아웃

```
┌────────────────────────────────────────────────────┐
│  ┌──────┐                              [main badge]  │
│  │ </>  │  anthropics/anthropic-cookbook             │
│  └──────┘  ⭐ 12k · Python · 3일 전               │
│                                                      │
│            Anthropic 공식 쿡북 — 다양한 use case    │
│                                                      │
│  ──────────────────────────────────────────         │
│  [GitHub 열기]              [라이브러리에 추가]     │
└────────────────────────────────────────────────────┘
```

- 아이콘 박스: 36×36, `chevron.left.forwardslash.chevron.right`, accent tint (macOS 11+ 호환)
- 제목: `.body.weight(.semibold)`, lineLimit 1
- 메타 행: ⭐ stars · 언어 · 갱신일 (relative)
- 설명: `.small`, lineLimit 2, textSecondary
- 상태 배지: "라이브러리에 있음" (성공 시 success 색상, Capsule)
- 카드 스타일: `surface` + `surfaceHi` stroke + shadow (ADR-117 LibraryItemCard 동일)

#### 코드 파일 카드

동일한 카드 구조 적용. 아이콘은 `doc.text.fill`.

---

## 4. 정렬 / 필터 — client-side 패턴

### 설계 원칙

- API 요청은 `sort:stars`로 최대 30개 가져온다 (기존 20 → 30으로 증가).
- 정렬 변경 / 언어 필터는 **client-side**에서만 동작한다 (추가 API 호출 없음).
- `displayedRepoResults` computed property가 sort + filter를 단일 파이프라인으로 처리.

### 정렬 옵션

```swift
enum SortOrder: String, CaseIterable, Identifiable {
    case stars     = "스타 많은 순"   // 기본값
    case updatedAt = "최근 갱신순"    // updatedAt DESC
    case name      = "이름순"         // localizedCaseInsensitiveCompare ASC
    var id: String { rawValue }
}
```

### 언어 필터

- 검색 결과의 unique language 목록을 동적 추출 → Picker에 표시
- nil language 리포는 언어 필터에서 제외됨
- "전체 언어" 선택 시 필터 해제

### 필터 초기화 시점

| 이벤트 | sortOrder | languageFilter |
|--------|-----------|---------------|
| 새 검색 실행 | 유지 | nil (초기화) |
| 검색어 지우기 | 유지 | nil |
| 모드 변경 | .stars (초기화) | nil |

### `updatedAt` 데이터 흐름

```
GitHub API response (updated_at: "2024-01-15T10:30:00Z")
    → RepoItem.updatedAt: String?
    → ISO8601DateFormatter().date(from:)
    → GitHubRepoResult.updatedAt: Date?
    → SortOrder.updatedAt 정렬에 사용
    → UI: relativeDate() → "3일 전"
```

---

## 5. 검색 전 / 빈 결과 상태 UX

### 검색 전 (idleState)

- 아이콘: `archivebox.circle` (macOS 11+ 호환)
- 제목: "GitHub에서 커뮤니티 자료 검색"
- 추천 키워드 chip 6개 표시 (FlexWrapChips 컴포넌트)
- chip 탭 시 해당 키워드로 즉시 검색

```
추천 검색어:
[🔍 CLAUDE.md tdd]  [🔍 react cursorrules]  [🔍 swift claude]
[🔍 python rules]   [🔍 nextjs cursorrules] [🔍 cursor rules]
```

### 결과 없음 (emptyState)

- 검색어 표시: "'키워드'로 결과를 찾지 못했어요."
- 다른 추천 키워드 chip 표시 (현재 검색어 제외)

### 언어 필터로 빈 결과

- "선택한 언어의 결과가 없어요." + [필터 해제] 버튼

---

## 6. 검증

### 자동 테스트 (ADR-118 추가 7개)

```
GitHubSearchSortFilterTests:
  ✅ 스타 많은 순 정렬 — 가장 스타 많은 리포가 첫 번째
  ✅ 최근 갱신순 정렬 — 가장 최근 리포가 첫 번째
  ✅ 최근 갱신순 정렬 — updatedAt nil인 리포는 맨 끝
  ✅ 이름순 정렬 — 알파벳 오름차순
  ✅ 언어 필터 — Swift만 선택 시 Swift 리포만 반환
  ✅ 언어 필터 — 해당 언어 없을 때 빈 배열 반환
  (+ 기존 GitHubSearchClientTests 11개 회귀 없음)
```

### 수동 검증 가이드

1. 앱 실행 후 사이드바 "커뮤니티 자료" 아이콘이 표시되는지 확인
2. GitHub 검색 Sheet 열기 → idle 화면에서 추천 키워드 chip 표시 확인
3. "CLAUDE.md tdd" chip 탭 → 검색 실행 → 결과 카드 디자인 확인
4. 정렬 Picker에서 "최근 갱신순" 선택 → 결과 재정렬 확인
5. 언어 Picker에서 특정 언어 선택 → 해당 언어만 표시 확인
6. "필터 해제" 버튼 → 언어 필터 초기화 확인
7. "라이브러리에 추가" → 성공 시 "라이브러리에 있음" 배지 표시 확인

---

## 7. 후속 개선 (Out of Scope)

- PAT (Personal Access Token) 입력 UI → rate limit 60 req/h → 5000 req/h 향상
- 코드 파일 카드에도 정렬/필터 추가 (현재는 리포 모드만)
- 페이지네이션 (현재 30개 고정)
