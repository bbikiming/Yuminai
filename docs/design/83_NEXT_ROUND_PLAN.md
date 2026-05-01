# 83_NEXT_ROUND_PLAN — v0.4 Multi-Agent + Delivery Loop

> **목적**: codex가 식별한 5개 거대 gap (pane model / diff review / embedded preview / software delivery loop / execution env mobility) + ADR-026 1단계 후속(인터-에이전트 메시지) 통합 기획.
>
> **방법**: GitHub 최상위 스타 오픈소스 패턴을 1차 근거로. 자체 발명 X.
>
> **Evidence base**: [`docs/research/01_NEXT_ROUND_REFERENCES.md`](../research/01_NEXT_ROUND_REFERENCES.md) — 23개 OSS 프로젝트 (총합 1.1M+ stars) 분석.

---

## 0. 전제 — Yuminai 현재 상태 (v0.3 / ADR-026 기준)

### 모듈 구조 (8개)
- `YuminaiCore` — 도메인 (Workspace + AgentKind + ClaudeAdapter protocol + SessionSettings)
- `YuminaiClaudeAdapter` — LiveClaudeAdapter + LiveCodexAdapter + MockClaudeAdapter + JSONStreamParser + CodexJSONLParser
- `YuminaiPersistence` — SwiftData (WorkspaceModel + SessionModel + MessageModel)
- `YuminaiTelegram` — LiveTelegramBot + TelegramSessionBridge + CokacdirImporter + Inspector
- `YuminaiObsidian` — ObsidianVault actor + MarkdownPreprocessor + VaultWatcher
- `YuminaiUI` — SwiftUI components (Theme + 약 20+ views)
- `YuminaiApp` — @main + AppModel + RootView (~900 lines)
- `YuminaiHarness` — scaffold + harness templates

### 현재 1 워크스페이스 = 1 세션 = 1 에이전트
- `AppModel.currentClaudeSession: (any ClaudeStreamSession)?` 하나
- `AppModel.adapter(for: workspace)` — workspace.agentKind로 dispatch
- 사용자가 toolbar에서 agent 전환 → 현재 session terminate + 새 session spawn

### 현재 한계 (v0.4 해결 대상)
1. 워크스페이스에 1 에이전트만 활성 — 멀티 패널 X
2. 인터-에이전트 메시지 X — Claude가 Codex에게 위임 불가
3. 코드 변경 review X — Edit tool 결과를 사용자가 IDE에서 따로 확인
4. Build/test 자동화 X — 에이전트 응답 후 사용자가 직접 실행
5. 임베드 터미널/프리뷰 X — 별도 Terminal.app/브라우저 사용

---

## 1. v0.4 라운드 5개 주제 — 전체 매트릭스

| ID | 주제 | 1순위 reference | 핵심 차용 패턴 | 복잡도 | 신뢰도 |
|----|------|----------------|---------------|--------|-------|
| M1 | 멀티 에이전트 패널 | **AutoGen AgentTool** (57.6k) + **Aider Architect/Editor** (44.2k) | 메인 agent가 보조를 tool로 호출 + 좌/우 split UI | L | High |
| M2 | 인터-에이전트 메시지 | **MetaGPT 메시지 환경** (67.6k) + AutoGen GroupChat | 워크스페이스 internal bus, `@codex` mention = publish | M | High |
| M3 | Diff review UI | **Cline editable diff** (61.2k) + **Aider git-as-source** (44.2k) | git이 단일 진실의 원천, 매 변경=commit | L | High |
| M4 | Software delivery loop | **Aider `--auto-test`** (44.2k) + **Devin step budget** | 단순 loop, max-attempts=3 hard cap | M | Moderate |
| M5 | Embedded terminal/preview | **SwiftTerm** (1.4k, Miguel de Icaza) + **Warp block UX** (50.8k) | Native PTY + block-단위 output | M-L | Moderate |

### 의존성 그래프

```
M5 (terminal) ──┐
                ├──> M4 (delivery loop)
M3 (diff review)┘     ↑
                      │
M1 (multi-pane) ──> M2 (inter-agent) ──┘
```

권고 phase 순서: **M3 → M5 → M4 → M1 → M2** (M3가 가장 가치 + 단순, M2는 가장 복잡 + 마지막).

---

## 2. 주제별 상세 — Evidence-Based 결정

### M1. 멀티 에이전트 패널 — 한 워크스페이스에 N 에이전트

**문제**: Claude(설계 강함) + Codex(빠른 구현 강함)를 한 워크스페이스에서 동시 활용 + 비교 불가.

**옵션 분석**:

| Option | 패턴 | 출처 | 평가 |
|--------|------|------|------|
| A | N panes (각 pane = 1 agent + 1 session + 1 messages) | Zed (81k), VS Code 통합 터미널 (184k) | UI 분할 비용 큼 |
| B | N tabs (현재 1 활성, 나머지 background) | VS Code, Cursor | 단순, 동시 비교 X |
| C | AutoGen GroupChat — 모든 agent 한 conversation | AutoGen (57.6k, **maint mode**) | Yuminai의 1ws-1agent UX와 충돌 |
| D | **AgentTool 패턴** — 메인 agent가 보조를 tool로 호출 | AutoGen 신패턴, Aider architect/editor 내부 검증 | Yuminai 진화 자연스러움 |

**1순위 reference**: **Aider `aider/coders/architect_coder.py`** (Architect/Editor 2-LLM, 44.2k stars, production-tested) + **AutoGen `AgentTool`** 신패턴.

**근거**: Aider는 single-LLM이 아니라 이미 내부적으로 `architect (planner) + editor (applier)` 2-step pipeline. `auto_accept_architect = False`로 사용자 승인 게이트 가능. **Yuminai의 "1ws-1agent → 1ws-2역할 (planner+applier)" 진화가 자연스럽고 production-검증됨.**

**결정**: 
- **Option D (AgentTool) 채택** — Claude를 메인, Codex를 callable tool로 노출
- UI는 **좌/우 split (M1.b)** 우선 — 양쪽이 보여야 협업 가시성
- AutoGen 자체 코드 의존은 X (maintenance mode), 패턴만 차용

**구현 변경 범위**:
- `AppModel`: `currentClaudeSession` → `agentPanes: [PaneId: AgentPane]` (Map)
- 새 도메인 `AgentPane { id, agentKind, session, messages, settings, role: .primary | .secondary }`
- `ChatView` → `PaneView`로 wrap, RootView가 N panes layout
- Composer는 active pane을 target (focus가 결정)
- ChatStatusBar는 active pane만
- Telegram bridge는 primary pane만 forwarding (사용자가 명시적 변경 가능)

**Phase 분할**:
- **M1.a (foundation)**: pane 데이터 모델 + tab UI (split 다음에)
- **M1.b (split layout)**: 좌/우 split + focus management
- **M1.c (sync controls)**: 모델/모드/effort picker per-pane

---

### M2. 인터-에이전트 메시지 패싱 — `@codex review this`

**문제**: 한 패널에서 다른 에이전트에게 작업 위임할 syntax 부재.

**옵션 분석**:

| Option | 패턴 | 출처 | 평가 |
|--------|------|------|------|
| A | `@<agent>` mention syntax | 일반 chat 도구 관용 | 학습 비용 낮음 |
| B | `/dispatch <agent> <text>` 명령 | Telegram bot 패턴 | 기억 비용 ↑ |
| C | AutoGen GroupChat speaker selection | AutoGen | 자동 선택 = 복잡 |
| D | **MetaGPT 메시지 환경 (publish/subscribe)** | MetaGPT (67.6k) | bus 추상화 + watch 패턴 |
| E | CrewAI manager → worker delegation | CrewAI (50.4k) | hierarchical 강제 |

**1순위 reference**: **MetaGPT 메시지 환경 (Environment + Shared Message Pool)** + **AutoGen GroupChat speaker selection** (manual hint).

**근거**: MetaGPT 67.6k는 이미 검증된 publish/subscribe 패턴. 각 Role이 `watch()`로 관심 메시지 구독. `@codex` 멘션은 자연스럽게 "target=@codex"인 message publish. Yuminai의 워크스페이스 = MetaGPT의 Environment 매핑이 깨끗.

**결정**:
- `@<agent>` mention syntax 채택 (Option A + D 결합)
- 워크스페이스에 internal `MessageBus` actor — publish/subscribe
- Composer가 `@codex` 파싱 → bus publish (`type: dispatch`, `target: codex`, `from: claude_pane`)
- 다른 에이전트의 turn 결과도 bus로 publish — 후속 에이전트가 watch 가능
- Telegram bridge에도 mention 파싱 포함 (사용자가 텔레그램에서 `@codex 검토` 가능)

**구현 변경 범위**:
- `Sources/YuminaiCore/MessageBus.swift` (신규) — actor, `publish(_)` / `subscribe(filter:)`
- `Sources/YuminaiCore/AgentMessage.swift` (신규) — `from`, `to`, `type`, `payload` Sendable
- AppModel에 bus 인스턴스 + per-pane 자동 subscribe
- Composer/Router에서 mention parsing
- ChatView 메시지에 source/target agent 라벨 표시

**자동 vs 수동 dispatch**:
- v0.4: **수동만** (`@codex` 명시적 mention)
- v0.5: AutoGen-style auto speaker selection 검토 (LLM이 다음 차례 결정)

---

### M3. Diff Review UI

**문제**: Edit/Write tool 결과를 IDE에서 따로 확인. accept/reject 메커니즘 X.

**옵션 분석**:

| Option | 패턴 | 출처 | 평가 |
|--------|------|------|------|
| A | git stash + UI에서 accept (commit) / reject (drop) | Aider git-as-source (44.2k) | 단순, 강력 |
| B | **VS Code editor-native diff** (editable) | Cline (61.2k) | UX SOTA, 구현 비용 큼 |
| C | side-by-side diff (view-only) | reviewdog (9.3k) | 단순, editable X |
| D | PR-style block review + comments | Copilot Workspace | 4-stage gating |
| E | Checkpoint/Restore | **Cline** | task vs workspace 분리 |

**1순위 reference**: **Cline checkpoint/restore + view-only diff** (61.2k) + **Aider git-as-source-of-truth** (44.2k, `--no-auto-commits` toggle).

**근거**: 
- Aider 패턴: 매 turn = git commit → diff = `git diff HEAD~1`, undo = `git revert`. **git이 단일 진실의 원천이면 자체 diff 모델 X 필요**.
- Cline 패턴: 매 step마다 checkpoint, "task만 restore" vs "workspace까지 restore" 분리. Yuminai의 conversation 보존 + 파일만 되돌리기 use case에 적합.
- **Editable diff는 v0.5로 보류** — SwiftUI에 native diff editor 부재, 자체 구현 M-L 비용. v0.4는 view-only + accept/reject로 충분.

**결정**:
- **Phase A 우선 구현**: git-based diff + view-only DiffView + accept (stage) / reject (revert) / partial accept (line range)
- **Checkpoint** = workspace dir의 file snapshot (git stash) at agent turn start
- **Restore**: "이 turn 이전으로" — git stash apply + checkout
- editable diff = v0.5

**구현 변경 범위**:
- `Sources/YuminaiCore/Checkpoint.swift` (신규) — Checkpoint actor: stash 관리
- VaultWatcher 확장 → workspace 파일 변경 감지 (Vault 외 일반 dir)
- `Sources/YuminaiUI/DiffView.swift` (신규) — git diff 렌더 (gutter + add/del 색)
- Inspector에 새 탭 "변경" — pending diffs 리스트 + accept/reject
- `Sources/YuminaiApp/CheckpointManager.swift` (신규) — git stash + commit 자동화

**git policy**:
- agent turn 시작 시 → `git stash push -u "yuminai-checkpoint-<turn-id>"`
- agent turn 완료 시 → `git stash pop` (변경 적용된 상태)
- accept → 그대로 (이미 working tree에 있음)
- reject → `git checkout -- <files>` 또는 `git stash apply <checkpoint>`

---

### M4. Software Delivery Loop — 자동 build/test/fix

**문제**: 코드 변경 후 사용자가 따로 build/test 실행. 실패 시 다시 에이전트에 알림.

**옵션 분석**:

| Option | 패턴 | 출처 | 평가 |
|--------|------|------|------|
| A | **Aider `--auto-test --auto-lint`** | Aider (44.2k) | 단순, 검증, 무한루프 방지 X |
| B | SWE-agent ACI + yaml policy | SWE-agent (19.1k), mini 100 LoC | 강력, 학습 곡선 |
| C | Sweep AI self-healing | Sweep (7.7k) | PR-centric, Yuminai와 model 다름 |
| D | OpenHands Docker runtime | OpenHands (72.5k) | 격리 우수, 사용자 부담 |
| E | **Devin step budget** | Cognition (closed) | 무한루프 방지 검증 |

**1순위 reference**: **Aider `--auto-test --auto-lint`** + **Devin step budget** + **mini-SWE-agent의 simplicity** (100 LoC로 SWE-bench 65%).

**근거**:
- mini-SWE-agent 100 lines로 65% achievement는 "loop은 단순할수록 좋다"는 강한 증거. **그래프/state machine framework 없이 단순 retry counter로 충분**.
- Aider는 production-검증, Yuminai의 single-shot 모델과 잘 맞음.
- Devin step budget = 무한 루프 방지 정석 패턴 (max attempts + max time + 사용자 확인 gate).
- OpenHands Docker runtime은 macOS native 정체성과 충돌 → NSTask + sandboxed dir로 충분.

**결정**:
- **Phase B 구현**: Workspace에 build/test/lint 명령 메타 + agent turn 완료 시 자동 실행 + 실패 시 다음 turn 자동 첨부
- **Hard cap** (Devin 패턴): max-attempts=3, max-time=5min, 동일 에러 반복 감지 시 사용자 에스컬레이션
- **자동 재요청 mode**: 처음에는 **소극적** (실패 결과를 다음 turn에 자동 첨부, agent가 직접 새 turn은 spawn 안 함). v0.5에서 적극적 mode (자동 새 turn) 토글 검토
- v0.5: SWE-agent yaml policy로 declarative workflow

**구현 변경 범위**:
- `Workspace.deliveryConfig: DeliveryConfig?` — `buildCommand`, `testCommand`, `lintCommand`, `triggers`, `maxAttempts`, `maxTime`
- `Sources/YuminaiApp/DeliveryRunner.swift` (신규) — actor, NSTask runner + 결과 capture
- AppModel hook: `handle(.completed)` → DeliveryRunner.maybeRun
- 결과는 M5의 terminal pane에 표시 (의존성)
- 실패 시 다음 turn input에 자동 prepend ("[테스트 실패]\n<stderr 200줄>\n...")

---

### M5. Embedded Terminal / Preview Pane

**문제**: 별도 Terminal/브라우저 띄워야 함. context switch 비용.

**옵션 분석**:

| Option | 패턴 | 출처 | 평가 |
|--------|------|------|------|
| A | **SwiftTerm 라이브러리** | Miguel de Icaza, 1.4k | macOS native, ADR-005에서 한 번 검토 |
| B | xterm.js + WKWebView | VS Code 184k | 무거움, web 의존 |
| C | NSTask + 자체 ANSI 파서 | DIY | 가벼움, 기능 한계 |
| D | 외부 Terminal.app/iTerm 호출 | macOS 관용 | 임베드 X |
| E | **Warp block-style output** | Warp (50.8k) | 출력 그룹핑 UX |

**1순위 reference**: **SwiftTerm** (Miguel de Icaza의 검증된 native terminal) + **Warp block UX** (50.8k stars의 modern terminal UX).

**근거**:
- SwiftTerm은 Miguel de Icaza (Mono 창시자) 작성 + macOS/iOS 양쪽 지원. **Yuminai의 macOS native 정체성과 alignment 우수**.
- Warp block UX (각 명령 = collapsible block + share 가능)은 diff review와 일관성 — "변경도 block, 출력도 block".
- xterm.js + WKWebView는 무게 vs 기능 trade-off가 SwiftTerm 대비 불리.

**결정**:
- **SwiftTerm 외부 의존성 도입** — 두 번째 외부 dep (첫 번째: swift-markdown-ui)
- ADR-031로 의존성 정책 변경 명시 (이전 ADR-021 — 외부 dep 정책 변경)
- Warp-style block output: 각 명령 호출을 1개 block으로 그룹핑, collapse 가능
- Preview는 별도 — WKWebView로 file:// URL 또는 dev server localhost

**구현 변경 범위**:
- Package.swift: SwiftTerm dependency 추가
- `Sources/YuminaiUI/TerminalPane.swift` (신규)
- `Sources/YuminaiUI/PreviewPane.swift` (신규, WKWebView wrapper)
- RootView layout 확장 (sidebar / chat pane(s) / inspector / + 옵션 terminal pane / + 옵션 preview pane)
- workspace 메타: 마지막 terminal cwd, preview URL

**Phase 분할**:
- **M5.a**: SwiftTerm 통합 spike (1-2일) — 기본 출력만, ANSI 색 OK 확인
- **M5.b**: Block 그룹핑 UI (Warp 스타일)
- **M5.c**: PreviewPane (WKWebView, 단순 URL 표시)

---

## 3. 횡단 의사결정 (분기점)

| 결정 | 권고 시점 | 영향 |
|------|---------|------|
| **ACP (Agent Client Protocol) 채택** | v0.4 마감 ~ v0.5 시작 | 채택 시 외부 에이전트 자동 호환 + obsidian-agent-client 인접 reuse. **Swift SDK 없음 → 자체 작성 필요** (TS SDK 코드량 + JSON-RPC 매핑). v0.5 follow-up. |
| **Runtime sandbox** (Docker vs NSTask) | M4 설계 시 | NSTask + sandboxed dir 권장 — Docker는 사용자 부담 ↑, Yuminai macOS native 정체성과 trade-off |
| **Diff UI editable vs view-only** | M3 시작 시 | **view-only로 시작** (v0.4) — Cline의 editable이 SOTA지만 SwiftUI 자체 구현 M-L 비용. v0.5에서 editable 검토 |
| **AutoGen 코드 의존** | M1 시작 시 | **X — 패턴만 차용** (AutoGen maintenance mode, MS Agent Framework 후속) |

---

## 4. Phase 분할 — 통합 commit 아닌 phase별

> 각 phase는 working software + 별도 ADR + 별도 commit (PR 대비).

### Phase A — Foundation (M3 + M5.a)
**범위**: Diff review UI + Embedded terminal (단순 출력만)
- git checkpoint manager + view-only DiffView + accept/reject
- SwiftTerm 통합 spike (1-2일) → TerminalPane (basic, ANSI 색)
- Inspector에 "변경" 탭 + workspace에 terminal pane

**신규 ADR**: ADR-027 (git-as-source diff + SwiftTerm 의존성)
**신규 외부 의존성**: SwiftTerm
**예상 commits**: 2-3개

### Phase B — Delivery Loop (M4 + M5.b)
**범위**: 자동 build/test + Warp 스타일 block 그룹핑
- Workspace.deliveryConfig + DeliveryRunner
- Aider-style auto-test on turn complete + Devin step budget
- Terminal output을 block 단위로 그룹

**신규 ADR**: ADR-028 (delivery loop + step budget hard cap)
**예상 commits**: 2개

### Phase C — Multi-pane Foundation (M1.a + M1.b)
**범위**: 워크스페이스 N panes + 좌/우 split UI
- AppModel pane 데이터 모델 (대규모 변경)
- Tab → split UI 단계적
- per-pane state (session, messages, settings)
- Telegram bridge는 primary pane만

**신규 ADR**: ADR-029 (multi-pane data model)
**예상 commits**: 3-4개 (가장 큰 phase)

### Phase D — Inter-agent (M2)
**범위**: MessageBus + @mention dispatch
- MessageBus actor + AgentMessage
- Composer/Router mention parsing
- ChatView 메시지에 source/target 라벨

**신규 ADR**: ADR-030 (MetaGPT 메시지 환경 차용)
**예상 commits**: 2개

### Phase E — Preview + Polish (M5.c + Codex schema 정밀화)
**범위**: WebView preview + Codex JSONL 실측 정밀화
- PreviewPane (WKWebView)
- Codex 실제 사용 결과로 unknown type 정확한 매핑
- M1 split layout polish

**신규 ADR**: ADR-031 (Codex schema 검증 결과)
**예상 commits**: 2-3개

**총 예상**: 5 phases, 약 11-15 commits, ADR-027 ~ ADR-031, 약 4-6주 작업.

---

## 5. 비범위 (이번 라운드 X — 명시)

- **ACP Swift SDK 자체 작성** — v0.5 follow-up, TS SDK 코드량 + JSON-RPC 매핑 비용 추정 후 결정
- **Editable diff editor** — v0.5 (Cline의 SOTA UX는 SwiftUI 자체 구현 비용 큼)
- **Auto speaker selection** — AutoGen-style LLM이 다음 차례 결정 (M2의 v0.5 확장)
- **Docker runtime sandbox** — NSTask로 충분, Docker는 사용자 부담 ↑
- **iCloud 동기화 / iOS 포트** — 별도 메이저 결정
- **코드 편집기 임베드** — ADR-008 유지 (Yuminai는 IDE 대체 X)
- **CI/CD 통합** — workspace 단위 local loop 우선, GitHub Actions 등은 v0.5+
- **Continue.dev style `.continue/checks/` 패턴** — interesting but Yuminai의 직접 매칭 use case 없음

---

## 6. 검증 매트릭스 (각 phase 완료 후)

| Phase | 검증 | 방법 |
|-------|------|------|
| A | git checkpoint가 turn 단위로 정확히 stash | unit test (CheckpointManager) + manual e2e |
| A | DiffView가 git diff 정확히 렌더 | snapshot test + manual `git diff` 비교 |
| A | TerminalPane이 ANSI 색 정상 (`ls --color`, `npm test`) | manual + 표준 escape 테스트 |
| B | Test 실패 → 다음 turn에 자동 첨부 | sample 프로젝트 e2e (failing test fixture) |
| B | Step budget hard cap (3 attempts, 5min) | unit test (DeliveryRunner) |
| C | N panes layout + focus 단축키 | manual + accessibility audit |
| C | Telegram bridge가 primary pane만 forward | unit test (Bridge) + e2e |
| D | `@codex` mention dispatch 정확 라우팅 | unit test (Router) + e2e (Telegram + UI 둘 다) |
| E | PreviewPane이 dev server localhost OK | manual (간단 정적 사이트) |
| E | Codex JSONL 실측 후 unknown type 5%↓ | run 100 turn → log analyze |

---

## 7. Open Questions (사용자 답변 필요)

| # | 질문 | 권고 default |
|---|------|-------------|
| Q1 | M1 layout — split (좌/우) 우선 vs tab 우선? | **split** (협업 가시성) |
| Q2 | M3 accept policy — auto vs manual vs hybrid? | **manual** (안전 우선, hybrid는 v0.5) |
| Q3 | M4 trigger — agent turn 완료 즉시 자동 vs 수동? | **자동** (Aider 패턴, 단 Hard cap) |
| Q4 | M5 SwiftTerm 외부 의존성 — OK? | **OK** (Miguel de Icaza, native, ADR로 정책 변경 문서화) |
| Q5 | M2 mention syntax — `@codex` vs `/dispatch codex`? | **`@codex`** (학습 비용 낮음, Telegram 표준) |
| Q6 | Phase 순서 — M3→M5→M4→M1→M2 OK? | **OK** (M3가 가장 가치 + 단순) |
| Q7 | ACP 채택 검토 — v0.5 시작 시 별도 spike? | **OK** (TS SDK reading + Swift PoC 1-2일) |

답변에 따라 ADR-027~031 세부 조정.

---

## 8. 신뢰도 / 위험 요약

**High confidence** — 카테고리 A/B의 1순위 references는 50k+ stars + production. 차용 안전:
- AutoGen AgentTool 패턴 (단 코드 X, 패턴만)
- Aider Architect/Editor + git-as-source
- Cline checkpoint
- MetaGPT 메시지 환경

**Moderate** — 도구별 production 사례 다양:
- Aider auto-test loop (검증 강함)
- mini-SWE-agent simplicity 강한 증거지만 Yuminai 환경 retest 필요

**Low / Speculative** — 사전 사례 부족:
- SwiftTerm + Yuminai 통합 (1-2일 spike 권장)
- ACP 채택 ROI (외부 에이전트 생태계 성장 의존)

**Risks**:
- Phase C (multi-pane) 가장 큰 변경 — AppModel 대규모 refactor. 일정 초과 가능 → 작업 중 split commit으로 위험 분산
- Codex JSONL schema 실측 검증 안 됨 — Phase E에서 정밀화 필요
- Telegram bridge가 multi-pane과 어떻게 상호작용할지 — primary만 forward로 단순화하지만 사용자 헷갈림 가능성, /bind에 pane 지정 옵션 추가 검토

---

## 9. 출처 (전체)

[`docs/research/01_NEXT_ROUND_REFERENCES.md`](../research/01_NEXT_ROUND_REFERENCES.md) — 23개 OSS, 1.1M+ stars, 2026-05-01 GitHub API 기준.

핵심 인용:
- AutoGen 57.6k (Microsoft, **maint mode**)
- MetaGPT 67.6k (FoundationAgents, ICLR 논문)
- Cline 61.2k (cline/cline)
- Aider 44.2k (Aider-AI/aider)
- OpenHands 72.5k (SWE-bench 77.6%)
- SWE-agent 19.1k → mini 100 LoC (NeurIPS 2024)
- SwiftTerm 1.4k (Miguel de Icaza)
- Warp 50.8k (block UX)
- ACP 3.0k (agentclientprotocol — Yuminai 정확한 use case 표준)
