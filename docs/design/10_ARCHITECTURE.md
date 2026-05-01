# 10_ARCHITECTURE — 시스템 아키텍처

## C4 - Context

```
┌────────────────────────────────────────────────────────────────────┐
│                         사용자 (본인)                                │
│  - 데스크탑 (Yuminai GUI)                                            │
│  - 모바일 (Telegram 봇)                                              │
└──────────────┬─────────────────────────────────┬───────────────────┘
               │                                 │
               ▼                                 ▼
        ┌──────────────────┐              ┌─────────────────┐
        │  Yuminai.app     │              │  Telegram Bot   │
        │  (SwiftUI)       │◀────────────▶│  (long polling) │
        └────────┬─────────┘              └────────┬────────┘
                 │                                 │
   ┌─────────────┼──────────────┬──────────────┐  │
   ▼             ▼              ▼              ▼  ▼
┌────────┐  ┌──────────┐  ┌──────────┐  ┌─────────────┐
│Claude  │  │Obsidian  │  │macOS     │  │Anthropic    │
│Code CLI│  │Vault     │  │Keychain  │  │API          │
│(child) │  │(filesys) │  │          │  │(via Claude) │
└────────┘  └──────────┘  └──────────┘  └─────────────┘
```

## C4 - Container

```
┌──────────────────────────── Yuminai.app ───────────────────────────┐
│                                                                    │
│  ┌──────────────────── Yuminai (App 타깃) ────────────────────┐    │
│  │  - SwiftUI Scene 구성                                       │    │
│  │  - 라우팅, 윈도우 관리                                       │    │
│  │  - DI 컨테이너                                              │    │
│  └────┬───────────────────────────────────────────────────────┘    │
│       │                                                            │
│       ▼ uses                                                       │
│  ┌────────────┐  ┌──────────────────┐  ┌──────────────────┐       │
│  │YuminaiUI   │  │YuminaiCore       │  │YuminaiPersistence│       │
│  │(SwiftUI    │  │(Domain models,   │  │(SwiftData,       │       │
│  │ widgets,   │  │ business logic,  │  │ migrations,      │       │
│  │ tokens)    │  │ DI protocols)    │  │ queries)         │       │
│  └────────────┘  └────┬─────────────┘  └────────┬─────────┘       │
│                       │                         │                  │
│                       ▼                         │                  │
│        ┌──────────────────────┐                │                   │
│        │YuminaiClaudeAdapter  │                │                   │
│        │(Process spawn, PTY,  │                │                   │
│        │ ANSI parser, stream) │                │                   │
│        └──────────┬───────────┘                │                   │
│                   │                            │                   │
│                   ▼ spawns                     │                   │
│              ┌──────────┐                      │                   │
│              │claude CLI│                      │                   │
│              │(child)   │                      │                   │
│              └──────────┘                      │                   │
│                                                │                   │
│        ┌──────────────────────┐                │                   │
│        │YuminaiHarness        │                │                   │
│        │(rules/agents/skills/ │◀───────────────┘                   │
│        │ hooks dispatcher,    │                                    │
│        │ MCP bridge)          │                                    │
│        └──────────────────────┘                                    │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

## 의존성 그래프

```
YuminaiApp
    ├── YuminaiUI ──────────► YuminaiCore
    ├── YuminaiPersistence ─► YuminaiCore
    ├── YuminaiClaudeAdapter ► YuminaiCore
    ├── YuminaiHarness ─────► YuminaiCore
    └── (Future) YuminaiObsidian, YuminaiTelegram ► YuminaiCore
```

규칙:
- **YuminaiCore**는 다른 Yuminai 모듈에 의존하지 *않는다* (도메인 코어)
- 모든 모듈은 YuminaiCore의 protocol에만 의존 (DI)
- App 타깃은 모든 모듈을 묶음

## Layered View

```
Layer 5: Presentation        SwiftUI Views (App + YuminaiUI)
                             ↓ @Environment, @Bindable
Layer 4: View Model          @Observable models
                             ↓
Layer 3: Use Case / Service  YuminaiCore (workspace lifecycle, session ops)
                             ↓ protocol
Layer 2: Adapter             YuminaiClaudeAdapter, YuminaiPersistence,
                             YuminaiHarness, (future) YuminaiObsidian/Telegram
                             ↓
Layer 1: Infrastructure      Process, SwiftData, Keychain, URLSession,
                             FileManager, FSEvents
```

상위 레이어는 하위 레이어에 의존, 역방향 금지.

## Concurrency 토폴로지

```
┌─────────────── @MainActor ─────────────────┐
│  - SwiftUI Views                            │
│  - View Models (@Observable)                │
│  - AppModel (DI 컨테이너)                    │
└──────────────────────┬──────────────────────┘
                       │ async/await
       ┌───────────────┼─────────────────┐
       ▼               ▼                 ▼
  ┌─────────┐    ┌──────────┐      ┌──────────┐
  │actor    │    │actor     │      │actor     │
  │Workspace│    │Claude    │      │Obsidian  │
  │Store    │    │Adapter   │      │Vault     │
  └─────────┘    └──────────┘      └──────────┘
       │               │                 │
       ▼               ▼                 ▼
  SwiftData      Process+PTY        FileManager
  (background)   (background)       (background)
```

- View → ViewModel: `@MainActor` 동일
- ViewModel → Service: `await` 호출
- Service 간 통신: actor 격리 + Sendable 메시지

## 데이터 흐름 — 채팅 한 사이클

```
사용자 입력 ("hello")
     │ (View → ViewModel)
     ▼
@Observable ChatViewModel.send(text:)
     │ (await)
     ▼
actor SessionService.append(message:)
     │ (a: SwiftData 저장)
     │ (b: Claude Adapter에 전달)
     ▼
actor ClaudeAdapter.send(text:)
     │ (process.stdin.write)
     ▼
[Claude CLI 처리]
     │ (process.stdout.readToEnd → stream)
     ▼
AsyncThrowingStream<ClaudeEvent>
     │ (consumer: ChatViewModel.task)
     ▼
ChatViewModel.append(event:)
     │ (a: SwiftData 저장)
     │ (b: View 자동 업데이트)
     ▼
SwiftUI 화면 갱신
```

## 에러 전파

```
Infra layer error
     │ (throw)
     ▼
Adapter wraps in domain error (YuminaiError)
     │ (throw or return Result)
     ▼
Service propagates (with context)
     │
     ▼
ViewModel catches, sets @Observable error state
     │
     ▼
View displays via .alert / inline banner
```

원칙:
- **Infra 에러는 절대 그대로 노출하지 않는다** (NSError, OSStatus 등)
- 각 모듈은 자기 도메인 에러 enum 보유
- View까지 올라온 에러만 한국어 메시지

## 핵심 시퀀스: 워크스페이스 활성화

```
사용자 클릭 "ws-nunchi"
   │
   ▼
@MainActor AppModel.activate(workspace:)
   │
   ├─► (기존 활성 ws 있으면) deactivate(): claude SIGTERM, save state
   │
   ├─► WorkspaceStore.load(id:) → SwiftData
   │
   ├─► HarnessLoader.scaffoldIfNeeded(workspace.url) → .harness/ 보장
   │
   ├─► ClaudeAdapter.spawn(in: workspace, harness: harnessUrl)
   │       │
   │       ├─► PATH 구성, env 셋업
   │       ├─► Process + PTY 생성
   │       └─► AsyncThrowingStream<ClaudeEvent> 반환
   │
   └─► ChatViewModel(stream: stream, workspace: workspace) 셋업
         │
         └─► .task { for try await event in stream { handle(event) } }
```

## 비기능 매핑

| 비기능 | 책임 모듈 | 구현 |
|---|---|---|
| 시작 속도 | App | Splash 빠르게, 워크스페이스 로딩 lazy |
| 스트리밍 fps | YuminaiClaudeAdapter + UI | AsyncSequence + Throttle |
| 메모리 | All | actor 격리로 누수 방지 + Profile 측정 |
| 시크릿 | YuminaiCore (Keychain abstraction) | Security framework |
| 로깅 | All | os.Logger (subsystem `com.yuminai`) |
| 테스트성 | All | protocol DI |

## 다음 문서

- [`20_MODULES.md`](20_MODULES.md) — 모듈별 상세 책임
- [`30_CLAUDE_ADAPTER.md`](30_CLAUDE_ADAPTER.md) — Claude CLI 통합 깊이
- [`40_PERSISTENCE.md`](40_PERSISTENCE.md) — SwiftData 설계
- [`50_INTEGRATIONS.md`](50_INTEGRATIONS.md) — Obsidian/Telegram 통합
