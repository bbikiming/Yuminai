# ADR-125: Tier 1 안정성 정리 — P0 4건 + P1 4건

| 항목 | 내용 |
|------|------|
| 날짜 | 2026-05-07 |
| 상태 | Accepted |
| 선행 ADR | ADR-124 (코드베이스 Gap 분석) |
| baseline | 커밋 1a2fe6a, 1303 tests |

---

## 배경

ADR-124에서 분석한 코드베이스 Gap 중 **Tier 1** (즉시 처리)에 해당하는 8건을 이 ADR에서 통합 처리한다.

- **P0 (안정성)**: 4건 — 데이터 손실 / 침묵 실패 / mutual exclusion 깨짐
- **P1 (Quick wins)**: 4건 — dead code / 친화 언어 / 아이콘 정책

Tier 2 → ADR-126, Tier 3 → ADR-127+에서 처리 예정.

---

## P0-1: dismissAllSheets mutual exclusion 복구

**문제:** ADR-111~117에서 추가된 6개 sheet 중 5개가 `dismissAllSheets()`에 누락. SwiftUI에서 여러 sheet가 동시에 `.isPresented = true`가 되면 동작 미정(undefined behavior).

`showGitHubPATSheet`는 P1-1에서 dead code로 제거되므로 미추가.

**수정:** `AppModel.swift:dismissAllSheets()`에 5줄 추가:

```swift
showLibrarySheet = false
showCatalogSheet = false
showBundleCatalogSheet = false
showGitHubSearchSheet = false
showCommunityResourcesSheet = false
```

**회귀 가드:** `Tests/YuminaiCoreTests/AppModelSheetExclusionTests.swift` 신규 생성.
AppModel은 executable target이라 직접 import 불가 → 소스 파일 텍스트 파싱으로 구조 검증.

---

## P0-2: relativeDate dead branch 수정 + RelativeTime helper 추출

**문제:** `GitHubSearchSheet`와 `LibrarySheet` 두 파일에 동일한 `relativeDate(_:)` 구현이 중복 존재했고, 두 파일 모두 1주~1개월 구간에 dead branch 버그 보유.

```swift
// 버그: 두 분기가 동일한 표현식 — 8일~29일 자료가 "N주 전" 대신 "N일 전"으로 표시
if diff < 86400 * 7  { return "\(Int(diff / 86400))일 전" }
if diff < 86400 * 30 { return "\(Int(diff / 86400))일 전" }  // ← dead: 상수 다름, 표현식 동일
```

**수정:**

1. `Sources/YuminaiCore/RelativeTime.swift` 신규 생성:
   - `RelativeTime.format(_ date: Date, now: Date = .now) -> String`
   - 두 번째 분기를 `"\(Int(diff / (86400 * 7)))주 전"`으로 교정
   - `now` 파라미터 주입으로 테스트 용이성 확보

2. `GitHubSearchSheet.swift`와 `LibrarySheet.swift`의 `relativeDate(_:)` → helper 위임으로 대체
   (`LibrarySheet`는 추가로 개월/년 구간이 없던 불완전 구현도 함께 보완됨)

3. `Tests/YuminaiCoreTests/RelativeTimeTests.swift` 신규 — 13 tests:
   - 방금 전 / 분 / 시간 / 일 / **주 (P0-2 핵심)** / 개월 / 년
   - 29일 → "4주 전" (구버그: "29일 전") 명시 검증

---

## P0-3: loadMoreResults 빈 catch → 401 침묵 swallow 수정

**문제:** `performSearch`는 401(unauthorized) 시 PAT 자동 삭제 + 사용자 알림을 올바르게 처리하지만, `loadMoreResults`(2페이지+)는 빈 catch로 401을 침묵 처리. PAT 만료 후 사용자가 빈 결과만 보고 원인 불명.

**수정:** `loadMoreResults catch` 블록을 `performSearch`와 동일한 분기 구조로 강화:

```swift
} catch GitHubSearchClient.SearchError.cancelled {
    // 취소됨 — 조용히 처리
} catch GitHubSearchClient.SearchError.unauthorized {
    searchError = "토큰이 만료됐거나 권한이 없어요. 위 배너에서 PAT를 재설정해 주세요."
    await appModel.removeGitHubPAT()
} catch {
    searchError = error.localizedDescription
}
```

---

## P0-4: Crawler 부분 실패 UX 개선

**문제:** 5개 파일 중 3개 다운로드 실패해도 "전체 크롤링 완료"처럼 `addedIds.insert(itemId)` 만 실행. 사용자가 부분 실패 인지 불가.

**수정:** `crawlRepo` 함수에서 각 파일 `addToLibraryFromURL` 결과를 집계:

```swift
var successCount = 0
var failCount = 0
for file in result.files {
    let addResult = await appModel.addToLibraryFromURL(...)
    if case .success = addResult { successCount += 1 } else { failCount += 1 }
}
if successCount > 0 { addedIds.insert(itemId) }
if failCount > 0 {
    crawlErrors[itemId] = "\(successCount)/\(total) 추가, \(failCount)개 다운로드 실패"
}
```

---

## P1-1: showGitHubPATSheet dead code 제거

**문제:** `AppModel.showGitHubPATSheet: Bool = false` 필드가 선언돼 있지만 setter, RootView 바인딩, 테스트 어디에도 사용되지 않음. 실제 PAT sheet는 `GitHubSearchSheet` 내부 `@State private var showPATSheet`로 표시.

**수정:** 필드 3줄 제거. `dismissAllSheets`에도 미추가(P0-1 참조).

---

## P1-7: CommandPaletteEditor "HITL" → "위험 명령"

**문제:** Telegram Command Palette에서 `requiresHITL` 명령에 "HITL" raw text badge 표시. 일반 사용자에게 무의미한 영어 약어.

**수정:** `Text("HITL")` → `Text("위험 명령")`.

---

## P1-8: ADR-118 정책 폐기 — cube.box.circle.fill 원복

**모순 발견:** `Package.swift:17`에 `.macOS(.v26)` 배포 대상이 설정돼 있어 macOS 14+ SF Symbol 사용이 완전히 안전하다. ADR-118은 macOS 11+ 호환성을 위해 `cube.box.circle.fill`(macOS 14+)을 `archivebox.circle.fill`(macOS 11+)으로 교체했으나, 이 정책 자체가 무효.

**결정:** ADR-118 정책 폐기. 사이드바 "커뮤니티 자료" 아이콘을 원래 디자인 의도인 `cube.box.circle.fill`로 원복.

**폐기 사유:**
- `Package.swift` macOS 26 minimum → macOS 11 호환 필요 없음
- `LibraryItem.swift`, `CommunityResourcesSheet.swift`, `CatalogSheet.swift` 등 다른 파일들은 이미 `cube.box.fill` 사용 중 → 아이콘 일관성
- 디자인 의도 (커뮤니티 = 박스/컨테이너 메타포) 회복

**영향 범위:** `SidebarView.swift` 1줄만 변경. 다른 파일(`LibraryItem.swift` 등)은 이미 `cube.box.fill` 사용 중이라 무변경.

---

## P1-9: TelegramHealthPill.swift 삭제

**문제:** `Sources/YuminaiUI/TelegramHealthPill.swift` (87줄)가 `@available(*, deprecated)` 마킹 상태이나 파일 자체 존재. 실제 사용처가 `SidebarView.swift`에 주석으로만 남아있고 `BotStatusDockView`로 완전 대체.

**검증:** `grep -rn TelegramHealthPill Sources/` 결과:
- `SidebarView.swift:261`: 주석 (`// ADR-093 Phase 2 — BotStatusDockView (TelegramHealthPill 대체)`)
- `BotStatusDockView.swift:6`: 주석 (대체 관계 설명)
- `BotStatusDock.swift:7`: 주석 (대체 관계 설명)
- 실제 타입 인스턴스화: 0개

**수정:** 파일 삭제.

---

## 산출물 요약

| 종류 | 파일 |
|------|------|
| 신규 | `Sources/YuminaiCore/RelativeTime.swift` |
| 신규 | `Tests/YuminaiCoreTests/RelativeTimeTests.swift` |
| 신규 | `Tests/YuminaiCoreTests/AppModelSheetExclusionTests.swift` |
| 신규 | `docs/ADR-125-Tier1-Stability-Cleanup.md` |
| 수정 | `Sources/YuminaiApp/AppModel.swift` (dismissAllSheets +5, showGitHubPATSheet -3) |
| 수정 | `Sources/YuminaiApp/GitHubSearchSheet.swift` (relativeDate, loadMoreResults, crawlRepo) |
| 수정 | `Sources/YuminaiApp/LibrarySheet.swift` (relativeDate) |
| 수정 | `Sources/YuminaiApp/TelegramHub/CommandPaletteEditor.swift` (HITL → 위험 명령) |
| 수정 | `Sources/YuminaiUI/SidebarView.swift` (archivebox → cube.box.circle.fill) |
| 삭제 | `Sources/YuminaiUI/TelegramHealthPill.swift` |

---

## 검증

```
swift build  → Build complete!
swift test   → 1315+ tests passed (1303 baseline + 13 RelativeTime + 8 SheetExclusion ≈ +~20)
```

---

## 후속

| 범위 | ADR |
|------|-----|
| Tier 2 (P2) | ADR-126 |
| Tier 3 (P3+) | ADR-127+ |
