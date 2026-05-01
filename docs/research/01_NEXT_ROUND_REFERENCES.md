# v0.4 Next Round — GitHub 레퍼런스 리서치

> **작성일**: 2026-05-01 (Friday)
> **대상 라운드**: Yuminai v0.4 (멀티 에이전트 패널 / 인터-에이전트 메시지 / Diff 리뷰 UI / Delivery loop / Embedded preview·terminal)
> **방법**: `gh` CLI 기반 metadata + README 1차 분석. 모든 스타 수는 2026-05-01 기준 GitHub API 응답.
> **주의**: 패턴 추출 위주. 깊은 코드 리딩은 Yuminai 적용이 결정된 1순위 레퍼런스에 한해 후속 PR에서 수행 권장.

---

## A. 멀티 에이전트 오케스트레이션 프레임워크

### A.1 MetaGPT — 67.6k stars
- **Repo**: https://github.com/FoundationAgents/MetaGPT (구 `geekan/MetaGPT`, owner 변경됨)
- **핵심 컨셉**: `Code = SOP(Team)` — 소프트웨어 회사를 시뮬레이션 (PM, Architect, Engineer, QA roles).
- **인터-에이전트 통신**: **Publish/Subscribe 메시지 환경 (Environment)** + **Shared Message Pool**. 각 Role은 자신이 구독한 메시지만 수신; 단순 broadcast가 아니라 "관심사 기반 라우팅". (논문: Hong et al. 2024, ICLR.)
- **역할 정의**: `Role` 클래스 상속 + `_init_actions()`로 가능 action 명시 + `watch()`로 구독할 메시지 타입 지정.
- **컨텍스트 공유**: Shared Memory (Environment 내부) + 표준화된 산출물 (PRD, design doc, code) — 각 단계 산출물을 다음 Role이 읽음.
- **Yuminai 적용 후보**:
  1. **메시지 환경 모델** — 워크스페이스에 Bus를 두고, Claude 세션과 Codex 세션이 각자 관심 메시지 (`type: "code-review"`, `target: "@codex"`)를 구독. "@codex 검토" 같은 명시적 위임이 Bus 메시지 발행으로 자연스럽게 연결됨.
  2. **표준 산출물 슬롯** — Claude가 생성한 PR diff를 워크스페이스 공유 슬롯에 저장 → Codex가 해당 슬롯을 watch.

### A.2 AutoGen / Microsoft Agent Framework — 57.6k stars
- **Repo**: https://github.com/microsoft/autogen
- **상태 (중요)**: **Maintenance mode**. 신규 프로젝트는 후속 [Microsoft Agent Framework](https://github.com/microsoft/agent-framework) 권장. v0.2 → v0.4 사이 큰 아키텍처 변경 있음.
- **핵심 컨셉**: 대화형 멀티 에이전트. `AssistantAgent` ↔ `UserProxyAgent` 2-party chat이 기본 패턴. `GroupChat`으로 N-party 확장.
- **인터-에이전트 통신**: 3개 layer — **Core (event-driven message passing, .NET/Python cross-runtime)** / **AgentChat (group chat, two-agent chat 등 opinionated API)** / **Extensions (LLM client / tool)**.
- **새로운 패턴 (현 README)**: `AgentTool` — 다른 agent를 그냥 tool로 wrap. `AssistantAgent(tools=[math_agent_tool, chemistry_agent_tool])`. 즉 **에이전트를 함수 호출처럼 호출**.
- **컨텍스트 공유**: 메시지 히스토리가 group chat 내부에 누적; speaker selection function이 다음 차례 결정.
- **Yuminai 적용 후보**:
  1. **AgentTool 패턴** — Claude를 메인 에이전트로, Codex를 `tool`로 노출. Claude가 `delegate_to_codex(prompt)` 호출하면 Yuminai가 Codex 세션에 forwarding. "@codex 검토해줘" UX와 가장 자연스럽게 매핑.
  2. **GroupChat speaker selection** — 워크스페이스 패널에서 "다음 발화자" 결정 로직을 라운드 로빈/auto-pick/manual로 토글.

### A.3 CrewAI — 50.4k stars
- **Repo**: https://github.com/crewAIInc/crewAI
- **핵심 컨셉**: **Role-based crew** + **Flow** (이벤트 기반 워크플로우). LangChain 비의존, 자체 프레임워크.
- **인터-에이전트 통신**: Crew 내부에서 **명시적 task delegation** (manager agent → worker agents). hierarchical / sequential / consensual process 선택 가능.
- **역할 정의**: `Agent(role, goal, backstory, tools, llm)` — 자연어 backstory가 핵심. `Task(description, expected_output, agent)`로 task→agent 바인딩.
- **컨텍스트 공유**: Task 출력이 다음 Task 입력으로 (sequential), 또는 Manager가 분배 (hierarchical). Memory 모듈 별도 제공.
- **Yuminai 적용 후보**:
  1. **Hierarchical Process** — 워크스페이스의 한 에이전트(예: Claude)를 manager로 설정, Codex를 worker로. UI상 "Manager / Worker" 라벨링이 Yuminai의 1WS-1Agent 패러다임 깨지 않으면서 협업 추가 가능.
  2. **Backstory-as-config** — 각 에이전트의 system prompt를 워크스페이스별로 저장 (Yuminai의 워크스페이스 설정에 `agent_backstory` 추가).

### A.4 LangGraph — 31.0k stars
- **Repo**: https://github.com/langchain-ai/langgraph
- **핵심 컨셉**: **그래프 기반 stateful workflow**. 노드 = 함수/에이전트, 엣지 = 전이 조건. Pregel/Apache Beam 영향.
- **인터-에이전트 통신**: 공유 **State 객체** (TypedDict)를 노드들이 read/write. 명시적 message bus 없음 — state mutation으로 간접 통신.
- **핵심 기능**: **Durable execution** (실패 복원), **human-in-the-loop interrupts** (state inspect/modify), **comprehensive memory** (short-term + long-term).
- **Yuminai 적용 후보**:
  1. **Interrupt 패턴** — Diff review UI의 "accept/reject" 결정을 LangGraph의 interrupt처럼 모델링. 에이전트가 변경 제안 → 그래프 일시 정지 → Yuminai UI에서 사용자 결정 → 재개.
  2. **Durable state** — Telegram bot에서 세션 disconnect 후 재접속 시에도 진행 상태 복원 가능한 State 모델 차용 가치.

### A.5 OpenHands — 72.5k stars (조사 카테고리 中 최다)
- **Repo**: https://github.com/OpenHands/OpenHands (구 `All-Hands-AI/OpenHands`, owner 변경됨)
- **핵심 컨셉**: AI-driven dev. SWE-bench 77.6% (2026-05 기준 README). CLI + Local GUI + Cloud + Enterprise 4가지 배포 형태.
- **인터-에이전트 통신**: **Agent SDK + Runtime 분리**. Runtime은 Docker sandbox; agent는 통신을 actions/observations로 추상화 (CodeAct 패러다임 — agent가 코드 실행을 action으로 발행, 결과를 observation으로 수신).
- **컨텍스트 공유**: Runtime 내부 file system이 "world model". 모든 에이전트가 같은 workspace dir 공유.
- **Yuminai 적용 후보**:
  1. **Action/Observation 추상화** — Claude/Codex 출력을 단일 형식 (action) 으로 정규화하면 인터-에이전트 메시지 패싱 구현 단순화. Yuminai의 메시지 forward 로직과 잘 맞음.
  2. **Runtime sandbox** — Software delivery loop의 build/test 격리에 Docker runtime 차용 검토. 단, macOS native 앱이라는 Yuminai 정체성과 trade-off 검토 필요 (NSTask로도 가능).

### A.6 Bonus — Agent Client Protocol (ACP) — 3.0k stars
- **Repo**: https://github.com/agentclientprotocol/agent-client-protocol
- **왜 중요**: **Yuminai의 정확한 use-case에 대한 표준 프로토콜**. Zed가 push. "code editor ↔ coding agent" 표준화.
- **SDK**: Kotlin / Java / Python / **Rust** / TypeScript 공식. Swift는 아직 없음 (커뮤니티 라이브러리 가능성).
- **연관 레포**: `obsidian-agent-client` (1.9k) — Obsidian + Claude Code/Codex/Gemini를 ACP로 묶음. **Yuminai와 가장 인접한 레퍼런스**. `OpenACP` (307) — Telegram에서 ACP 세션 제어.
- **Yuminai 적용 후보**: **차후 메이저 결정 사항**. Yuminai의 자체 wire protocol 대신 ACP 채택 검토 → 외부 에이전트 (Gemini CLI 등) 자동 호환 + obsidian-agent-client 코드 reuse 가능. v0.4 범위 외이지만 v0.5 이전에 결정 권장.

---

## B. AI 코딩 어시스턴트 (UI / 협업 패턴)

### B.1 Cline — 61.2k stars
- **Repo**: https://github.com/cline/cline
- **핵심 컨셉**: VSCode autonomous agent. **모든 file edit / terminal command / browser action에 human-in-the-loop 승인**.
- **UI 레이아웃**: VSCode sidebar; 우측 패널 권장. 대화 + diff view + terminal output이 한 패널에 stream.
- **Diff review 패턴**: **Editor-native diff view** — Cline이 변경 제안 → VSCode diff editor가 열림 → 사용자가 diff 안에서 직접 편집/되돌리기 가능 → 승인 후 적용. "diff 안에서 편집" UX가 핵심.
- **Auto loop**: linter/compiler error를 monitor → proactive fix (사용자 승인 없이 immediate). Browser 모드에서 dev server 띄우고 console log 보며 self-debug.
- **Checkpoint 시스템**: 매 step마다 워크스페이스 snapshot → 'Compare' / 'Restore' 버튼. "task만 restore vs workspace까지 restore" 분리.
- **Yuminai 적용 후보**:
  1. **Checkpoint/Restore** — Yuminai 워크스페이스에 step-level snapshot 저장 → diff review UI에서 "되돌리기"가 곧 checkpoint restore. 구현은 git stash 또는 file copy.
  2. **Diff 안에서 직접 편집** — view-only diff가 아니라 editable diff editor. SwiftUI는 native diff 없으므로 자체 구현 필요 (M-L 복잡도).

### B.2 Aider — 44.2k stars (실제 owner: `Aider-AI`)
- **Repo**: https://github.com/Aider-AI/aider
- **핵심 컨셉**: 터미널 AI pair programmer. **자기 자신의 88% 코드를 자기가 작성** (Singularity 88% 배지).
- **Architect/Editor 2-agent 내부 구조 (중요한 발견)**: `aider/coders/architect_coder.py` 코드 분석 결과 — **상위 LLM (architect)이 plan을 제안 → 하위 LLM (editor)이 실제 SEARCH/REPLACE 적용**. 이미 single-LLM이 아니라 2-step pipeline. `auto_accept_architect = False`로 step 사이 사용자 승인 가능.
- **Diff/commit 패턴**: 매 변경마다 자동 git commit (의미 있는 메시지 포함). `aider --no-auto-commits` toggle. SEARCH/REPLACE block 형식이 LLM-friendly.
- **Auto test/lint 모드**: `aider --auto-test --auto-lint` — 매 변경 후 lint/test 실행, 실패 시 LLM에 결과 feedback 후 자동 fix loop.
- **Yuminai 적용 후보**:
  1. **Architect/Editor 2-LLM 패턴** — Claude=architect (plan 강함), Codex=editor (apply 강함) 같은 역할 분리. Yuminai의 "한 워크스페이스 1 에이전트" → "한 워크스페이스 2-역할 (planner+applier)"로 자연스럽게 진화 가능.
  2. **자동 git commit + undo** — 매 에이전트 turn마다 commit → diff review = `git diff HEAD~1`. Reject = `git revert` 또는 `git reset --hard HEAD~1`.

### B.3 Continue — 32.9k stars
- **Repo**: https://github.com/continuedev/continue
- **현재 포커스 (2026)**: **Source-controlled AI checks, enforceable in CI** — `.continue/checks/` 폴더의 markdown 파일이 PR check로 동작. 구 IDE extension 위주에서 CI 위주로 피벗.
- **CLI**: `cn` 명령. `npm i -g @continuedev/cli`.
- **Yuminai 적용 후보**: **체크 정의를 markdown으로** — 워크스페이스에 `.yuminai/checks/security.md`, `architecture.md` 등 체크 정의 → Claude가 PR-시점 자동 실행. Software delivery loop의 "정책 가드레일" 패턴으로 차용 가능.

### B.4 Zed — 81.0k stars
- **Repo**: https://github.com/zed-industries/zed
- **핵심 컨셉**: Rust 기반 high-performance multiplayer editor. GPUI custom UI framework.
- **Multi-agent 지원**: ACP (Agent Client Protocol) push. Zed UI에서 Claude Code / Codex / Gemini CLI를 동일 인터페이스로 호출.
- **UI 패턴**: Pane splitting (수직/수평), Tab group, AI assistant panel이 별도 dock.
- **Yuminai 적용 후보**: **ACP 호환성** (위 A.6 참조). Zed의 native diff UI 패턴 (inline + side-by-side toggle) 참고.

### B.5 OpenHands — (위 A.5 참조, 72.5k)
- AI 코딩 어시스턴트로도 분류 가능. Local GUI (single-page React)가 SWE-bench 77.6% 성능을 사용자에게 노출. Devin/Jules 류 UX.

### B.6 Goose (block/goose) — 43.6k stars
- **Repo**: https://github.com/aaif-goose/goose (owner 변경됨, 원래 `block/goose`)
- **핵심 컨셉**: Block (Square)이 만든 extensible AI agent. install / execute / edit / test all-in-one. MCP 광범위 지원.
- **Yuminai 적용 후보**: MCP server 패턴 (Yuminai가 이미 채택 중인 MCP 4-server default와 align). 별도 새 패턴 적용은 우선순위 낮음.

---

## C. Diff / Code Review 패턴

### C.1 Reviewdog — 9.3k stars
- **Repo**: https://github.com/reviewdog/reviewdog
- **핵심 컨셉**: 임의 lint 결과를 PR comment로 변환. `lint output → unified diff context → inline PR comment`.
- **Yuminai 적용 후보**: **Inline diff에 comment를 attach하는 데이터 모델**. Diff review UI에서 "이 줄에 대한 LLM의 reasoning" 같은 메타데이터를 inline 표시할 때 reviewdog의 normalization 형식 (`reviewdog -f` formats: rdjson/rdjsonl/checkstyle/sarif) 차용 검토.

### C.2 Aider의 Git diff/commit 패턴
- (위 B.2에서 상세) 핵심: **변경 = commit, undo = revert**. Diff UI 따로 구현 안 해도 git을 단일 진실의 원천으로 쓰면 복잡도 급감.

### C.3 Sweep AI — 7.7k stars
- **Repo**: https://github.com/sweepai/sweep
- **현재 상태**: GitHub PR 자동화에서 JetBrains plugin으로 피벗. issue → PR draft 자동 생성이 원래 패턴.
- **Self-healing**: PR CI 실패 시 sweep이 로그 읽고 자동 수정 PR push.
- **Yuminai 적용 후보**: **Failure → Diff → Auto-fix-attempt loop**의 reference. 단, Yuminai는 PR 단위가 아닌 워크스페이스 단위 → "test fail → diff에 빨간 마커 → 한 클릭 auto-fix request" UX로 변형.

### C.4 Cline의 Editor-native diff (위 B.1 참조)
- 핵심: **diff = editable**. View-only가 아니라 사용자가 직접 손볼 수 있어야 함.

### C.5 GitHub Copilot Workspace (closed source)
- 알려진 패턴: **Spec → Plan → Implementation → PR** 4단계, 각 단계 사용자 승인 게이트. Plan 단계에서 변경 파일 목록 + 의도를 보여주고 승인.
- **Yuminai 적용 후보**: 4-stage gating. Diff review UI를 단순 "accept/reject" 이상으로 spec/plan 검토 단계까지 확장.

---

## D. Software Delivery Loop (자동 build / test / fix)

### D.1 SWE-agent — 19.1k stars
- **Repo**: https://github.com/SWE-agent/SWE-agent (구 `princeton-nlp/SWE-agent`)
- **상태**: **현재 핵심 개발은 [mini-SWE-agent](https://github.com/SWE-agent/mini-SWE-agent)로 이관**. Mini는 100 lines Python으로 SWE-bench verified 65%.
- **핵심 컨셉**: Agent-Computer Interface (ACI) — LLM이 컴퓨터를 효과적으로 다룰 수 있게 명령 인터페이스 자체를 design. NeurIPS 2024.
- **YAML 기반 config**: 단일 yaml로 agent 동작 전체 제어. 도구 추가/수정이 코드 변경 없이 가능.
- **Yuminai 적용 후보**:
  1. **YAML 기반 워크플로우 정의** — Yuminai 워크스페이스 옆에 `.yuminai/workflow.yaml`로 "테스트 실패 시 retry 3회, 그 후 사용자에게 ask" 같은 정책 선언적 기술.
  2. **Mini 단순함의 미덕** — 100 lines로 SOTA 65% 달성한 것은 "복잡한 graph framework 없이도 loop은 충분히 강력하다"는 증거. v0.4 첫 구현은 minimal loop으로 시작.

### D.2 Aider의 `--auto-test --auto-lint` 모드 (위 B.2 참조)
- 가장 단순하고 검증된 loop: change → test → fail이면 결과를 다음 turn 입력으로. **무한 루프 방지: 사용자가 retry 한도 직접 명령** (Aider는 명시적 retry cap 없음 — 대신 매 turn에 사용자가 보고 stop 가능).

### D.3 Devin (Cognition AI, closed)
- 알려진 패턴: **planner agent + executor + browser + IDE** 가상화된 Linux env. State machine으로 task → subtask 분해 → 각 subtask 실행 → 결과 verification.
- **무한 루프 방지**: time budget + step budget + 사용자 confirmation gate.
- **Yuminai 적용 후보**: **Step budget 패턴** — 자동 fix loop에 max-attempts (default 3) + max-time (default 5min) 명시. UI에 카운터 표시.

### D.4 OpenHands runtime (위 A.5 참조)
- Runtime container에서 build/test 격리. Yuminai는 macOS 데스크탑 앱이므로 Docker 의존은 사용자 진입장벽 ↑. 대안: NSTask + sandboxed work dir.

### D.5 Sweep AI self-healing (위 C.3 참조)
- CI fail signal을 trigger로 사용. Yuminai는 자체 build/test runner 호출 → exit code → trigger.

---

## E. Embedded Terminal / Preview Pane

### E.1 VS Code 통합 터미널 (Microsoft VSCode — 184.4k stars)
- **Repo**: https://github.com/microsoft/vscode
- **패턴**: **xterm.js + node-pty**. 터미널 표시는 xterm.js (canvas/webgl renderer), PTY는 node-pty로 native bindings.
- **Shell integration API** (v1.93+): 터미널이 명령 시작/종료, exit code, current dir 등을 호스트에 노출. Cline이 활용한 그 API.
- **Yuminai 적용 후보**: SwiftUI는 xterm.js 사용 불가 (web view 임베드는 가능하나 무겁다). **Swift native 대안**:
  - `SwiftTerm` (https://github.com/migueldeicaza/SwiftTerm) — Miguel de Icaza의 native Swift 터미널. macOS/iOS 양쪽 지원. **Yuminai 1순위 후보**.
  - 또는 `NSTask` + `Pipe`로 PTY 직접 다루고 출력은 SwiftUI Text로 간단 표시 (ANSI escape 파싱 필요).

### E.2 Tabby — 70.9k stars
- **Repo**: https://github.com/Eugeny/tabby
- **핵심 컨셉**: Electron 기반 modern terminal. SSH/serial/local 통합. Plugin 시스템.
- **Yuminai 직접 차용 어려움**: Electron 의존. 단, **탭/스플릿 UX 패턴**은 참고 가치 (vertical split, horizontal split, tab dragging).

### E.3 Ghostty — 53.1k stars
- **Repo**: https://github.com/ghostty-org/ghostty
- **핵심 컨셉**: Native UI + GPU acceleration. Zig로 작성. macOS는 SwiftUI 기반 chrome.
- **Yuminai 적용 후보**: macOS 네이티브 chrome + GPU rendering 패턴은 직접 차용 어렵지만, **macOS terminal feel** (Cmd+T 탭, Cmd+D split 등 macOS 관용 단축키)를 Yuminai에 그대로 적용.

### E.4 xterm.js — 20.4k stars
- **Repo**: https://github.com/xtermjs/xterm.js
- **Yuminai 직접 적용**: WKWebView로 임베드 가능하지만 권장 않음. SwiftTerm이 native UX 측면에서 우월.

### E.5 Warp — 50.8k stars
- **Repo**: https://github.com/warpdotdev/warp
- **핵심 컨셉**: "Agentic development environment, born out of the terminal" — 2026-05 기준 description. 단순 terminal에서 AI dev env로 포지셔닝 변경.
- **Block 단위 출력**: 각 명령 = block (collapse/share 가능). AI가 명령 자체를 자연어로 받아 변환.
- **Yuminai 적용 후보**: **Block-based terminal output**. 단순 stream이 아닌 "command N의 출력 block"을 단위로 → diff review와 일관성 (변경도 block, 출력도 block).

### E.6 SwiftTerm (참고) — 약 1.4k stars
- macOS Swift native 터미널 emulator. v0.4 implementation의 1순위 후보. macOS Native ↔ Yuminai 정체성 alignment 우수.

---

## 종합 — Yuminai v0.4 적용 권고

| # | 주제 | 1순위 레퍼런스 | 핵심 차용 패턴 | 구현 복잡도 | 신뢰도 |
|---|------|---------------|---------------|------------|-------|
| 1 | 멀티 에이전트 패널 | **AutoGen `AgentTool`** + Aider Architect/Editor | 메인 에이전트(Claude)가 보조(Codex)를 tool로 호출. 워크스페이스 한 패널에 2 stream 표시 (좌/우 또는 상/하 split). | **L** | High (둘 다 production-tested) |
| 2 | 인터-에이전트 메시지 | **MetaGPT 메시지 환경** + AutoGen group chat speaker selection | 워크스페이스에 internal message bus. `@codex` 멘션 = bus publish. UI에서 메시지 source/target 라벨링. | **M** | High |
| 3 | Diff review UI | **Cline editable diff** + **Aider git-as-source-of-truth** | 매 변경 = git commit. Diff view는 editable. accept = stage, reject = `git revert HEAD`. Restore checkpoint 추가. | **L** | High |
| 4 | Software delivery loop | **Aider `--auto-test --auto-lint`** + Devin step budget | 단순 loop으로 시작 (test fail → 결과 다음 turn). Max-attempts=3, max-time=5min hard cap. SWE-agent의 yaml policy는 v0.5 이후. | **M** | Moderate (mini-SWE-agent 검증되긴 했으나 Yuminai 환경에서 retest 필요) |
| 5 | Embedded terminal/preview | **SwiftTerm** (Swift native PTY) + Warp block UX | SwiftTerm을 워크스페이스 패널에 dock. 출력을 block 단위로 그룹핑하여 collapse/share 지원. WebView 기반 preview는 WKWebView로 별도. | **M-L** | Moderate (SwiftTerm 통합 사례 적음, but Miguel de Icaza의 검증된 라이브러리) |

### 횡단 결정 — 차후 메이저 분기점

| 결정 사항 | 권고 시점 | 영향 |
|---------|---------|-----|
| **ACP (Agent Client Protocol) 채택 여부** | v0.4 마감 ~ v0.5 시작 사이 | 채택 시 외부 에이전트 자동 호환 + obsidian-agent-client 같은 인접 프로젝트 코드 reuse. Swift SDK 없음 → 자체 작성 필요. |
| **Runtime sandbox (Docker vs NSTask)** | v0.4 D번 (delivery loop) 설계 시 | Docker = OpenHands급 격리 but 사용자 부담. NSTask = macOS native but 격리 약함. Yuminai 정체성상 NSTask + sandboxed dir 권장. |
| **Diff UI: editable vs view-only** | v0.4 C번 시작 시 | Editable이 Cline UX 강점이지만 SwiftUI native diff editor 부재 → 구현 비용 큼. v0.4는 view-only로 시작 + accept/reject 명확히, editable은 v0.5. |

### 핵심 인사이트 (의사결정 근거)

1. **MetaGPT 67.6k / OpenHands 72.5k**가 카테고리 A에서 압도적. AutoGen은 maintenance mode이므로 신규 차용은 패턴만 가져오고 코드 의존은 권장하지 않음.
2. **Aider의 Architect/Editor 내부 2-LLM 패턴**은 멀티 에이전트 구현의 가장 검증된 minimal 형태 — 67.6k MetaGPT 같은 거대한 framework 없이도 핵심 가치 (역할 분리)를 얻을 수 있음.
3. **Cline의 checkpoint/restore + editable diff**는 Diff review UI의 SOTA. 단, editable diff는 SwiftUI에서 비용이 큼 → v0.4는 checkpoint만 우선.
4. **mini-SWE-agent 100 LoC로 65% SWE-bench**는 "loop은 단순할수록 좋다"는 강한 증거 — v0.4 delivery loop은 graph/state machine 없이 단순 retry counter로 충분.
5. **Agent Client Protocol (ACP)**은 Yuminai의 정확한 use case에 대한 표준으로 부상 중 (Zed push, Obsidian client 1.9k stars). 자체 wire protocol vs ACP 채택은 v0.4 마감 시점 별도 의사결정 필요. Swift SDK 부재가 주요 리스크.

### Confidence Notes

- **High**: 카테고리 A, B의 1순위 레퍼런스들은 50k+ stars 및 production 사용처 명확. 패턴은 직접 차용 안전.
- **Moderate**: 카테고리 D (delivery loop)는 production 사례가 도구별로 차이 큼 — Aider의 auto-test는 검증, OpenHands runtime은 enterprise context. Yuminai 환경 (1ws-1agent, Telegram 양방향)에서 재검증 필요.
- **Low**: SwiftTerm의 Yuminai 통합은 사전 사례 부족 → v0.4 PoC 단계에서 spike 1-2일 권장.
- **Speculative**: ACP 채택의 ROI는 외부 에이전트 생태계 성장 속도에 의존 — 2026 하반기 추가 관찰 후 결정 권장.

### 출처 요약 (정확한 스타 수, 2026-05-01 GitHub API)

| Repo | Stars | URL |
|------|------:|-----|
| microsoft/vscode | 184,445 | https://github.com/microsoft/vscode |
| zed-industries/zed | 81,045 | https://github.com/zed-industries/zed |
| OpenHands/OpenHands | 72,450 | https://github.com/OpenHands/OpenHands |
| Eugeny/tabby | 70,851 | https://github.com/Eugeny/tabby |
| FoundationAgents/MetaGPT | 67,596 | https://github.com/FoundationAgents/MetaGPT |
| openinterpreter/open-interpreter | 63,362 | https://github.com/openinterpreter/open-interpreter |
| alacritty/alacritty | 63,800 | https://github.com/alacritty/alacritty |
| cline/cline | 61,239 | https://github.com/cline/cline |
| microsoft/autogen | 57,634 | https://github.com/microsoft/autogen |
| ghostty-org/ghostty | 53,102 | https://github.com/ghostty-org/ghostty |
| warpdotdev/warp | 50,785 | https://github.com/warpdotdev/warp |
| crewAIInc/crewAI | 50,410 | https://github.com/crewAIInc/crewAI |
| Aider-AI/aider | 44,194 | https://github.com/Aider-AI/aider |
| aaif-goose/goose | 43,629 | https://github.com/aaif-goose/goose |
| continuedev/continue | 32,907 | https://github.com/continuedev/continue |
| langchain-ai/langgraph | 30,975 | https://github.com/langchain-ai/langgraph |
| voideditor/void | 28,692 | https://github.com/voideditor/void |
| wezterm/wezterm | 25,864 | https://github.com/wezterm/wezterm |
| xtermjs/xterm.js | 20,412 | https://github.com/xtermjs/xterm.js |
| SWE-agent/SWE-agent | 19,116 | https://github.com/SWE-agent/SWE-agent |
| reviewdog/reviewdog | 9,258 | https://github.com/reviewdog/reviewdog |
| sweepai/sweep | 7,710 | https://github.com/sweepai/sweep |
| agentclientprotocol/agent-client-protocol | 2,981 | https://github.com/agentclientprotocol/agent-client-protocol |

### Follow-up 리서치 후보 (v0.4 범위 외)

1. **ACP Swift SDK 자체 구현 비용 추정** — TypeScript SDK 코드 양 + JSON-RPC 매핑 난이도 분석.
2. **SwiftTerm 실측 통합 PoC** — macOS SwiftUI 앱에 1일 spike 결과 평가.
3. **Microsoft Agent Framework (AutoGen 후속)** — 2026 후반 stable 시점에 재평가, 멀티 에이전트 패턴 비교.
4. **mini-SWE-agent 100 LoC 직접 읽기** — Yuminai delivery loop의 reference impl로 line-by-line 해부.
5. **Obsidian Agent Client (1.9k stars) 코드 reading** — Yuminai와 인접 use case이므로 차용 가능 패턴 탐색.
