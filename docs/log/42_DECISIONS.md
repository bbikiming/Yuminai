# Decisions Log (ADR-lite)

> 최신: ADR-039 (v0.9+ R3 — File CRUD UX: 새 파일/폴더 + 이름 변경 + 삭제 + path safety)

---

## ADR-039 — v0.9+ R3: File CRUD UX (rename / new file / new folder / delete)

- **날짜**: 2026-05-02
- **상태**: Accepted
- **결정**: ADR-038 v1.0+로 미뤘던 파일 CRUD UX를 v0.9+ R3로 앞당김 — 사용자가 외부 IDE 없이 워크스페이스 내에서 파일 생성/이름변경/삭제 가능. `WorkspaceFileTree` actor에 4 CRUD 메서드 + path safety + UI: 트리 컨텍스트 메뉴 + 공통 이름 입력 sheet + 삭제 confirmation alert
- **컨텍스트**:
  - 사용자 — "진행해 줘" (R2 점검 후 file CRUD가 ROI 가장 높다는 분석 승인)
  - ADR-038 v1.0+ 후보 중 가장 자연스러운 후속 — Multi-tab + 검색 까지 가능하지만 새 파일 만들려면 외부 IDE 필요했던 것
  - macOS Finder 컨텍스트 메뉴 + VSCode tree 패턴 표준 — 새로 학습할 게 적음
- **각 결정**:
  1. **CRUD 4종 일괄 (rename / new file / new folder / delete)**:
     - **편집 + 정리** workflow 완전성을 위해 4종 모두 필요. rename만 빼고는 외부 IDE 의존
     - **delete confirmation 필수** — 폴더는 재귀 삭제 (Finder 휴지통 X, 영구 삭제) 명시
  2. **공통 이름 입력 sheet (FileNameSheet) — 단순화**:
     - 새 파일/새 폴더/이름 변경 모두 같은 UI shape (TextField 1개 + 부모 위치 표시 + Enter/Esc)
     - 3개 별도 sheet → 1 sheet + intent enum으로 단순화 (FileNameSheetIntent)
     - sheet binding은 `Identifiable` enum + `.sheet(item:)` 패턴
     - inline tree rename (TextField in row)은 SwiftUI에서 focus 관리 까다로움 + sheet가 더 안전 — VSCode도 sheet/popover 선호
  3. **삭제는 alert (sheet X)**:
     - destructive operation은 SwiftUI `Alert` + `.destructive` button role 표준
     - confirmation message에 "복구할 수 없어요" + 폴더면 "안 모든 파일이 함께 삭제" 명시
  4. **컨텍스트 메뉴 (`.contextMenu`) — Finder/VSCode 표준**:
     - 파일: 이름 변경 / 삭제
     - 폴더: 새 파일 / 새 폴더 / divider / 이름 변경 / 삭제
     - root scope 새 파일/새 폴더는 트리 헤더 + 버튼 (Finder의 "현재 폴더" 동작 차용)
  5. **Path safety (보안 — 절대 필수)**:
     - 빈 경로 / 절대 경로 (`/etc/passwd`) / `..` traversal 모두 차단
     - `resolveSafePath` helper — standardize 후 rootURL prefix 검증 (symlink escape 방어)
     - rename 시 새 이름에 `/`/`\\` 포함 차단 (같은 부모 디렉토리 내에서만 허용)
  6. **AppModel openFileTabs 자동 sync**:
     - **rename**: 영향받는 tab path를 새 path로 업데이트 (파일 단일 + 폴더 prefix 변경 둘 다)
     - **delete**: 영향받는 tab 모두 강제 close (dirty 무시 — 디스크에 없으니 의미 없음)
     - **create file**: 새 파일은 자동 tab 열기 (편집 즉시 가능 UX)
- **단순화 ROI 분석**:
  - **CRUD 4종**: 가치 80 (외부 IDE 의존 제거), 비용 1.5인일 (path safety + tab sync 까다로움) — ROI 양호
  - **공통 sheet**: 비용 절감 (3개 별도 → 1) + UI 일관성
  - **컨텍스트 메뉴**: 비용 0.2인일 (`.contextMenu` modifier만), 가치 50 (사용자 학습 최소)
- **격리**:
  - `WorkspaceFileTree`: CRUD + path safety는 Core (UI 의존 X)
  - `FileNameSheet` / `FileDeleteConfirmation` / `FileNameSheetIntent`: App 모듈 (UI binding 종속)
  - `FilesPanel`: UI에서 callback만 호출 (sheet/alert 책임 X)
  - **분리 원칙**: UI는 의도(intent)를 emit, App layer가 sheet/alert 제어
- **외부 의존성 정책**:
  - 새 dependency 없음 — Foundation FileManager + SwiftUI 표준 사용
- **단순화 보류 (v1.0+)**:
  - **inline rename** (트리 cell 안 TextField) — focus 관리 까다로움, sheet로 충분
  - **drag-drop 폴더 이동** — rename + 같은 부모 제약 풀어야 함, 큰 작업
  - **휴지통 (Trash, NSWorkspace.recycle)** — 복구 가능 옵션. 현재는 영구 삭제만, 사용자 신호 후 추가
  - **다중 선택 + 일괄 삭제** — checkbox UI 비용
  - **rename 시 imports/refs 자동 업데이트** — LSP 의존 (큰 작업)
- **결과**:
  - 신규 파일 2개 (App): FileNameSheet.swift / FileNameSheetIntent (같은 파일)
  - 신규 파일 1개 (Test): WorkspaceFileTreeCRUDTests.swift (19 tests)
  - 수정 파일 4개:
    - YuminaiCore/WorkspaceFileTree.swift — CRUD 4 메서드 + resolveSafePath helper + 3 새 error case
    - YuminaiApp/AppModel.swift — 4 CRUD 메서드 + commitFileNameIntent + 2 sheet state
    - YuminaiUI/FilesPanel.swift — 4 callback + tree header CRUD 버튼 + FileNodeRow 컨텍스트 메뉴
    - YuminaiUI/InspectorPanel.swift — 4 callback forwarding
    - YuminaiApp/RootView.swift — sheet/alert binding + 4 callback wiring
  - **테스트 19 신규 (271/271 통과, 252→271)**:
    - createFile (basic / 중첩 / duplicate reject)
    - createFolder (basic / duplicate reject)
    - rename (basic / 중첩 / `/` 차단 / 빈 이름 / missing source / target exists)
    - delete (file / folder 재귀 / missing)
    - path safety (절대 경로 / `..` traversal / 빈 경로)
    - workflow 통합 (createFile then read / createFile then write)
  - 빌드 6.71s clean
- **알려진 한계 / v1.1+**:
  - 폴더 사이 이동 (drag-drop or rename to different parent)
  - 휴지통 (NSWorkspace.recycle)
  - 다중 선택 일괄 작업
  - rename 시 자동 imports 업데이트 (LSP)
  - inline rename (트리 cell 내 TextField)
- **재검토**:
  - 사용자 외부 IDE 사용 빈도 감소 여부 (가설: file CRUD 추가 후 80% 워크플로 Yuminai 안에서 가능)
  - delete confirmation이 너무 잦은 마찰 만드는지
  - 컨텍스트 메뉴 vs 단축키 — `Delete` 키 / `F2` rename 표준 단축키 추가 필요한지

---

## ADR-038 — v0.9+ R1: Syntax highlight + Multi-tab + Cmd+P 파일 검색 + Quick command 사용자 정의

- **날짜**: 2026-05-02
- **상태**: Accepted
- **결정**: ADR-037 v0.9+ deferred 항목 4개 일괄 — E1 syntax highlight (Highlightr) + E2 multi-tab 편집 + E3 file search sheet + E4 quick command 사용자 정의. E5/E6 (block 강화 / ACP Spike) 보류
- **컨텍스트**:
  - 사용자 — "v0.9+ 항목들 전부 논리적으로 기획해 가면서 구현해 줘"
  - ADR-037 v0.8 R1에서 단순화 보류된 IDE 인접 기능들 — 사용자 평가 후 가치 검증된 항목 우선
  - v0.8 사용으로 raw mono viewer가 가독성 한계 + 다중 파일 동시 검토 needs 확인
- **각 결정**:
  1. **E1 Syntax highlight = Highlightr 채택**:
     - 대안 평가: SwiftUI native code editor (없음) / Sourceful (오래됨) / Highlightr (Highlight.js wrap, MIT, 활성)
     - **선택 이유**: 100+ 언어 즉시 + AppKit NSAttributedString → AttributedString 변환 가능 + 단일 의존성 / lock-in 완화 (CodeViewer가 Highlightr 직접 노출 X — 외부에는 SwiftUI View)
     - **단순화**: read-only viewer만 highlight (editor는 raw TextEditor 유지 — editable highlight = NSTextView wrap이 큰 작업, v1.0+)
     - **fallback**: > 100KB 파일은 plain text (highlight 비용 회피, 일반 코드는 < 50KB)
     - **theme**: atom-one-dark 고정 (Yuminai dark-first — light theme switch는 v1.0+)
  2. **E2 Multi-tab 편집**:
     - **상태 모델**: `FileTab` struct (id/path/savedContents/draft/isEditing) + `[FileTab]` in AppModel + `activeFileTabId`
     - **legacy 유지**: 기존 `selectedFilePath`, `workspaceFileDraft` 등 single-file API는 active tab의 computed projection으로 retained — 호출자 리팩터링 없이 multi-tab 동작
     - **dirty tracking**: `isDirty = isEditing && draft != savedContents` — preview-only navigation은 dirty 아님
     - **tab 한도**: 10개 (FIFO non-dirty 제거 — dirty tab은 사용자 명시 close 필요)
     - **close protection**: dirty tab close는 reject (저장 또는 discard 필수) — VSCode 패턴
  3. **E3 File search (Cmd+P)**:
     - **알고리즘**: prefix(100) > name contains(50) > path contains(20) + 짧은 이름 가산점 — full fuzzy matcher (Sublime/VSCode식 char-by-char) 보류 ROI 약함
     - **격리**: `FuzzyFileFilter` enum을 Core에 추출 (테스트 가능) / FileSearchSheet (App)는 UI binding만
     - **결과 cap**: 50개 (성능 + 인지 부하) — 뮈 매칭 더 좁은 query 유도
     - **binary 자동 제외**: WorkspaceFileTree의 isBinary flag 활용
  4. **E4 Quick command 사용자 정의**:
     - `CustomQuickCommand` struct (id/label/command) → `DeliveryConfig.customQuickCommands` 영속
     - **UI**: WorkspaceDeliverySheet에 customQuickSection 추가 (이름 + 명령 TextField + 추가/제거 버튼)
     - **chip icon**: sparkles (default 명령들과 시각 구분)
     - **순서**: test/build/lint default → custom → git 명령 (사용자 자주 쓰는 것이 default와 git 사이)
  5. **E5/E6 보류**: CommandRunner block 강화 (search/replay/share 등) + ACP Spike — ROI 약하거나 외부 의존 변동 큼. v1.0+ 사용자 신호 후
- **단순화 ROI 분석**:
  - **Syntax highlight**: 가치 90 (코드 가독성 핵심), 비용 0.5인일 (Highlightr 단일 의존성, viewer-only) — ROI 압도
  - **Multi-tab**: 가치 75 (multi-file workflow 표준), 비용 1인일 (dirty tracking + close protection) — ROI 양호
  - **Cmd+P**: 가치 70 (대형 프로젝트에서 트리 navigation 한계), 비용 0.3인일 (단순 fuzzy + sheet) — ROI 압도
  - **Custom quick**: 가치 50 (사용자 워크플로 특화), 비용 0.2인일 (DeliveryConfig 필드 + sheet UI) — ROI 양호
- **격리**:
  - **Highlightr**: YuminaiUI 의존성. CodeViewer가 wrap (외부에 Highlightr API 노출 X)
  - **FileTab**: YuminaiCore (UI 의존 X)
  - **FuzzyFileFilter**: YuminaiCore (FileNode 의존, 테스트 가능)
  - **FileSearchSheet**: YuminaiApp (FuzzyFileFilter 사용, UI binding)
  - **CustomQuickCommand**: YuminaiCore (DeliveryConfig와 함께 영속)
- **외부 의존성 정책 변경**:
  - Highlightr 추가 (raspu/Highlightr, MIT) — ADR-021 (swift-markdown-ui 추가) 패턴 동일 검토
  - **lock-in 완화**: CodeViewer가 wrap하므로 향후 dropping 가능 (Highlightr 미사용 시 plain text fallback 동작)
- **결과**:
  - 신규 파일 5개: CodeViewer.swift / FileTab.swift / FuzzyFileFilter.swift / FileSearchSheet.swift / FileTabTests.swift / FuzzyFileFilterTests.swift / CodeViewerTests.swift (4 src + 3 test)
  - 수정 7개: Package.swift (Highlightr) / DeliveryConfig.swift (customQuickCommands) / AppModel.swift (multi-tab) / FilesPanel.swift (tab bar + search btn + CodeViewer) / InspectorPanel.swift (forwarding) / RootView.swift (sheet + ⌘P hotkey + custom quick) / CommandRunnerPane.swift (custom param) / WorkspaceDeliverySheet.swift (custom section)
  - 신규 테스트 31개 — FileTab(7) + CustomQuickCommand(4) + FuzzyFileFilter(11) + CodeViewer(9)
  - build 7.05s clean, 31/31 v0.9+ tests 통과
- **알려진 한계 / v1.0+**:
  - Editable highlight (현재 read-only viewer만)
  - Light theme support (현재 atom-one-dark 고정)
  - File rename / new file / delete UX
  - Tree fuzzy filter inline (현재 Cmd+P sheet만)
  - Custom quick command 위치 reorder
  - Command block search/share/replay (E5)
  - ACP 진짜 양방향 (E6)
- **재검토**:
  - Highlightr 성능 — 1MB 코드에서 500ms 이상이면 worker thread offload 검토
  - Multi-tab 한도 10이 너무 작은지 (사용자 사용 데이터로)
  - Cmd+P 결과 50 cap이 missed match 야기하는지
  - Custom quick command가 deliveryConfig.customQuickCommands가 아닌 별도 영속이 필요한지

---

## ADR-037 — v0.8 R1: 워크스페이스 파일 트리 + 뷰어/편집기 + Quick command 버튼

- **날짜**: 2026-05-02
- **상태**: Accepted
- **결정**: 사용자 요청 IDE-like 기능을 단순화 패턴으로 — 워크스페이스 파일 트리 + viewer/editor (Inspector "파일" 탭) + CommandRunnerPane에 quick command 버튼
- **컨텍스트**:
  - 사용자 — "0.8 진행해주고 터미널 실행 기능, ide처럼 코드 뷰어 및 편집 기능도 추가해 줘"
  - 터미널: 이미 SwiftTerm + CommandRunnerPane 있음 → 강화 (quick command + history 유지)
  - IDE-like: 파일 트리 + 뷰어/편집기 (단순화: 1-file, no syntax highlight)
- **각 결정**:
  1. **D1+D2 IDE-like (단순화)**: VSCode-class 풀 IDE는 cost prohibitive. 단순화 — 트리 + 1-file viewer/editor, Inspector 탭. Obsidian Vault NoteTreeView/MarkdownViewer 패턴 차용
  2. **D3 Multi-tab 보류**: tab state + dirty tracking 큰 작업. 현재 디자인 (편집 중이면 다른 파일 reject)이 안전하고 단순
  3. **D4 Syntax highlight 보류**: SwiftUI native code editor 부재. NSViewRepresentable wrap이 가능하지만 (Highlightr 등) 외부 의존성 추가 + 유지보수 비용. raw mono로 시작, v0.9+ 라이브러리 발견 시
  4. **D5 Command history**: 이미 메모리 max 50 — 충분 (single session 내). SwiftData 영속은 cost 작지만 user value 모호 → v0.9
  5. **D6 Quick command**: workspace.deliveryConfig 활용 + git 기본 명령. 사용자 정의는 v0.9
- **단순화 ROI 분석**:
  - VSCode IDE: 가치 100, 비용 50인일 (LSP + multi-tab + syntax + folding + ...)
  - **단순 트리+뷰어**: 가치 70 (read/edit), 비용 0.5인일 — ROI 압도적
- **WorkspaceFileTree 설계 결정**:
  - actor (Vault 패턴 동일)
  - 자동 제외 list — gitignore parsing은 큰 작업 vs 알려진 폴더 hardcode가 80% 케이스 cover
  - max depth 6 — 무한 재귀 방지 (typical project 깊이)
  - file size 1MB limit — UI 무거움 회피
  - binary 자동 감지 — viewer/editor에 안 좋은 파일 hide
- **편집 안전 결정**:
  - dirty 상태에서 다른 파일 선택 reject (data loss 방지)
  - 자동 prompt save dialog는 추가 UI 비용 → v0.9
  - 사용자가 "저장 또는 취소" 명시적 액션 필요
- **격리**:
  - WorkspaceFileTree는 Core (UI 의존 X)
  - FilesPanel은 UI (FileNode 의존)
  - QuickCommand는 UI (private 단순 struct)
  - AppModel은 file state owner (single source of truth)
- **결과**:
  - 신규 파일 2개: WorkspaceFileTree.swift / FilesPanel.swift
  - InspectorTab .files 추가 (4 탭)
  - InspectorPanel +14 params (file tree state + callbacks)
  - AppModel +6 file state + 5 file methods
  - CommandRunnerPane +QuickCommand + quickCommandRow + Chip view
  - RootView InspectorPanel 호출 + workspace 변경 .task hook
  - 7 신규 테스트 (WorkspaceFileTree)
  - build 5.9s, test 216/216 (209→216, +7)
- **알려진 한계 / v0.9+**:
  - Multi-tab 편집 (현재 1 file)
  - Syntax highlight (Highlightr 등 외부 의존성 평가)
  - File rename / new file / delete UX (현재는 외부 IDE 사용)
  - File search (Cmd+P)
  - Command history 영속 (SwiftData)
  - Quick command 사용자 정의
- **재검토**:
  - 사용자 inline 편집 사용 빈도 vs 외부 IDE
  - syntax highlight 진짜 필요한지 (raw mono로 충분?)
  - Multi-tab 필요성 (1 file이 충분한지)
  - Quick command 사용자 정의 요구 빈도

---

## ADR-036 — v0.5 R3: Live ping + Editable diff (inline) + Terminal block (별개 pane) + chain hint 강화

---

## ADR-036 — v0.5 R3: Live ping + Editable diff (inline) + Terminal block (별개 pane) + chain hint 강화

- **날짜**: 2026-05-02
- **상태**: Accepted
- **결정**: v0.7+ 보류 항목 5개 평가 → 4/5 진행, 모두 단순화 패턴 채택. ACP는 별도 spike 작업으로 유지
- **컨텍스트**:
  - 사용자 — "v0.7+ 권고 항목들도 구현 진행"
  - 보류 항목 모두 cost prohibitive였으나, 단순화 가능한 것들만 진행
- **각 결정**:
  1. **C1 ping**: ROI 명확. 0.3s timeout으로 빠른 응답, false-positive 위험은 confidence label로 완화
  2. **C2 chain hint**: 코드 변경 작음. 사용자가 chain의 multi-mention sequential 효과를 자연스럽게 알게
  3. **C3 editable diff (TextEditor)**: Cline editable은 SwiftUI native diff editor 부재로 비용 prohibitive. 단순화 — segmented "Diff/편집" 토글 + raw TextEditor. syntax highlight X but cost 80% 감소
  4. **C4 CommandRunnerPane (별개)**: SwiftTerm은 PTY-based, block grouping 불가. **별개 패널** 채택 — NSTask로 단일 명령 + block. 사용자에게 명확한 use case 분리 (interactive zsh = ⌘⌥T, 기록되는 명령 = ⌘⌥R)
- **C3 단순화 가치**:
  - 진짜 Cline editable diff: gutter + inline edit + 변경 추적 — 3-5인일
  - inline TextEditor: 100라인 정도 — 0.5인일
  - 사용자 가치 중 80%는 "수정 가능" 자체에서 옴 — diff editor UX는 polish
- **C4 별개 pane 결정 사유**:
  - SwiftTerm wrap으로 block UX 추가 = PTY parser + prompt 인식 + grouping = 매우 큼
  - 별개 pane = NSTask + 단순 UI = 1인일
  - 사용자 use case 다름:
    - 기존 SwiftTerm: interactive zsh, vim/htop 같은 interactive
    - 새 CommandRunnerPane: 한 번 실행 + 결과 기록 (npm test, git status 등)
  - 두 use case 분리가 UX 더 명확
- **격리**:
  - DevServerDetector.pingAll은 Core (URLSession Foundation)
  - CommandRunner는 Core (NSTask Foundation)
  - CommandRunnerPane은 UI (Core 의존)
- **결과**:
  - 신규 파일 2개: CommandRunner.swift / CommandRunnerPane.swift
  - DevServerDetector +pingAll + isAlive 필드
  - PreviewPane SuggestionChip live indicator
  - DiffView +inline editor (segmented 토글)
  - AppModel +readWorkspaceFile / writeWorkspaceFile / runCommand / clearCommandBlocks / refreshDevServerSuggestions
  - ChatToolbar +commands toggle (⌘⌥R)
  - RootView 3-way VSplit (chat / terminal / commands)
  - InspectorPanel +readChangedFile / onSaveChangedFile
  - Composer hint chain-aware
  - 3 신규 테스트 (CommandRunner)
  - build 7.2s, test 209/209 (206→209, +3)
- **알려진 한계 / v0.8+**:
  - Live ping 0.3s timeout — slow server false-negative 가능
  - Editable diff syntax highlight X (SwiftUI Code Editor 라이브러리 발견 시)
  - CommandRunnerPane은 1회 명령만 (vim 등 interactive는 SwiftTerm 사용)
  - 진짜 Warp PTY-aware block UX — SwiftTerm wrap 큰 작업
  - ACP 실제 PoC — 2-3일 별도 (ADR-034 doc 유지)
- **재검토**:
  - ping false-positive/negative 빈도 (사용자 사용 데이터)
  - inline editor 사용 빈도 (외부 IDE 대비)
  - CommandRunner vs Terminal 사용 빈도 비교

---

## ADR-035 — v0.5 R2: Dev server auto-detect + Editable diff 단순화 + multi-mention 안내 + Dual-Composer split

---

## ADR-035 — v0.5 R2: Dev server auto-detect + Editable diff 단순화 + multi-mention 안내 + Dual-Composer split

- **날짜**: 2026-05-02
- **상태**: Accepted
- **결정**: UX 검토 후 4/6 진행 — 가치 큰 것 + 구현 가능한 것. Terminal Block UX와 ACP는 cost 명시 보류
- **컨텍스트**:
  - 사용자 — "다음 단계도 이어서 구현해 줘 uiux를 상세히 검토해서 구현해"
  - **상세 UX 검토** — 단순 구현 X, 각 항목 사용성 분석 후 결정
- **각 결정**:
  1. **B1 dev server auto-detect** — package.json + config 파일 분석. ping은 X (사용자가 server 시작했는지 모름, false-positive 회피). Suggestion chip으로 추천만, 사용자 클릭 시 로드
  2. **B2 Editable diff 단순화** — Cline editable은 SwiftUI 자체 구현 prohibitive (3-5인일). External editor 버튼으로 단순화 — NSWorkspace.open이 Xcode/VSCode/etc 자동 열어줌. 가치 80% 비용 5%
  3. **B3 Multi-mention 안내** — parallel dispatch는 multi-pane state 충돌 위험 + UX 복잡. 첫 mention만 + UI hint로 명확화 (사용자가 잘못 쓰면 알아챔)
  4. **B4 Dual-Composer 단순화** — 진짜 isolated dual은 Composer state 분리 매우 큼. **단순화**: secondary는 자체 input draft만 보관, send 시 setActivePane → input swap → sendMessage. 양쪽 동시 입력 가능 + send가 active 전환을 트리거 (focus follow)
- **B1 UX 결정 — ping vs 추천**:
  - ping (HTTP HEAD)으로 서버 살아있는지 확인 가능 but:
    - false-positive: localhost:3000이 다른 앱 점유 가능
    - 사용자가 anyway URL 직접 클릭해야 — ping은 noise
  - **추천만 채택** — confidence label로 user expectation 관리
- **B2 단순화 가치 분석**:
  - Cline editable 가치: 100 (매우 높음)
  - SwiftUI 자체 diff editor 비용: 100 (3-5인일 + 유지보수)
  - External editor 가치: 80 (사용자가 익숙한 IDE 사용 가능)
  - External editor 비용: 5 (NSWorkspace.open 1줄)
  - **ROI: External editor가 압도적**
- **B4 Dual 단순화 — focus follow 패턴**:
  - 진짜 dual은 두 Composer가 독립 + 각자 active pane으로 send
  - 문제: 어느 쪽이 ⌘Return target인지, 양쪽 isStreaming 상태 동시 추적
  - **단순화**: send 시 active 전환 — 사용자 의도가 명확 (이 pane으로 보낸다 = 이 pane을 본다)
  - 양쪽 입력 draft는 보존 (secondary @State) — 사용자가 panes 옮겨다니면서 draft 유지
- **격리**:
  - DevServerDetector는 YuminaiCore (UI 의존 X)
  - openFileInExternalEditor는 AppModel (NSWorkspace.open)
  - SecondaryPaneView 자체 @State (AppModel state 변경 X)
- **결과**:
  - 신규 파일 1개: DevServerDetector.swift
  - PreviewPane +SuggestionChip + suggestions strip
  - DiffView.FileRow +open in editor 버튼
  - AppModel +openFileInExternalEditor + sendToPane
  - InspectorPanel +onOpenChangeInEditor callback
  - SecondaryPaneView +자체 Composer (draft @State)
  - MentionParser +allInline
  - Composer +multiMentionHint (orange banner)
  - 15 신규 테스트
  - build 7.6s, test 206/206 (191→206, +15)
- **알려진 한계 / 보류**:
  - **Terminal Block UX (Warp)** — SwiftTerm 한계, 자체 PTY wrap 비용 매우 큼 → v0.7+
  - **ACP 실제 PoC** — 2-3일 별도 spike, ADR-034 doc 자료 유지
  - Multi-mention parallel dispatch — v0.7+ (state 충돌)
  - Dev server ping — false-positive 위험으로 X
  - External editor는 system default (Xcode 등) — 사용자 설정 가능
- **재검토**:
  - 사용자 dual-Composer 사용 후 — focus follow가 자연스러운지
  - 사용자 dev server suggestion 사용 후 — confidence label이 실용적인지
  - Terminal Block UX 진짜 필요한지 (사용자 명시 요청 데이터)

---

## ADR-034 — v0.5 Round 1: Agent chain + Inline mention + PreviewPane + Codex schema + Terminal reload + ACP decision doc

---

## ADR-034 — v0.5 Round 1: Agent chain + Inline mention + PreviewPane + Codex schema + Terminal reload + ACP decision doc

- **날짜**: 2026-05-02
- **상태**: Accepted (v0.5 시작)
- **결정**: 보류했던 v0.5 권고 항목 10개 평가 → 6개 진행 (A1~A6), 4개 명시 보류 (cost prohibitive 또는 가치 < 비용)
- **컨텍스트**:
  - 사용자 — "권고 항목 모두 진행해 줘"
  - **냉정 평가** — 모두 진행은 비효율. cost-prohibitive 항목은 명시 보류
- **각 결정**:
  1. **A1 pane→pane 자동 답장** — default OFF (안전 우선) + max hops Stepper + 같은 pane 재방문 차단 + UI banner. 사용자가 명시적으로 켜야 동작
  2. **A2 inline mention** — `parseInline(_:)` 추가. body는 원문 보존 (mention 위치 컨텍스트). email-like 무시 (단어 경계 검사)
  3. **A3 Codex schema** — 12 alias + logger.warning (unknown type 누적 데이터)
  4. **A4 PreviewPane** — WKWebView 단순 wrap + URL TextField. scheme 자동 추정 (http://default)
  5. **A5 Terminal reload** — block 그룹화는 SwiftTerm 한계 → 단순화 (`id(trigger)` 패턴으로 새 view spawn). 풀 block UX는 v0.6+
  6. **A6 ACP doc** — Spike summary만, 코드 변경 X. v0.6 결정 자료
- **명시 보류 사유**:
  - **Dual-Composer split** — 비용 매우 큼 (Composer state 분리, focus management). 가치 보통 → v0.6
  - **Editable diff** — Cline SOTA지만 SwiftUI native diff editor 부재, 자체 구현 prohibitive (3-5인일). SwiftUI 솔루션 발견 시 재검토
  - **인터랙티브 튜토리얼** — 가이드 카드(ADR-033 G3)로 충분 — 추가 비용 < 가치
  - **T5 per-pane settings** — tab swap이 동일 효과, 가치 < 비용 (계속 보류)
- **A1 안전 설계**:
  - default OFF (사용자 명시 토글 필요)
  - max hops Stepper 1~5 (default 1)
  - 같은 pane 재방문 차단 (visited set)
  - 자기 자신 mention skip
  - 실패(exit≠0) 시 chain 즉시 종료
  - UI banner (활성 시 표시) + "중단" 버튼
- **A2 mention 정밀도**:
  - leading parser는 그대로 (body = mention 제거)
  - inline parser는 body = 원문 보존 (mention 위치 컨텍스트)
  - email-like 무시 (`@` 앞 공백/시작 검사)
  - 첫 mention만 인식 (multi-target은 v0.6)
- **A4 PreviewPane 단순화 결정**:
  - dev server auto-detect (예: package.json 보고 npm dev port 추정)는 v0.6
  - 사용자가 직접 URL 입력하는 단순 패턴이 cost-effective + UX 명확
- **A5 SwiftTerm 한계**:
  - SwiftTerm은 line-based PTY emulator — 명령 경계 인식 X
  - Warp-style block은 Yuminai가 자체 wrap (NSTask + 출력 grouping)으로 가능하지만 큰 작업
  - **단순화 채택**: reload 버튼 + hint만. 풀 block UX는 v0.6
- **격리**:
  - Agent chain 로직은 AppModel (state + hook)
  - MentionParser 확장은 Core (다른 모듈도 사용 가능)
  - PreviewPane은 YuminaiUI (WebKit import)
- **결과**:
  - 신규 파일 2개: PreviewPane / 02_ACP_DECISION.md
  - AppPreferences +2 (agentChainEnabled / agentChainMaxHops)
  - AppModel +chain state (3) + chain logic (2 메서드) + preview state (2)
  - MentionParser +parseInline + parseAny
  - LiveCodexAdapter +12 type alias + logger
  - SettingsView +Agent Chain section (toggle + Stepper)
  - ChatToolbar +preview toggle (⌘⌥P)
  - RootView +chain banner + preview HSplitView + chatColumnWithOptionalTerminal
  - TerminalPane 헤더에 reload 버튼 + HelpHint
  - 7 신규 테스트 (MentionParser inline)
  - build 5.3s, test 191/191 (184→191, +7)
- **알려진 한계 → v0.6**:
  - Dual-Composer split (cost 큼)
  - Editable diff (SwiftUI native 부재)
  - Terminal block UX (SwiftTerm 한계 → 자체 wrap)
  - Inline mention multi-target
  - PreviewPane dev server auto-detect
  - ACP Spike (2-3일) → 결정
- **재검토**:
  - 사용자 chain 사용 후 — max hops 적정성, banner UX, 안전 토글 default 유지 여부
  - 사용자 codex 사용 후 — logger의 unknown type 데이터로 매핑 추가
  - PreviewPane use case 명시 — dev server auto-detect 우선순위

---

## ADR-033 — v0.4 Phase F: GUI 사용성 polish (위임 버튼 + 더블클릭 rename + 가이드 카드) + pane→pane 자동 답장 명시 보류

---

## ADR-033 — v0.4 Phase F: GUI 사용성 polish (위임 버튼 + 더블클릭 rename + 가이드 카드) + pane→pane 자동 답장 명시 보류

- **날짜**: 2026-05-02
- **상태**: Accepted
- **결정**: 시나리오 항목들을 GUI 버튼으로 노출 (G1: Composer 위임 / G2: 더블클릭 rename + Toolbar 가이드 / G3: 시나리오 카드). pane→pane 자동 답장 (F1)은 안전 우선으로 명시 보류
- **컨텍스트**:
  - 사용자 — "사용해 볼 시나리오 항목들을 명령어보다는 gui를 통해 버튼으로 사용성을 쉽게 구현해 주고 후속 작업도 검토해서 진행"
  - ADR-031/032에서 만든 mention/rename/split 등 기능이 키보드/우클릭 의존 → 발견성 약함
  - 새 사용자가 첫 진입 시 "어디에 뭐 있는지" 모름
- **각 결정**:
  1. **Composer 위임 버튼** — `@` 키보드 의존 X, 명시적 GUI 진입점. menu에 모든 mention 후보 표시, 클릭 시 text 앞에 prepend
  2. **Tab 더블클릭 rename** — 우클릭 메뉴 발견 어려움. `simultaneousGesture(TapGesture(count: 2))`로 단일 클릭(select)과 공존
  3. **Toolbar 가이드 버튼** — ⌘/ 단축키 외에 명시 진입점 (`questionmark.circle`)
  4. **ShortcutHelpSheet 시나리오 카드** — 단축키 표만 보여주는 게 아니라 "이 기능 GUI에서 어디?" 8개 카드 (icon + title + howTo)
  5. **EmptyWorkspaceView 강화** — "도움말" 버튼 + quick tip 4개 (split / 위임 / terminal+inspector / 텔레그램+delivery)
  6. **F1 보류** — pane→pane 자동 답장은 v0.5 이후. 사유: 무한 루프 위험, 복잡도, 사용자 control 약화
- **F1 보류 사유 (자세히)**:
  - 가치: agent끼리 자동 협업하면 진정한 multi-agent — 매력적
  - 비용: chain hop counter, 같은 pane 재방문 감지, max hops 정책, UI에 chain visualization, 사용자 cancel 메커니즘
  - 위험: 무한 루프 (max hops로 mitigation 가능하지만 디버깅 어려움)
  - 사용자 control: agent가 사용자 모르게 다른 agent 호출 → 비용/안전 issue
  - 결론: v0.5에서 진행 — 사용자 명시 토글 + max 1 hop default + UI에서 chain 표시
- **격리**: 모든 변경은 UI 모듈만 (Composer / PaneTabBar / ChatToolbar / ShortcutHelpSheet) + AppModel state X (renameSheet은 ADR-032에서 이미 추가). 도메인 변경 없음
- **결과**:
  - Composer +1 메뉴 (delegateMenu)
  - PaneTabBar +simultaneousGesture (rename)
  - ChatToolbar +1 IconButton (도움말)
  - ShortcutHelpSheet +scenariosSection (8 카드, ScenarioEntry struct)
  - EmptyWorkspaceView quick tip 3→4 + 도움말 버튼
  - build 2.8s, test 184/184 (UI 추가만이라 신규 테스트 없음)
- **알려진 한계**:
  - 위임 버튼은 panes가 1개뿐일 때 (mentionSuggestions가 자기 자신만이면) 의미 약함 — 표시는 됨
  - 더블클릭 + 단일 클릭 시 macOS gesture 처리에 따라 가끔 race — 실측 후 조정
  - 가이드 카드는 정적 텍스트 (인터랙티브 튜토리얼 X)
  - F1 보류 — agent 협업의 자동화는 v0.5
- **재검토**: 사용자 사용 후 feedback — "위임 버튼 자주 쓰는지" / "더블클릭 충돌 있는지" / "F1 진짜 원하는지"

---

## ADR-032 — v0.4 Phase E: UX polish 4종 + Split layout

---

## ADR-032 — v0.4 Phase E: UX polish 4종 + Split layout

- **날짜**: 2026-05-02
- **상태**: Accepted
- **결정**: 보류 항목 10개 평가 후 4개 진행 (Mention picker U1 / Assistant 라벨 U2 / Pane rename U3 / Split layout U4). 6개는 defer 사유 명시
- **컨텍스트**:
  - 사용자 — "나머지 라운드도 이어서 진행해 줘"
  - 보류 항목 (ADR-031 doc 84): T5/T6/T8 + v0.5 권고 (mention picker / source 라벨 / pane→pane / ACP / editable diff)
  - **냉정한 평가** — 모두 진행은 비효율. 가치 큰 것만 선별
- **각 결정 핵심**:
  1. **U1 Mention picker** — Composer `@`로 시작하면 자동 popover. customName + shortLabel 모두 후보. 사용성 임팩트 큼 (mention 학습 비용 ↓)
  2. **U2 Assistant 라벨** — MessageBubble에 `assistantLabel` param. active pane의 displayName 표시. multi-pane에서 "어느 agent가 말하는지" 명확
  3. **U3 Rename + promote** — context menu에서 rename / primary promote. 사용자가 "Claude (설계)" "Codex (구현)" 같은 의미 있는 이름 부여 가능. mention picker 후보로도 등장
  4. **U4 Split layout (단순화)** — `PaneSplitMode { single, horizontal, vertical }`. secondary는 read-only (Composer 없음, 활성화 버튼). 진짜 dual-Composer는 v0.5 (사용성 검증 후)
- **단순화 결정 (U4)**:
  - 원안: 좌/우 동시 Composer + 각자 messages 입력
  - 현실: SwiftUI focus management 복잡 + Composer 자체가 큰 컴포넌트 + per-side 설정 picker
  - **단순화**: secondary는 read-only chat + 활성화 버튼. 사용자가 클릭하면 active 전환 (bounce). dual-Composer는 v0.5 사용성 검증 후
- **defer 항목 사유**:
  - T5 per-pane settings: tab swap이 동일 효과, 가치 < 비용
  - T6 PreviewPane: use case 명시 (web 개발 등) 시 진행
  - T8 Block UX (Warp): terminal 사용 빈도 데이터 필요
  - pane→pane 자동 답장: 무한 루프 위험, v0.5 안전 토글로
  - ACP Spike: Swift SDK 부재, 외부 생태계 성장 의존, v0.5 별도
  - Editable diff (Cline SOTA): SwiftUI native diff editor 부재, 비용 prohibitive (~3-5인일)
- **격리**:
  - PaneSplitMode는 YuminaiCore (UI 모듈에서 binding)
  - MentionSuggestion은 YuminaiUI (Composer만 의존)
  - PaneRenameSheet/SecondaryPaneView는 YuminaiApp (AppModel + UI 모두 import)
- **결과**:
  - 신규 파일 3개: PaneSplitMode / PaneRenameSheet / SecondaryPaneView
  - Composer +2 (MentionSuggestion + popover)
  - MessageBubble/AssistantMessageBlock/ChatView +1 param
  - PaneTabBar +context menu + split mode picker
  - AppModel +promotePaneToPrimary + renameSheetPane + paneSplitMode
  - RootView mentionSuggestions computed + chatArea split
  - 3 신규 테스트 (PaneSplitMode)
  - build 3.7s, test 184/184 (181→184, +3)
- **알려진 한계 → 후속 (v0.5)**:
  - Split secondary read-only (dual-Composer = v0.5)
  - per-pane delivery config X
  - Mention picker leading `@`만 (중간 mention X)
  - Codex JSONL 실측 정밀화 (사용자 사용 후 데이터)
  - pane→pane 자동 답장 (안전 토글)
  - ACP Swift SDK Spike
  - Editable diff (Cline SOTA)
- **재검토**: 사용자 multi-pane + split 사용 후 — dual-Composer 필요성 / pane→pane 자동 답장 / per-pane settings 가치 재평가

---

## ADR-031 — v0.4 Phase D: Panes 영속 (T1) + 인터-에이전트 메시지 (T2) + Codex schema 정밀화 (T3)

---

## ADR-031 — v0.4 Phase D: Panes 영속 (T1) + 인터-에이전트 메시지 (T2) + Codex schema 정밀화 (T3)

- **날짜**: 2026-05-02
- **상태**: Accepted
- **결정**: ADR-027 권고 5개 phase 중 가치/비용 평가 후 가치 큰 3개 선별 — Panes 영속 + `@codex` mention dispatch + Codex schema 안전 추가. 나머지 5개(T4-T8)는 사용자 트리거 시 진행
- **컨텍스트**:
  - 사용자 — "남은 권고 순서 하나하나 상세하게 기획하고 냉정하게 사용성과 단위 기능 검토해 가면서 구현"
  - Phase A/B/C 완료 후 권고는 split layout / per-pane 설정 / PreviewPane / 인터-에이전트 / Codex 정밀화 등
  - **냉정한 평가** — 권고 모두 진행은 비효율. 가치 큰 것만 선별
- **평가 매트릭스** (`docs/design/84_REMAINING_PHASES_EVALUATION.md`):
  | 항목 | 가치 | 비용 | 사용성 | 결정 |
  |------|-----|------|------|------|
  | T1 panes 영속 | 높음 | 작음 | 높음 | ✅ |
  | T2 mention dispatch | 높음 | 보통 | 높음 | ✅ |
  | T3 codex schema | 보통 | 작음 | 보통 | ✅ |
  | T4 split layout | 보통 | 큼 | 모호 | ⏸ |
  | T5 per-pane settings | 낮음 | 보통 | 낮음 | ⏸ |
  | T6 PreviewPane | 보통 | 보통 | 모호 | ⏸ |
  | T7 reorder/rename | 낮음 | 작음 | 낮음 | ⏸ |
  | T8 Block UX | 보통 | 보통 | 보통 | ⏸ |
- **각 결정**:
  1. **T1: Workspace.savedPanes 영속** — SwiftData JSON column (deliveryConfigJSON 패턴 재사용). session/messages는 영속 X (메타만). claude session resume으로 컨텍스트 자동 복원
  2. **T2 mention syntax `@<agent>`** — Telegram 표준 친숙. 우선순위 매칭 (customName 정확 → 부분 → agentKind → @me). 매칭 실패 시 안내, 일반 send fallback X (의도 보존)
  3. **T2 dispatch는 "사용자 응답"** — pane → pane 답장 자동 새 turn은 무한 루프 위험. v0.5 검토. 현재는 pane 활성화 + 사용자 메시지 전송
  4. **T3 명시적 무시 type 추가** — thinking/reasoning은 노이즈 (verbose 모드 토글 v0.5)
  5. **T3 error 이벤트 forward** — silent drop 위험, toolResult로 표시
  6. **T4-T8 보류** — defer 사유 명시 (사용자 트리거 조건 포함). plan에 보존, 잊지 않게
- **대안 분석**:
  - **panes 영속 vs ephemeral**: 영속 채택. 사용자가 만든 panes 잃는 것 X (워크스페이스 단위 의도 명시)
  - **mention auto-complete picker** vs **manual syntax**: picker는 v0.5. manual은 학습 비용 있지만 Telegram 표준이라 자연스러움. placeholder + i 도움말로 보조
  - **dispatch가 자동 새 turn 트리거** vs **사용자 응답만**: 전자는 자동 협업이지만 무한 루프. 후자는 안전. v0.5에서 명시적 토글 추가 검토
- **격리**:
  - MentionParser는 YuminaiCore (모든 모듈 사용 가능)
  - panesJSON은 WorkspaceModel (SwiftData column)
  - dispatch 로직은 AppModel (pane state + sendMessage 호출)
- **결과**:
  - 신규 파일 1개: MentionParser.swift
  - Workspace +1 필드 (savedPanes) + with(savedPanes:)
  - WorkspaceModel +1 column (panesJSON, nullable, 호환)
  - AppModel +3 메서드 (resolveMentionTarget / tryDispatchMention / persistCurrentPanes)
  - AppModel persist 자동: addPane / removePane / renamePane / ensurePrimaryPane
  - Composer placeholder + Composer onSend (mention 우선) + Telegram router (mention pass-through)
  - LiveCodexAdapter +12 type alias + thinking 무시 + error forward
  - 20 신규 테스트
  - build 3.5s, test 181/181 (161→181, +20)
- **알려진 한계**:
  - panes 영속하지만 messages는 fresh (claude resume에 의존)
  - mention picker (자동완성) X
  - pane → pane 답장 자동 새 turn X (안전 우선)
  - ChatView에 source/target 시각 표시 X (tab으로만 구분)
  - per-pane delivery config X (workspace 단위)
- **재검토**:
  - T4-T8 사용자 트리거 조건 (split, PreviewPane, Block UX, reorder)
  - mention picker 필요성 (사용 빈도 보고)
  - Codex JSONL 실제 사용 데이터로 unknown type 추가 매핑

---

## ADR-030 — v0.4 Phase C: Multi-pane Foundation (M1)

---

## ADR-030 — v0.4 Phase C: Multi-pane Foundation (M1)

- **날짜**: 2026-05-02
- **상태**: Accepted (Phase C foundation, split layout/per-pane controls는 후속)
- **결정**: 워크스페이스에 N개의 AgentPane 도입. 각 pane은 자체 session/messages/settings/usage. UI는 tab bar로 빠른 전환 (split layout은 후속). 1순위 reference: AutoGen AgentTool + Aider Architect/Editor 2-LLM
- **컨텍스트**:
  - 사용자 — "다음 권고 사항 이어서 진행해 줘"
  - ADR-027 권고 phase 순서: M3→M5→M4→M1→M2 — M1 (multi-pane) 차례
  - 1ws-1agent → 1ws-Nagent 진화 — Yuminai의 가장 큰 architectural change
- **각 결정**:
  1. **AgentPane domain은 Core** — 모든 모듈이 의존 가능 (UI, Telegram, App)
  2. **PaneRole 2종 (primary/secondary)** — primary는 Telegram bridge target. 워크스페이스당 1개. 인터-에이전트 메시지(M2 후속)에서는 다른 의미로 확장 가능
  3. **workspace 단위로 panes 관리** — `[UUID: AgentPane]` workspace.id key 매핑은 X. workspace 전환 시 panes 새로 생성/clear (같은 workspace 다시 들어가면 panes 잃음 — v0.5에서 영속 검토)
  4. **tab swap 패턴** — 한 시점에 1 pane visible (split layout은 후속). 전환 시 messages/session/settings/usage 모두 swap. session은 lazy spawn (첫 활성 시)
  5. **마지막 pane close 불가** — 워크스페이스에 항상 ≥1 pane. UX 단순화
  6. **session lifecycle은 pane이 소유** — pane remove 시 자체 session terminate. 기존 currentClaudeSession은 active pane의 session alias
  7. **AppModel 기존 alias 유지** — `messages` / `currentClaudeSession` / `activeSettings` / `currentSessionUsage` 모두 그대로. backward-compat 위해 active pane의 state로 swap (refactor 부담 ↓)
- **대안 분석**:
  - **워크스페이스 영속 panes** vs **세션 영속 panes**: 영속이면 workspace 다시 들어가도 같은 panes — 그러나 SwiftData 영속 비용 + session 복원 복잡 (claude session id resume). v0.4는 메모리만, v0.5에서 영속 검토
  - **tab vs split UI**: split이 power user UX 우월 but SwiftUI에서 dynamic split 비용 큼. tab 먼저, split는 사용자 검증 후 후속
  - **AppModel refactor strategy**: full alias getter (computed property)로 모든 기존 코드 호환 vs 새 메서드 추가 + 점진적 migration. 후자 채택 — 위험 분산, 점진적 검증 가능
  - **session 즉시 spawn vs lazy spawn**: 즉시는 새 pane 추가 시 비용 ↑ + 사용자가 그 pane 안 쓸 수도. lazy는 setActivePane이 처리 — 자연스러움
- **격리**:
  - AgentPane은 YuminaiCore (모든 모듈 import 가능)
  - PaneTabBar는 YuminaiUI (도메인 모델만 의존, callback 4개)
  - paneSessions는 AppModel private (Sendable 경계 안전)
- **결과**:
  - 신규 파일 2개: AgentPane.swift / PaneTabBar.swift
  - AppModel +6 properties + 5 actions (ensurePrimaryPane / setActivePane / addPane / removePane / renamePane + clearPaneState)
  - RootView chat 영역 상단에 PaneTabBar 통합
  - teardownCurrentSession 확장 (모든 panes 정리)
  - 9 신규 테스트 (defaults / displayName / immutable updates / Codable)
  - build 3s, test 161/161
- **알려진 한계 → 후속 phase**:
  - **Phase C2/C3/C4**: 좌/우 split layout / per-pane Composer 설정 / pane drag-reorder / pane settings sheet (rename/role)
  - **Phase D (M2)**: 인터-에이전트 메시지 (`@codex` mention) — MetaGPT 메시지 환경 + AutoGen GroupChat
  - panes 영속 X (워크스페이스 다시 들어가면 새 primary 1개)
  - per-pane delivery config X — workspace 전체 1개
  - per-pane usage 누적은 메모리만 (SwiftData 저장 X)
- **재검토**: 사용자 multi-pane 사용 후 — split layout 필요성, panes 영속 필요성, per-pane 설정 분리 필요성

---

## ADR-029 — v0.4 Phase B: Delivery Loop (M4) + UI 도움말 일괄 적용

---

## ADR-029 — v0.4 Phase B: Delivery Loop (M4) + UI 도움말 일괄 적용

- **날짜**: 2026-05-01
- **상태**: Accepted (구현 완료, Phase B)
- **결정**: M4 (Aider auto-test + Devin step budget) 채택 + UI 사용성 개선을 위한 HelpHint 컴포넌트 일괄 도입. M5.b (Warp block UX)는 Phase B 시간 제약으로 v0.4 후속에 보류
- **컨텍스트**:
  - 사용자 — "페이즈 b 시작하고 사용성에 대해 안내 도움말은 i 아이콘이나 간단한 건 상시로 보여지게"
  - 두 요청 동시 — UI 도움말은 신규 UI에 활용되므로 Phase B 신규 컴포넌트(WorkspaceDeliverySheet, DeliveryResultsView)에 즉시 적용
- **각 결정**:
  1. **HelpHint 4종 컴포넌트** — `HelpHint`(i+popover) + `InlineHint`(상시) + `EmptyStateHint`(빈 영역) + `LabelWithHint`(LabeledContent inline). 사용처별 패턴 분리로 일관성 + 재사용
  2. **Aider auto-test 패턴 채택** — test → lint 순서, 실패 시 lint skip. Aider 검증된 default
  3. **Devin step budget hard cap** — maxAttempts (default 3), timeout (default 300초). 무한 루프 방지 정석. mini-SWE-agent 100 LoC 단순함 증거 (Princeton NeurIPS 2024)
  4. **소극적 fix loop** — 실패 결과는 다음 사용자 메시지 앞에 prepend만. 즉시 새 turn 자동 spawn은 X (사용자 control 우선, v0.5에서 적극적 mode 검토)
  5. **빌드는 수동만** — 빌드는 보통 오래 걸리므로 turn 완료 자동 trigger 부적합. test/lint만 자동
  6. **`/bin/zsh -lc`로 실행** — 사용자 login shell config 그대로 (PATH, env). 의존성 안 깨짐
  7. **JSON 직렬화로 SwiftData 저장** — DeliveryConfig를 nullable `Data?` 컬럼에 JSON. nil → .disabled fallback (기존 워크스페이스 호환)
  8. **결과는 메모리 전용 (max 10개)** — 영속 X. 사용자가 누적 history 필요시 v0.5
- **대안 분석**:
  - **즉시 새 turn 자동 spawn** vs **소극적 prepend**: 자동 spawn은 sweep AI 패턴이지만 사용자 control 약함, agent를 무시할 수 없음. 소극적은 안전 + 사용자가 실패 결과 보고 결정 가능 → 후자 채택 (v0.5에서 적극적 mode 토글 추가 검토)
  - **Docker runtime 격리** vs **NSTask shell**: Docker는 OpenHands급 격리 but 사용자 부담 ↑, Yuminai macOS native 정체성과 충돌 → NSTask + sandboxed dir
  - **자체 ANSI parser + capture** vs **shell 그대로 + readability handler**: shell 그대로가 사용자 환경 일치. ANSI는 결과 표시에서만 처리 (현재는 raw text)
- **격리**:
  - DeliveryConfig는 `YuminaiCore` (모든 모듈 접근 가능)
  - DeliveryRunner는 `YuminaiApp` (AppModel hook과 강결합)
  - DeliveryResultsView는 `YuminaiUI` (도메인 모델만 의존)
  - WorkspaceDeliverySheet은 `YuminaiApp` (AppModel + UI 둘 다 import)
- **HelpHint 디자인 결정**:
  - i 아이콘은 11pt, 대기 색은 textTertiary, 활성/호버는 accent
  - InlineHint는 4 kind: info(accent) / success(green) / warning(orange) / tip(accent) — bg는 각 색 10~12%
  - EmptyStateHint는 28pt icon + title body + optional action button. 모든 빈 상태 영역에 일관 적용
  - LabelWithHint는 Settings의 LabeledContent와 자연스럽게 — Toggle/Stepper 라벨 옆에 inline
- **결과**:
  - 신규 파일 5개: HelpHint / DeliveryConfig / DeliveryRunner / DeliveryResultsView / WorkspaceDeliverySheet
  - 신규 테스트 8건 (DeliveryConfig 3 + DeliveryResult prompt 5)
  - InspectorPanel "변경" 탭이 VSplitView로 diff 위 / delivery results 아래 분할
  - SidebarView 우클릭 메뉴 "Delivery 자동화 설정…" 추가
  - SwiftData migration: deliveryConfigJSON nullable column (nil fallback)
  - build 3.2s + 152/152 tests
- **알려진 한계 → 후속**:
  - test/lint 순서 고정 (커스텀 X) — v0.5
  - 자동 fix loop는 소극적 (즉시 spawn X) — v0.5에서 적극적 mode 토글
  - 결과 영속 X (메모리 max 10) — v0.5에서 SwiftData 저장 검토
  - Block 그룹화 (Warp UX) — v0.4 후속 또는 v0.5
  - Telegram에 delivery 결과는 단순 알림만 — 자동 fix 진행 알림은 v0.5
- **재검토**: Phase C (multi-pane) 시작 전 사용자 검증 — auto-fix prepend가 자연스러운지, hard cap이 충분한지

---

## ADR-028 — v0.4 Phase A: Diff Review (M3) + Embedded Terminal (M5.a)

---

## ADR-028 — v0.4 Phase A: Diff Review (M3) + Embedded Terminal (M5.a)

- **날짜**: 2026-05-01
- **상태**: Accepted (구현 완료, Phase A)
- **결정**: ADR-027 권고 default 7개 모두 채택 후 Phase A 구현. M3 + M5.a를 한 commit으로 통합 (작업이 같은 라운드 + UI 영역 공유).
- **컨텍스트**:
  - 사용자 — "권고 사항 기준으로 구현 진행해 줘"
  - ADR-027의 권고 default 7개 모두 OK (split UI / manual accept / 자동 + hard cap / SwiftTerm OK / @codex syntax / phase 순서 / ACP v0.5 spike)
- **각 결정**:
  1. **SwiftTerm 채택 (M5.a)** — Miguel de Icaza의 검증된 native Swift terminal. 두 번째 외부 dep (첫째: swift-markdown-ui). lock-in 완화는 TerminalPane wrapping으로
  2. **git-as-source (M3)** — Aider 패턴 그대로. 자체 diff 모델 X, git status/diff/checkout/clean을 단일 진실의 원천으로
  3. **manual accept** — 사용자 권고. 자동 commit/reject 모두 X. UI에서 명시적 클릭만
  4. **silent no-op for non-git workspaces** — git 저장소 아니면 checkpoint skip (panic X). 사용자에게 "이 워크스페이스는 git이 없어서 변경 추적 안 됨" 안내는 v0.5 (현재는 변경 탭이 빈 상태로만 표시)
  5. **VSplitView로 chat/terminal 분할** — macOS native split view 사용 (NSSplitView wrap). 좌/우 split (M1.b)는 다른 phase
  6. **InspectorTab .changes 추가** — 기존 컨텍스트/노트 옆에 자연스럽게. badge X (현재는 단순)
- **대안 분석**:
  - **자체 diff 모델** vs **git-as-source**: 자체 모델은 history 추적 자유도 ↑ but 복잡도 ↑↑. git은 이미 모든 사용자가 익숙 + 이미 워크스페이스에 있음 → git 채택
  - **xterm.js + WKWebView** vs **SwiftTerm**: web view는 무겁고 native UX 약함. SwiftTerm 검증됨 + macOS native
  - **자동 turn-단위 commit** vs **manual accept**: 자동은 noise ↑ + revert 어려움. 사용자가 명시적으로 결정하는 게 안전
- **격리**:
  - `GitRunner`는 `YuminaiCore` (모든 모듈 사용 가능)
  - `CheckpointManager`는 `YuminaiApp` (AppModel 의존)
  - `TerminalPane`은 `YuminaiUI` (SwiftTerm wrap)
  - `DiffReviewView`는 `YuminaiUI` (도메인 모델 `ChangedFile`만 의존)
- **결과**:
  - 신규 파일 4개: TerminalPane / GitRunner / CheckpointManager / DiffView
  - 신규 테스트 17건 (porcelain 6 + mock 1 + line kind 6 + extract hunks 4)
  - InspectorTab .changes / AppModel +5 properties + 4 actions
  - SwiftTerm 외부 dep
  - build 22s (SwiftTerm 첫 resolve 후) + 4-9s incremental, 144/144 tests
- **알려진 한계 → 후속 phase**:
  - Editable diff X (Cline SOTA, v0.5 — SwiftUI native diff editor 부재)
  - 자동 commit X (manual policy, hybrid v0.5)
  - Block 그룹화 X (Warp UX) — Phase B (M5.b)
  - Diff path 매칭에 한글/공백 정밀도 약함 — 실측 후 정밀화
  - 일반 dir file watcher X — turn 종료 시 git status 1회로 충분, watcher는 v0.5
- **재검토**: Phase B (M4 delivery loop) 시작 전 Phase A 사용자 검증 결과 반영

---

## ADR-027 — v0.4 라운드 기획 + GitHub 최상위 스타 레퍼런스 근거 채택

---

## ADR-027 — v0.4 라운드 기획 + GitHub 최상위 스타 레퍼런스 근거 채택

- **날짜**: 2026-05-01
- **상태**: Accepted (planning) — 구현 시 phase별 별도 ADR-028~031로 세부 결정
- **결정**: v0.4 라운드를 5개 주제 (M1 멀티에이전트 패널 / M2 인터-에이전트 메시지 / M3 diff review / M4 delivery loop / M5 embedded terminal-preview)로 정의. 각 주제는 GitHub 최상위 스타 OSS 패턴을 1차 근거로 채택. Phase 분할 (A→B→C→D→E)로 순차 commit
- **컨텍스트**:
  - 사용자 — "다음 라운드 각 항목 효율성을 고려해서 기획하고 설계 진행해 줘. 깃허브 최상위 스타 래퍼지토리를 근거와 래퍼런스로 조사하고 기획에 반영해 줘"
  - codex 식별 5 거대 gap + ADR-026 1단계 후속(인터-에이전트 메시지)
  - 자체 발명 X — 검증된 패턴만 차용
- **리서치 방법**:
  - research-analyst agent (background) — `gh` CLI로 23개 OSS 메타데이터 + README 분석
  - 카테고리: 멀티 에이전트 프레임워크 / AI 코딩 어시스턴트 / Diff review / Delivery loop / Terminal-Preview
  - 결과: `docs/research/01_NEXT_ROUND_REFERENCES.md` (270 lines, 1.1M+ stars 합계)
- **주제별 1순위 reference + 차용**:
  | M | 주제 | 1순위 ref (stars) | 핵심 차용 |
  |---|------|------------------|----------|
  | M1 | 멀티 에이전트 패널 | AutoGen AgentTool (57.6k) + Aider Architect/Editor (44.2k) | 메인 agent가 보조를 tool로 호출 + 좌/우 split UI |
  | M2 | 인터-에이전트 메시지 | MetaGPT 메시지 환경 (67.6k) | publish/subscribe bus + `@codex` mention |
  | M3 | Diff review | Cline checkpoint (61.2k) + Aider git-as-source (44.2k) | git이 단일 진실의 원천, view-only diff (editable v0.5) |
  | M4 | Delivery loop | Aider --auto-test (44.2k) + Devin step budget | 단순 retry counter, max-attempts=3, max-time=5min hard cap |
  | M5 | Terminal/Preview | SwiftTerm (Miguel de Icaza) + Warp block UX (50.8k) | macOS native PTY + block-단위 output |
- **핵심 의사결정 근거 (evidence)**:
  - **AutoGen은 maintenance mode** (Microsoft Agent Framework 후속) → 코드 의존 X, 패턴만 차용
  - **Aider 내부에 이미 Architect/Editor 2-LLM** (`aider/coders/architect_coder.py`) 검증됨 → Yuminai의 1ws-1agent → 2-역할 진화가 자연스러움
  - **mini-SWE-agent 100 LoC로 SWE-bench 65%** → "loop은 단순할수록 좋다"는 강한 증거. graph framework 없이 retry counter+budget으로 충분
  - **Cline editable diff가 SOTA지만 SwiftUI 자체 구현 비용 큼** → v0.4는 view-only, editable v0.5
  - **ACP (Agent Client Protocol) 부상** (3.0k stars but Zed push, obsidian-agent-client 1.9k 인접 use case) — Yuminai의 정확한 표준 후보지만 Swift SDK 부재 → v0.5 별도 spike
- **횡단 결정**:
  - **외부 의존성 정책 변경** — SwiftTerm 추가 (두 번째 외부 dep, 첫째: swift-markdown-ui). M5 phase 시작 시 ADR-031로 세부 명시
  - **Runtime sandbox**: Docker X, NSTask + sandboxed dir (macOS native 정체성 우선)
  - **AutoGen 코드 의존**: X (maint mode), 패턴만
- **Phase 순서** (의존성 + 가치 기반):
  - A (M3 + M5.a): Diff review + 기본 terminal — 가장 가치 + 단순
  - B (M4 + M5.b): Delivery loop + Warp block — A 의존
  - C (M1.a + M1.b): Multi-pane foundation + split — 가장 큰 변경
  - D (M2): Inter-agent message — C 후 자연스러움
  - E (M5.c + Codex schema): Preview + Codex 정밀화 — 마무리
- **결과**:
  - `docs/design/83_NEXT_ROUND_PLAN.md` (440+ lines, evidence-based)
  - `docs/research/01_NEXT_ROUND_REFERENCES.md` (270 lines, 23 OSS)
  - 5 phase, 11-15 commits 예상, 4-6주 작업
  - ADR-028 ~ 031 phase별 추가 예정
- **Open Questions** (사용자 답변 시 plan 업데이트):
  - Q1 split vs tab 우선? (권고: split)
  - Q2 diff accept policy? (권고: manual, hybrid v0.5)
  - Q3 delivery loop trigger? (권고: 자동 + hard cap)
  - Q4 SwiftTerm 외부 dep OK? (권고: OK)
  - Q5 mention syntax? (권고: `@codex`)
  - Q6 phase 순서? (권고: M3→M5→M4→M1→M2)
  - Q7 ACP 채택 검토? (권고: v0.5 별도 spike)
- **Risks**:
  - Phase C (multi-pane) AppModel 대규모 refactor — 일정 초과 가능, split commit으로 위험 분산
  - SwiftTerm + Yuminai 통합 사전 사례 부족 — 1-2일 spike 권장
  - Telegram bridge ↔ multi-pane 상호작용 (primary만 forward로 단순화)
- **재검토**: 사용자 Open Questions 답변 후 → ADR-028 (Phase A 시작 시) 작성

---

## ADR-026 — 멀티 에이전트 기반 + Codex CLI 통합 + cokacdir chat 라벨

- **날짜**: 2026-05-01
- **상태**: Accepted (1단계)
- **결정**: AgentKind enum (claude/codex) 도입 + workspace 단위 에이전트 전환 + Codex CLI 어댑터 추가 + cokacdir chat label 친화 표시. Antigravity-style 멀티 에이전트 협업의 1단계 — 같은 프로젝트 폴더에서 두 에이전트가 file system 공유로 협업 가능. 멀티 패널 + 인터-에이전트 메시지 패싱은 v0.4
- **컨텍스트**:
  - 사용자 3가지 동시 요청 — 각각 독립 ADR로 분리할 수도 있지만 핵심이 "1 워크스페이스 多 에이전트"라는 한 흐름이라 통합
  - 1: chat id가 숫자여서 그룹/개인 구분 어려움 (UX)
  - 2: codex CLI 연결
  - 3: 안티그래비티처럼 한 컨텍스트·폴더에서 여러 에이전트 협업
- **각 결정**:
  1. **chat label**: cokacdir 자체가 `~/.cokacdir/group_chat/<chat_id>.jsonl`에 메시지 로그 저장. 거기서 bot_display_name + from 추출 → "그룹 — 🤖 Bot Alpha, 🤖 Bot Beta, 홍길동" 같은 친화 라벨 생성. Telegram getChat API 호출 회피 (토큰 사용 X, network X, 이미 있는 데이터 활용)
  2. **Codex 어댑터**: `codex exec --json` + `codex exec resume <id>` 모델 — Claude와 달리 turn마다 새 프로세스. session id 자동 추출 + 다음 send에서 resume으로 컨텍스트 유지
  3. **AgentKind 단계적 도입**: 워크스페이스 단위 1 에이전트 (1단계) → 멀티 패널 (2단계) → 인터-에이전트 메시지 (3단계). 1단계에서도 같은 workspace 폴더 공유로 "유기적 협업" 가능 (사용자가 빠르게 전환하면서 두 에이전트 능력 결합)
- **대안 분석**:
  - Codex CLI 위임 X → Anthropic SDK처럼 OpenAI SDK 직접 호출: ROI 낮음, 학습 곡선, codex가 이미 잘 만들어진 도구
  - 멀티 패널 즉시 구현 → 큰 작업 (UI 분할, 동시 streaming, focus 관리), 1단계로 분리해 사용자 검증 후 진행
  - chat label에 Telegram getChat API 호출 → 토큰 필요 + network IO + 새 의존성. 이미 가진 cokacdir 로그가 더 풍부 (참여자 + 봇 정보)
- **AgentAdapter 설계**:
  - `ClaudeAdapter` protocol을 그대로 재사용 — Codex도 같은 시그니처 (spawn/terminate/updateSettings/currentSettings) 구현
  - 이름은 `ClaudeAdapter`로 유지 (역사적 이유 + 변경 비용) — 사실상 "AgentAdapter" 의미
  - `LiveCodexStreamSession`이 `ClaudeStreamSession` 프로토콜 구현 — events 스트림 + send
  - 차이점은 내부에서 흡수: events 스트림은 multi-turn 동안 유지, send마다 새 프로세스 spawn
- **Codex JSONL 파싱**:
  - schema가 향후 변경될 수 있어 defensive — 알려진 type만 정확히 매핑, 알 수 없는 type은 raw text로 forward (silent drop X — 사용자가 디버깅 가능)
  - JSON parse 실패 시 raw line을 .text로 emit
  - session_id 추출은 여러 key 후보 시도 (session_id / sessionId / id, nested session.id 등)
- **격리**:
  - `AgentKind`는 YuminaiCore — 모든 모듈이 의존 가능
  - `LiveCodexAdapter`는 YuminaiClaudeAdapter 모듈 (이름은 ClaudeAdapter지만 역할은 모든 agent CLI 어댑터)
  - SettingsView는 codex 경로 input + 감지 상태만 — UI는 Telegram 모듈 의존 없음
- **결과**:
  - 신규: AgentKind.swift / LiveCodexAdapter.swift / CokacdirChatInspector + Label / 18 신규 테스트
  - 확장: Workspace.agentKind / WorkspaceModel.agentKindRaw / AppPreferences.codexBinaryPath / AppModel multi-adapter dispatch / ChatToolbar agent picker / SettingsView Codex CLI section / CokacdirImportSheet ChatRow UI
- **알려진 한계 / v0.4 작업**:
  - 워크스페이스당 1 에이전트만 활성 (멀티 패널 X)
  - 인터-에이전트 메시지 패싱 X (cokacdir의 `--message --to <bot>` 같은)
  - Codex 출력 schema 검증 안 됨 (실제 codex 사용해서 unknown type 정확한 매핑 필요)
  - Codex model alias가 Claude와 달라 SessionSettings.model을 codex에 그대로 넘기지 않음 — codex는 자체 default
  - ChatView에 어떤 agent의 응답인지 메타데이터 표시 안 함
  - Workspace SwiftData 마이그레이션은 nil fallback으로 처리 — 명시적 versioned migration 안 함
- **재검토**: 사용자 codex 테스트 후 — JSONL schema 정확도, 전환 UX, multi-pane 필요성

---


> 큰 결정만 기록. 형식: 결정 / 컨텍스트 / 대안 / 근거 / 결과 / 재검토 시점.

---

## ADR-025 — 텔레그램 단일 세션 bind + ClaudeEvent forwarding bridge

- **날짜**: 2026-05-01
- **상태**: Accepted
- **결정**: 워크스페이스 1개를 텔레그램 챗에 1:1 bind. `TelegramSessionBridge` actor가 ClaudeEvent를 chunked Telegram 메시지로 변환해 forwarding. 명령(`/bind`, `/unbind`, `/status`, `/cancel`, `/list`, `/help`)은 `YuminaiCommandRouter`가 처리, 일반 텍스트는 bound 세션의 input으로 전송
- **컨텍스트**:
  - 사용자 — "하나의 세션을 탤래그램에서 제어할 수 있도록 설계해 줘"
  - 기존 인프라: `TelegramAlertDispatcher`(outgoing 정책 알림) + `TelegramCommandPump`(incoming pump) + `YuminaiCommandRouter`(현재 활성 워크스페이스로 단순 라우팅)
  - 부족: bound 세션 개념 X, Claude 응답이 텔레그램으로 안 돌아감, 명령 X
- **대안**:
  - 활성 워크스페이스로 라우팅 (현재 동작) → 사용자가 UI에서 워크스페이스 바꾸면 텔레그램 동작도 따라 바뀜 — 의도 안 맞음
  - 멀티 bind (n 워크스페이스 ↔ n 챗) → 복잡도 ↑, 사용자 1명 본인 사용 시 단일 chat이 자연스러움
  - **단일 bind (채택)** — preference에 `telegramBoundWorkspaceId: UUID?` 1개. UI 활성 워크스페이스와 분리. ✈ 아이콘으로 표시
- **Bridge 설계**:
  - 별도 actor — AppModel(MainActor)에서 분리해 telegram I/O를 background로
  - ClaudeEvent를 받아서 Telegram-친화 텍스트로 변환 (forwarding policy는 Bridge 내부)
  - text event는 buffer에 누적 → debounce(800ms) 또는 chunk size(3500) 초과 시 flush — Telegram rate limit + 4096자 한도 회피
  - tool call은 즉시 + 한 줄 요약 (`🔧 name — input 첫 줄 (80자 cap)`) — 본문 전체는 토큰 폭증
  - completed에서 elapsed + tool count로 한 줄 요약
- **AppModel hook**:
  - `handle(_ event:)`에 `forwardToBridgeIfBound(event)` 한 줄 추가 — 활성 워크스페이스 == bound일 때만 forwarding (UI에서 다른 워크스페이스 선택 시 텔레그램에 가면 혼란)
  - `sendMessage()`가 bound 워크스페이스에서 호출되면 `notifyTurnStart(userText:)` — 텔레그램이 누가 어떤 명령을 보냈는지 추적 가능
  - `bindTelegramWorkspace(_:)`이 bridge를 reset + 재구성 + 알림 — preference 변경 시 즉시 반영
- **명령 vs plain text 분기**: prefix `/`가 명령. 그 외는 bound 세션 입력. 이유:
  - 명령은 슬래시 — Telegram 표준 (BotFather, 다른 봇과 일관)
  - plain text가 일반 prompt가 되어야 자연스러움 (모바일에서 빠른 명령)
  - bound 안 됐을 때 plain text → 안내 메시지 ("먼저 /bind 하세요")
- **자동 워크스페이스 전환**: bound 세션과 활성 워크스페이스가 다를 때 plain text가 오면 자동으로 bound로 전환. 사용자 UI 작업과 충돌하면 텔레그램 우선 — bound는 사용자가 명시적으로 한 결정이므로
- **격리**: `TelegramSessionBridge`는 `TelegramClient` 프로토콜과 `ClaudeEvent` enum만 의존. AppModel 내부 X — 테스트 가능 (MockTelegramBot 사용)
- **결과**:
  - `Sources/YuminaiTelegram/TelegramSessionBridge.swift` (actor + Configuration + chunking + tool summarize)
  - `Sources/YuminaiApp/YuminaiCommandRouter.swift` 전면 재작성 (명령 분기)
  - `AppPreferences +3` 필드 (boundWorkspaceId / forwardAssistant / forwardToolCalls)
  - `AppModel` bridge 라이프사이클 + bind 메서드 + status snapshot + cancel
  - `SidebarView` ✈ 아이콘 + 우클릭 메뉴
  - 14 신규 테스트
- **알려진 한계**:
  - 단일 bind (멀티 워크스페이스 ↔ 멀티 챗 X)
  - bridge는 message edit 미사용 — chunk마다 새 메시지 (편집 흐름은 차기 라운드)
  - 도구 결과 본문 forwarding 안 함 (성공/실패만) — Read 결과 같은 거 보고 싶으면 사용자가 Yuminai UI 봐야 함
  - thinking 이벤트 forwarding X
  - Telegram 4초 rate limit 처리 X (debounce가 어느 정도 완화하지만 보장은 X)
  - bound 워크스페이스 삭제 시 자동 unbind 없음 (router가 boundMissing 안내)
- **재검토**: 사용자 모바일 사용 후 — 응답 chunk 빈도, edit 사용으로 진행 중 응답 단일 메시지 갱신 필요성, thinking 표시 여부

---

## ADR-024 — cokacdir bot_settings.json import (LiveTelegramBot 재사용)

- **날짜**: 2026-05-01
- **상태**: Accepted (이전 안 — openclaw 위임 — 폐기 후 재작성)
- **결정**: cokacdir의 `~/.cokacdir/workspace/bot_settings.json`을 읽어 봇 토큰 + chat id를 Yuminai로 import하는 일회성 import 방식. 별도 actor/CLI 위임 없이 기존 `LiveTelegramBot`을 그대로 사용
- **컨텍스트**:
  - 1차 시도: "cocakdir" 오타를 openclaw로 추정 → openclaw 위임 actor (`OpenClawTelegramBot`) 작성 + commit. 사용자 정정: 실제 도구는 [cokacdir](https://cokacdir.cokac.com/) v0.4.63
  - cokacdir = multi-panel terminal file manager + Telegram bot server (`--ccserver <TOKEN>`)
  - `bot_settings.json`에 봇 목록 평문 저장 — display_name / username / token / owner_user_id / last_sessions (chat → workspace path 매핑)
  - cokacdir는 openclaw처럼 message proxy CLI가 아님 — 봇 서버 자체. `--message ... --key <HASH>` 내부 send도 token hash 필요
- **대안 분석**:
  - **CLI 위임** (`cokacdir --message --to <bot> --chat <id> --key <hash>`) → "internal use" 표시 + token hash 계산 필요 + 비공식 인터페이스, 깨질 위험
  - **bot 서버 공유** (Yuminai와 cokacdir이 같은 토큰으로 동시 polling) → Telegram update 분산 (한쪽만 받음), 충돌
  - **bot_settings.json import (채택)** → 일회성, 단순, 기존 LiveTelegramBot 재사용. 토큰 중복 저장 trade-off는 충돌 없는 운용 우선
- **import flow**:
  1. Settings → 텔레그램 → "cokacdir 통합" Section → "열기…" 버튼
  2. AppModel.loadCokacdirBots() → CokacdirImporter.loadBots() → CokacdirImportSheet 표시
  3. 사용자가 봇 + chat id 선택 (suggested chip / 직접 입력)
  4. AppModel.applyCokacdirBot(_:chatId:) → keychain에 토큰 저장 + telegramChatId/AllowedUserIds 자동 + telegramSourceLabel 기록
- **충돌 처리**: 같은 토큰으로 cokacdir 봇 서버가 동시 실행 중이면 polling 분산 → UI footer로 안내 ("Yuminai 사용 중에는 cokacdir의 해당 봇을 잠시 꺼두는 걸 권장")
- **결과**:
  - `CokacdirImporter` (Sendable struct) + `CokacdirBot` Sendable model + `CokacdirImportError`
  - `CokacdirImportSheet` (YuminaiApp 모듈, YuminaiTelegram + YuminaiUI 모두 import) — 봇 라디오 리스트 + chat chip + 직접 입력
  - `AppPreferences.telegramSourceLabel: String?` — "토큰 출처: cokacdir — <display_name>" 표시
  - `AppModel.cokacdirBots / cokacdirImportError / showCokacdirImportSheet` + `loadCokacdirBots / applyCokacdirBot`
  - `SettingsView` Telegram 탭에 새 Section + 충돌 안내 footer
  - 8 신규 테스트 (parse 6 + loadBots 2)
- **격리 결정**: `CokacdirBot`은 YuminaiTelegram public이지만 sheet UI는 YuminaiApp에 둠 (YuminaiUI에 YuminaiTelegram 의존성 추가 회피). YuminaiUI ↔ YuminaiTelegram 사이는 callback `() -> Void`로만 연결
- **이전 안 폐기 근거** (openclaw 위임):
  - 도구 자체가 잘못 식별됨 (openclaw는 사용자 PC에 있긴 하지만 사용자가 의도한 도구 아님)
  - 설령 정확했어도 openclaw `channels list`에 telegram 채널 없음 (`chat: {}`) — 통합 가능 상태가 아니었음
  - cokacdir이 실제로 활성 사용 중인 도구 (workspace 12개 + ai_sessions 9개 + 봇 2개 등록)
- **알려진 한계**:
  - 토큰 중복 저장 (cokacdir + Yuminai keychain) — 보안 위험은 사용자 신뢰 모델에 종속
  - 일회성 import — cokacdir에서 토큰 재발급되면 사용자가 다시 import 필요
  - cokacdir와 동시 실행 시 polling 충돌 — 자동 감지/회피 미구현 (사용자 운용)
  - bot_settings.json 형식 변경에 종속 (방어적 파싱이지만 schema 깨질 수 있음)
- **재검토**: 사용자 사용 후 — 충돌 자동 감지, cokacdir 봇 서버 status 체크 옵션 추가 여부

---

## ADR-023 — Parity Round (B1~B7 + C1~C3)

- **날짜**: 2026-05-01
- **상태**: Accepted
- **결정**: codex가 노트 모듈에 대해 식별한 10개 gap 중 사용성 임팩트가 즉각적인 7개(disambig / 검색 highlight / 임베드 preview / split editor / CRUD / 즐겨찾기·최근 / 캐시) + UX polish 3개(⌘/ 도움말 / vault action bar / quick access)를 한 라운드에 통합 구현. 나머지 5개(pane model / diff review / embedded terminal / software delivery loop / exec env mobility)는 다음 라운드로 명시 보존
- **컨텍스트**:
  - 사용자 — "이 앱의 퀄리티가 클로드코드 이상의 사용성이 됐다고 자신할 때까지 래퍼런스 조사, 검증, 기획, 구현 반복"
  - codex CLI로 본인 자체 review 수행 → 10개 gap 도출 → 우선순위 분류
  - 사용자 명시 7개 노트 기능과 codex 식별 항목이 70% 겹침 → 합집합 = parity round
- **각 결정 핵심**:
  1. **B1 Disambig** — 동명 노트 sheet, 첫 매칭만 잡던 v0.2 한계 해소. case-insensitive 비교
  2. **B2 Highlight** — AttributedString으로 매칭 substring만 accent color + bold (라인 전체 색칠 X)
  3. **B3 임베드 preview** — 본문 첫 5줄만 inline blockquote (full embed는 v0.4) — 가독성 + 토큰 비용 절충
  4. **B4 Split** — 3-way (editor/split/preview), 단순 toggle보다 풍부. enum은 별도 file로 (AppModel에 의존 안 함)
  5. **B5 CRUD + 휴지통** — `.trash/<timestamp>-<filename>`로 이동 (영구 삭제 X) — 실수 복구 가능. Obsidian과 동일한 패턴
  6. **B6 즐겨찾기/최근** — Set<String> + 영속 (UserDefaults), 최근은 10개 LRU. quick access는 sidebar가 아닌 InspectorPanel 노트 탭 상단 (이미 사용자 시선이 있는 곳)
  7. **B7 In-memory cache** — bodyCache(`[String: String]`), watcher 변경 path만 granular invalidate. 영속 인덱스(SQLite FTS / SwiftData FTS5)는 v0.4
  8. **C1 ⌘/ 도움말** — sheet 형태, 카테고리(글로벌/채팅/노트) + ShortcutKeyBadge로 키캡 시각화. command palette는 v0.4
  9. **C2 vault action bar** — 노트 탭 상단에 "+ 새 노트" primary button — discoverability ↑
  10. **C3 quick access** — 빈 상태 메시지 한글 친화 ("아직 즐겨찾기한 노트가 없어요")
- **Actor isolation 해결**:
  - `ObsidianVault.rootURL`이 actor-isolated이면 `MarkdownViewer` (MainActor)에서 wiki link/embed 처리 불가 → `nonisolated let` (immutable이므로 race 무관)
  - `notePreviewBody`는 actor 내부 메서드면 closure에서 `await` 필요 → static + URL 파라미터로 nonisolated 변경. resolver closure는 `{ name in AppModel.notePreviewBody(name: name, vaultRoot: appModel.vaultRootURL) }` — vault root를 외부에서 주입
- **결과**:
  - 신규 파일 5개 (EditorSplitMode/WikiDisambiguationSheet/CreateNoteSheet/ShortcutHelpSheet + ParityRoundTests)
  - InspectorPanel 25+ params로 전면 재작성
  - 86/86 tests (B1 disambig 4건 + B5 CRUD 6건 + B7 cache 3건 + EditorSplitMode 1건 = 14 신규)
- **알려진 한계 (다음 라운드)**:
  - Pane model (사이드 by 사이드 노트/다이얼로그) — codex gap #1
  - Diff review UI (코드 변경 시각화) — codex gap #2
  - Embedded preview/terminal pane — codex gap #3
  - Software delivery loop (build/test/deploy 통합) — codex gap #4
  - Execution env mobility (mobile↔desktop 작업 이전) — codex gap #5
  - 영속 검색 인덱스 (SQLite FTS5) — B7 v0.4
  - frontmatter 인라인 편집 — B4 v0.4 (현재 raw markdown만)
  - 노트 이름 변경 / 폴더 이동 / drag-drop — B5 v0.4
  - Wiki link autocomplete (`[[`치면 popup) — v0.4
- **재검토**: 사용자 1주일 사용 후 feedback / 다음 라운드 시작 전

---

## ADR-001 — SwiftUI 네이티브 채택

- **날짜**: 2026-05-01
- **상태**: Accepted
- **결정**: 데스크탑 앱 UI를 SwiftUI로 구현. Tauri / Electron / 웹 기반 후보 모두 기각.
- **컨텍스트**: 본인 1인 macOS 사용, 출시 계획 없음, Apple Silicon 환경
- **대안**:
  - Tauri 2.x + React + Rust → 작은 번들이지만 macOS 네이티브감 < SwiftUI
  - Electron + React → 무겁고 메모리 큼
  - SwiftUI → 네이티브감 최상, Liquid Glass 등 macOS 26 신기능 활용
- **근거**: 다른 OS 지원 비범위, claude-forge React 자산은 *개발 도구* 자산이지 *데스크탑 앱* 자산이 아님, Swift 학습은 본인에게 자산
- **결과**: Package.swift 셋업, 5개 모듈 정의
- **재검토**: 만약 6개월 후 Apple platform 외 사용자가 필요해지면 재검토 (가능성 낮음)

---

## ADR-002 — A1 (Claude Code CLI Wrapper) 모델 채택

- **날짜**: 2026-05-01
- **상태**: Accepted
- **결정**: Anthropic SDK를 직접 호출하지 않고, `claude` CLI를 자식 프로세스로 spawn해서 추론을 위임한다.
- **컨텍스트**: 본인 1인, Claude Code의 모든 능력(에이전트, MCP, 메모리, 도구)을 그대로 활용하고 싶음
- **대안**:
  - A2 자체 구현: Anthropic API 직접 호출 → 자유도↑, 개발 비용 3-6개월
  - A3 하이브리드: Claude Code + 자체 일부 → 인터페이스 호환 유지 부담
- **근거**: 차별화 포인트는 추론이 아니라 *통합·UX·오케스트레이션*. 추론은 Claude Code에 위임이 ROI 최대.
- **결과**: `YuminaiClaudeAdapter` 모듈 책임이 명확해짐. Anthropic SDK 의존성 추가 금지.
- **리스크**: Claude Code의 stdin/stdout 인터페이스가 brittle할 수 있음 (R2)
- **재검토**: MVP-0 W1 Spike 결과 후 / 6개월 후 자체 구현 타당성 재평가

---

## ADR-003 — App Sandbox OFF

- **날짜**: 2026-05-01
- **상태**: Accepted
- **결정**: macOS App Sandbox를 비활성화한다. Hardened Runtime은 켠 채 일부 entitlement만 추가.
- **컨텍스트**: Process spawn (`claude` CLI), Vault 임의 경로 접근 등이 sandbox와 충돌
- **대안**:
  - Sandbox ON + 임시 예외 (`temporary-exception.unix-process-execution`) → 복잡, 일부 케이스 실패
  - Sandbox ON + UI에서만 통합 → Process spawn 자체가 불가
- **근거**: 본인 빌드 / 본인 사용 → 신뢰 가능. App Store 배포 비범위.
- **결과**: `App/README.md`의 Xcode 셋업 단계에 명시
- **재검토**: 친한 개발자에게 공유 시점

---

## ADR-004 — SwiftData 채택 (vs CoreData / GRDB)

- **날짜**: 2026-05-01
- **상태**: Accepted (MVP-0)
- **결정**: 영속 계층은 SwiftData를 사용한다.
- **컨텍스트**: 메시지 ~10만 개, 워크스페이스 ~10개 규모
- **대안**:
  - CoreData → 더 성숙하지만 boilerplate 많음
  - GRDB.swift → 명시적 제어, FTS 등 기능 풍부, 외부 의존성
- **근거**: SwiftUI와 자연스러움 (`@Query` 등), Swift 6.2 + macOS 26에서 마이그레이션 도구 개선됨, 본인 사용 규모에서 한계 안 만남
- **결과**: `YuminaiPersistence` 모듈에 SwiftData 사용
- **재검토**: 메시지 10만 개 도달 또는 FTS 검색 필요 시 GRDB 평가

---

## ADR-005 — Process Spawn은 PTY 필요 시 SwiftTerm 의존성 검토

- **날짜**: 2026-05-01 (작성) / 2026-05-01 (Spike 종료)
- **상태**: **Superseded by ADR-009** — PTY 불필요 확정
- **결정 (당시)**: 일단 외부 의존성 없이 `Process` + `Pipe`로 시작. 작동 안 하면 SwiftTerm 또는 직접 `forkpty` 사용.
- **W1 Spike 결과**: Claude CLI 2.1.101이 `-p --output-format stream-json --input-format stream-json` 조합으로 **TTY 없이 JSON 양방향 스트리밍을 1급 지원**. PTY/SwiftTerm/forkpty 모두 불필요.
- **결과**: ADR-009로 대체. SwiftTerm 의존성 추가하지 않음. `Package.swift`의 검토 코멘트 정리 가능.

---

## ADR-009 — `-p` 모드 + JSON 양방향 스트리밍 채택

- **날짜**: 2026-05-01
- **상태**: Accepted
- **결정**: Claude CLI는 항상 다음 인자 조합으로 호출한다:
  ```
  claude -p \
    --input-format stream-json \
    --output-format stream-json \
    --include-partial-messages \
    --include-hook-events \
    --session-id <uuid> \
    --settings <workspace harness settings.json> \
    --mcp-config <workspace harness .mcp.json> \
    --plugin-dir <workspace harness> \
    --add-dir <workspace directory>
  ```
- **컨텍스트**: W1 Spike(`claude --help` 분석)에서 `stream-json`, `--session-id`, `--settings`, `--mcp-config`, `--agents`, `--plugin-dir`, `--add-dir` 모두 공식 옵션으로 제공됨을 확인 (claude 2.1.101)
- **대안**:
  - Interactive REPL + PTY → ANSI 파싱 필요, TTY 필요, 복잡
  - `-p text` 모드 → 한 단계 단순하지만 도구 호출/부분 메시지를 잃음
  - **`-p stream-json` (채택)** → JSON 1급, 모든 메타 정보 보존
- **근거**:
  - **PTY 불필요**: `-p` 모드는 TTY 무관 → ADR-005 불필요
  - **ANSI 파싱 불필요**: JSON 메시지로 직접 받음
  - **하네스 완벽 주입**: `.harness/settings.json`, `.harness/.mcp.json`, `.harness/agents/`가 CLI 인자로 전달
  - **세션 영속을 Claude에 위임**: `--session-id` UUID만 SwiftData에 저장, 본문 관리는 Claude
  - **부분 메시지 + Hook 이벤트** GUI 진행 표시에 필수
- **결과**:
  - `Sources/YuminaiClaudeAdapter/`의 `LiveClaudeAdapter`는 단순 `Process` + `Pipe`로 구현 가능
  - `ClaudeEvent` enum은 W2에서 실제 stream-json 메시지 보고 정밀화
  - `ANSIStreamParser` 모듈 불필요 → 삭제 결정. 대신 `JSONStreamParser` 작성
  - `Package.swift`의 SwiftTerm 검토 코멘트 정리
- **리스크**: stream-json 메시지 schema 변경 시 우리도 따라야 함 (R8 — Claude Code 자체 변경)
- **재검토**: 다음 Claude Code 메이저 버전(3.0+) 출시 시점

---

## ADR-011 — SPM executable로 MVP 시작, Xcode App 번들은 후속

- **날짜**: 2026-05-01
- **상태**: Accepted (MVP-0 한정)
- **결정**: MVP-0의 SwiftUI macOS app은 `Sources/YuminaiApp/` SPM `.executable` 타깃으로 만든다. `swift run YuminaiApp`으로 실행/검증. 정식 `.app` 번들 + Xcode 프로젝트는 v0.2 시작 시 도입.
- **컨텍스트**: 본인 1인 사용 + 본인이 즉시 실행해보고 피드백 루프 빨리 돌리는 게 우선
- **대안**:
  - xcodegen 도입 → 추가 도구 의존성, 사용자 brew install 단계
  - Xcode 직접 새 프로젝트 → 사용자 GUI 개입 단계 필요
  - **SPM executable (채택)** → `swift run` 한 줄로 실행. CI/검증도 단순
- **근거**: SPM executable은 SwiftUI App protocol을 완전 지원. NSApplication, WindowGroup, Settings scene 모두 동작. Dock 아이콘/메뉴는 일부 제한적이지만 본인 사용에 충분.
- **결과**: `Package.swift`의 `.executableTarget(name: "YuminaiApp", ...)`. 빌드/실행 검증됨 (PID 39282, 12초 stable).
- **알려진 제약**:
  - Code signing 없음 (본인 사용 OK)
  - Info.plist 일부 키 자동 생성 안 됨 → Telegram URL 스킴, 알림 권한 등은 후속 단계에서 .app 번들로 가야 완전
  - 자동 업데이트 없음
- **재검토**: v0.2 진입 시 → xcodegen + .app 번들로 승격 검토 (사용자 답변 필요)

---

## ADR-012 — Telegram 양방향 (알림 + 명령) 채택

- **날짜**: 2026-05-01
- **상태**: Accepted
- **결정**: Telegram 통합은 시작부터 *양방향* — 알림 송신(`TelegramAlertDispatcher`) + 모바일 명령 수신(`TelegramCommandPump` + `TelegramCommandRouter`). 단방향 알림만 v0.2로 미루는 PRD 초기 안을 *수정함*.
- **컨텍스트**: 사용자 명시 요청 — "텔레그램 봇으로 직접 제어하거나, 작업 마쳤을 때 알림을 보내주는 형태"
- **대안**:
  - 단방향 알림만 v0.2 (이전 안) → 사용자 의도 미흡
  - 양방향 (채택) → 모바일에서 명령 → 데스크탑 Yuminai 활성 워크스페이스의 Claude로 전달
- **근거**: Long polling은 actor 1개 + URLSession만으로 구현 가능. `TelegramCommandRouter` protocol로 라우팅 책임 분리해 구현체 교체 가능.
- **결과**:
  - `LiveTelegramBot` actor: send / edit / startPolling / incoming AsyncStream
  - 화이트리스트 `allowedUserIds`로 보안 (다른 user 메시지는 silently drop)
  - `TelegramCommandPump`: incoming → router → 응답 송신
  - `YuminaiCommandRouter` (App layer): 받은 텍스트를 현재 활성 워크스페이스의 채팅 입력으로 주입 후 sendMessage()
  - SettingsView에서 토큰/Chat ID/허용 user ID 모두 GUI 편집 가능
- **알려진 제약 (v0.3로)**:
  - 의도 분류 없음 — 모든 메시지가 그대로 채팅에 들어감 (`#workspace command` 같은 prefix 라우팅은 후속)
  - inline keyboard / callback_query 없음 — 결정 요청 UI는 단순 텍스트
  - 앱 실행 중일 때만 polling (백그라운드 launchd agent 후순위)
- **재검토**: 본인 1주일 사용 후 — 양방향이 실제로 가치 있는지 데이터로 확인

---

## ADR-022 — 노트 기능 7종 일괄 (frontmatter / watcher / 검색 / wiki / embed / 편집 / @note)

- **날짜**: 2026-05-01
- **상태**: Accepted
- **결정**: 7개 노트 enhancement를 의존성 순서대로 한 라운드에 통합 구현 + 단위 테스트 + 실행 검증
- **컨텍스트**: 사용자 — 모든 항목 한 번에 + 마지막 UI/UX·반응형·기능 테스트
- **각 결정**:
  1. frontmatter — UI에서만 표시 (편집 X), reserved 키 (title, tags) 외 알파벳순
  2. file watcher — FSEventStream + 800ms debounce + AsyncStream<Set<String>>
  3. 본문 검색 — lazy concurrent (50개 limit, 250ms debounce). SwiftData FTS 미지원 — 자체. 영속 인덱스 v0.3
  4. Wiki link — preprocessing → swift-markdown-ui 일반 link → OpenURLAction이 yuminai-note scheme 인터셉트
  5. 이미지 임베드 — preprocessing → file:// URL → NetworkImage. 노트 임베드 (`![[Note]]`)는 wiki link로 fallback
  6. 편집 모드 — segmented toggle + ⌘S 저장 + 외부 변경 banner. 자동 저장 X
  7. @note — Composer 첨부 메커니즘 재사용 (path mention)
- **검증**: 72 tests (15 신규) + build 2.63s + run 정상
- **알려진 한계**:
  - Wiki link 동명 노트 시 첫 매칭만
  - 노트 임베드 inline 표시 v0.3
  - 편집 모드 raw markdown only
  - 검색 50개 limit
  - frontmatter 편집 UI 없음
- **재검토**: 사용자 사용 후

---

## ADR-021 — Obsidian Vault 직접 접근 + swift-markdown-ui (외부 의존성 정책 변경)

- **날짜**: 2026-05-01
- **상태**: Accepted
- **결정**:
  1. Obsidian CLI 별도 의존성 없이 Vault `.md` 파일 직접 접근 (FileManager)
  2. **첫 외부 SPM 의존성 도입** — swift-markdown-ui (gonzalezreal). 이전 정책 "외부 의존성 0" 변경
  3. Inspector를 tab 구조로 — 컨텍스트 / 노트 두 탭
  4. 마크다운 렌더링은 `MarkdownViewer` wrapping으로 라이브러리 lock-in 완화
- **컨텍스트**:
  - 사용자 — "옵시디언 cli 연동, Notion/Obsidian급 마크다운 뷰어"
  - Notion급 = 헤더/코드/테이블/task list/blockquote/이미지/링크 모두 — 자체 구현 비현실 (100시간+)
  - Obsidian CLI는 공식 X (npm `obsidian-cli` 비공식). Vault는 단순 `.md` 파일 → 파일 시스템 접근으로 충분
- **라이브러리 비교**:
  | 옵션 | 평가 |
  |---|---|
  | `AttributedString(markdown:)` Apple 네이티브 | basic만, 코드블록/테이블/task X |
  | `swift-markdown` (Apple) | 파싱만, 렌더러 자체 작성 |
  | **`swift-markdown-ui`** (채택) | Notion급 + Apple swift-markdown 기반 + theme 시스템, 1.5k stars, MIT |
  | 자체 구현 | 100시간+, 비현실 |
- **외부 의존성 정책 변경 근거**:
  - 자체 작성 ROI 낮음 (마크다운 렌더링은 standard task)
  - 라이브러리 검증 — 1.5k stars, Apple swift-markdown 의존, 활발한 maintenance
  - lock-in 완화 — `MarkdownViewer` wrapping → 교체 시 한 곳만 수정
- **결과**:
  - `Sources/YuminaiObsidian/` 신규 모듈 (ObsidianVault actor + Note + VaultNode)
  - `MarkdownViewer` + Yuminai theme (h1~h4 + paragraph + 인용 + 코드블록 + task list + 테이블 + 링크)
  - `NoteTreeView` (검색 + 트리/flat 모드)
  - `InspectorPanel` (tab 구조 + Vault 미설정 안내)
  - `AppModel` Vault state + lifecycle
  - 새 의존성: swift-markdown-ui 2.4.1, NetworkImage 6.0.1, swift-cmark 0.7.1 (transitive)
- **알려진 한계 (다음 라운드)**:
  - 채팅 @note 인라인 주입 미구현 (메시지에 노트 본문 첨부)
  - Wiki 링크 [[Page]] 미렌더 (swift-markdown-ui standard 외)
  - 임베드 ![[file]] 미렌더
  - frontmatter 파싱은 됐지만 표시 안 함
  - file watcher (Vault 변경 자동 갱신) 미구현
  - 노트 편집 read-only (편집 모드 v0.3)
- **재검토**: 사용자 사용 후 / 라이브러리 v3 출시 시

---

## ADR-020 — Settings는 macOS native Form + 첨부파일 = `@<path>` mention prepend

- **날짜**: 2026-05-01
- **상태**: Accepted
- **결정**:
  1. SettingsView는 시스템 룩 (`.formStyle(.grouped)` + `LabeledContent` + `Section { } header: { } footer: { }` 명시 형식). 자체 flat 컴포넌트 적용 안 함 (사용 빈도 낮음 + 시스템 정렬·접근성 보장)
  2. 첨부파일은 prompt에 `@<path>` mention 형식으로 prepend → Claude가 자체 Read 도구로 처리
- **컨텍스트**:
  - 사용자 — "설정 팝업 깨진 layout. 맥 네이티브 설정 메뉴 퀄리티로 정렬"
  - macOS Settings의 표준 룩 (System Settings)이 이미 잘 설계됨 — 우리가 다시 만들 필요 없음
  - 첨부파일을 어떻게 Claude에 전달할지 두 가지 옵션:
    - inline 파일 본문 (작은 파일만, 토큰 비용)
    - mention 경로 (Claude가 Read로 자동 호출, 토큰 절약)
- **이전 시도 실패 원인**:
  - `Section("title") { ... } footer: { ... }` shortcut이 macOS 26 SwiftUI에서 ambiguous → 매번 명시적 `Section { } header: { Text(...) } footer: { Text(...) }` 사용
  - Form/`Picker(.menu)` 기본 right alignment를 우리 토큰으로 override 시도하면서 깨짐
- **결과**:
  - SettingsView 5탭 (`일반/모델·모드/편집/텔레그램/Anthropic`) 모두 시스템 Form
  - 윈도우 480~760 height, 640~880 width
  - SecretField는 inline status badge + 버튼들 (시스템 button)
  - AppModel.attachedFiles + openAttachmentPicker (NSOpenPanel) + sendMessage prompt 가공
  - Composer attachedFiles chips (icon 확장자 추정 + ✕ + tooltip)
- **알려진 한계**:
  - SettingsView가 다른 view와 디자인 일관성 일부 깨짐 (시스템 룩 vs 자체 flat)
  - 첨부 파일 다중 시 chips가 매우 길면 horizontal scroll
  - 큰 폴더 첨부 시 Claude가 모두 Read 시도 — 토큰 폭발 가능 (사용자가 신중히 선택)
  - drag-and-drop 미지원 (다음 라운드)
- **재검토**: 사용자 사용 후

---

## ADR-019 — Brand accent = AG2R 시안 + PickerMenu 자체 컴포넌트 (Claude Code 룩)

- **날짜**: 2026-05-01
- **상태**: Accepted
- **결정**:
  1. ar2r → AG2R La Mondiale 확정 → `Theme.Brand.accent`를 밝은 시안 `#22C8E0`로 교체
  2. SwiftUI native `Menu` → 자체 `PickerMenu` (popover 기반)으로 전면 교체. Claude Code 데스크탑 dropdown 디자인 정합
  3. Settings 호출 → `@Environment(\.openSettings)` 사용 (`NSApp.sendAction` 대체)
- **컨텍스트**:
  - 사용자 메시지: "밝은 하늘색 강조색" + "설정 버튼/모델 스위치 작동 안 함" + Claude Code dropdown 스크린샷 제공
  - 기존 inline `Menu` (borderlessButton style)이 일부 환경에서 trigger 안 되는 알려진 이슈
- **PickerMenu 설계**:
  - native `.popover(isPresented:)` 기반 — macOS 표준, 위치/크기 안정
  - `PickerSection`: title + 우측 shortcut hint badges (⇧⌘M 등) + items
  - `PickerItem`: label + subtitle (부제, "1M"/"레거시" 같은) + isSelected (✓) + shortcutHint (1, 2, 3 등)
  - 항목 hover bg + 클릭 시 자동 close
  - `ShortcutKeyBadge` — 키캡 모양 미니 컴포넌트 (border + 작은 폰트)
- **결과**:
  - `Sources/YuminaiUI/PickerMenu.swift` (신규, 200줄+)
  - `SessionPickers.swift` 전면 재작성 — 모든 picker가 PickerMenu 사용
  - `PickerTriggerLabel` — Composer footer inline label (hover chevron → accent)
  - Theme.Brand.accent / accentDeep / accentMuted / accentBorder 모두 시안 톤
- **재검토**: 사용자 사용 후 — popover 위치/크기, shortcut hint 가시성, Settings 호출 동작 여부
- **알려진 한계**:
  - PickerMenu는 popover라 윈도우 매우 좁을 때 잘림 가능 (compact mode)
  - shortcut hint (1, 2, 3)은 표시만, 실제 단축키 처리는 미연결 (다음 라운드)
  - "빠른 모드" toggle (Claude Code 스크린샷의 마지막 섹션)은 우리 도메인에 없어 미구현

---

## ADR-018 — 브랜딩 (ar2r 자전거 팀 컬러) + 인터랙션 표준 + UX 라이팅 한글 친화

- **날짜**: 2026-05-01
- **상태**: Accepted (브랜드 컬러는 fallback, 사용자 답변 시 교체)
- **결정**:
  1. `Theme.Brand` namespace 도입 — 모든 강조 색은 Brand로 위임. 토큰 한 곳 변경으로 전체 반영.
  2. ar2r 정확한 컬러는 codex CLI 조사로 미확인 → fallback (deep navy `#0E2A47` + vivid orange-red `#FF5A36` + white) 사용
  3. 모든 버튼에 `PressedScaleStyle` (0.97 scale, 80ms) 적용. CTA(primary)는 `PrimaryButtonStyle` (hover 1.02 + brightness 추가)
  4. 모든 hover bg 변화에 100ms easeOut 애니메이션
  5. UX 라이팅 전수 패스 — `docs/design/70_BRANDING_AND_INTERACTION.md` §5.2 라벨 통일표 적용
- **컨텍스트**:
  - 사용자 — "이 정도 디자인 퀄리티" + "ar2r 자전거 팀 컬러" + "버튼 인터랙션·애니메이션" + "UX 라이팅 한글 친화" 동시 요청
  - 디자인은 색·인터랙션·라이팅이 동시 작동해야 일관 — 한 라운드에 통합 처리 필요
- **codex 조사 결과** (`codex exec --skip-git-repo-check`):
  - `ar2r` / `AR2R` / `에이알투알` + 자전거 키워드로 검색 — 공개 웹에서 자전거 팀 미확인
  - 발견된 동명: AI tool, 프랑스 회사, 알마티 클럽 (모두 자전거 무관)
  - codex 제안 fallback: deep navy + orange-red (자전거 저지 표준 — bold primary + high-visibility accent + white)
- **결과**:
  - `Theme.Brand` 5개 토큰 (primary/primaryDark/primaryLight/accent/accentDeep/accentMuted/accentBorder/contrast)
  - `Theme.Color.accent` 등 Brand 위임
  - `FlatComponents`에 `PressedScaleStyle`, `PrimaryButtonStyle`, `AnyButtonStyle` 추가
  - `WorkspaceItemRow`에 hover 시 ⌘N 단축키 hint
  - `ChatToolbar` Breadcrumb 클릭 시 native `Menu` (워크스페이스 리스트 + "+ 새")
  - `RootView`에 ⌘1~9 invisible button 9개 (workspace 빠른 전환)
  - 18개 view literal 한글화 (Composer/Sidebar/ChatView/ChatToolbar/ContextInspector/UsageDashboard/CreateWorkspaceSheet/RootView empty/error alert)
- **알려진 한계 (다음 라운드)**:
  - 로고 SwiftUI View / SVG / PNG / .icns 미생성
  - About/splash 화면 미구현
  - Settings는 여전히 시스템 Form
  - ⌘K command palette 미구현 (sidebar search 콜백 빔)
  - Toast 컴포넌트 미작성 (alert만)
  - Sidebar ↑↓ keyboard nav (focus management) 미구현
  - Reduce-motion 자동 감지 미적용
  - **ar2r 정확한 컬러** — 사용자 답변 필요 (Q-A in 70 spec)
- **재검토**: 사용자 답변 + 다음 iteration

---

## ADR-017 — 반응형 Layout (LayoutMode + AppStorage user intent)

- **날짜**: 2026-05-01
- **상태**: Accepted
- **결정**: 윈도우 너비를 4단 breakpoint(compact/medium/regular/wide)로 분기. 각 모드에 따라 sidebar/inspector 자동 표시 정책. 사용자 의도(toggle 결과)는 AppStorage에 영속 → mode 복귀 시 복원. compact 모드에서 sidebar는 overlay popup.
- **컨텍스트**: 좁은 윈도우(<800px)에서 sidebar+inspector+chat 모두 표시 시 chat 너비 부족 → 사용성 저하. 사용자가 매번 수동 toggle 강요당함.
- **대안**:
  - NavigationSplitView 시스템 자동 — 디자인 통제 불가 (ADR-015에서 우회 결정)
  - 사용자 수동만 — UX poor
  - **breakpoint 자동 + intent 영속 (채택)** — Linear/Slack/VS Code 등 표준 패턴
- **breakpoint 결정 근거**:
  - 760: macOS 작은 윈도우 (압축 시) 평균값. 그 이하는 mobile-like
  - 1080: sidebar 280 + chat 520 + inspector 280 ≈ 1080. 임계
  - 1440: 모든 컴포넌트 여유 + 코드 본문 여유. 표준 외장 모니터 단계
- **결과**:
  - `LayoutMode` enum (Theme.Layout 외부)
  - `Theme.Layout.mode(for:)` static
  - RootView `GeometryReader` + `@AppStorage` 2건 + `@State sidebarOverlayShown`
  - `handleSizeChange(_:)` — mode 변경 시 자동 정리 (overlay 닫기, inspector sync)
  - ChatToolbar inspector 버튼 disabled 상태 + tooltip
  - 단위 테스트 3건 (boundaries / allowance / overlay)
- **알려진 한계**:
  - sidebar/inspector 너비 사용자 리사이즈 미지원 (현재 고정) — 다음 라운드 후보
  - 동적 contentMaxWidth 미적용 (chat 본문 폭 자동 조정 가능) — 다음 라운드 후보
  - reduce-motion 환경에서 transition 애니메이션 자동 disable 미적용
- **재검토**: 사용자 사용 후 — 너비 임계값이 본인 환경에 맞는지

---

## ADR-016 — codex CLI 검증 → Design Spec v3 (Claude Code 데스크탑 정합)

- **날짜**: 2026-05-01
- **상태**: Accepted
- **결정**: 사용자 제공 Claude Code 데스크탑 스크린샷을 기준으로 design spec을 작성하고, codex CLI 0.116.0의 critical review 9건을 모두 명세서 v3에 반영. 그 위에 Theme + 11개 컴포넌트를 재구성한다.
- **컨텍스트**: v2 flat 룩이 너무 monospace/직각 위주로 가서 "Claude Code 데스크탑처럼 플랫하고 사용성있는" 사용자 기대 미달. 스크린샷 자체를 ground truth로 정밀 추출 + 외부 디자인 시스템 검증 + codex 메타 검증 필요.
- **codex 9건 critical 이슈**:
  1. 단일 스크린샷 과적합 (pane/diff/terminal view 무시) → MVP 비범위 명시
  2. Sidebar dot semantics 모호 → ●=selected 확정, status는 trailing badge 분리
  3. Composer 핵심 컨트롤 누락 (send/stop/pickers) → 모두 명시 + 구현
  4. 토큰이 generic SaaS dark → warm 톤 (R>B), sidebar/bg 분리
  5. textTertiary 대비 부족 → 토큰 lift + 11~12px 한정
  6. 팔레트 noisy (blue user bubble) → orange muted로 변경
  7. 컴포넌트 비율 web-app적 → sidebar 32px, sf 14px, update card 2px-bar 제거
  8. Interaction 미정의 → 키보드 표 + non-color selected + reduced motion + VoiceOver
  9. SwiftUI 함정 → Breadcrumb 위치 변경, NSTextView 옵션, min/max width 명시
- **방법**: `codex exec --skip-git-repo-check "Read docs/.../60_UI_DESIGN_SPEC.md, critically review..."` → tool use로 file 읽고 web 참조 (`code.claude.com/docs/en/desktop`) 후 9건 도출
- **결과**: `docs/design/60_UI_DESIGN_SPEC.md` v3 (350+ 줄, §14에 codex→우리결정 추적), Theme.swift v3, FlatComponents v3, SidebarView/MessageBubble/Composer/ChatToolbar/ChatStatusBar/ContextInspector/SessionPickers/UsageDashboard/CreateWorkspaceSheet/ChatView/RootView 모두 v3
- **재검토**: 사용자가 다시 띄워본 후 / 다음 iteration 라운드

---

## ADR-015 — macOS 네이티브 컴포넌트 우회 + 자체 Flat 토큰 시스템

- **날짜**: 2026-05-01
- **상태**: Accepted
- **결정**: Yuminai UI는 macOS 네이티브 컴포넌트(NavigationSplitView, Form, Picker dropdown 룩, `.regularMaterial` 등)를 의도적으로 우회하고, 자체 Theme 토큰 + 자체 Flat 컴포넌트(FlatButton, FlatTextField, FlatSection 등)로 구성한다.
- **컨텍스트**: 사용자 피드백 — "macOS 네이티브감이 너무 강함, Claude Code의 플랫하고 사용성 있는 룩 원함". 디자인 MD 라이브러리(shadcn/Tailwind 등)는 SwiftUI에 직접 import 불가하지만, 토큰 + 자체 컴포넌트로 등가 재현 가능.
- **대안**:
  - macOS 네이티브 룩 그대로 + 색만 조정 → 사용자 의도 미흡
  - WebView 임베드 + HTML/Tailwind → 무겁고 SwiftUI 의도 어긋남
  - **자체 Flat 토큰 + 자체 컴포넌트 (채택)** → 가장 깨끗
- **근거**:
  - SwiftUI에서 macOS 네이티브 룩은 시스템 색/material/standard 컴포넌트로부터 옴. 이걸 우회하면 임의 디자인 가능.
  - Theme.Color는 명시적 light/dark hex 정의, Color(light:dark:) helper로 자동 전환.
  - Layout은 NavigationSplitView 대신 직접 HStack — sidebar는 자체 toggle.
- **결과**:
  - `Theme.swift` 전면 재작성 (Color/Typography/Spacing/Radius/Stroke/Layout)
  - `FlatComponents.swift` 신규 (FlatButton/Text/Section/Row/Divider/Toggle)
  - 모든 view 파일에서 시스템 색 참조 → 새 토큰
  - `flatChrome(borders:)` modifier로 chrome 단순화
  - MessageBubble 박스 제거 → CLI 스타일 prefix 마커 + role 라벨
  - InlinePicker monospace + 1px border 형식
- **알려진 한계**:
  - `SettingsView`는 SwiftUI Form/Section/Picker 그대로 (시스템 룩 잔존) — 사용 빈도 낮아 후순위
  - 사이드바 collapse animation이 NavigationSplitView보다 단순
- **재검토**: SettingsView도 자체 flat 컴포넌트로 마이그레이션 필요 시점

---

## ADR-014 — Toolbar inline picker + 즉시 재spawn

- **날짜**: 2026-05-01
- **상태**: Accepted
- **결정**: 채팅 영역 상단의 picker (model/mode/effort)를 변경하면 즉시 `LiveClaudeAdapter.updateSettings(_:)` 호출 + 활성 워크스페이스의 ClaudeStreamSession을 종료하고 새 settings로 spawn. 메시지 UI 로그는 보존.
- **컨텍스트**: 사용자가 채팅 도중 모델/모드를 자유롭게 바꿔서 비교 실험을 원함 (Claude Code 데스크탑 마이그레이션 수준의 UX)
- **대안**:
  - "Apply" 버튼 추가 후 명시적 적용 → 마찰 큼
  - 다음 메시지부터 적용 (lazy) → 우리 spawn 모델은 세션 1개 유지라서 어려움
  - **즉시 재spawn (채택)** → 자연스러움. Claude CLI의 `--session-id`로 컨텍스트 유지되므로 메시지 손실 없음
- **결과**:
  - `ClaudeAdapter` protocol에 `updateSettings/currentSettings` 추가
  - `LiveClaudeAdapter.updateSettings`는 actor state만 변경 (다음 spawn에 적용)
  - `AppModel.updateActiveSettings(_:)`이 spawn 재실행 + 메시지 UI는 그대로
- **알려진 한계**: settings 변경 시 진행 중이던 응답은 잃을 수 있음 (intentional)
- **재검토**: 본인 사용 후 → 충분히 자연스러운지 / 디바운스 필요한지

---

## ADR-013 — UI 형태 B2 확정

- **날짜**: 2026-05-01
- **상태**: Accepted (Q-B 답변 완료)
- **결정**: B2 — CLI 스타일 채팅 GUI. monospace, 다크 친화 토큰, NavigationSplitView (사이드바 + chat detail), MessageBubble 위젯.
- **컨텍스트**: 사용자 명시 결정
- **결과**: `YuminaiUI` 컴포넌트 완비. Liquid Glass는 후속에서 chrome에만 적용 검토.

---

## ADR-010 — 세션 영속을 Claude에 위임, SwiftData는 메타만

- **날짜**: 2026-05-01
- **상태**: Accepted (ADR-009 종속)
- **결정**: 메시지 본문 영속은 Claude CLI의 `--session-id` 메커니즘에 위임. Yuminai SwiftData에는 다음만 저장:
  1. `Workspace` 엔티티 (디렉토리, 이름, 하네스 템플릿)
  2. `Session` 엔티티 (UUID, workspace ref, started/ended, title)
  3. `Message` 엔티티 (UI 표시용 캐시 — Claude의 sole source of truth가 아니라 빠른 사이드바/검색용)
  4. `ToolEvent` (선택, 분석용)
- **컨텍스트**: Claude CLI가 자체적으로 세션 영속/재개 메커니즘 보유 (`-r`, `-c`, `--session-id`)
- **대안**:
  - SwiftData가 sole source of truth → Claude의 영속 메커니즘과 이중화, 일관성 어려움
  - Claude만 영속 → Yuminai 사이드바/검색이 어려움
  - **하이브리드 (채택)** → Claude는 컨텍스트 복원에 사용, SwiftData는 UI/검색에 사용
- **결과**: `YuminaiPersistence`의 `Message` 모델은 cache 의미. truncate해도 다음 호출 시 Claude가 컨텍스트 유지함.
- **재검토**: 메시지 검색 / 분석 요구 강해지면 SwiftData를 sole source로 승격

---

---

## ADR-006 — UI 형태 잠정 B2 (CLI 스타일 채팅 GUI)

- **날짜**: 2026-05-01
- **상태**: Provisional
- **결정**: B2 — Monospace 다크 채팅 UI + 통합 위젯 (사이드바, inspector). B1 터미널 임베드와 B3 풀 GUI는 보류.
- **컨텍스트**: 사용자가 "Claude Code와 같은 형태"라고 요청
- **대안**: [`99_OPEN_QUESTIONS.md`](../prd/99_OPEN_QUESTIONS.md) Q-B 참조
- **근거**: B2가 통합 친화도와 노력의 균형. 사용자 답변 시 변경 가능.
- **재검토**: 사용자 답변 시 즉시

---

## ADR-007 — MVP-0 통합 완전 비활성

- **날짜**: 2026-05-01
- **상태**: Accepted
- **결정**: MVP-0에선 Obsidian / Telegram / git worktree 등 모든 외부 통합을 비활성. 오직 Claude CLI + 채팅 + 영속만.
- **컨텍스트**: 4주 일정, 핵심 가설(Yuminai를 본인이 실제로 일상 진입점으로 쓸 것인가) 검증이 우선
- **대안**: 통합 일부 동시 진행 → 일정 미스 + 핵심 가설 검증 늦어짐
- **근거**: R5 (통합이 너무 많아 핵심 가치 흐려짐) 완화
- **결과**: [`90_ROADMAP.md`](../prd/90_ROADMAP.md) MVP-0 Scope 명시
- **재검토**: MVP-0 종료 시점

---

## ADR-008 — 코드 편집기 비포함

- **날짜**: 2026-05-01
- **상태**: Accepted
- **결정**: Yuminai는 코드 직접 편집 기능을 제공하지 않는다. 변경은 Claude가 수행한다.
- **컨텍스트**: Cursor / VS Code / Xcode 등 별도 IDE 사용
- **대안**: 간단한 코드 편집기 임베드 → 큰 노력 / 본인 IDE 대체 안 됨
- **근거**: Yuminai는 *대화형 작업 셸*. IDE 기능과 경쟁하지 않음.
- **결과**: F-W (Won't) 명시, [`30_GOALS_NONGOALS.md`](../prd/30_GOALS_NONGOALS.md) NG7
- **재검토**: 만약 1년 후 별도 IDE 없이 Yuminai만 쓰고 싶어지면 재검토

---

## 잠정 결정 (Provisional)

답변 받기 전 잠정값. [`99_OPEN_QUESTIONS.md`](../prd/99_OPEN_QUESTIONS.md) 답변 시 ADR로 승격.

| Provisional | 잠정값 | 근거 |
|---|---|---|
| Q-B UI 형태 | B2 | 통합 친화도 + 노력 균형 |
| Q-D1 Obsidian Vault | 사용자 입력 받음 | - |
| Q-D2 Telegram bot | BotFather에서 새로 만듦 | - |
| Q-D3 다른 통합 | GitHub만 v0.3 | 본인 일상 사용 빈도 |
| Q-E 워크스페이스 | git worktree 선택 (생성 시 옵션) | 유연성 |
| Q-F iCloud | 1대 가정, v0.3에서 메타만 | 단순성 |
| Q-G 보안 | Sandbox OFF, Hardened Runtime ON+ent | ADR-003 |
| Q-H 일정 | MVP-0 4주 공격적 | - |
| Q-I Xcode 자동화 | xcodegen/tuist 미도입 | 단순성 |
| Q-J 코드네임 | "Yuminai" 정식 / 영문 우선 | 사용자 결정 |
| Q-K 메타-하네스 | claude-forge 참조 | 중복 회피 |
| Q-L 사용 분석 | v1.0 간단 차트 | 우선순위 낮음 |
