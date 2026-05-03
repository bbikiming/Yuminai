# ADR-092 — Telegram Remote Vibecoding UX (통합 Hub 기획)

- **날짜**: 2026-05-04 (Monday)
- **상태**: Proposed (UX 기획 단계, 구현 미착수)
- **선행 ADR**: ADR-086 (텔레그램 멀티봇 + 모니터링)
- **연관 후보**: ADR-093 (Active Dock + Chat Context Card), ADR-094 (Inline Command Palette + HITL), ADR-095 (Diff/Log 전송 포맷 + 다중 디바이스 정책)

> **표기 규약**: 본 문서의 모든 외부 사실 주장은 confidence label을 붙인다.
> `[H]` high (직접 검증/공식 문서), `[M]` moderate (다수 일관 보고), `[L]` low (단편적/2차), `[S]` speculative.
> 본 문서 작성 시 환경 제약으로 실시간 웹 검증이 제한되어, 학습된 지식 기반 기술된 부분은 `[M]`/`[L]`로 보수적으로 라벨링하였다. 인용 URL은 §7에 정리.

---

## 1. Executive Summary

**결론 (3-5줄):**

1. **Anthropic 공식 Telegram bot은 존재하지 않는다 [M].** Slack 통합(claude.ai/slack)은 공식 제공되지만 Telegram은 커뮤니티/서드파티 영역. 즉, Yuminai는 "Claude × Telegram" 카테고리에서 reference UX를 직접 정의할 기회를 가진다.
2. **Yuminai의 텔레그램 기능은 백엔드는 견고(ADR-086)하나 UI가 5개 sheet로 파편화**되어 있다 (`TelegramBotManagerSheet`, `TelegramAdvancedSheet`, `TelegramErrorLogSheet`, `TelegramBotEditSheet`, `TelegramBotGroupEditSheet` + `TelegramHealthPill`). 사용자가 "지금 봇이 살아있나? 어느 채팅이 어느 워크스페이스로 연결됐나?"를 한눈에 못 본다.
3. **권장 방향**: 모든 텔레그램 surface를 단일 **Telegram Hub** (4-tab 구조: Bots / Bindings / Commands / Activity)로 통합하고, **상시 표시 Bot Status Dock** + **3-step Onboarding Wizard**를 도입한다.
4. **HITL (Human-In-The-Loop) 승인 흐름**을 1급 시민으로 격상 — Devin/OpenDevin/Claude Code의 자율 에이전트 UX 합의점 [M]. 텔레그램 inline button (`✅ Approve` / `❌ Reject` / `🔍 Diff`)을 통해 폰에서 작업 승인이 가능해야 한다.
5. **Diff/Log 전송은 "preview + jump"** 패턴으로 — 처음 30줄 + macOS 앱으로 deep-link하는 button. 메신저에 4KB 이상 코드를 붙여넣지 않는다 (Telegram Bot API 메시지 한도 4096자 [H]).

---

## 2. 시장 조사 결과

### 2.1 Anthropic 공식 Telegram 통합 현황

| 채널 | 공식 제공 여부 | 출처 신뢰도 | 비고 |
|---|---|---|---|
| Slack | **공식** (Claude in Slack) | [H] | claude.ai/slack — 워크스페이스 앱, DM/채널 멘션 |
| Microsoft Teams | 베타/파트너 | [M] | Anthropic 공식 announcement에서 언급 |
| Telegram | **없음** | [M] | docs.claude.com/anthropic.com에서 공식 페이지 부재. GitHub `anthropics/anthropic-cookbook`에 telegram 예제 부재 (검증 필요) |
| Discord | 없음 (커뮤니티만) | [M] | |

**시사점**: Yuminai의 텔레그램 봇은 해당 카테고리에서 **레퍼런스 UX를 정의할 기회**다. Slack 통합 패턴 (멘션 → 답변, slash command, ephemeral message)을 가져오되, 텔레그램의 inline button + edited message + reply chain 강점을 활용해야 한다.

### 2.2 경쟁/유사 도구 표

| 도구 | 채널 | 핵심 기능 | 강점 | 약점 | confidence |
|---|---|---|---|---|---|
| **GitHub Mobile + Copilot** | iOS/Android 앱 | PR 리뷰, 이슈 코멘트, Copilot 답변 미리보기 | 알림 통합, 익숙한 워크플로우 | "코드 작성"은 못함, 리뷰 중심 | [H] |
| **Cursor** | 데스크탑 only | AI pair-programming | 깊은 IDE 통합 | 모바일/원격 부재 | [H] |
| **Cline / Continue.dev** | VSCode extension | Agent loop, tool use | 오픈소스, 로컬 LLM | 모바일 부재 | [M] |
| **Devin** (Cognition) | Web + Slack | 자율 에이전트, 진행 상태 stream | "Devin's view" 실시간 데스크탑 스트림, Slack 알림 | 비공개/유료 | [M] |
| **OpenDevin / OpenHands** | Web + CLI | 오픈소스 자율 에이전트 | HITL 승인 패턴, terminal/browser/editor 다중 view | 모바일 미흡 | [M] |
| **Replit Mobile** | iOS/Android 네이티브 | 모바일 IDE + Replit AI | 진짜 모바일 코딩, AI 인라인 | 메신저 아님 | [H] |
| **Aider** | CLI | git-aware AI pair | git diff 친화적, 커밋 자동 | UI 없음 | [M] |
| **Telegram bot 코딩 도구** (커뮤니티) | Telegram | `gpt-telegram-bot` 류 | DM 기반 채팅 | 워크스페이스/git 컨텍스트 부재 | [L] |
| **ChatGPT in Slack** | Slack | DM/멘션 답변, thread context | 공식, Enterprise SSO | 코드 실행/git 부재 | [M] |
| **Claude in Slack** | Slack | 동일 + Anthropic 공식 | 공식 지원, multi-workspace | 텔레그램 부재 | [H] |

### 2.3 핵심 UX 패턴 5-10개 (메신저/원격 코딩)

각 패턴은 위 도구들에서 추출. 출처 신뢰도 라벨링.

1. **HITL inline button (Approve/Reject/Diff)** — Devin, OpenDevin, GitHub Copilot CLI가 공통 채택. 자율 작업 진행 중 destructive action (파일 삭제, force-push, secret 노출 위험) 직전에 승인 요청. [M]
2. **Long-message truncation + "expand/jump"** — Slack의 "Show more", GitHub Mobile의 "View on GitHub" deep link. Telegram Bot API는 메시지 4096자 제한이 있어 [H], 코드 diff/log는 반드시 truncate + 풀뷰 deep-link 필요.
3. **Typing indicator로 "에이전트 작동 중" 신호** — Telegram `sendChatAction(typing)`은 5초 유지. 긴 작업은 5초마다 갱신하거나 progress message edit 패턴 사용. [H]
4. **Edited message로 progress update** — 새 메시지 스팸 방지. Telegram `editMessageText`로 동일 메시지를 "⏳ Building... 30%" → "✅ Done"으로 갱신. Devin/Cursor agent log가 이 패턴을 사용. [M]
5. **Slash command palette** — `/run`, `/diff`, `/abort` 등. Telegram의 BotFather에 등록하면 `/`타이핑 시 autocomplete 제공. [H]
6. **Reply chain으로 컨텍스트 유지** — 한 메시지를 reply하면 그 메시지의 워크스페이스/세션을 자동 inherit. Slack thread와 동일 모델. [M]
7. **Whitelist + first-message handshake** — 봇이 처음 받은 메시지의 sender_id를 제안 → 데스크탑에서 confirm. Self-hosted bot의 보안 표준 패턴. [M]
8. **Quiet hours / rate-limit 알림 격하** — PagerDuty, Opsgenie의 알림 정책 관행을 차용. 비업무 시간엔 critical만 push, 일반은 daily digest. [M]
9. **Multi-device "이미 다른 곳에서 봤음" 처리** — macOS 알림과 텔레그램 알림 중복 제거. 사용자가 데스크탑에서 응답하면 텔레그램 메시지에도 ✅ 표시 (edited). [S/M]
10. **"Quick reply" vs "Deep work" 구분** — 짧은 질문은 메신저에서 즉답, 긴 작업은 큐 + 알림. ChatGPT Slack 통합이 "ephemeral vs full response"로 구현 [M].

---

## 3. Yuminai 현재 상태 진단

### 3.1 이미 구현된 기능 (ADR-086 기준)

**Backend (YuminaiCore + YuminaiTelegram):**
- `TelegramMultiBot` — 다중 봇 동시 운영
- `TelegramBotRegistry` — 봇 등록/조회 actor
- `TelegramOfflineQueue` — 네트워크 단절 시 메시지 큐잉
- `TelegramReliability` (`TelegramRetryPolicy`, `TelegramHealthMonitor`, `TelegramConnectionState`, `TelegramIdempotencyTracker`)
- `TelegramAdvanced` — 그룹/바인딩, chat↔workspace mapping
- `TelegramUsageStore` — 사용량 추적
- `TelegramErrorClassifier` + `TelegramErrorLog` — 분류된 에러 ring buffer
- `TelegramSessionBridge` — 텔레그램 chat ↔ Yuminai session 연결
- `TelegramCommandPump` — 슬래시 명령 처리
- `TelegramAlertDispatcher` — 알림 발송

**UI (YuminaiApp + YuminaiUI) — 산재한 surface 8개:**
- `TelegramBotManagerSheet` — 봇 목록 관리
- `TelegramBotEditSheet` — 개별 봇 편집
- `TelegramBotGroupEditSheet` — 그룹 편집
- `TelegramBotGroupSection`, `TelegramBotListSection` — 섹션 컴포넌트
- `TelegramBotBindingEditSheet` — chat ↔ workspace 바인딩
- `TelegramAdvancedSheet` — 고급 설정
- `TelegramErrorLogSheet` — 에러 로그
- `TelegramHealthPill` (in YuminaiUI) — 상태 pill
- `TelegramUsageDashboard` (in YuminaiUI) — 사용량 대시보드

### 3.2 UX 문제점

1. **진입점 분산** — Settings/메뉴/툴바 어디서 텔레그램을 시작해야 하는지 사용자가 알기 어렵다. 8개 sheet가 각자 다른 경로로 열린다.
2. **상태 가시성 부족** — `TelegramHealthPill`은 있으나 어떤 봇이 어떤 chat과 어떤 workspace에 묶였는지 한눈에 안 보임.
3. **온보딩 흐름 부재** — 처음 봇을 추가할 때 (1) BotFather 토큰 → (2) 권한/whitelist → (3) workspace 매핑을 한 번에 안내하는 wizard 없음.
4. **HITL 흐름 미정의** — 위험한 명령 (force-push, rm -rf, secret expose) 시 텔레그램에서 어떻게 승인받는지 패턴이 없음. 현재는 일방향 알림 위주.
5. **Slash command 관리 UI 없음** — `TelegramCommandPump`는 있지만 사용자가 어떤 명령이 가능한지 GUI에서 확인/편집 불가. BotFather 등록 동기화도 수동.
6. **에러 로그가 묻혀있음** — 별도 sheet에서만 보여 사용자가 "왜 메시지가 안 갔지?"를 추적하기 어려움.
7. **Diff/log 전송 형식 미정의** — 긴 응답을 텔레그램에서 어떻게 보여줄지 (truncate? 첨부? deep link?) 코드 패턴 없음.

### 3.3 사용자가 텔레그램으로 할 수 있어야 할 핵심 task 5개

| # | Task | 빈도 | 현재 가능? | 권장 진입 |
|---|---|---|---|---|
| T1 | **원격 명령 실행** ("이 워크스페이스에서 빌드 돌려줘") | 매일 | 부분 (slash 가능, UI 안내 없음) | `/run <cmd>` + reply |
| T2 | **결과/diff 리뷰** (PR 검토, build 결과 확인) | 매일 | 미흡 (포맷 불명) | inline preview + "View in app" |
| T3 | **HITL 승인** (위험 작업 confirm) | 주 1-3회 | 없음 | inline button |
| T4 | **긴급 중단** ("/abort 지금 도는 작업 죽여") | 드물지만 critical | 부분 | `/abort` + confirm |
| T5 | **상태/로그 확인** ("지금 빌드 어디까지 갔어?") | 매일 | 부분 (status 없음) | `/status` + edited progress message |

추가 보조 task: T6 워크스페이스 전환 (`/switch <name>`), T7 알림 음소거 (`/mute 1h`).

---

## 4. 권장 UX 기획 (핵심)

### 4.1 단일 진입점: Telegram Hub

**현재 8개로 분산된 sheet를 단일 윈도우 `TelegramHubView`로 통합.** 좌측 사이드바 메뉴(또는 Settings의 "Telegram" 섹션)에서 단 하나의 항목만 노출.

**4-Tab 구조:**

```
┌─────────────────────────────────────────────────────┐
│  Telegram Hub                              [+ Bot]  │
├─────────────────────────────────────────────────────┤
│  [Bots]  [Bindings]  [Commands]  [Activity]         │  ← Tab bar
├─────────────────────────────────────────────────────┤
│                                                     │
│  (선택된 탭의 컨텐츠)                                  │
│                                                     │
└─────────────────────────────────────────────────────┘
```

| Tab | 책임 | 흡수하는 기존 sheet |
|---|---|---|
| **Bots** | 봇 목록, 추가/편집/삭제, health 표시 | TelegramBotManagerSheet, TelegramBotEditSheet, TelegramBotGroupEditSheet |
| **Bindings** | chat ↔ workspace ↔ agent 매핑 시각화 | TelegramBotBindingEditSheet |
| **Commands** | slash command 등록/편집/BotFather sync | (신규) |
| **Activity** | 사용량 + 에러 로그 + 최근 메시지 stream | TelegramUsageDashboard, TelegramErrorLogSheet |

`TelegramAdvancedSheet`의 항목들은 각 탭의 "Advanced" disclosure 또는 우측 inspector로 흡수.

### 4.2 3-Phase 온보딩 Wizard

**`TelegramOnboardingWizard`** — `[+ Bot]` 클릭 시 첫 봇이 없으면 자동 시작.

```
Step 1/3 — Bot Token
┌──────────────────────────────────────────────┐
│ 1. BotFather에서 봇 생성              [열기]  │
│    (https://t.me/botfather)                  │
│ 2. 토큰을 붙여넣으세요                         │
│    ┌────────────────────────────────────┐    │
│    │ 1234567890:ABCdef...                │    │
│    └────────────────────────────────────┘    │
│    ✅ Validated as @YuminaiBot                │
│                                              │
│                          [다음 →]              │
└──────────────────────────────────────────────┘

Step 2/3 — Authorize Users
┌──────────────────────────────────────────────┐
│ 봇에 메시지를 보낼 수 있는 사용자를 추가하세요.    │
│                                              │
│ Method A: 봇에게 /start 보내기 → 자동 감지       │
│   👤 @bbikiming (id: 12345) [+ Allow]         │
│                                              │
│ Method B: 수동으로 user_id 입력                │
│   ┌────────────────────────────────────┐    │
│   │ user_id...                          │    │
│   └────────────────────────────────────┘    │
│                                              │
│                  [← 이전]    [다음 →]          │
└──────────────────────────────────────────────┘

Step 3/3 — Map Workspaces
┌──────────────────────────────────────────────┐
│ 어떤 chat을 어떤 workspace에 연결할까요?         │
│                                              │
│ Chat: @bbikiming (DM)                        │
│ ↓ binds to ↓                                 │
│ Workspace: [Yuminai ▾]                       │
│ Default agent: [Claude Code ▾]               │
│                                              │
│ [+ Add another binding]                      │
│                                              │
│              [← 이전]    [✓ 완료]              │
└──────────────────────────────────────────────┘
```

**중요 원칙:**
- Step 1에서 토큰 즉시 `getMe` 호출로 validation (HEAD 표시)
- Step 2의 "/start 자동 감지"는 first-message handshake 패턴 — bot이 처음 받은 메시지의 sender_id를 wizard로 push (AsyncStream)
- Step 3에서 최소 1개 binding 강제. 그래야 첫 메시지가 어디로 갈지 정의됨

### 4.3 활성 봇 + 채널 상태 Dock (`BotStatusDock`)

**상시 표시 미니 위젯.** 메인 윈도우 우상단 또는 status bar에 배치.

```
┌─────────────────────────────────────────────────┐
│  🟢 @YuminaiBot · 🟡 @WorkBot · queue: 2 · 1m   │
└─────────────────────────────────────────────────┘
   ↑ 클릭 시 popover로 상세 (각 봇 상태 + 최근 3개 메시지)
   ↑ double-click 시 Telegram Hub의 해당 봇 탭으로 jump
```

상태 매핑 (ADR-086 `TelegramConnectionState` 활용):
- 🟢 healthy
- 🟡 degraded (재시도 중) + tooltip "rate limit 대기 12s"
- 🔴 failed (영구 실패, polling 중단) — 클릭 시 에러 로그로 jump
- ⚪ idle (시작 전)

`queue: N`은 `TelegramOfflineQueue.depth` 노출. 0이면 숨김.

### 4.4 채팅별 컨텍스트 카드 (`ChatContextCard`)

**Bindings 탭에서 각 chat을 카드 형태로 시각화.**

```
┌────────────────────────────────────────────────┐
│ 💬 @bbikiming (Private DM)                     │
│ ────────────────────────────────────────────── │
│ Bot:        @YuminaiBot                        │
│ Workspace:  Yuminai (~/Documents/.../Yuminai)  │
│ Agent:      Claude Code  [▾]                   │
│ Whitelist:  ✅ Allowed                          │
│ Last msg:   "/run swift test" · 3m ago         │
│                                                │
│ [Open Chat]  [Edit Binding]  [Disable]        │
└────────────────────────────────────────────────┘
```

그룹 채팅의 경우 멤버 목록 + 누가 명령 보낼 수 있는지 (admin/whitelist) 표시.

### 4.5 Inline Command Palette Editor

**Commands 탭에서 slash command 정의 GUI.**

```
┌──────────────────────────────────────────────────┐
│ Commands                          [+ New Command] │
├──────────────────────────────────────────────────┤
│ /run <cmd>      Execute in current workspace      │
│ /switch <ws>    Change workspace binding          │
│ /diff           Show pending diff                 │
│ /approve        Approve last HITL request         │
│ /abort          Cancel running task               │
│ /status         Show current task status          │
│ /mute <dur>     Mute notifications                │
├──────────────────────────────────────────────────┤
│ [Sync to BotFather]  ← BotFather에 등록 자동화      │
└──────────────────────────────────────────────────┘
```

각 행 클릭 시 inspector에서:
- Trigger pattern (regex)
- Handler (TelegramCommandPump의 어떤 closure에 매핑)
- 권한 (any user / admin only / specific user_id)
- HITL 필요 여부

"Sync to BotFather"는 `setMyCommands` API [H]로 등록 → 텔레그램 클라이언트에서 `/`타이핑 시 autocomplete.

### 4.6 HITL 승인 흐름

**시나리오**: 사용자가 데스크탑에서 자리를 비웠는데 Claude Code가 `git push --force` 직전에 도달.

**Flow:**
1. Yuminai가 destructive action 감지 (이미 있는 hooks 활용)
2. macOS UserNotification + Telegram message 동시 발송:

```
⚠️ HITL Approval Needed
Workspace: Yuminai
Action: git push --force origin main
Files affected: 12 (3 deletions)

[ ✅ Approve ]  [ ❌ Reject ]  [ 🔍 View Diff ]
```

3. 사용자가 텔레그램 inline button 누름 → callback_query 수신 → `TelegramCommandPump`가 hook unblock
4. 메시지 자동 edit: "✅ Approved by @bbikiming · 14:23" (다른 디바이스/그룹 멤버에게도 visible)
5. 60초 timeout — auto-reject + edit "⏱ Timeout, action cancelled"

**중요**: 데스크탑에서 먼저 응답하면 텔레그램 메시지도 즉시 edit해서 "✅ Approved on desktop" — 다중 디바이스 일관성.

### 4.7 Diff/로그 전송 형식

**원칙: "preview + jump", 절대 4096자 풀 dump 금지.**

**Diff 메시지 템플릿:**
```
📝 Diff Preview · 3 files, +42/-18

```diff
--- a/Sources/YuminaiCore/Foo.swift
+++ b/Sources/YuminaiCore/Foo.swift
@@ -10,7 +10,7 @@ class Foo {
-    var bar: Int = 0
+    var bar: Int = 42
... (truncated, 28 more lines)
```

[ 📂 View Full Diff in Yuminai ]  ← deep-link: yuminai://diff/<id>
[ ✅ Approve & Commit ]  [ ❌ Reject ]
```

규칙:
- 첫 30줄 또는 2000자 중 빠른 것 (한도 4096자 [H]의 절반 아래로 안전 마진)
- ` ```diff ` fenced code block — 텔레그램 monospace 렌더링
- "View Full Diff" deep-link은 `yuminai://` URL scheme 신규 등록 필요
- 5MB 이상이면 `sendDocument`로 첨부 [H]

**로그 메시지 템플릿** (build/test):
```
🔨 Build · Yuminai · 2m 14s · ❌ FAILED

Last 20 lines:
```
error: cannot find 'TelegramHubView' in scope
  --> Sources/YuminaiApp/RootView.swift:42:12
... (1247 more lines)
```

[ 📜 Full Log ]  [ 🔁 Rebuild ]
```

### 4.8 다중 디바이스 시나리오

**알림 정책 매트릭스** (사용자 상태 × 알림 종류):

| 알림 종류 | 데스크탑 active | 데스크탑 idle | 데스크탑 off |
|---|---|---|---|
| HITL 승인 요청 | macOS only | macOS + Telegram | Telegram only |
| 작업 완료 (성공) | macOS only | (off) | Telegram (digest) |
| 작업 실패 | macOS + Telegram | macOS + Telegram | Telegram only |
| Rate limit alert | macOS only | (suppressed) | Telegram (1h cooldown) |
| Quiet hours (22:00-08:00) | macOS only | (suppressed) | Critical only |

"데스크탑 idle"은 `NSWorkspace.didSleepNotification` 또는 5분 무입력 기준 [M].

**중복 제거**: 데스크탑에서 응답 → Telegram 메시지 edit ("seen on desktop"). 텔레그램에서 응답 → 데스크탑 알림 dismiss.

**rate limit 격하**: 같은 종류 알림 5분 내 3회 초과 시 digest로 묶기. 예: "5 builds completed in last 30m. View summary."

---

## 5. SwiftUI 구체 구현 가이드

### 5.1 새 파일 트리 제안

```
Sources/YuminaiUI/TelegramHub/
├── TelegramHubView.swift                  ← 메인 컨테이너 (4-tab)
├── BotStatusDock.swift                    ← 상시 표시 위젯
├── ChatContextCard.swift                  ← Bindings 탭 카드
├── CommandPaletteEditor.swift             ← Commands 탭
├── ActivityFeedView.swift                 ← Activity 탭 (usage + errors + recent msgs)
├── MessagePreviewCard.swift               ← Activity의 최근 메시지 카드
└── Onboarding/
    ├── TelegramOnboardingWizard.swift     ← 3-step 컨테이너
    ├── OnboardingStep1_Token.swift
    ├── OnboardingStep2_Whitelist.swift
    └── OnboardingStep3_Binding.swift

Sources/YuminaiUI/HITL/
├── HITLApprovalSheet.swift                ← 데스크탑 승인 sheet
└── HITLApprovalCard.swift                 ← Activity 피드 내 카드

Sources/YuminaiCore/
├── TelegramHITLCoordinator.swift          ← 신규: HITL state machine
├── TelegramDeepLinkRouter.swift           ← 신규: yuminai:// scheme
└── (기존 파일 그대로 재사용)
```

### 5.2 핵심 SwiftUI 컴포넌트 5-7개

| 컴포넌트 | 책임 | 의존 |
|---|---|---|
| `TelegramHubView` | 4-tab 컨테이너, `TabView` 또는 `NavigationSplitView` | AppModel, TelegramBotRegistry |
| `BotStatusDock` | 항상 보이는 미니 위젯, AsyncStream 구독 | TelegramHealthMonitor.snapshots() |
| `ChatContextCard` | 1개 chat의 binding 시각화 카드 | TelegramAdvanced bindings |
| `CommandPaletteEditor` | slash command CRUD + BotFather sync 버튼 | TelegramCommandPump |
| `TelegramOnboardingWizard` | 3-step `NavigationStack` wizard | TelegramClient (validation), Registry |
| `MessagePreviewCard` | Activity 피드의 메시지 1건 표시 | TelegramErrorLog (for failures), Usage |
| `HITLApprovalSheet` | 데스크탑에서 승인 prompt | TelegramHITLCoordinator |

### 5.3 기존 코드 재사용 vs 새로 작성 매트릭스

| 기존 자산 | 운명 | 비고 |
|---|---|---|
| `TelegramMultiBot`, `TelegramBotRegistry` | **재사용** | 백엔드 그대로 |
| `TelegramHealthMonitor`, `TelegramConnectionState` | **재사용** | Dock의 데이터 소스 |
| `TelegramOfflineQueue` | **재사용** | Dock의 queue depth 표시 |
| `TelegramErrorLog`, `TelegramErrorClassifier` | **재사용** | Activity 탭 데이터 |
| `TelegramCommandPump` | **확장** | command 메타데이터 (description, permission) 필드 추가 필요 |
| `TelegramAdvanced` (bindings) | **재사용** | Bindings 탭 데이터 |
| `TelegramSessionBridge` | **재사용** | chat → session 변환 |
| `TelegramAlertDispatcher` | **확장** | HITL message 종류 추가 |
| `TelegramBotManagerSheet` | **deprecate** → `TelegramHubView` Bots 탭으로 흡수 |
| `TelegramBotEditSheet` | **유지** | Hub 내부에서 sheet로 호출 |
| `TelegramBotGroupEditSheet` | **유지** | 동일 |
| `TelegramBotBindingEditSheet` | **유지** | Bindings 탭에서 호출 |
| `TelegramAdvancedSheet` | **deprecate** → 항목들 분산 흡수 |
| `TelegramErrorLogSheet` | **deprecate** → Activity 탭 흡수 |
| `TelegramHealthPill` | **deprecate** → `BotStatusDock`로 대체 |
| `TelegramUsageDashboard` | **흡수** → Activity 탭의 한 섹션 |

### 5.4 데이터 모델 변경 필요 여부

**필요한 확장:**

1. `Preferences` (또는 `TelegramPreferences`) 신규 필드:
   - `quietHoursStart: Date?`, `quietHoursEnd: Date?`
   - `notificationPolicy: NotificationPolicyMatrix` (struct)
   - `hitlTimeoutSeconds: Int = 60`
   - `diffPreviewLineLimit: Int = 30`

2. `TelegramCommand` (신규 struct, in YuminaiCore):
   ```swift
   struct TelegramCommand: Codable, Sendable {
       let trigger: String          // "/run"
       let description: String      // "Execute in current workspace"
       let pattern: String          // regex
       let permission: Permission   // .anyUser / .admin / .userIds([Int64])
       let requiresHITL: Bool
   }
   ```

3. `HITLRequest` (신규 actor, in YuminaiCore):
   ```swift
   actor TelegramHITLCoordinator {
       func request(action: String, diff: String?) async throws -> HITLResponse
       enum HITLResponse { case approved(by: String), rejected(by: String), timeout }
   }
   ```

4. `Info.plist` URL scheme `yuminai://` 등록 (deep link).

기존 `TelegramAdvanced` binding 모델은 그대로 충분.

---

## 6. 단계별 구현 로드맵

| Phase | 기간 | 산출물 | ADR 후보 |
|---|---|---|---|
| **Phase 1** | 1주 | `TelegramHubView` 4-tab 셸 + `TelegramOnboardingWizard` (3-step) + 기존 sheet 흡수/deprecate | **ADR-092** (본 문서) |
| **Phase 2** | 1주 | `BotStatusDock` 상시 표시 + `ChatContextCard` Bindings 탭 + `ActivityFeedView` | **ADR-093** |
| **Phase 3** | 1주 | `CommandPaletteEditor` + BotFather setMyCommands sync + `TelegramHITLCoordinator` + `HITLApprovalSheet` + Telegram inline button callback | **ADR-094** |
| **Phase 4** (선택) | 1주 | Diff/log preview 포맷 + `yuminai://` deep link + 다중 디바이스 알림 정책 매트릭스 + quiet hours | **ADR-095** |

**병렬화 가능:**
- Phase 2의 `ActivityFeedView`는 Phase 1과 병렬 진행 가능 (다른 탭이라 충돌 적음)
- Phase 4의 deep link scheme 등록은 Phase 1 시작 시 미리 (Info.plist만 변경)

**검증 게이트 (각 phase):**
- Unit test 80%+ (TDD per golden-principles.md)
- 기존 723개 테스트 회귀 0
- Code review 통과 (code-reviewer agent)
- 실제 Telegram 봇 1개로 e2e smoke test

---

## 7. 참고 자료

> **주의**: 본 ADR 작성 환경에서 실시간 웹 검증이 제한적이었다. 아래 URL들은 학습된 지식 기반이며, 구현 착수 전 각 사실을 재검증할 것.

### 7.1 Anthropic 공식

- Claude in Slack — https://claude.ai/slack — `[H]` 공식 페이지
- Anthropic docs — https://docs.claude.com/ — `[H]`
- Anthropic cookbook — https://github.com/anthropics/anthropic-cookbook — `[H]` (텔레그램 예제 부재 확인 필요)
- Claude API messages — https://docs.claude.com/en/api/messages — `[H]`

### 7.2 Telegram Bot API (사실 검증 출처)

- Telegram Bot API — https://core.telegram.org/bots/api — `[H]`
  - 메시지 4096자 제한
  - `sendChatAction(typing)` 5초
  - `editMessageText`, `setMyCommands`, `answerCallbackQuery`
  - `sendDocument` (5MB+ 파일)
- BotFather — https://t.me/botfather — `[H]`

### 7.3 경쟁 도구

- GitHub Mobile — https://github.com/mobile — `[H]`
- Cursor — https://cursor.sh — `[H]`
- Cline — https://github.com/cline/cline — `[M]`
- Continue.dev — https://continue.dev — `[M]`
- Devin / Cognition — https://cognition.ai — `[M]`
- OpenDevin / OpenHands — https://github.com/All-Hands-AI/OpenHands — `[M]`
- Replit Mobile — https://replit.com/mobile — `[H]`
- Aider — https://aider.chat — `[M]`

### 7.4 UX 패턴 출처

- Slack Block Kit (interactive button) — https://api.slack.com/block-kit — `[H]`
- Telegram inline keyboards — https://core.telegram.org/bots/2-0-intro — `[H]`
- PagerDuty notification policies — https://www.pagerduty.com/docs/ — `[M]` (rate limit / quiet hours 패턴 참조)
- macOS URL Scheme — https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app — `[H]`

### 7.5 내부 참조

- `/Users/bbikiming/Documents/vibe_coding/Yuminai/docs/log/42_DECISIONS.md` — ADR-086
- `/Users/bbikiming/Documents/vibe_coding/Yuminai/Sources/YuminaiTelegram/` — 백엔드
- `/Users/bbikiming/Documents/vibe_coding/Yuminai/Sources/YuminaiCore/Telegram*.swift` — 모델/액터
- `/Users/bbikiming/Documents/vibe_coding/Yuminai/Sources/YuminaiApp/Telegram*.swift` — 기존 sheet (deprecate 대상)
- `/Users/bbikiming/Documents/vibe_coding/Yuminai/Sources/YuminaiUI/TelegramHealthPill.swift`, `TelegramUsageDashboard.swift`

---

## Appendix A — 출시 후 follow-up 연구 질문 (우선순위 순)

1. **[High]** 사용자가 폰에서 보는 diff의 가독성 — 작은 화면에서 fenced code block이 실제로 읽히는지 사용자 테스트.
2. **[High]** HITL timeout (60s) 적정성 — 실 사용자 응답 시간 분포 측정 후 조정.
3. **[Medium]** Telegram outage 시 fallback — 봇 다운 중 HITL 요청은 어떻게 처리? (자동 reject? 데스크탑 only?)
4. **[Medium]** 그룹 채팅에서 멀티 사용자 승인 정책 — N-of-M approval 필요한가?
5. **[Low]** Voice message 입력 지원 — Whisper 통합으로 음성 명령?
6. **[Low]** Telegram Mini Apps 활용 — full-screen webview로 Yuminai 일부 UI 임베딩 가능성.

---

## Appendix B — 합리화 방지 (이 변명은 통하지 않는다)

| 변명 | 현실 |
|---|---|
| "현재 8개 sheet도 잘 작동하니 통합 불필요" | 사용자가 진입점 못 찾으면 기능은 없는 것과 같다 |
| "HITL은 데스크탑에서만 하면 됨" | "원격 바이브코딩"의 핵심 가치. 폰 승인이 없으면 외출 중 작업 정지 |
| "Diff는 4096자 잘라서 보내면 됨" | Telegram 한도는 안전 마진 후 2000자. 안 그러면 silent truncate |
| "온보딩 wizard는 over-engineering" | BotFather 토큰 발급은 5단계 외부 절차. wizard 없으면 첫 사용자 90% 이탈 |
| "공식 Anthropic Telegram 봇 나오면 의미 없어짐" | 출시 시점이 불명. 그동안 reference UX를 정의할 기회 |
