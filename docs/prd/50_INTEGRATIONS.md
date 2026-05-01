# 50_INTEGRATIONS — 외부 통합 명세

## 통합 우선순위

| # | 통합 | 우선순위 | MVP-0 | v0.2 | v0.3+ |
|---|---|---|---|---|---|
| 1 | **Claude Code CLI** | M | ✅ spawn + stream | — | — |
| 2 | **Obsidian Vault** | S | — | ✅ 양방향 | 템플릿 시스템 |
| 3 | **Telegram Bot** | S | — | ✅ 알림(단방향) | ✅ 양방향 명령 |
| 4 | **macOS Keychain** | M | ✅ | — | — |
| 5 | **git** | S | (워크스페이스 디렉토리 경로만) | ✅ worktree 통합 | bisect/blame UI |
| 6 | **macOS Notification** | S | — | ✅ | rich actions |
| 7 | **Anthropic API (직접)** | NG | ❌ A1 wrapper 위반 | ❌ | ❌ |
| 8 | **iCloud Drive** | C | — | — | ✅ 메타 동기화 |
| 9 | **Linear / Notion / Slack** | C | — | — | TBD (사용자 답변 필요) |
| 10 | **GitHub (gh CLI)** | C | — | — | PR 생성, 머지 GUI 트리거 |

> "다양한 외부 앱들"의 구체적 후보는 [`99_OPEN_QUESTIONS.md`](99_OPEN_QUESTIONS.md) Q-D2에 답변 필요.

---

## 1. Claude Code CLI (Must — 기반)

### 인터페이스
- Binary: `~/.local/bin/claude` (사용자 환경 확인됨)
- 호출 방식: 자식 프로세스 (PTY)
- 입력: stdin
- 출력: stdout (ANSI 포함) + stderr
- 종료: SIGTERM → 0.5s → SIGKILL

### 인증
- Claude Code 자체가 OAuth/API key 처리 → Yuminai는 위임
- 사용자가 한 번 `claude` 직접 실행해서 로그인하면 끝

### 데이터 흐름
```
사용자 입력 → Yuminai → stdin → claude CLI → Anthropic API
                                ↓
사용자 화면 ← Yuminai ← stdout(ANSI parser) ← claude CLI
```

### 알아야 할 것 (조사 필요)
- `claude` CLI의 stream 모드 옵션 (`--json`?, `--no-color`?)
- Slash command 라우팅이 어떻게 노출되는지
- 종료 코드 의미
- 멀티 턴 세션 유지 방법 (CLI를 살려두고 stdin으로 계속 보낼 수 있는지, 아니면 매 턴 새로 spawn인지)

→ MVP 1주차에 검증할 것. [`docs/design/30_CLAUDE_ADAPTER.md`](../design/30_CLAUDE_ADAPTER.md) 참조.

---

## 2. Obsidian Vault (Should — v0.2)

### 인터페이스
- **파일 시스템 직접 접근**: Vault는 그냥 디렉토리 (`.md` 파일들)
- **URL 스킴**: `obsidian://open?vault=X&file=Y` — Obsidian 앱 트리거 시 사용
- **Plugin 없음**: Yuminai는 Obsidian 외부에서 동작

### 권한
- macOS는 사용자 디렉토리 접근 시 개별 권한 필요 — sandbox OFF면 무관, sandbox ON이면 Documents/iCloud 권한 명시

### 양방향 동작

**A. Vault → Yuminai (컨텍스트 주입)**
- 사용자가 노트 클릭 / `@note-name` 입력
- 노트 본문 + frontmatter 읽기
- Claude에 전달 시 형식: 
  ```
  ## Context: {note name}
  {note content}
  ---
  ```

**B. Yuminai → Vault (자동 노트화)**
- 작업 완료 트리거 (사용자 지정 또는 슬래시 명령)
- 템플릿 적용 후 Vault에 새 `.md` 생성 또는 Daily Note에 append
- Daily Note 위치: 사용자 설정 (예: `Daily/2026-05-01.md`)

### 파일 watcher
- FSEvents로 Vault 변경 감지 → 사이드바 자동 갱신
- debounce 500ms

### 알아야 할 것 (사용자 답변 필요)
- Vault 위치 (예: `~/Documents/Obsidian/MainVault/`)
- Daily Note 경로 패턴
- 자동 노트화 디폴트 ON/OFF

---

## 3. Telegram Bot (Should — v0.2 알림 / v0.3 양방향)

### 인터페이스
- HTTPS Bot API (`https://api.telegram.org/bot{TOKEN}/...`)
- Webhook 안 씀 (서버 없음) → **long polling** (앱 실행 중일 때만)
- 라이브러리: 직접 `URLSession` 호출 (가벼움) 또는 Swift `TelegramVapor` 종류

### 인증
- Bot Token: BotFather에서 받음 → Keychain 저장
- 허용 사용자 ID: 화이트리스트 (본인 사용자 ID 1개만)

### 동작

**A. Yuminai → Telegram (알림)**
- 트리거: 작업 완료, 에러, 사용자 의사결정 요청
- 메시지: 텍스트 + 옵션 inline keyboard
- Rate limit: 작업당 최대 5건/분

**B. Telegram → Yuminai (양방향 — v0.3)**
- 봇이 사용자 메시지 수신 (long polling)
- 의도 분류: 워크스페이스 명시 (`#nunchi 빌드해줘`) 또는 추론
- 실행 가능한 명령으로 변환 → 해당 워크스페이스에 주입
- 결과는 봇으로 응답

### 알아야 할 것 (사용자 답변 필요)
- Bot token 보유 여부 / 새로 만들 것인지
- 사용자 Telegram user ID
- 어떤 알림을 받고 싶은지 (모든 작업 vs 명시적으로만)

---

## 4. macOS Keychain (Must)

[`rules/50_SECURITY.md`](../../rules/50_SECURITY.md) 참조. 모든 시크릿(`anthropic_api_key`, `telegram_bot_token` 등)이 여기.

---

## 5. git (Should)

### 인터페이스
- `git` 바이너리 호출 (Process)
- 라이브러리 사용 안 함 (libgit2 swift 바인딩 = 무겁고 변경 대응 늦음)

### 통합 범위 (v0.2)
- 워크스페이스 생성 시 `git worktree add` 옵션
- 사이드바에 브랜치명 + dirty 표시 (`git status --porcelain`)
- 워크스페이스 닫기 시 cleanup 안내 (자동 X)

### 비범위
- diff viewer (Claude가 출력하는 diff로 충분 — F-S06)
- commit/push GUI (Claude에게 명령으로 위임)

---

## 6. macOS Notification (Should)

- `UserNotifications` 프레임워크
- 권한 요청은 첫 알림 발송 시
- 표시: 작업 완료, 에러
- Action: "워크스페이스 열기"
- Telegram 알림과 중복 가능 (사용자 토글)

---

## 7. iCloud Drive (Could — v0.3+)

- 워크스페이스 메타데이터(이름, 경로, 마지막 세션 ID)만 동기화
- 메시지/세션 본문은 동기화 안 함 (용량 + 충돌 위험)
- 시크릿은 동기화 안 함

---

## 9. 미정 통합 (사용자 답변 대기)

[`99_OPEN_QUESTIONS.md`](99_OPEN_QUESTIONS.md) Q-D2 — 후보:

| 후보 | 가치 | 노력 | MVP 후보? |
|---|---|---|---|
| GitHub (`gh` CLI) | 중간 | 낮음 | ✅ v0.3 |
| Linear | 낮음 (개인 프로젝트라면) | 중간 | ❌ |
| Notion | 낮음 (Obsidian 사용 중) | 중간 | ❌ |
| Slack | 낮음 (Telegram 사용 중) | 중간 | ❌ |
| Discord | 낮음 | 중간 | ❌ |
| Figma / Pencil | 중간 (디자인 워크플로우) | 높음 | TBD |
| 캘린더 | 중간 | 낮음 | ✅ v0.3 |
| Reminders | 낮음 | 낮음 | ❌ |

**사용자 결정 필요**: 어떤 것을 v0.3 후보에 넣을지.
