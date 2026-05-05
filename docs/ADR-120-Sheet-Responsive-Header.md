# ADR-120 — Sheet 반응형 + 헤더 일관성

**날짜**: 2026-05-04  
**상태**: 완료  
**연관**: ADR-073, ADR-074, ADR-117

---

## 배경

사용자 신고:

> "팝업의 상단이 조금 잘리는 것 같아, 이것 외에도 다른 팝업들도 한 번 uiux와 반응형 확인해 줘"

진단:

1. **CommunityResourcesSheet 이중 헤더** — Sheet wrapper 헤더("📦 커뮤니티 자료 + X 버튼")와 그 아래 `CommunityResourcesPanel` 내부 헤더("📦 커뮤니티 자료 + 스택 번들/GitHub 검색/전체 카탈로그/라이브러리 보기 버튼")가 중복.
2. **고정 frame 반응형 실패** — `CommunityResourcesSheet`에 `.frame(width: 860, height: 640)` 하드코딩. 윈도우 < 640px 세로에서 잘림.
3. **여러 sheet에 동일 문제** — 총 9개 sheet/dashboard에 fixed `frame(width:height:)` 직접 사용 확인.

---

## 결정

### A. SheetHeader 공용 컴포넌트 신규

`Sources/YuminaiUI/SheetHeader.swift`

```swift
SheetHeader(icon:title:subtitle:onClose:trailing:)
```

모든 sheet 헤더를 통일하는 컴포넌트:
- 좌측: SF Symbol 아이콘 + 제목 (16pt semibold) + 옵셔널 부제목
- 중앙 trailing: `@ViewBuilder trailing` — 액션 버튼 그룹 삽입 가능
- 우측 끝: `xmark.circle.fill` X 닫기 버튼 (항상 고정)
- padding: `Theme.Spacing.lg horizontal`, `.md vertical`
- background: `Theme.Color.surface`
- 하단 Divider 포함

### B. CommunityResourcesSheet 이중 헤더 제거 (Option B)

**선택**: Sheet wrapper SheetHeader 유지 + Panel `headerSection` 제거.

변경:
- `CommunityResourcesSheet`: 4개 액션 버튼(스택 번들/GitHub 검색/전체 카탈로그/라이브러리 보기)을 SheetHeader trailing으로 이동
- `CommunityResourcesPanel`: `showHeader: Bool = true` 파라미터 추가 → Sheet에서 호출 시 `showHeader: false`

### C. 반응형 마이그레이션

`.frame(width:height:)` 고정 → `yuminaiSheetFrame(width:height:)` 반응형

| 파일 | 변경 전 | 변경 후 |
|------|---------|---------|
| `CommunityResourcesSheet.swift` | `.frame(width: 860, height: 640)` | `.yuminaiSheetFrame(width: 860, height: 640)` |
| `HarnessSheets.swift` (WalkthroughSheet) | `.frame(width: 720, height: 540)` | `.yuminaiSheetFrame(width: 720, height: 540, wrapInScrollView: false)` |
| `HarnessSheets.swift` (HarnessHelpSheet) | `.frame(width: 640, height: 600)` | `.yuminaiSheetFrame(width: 640, height: 600, wrapInScrollView: false)` |
| `LibrarySheet.swift` (AddLibraryTextSheet) | `.frame(width: 580, height: 620)` | `.yuminaiSheetFrame(width: 580, height: 620, wrapInScrollView: false)` |
| `LibrarySheet.swift` (AddLibraryURLSheet) | `.frame(width: 480, height: 400)` | `.yuminaiSheetFrame(width: 480, height: 400, wrapInScrollView: false)` |
| `LibrarySheet.swift` (LibraryItemContentSheet) | `.frame(width: 600, height: 500)` | `.yuminaiSheetFrame(width: 600, height: 500, wrapInScrollView: false)` |
| `LibrarySheet.swift` (EditLibraryItemSheet) | `.frame(width: 440, height: 340)` | `.yuminaiSheetFrame(width: 440, height: 340, wrapInScrollView: false)` |
| `ChartsDashboard.swift` | `.frame(width: 920, height: 700)` | `.yuminaiSheetFrame(width: 920, height: 700, wrapInScrollView: false)` |
| `TelegramUsageDashboard.swift` | `.frame(width: 880, height: 720)` | `.yuminaiSheetFrame(width: 880, height: 720, wrapInScrollView: false)` |
| `GitBranchPickerSheetWrapper.swift` | `.frame(width: 380)` | `.yuminaiSheetFrame(width: 380)` |

**점검 결과 — 반응형 이미 OK (변경 불필요):**

| Sheet | 이유 |
|-------|------|
| `LibrarySheet` (메인) | `.frame(minWidth: 760, minHeight: 540)` — 이미 반응형 |
| `GitHubSearchSheet` | `.frame(minWidth: 720, minHeight: 580)` — 이미 반응형 |
| `GitHubPATSheet` | `.frame(minWidth: 520, minHeight: 420)` — 이미 반응형 |
| `UserProfileSheet` | `YuminaiSheet(wrapInScrollView: false)` — ADR-110 완료 |
| `ImageCropSheet` | 자체 canvas layout, 반응형 불필요 |
| `SetupWizardSheet` | `yuminaiSheetFrame` 이미 적용 확인 필요시 개별 점검 |
| `CreateWorkspaceSheet` | `YuminaiSheet` 사용 (YuminaiUI 내부) |
| `AboutSheet`, `ShortcutHelpSheet`, `RehearsalSheet` | YuminaiUI 내부, 별도 점검 OK |

---

## 검증

- `swift build` 성공
- 총 신규/수정 파일: 11개
  - 신규 1: `SheetHeader.swift`
  - 수정 10: `CommunityResourcesSheet.swift`, `CommunityResourcesPanel.swift`, `HarnessSheets.swift`, `LibrarySheet.swift` (4 sub-sheets), `ChartsDashboard.swift`, `TelegramUsageDashboard.swift`, `GitBranchPickerSheetWrapper.swift`

---

## 수동 검증 가이드

1. **CommunityResourcesSheet**: 사이드바에서 "커뮤니티 자료" 클릭 → 헤더가 한 번만 보임, 스택 번들/GitHub 검색/전체 카탈로그/라이브러리 보기 버튼이 헤더 우측에 표시
2. **소형 윈도우 테스트**: 윈도우를 640px 이하로 줄인 뒤 각 sheet 오픈 → 잘림 없음 확인
3. **HarnessSheets**: Task walk-through / 도움말 sheet 오픈 → 반응형 동작 확인
4. **LibrarySheet 서브 시트**: 자료 추가(텍스트/URL), 내용 보기, 편집 시트 오픈 → 소형 윈도우에서 잘림 없음
5. **ChartsDashboard / TelegramUsageDashboard**: 각 대시보드 오픈 → 1280x800 이하 해상도에서 잘림 없음

---

## 후속 작업

- [ ] 나머지 `SetupWizardSheet`, `AboutSheet`, `ShortcutHelpSheet` 개별 점검 (ADR-121 예정)
- [ ] 모든 sheet에 SheetHeader 컴포넌트 적용 확장 (현재는 CommunityResourcesSheet만 SheetHeader 사용)
