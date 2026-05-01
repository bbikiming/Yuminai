# 00_HARNESS_DESIGN — 하네스 엔지니어링 설계

> claude-forge 패턴을 Yuminai에 매핑하는 메타-아키텍처. *앱 자체가 하네스 엔진*.

## 핵심 명제

Yuminai는 단순히 Claude Code의 GUI 셸이 아니라, **사용자(본인)가 자기 워크플로우에 맞는 rules/agents/skills/hooks를 워크스페이스에 끼워넣을 수 있는 하네스 엔진**이다.

이 설계 패턴 자체가 claude-forge에서 검증되었으므로, 그대로 이식한다.

## 두 레이어

Yuminai의 하네스는 **두 개의 명백히 다른 컨텍스트**에 존재한다:

| 레이어 | 위치 | 누구를 위함 |
|---|---|---|
| **개발 하네스** | `~/Documents/vibe_coding/Yuminai/` (이 리포) | Claude Code가 *Yuminai 자체를 개발*할 때 |
| **사용자 워크스페이스 하네스** | `~/Library/Application Support/Yuminai/workspaces/{id}/.harness/` | Yuminai *런타임*이 사용자 워크스페이스의 Claude CLI에 주입할 때 |

두 레이어는 **같은 형식**(rules/agents/skills/hooks/settings/.mcp)을 사용하므로, 본인이 한 번 패턴을 익히면 양쪽 다 활용 가능.

## claude-forge → Yuminai 매핑

| claude-forge 요소 | 개발 하네스 (Yuminai 리포) | 사용자 워크스페이스 하네스 |
|---|---|---|
| `rules/*.md` | `Yuminai/rules/` (Swift/SwiftUI/concurrency 등) | `.harness/rules/` (사용자 정의) |
| `agents/*.md` | `Yuminai/agents/` (swift6-reviewer 등) | `.harness/agents/` (사용자 정의) |
| `skills/*/SKILL.md` | `Yuminai/skills/` (yuminai-build 등) | `.harness/skills/` |
| `hooks/` + `settings.json` | `Yuminai/settings.json` + `Yuminai/hooks/` | `.harness/settings.json` + hooks |
| `.mcp.json` | `Yuminai/.mcp.json` | `.harness/.mcp.json` |
| `worktrees/` | git worktree 직접 사용 | 워크스페이스 = git worktree (선택) |
| `~/.claude/agent-memory/` | 동일 | 워크스페이스별 `memory/` 디렉토리 |
| `MEMORY.md` (auto-load) | 동일 | 사용자가 작성 |

## 사용자 워크스페이스 하네스 lifecycle

### 생성

```
사용자 → "+ 새 워크스페이스" → 템플릿 선택 (Swift/TS/Py/General/Empty)
                              ↓
              YuminaiHarness.scaffold(template, at: workspace.url)
                              ↓
~/Library/Application Support/Yuminai/workspaces/{id}/
└── .harness/
    ├── rules/        ← 템플릿 기본 + 사용자 추가
    ├── agents/
    ├── skills/
    ├── hooks/
    ├── commands/
    ├── settings.json
    └── .mcp.json
```

### Claude CLI 주입

Claude CLI를 spawn할 때, **작업 디렉토리 + 환경변수**로 하네스 위치를 알린다:

```swift
let process = Process()
process.executableURL = URL(fileURLWithPath: settings.claudePath)
process.currentDirectoryURL = URL(fileURLWithPath: workspace.directoryPath)  
                                  // ← 사용자 git 워크트리 디렉토리
process.environment = ProcessEnvironment.augmented([
    "CLAUDE_CONFIG_DIR": workspace.harnessURL.path,  // ← 우리 하네스 위치 알림
    // ...
])
```

> **검증 필요**: Claude CLI가 어떤 환경변수/플래그로 settings/agents 위치를 받는지. MVP-0 W1 Spike.

### 사용자 편집

워크스페이스 하네스 GUI 편집기 (v0.3+):
- rules/agents/skills 추가/편집
- 글로벌 + 워크스페이스 머지 결과 미리보기
- export/import (다른 워크스페이스에 복제)

> MVP-0에선 텍스트 에디터로 직접 편집. GUI는 후순위.

## 글로벌 vs 워크스페이스 머지 정책

| 우선순위 | 위치 |
|---|---|
| 1 (최저) | claude-forge 글로벌 (`~/.claude/CLAUDE.md`, `claude-forge/rules/*.md`) |
| 2 | Yuminai 글로벌 settings (앱 설정) |
| 3 | 워크스페이스 `.harness/settings.json` |
| 4 (최고) | 세션 임시 override (사용자 슬래시 명령 등) |

머지 알고리즘:
- **`rules/`**: 합집합 (모든 rule 적용)
- **`agents/`**: 이름 충돌 시 우선순위 높은 것 (워크스페이스 > 글로벌)
- **`skills/`**: 합집합
- **`settings.json`**: 깊은 머지 (object 병합, array 합집합, primitive override)
- **`.mcp.json`**: 합집합 (이름 충돌 시 워크스페이스 우선)

## 메모리 전략

```
~/Library/Application Support/Yuminai/workspaces/{id}/
└── memory/
    ├── MEMORY.md                    ← 워크스페이스 자동 로드 (사용자 또는 자동 채움)
    ├── agent-memory/
    │   └── {agent-name}/
    │       └── MEMORY.md            ← 에이전트별 self-evolution 메모리
    └── session-summaries/
        └── {session-id}.md          ← 세션 종료 시 자동 요약 (Claude에 위임)
```

`YuminaiHarness`가 Claude CLI에 메모리 위치를 환경변수로 전달.

## Hook 디스패처

```swift
public actor HookDispatcher {
    public func dispatch(_ event: HookEvent) async throws {
        let hooks = try await loadApplicableHooks(for: event)
        // 워크스페이스 hook → Yuminai 글로벌 hook 순차 실행
        for hook in hooks {
            try await execute(hook, with: event)
        }
    }
}

public enum HookEvent: Sendable {
    case sessionStart(workspaceId: UUID)
    case userPromptSubmit(text: String)
    case preToolUse(tool: String, input: String)
    case postToolUse(tool: String, output: String)
    case stop(reason: StopReason)
    case taskCompleted(success: Bool)
    
    // Yuminai 특화 추가
    case obsidianNoteInjected(path: String)
    case telegramAlertSent(category: String)
}
```

claude-forge 호환 + Yuminai 추가 이벤트.

## MCP Bridge

A1 wrapper이므로, 사용자 워크스페이스의 `.harness/.mcp.json`은 Claude CLI가 처리한다 (우리는 파일만 마련).

다만 Yuminai 자체가 *MCP 서버*를 자체 노출할 수도:

```
Yuminai MCP Server (자체 제공)
├── tool: yuminai_obsidian_search
├── tool: yuminai_obsidian_read
├── tool: yuminai_telegram_send
└── tool: yuminai_workspace_status
```

이러면 사용자 워크스페이스의 `.mcp.json`에 자동 등록되어, Claude가 Yuminai의 통합 기능을 도구로 사용 가능.

> MVP-0 비범위. v0.3 검토.

## 보안 경계

- 워크스페이스 hook 스크립트는 **사용자 작성** = 신뢰
- 하지만 외부에서 import한 hook은 권한 다이얼로그
- Hook 실행은 timeout 강제 (3-5초)
- Hook 실패가 작업 차단하지 않게 (exit 0 권장)

## 비교: claude-forge 자체와 무엇이 다른가

| | claude-forge | Yuminai |
|---|---|---|
| 형태 | CLI/터미널 + 파일 시스템 | macOS GUI 앱 |
| 사용자 | 모든 Claude Code 사용자 | 본인 1인 |
| 하네스 정의 위치 | 리포 / `~/.claude/` | 리포 + 사용자 워크스페이스 |
| 하네스 편집 | 텍스트 에디터 | (v0.3) GUI + 텍스트 에디터 |
| Claude 호출 | 사용자가 `claude` 직접 | Yuminai가 자식 프로세스로 |
| 통합 | MCP 서버 등록 | MCP + 자체 GUI 통합 (Obsidian/Telegram) |

## 다음 문서

- [`10_ARCHITECTURE.md`](10_ARCHITECTURE.md) — 시스템 전체 아키텍처
- [`20_MODULES.md`](20_MODULES.md) — 모듈별 책임 / 의존성
- [`30_CLAUDE_ADAPTER.md`](30_CLAUDE_ADAPTER.md) — Claude CLI 통합 상세
