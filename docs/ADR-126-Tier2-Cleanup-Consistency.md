# ADR-126: Tier 2 — 정리 + 일관성 6건 통합 처리

**날짜:** 2026-05-07  
**상태:** 완료  
**기반:** ADR-125 직후 (baseline: 1326 tests, 커밋 5d4d936)

---

## 1. 배경

ADR-124 기술부채 분석 P1 Tier 2에서 확인된 6건의 정리/일관성 이슈를 한 커밋으로 통합 처리한다.  
회귀 0, DRY, 친화 언어 일관성, UI 기능 활성화를 목표로 한다.

---

## 2. 변경 상세

### Fix 1: categoryColor 4파일 100% 복제 제거 (P1-4)

**문제:** LibrarySheet / CatalogSheet / CommunityResourcesPanel / LibraryPickerPopover 4곳에 16-case switch(`categoryColor`/`badgeColor`)가 글자 단위로 동일하게 복제되어 있었음.

**수정:**
- `Sources/YuminaiUI/CategoryColors.swift` 신규 생성
- `public extension CommunityResource.Category { var swiftUIColor: Color }` 추가
- 4파일의 private 함수를 각 1줄 (`category.swiftUIColor`) 로 교체

**제거된 줄 수:** 4 × 17줄 = 68줄 → 4줄 (64줄 순감)

---

### Fix 2: FilterCategory 3파일 중복 + LibraryPickerPopover 4-case outdated bug (P1-5)

**문제:**
- LibrarySheet / CommunityResourcesPanel에 16-case `FilterCategory` enum이 100% 복제
- LibraryPickerPopover는 ADR-111 시점 4-case만 남아 11개 카테고리 필터 불가

**수정:**
- `Sources/YuminaiCore/CommunityResource.swift`에 `LibraryFilterCategory` 공개 enum 추가
- 3파일 모두 `typealias FilterCategory = CommunityResource.LibraryFilterCategory`로 교체
- LibraryPickerPopover: 4-case → 15-case 자동 동기화 (필터 버그 수정)

**영향:** 사용자가 라이브러리 picker로 첨부 시 이제 전체 15개 카테고리 필터 가능

---

### Fix 3: OnboardingStep2Whitelist 친화 언어 미적용 (P1-6)

**문제:** ADR-101 친화 언어 정책 위반 — raw "사용자 허용 목록", "허용 목록", "모든 사용자 허용 (위험)" 등 하드코딩.

**수정:**
- `TelegramHubFriendlyText.Whitelist` enum 신규 (title / subtitle / userIdsTitle / emptyWarningTitle / emptyHint)
- `OnboardingStep2Whitelist.swift` 4곳의 raw 문자열을 `TelegramHubFriendlyText.Whitelist.*` 상수로 교체

---

### Fix 4 & 5: 검색 즐겨찾기/히스토리 UI 활성화 (P1-2 + P1-3)

**문제:**
- `AppModel.saveSearchAsFavorite` — UI 호출 site 0 (즐겨찾기 sheet에서만 swipe-delete, 추가 방법 없음)
- `AppModel.clearSearchHistory` — UI 호출 site 0 (히스토리 dropdown에 삭제 UI 없음)

**수정 (`GitHubSearchSheet.swift`):**

1. **filterSortBar** — 검색 결과 헤더에 ⭐ 즐겨찾기 토글 버튼 추가
   - 현재 검색어가 이미 즐겨찾기면 "즐겨찾기 해제" (노란색 star.fill)
   - 아니면 "즐겨찾기" (회색 star) — 클릭 시 `saveSearchAsFavorite` 호출

2. **히스토리 dropdown** — 항목 목록 하단에 [전체 삭제] 버튼 추가
   - 클릭 시 `clearSearchHistory` 호출 → dropdown 닫힘

3. **favoritesSheet** — 헤더에 [현재 검색어 추가] 버튼 추가 (검색어가 있고 미등록일 때)
   - 즐겨찾기가 비어있을 때 빈 상태 뷰에서도 [현재 검색어 추가하기] 버튼 표시

---

## 3. 설계 결정

### CategoryColors → YuminaiUI 위치

`swiftUIColor`는 SwiftUI `Color`를 반환하므로 YuminaiCore(Foundation 전용)가 아닌 YuminaiUI에 위치.  
YuminaiCore의 `tintColorName: String`은 UI-독립 문자열 기반 속성으로 유지 (기존 호환).

### LibraryFilterCategory → YuminaiCore 위치

필터 로직은 UI가 아닌 도메인 개념이므로 `CommunityResource` 내부에 위치.  
`CaseIterable + Identifiable + Sendable` — 서버/Core 레이어에서도 안전하게 사용 가능.

### Whitelist 친화 언어 — TelegramHubFriendlyText 패턴 준수

기존 `CommandPaletteEditor`가 사용하는 패턴과 동일하게 `TelegramHubFriendlyText.Whitelist` enum으로 관리.

---

## 4. 검증

```bash
swift build     # 0 errors
swift test      # 1340+ tests passed (1326 baseline + ~14 신규)
```

---

## 5. 신규 파일

| 파일 | 타겟 | 역할 |
|------|------|------|
| `Sources/YuminaiUI/CategoryColors.swift` | YuminaiUI | `swiftUIColor` extension |
| `Tests/YuminaiUITests/CategoryColorsTests.swift` | YuminaiUITests | 16 케이스 + FilterCategory 검증 |
| `docs/ADR-126-Tier2-Cleanup-Consistency.md` | — | 이 문서 |

---

## 6. 수정 파일

| 파일 | 변경 내용 |
|------|----------|
| `Sources/YuminaiCore/CommunityResource.swift` | `LibraryFilterCategory` 공유 enum 추가 |
| `Sources/YuminaiCore/TelegramHubFriendlyText.swift` | `Whitelist` enum 추가 |
| `Sources/YuminaiUI/LibraryPickerPopover.swift` | categoryColor switch 제거, FilterCategory typealias (4→15 케이스 확장) |
| `Sources/YuminaiApp/LibrarySheet.swift` | categoryColor switch 제거, FilterCategory typealias |
| `Sources/YuminaiApp/CatalogSheet.swift` | categoryColor switch 제거 |
| `Sources/YuminaiApp/CommunityResourcesPanel.swift` | badgeColor + chipColor switch 제거, FilterCategory typealias |
| `Sources/YuminaiApp/TelegramHub/Onboarding/OnboardingStep2Whitelist.swift` | 4곳 raw 문자열 → TelegramHubFriendlyText.Whitelist 교체 |
| `Sources/YuminaiApp/GitHubSearchSheet.swift` | ⭐ 토글 버튼, 히스토리 전체 삭제, 즐겨찾기 추가 버튼 |

---

## 7. 후속 (Tier 3 → ADR-127)

- P3-3: dismissAllSheets/presentExclusiveSheet 회귀 테스트 보강
- 추가 기술부채 분석 (ADR-124 Tier 3)
