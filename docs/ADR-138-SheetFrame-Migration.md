# ADR-138: Sheet Frame 마이그레이션 (YuminaiSheetFrame)

**날짜**: 2026-05-08  
**상태**: Accepted  
**연관**: ADR-073 (Sheet Frame Baseline), ADR-074 (Sheet Frame Responsive)

---

## 1. 배경

`frame(minWidth: X, minHeight: Y)` 패턴으로 크기를 직접 지정하는 sheet들이 남아 있었다. `YuminaiSheetFrame` / `YuminaiSheet` (ADR-073/074 도입) 표준으로 통일되지 않아 크기 일관성이 깨졌다.

---

## 2. 결정

다음 sheet들을 `.yuminaiSheetFrame(width:height:wrapInScrollView:)` 패턴으로 교체했다.

| Sheet | width | height | wrapInScrollView |
|-------|-------|--------|-----------------|
| CatalogSheet | 900 | 600 | false (HSplitView) |
| GitHubSearchSheet (main) | 720 | 580 | false |
| GitHubSearchSheet (slim) | 380 | 300 | false |
| GitHubPATSheet | 520 | 420 | true |
| BundleCatalogSheet | 900 | 620 | false |
| GitLabPATSheet | 520 | 480 | true |
| GitLabSearchSheet | 720 | 520 | false |
| CommandPolicySettingsSheet | 580 | 500 | true |
| LibrarySheet | 760 | 540 | false |

### wrapInScrollView 결정 기준

- `HSplitView` 또는 좌우 분할 레이아웃 → `false`
- 단순 스크롤 가능한 단일 컬럼 → `true`

---

## 3. 영향 파일

위 목록의 각 sheet 파일에서 `frame()` 직접 지정을 `.yuminaiSheetFrame()` 뷰 모디파이어로 교체.
