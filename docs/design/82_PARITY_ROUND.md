# 82_PARITY_ROUND — Claude Code Parity 라운드

> **목적**: 사용자 명시 7개 후보 + codex CLI 검증으로 도출된 gap을 통합 처리.
> **현실 인정**: Claude Code 데스크탑의 *모든* 기능 parity는 한 라운드 불가능
> (codex가 6건 must-level 거대 작업 도출). 이번 라운드는 7개 + 가능한 polish + 정직한 후속 안내.

---

## 1. codex CLI 검증 (10건 gap, 2026-05-01)

**Must (parity 필수, 거대)**:
1. Pane model (chat + diff + preview + terminal + file) — **거대, 별도 라운드**
2. file-by-file diff review loop — **거대, 별도 라운드**
3. embedded preview + auto-verify (dev server, browser) — **거대**
4. session/history 깊이 (parallel sessions, side chats, archive, transcript modes) — 일부 가능
9. 전체 software delivery loop (CI, auto-fix, auto-merge) — **거대**

**Should (polish + 사용자 명시)**:
5. tool/result inline rendering 풍부화 — 부분 가능
6. notes UX 성숙 — **이번 라운드 핵심**
7. notes를 first-class (recents/favorites/quick-attach) — 부분 가능
8. shortcut discoverability, desktop notifications — 가능
10. execution environment mobility — **별도 라운드**

### 이번 라운드 처리 범위

- **사용자 명시 7개 후보** (전부)
- **codex #6, #7 일부** (notes 성숙화는 이미 사용자 후보와 정합)
- **codex #8 일부** — 키보드 도움말 sheet (⌘?), 노트 favorites
- **별도 라운드 명시**: pane model (#1), diff review (#2), preview (#3), software delivery (#9), execution env (#10)

---

## 2. 사용자 명시 7개 후보 — 결정

### B1. Wiki link disambiguation
- 동명 노트 다수 시 sheet popup으로 선택. 단일 매칭 시 즉시 이동
- AppModel.openNoteByName이 후보 array 반환 → UI sheet
- 결과: `WikiDisambiguationSheet` view + AppModel state

### B2. 검색 매칭 단어 highlight
- `SearchHitRow`의 matchedLine을 AttributedString으로 렌더 — 매칭 substring에 accent bg
- swift-markdown-ui 의존성 X (AttributedString 표준)

### B3. 노트 임베드 `![[Note]]` inline 표시
- MarkdownPreprocessor가 `![[Note]]`를 fallback wiki link 대신 *inline content blockquote*로 변환
- 또는: SwiftUI 측에서 별도 view 합성 — **둘째 옵션 어려움 (swift-markdown-ui 한계)**
- **선택**: inline blockquote — `> [Note](yuminai-note://Note) 본문 첫 N줄...` 형식. 제목 + 본문 head + "전체 보기" link

### B4. Split view 편집
- 편집 모드에서 좌(편집) / 우(preview) toggle
- AppModel.editorSplitMode: `editor / preview / split`
- 헤더에 segmented (편집 / 분할 / 보기)

### B5. 노트 생성/삭제 (CRUD)
- 생성: 사이드 트리 우측 상단 "+" 버튼 → sheet (이름 + 폴더)
- 삭제: 우클릭 menu → 확인 alert → 휴지통으로 이동 (`.trash` 폴더)
- 이동/이름 변경: **v0.4 보류**

### B6. Frontmatter 편집 UI
- raw markdown 편집 시 자연스럽게 frontmatter도 편집 (이미 가능)
- 추가: 노트 헤더에 "tags 추가" 인라인 — 별도 sheet 부담스러움
- **결정**: 별도 UI 없음, 편집 모드에서 raw로 처리 (이미 됨). 명시만.

### B7. 검색 영속 인덱스
- in-memory cache class `VaultIndex` actor — 노트 본문 캐시
- 첫 검색 시 build, watcher가 변경 path만 invalidate
- 큰 vault (1000+) 첫 검색 후 instant
- SwiftData 영속은 v0.5 (다음 dependency)

---

## 3. codex 추가 발견 처리 (이번 라운드 가능한 것)

### C1. 키보드 단축키 도움말 sheet (⌘?)
- ShortcutHelpSheet — 모든 단축키 카테고리별 정리
- ⌘? 또는 ⌘/ 호출

### C2. 노트 favorites
- Vault에 별도 메타: `~/.yuminai/favorites.json` 또는 frontmatter `yuminai-fav: true`
- 사이드 트리에 별 표시 + 별도 group "즐겨찾기"
- **단순화**: 토글만 (별 표시), 별도 group은 v0.4

### C3. Recents
- AppModel에 `recentNoteHistory: [String]` (LRU, 10개)
- 노트 트리 상단에 "최근" 섹션

---

## 4. 비범위 (정직한 안내)

다음 거대 작업은 **별도 라운드 + 사용자 결정** 필요:

| 항목 | 작업량 | 설명 |
|---|---|---|
| Pane model | 1-2주 | NavigationSplitView + 다중 패널 (chat / diff / preview / terminal / file) — RootView 전면 재구성 |
| file-by-file diff review | 1주 | git integration + diff viewer + 인라인 코멘트 |
| embedded preview | 1주 | WKWebView wrapping + dev server 자동 감지 |
| 전체 software delivery loop | 2주+ | gh CLI 통합 + CI 모니터링 + auto-fix |
| Execution env mobility | 큰 | remote/SSH/background — Claude Code 백엔드 의존 |

**이 라운드 후 사용자가 우선순위 결정**: Pane model? Diff? Preview?

---

## 5. 의존성 순서 + 구현 매핑

1. **B7 VaultIndex** (다른 기능들이 활용)
2. **B2 검색 highlight** (B7 인덱스 위에)
3. **B6 frontmatter** (이미 가능, 명시만)
4. **B1 Wiki disambig** (AppModel + sheet)
5. **B3 노트 임베드 inline** (preprocessing 변경)
6. **B4 Split view** (InspectorPanel 편집 UI 분할)
7. **B5 CRUD** (Vault + UI)
8. **C1 도움말 sheet** + **C2 favorites** + **C3 recents**

---

## 6. 검증 매트릭스

| 영역 | 항목 | 검증 |
|---|---|---|
| B1 | 동명 노트 ≥ 2 → sheet 표시 | 수동 |
| B1 | 단일 매칭 → 즉시 이동 | 수동 |
| B2 | 검색 결과 매칭 단어 강조 | 수동 |
| B3 | `![[Note]]` 인라인 미리보기 | 수동 |
| B4 | 편집 / 분할 / 보기 toggle | 수동 |
| B5 | 새 노트 생성 → 트리에 추가 | 수동 |
| B5 | 노트 삭제 → `.trash`로 이동 | 수동 |
| B6 | 편집 모드에서 frontmatter 자연 편집 | 수동 |
| B7 | 큰 vault에서 첫 검색 후 instant | 수동 |
| C1 | ⌘? 도움말 sheet | 수동 |
| C2 | 노트 favorites toggle (별) | 수동 |
| C3 | 최근 본 노트 트리 상단 | 수동 |
| 단위 테스트 | 신규 (highlight, disambig, CRUD) | swift test |
| 빌드 | swift build | 통과 |
| 실행 | swift run | 윈도우 정상 |

---

## 7. ADR-023 — 7+3 일괄 + 거대 작업 별도 라운드 명시
- 결정: 사용자 7개 + codex polish 3개 = 10개 일괄. 거대 (pane/diff/preview/CI/exec env)는 별도 라운드 + 사용자 결정 대기.
- 근거: parity는 점진. 한 라운드에 모든 must 처리 비현실 (codex 인정).
- 후속: 사용자가 우선순위 정해주면 그 항목 별도 명세 + 구현.
