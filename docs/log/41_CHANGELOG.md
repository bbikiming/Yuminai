# Changelog

> 변경 사항 시간순 기록. 의미 있는 변경만.

## [Unreleased] — 2026-05-02

### Added — v0.4 Phase F: GUI 사용성 polish (위임 버튼 + 더블클릭 rename + 가이드) (ADR-033)

사용자: "사용해 볼 시나리오 항목들을 명령어보다는 gui를 통해 버튼으로 사용성을 쉽게 구현해 주고 후속 작업도 검토해서 진행해"

**평가** (이번 라운드):
| 항목 | 결정 |
|------|------|
| GUI 위임 버튼 (Composer footer) | ✅ |
| Tab 더블클릭 rename | ✅ |
| Toolbar 가이드 버튼 (questionmark) | ✅ |
| 빈 워크스페이스 onboarding 강화 | ✅ |
| ShortcutHelpSheet에 GUI 시나리오 카드 | ✅ |
| pane→pane 자동 답장 (안전 토글) | ⏸ 보류 (안전 우선) |

**G1. Composer 위임 버튼**:
- Composer footer에 ↪ 화살표 아이콘 (`arrowshape.turn.up.right`) Menu
- mentionSuggestions 비어있지 않으면 표시
- 클릭 → 사용 가능한 pane 리스트 (★ primary 표시 + agent kind label)
- 선택 → 현재 text 앞에 `@<handle>` prepend (또는 빈 text면 mention만)
- 사용성: `@` 키보드 입력 외에 명시적 GUI 진입점

**G2. Tab 더블클릭 rename + Toolbar 가이드 버튼**:
- PaneTabBar PaneTabButton에 `simultaneousGesture(TapGesture(count: 2))` → onRename 호출
- tooltip: "더블클릭으로 이름 변경, 우클릭 메뉴"
- ChatToolbar에 ⌘D 옆 `questionmark.circle` IconButton 추가 → ShortcutHelpSheet 호출
- 단축키 ⌘/ 외에 클릭으로도 가능

**G3. Onboarding hint + ShortcutHelpSheet 시나리오 카드**:
- EmptyWorkspaceView에 "도움말" secondary 버튼 추가 (`+ 새 워크스페이스` 옆)
- quick tip 4개로 확장 (split / 위임 / terminal+inspector / 텔레그램+delivery)
- ShortcutHelpSheet 상단에 새 섹션 "주요 시나리오 — GUI에서 어디?"
  - 8 카드: Codex pane 추가 / split / 위임 / rename / 텔레그램 / delivery / diff review / terminal
  - 각 카드: icon + title + howTo 한 줄 (단축키만 X, GUI 위치 안내)
- ShortcutHelpSheet 크기 520×560 → 560×640 (시나리오 카드 수용)
- 헤더 라벨 "단축키" → "도움말"

**F1. pane→pane 자동 답장 — 명시 보류**:
- 평가 결과: 가치 보통, 무한 루프 위험, 사용자 control 약화, 복잡도 보통
- **결정**: v0.5 이후로 보류. 현재는 사용자 명시 mention만 (안전 우선)
- ADR-033에 사유 명시 (다음 라운드 검토 트리거: 사용자가 "agent끼리 자동 답장 원함" 명시)

**검증**: build 2.8s, test 184/184 (변경 없음 — UI 추가만)

알려진 한계:
- 위임 버튼은 mentionSuggestions이 있어야 표시 (panes 1개일 땐 mentionSuggestions가 자기 자신 후보만이라 의미 X)
- 더블클릭 rename은 단일 클릭(select)와 simultaneousGesture라 가끔 충돌 가능 (실측 후 조정)
- 가이드 시나리오 카드는 정적 텍스트 — 인터랙티브 튜토리얼 X (v0.5)

**보류 명시**:
- pane→pane 자동 답장 (안전)
- Mention picker 중간 위치 (가치 < 비용)
- Codex JSONL 실측 정밀화 (사용 데이터 필요)
- ACP Spike / Dual-Composer / Editable diff / T5/T6/T8 (이전 ADR-032와 동일)

### Added — v0.4 Phase E: Mention picker + Source label + Pane rename + Split layout (ADR-032)

사용자: "나머지 라운드도 이어서 진행해 줘" — 보류 항목 (T4-T8 + v0.5) 평가 후 가치/비용 매트릭스로 4개 진행, 6개 명시 보류.

**평가 매트릭스** (이번 라운드):
| 항목 | 가치 | 비용 | 결정 |
|------|-----|------|------|
| U1 Mention picker | 높음 | 보통 | ✅ |
| U2 Assistant 라벨 | 높음 | 작음 | ✅ |
| U3 Pane rename | 보통 | 작음 | ✅ |
| U4 Split layout | 보통 | 큼→작음(단순화) | ✅ |
| T5 per-pane settings | 낮음 | 보통 | ⏸ |
| T6 PreviewPane | 보통 | 보통 | ⏸ (use case 명시 시) |
| T8 Block UX | 보통 | 보통 | ⏸ (terminal 빈도 보고) |
| pane→pane 자동답장 | 보통 | 작음 | ⏸ (안전 우선) |
| ACP Spike | 모호 | 큼 | ⏸ (별도 라운드) |
| Editable diff | 높음 | **매우 큼** | ⏸ (cost prohibitive) |

**U1. Mention picker (Composer `@` 자동완성)**:
- `Sources/YuminaiUI/Composer.swift` 확장
  - `MentionSuggestion { handle, displayName, agentKindLabel, isPrimary }` 구조
  - `mentionSuggestions: [MentionSuggestion]` param
  - `text`가 `@`로 시작 + 공백 없음 시 popover 자동 표시
  - 필터: handle prefix 또는 displayName contains (case-insensitive)
  - 선택 시 `text = "@<handle> "` 자동 채움 + focus 유지
  - 빈 결과 시 "매칭되는 pane이 없어요" 안내
- `RootView.mentionSuggestions` computed — agentPanes에서 customName + shortLabel 모두 후보

**U2. ChatView source label (assistant pane 표시)**:
- `MessageBubble`/`AssistantMessageBlock`에 `assistantLabel: String` param 추가 (default "Claude")
- `ChatView`가 prop으로 받아 forward
- RootView가 `appModel.activePane?.displayName ?? "Claude"` 전달
- 효과: Codex pane 활성 시 "CODEX"로 라벨 표시 (uppercase + tracking)

**U3. Pane rename + promote**:
- `Sources/YuminaiApp/PaneRenameSheet.swift` (신규) — 420pt 모달
  - TextField + InlineHint ("비워두면 기본 이름")
  - ⌘Return 저장 / ESC 취소
- `PaneTabBar` `contextMenu` 추가:
  - "이름 바꾸기…" (pencil)
  - "기본 pane으로 설정" (star, primary 아닐 때)
  - "닫기" (xmark, destructive, can close 시)
- `AppModel.promotePaneToPrimary(_:)` — 다른 primary는 secondary로 demote
- `AppModel.renameSheetPane: AgentPane?` (sheet item binding)
- `RootView.sheet(item:)` — 모달 등록 + onApply/onCancel

**U4. Split layout (단순화 — active + 첫 secondary)**:
- `Sources/YuminaiCore/PaneSplitMode.swift` (신규)
  - `enum { single, horizontal, vertical }` + 한국어 라벨 + icon
- `AppModel.paneSplitMode: PaneSplitMode = .single`
- `PaneTabBar`에 split mode picker (panes 2개+ 시만 표시) — Menu icon
- `RootView.chatArea` computed:
  - `.single` → 기존 동작 (active만)
  - `.horizontal` → HSplitView(active 좌, secondary 우)
  - `.vertical` → VSplitView(active 위, secondary 아래)
- `Sources/YuminaiApp/SecondaryPaneView.swift` (신규)
  - read-only chat (Composer 없음)
  - 헤더: agent icon + 이름 + ★ + "보조" badge + 활성화 버튼
  - 빈 상태: "이 pane은 아직 대화가 없어요"
- 단순화 결정: 진짜 N-pane 동시 (각자 Composer)는 v0.5. 현재는 active 1 + secondary 보기만

**테스트 3 신규** (PaneSplitMode):
- 3개 case 한국어 라벨 + icon
- Codable round-trip
- raw value 확인

**검증**: build 3.7s, test 184/184 (181→184, +3 신규)

알려진 한계:
- Split의 secondary는 read-only (입력 X) — 진짜 동시 dual-Composer는 v0.5
- per-pane delivery config 여전히 X
- Mention picker는 leading `@`만 — 중간 mention X
- Codex JSONL schema 실측 정밀화는 사용자 사용 후 (idle 데이터 모임)

**보류 명시 (defer doc 84)**:
- T5/T6/T8 — 사용자 명시 트리거 시
- pane→pane 자동 답장 — v0.5 안전 토글
- ACP Spike — v0.5 별도 spike (Swift SDK 부재)
- Editable diff — cost prohibitive (SwiftUI native diff editor 부재)

### Added — v0.4 Phase D: Panes 영속 + 인터-에이전트 메시지 + Codex schema 정밀화 (ADR-031)

사용자: "남고 권고 순서 하나하나 상세하게 기획하고 냉정하게 사용성과 단위 기능 검토해 가면서 구현 이어서 진행해"

먼저 평가 doc 작성 → 가치/비용 매트릭스로 우선순위 재조정 → T1+T2+T3 진행, T4-T8 보류 (defer 사유 명시).

**평가 결과** (`docs/design/84_REMAINING_PHASES_EVALUATION.md`):
- 가치 큰 것 우선: Panes 영속 (T1) → 인터-에이전트 메시지 (T2) → Codex schema 정밀화 (T3)
- 보류: split layout (T4, tab 충분), per-pane 설정 (T5, swap 동일), PreviewPane (T6, use case 모호), pane reorder (T7, 사용 빈도 낮음), Block 그룹화 (T8, terminal 사용 빈도 보고)

**T1. Panes 영속 (workspace 재진입 시 보존)**:
- `Workspace.savedPanes: [AgentPane]` 필드 추가 + `with(savedPanes:)` immutable
- `AgentPane: Codable` 추가 (SessionSettings/AgentKind/PaneRole 모두 이미 Codable)
- `WorkspaceModel.panesJSON: Data?` SwiftData column (nullable, 마이그레이션 호환)
- `AppModel.ensurePrimaryPane`이 `savedPanes`가 있으면 복원 (primary 없으면 첫 pane promote)
- `addPane`/`removePane`/`renamePane`이 `persistCurrentPanes()` 자동 호출
- session/messages는 영속 X (메타만 — conversation은 fresh, claude resume으로 컨텍스트 복원)

**T2. 인터-에이전트 메시지 (`@codex` mention)**:
- 1순위 reference: MetaGPT 메시지 환경 + AutoGen GroupChat speaker selection (manual hint)
- `Sources/YuminaiCore/MentionParser.swift` (신규)
  - `parse(_:) -> Mention?` — leading `@<word> <body>` 추출
  - `Mention { target, body, originalText }`
  - `normalizedTarget(_)` static — `@` 제거 + lowercase
  - 단순한 패턴 (mention만 있고 body 없으면 nil, `@` 한 글자 무시)
- `AppModel.resolveMentionTarget(_:) -> AgentPane?` — 우선순위:
  1. customName 정확 매칭 (case-insensitive)
  2. customName 부분 매칭
  3. agentKind shortLabel (`@claude`, `@codex`)
  4. agentKind displayName 부분 매칭
  5. `@me` → active pane (no-op)
- `AppModel.tryDispatchMention() async -> Bool` — inputText에서 mention 발견 시 대상 pane 활성화 + body로 inputText 교체 + sendMessage. 매칭 실패 시 사용자 안내
- Composer onSend 수정: tryDispatchMention 우선, 매칭 안 되면 일반 sendMessage
- Telegram router도 동일 흐름 (텔레그램에서도 `@codex` 사용 가능)
- Composer placeholder 변경: "@codex 또는 @claude로 다른 pane에 위임"

**T3. Codex JSONL schema 안전 type 추가**:
- 알려진 type alias 추가: `agent_message_chunk` / `agent_message_delta` / `delta` / `stream_text` / `tool_use_started` / `tool_call_delta` / `tool_use_result` / `tool_observation` / `usage_update` / `session_initialized` / `configured` / `ready` / `cached_tokens` 키 / `cost` 키
- `thinking` / `reasoning` / `chain_of_thought` 명시적 무시 (verbose 노이즈 회피)
- `error` / `agent_error` → `toolResult(success: false)` forward (사용자 인지)
- `status: "completed"`도 success로 인식
- 알 수 없는 type fallback은 그대로 (`[codex <type>] raw`로 forward)

**테스트 20 신규**:
- MentionParserTests (8): basic / leading whitespace / newline separator / no prefix / bare @ / no body / multiline / normalize
- WorkspaceSavedPanesTests (5): defaults empty / 1개 / immutable / Codable round-trip / 다른 with() 보존
- CodexSchemaExtraTests (7): chunk/thinking 무시/tool_use_started/completed status/usage_update/error→toolResult/session_initialized

**검증**: build 3.5s, test 181/181 (161→181, +20 신규)

**보류된 항목** (defer 사유 doc 84 참조):
- T4 좌/우 split layout — 사용자 명시 요청 시
- T5 per-pane Composer 설정 — swap이 동일 효과
- T6 PreviewPane (WKWebView) — use case 명시 시
- T7 pane drag-reorder / rename sheet — panes 5개+ 시
- T8 Block 그룹화 (Warp UX) — terminal 사용 빈도 보고

알려진 한계 (다음 라운드):
- mention dispatch는 "사용자 응답"만 (pane → pane 답장 X, 무한 루프 위험)
- mention 자동완성 picker X (Composer에 `@` 입력 시 추천 — v0.5)
- panes 영속하지만 messages는 fresh — claude session resume으로 컨텍스트만 복원
- ChatView에 어떤 pane이 보낸/받은 메시지인지 시각적 구분 X (tab 자체로 구분)
- per-pane 별도 deliveryConfig X (workspace 단위)

### Added — v0.4 Phase C: Multi-pane Foundation (M1) (ADR-030)

사용자: "다음 권고 사항 이어서 진행해 줘"
ADR-027의 Phase 순서 권고 — Phase C M1 multi-pane 진행.

**참조** (ADR-027 evidence): AutoGen `AgentTool` 패턴 (57.6k, 패턴만) + Aider Architect/Editor 내부 2-LLM (44.2k, 검증된 패턴).

한 워크스페이스에서 Claude pane과 Codex pane을 동시에 띄우고 빠르게 전환:
- 각 pane은 자체 session + messages + settings + usage
- 같은 프로젝트 폴더 공유 (file system이 협업 매개체)
- Tab 클릭으로 active 전환 (messages/session swap)
- "+" 버튼으로 새 pane 추가 (Claude/Codex 선택)

**구현**:
1. **`Sources/YuminaiCore/AgentPane.swift` (신규)**
   - `AgentPane { id, agentKind, settings, role, customName?, createdAt }`
   - `displayName` computed (customName ?? agentKind.displayName)
   - immutable updates: `with(agentKind:)` / `with(settings:)` / `with(role:)` / `with(customName:)`
   - `PaneRole` enum: `.primary` (Telegram bridge target, 1개) / `.secondary`
2. **`AppModel` multi-pane state (refactor)**
   - `agentPanes: [AgentPane]` published
   - `activePaneId: UUID?`
   - `paneMessages: [UUID: [Message]]` / `paneSettings: [UUID: SessionSettings]` / `paneUsage: [UUID: UsageStats]`
   - private `paneSessions: [UUID: any ClaudeStreamSession]`
   - `activePane: AgentPane?` computed
   - `ensurePrimaryPane(for:session:)` — workspace 활성화 시 default primary 1개 자동 등록 (기존 session/messages를 wrap)
   - `setActivePane(_:)` — 현재 pane state 보존 (paneMessages/Settings/Usage 저장) + 대상 pane state 로드 + session lazy spawn (없으면 새로)
   - `addPane(agentKind:)` — 새 pane 등록 + active 전환 (session은 setActivePane이 spawn)
   - `removePane(_:)` — session terminate + state 정리 + active 변경 (마지막 pane은 close 불가)
   - `renamePane(_:to:)` — customName 갱신
   - `clearPaneState()` — workspace 전환 시 호출
   - `teardownCurrentSession()` 확장 — 모든 secondary pane sessions terminate + clearPaneState
3. **`Sources/YuminaiUI/PaneTabBar.swift` (신규)**
   - workspace 안의 panes를 horizontal tab으로 표시
   - 각 tab: agent icon + displayName + primary star + 호버/active 시 ✕ close 버튼
   - active tab 하단에 2pt accent border
   - "+" Menu — Claude pane 추가 / Codex pane 추가 (codex 미설치 시 disabled)
   - HelpHint i 아이콘 — 사용법 안내 popover
4. **`Sources/YuminaiApp/RootView.swift`** — chat 영역 위에 PaneTabBar 표시 (panes 1개 이상일 때)

**같은 프로젝트, 다른 에이전트 협업**:
- 두 pane 모두 `workspace.directoryPath` 공유 — file system이 자연스러운 IPC
- Claude로 설계 → tab 전환 → Codex로 빠른 구현 → 다시 Claude로 검토
- 각 pane은 자체 session id로 conversation context 유지 (전환 시 메시지 보존)

**테스트 9 신규**:
- AgentPaneTests (9): defaults / customName override / empty fallback / with() immutable variants 3건 / PaneRole 라벨+icon / Codable / 같은 kind 다른 id

**검증**: build 3.0s, test 161/161 (152→161, +9 신규)

알려진 한계 (Phase C 후속 → C2/C3/C4):
- **좌/우 split layout** X — tab 전환만 가능 (한 시점에 1 pane만 visible). Power user UX는 다음 sub-phase
- **per-pane Composer/Toolbar settings** X — 현재 모든 pane이 같은 activeSettings 사용 후 swap 시 pane.settings로 교체. 진짜 per-pane picker는 v0.5
- **인터-에이전트 메시지 (`@codex`)** X — Phase D (M2)
- **Codex JSONL schema 정밀화** X — Phase E
- pane drag-and-drop reorder X
- pane settings sheet (이름/role 변경) X — 현재는 컨텍스트 메뉴 없음

### Added — v0.4 Phase B: Delivery Loop (M4) + 사용성 도움말 UI (ADR-029)

사용자: "페이즈 b 시작하고 사용성에 대해 안내 도움말은 i 아이콘이나 간단한 건 상시로 보여지게 ui 디자인해줘"

두 가지 동시 진행:
1. **HelpHint UI 일괄** — i 아이콘 (popover) + 상시 hint + 빈 상태 hint
2. **Phase B Delivery Loop** — Aider auto-test + Devin step budget 패턴 (ADR-027 권고)

**1. UI 도움말 컴포넌트 (재사용 가능)**:
- `Sources/YuminaiUI/HelpHint.swift` (신규)
  - `HelpHint` — i 아이콘 + 클릭/호버 popover (긴 안내)
  - `InlineHint` — 항상 보이는 짧은 안내 (info/success/warning/tip 4종)
  - `EmptyStateHint` — 빈 영역 friendly 안내 (icon + title + body + optional action)
  - `LabelWithHint` — LabeledContent 라벨 옆 i 아이콘 inline
- 일괄 적용:
  - `EmptyWorkspaceView` — quick tip 3개 (단축키 / 패널 / 텔레그램) 상시
  - SettingsView Claude/Codex CLI 헤더에 i 아이콘
  - ChatToolbar agent picker 옆 i 아이콘
  - DiffView 빈 상태 EmptyStateHint + git 미초기화 안내 InlineHint
  - DiffView summary header HelpHint
  - WorkspaceDeliverySheet 전체 (LabelWithHint + InlineHint)

**2. M4 Delivery Loop (자동 build/test/fix)**:
- `Sources/YuminaiCore/DeliveryConfig.swift` (신규)
  - `DeliveryConfig { buildCommand?, testCommand?, lintCommand?, autoRunOnTurnComplete, autoFeedFailureToAgent, maxAttempts=3, timeoutSeconds=300 }`
  - `DeliveryResult { id, kind, command, exitCode, stdout, stderr, durationMs, attempt, timedOut }` — `failurePromptPrefix()`로 다음 turn에 prepend할 텍스트 생성
  - Aider 패턴: test 우선 → 성공 시 lint 추가, 실패 시 lint skip
- `Sources/YuminaiApp/DeliveryRunner.swift` (신규) — actor
  - `runIfConfigured(workspace:trigger:)` — autoRunOnTurnComplete 분기
  - `runOnce(workspace:kind:command:)` — 사용자 수동
  - `/bin/zsh -lc "<cmd>"` (login shell, 사용자 환경 상속)
  - **Devin step budget** — maxAttempts hard cap, 초과 시 escalation 메시지
  - **timeout watchdog** — SIGTERM → 0.5s → SIGKILL
  - readability handler + ConcurrentStringBuffer (thread-safe stdout/stderr capture)
  - 재진입 방지 (workspace.id mutex)
- `Sources/YuminaiCore/Workspace.swift` 확장
  - `deliveryConfig: DeliveryConfig` 필드 + `with(deliveryConfig:)` 불변 update
- `Sources/YuminaiPersistence/WorkspaceModel.swift` 확장
  - `deliveryConfigJSON: Data?` 컬럼 (JSON 직렬화, nil → .disabled fallback, 마이그레이션 호환)
- `Sources/YuminaiApp/AppModel.swift`
  - `deliveryResults: [DeliveryResult]` published (max 10개 누적)
  - `isDeliveryRunning` / `pendingFailureFeedback`
  - `handle(.completed)` hook — exit==0 + autoRunOnTurnComplete면 `maybeRunDelivery`
  - `sendMessage()` hook — `pendingFailureFeedback`이 있으면 prompt 앞에 prepend (소극적 fix loop)
  - `runDelivery(kind:)` / `clearDeliveryResults()` / `updateDeliveryConfig(_:)` 액션
  - Telegram bridge에도 결과 알림 (✅ test — exit 0, 1.2s 형식)
- `Sources/YuminaiApp/WorkspaceDeliverySheet.swift` (신규) — 580×540 모달
  - 명령 3개 input + 정책 toggle + Stepper (max-attempts 1~10, timeout 30~1800초)
  - 모든 라벨에 LabelWithHint
  - 도움말 섹션에 InlineHint (tip + info)
- `Sources/YuminaiUI/DeliveryResultsView.swift` (신규)
  - Inspector "변경" 탭 하단 (VSplitView)
  - run buttons (test/build/lint) — 명령 미설정 시 disabled
  - 결과 row: status icon + kind + command + duration + attempt# + chevron
  - 클릭 → expand → stdout/stderr (160pt 스크롤 + textSelection)
  - timeout은 별도 InlineHint로 안내
  - 빈 상태 EmptyStateHint (config 미설정 / 결과 없음 분기)
  - 톱니 → WorkspaceDeliverySheet 호출
- `Sources/YuminaiUI/SidebarView.swift` 확장
  - 워크스페이스 우클릭 메뉴에 "Delivery 자동화 설정…" 추가

**테스트 8 신규**:
- DeliveryConfigTests (3): defaults / hasAnyCommand / Codable round-trip
- DeliveryResultPromptTests (5): failure prompt / 타임아웃 / stdout fallback / 50줄 truncate / 짧은 텍스트 그대로

**검증**: build 3.2s + clean rebuild OK, test 152/152 (144→152, +8 신규)

알려진 한계:
- Test → Lint 순서 고정 (커스텀 순서 X) — v0.5
- 자동 fix는 다음 turn에 prepend만 — agent가 먼저 응답하고 사용자가 새 메시지를 보낼 때 작동 (즉시 새 turn spawn은 안 함)
- 빌드는 자동 trigger 안 됨 (수동만) — 빌드는 보통 오래 걸려서 의도적 제외, v0.5에서 옵션 추가 검토
- Block 그룹화 (Warp UX, M5.b) — 시간상 Phase B에서 보류, v0.4 후속에 추가

### Added — v0.4 Phase A: Diff Review + Embedded Terminal (ADR-028)

사용자: "권고 사항 기준으로 구현 진행해 줘" — 83_NEXT_ROUND_PLAN의 권고 default 채택.

Phase A는 v0.4 라운드의 첫 단계. M3 (diff review) + M5.a (basic terminal) 통합 구현.

**M5.a — 임베드 터미널 (SwiftTerm)**:
- 두 번째 외부 SPM 의존성 도입 — `SwiftTerm` (Miguel de Icaza, 1.4k stars, MIT)
- ADR-021 외부 의존성 정책 변경 — wrapping으로 lock-in 완화 (TerminalPane이 SwiftTerm 직접 노출 X)
- `Sources/YuminaiUI/TerminalPane.swift` — `LocalProcessTerminalView` NSViewRepresentable wrap
  - 워크스페이스 디렉토리에서 `$SHELL --login` spawn
  - 시작 직후 `cd <workspace>` + `clear` 자동
  - workingDirectory 변경 시 자동 cd
  - ANSI 256색 + processTerminated callback (M4 delivery loop 의존성)
- ChatToolbar에 ⌘⌥T toggle 버튼 (`terminal` icon)
- RootView VSplitView로 chat 위/터미널 아래 분할

**M3 — Diff Review UI (git-as-source-of-truth)**:
- `Sources/YuminaiCore/GitRunner.swift` — actor + ProcessResult + GitError + ChangedFile 모델
  - `ProcessRun` typealias 주입 → mock 가능
  - `parsePorcelain(_)` static — `git status --porcelain=v1 -z` NUL-separated 파싱
  - `currentHeadSha()` / `changedFiles()` / `diff()` / `revert(paths:)` / `revertAll()`
  - status 인식: modified / added / deleted / renamed / copied / untracked
- `Sources/YuminaiApp/CheckpointManager.swift` — actor, agent turn 단위 checkpoint
  - `beginTurn(workspace:)` — HEAD SHA 기록 (git 저장소 아니면 silent no-op)
  - `endTurn(workspace:)` — changedFiles + unified diff 캡처
  - `acceptAll()` / `rejectAll(workspace:)` / `rejectPaths(_:workspace:)`
  - 정책 (사용자 권고: manual): 자동 commit X / 자동 reject X / 사용자 명시적 액션만
- `Sources/YuminaiUI/DiffView.swift` — `DiffReviewView` SwiftUI
  - Summary header (N개 파일 + 모두 적용 / 모두 원복)
  - File list (status badge + path + 각 파일 reject 버튼)
  - Unified diff viewer (+ 녹색 / − 빨강 / hunk header surfaceHi / context 일반)
  - `extractHunks(from:path:)` — `diff --git` 헤더 기준 file별 라인 추출
  - `lineKind(_:)` static — added/removed/hunkHeader/context 분류
- `InspectorTab` enum에 `.changes` case 추가 (icon: arrow.triangle.2.circlepath)
- AppModel:
  - `pendingChanges: [ChangedFile]` + `pendingDiff: String` published state
  - `currentWorkspace` computed
  - `sendMessage()` hook — turn 시작 시 `checkpointManager.beginTurn`
  - `handle(.completed)` hook — turn 종료 시 endTurn + state 갱신
  - `acceptAllChanges()` / `rejectAllChanges()` / `rejectPaths(_)` 액션

**테스트** (17 신규):
- GitRunnerPorcelainTests (6): single modified / untracked ?? / 여러 파일 / renamed old-path skip / 빈 입력 / 한글 라벨
- GitRunnerMockTests (1): mock으로 changedFiles 호출 시 git status 인자 전달
- DiffLineKindTests (6): added/removed/hunk header/diff meta/context/empty
- DiffExtractHunksTests (4): 단일 파일 / 여러 파일 중 특정만 / 매칭 없음 / 빈 diff

**검증**: build OK (SwiftTerm dependency resolve 22s 후 4-9s incremental), test 144/144 (127→144, +17 신규)

알려진 한계 (Phase B/D에서 처리):
- Diff editable X (Cline SOTA지만 SwiftUI 비용 큼, v0.5)
- 자동 commit 정책 X (사용자 권고: manual, hybrid v0.5)
- TerminalPane은 작업 디렉토리 변경 외 추가 customization X (block 그룹화 = M5.b/Phase B)
- diff 파일 경로에 quote 없는 매칭 — 한글/공백 path는 `extractHunks`가 놓칠 수 있음 (실측 후 정밀화)
- VaultWatcher는 .md 한정 — 일반 dir watcher (M3 의존성) 추가 필요할 수 있음 (현재 turn 종료 시 git status로 충분)

### Added — 멀티 에이전트 기반 + Codex CLI 통합 + cokacdir chat label (ADR-026)

사용자 요청 (3가지):
1. "탤래그램의 그룹챗인지 개인챗인지 어떤 거랑 연결할지 숫자여서 알기 어려워"
2. "코덱스 cli도 연결해주고"
3. "안티그래비티처럼 하나의 컨택스트와 프로젝트 폴더 안에서 다양한 에이전트들이 유기적으로 협업할 수 있는 시스템"

**1. cokacdir chat label 친화 표시**
- `CokacdirChatInspector` (YuminaiTelegram) — `~/.cokacdir/group_chat/<chat_id>.jsonl` 파싱
- chat 종류 추정:
  - positive id == ownerUserId → "내 1:1 채팅"
  - positive id ≠ owner → "1:1 — <이름>"
  - negative id → "그룹 — <봇/사람 N개>" (jsonl에서 bot_display_name + from 추출)
- `CokacdirChatLabel { chatId, kind, title, participantNames }`
- `CokacdirImportSheet`의 chat chip → row UI로 교체 (icon + 친화 title + chat_id mono small + "N명 활동" hint + 선택 ✓)

**2. Codex CLI 통합**
- `Sources/YuminaiClaudeAdapter/LiveCodexAdapter.swift` (신규)
  - `codex exec --json -C <dir>` (initial) / `codex exec resume <session-id> --json -C <dir>` (subsequent)
  - **Claude와 다른 모델**: turn마다 새 프로세스 (Claude는 long-lived stdin/stdout)
  - `LiveCodexStreamSession` actor — events 스트림은 워크스페이스 lifetime 동안 유지, turn마다 spawn → completed
  - session_id 자동 추출 + 다음 send에서 resume
  - prompt는 stdin으로 전달 (codex 기본 stdin 입력 모드)
- `CodexJSONLParser` actor — defensive JSONL 파싱
  - 알려진 type: agent_message / tool_call / tool_result / usage / session_started
  - 알 수 없는 type: `[codex <type>]` prefix로 raw forward (디버깅 가능)
  - non-JSON: raw text fallback
- `AppPreferences.codexBinaryPath` + `detectCodexBinaryPath()` 자동 감지
- SettingsView 일반 탭에 Codex CLI section (경로 + 찾아보기 + 감지 상태)

**3. 멀티 에이전트 시스템 기반 (Antigravity-style 1단계)**
- `AgentKind` enum (claude/codex) — `displayName`/`shortLabel`/`icon`/`hint`
- `Workspace.agentKind: AgentKind` — 워크스페이스 단위 에이전트 + `with(agentKind:)` 불변 갱신
- `WorkspaceModel.agentKindRaw: String?` — SwiftData 컬럼 추가, nil → .default(claude) fallback (마이그레이션 호환)
- `AppModel`:
  - `codexAdapter: (any ClaudeAdapter)?` — codex 미설치면 nil
  - `adapter(for: workspace)` — agentKind 기반 dispatch (codex nil이면 claude로 fallback)
  - `activeAdapter` / `codexAvailable` computed
  - `setActiveAgentKind(_ kind:)` — workspace 갱신 + 영속 + 즉시 세션 재spawn
  - `selectCodexBinary()` — NSOpenPanel
  - `spawn`/`teardownCurrentSession`/`updateActiveSettings`/`cancelStream` 모두 `activeAdapter`/`adapter(for:)` 사용
- `ChatToolbar` — agent picker (PickerMenu) Breadcrumb 옆 inline
  - 현재 에이전트 icon + name + chevron, accentMuted bg
  - Menu: Claude/Codex 선택, 비설치 항목은 disabled + "codex CLI 미감지" hint
- `RootView` — `currentAgentKind` computed + Toolbar/AppModel 연결

**같은 프로젝트 폴더, 다른 에이전트** — 두 에이전트 모두 `workspace.directoryPath`를 working dir로 사용. 파일 시스템이 자연스러운 공유 컨텍스트. 사용자가 toolbar에서 빠르게 전환 (각 에이전트는 자체 session id로 컨텍스트 유지). 멀티 패널 동시 표시 + 인터-에이전트 메시지 패싱은 v0.4.

**테스트** (18 신규):
- AgentKindTests (3): metadata / Codable / default
- WorkspaceWithAgentKindTests (2): with()의 immutability / default
- CodexJSONLParserTests (8): agent_message / tool_call / tool_result / session_id / usage / non-JSON / unknown type / partial chunk buffering
- CokacdirChatInspectorTests (5): owner direct / negative=group / 봇+사람 추출 / 로그 없음 fallback / dedupe + order

**검증**: build 3.56s, test 127/127 (109→127, +18 신규)

알려진 한계:
- Codex JSONL 출력 schema는 실제 codex CLI에서 검증 필요 (defensive 파싱이지만 unknown type은 raw text로만 forward)
- Codex의 model alias가 Claude와 다름 → Codex는 자체 default 모델 사용 (`~/.codex/config.toml` 우선)
- 워크스페이스에 1 에이전트 활성 — 멀티 패널 (Claude + Codex 동시) 미구현 (v0.4)
- 인터-에이전트 메시지 패싱 미구현 (v0.4) — 현재는 파일 시스템 공유로만 협업
- ChatBox UI에 어떤 에이전트가 응답했는지 표시 X (메시지 메타데이터 추가는 v0.4)
- Codex의 stdin prompt 형식이 Claude와 다를 수 있음 (예: 종료 처리 타이밍)

### Added — 텔레그램 단일 세션 양방향 제어 (ADR-025)

사용자 요청: "하나의 세션을 탤래그램에서 제어할 수 있도록 설계해 줘"

워크스페이스 1개를 텔레그램 챗에 bind해서 양방향 제어 — 텔레그램에서 메시지 보내면 bound 세션의 Claude로 전달, Claude 응답은 chunk 단위로 텔레그램에 forwarding.

**명령어** (Telegram chat에서):
- `/bind <이름>` — 워크스페이스 연결 (이름 부분 매칭)
- `/unbind` — 연결 해제
- `/status` — 현재 상태 (bound/active/streaming/모델/컨텍스트%)
- `/cancel` 또는 `/stop` — 진행 중 turn 중단
- `/list` — 워크스페이스 목록 (✈ = bound)
- `/help` — 도움말
- prefix 없는 텍스트 → bound 세션 입력으로 전송

**구현**:
1. **`TelegramSessionBridge` actor (YuminaiTelegram)** — event → chunked 메시지 변환
   - `notifyTurnStart(userText:)` → "▶ 시작 — workspace\n> preview"
   - `consume(event:)` — ClaudeEvent 분기:
     - `.text` → assistantBuffer에 누적, debounce(800ms) 또는 chunk 크기(3500) 초과 시 flush
     - `.toolCall` → "🔧 name — input 첫 줄 (80자 cap)"
     - `.toolResult(success:false)` → "⚠ 도구 실패"
     - `.completed(exitCode:)` → "✅ 완료 (Ns, M tools)" 또는 "❌ 실패 — exit N"
   - `notifyCancelled()` → "🛑 진행 중 turn 중단됨"
   - `sendNotice(_:)` — 임의 안내 (bind/unbind 알림 등)
   - `chunked(text:maxSize:)` — 줄바꿈 우선 → 공백 우선 분할 (Telegram 4096자 한도 안전 마진)
2. **`YuminaiCommandRouter` 전면 재작성** — `/` prefix 분기 + plain text 라우팅
   - bindCommand: 이름 정확 매칭 → 부분 매칭 폴백
   - statusCommand: AppModel.telegramStatusSnapshot() 호출
   - listCommand: 워크스페이스 목록 + ✈ 표시
   - plain text: bound 워크스페이스 자동 전환 → inputText → sendMessage
3. **`AppPreferences` +3 필드**
   - `telegramBoundWorkspaceId: UUID?`
   - `telegramForwardAssistant: Bool` (기본 true)
   - `telegramForwardToolCalls: Bool` (기본 true)
4. **`AppModel`**
   - `sessionBridge: TelegramSessionBridge?` 라이프사이클 (activate/deactivateTelegram에 통합)
   - `bindTelegramWorkspace(_:)` — preference 영속 + bridge 재구성 + 알림
   - `boundWorkspaceName` computed
   - `telegramStatusSnapshot()` — /status 응답 텍스트
   - `cancelBoundTurn()` — bound 세션 한정 cancelStream + bridge.notifyCancelled
   - `handle(_ event:)`에 `forwardToBridgeIfBound` hook — 활성 워크스페이스가 bound와 일치할 때만 forwarding
   - `sendMessage()`에 turnStart hook
5. **`SidebarView`** — bound 워크스페이스에 ✈ paperplane 아이콘 + 우클릭 "텔레그램에 연결" / "연결 해제"
   - `telegramBoundId: UUID?` + `telegramAvailable: Bool` (token + chatId + enabled 모두 OK일 때) + `onToggleTelegramBind` 콜백
6. **`RootView`** — SidebarView에 새 binding 전달

**격리**: `TelegramSessionBridge`는 `(any TelegramClient)` + `Configuration`만 의존. AppModel이 ClaudeEvent를 forwarding하는 형태로 — bridge가 AppModel 내부를 알 필요 없음.

**테스트**: 14 신규 (chunking 4 + tool summary 3 + event forwarding 7)
- chunking: 단일/줄바꿈 경계/공백 경계/round-trip 보존
- summary: 빈 input/긴 input cap/멀티라인 첫 줄
- forwarding: text flush + ✅완료 / forwardAssistant=false 무시 / toolCall 🔧 prefix / forwardToolCalls=false 무시 / notifyTurnStart ▶ 시작 / notifyCancelled 🛑 / completed exit≠0 ❌

**검증**: build 2.77s, test 108/108 (94→108, +14 신규)

알려진 한계:
- bind는 단 1개 워크스페이스 1개 텔레그램 챗 (멀티 매핑 X)
- Bridge는 raw text를 그대로 보냄 (Markdown은 LiveTelegramBot이 parse_mode=Markdown으로 송신 — 응답이 Markdown 문법 어긋나면 silent drop)
- 도구 결과 본문은 forwarding 안 함 (성공/실패만) — 토큰 비용 폭증 회피
- Telegram 4초 rate limit은 안 다룸 (bridge가 빠르게 flush하면 throttle 가능)
- thinking 이벤트 forwarding 옵션 없음 (필요 시 새 preference 플래그)
- bridge가 message edit 미사용 (chunk마다 새 메시지) — 진행 중 응답 단일 메시지 갱신은 차기

### Changed — cokacdir 봇 import로 통합 방식 교체 (ADR-024 개정)

사용자 정정: "🟢 cokacdir started (v0.4.63) ... 이걸로 확인해서 적용해 줘"

이전 ADR-024(openclaw 위임)은 잘못된 도구 가정으로 폐기. 실제 도구는 [cokacdir](https://cokacdir.cokac.com/) (`/usr/local/bin/cokacdir` 0.4.63) — multi-panel terminal file manager + Telegram bot server. CLI 위임이 아닌 **bot_settings.json 토큰 import** 방식으로 통합 재작성.

**제거**:
- `Sources/YuminaiTelegram/OpenClawTelegramBot.swift` (actor + Detector)
- `Tests/YuminaiTelegramTests/OpenClawTelegramBotTests.swift` (10 tests)
- AppPreferences `telegramUseOpenClaw` / `openClawBinaryPath` / `openClawTelegramTarget` 필드
- AppModel `makeOpenClawBot` / `refreshOpenClawStatus` / `selectOpenClawBinary` / `openClawUIStatus`
- SettingsView `openClawConnectionFields` / segmented picker / status badge

**신규 (cokacdir bot import 방식)**:
1. **`CokacdirImporter` (YuminaiTelegram)** — `~/.cokacdir/workspace/bot_settings.json` 파싱
   - dictionary key = bot hash, value = `{display_name, username, token, owner_user_id, last_sessions: {<chat_id>: <workspace_path>}}`
   - `loadBots()` / `parse(data:)` static
   - 정렬: display_name 알파벳순
   - chat id 정렬: abs 작은 순 (1:1 chat 우선, 그룹/채널 음수 ID 후순)
2. **`CokacdirBot` Sendable struct** — botHash, displayName, username, token, ownerUserId, suggestedChatIds, handle (`@username`)
3. **`CokacdirImportError`** — notFound / readFailed / invalidJSON
4. **`CokacdirImportSheet` (YuminaiApp)** — 540pt 모달
   - 봇 리스트 (BotRow: 라디오 + display name + handle + chat 후보 수)
   - 선택 시 chat id chip 후보 (LazyVGrid, 양수=person/음수=group icon) + 직접 입력 TextField
   - "가져오기" → AppModel.applyCokacdirBot(_:chatId:) → keychain 저장 + telegramChatId 자동 + telegramSourceLabel 기록 + ownerUserId를 allowedUserIds에 자동 추가
5. **AppPreferences `telegramSourceLabel: String?`** — UI에 "토큰 출처: cokacdir — 스튜디오 클로드" 표시용
6. **AppModel** — `cokacdirBots` / `cokacdirImportError` / `showCokacdirImportSheet` state + `loadCokacdirBots()` / `applyCokacdirBot(_:chatId:)` 액션
7. **SettingsView Telegram 탭** — 새 Section "cokacdir 통합" + "열기…" 버튼 + footer로 충돌 안내 ("같은 토큰으로 cokacdir 봇 서버가 실행 중이면 update가 분산됨, Yuminai 사용 중에는 cokacdir 해당 봇을 잠시 끄는 걸 권장")

**보안 메모**: cokacdir의 `bot_settings.json`은 봇 토큰을 평문 저장. import 시 Yuminai keychain에도 저장됨. 사용자가 토큰을 노출 의심하면 BotFather에서 재발급 권장.

**테스트**: 8 신규 (parse 6 + loadBots 2)
- 두 봇 파싱 (실제 cokacdir 형식)
- 알파벳 정렬
- token 없는 항목 무시
- display_name 없으면 hash 앞 8자 fallback
- chat id abs 정렬
- invalid JSON throw
- 파일 없으면 throw
- end-to-end 임시 파일 → parse

**검증**: build 2.07s, test 94/94 (96→94, openclaw 10건 제거 + cokacdir 8건 추가)

알려진 한계:
- cokacdir 봇 서버가 같은 토큰으로 동시 실행 중이면 polling 충돌 (UI 안내만 제공)
- bot_settings.json 형식 변경 시 import 실패 가능 (방어적 파싱이지만 schema는 cokacdir 내부 변경에 종속)
- import는 일회성 — cokacdir에서 토큰 재발급되면 사용자가 다시 import 필요

구현:
1. **`OpenClawTelegramBot` actor (YuminaiTelegram)** — `TelegramClient` 두 번째 구현체
   - `send` → `openclaw message send --channel telegram --target <id> --message <text> --json`
   - `edit` → `openclaw message edit --channel telegram --target <id> --message-id <id> --message <text> --json`
   - `startPolling` → 5초 간격 `openclaw message read --channel telegram --target <id> --after <last> --limit 20 --json`
   - 화이트리스트 (`allowedUserIds`) 적용은 LiveTelegramBot과 동일
   - `ProcessRun` typealias로 process 실행 추상화 → 테스트에서 mock 주입
   - JSON shape 방어적 파싱: `messageId`/`message_id`/`id` + `result`/`data` 중첩 + `messages`/`result`/`data`/`items` 키 모두 시도
2. **`OpenClawDetector` (YuminaiTelegram)** — 설치 + 채널 활성 상태 감지
   - 바이너리 존재 + 실행 가능 확인
   - `openclaw --version`로 버전 추출
   - `openclaw channels list --json` 응답에 "telegram" 포함 여부로 채널 활성 추정
   - `Status { installed, version, telegramActive, message }`
3. **`AppPreferences` 확장**
   - `telegramUseOpenClaw: Bool` (기본 false — 직접 토큰 모드 유지)
   - `openClawBinaryPath: String` (자동 감지 — brew/local 순)
   - `openClawTelegramTarget: String` (`@username` 또는 숫자 chat id)
   - `detectOpenClawBinaryPath()` static
4. **`AppModel` 통합**
   - `activateTelegramIfReady`가 `useOpenClaw` 분기로 `LiveTelegramBot` vs `OpenClawTelegramBot` 선택
   - `makeLiveBot()` / `makeOpenClawBot()` 분리 (단일 책임)
   - `openClawStatus` state + `refreshOpenClawStatus()` (Settings 진입 시 자동 호출)
   - `openClawUIStatus: OpenClawUIStatus?` 변환 property — YuminaiUI가 YuminaiTelegram에 의존하지 않게 격리
   - `selectOpenClawBinary()` — NSOpenPanel
5. **`SettingsView` Telegram 탭 확장**
   - 연결 방식 segmented picker: "Bot 토큰 직접 입력" / "openclaw에 위임"
   - openclaw 모드 시: 경로 + 찾아보기 버튼 + 대상 (@username/chat id) + 상태 badge (✓ 활성 / ⚠ 비활성 / ? 미감지) + 새로고침 버튼
   - footer 친화 안내: "openclaw에 등록된 토큰을 위임 사용해요. Yuminai는 토큰을 직접 보거나 저장하지 않아요."
   - 테스트 메시지 버튼은 모드별 활성 조건 분기

신규 파일:
- `Sources/YuminaiTelegram/OpenClawTelegramBot.swift` — actor + ProcessOutput + OpenClawError + OpenClawDetector
- `Tests/YuminaiTelegramTests/OpenClawTelegramBotTests.swift` — 10 신규 테스트 (send 4 + parse 4 + edit 1 + Detector 1)

확장:
- `AppPreferences` — telegramUseOpenClaw / openClawBinaryPath / openClawTelegramTarget + detectOpenClawBinaryPath()
- `AppModel` — openClawStatus + makeLiveBot/makeOpenClawBot 분리 + refreshOpenClawStatus + selectOpenClawBinary + openClawUIStatus 변환
- `SettingsView` — OpenClawUIStatus struct + openClawConnectionFields + 상태 badge UI + 모드별 conditional rendering
- `YuminaiApp.SettingsContainer` — 신규 callback 2개 + .task로 진입 시 상태 자동 새로고침

알려진 한계 (다음 라운드):
- openclaw `channels add --channel telegram --token <token>`는 Yuminai 안에서 직접 트리거 안 함 (사용자가 별도 셸에서 실행)
- openclaw 채널 비활성 시 적극적 onboarding wizard (ex. "이 명령을 실행하시겠어요?" 확인) 미구현
- 멀티 챗 라우팅 미지원 (openclaw target 1개 가정)
- openclaw 에러 시 retry 정책 단순 (15초 sleep) — exponential backoff 미적용
- openclaw가 송신한 메시지 본문 inline keyboard / media 미지원 (text only)

ADR-024 채택. 검증: build 3.89s, test 96/96 (86→96, +10 신규)

### Added — Parity Round: codex 10 gap 중 7개 + UX polish 3종 (ADR-023)

사용자 요청: "다음 라운드도 전부 기획해서 구현해 줘 이 앱의 퀄리티가 클로드코드 이상의 사용성이 됐다고 자신할 때까지 래퍼런스 조사, 검증, 기획, 구현 반복해"

명세 `docs/design/82_PARITY_ROUND.md` (codex 10 gap 분석 → 7 user feature B1~B7 + 3 polish C1~C3 + scope 외 `pane model`/`diff review`/`embedded preview`/`software delivery loop`/`execution env mobility` 차기 라운드 보존).

구현 (B1~B7, C1~C3):

1. **B1 Wiki link disambiguation** — `ObsidianVault.findNotesByName(_:)` (대소문자 무시 매칭) + `WikiDisambiguationSheet` (480pt 카드, 후보 리스트 + path subtitle + chevron + ESC 취소). AppModel에 `disambigCandidates`/`disambigOriginalName`/`showDisambigSheet` state + `selectDisambigCandidate(_:)`. `openNoteByName`이 다수 매칭 시 sheet 띄움
2. **B2 검색 highlight** — `NoteTreeView.SearchHitRow.highlight(text:query:accent:)` static func — 매칭 substring을 accent color + `.bold` AttributedString으로 변환. 파일명/본문 라인 모두 highlight
3. **B3 노트 임베드 inline preview** — `MarkdownPreprocessor.process(_:noteResolver:)` — embed 발견 + resolver가 본문 반환 시 inline blockquote (`> [Note](url)\n> 첫 5줄`) 생성. resolver nil이면 wiki link로 fallback. `MarkdownViewer`도 `noteResolver` 통과
4. **B4 Split editor mode** — `EditorSplitMode` enum (editor/split/preview, 3-way) + InspectorPanel header에 segmented button. split 모드는 좌측 TextEditor + 우측 MarkdownViewer 동시 표시. AppModel `editorSplitMode` state
5. **B5 노트 CRUD + 휴지통** — `ObsidianVault.createNote(at:title:body:)` (frontmatter 자동 생성, 부모 폴더 자동 mkdir) + `deleteNote(at:)` (vault root의 `.trash/<timestamp>-<filename>`로 이동, 영구 삭제 X). `VaultError.alreadyExists` 추가. `CreateNoteSheet` (filename + title 옵션 + 폴더 옵션, .md 확장자 자동) + InspectorPanel "새 노트" 버튼 + 휴지통 아이콘 (현재 노트 삭제)
6. **B6 즐겨찾기 / 최근 노트** — AppModel `favoriteNotePaths: Set<String>` (UserDefaults 영속) + `recentNotePaths: [String]` (max 10) + `toggleFavorite(_:)` + `pushRecent(_:)`. InspectorPanel 노트 탭 상단에 quick access section (별 아이콘 toggle + 최근 라인). 별 표시 버튼이 노트 헤더에 inline
7. **B7 In-memory body cache** — `ObsidianVault.bodyCache: [String: String]` 추가. `searchFullText`이 캐시 우선, 미스 시 fill. watcher 변경 path만 `invalidateCache(paths:)` (granular). `cachedBodyCount` / `clearCache` 노출. AppModel.handleVaultChanges가 watcher 콜백에 cache invalidation hook 연결

UX polish (C1~C3):

- **C1 ⌘/ 단축키 도움말 sheet** — `ShortcutHelpSheet` (글로벌/채팅/노트 카테고리 + ShortcutKeyBadge 키캡 시각화) + RootView `helpHotkey` (⌘/) + AppModel `showShortcutHelp`
- **C2 InspectorPanel vault action bar** — "새 노트" primary button + 검색 placeholder 친화화
- **C3 quick access section** — 즐겨찾기/최근 노트 row UI (`QuickNoteRow` + 빈 상태 안내)

신규 파일:
- `Sources/YuminaiUI/EditorSplitMode.swift` — split mode enum
- `Sources/YuminaiUI/WikiDisambiguationSheet.swift` — 동명 노트 선택 sheet
- `Sources/YuminaiUI/CreateNoteSheet.swift` — 노트 생성 form sheet
- `Sources/YuminaiUI/ShortcutHelpSheet.swift` — ⌘/ 단축키 도움말
- `Tests/YuminaiObsidianTests/ParityRoundTests.swift` — 14 신규 (B1 4건 + B5 4+2건 + B7 3건 + EditorSplitMode 1건)

확장:
- `ObsidianVault` — bodyCache + searchFullText 캐시 통합 + invalidateCache/clearCache/cachedBodyCount + createNote/deleteNote + findNotesByName + VaultError.alreadyExists + nonisolated rootURL
- `MarkdownPreprocessor` — process(_:noteResolver:) (선택적 resolver) + processEmbeds inline blockquote 생성
- `MarkdownViewer` — noteResolver 파라미터 통과
- `NoteTreeView` — SearchHitRow query 받아 highlight, static highlight 헬퍼
- `InspectorPanel` — 25+ params로 전면 재작성: vaultActionBar / quickAccessSection / splitEditor / splitToggle / favoriteToggle / deleteCurrentNote / createNote callback
- `AppModel` — disambigCandidates / disambigOriginalName / showDisambigSheet / editorSplitMode / showCreateNoteSheet / favoriteNotePaths / recentNotePaths / showShortcutHelp + toggleFavorite/isFavorite/persistFavorites/loadFavorites + selectDisambigCandidate/createNote/deleteNote + static notePreviewBody(name:vaultRoot:) (nonisolated, actor isolation 회피)
- `RootView` — 3 신규 sheet (WikiDisambiguationSheet/CreateNoteSheet/ShortcutHelpSheet) + helpHotkey + InspectorPanel 25+ args binding + noteResolver wiring

Bugfix (수반):
- `ObsidianVault.rootURL`을 `nonisolated let`으로 — MainActor에서 안전 접근 (immutable이라 race 무관)
- `notePreviewBody`를 static + URL 파라미터로 — actor-isolated obsidianVault 접근 회피, MarkdownViewer resolver closure가 nonisolated context에서 호출 가능
- `Color.adaptive(light:dark:)` static func로 rename — MarkdownUI Color(light:dark:) init과 ambiguity 해소

ADR-023 채택. 검증: build 3.23s + test 86/86 (72→86, +14 신규), CRUD/cache/disambig 모두 unit 검증

### Added — 노트 기능 7종 일괄 (ADR-022)

사용자 요청: "다음 라운드 항목들 하나하나 상세하게 논리적으로 기획해서 구현하고 전부 마친 후에 uiux와 반응형, 단위 기능 정상 작동 테스트까지"

명세 `docs/design/81_NOTES_ENHANCEMENTS.md` (의존성 순서대로 7기능 + UX/반응형 검증 매트릭스).

구현:
1. **Frontmatter 표시 (NoteHeaderView)** — title, tags pill (accent muted bg), 기타 메타 row. frontmatter 비어있으면 미표시
2. **VaultWatcher (FSEventStream)** — 800ms debounce + AsyncStream<Set<String>>. AppModel이 구독해서 트리 자동 reload + 현재 노트가 변경되면 reload (편집 모드 시 충돌 banner)
3. **본문 검색 (searchFullText)** — lazy concurrent file read + 매칭 라인 컨텍스트 추출. NoteTreeView에 "본문도 검색" toggle. SearchHitRow에 매칭 line 미리보기. 250ms debounce search task
4. **Wiki link `[[Page]]`** — MarkdownPreprocessor가 `[Page](yuminai-note://Page)`로 변환. swift-markdown-ui가 일반 link 렌더, OpenURLAction이 yuminai-note scheme 인터셉트 → AppModel.openNoteByName(이름→path 매칭)
5. **이미지 임베드 `![[image.png]]`** — vaultRoot 기준 절대 file URL로 변환. swift-markdown-ui NetworkImage가 로드. 노트 임베드 `![[Note]]`는 wiki link로 fallback (v0.3 별도)
6. **편집 모드** — AppModel.isEditingNote / editingDraft / noteIsDirty. InspectorPanel 헤더에 보기/편집 segmented + ⌘S 저장 + 저장 안 됨 ● 표시. 외부 변경 감지 시 warning banner + "다시 불러오기"
7. **@note 채팅 주입** — NotePickerPopover (320×360) + Composer 📓 버튼 (Vault 활성 시만 표시). 선택 시 attachNoteByPath → 기존 attachedFiles 메커니즘 재사용 (`@<path>` mention prepend)

신규 파일:
- `Sources/YuminaiObsidian/VaultWatcher.swift` — FSEventStream wrapper
- `Sources/YuminaiObsidian/MarkdownPreprocessor.swift` — wiki + embed
- `Sources/YuminaiUI/NoteHeaderView.swift` — frontmatter UI
- `Sources/YuminaiUI/NotePickerPopover.swift`
- `Tests/YuminaiObsidianTests/MarkdownPreprocessorTests.swift` (10 tests)
- `Tests/YuminaiObsidianTests/SearchAndWriteTests.swift` (5 tests)

확장:
- `ObsidianVault` — searchFullText / write
- `NoteTreeView` — fullTextEnabled toggle + SearchHitRow + 매칭 컨텍스트
- `MarkdownViewer` — vaultRoot + onWikiLink (URL handler)
- `InspectorPanel` — 외부 변경 banner + 편집 모드 + modeToggle (segmented)
- `Composer` — onAttachNote (📓 버튼) — Vault 활성 시만 표시
- `AppModel` — 모든 새 기능의 lifecycle + state (15+ method/property 추가)
- `RootView` — InspectorPanel + NotePickerPopover binding

기타 fix:
- ObsidianVault.rootURL → `nonisolated let` (MainActor에서 접근 가능)
- YuminaiUI → YuminaiObsidian 의존성 추가

ADR-022 채택. 검증: build 2.63s, test 72/72 (57→72, +15 신규), run 정상

### Added — Obsidian Vault 통합 + Notion급 마크다운 뷰어 (ADR-021)

사용자 요청: "옵시디언 cli를 연동해서 마크다운 파일을 노션, 옵시디언급 퀄리티로 볼 수 있는 뷰어"

처리:
1. **명세서 docs/design/80_OBSIDIAN_VIEWER.md** 작성 — Vault 접근, 라이브러리 선정 근거, UI 통합
2. **swift-markdown-ui 외부 의존성 도입 (ADR-021)**:
   - 첫 외부 SPM 의존성. 자체 작성 비현실 (100시간+) vs 라이브러리 (잘 검증, MIT)
   - swift-markdown-ui 2.4.1 + NetworkImage 6.0.1 + swift-cmark 0.7.1
   - `MarkdownViewer` wrapping으로 lock-in 완화 (라이브러리 교체 시 한 곳만)
3. **YuminaiObsidian 신규 모듈** (`Sources/YuminaiObsidian/`):
   - `ObsidianVault` actor — 파일 시스템 직접 접근
     - `tree()` — `.md` + 폴더 트리 인덱싱 (`.obsidian`/`.trash` 자동 제외)
     - `read(_:)` — 노트 본문 + frontmatter 파싱
     - `search(_:)` — 파일명 매칭 (본문 검색은 v0.3)
     - `openInObsidian(_:)` — `obsidian://` URL scheme로 Obsidian 앱에서 열기
   - `Note` / `VaultNode` (folder/note) Sendable 모델
   - `splitFrontmatter` — `---\nyaml\n---` 분리
4. **MarkdownViewer (YuminaiUI)** — Notion급 룩:
   - h1 (24, bold + 하단 divider) / h2 (20) / h3 (17) / h4 (15)
   - 본문 14, lineSpacing 4
   - 인라인 code: `inlineCode` bg + mono 13
   - 코드 블록: surface bg + horizontal scroll + 우상단 language 라벨
   - 인용: 좌측 3px accent bar + surface bg + 둥근 모서리
   - task list: 체크박스 (accent 색)
   - 테이블: 교차 행 색 + border
   - 링크: accent 색 + underline
5. **NoteTreeView (YuminaiUI)**:
   - 검색창 (실시간 필터)
   - 트리 모드 (folder expand/collapse) + 검색 모드 (flat)
   - 친화 안내 ("‘query’와 매칭되는 노트가 없어요" / "이 Vault에 .md 노트가 없네요")
   - hover/selected 색
6. **InspectorPanel (YuminaiUI)** — Tab 구조:
   - 좌상단 segmented tab (`컨텍스트 | 노트`) + 활성 시 하단 2px accent border
   - 컨텍스트 탭: 기존 ContextInspector
   - 노트 탭: Vault 미설정 시 안내 + "설정 열기" 버튼 / 트리 / 노트 본문 (선택 시)
   - 노트 본문 위 헤더: 좌측 ← 트리 / 우측 Obsidian 앱에서 열기 (↗)
7. **AppModel + RootView 통합**:
   - `inspectorTab`, `obsidianVault`, `vaultTree`, `selectedNote`, `noteSearchQuery` state
   - `setupObsidianVault()` — preferences 변경 시 vault 재구성 (자동 호출)
   - `loadVaultTree() / selectNote(at:) / clearSelectedNote() / openCurrentNoteInObsidian()`
   - `bootstrap()` 끝에 setupObsidianVault 호출
   - RootView에서 ContextInspector → InspectorPanel 교체
8. 테스트 5건 신규 (frontmatter 파싱 / nonexistent vault / 임시 vault 인덱싱 / 숨김 폴더 제외)

ADR-021 채택. 검증: build 2.31s, test 57/57 (52→57), run 정상.

### Changed/Added — Settings macOS 네이티브 정렬 + 첨부 파일 기능 (ADR-020)

사용자 보고: "설정 팝업 깨진 layout (라벨/컨트롤 우측 몰림, helper 잘림). 맥 네이티브 설정 메뉴 퀄리티로 정렬." + "첨부파일 업로드 동작화 + 안내 문구"

처리:
1. **SettingsView 전면 재구성**:
   - `.formStyle(.grouped)` macOS 표준 — System Settings와 동일한 GroupBox 룩
   - `LabeledContent` 사용 — 좌측 라벨 + 우측 컨트롤 자동 정렬
   - 모든 Section은 `Section { } header: { } footer: { }` 명시적 형식 (macOS 26 SwiftUI ambiguity 회피)
   - 윈도우 minWidth 640 → idealWidth 720 → maxWidth 880, height 480~760
   - 라벨 일관 한글 ("Permission mode" → "권한 모드", "Effort" → "강도")
   - Toggle에 helper 텍스트 inline VStack 패턴 (시스템 룩)
   - Stepper에 `+2pt` 같은 monospaced digit 표시
   - SecretField는 inline status badge (✓ 준비 완료 / ⚠ 에러 / 아직 안 넣음) + "바꾸기/넣기/지우기" 버튼

2. **첨부 파일 기능 동작화**:
   - `AppModel.attachedFiles: [URL]` state 추가
   - `openAttachmentPicker()` — NSOpenPanel (파일+폴더, 다중 선택, "Claude가 함께 살펴볼 파일이나 폴더를 선택하세요" 안내)
   - `removeAttachment(_:)` / `clearAttachments()`
   - `sendMessage()` — 첨부 있으면 prompt 앞에 `다음 파일이 첨부됐어요:\n@<path>` 형식 prepend (Claude의 `@` mention 구문, 자동 Read 도구 호출)
   - 송신 후 attachedFiles 자동 클리어
   - **Composer**:
     - `attachedFiles` + `onRemoveAttachment` + `onClearAttachments` parameter 추가
     - 입력창 위에 horizontal scroll로 chips 표시
     - 각 chip: 파일/폴더 icon (확장자 추정) + 이름 + ✕ 버튼 + hover 시 ✕가 danger 색
     - chip hover bg 변화 + tooltip은 절대 경로
     - 첨부 2개+ 시 "모두 지우기" 버튼
     - attachment 버튼 tooltip: "파일이나 폴더를 첨부합니다. Claude가 자동으로 살펴봐요."

ADR-020 채택. 검증: build 2.36s, test 52/52, run 정상.

### Changed — 브랜드 컬러 = AG2R 시안 + Picker 전면 재구성 (ADR-019)

사용자 답변: ar2r → AG2R La Mondiale 자전거 팀 → 시그니처 시안. 추가 — "설정 버튼/모델 변경 스위치 인터랙션 작동 안 함, Claude Code 같은 dropdown 디자인"

처리:
1. **Theme.Brand.accent → 밝은 시안** (`#22C8E0`, AG2R 톤). accentDeep `#0FA8C0`, accentMuted dark cyan `#0A2128`. Brand 한 곳만 교체로 전체 자동 반영
2. **Settings 호출 fix** — `NSApp.sendAction("showSettingsWindow:")` → `@Environment(\.openSettings)` (SwiftUI 14+ 표준)
3. **PickerMenu 신규 컴포넌트** — Claude Code 데스크탑 dropdown 룩 그대로:
   - native `.popover()` 기반 (안정적 위치)
   - `PickerSection` (title + shortcutHint + items)
   - `PickerItem` (label + subtitle + isSelected + shortcutHint)
   - `ShortcutKeyBadge` (`[⇧] [⌘] [I]` 같은 cap 디자인)
   - 항목 hover bg + ✓ 마커 + 우측 단축키 숫자
4. **ModelPicker/EffortPicker/ModePicker** 모두 PickerMenu로 교체:
   - 모델: 5개 모델 + ✓ + 1~5 단축키 hint + ⇧⌘M section hint
   - 권한 모드: 6개 모드 + 부제 (shortDescription) + 선택 ✓
   - 작업량: 4단계 + 부제 + ⇧⌘E section hint
5. `PickerTriggerLabel` — Composer footer의 inline button (`label · value ▾`), hover 시 chevron이 accent 색

ADR-019 채택. 검증: build 2.49s, test 52/52, run 정상.

### Added — 브랜딩 + 인터랙션 + UX 라이팅 (ADR-018, 2026-05-01)

사용자 요청: "각 버튼 인터랙션·애니메이션 + 모든 설정/버튼 동작화 + UX 라이팅 한글 친화 + ar2r 자전거 팀 컬러로 브랜딩"

진행:
1. **ar2r 조사** — codex CLI로 web search, 공개 웹에서 자전거 팀 식별 불가 → fallback 자전거 저지 표준 팔레트 사용 (사용자 답변 시 토큰 한 곳만 교체)
2. **브랜드 시스템** — `Theme.Brand` namespace 신규 (`primary` deep navy `#0E2A47`, `accent` orange-red `#FF5A36`, `accentDeep`, `accentMuted`, `accentBorder`). `Theme.Color.accent`/`accentMuted`/`accentBorder`/`accentHover`/`liveDot` 모두 Brand로 위임 → 한 곳 변경으로 전체 반영
3. **인터랙션 강화**:
   - `PressedScaleStyle` (모든 버튼 0.97 scale on press, 80ms easeOut)
   - `PrimaryButtonStyle` (CTA hover 1.02 scale + brightness +0.04)
   - `FlatButton` 모든 variant에 hover bg 토큰 (`bgHover` 추가)
   - `IconButton` press 0.92 scale + hover bg 100ms 애니메이션
   - `SendButton` hover/press 별도 애니, "보내기"/"중단" 한글 + tooltip
   - `WorkspaceItemRow` hover 시 `⌘N` 단축키 hint 표시 (10개 미만)
4. **UX 라이팅 한글 친화 (전수 패스)**:
   - Composer placeholder → "무엇을 도와드릴까요? `/`로 명령, `@`로 노트"
   - Composer "자동 모드" → "응답 중", attachment tooltip → "파일 첨부는 곧 지원됩니다"
   - Sidebar "Settings" → "설정", "Workspaces" → "워크스페이스"
   - Sidebar empty → "아직 시작한 작업이 없네요. 위 ‘+ 새 워크스페이스’로 시작해보세요."
   - UpdateCard → "업데이트 준비 / 새 버전이 도착했어요"
   - WorkspaceItemRow 우클릭 "삭제" → "지우기"
   - ChatView empty → "여기서 새 작업을 시작해보세요." + 단축키 힌트 친화화
   - ChatToolbar streaming "streaming" → "응답 중"
   - ChatToolbar inspector tooltip → "창을 더 넓혀주세요 (1080px↑)"
   - ContextInspector 섹션 → "활성/컨텍스트/토큰/비용/최근 도구" + key 한글
   - UsageDashboard 제목/섹션 한글 ("이번 세션", "앱 실행 후 누적", "모델 가격")
   - CreateWorkspaceSheet 전수 한글 ("어떤 폴더에서 시작할까요?", "이 폴더로", "만들기")
   - RootView empty → "어떤 작업으로 시작할까요?" + 부제
   - Error alert "오류" → "잠깐, 문제가 생겼어요" / "확인" → "알겠어요"
5. **미동작 버튼 wiring**:
   - Breadcrumb 클릭 → 워크스페이스 switcher menu (체크 마크 + "+ 새 워크스페이스")
   - ⌘1~9 → 워크스페이스 빠른 전환 (invisible button 9개)
   - Sidebar 워크스페이스 hover 시 단축키 hint 표시
6. **`docs/design/70_BRANDING_AND_INTERACTION.md`** 작성 (ar2r 조사 결과 + 브랜드 시스템 + 인터랙션 매트릭스 + UX 라이팅 표 + 동작 명세)

ADR-018 채택. 사용자 답변(ar2r 정확한 컬러) 시 Brand namespace 한 곳만 교체.

검증: build 1.5s, test 52/52, run 정상

### Added — 반응형 Layout 시스템 (ADR-017, 2026-05-01)

사용자 요청: "반응형부터 명확하게 구현"

- `LayoutMode` enum (compact/medium/regular/wide) — Theme.Layout 외부 namespace
- `Theme.Layout` 신규 토큰: `breakpointCompact (760)`, `breakpointMedium (1080)`, `breakpointWide (1440)`, `minWindowWidth (600)`, `minWindowHeight (480)`, `minChatWidth (520)`
- `Theme.Layout.mode(for:)` 정적 함수 — 너비 → mode
- `LayoutMode.allowsInspector` / `sidebarIsOverlay` computed
- **RootView 반응형**: GeometryReader로 윈도우 크기 추적, mode 변경 시 `handleSizeChange` 자동 정리
- **User intent 영속**: `@AppStorage("yuminai.sidebar.userVisible")` / `"yuminai.inspector.userVisible")` — 다음 실행 복원
- **Sidebar overlay**: compact 모드에서 toggle 시 콘텐츠 위에 popup + semi-transparent backdrop 클릭으로 닫힘
- **Inspector 자동 hide**: medium/compact에서 사용자 의도와 무관하게 강제 hidden, 다시 regular+로 가면 사용자 의도 복원
- **Toolbar 적응**: inspector 버튼이 mode에 따라 disabled (조명 ↓ + tooltip), layoutBadge로 "compact"/"medium" 모드 표시
- 신규 테스트 3건 (LayoutMode boundaries / inspector allowance / sidebar overlay)

검증: `swift build` 2.53s, `swift test` 52/52 통과, `swift run YuminaiApp` 윈도우 정상

### Redesigned v3 (Claude Code 데스크탑 룩 — codex 검증 반영, 2026-05-01 심야)

사용자 피드백 — "이 정도 디자인 퀄리티 (Claude Code 데스크탑 스크린샷)로 / 냉정 조사 / 무한 iteration / 기획 검증 후 구현"

처리 절차:
1. 스크린샷 정밀 분석 → 색/타이포/spacing/component 상세 추출
2. 외부 레퍼런스 검증 (Anthropic Console, Linear, Vercel, shadcn dark, Raycast)
3. `docs/design/60_UI_DESIGN_SPEC.md` v2 작성
4. **codex CLI 0.116.0으로 명세서 review** → 9건 critical 이슈 도출 (ADR-016)
5. 명세서 v3로 보완 (warm 톤, 대비 ↑, palette 단순화, Composer 핵심 컨트롤, interaction 표, SwiftUI 함정 회피)
6. 구현

신규/재작성 컴포넌트:
- **Theme v3**: warm 다크 토큰 (R>B), 4단 hierarchy (bgSidebar/bg/surface/surfaceHi/elevated/inlineCode), sans+mono 분리, monoSmall/monoStat 추가, Layout 토큰 정밀 정의 (sidebarWidth/sidebarItemHeight/composerOuterPadding 등), CenteredContent + SelectedBar modifier
- **FlatComponents v3**: FlatButton 5 variants × 4 sizes, IconButton (hover bg), SendButton (idle/streaming/disabled 3-state), PulseDot (streaming 표시), FlatSection/FlatRow/FlatTextField/FlatToggle/FlatHDivider/FlatVDivider
- **SidebarView v3**: top header (collapse + search) → primary action ("+ 새 워크스페이스") → menu ("Settings") → group "Workspaces" → WorkspaceItemRow (○/● dot + selected 좌측 2px bar) → UpdateCard → BottomUserCard
- **MessageBubble v3**: role 분기 — UserMessageBlock (warm muted bg + 2px accent bar), AssistantMessageBlock (박스 없음 + role 라벨), ToolMessageBlock (작은 ● + 작은 텍스트), SystemMessageBlock (centered)
- **Composer (신규)**: git/diff meta row → TextEditor + placeholder → footer (model/mode/effort picker + attachment + 자동 모드 + SendButton)
- **ChatToolbar v3**: sidebar toggle + Breadcrumb (folder + name + chevron) + streaming badge + dashboard/inspector buttons
- **ChatStatusBar v3**: ContextGauge (50/75% 임계 색) | msg/in/out/cache | cost
- **ContextInspector v3**: 박스 없는 sections (active/context/tokens/cost/recent tools)
- **SessionPickers v3**: InlinePicker — "label · value ▾" hover bg
- **UsageDashboard v3 / CreateWorkspaceSheet v3**: FlatSection 사용
- **RootView v3**: 자체 HStack (sidebar/main/inspector), Composer 통합, EmptyWorkspaceView

ADR-016 — codex review 결과 반영 + design spec v3 정식 채택

검증:
- swift build → 2.21s 성공
- swift test → 49/49 통과
- swift run YuminaiApp → 윈도우 정상 (PID 94678)

### Redesigned (CLI-flat 룩으로 전면 재구성, 2026-05-01 늦은밤)
- **macOS 네이티브 컴포넌트 우회** — NavigationSplitView 제거 (직접 HStack), Form/Picker/.regularMaterial 모두 chrome에서 제거
- **Theme 전면 재정의** — 시스템 색 (`Color(NSColor.windowBackgroundColor)` 등) 모두 제거 → 명시적 light/dark 적응형 hex 토큰. 모든 폰트 monospace 기본
- **자체 Flat 컴포넌트** (`FlatComponents.swift`): FlatButton (5 variants × 2 sizes), FlatTextField, FlatSection, FlatRow, FlatHDivider/FlatVDivider, FlatToggle
- **flatChrome modifier** — `.regularMaterial` 대신 단색 + 옵션 1px border (top/bottom/leading/trailing 선택)
- **MessageBubble 완전 재작성** — 박스/배경 제거, prefix 마커 (`>`, `·`, `○`, `—`) + lowercase role 라벨 + 본문만 (Claude Code CLI 룩)
- **InlinePicker** — `model · sonnet ▾` 형식의 monospace 1px-border 픽커
- **ChatToolbar** — `[ws-name] | model·sonnet▾ mode·default▾ effort·medium▾ │ ●streaming` flat 룩
- **ChatStatusBar** — `ctx ▓▓░ 23.4% │ msg 8 in 12.3k out 4.5k cache 890 │ $0.0451`
- **ContextInspector** — 박스 없는 섹션 (uppercase 라벨 + key/value)
- **SidebarView** — flat row, `>` 선택 마커, hover/select 단색 배경
- **MessageInputView** — `>` prompt + flat textarea + send/cancel
- **SidebarToggle 버튼** — Toolbar 좌측, 사이드바 hide/show
- **CreateWorkspaceSheet, UsageDashboard** — 자체 flat 컴포넌트 사용
- 정수 spacing (2/4/8/12/16/24)으로 정보 밀도 ↑

### Added (UI/UX 대폭 개선, 2026-05-01 후반)
- **모델·모드·효과 picker (인라인)** — ChatToolbar에서 즉시 변경. 변경 시 Claude CLI 자동 재spawn (현재 메시지 보존)
- **ChatToolbar** — Claude orange 액센트, monospace 라벨, 워크스페이스명 + model/mode/effort + 스트리밍 뱃지 + dashboard/inspector 버튼
- **ChatStatusBar** (입력창 위) — 컨텍스트 게이지 (색상 임계값 50/75%), 메시지 수, in/out/cache 토큰, 비용 inline
- **UsageDashboard sheet (⌘D)** — 현재 세션 + 누적 사용량 통계 + 모델별 가격 풋터
- **ContextInspector (⌘⌥I 토글)** — 우측 사이드 패널: Active 설정 / Context 게이지 / Tokens / Cost / Recent Tools
- **SettingsView 5탭** — 일반 / 모델·모드 / 편집 / Telegram / Anthropic. 기본 모델/모드/효과/예산 모두 GUI 편집
- **EditPreferences struct** — autoFormat, showDiffOnEdit, autoBackup
- **Liquid Glass chrome** — Toolbar/StatusBar/Inspector에 `.regularMaterial` 배경
- **Theme 토큰 정밀화** — chrome/surface/role tints, monospace 통계 폰트, pill radius 추가
- **사용량 트래킹** — JSONStreamParser가 `usage` 객체 + `total_cost_usd` 추출 → `.usage(UsageDelta)` 이벤트 → AppModel이 currentSessionUsage / allTimeUsage 누적
- **PermissionMode / EffortLevel / ClaudeModel enum** — Claude CLI 옵션 1:1 매핑 + displayName/shortDescription/가격 메타
- **SessionSettings struct** — model + permissionMode + effortLevel + includeHookEvents + maxBudgetUSD
- 단위 테스트 추가: UsageStats accumulate/contextUsage clamp (49 tests / 17 suites 모두 통과)

### Decided (ADR-014, 2026-05-01)
- Toolbar inline picker 패턴 — picker 변경 시 즉시 새 ClaudeStreamSession spawn (활성 settings 적용). 메시지 로그는 UI에 보존.

### Fixed (2026-05-01)
- SPM executable이 background-only로 시작되어 윈도우가 안 보였던 문제 — `NSApplication.shared.setActivationPolicy(.regular)` + `NSApplicationDelegateAdaptor` + `applicationDidFinishLaunching`에서 `activate(ignoringOtherApps: true)` 추가

### Added (MVP-0 골격, 2026-05-01)
- **YuminaiCore**: KeychainStore (Live + InMemory), WorkspaceStore/SessionStore protocol, TelegramClient protocol, AppPreferences + UserDefaultsStore
- **YuminaiPersistence**: SessionModel, MessageModel + SchemaV1 갱신, SwiftDataWorkspaceStore, SwiftDataSessionStore, live ModelContainer factory
- **YuminaiClaudeAdapter**: JSONStreamParser (NDJSON), LiveClaudeAdapter (Process + Pipe spawn, ADR-009 인자 조합)
- **YuminaiTelegram (신규 모듈)**: LiveTelegramBot (HTTPS API + long polling), MockTelegramBot, TelegramAlertDispatcher (정책 기반 알림), TelegramCommandPump + TelegramCommandRouter protocol, EchoCommandRouter
- **YuminaiUI**: MessageBubble, MessageInputView, ChatView, SidebarView + WorkspaceRow, CreateWorkspaceSheet, SettingsView (3-tab) + SecretField/SecretStatus
- **YuminaiApp (신규 executable)**: @main YuminaiAppMain, AppModel (@MainActor @Observable, 모든 모듈 DI + lifecycle), RootView (NavigationSplitView), ChatDetailView, SettingsContainer, YuminaiCommandRouter (Telegram→Claude 라우터)
- 단위 테스트: 47개 / 16 suite (KeychainStore, AppPreferences Codable, JSONStreamParser 8건, MockTelegramBot, AlertDispatcher 정책, EchoRouter, SwiftDataWorkspaceStore CRUD 6건, SwiftDataSessionStore CRUD + messages 3건)
- 검증: `swift build` 성공, `swift test` 47/47 통과, `swift run YuminaiApp` 프로세스 정상 시작/종료

### Decided (2026-05-01 — 사용자 답변)
- **Q-B 확정**: B2 (CLI 스타일 채팅 GUI). ADR-013 정식 채택
- **Q-D1 잠정**: Obsidian Vault는 사용자 미정 → SettingsView에서 경로 입력 받고 v0.2에서 활성화. 코어/UI 변경 없이 추후 모듈 추가 가능 구조
- **Q-D2 확정**: Telegram bot은 SettingsView에서 토큰/Chat ID/허용 user ID 추가. 양방향(알림 + 명령 수신) 둘 다 구현. ADR-012 정식 채택

### Discovered (W1 Spike, 2026-05-01)
- Claude CLI 2.1.101이 `-p --input-format stream-json --output-format stream-json --include-partial-messages --include-hook-events` 로 JSON 양방향 스트리밍을 공식 지원 → **PTY 불필요, ANSI 파싱 불필요**
- `--session-id <uuid>`, `-r/--resume`, `-c/--continue`로 멀티턴 세션 영속을 Claude가 자체 처리
- `--settings`, `--mcp-config`, `--agents`, `--plugin-dir`, `--add-dir`로 워크스페이스 하네스 완벽 주입 가능
- 결과: ADR-005 superseded → **ADR-009 채택** (`-p` + stream-json), **ADR-010 채택** (세션 영속 Claude 위임 + SwiftData 캐시)

### Added
- 프로젝트 초기 스캐폴딩 (디렉토리 구조 + 하네스 골격)
- PRD 문서 12개 (00~99)
- 설계 문서 6개 (`docs/design/`)
- Swift 6.2 / SwiftUI / SwiftData 기반 5개 모듈 정의:
  - `YuminaiCore` — 도메인 모델 / DI 프로토콜
  - `YuminaiClaudeAdapter` — Claude CLI 자식 프로세스 + PTY
  - `YuminaiPersistence` — SwiftData 모델 / 마이그레이션
  - `YuminaiUI` — SwiftUI 컴포넌트 / Liquid Glass
  - `YuminaiHarness` — rules/agents/skills/hooks 디스패처
- 5개 테스트 타깃 placeholder
- claude-forge 패턴 매핑 (rules/, agents/, skills/, hooks/, commands/, settings.json, .mcp.json)
- `Package.swift` (macOS 26.0+, Swift 6.2, StrictConcurrency 활성)
- Xcode App 타깃 추가 가이드 (`App/README.md`)

### Decided
- 기술 스택: SwiftUI 네이티브 / Swift 6.2 / SwiftData / Keychain
- Claude Code 관계: A1 (CLI Wrapper)
- 본인 1인 사용 / unsigned / App Sandbox OFF
- macOS 26.0+ (deployment target)

### Open
- UI 형태 확정 (B1/B2/B3 — 잠정 B2)
- Obsidian 통합 구체 명세 (Vault 경로 등)
- Telegram bot 토큰 / user ID
- "다양한 외부 앱들" 구체 후보

[`docs/prd/99_OPEN_QUESTIONS.md`](../prd/99_OPEN_QUESTIONS.md) 전체 참조.
