# Decisions Log (ADR-lite)

> 큰 결정만 기록. 형식: 결정 / 컨텍스트 / 대안 / 근거 / 결과 / 재검토 시점.

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
