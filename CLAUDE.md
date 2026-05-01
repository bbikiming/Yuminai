# CLAUDE.md — Yuminai 프로젝트 컨텍스트

> 이 파일은 Claude Code가 Yuminai 작업 시 자동 로드하는 프로젝트 가이드라인입니다.
> 글로벌 `~/.claude/CLAUDE.md` 및 `claude-forge/rules/*.md`를 상속하며, 그 위에 Yuminai 특화 규칙을 추가합니다.

## 프로젝트 1줄 정의

> **바이브 코딩을 위한 1인 macOS 워크스페이스.** Claude Code CLI를 추론 엔진으로 위임하고, Obsidian/Telegram/외부 도구를 SwiftUI 네이티브 GUI에서 오케스트레이션한다.

## 환경 (작업 시 가정 가능)

| 항목 | 값 |
|------|------|
| macOS | 26.0+ (Tahoe) |
| Xcode | 26.0+ |
| Swift | 6.2+ |
| 타깃 | macOS 26.0 (deployment target) |
| Claude CLI | `~/.local/bin/claude` |
| 디바이스 | Apple Silicon |
| 배포 | unsigned, 본인 1인 사용 |

## 핵심 아키텍처 결정 (DECIDED)

다음은 이미 결정되었으며 변경 시 반드시 사용자 승인 필요:

1. **A1 (Wrapper)**: Claude Code CLI를 자식 프로세스로 spawn하고 stdin/stdout을 GUI로 중계. Anthropic SDK를 직접 호출하지 않음.
2. **SwiftUI 네이티브**: macOS only. Tauri/Electron/React 사용 안 함.
3. **Swift 6.2 Approachable Concurrency**: `@MainActor` 격리, `Sendable` 준수, `async/await` 우선.
4. **SwiftData**: 영속 계층 (CoreData/GRDB 사용 안 함, 단순성 우선).
5. **Keychain**: 모든 비밀(API key, bot token)은 macOS Keychain만 사용.
6. **App Sandbox: OFF**: Process spawn(`claude` CLI)을 위해 비활성화. Hardened Runtime 일부만.

자세한 결정은 [`docs/log/42_DECISIONS.md`](docs/log/42_DECISIONS.md), 미결정 사항은 [`docs/prd/99_OPEN_QUESTIONS.md`](docs/prd/99_OPEN_QUESTIONS.md) 참조.

## 모듈 책임

| 모듈 | 책임 | 절대 하지 말 것 |
|------|------|------|
| `YuminaiCore` | 도메인 모델, 워크스페이스/세션 모델, 비즈니스 로직 | UI 의존, FileManager 직접 호출 |
| `YuminaiClaudeAdapter` | Claude CLI spawn, PTY, stdin/stdout 스트리밍, 종료 감지 | 비즈니스 로직, UI |
| `YuminaiPersistence` | SwiftData 모델/마이그레이션 | UI, 외부 프로세스 |
| `YuminaiUI` | SwiftUI 컴포넌트, 디자인 토큰, Liquid Glass | 비즈니스 로직, IO |
| `YuminaiHarness` | rules/agents/skills/hooks 디스패처, MCP bridge | UI |
| `App/Yuminai.app` | 셸, 라우팅, Scene 구성 | 비즈니스 로직(모듈로 위임) |

## Yuminai 개발 시 작업 규칙

> 글로벌 `golden-principles.md`(불변성/TDD/결론 먼저/HARD-GATE 등)을 모두 따른다. 아래는 추가/특화 규칙.

### 1. Swift 6.2 Concurrency 규칙
- 모든 UI 코드는 `@MainActor` 명시
- `Sendable` 미준수 타입을 actor 경계 넘기지 말 것
- `Task {}` 남발 금지 — actor isolation으로 해결 가능한지 먼저 검토
- 자세한 패턴: `rules/20_CONCURRENCY.md`

### 2. SwiftUI 패턴
- `@Observable` (Swift 6) 사용. `ObservableObject` 신규 추가 금지
- View는 100줄 이내 권장, 200줄 초과 시 분리
- `@State` 보유 책임은 view local state만; 도메인 상태는 `@Observable` 모델로
- 자세한 패턴: `rules/10_SWIFTUI_PATTERNS.md`

### 3. Process Spawning (Claude CLI 호출)
- GUI 앱은 zsh init 파일(`~/.zshrc`)을 읽지 않는다. PATH를 명시적으로 구성하라.
- Process API는 ttybuf/PTY가 아니므로 ANSI 색상이 끊긴다 — `YuminaiClaudeAdapter`에서 PTY 처리
- 자세한 패턴: `rules/40_PROCESS_SPAWNING.md`

### 4. 테스트 (Swift Testing 우선)
- 신규 코드는 Swift Testing(`@Test`) 우선, XCTest는 레거시 호환만
- 80%+ 커버리지 (글로벌 규칙)
- Process spawn은 mock 가능한 protocol 뒤에 두기

### 5. 보안
- 모든 시크릿: Keychain only (UserDefaults / .env 절대 금지)
- 외부 API 통신: URLSession + ATS 준수
- 자세한 패턴: `rules/50_SECURITY.md`

## 흔한 실수 방지

| 실수 | 올바른 방법 |
|------|------|
| `Process()` 직접 호출 후 stdout 못 받음 | `YuminaiClaudeAdapter` 사용 (PTY 처리됨) |
| `@State`로 비즈니스 모델 보유 | `@Observable` 클래스로 분리 |
| `print()` 디버깅 | `os.Logger` 사용 (`Logger(subsystem: "com.yuminai", category: ...)`) |
| Vault 파일을 main thread에서 읽기 | `actor ObsidianVault` 안에서 처리 |
| API key를 Info.plist에 박기 | Keychain `kSecClassGenericPassword` |

## 작업 흐름 권장

1. **신규 기능** → `/plan` 먼저 (3파일 이상 변경 예상)
2. **테스트 먼저** → `/tdd` 또는 `tdd-guide` 에이전트
3. **구현 후** → `/code-review` (`code-reviewer` 에이전트)
4. **커밋 전** → `/security-review` (시크릿/입력검증 확인)

## 자주 참조할 문서

- 비전/요구사항: `docs/prd/`
- 아키텍처: `docs/design/10_ARCHITECTURE.md`
- 모듈 책임: `docs/design/20_MODULES.md`
- Claude CLI 통합 상세: `docs/design/30_CLAUDE_ADAPTER.md`
- 결정 로그: `docs/log/42_DECISIONS.md`
- 미해결: `docs/prd/99_OPEN_QUESTIONS.md`

## 작업하지 말 것 (Out of Scope)

- iOS/iPadOS 빌드
- 멀티유저 협업 기능
- 클라우드 서버 컴포넌트
- App Store 배포 준비
- Anthropic SDK 직접 호출 (A1 wrapper 위반)
