# 20_MODULES — 모듈 책임 / 인터페이스

## YuminaiCore

### 책임
- 도메인 모델 (Workspace, Session, Message — *non-persistent* 표현; persistent는 YuminaiPersistence)
- 비즈니스 로직 (세션 lifecycle, 메시지 검증)
- DI 프로토콜 정의 (`ClaudeAdapter`, `WorkspaceStore`, `KeychainStore` 등)
- 에러 enum (`YuminaiError`)
- 시간/시계 추상화 (`Clock`)

### Public API (스케치)

```swift
public struct Workspace: Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let directoryPath: String
    public let createdAt: Date
}

public struct Session: Sendable, Identifiable {
    public let id: UUID
    public let workspaceId: UUID
    public let startedAt: Date
    public let messages: [Message]
}

public struct Message: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let role: Role
    public let content: String
    public let timestamp: Date
    
    public enum Role: String, Sendable, Codable { case user, assistant, system, tool }
}

public protocol WorkspaceStore: Sendable {
    func list() async throws -> [Workspace]
    func get(_ id: UUID) async throws -> Workspace?
    func create(_ workspace: Workspace) async throws
    func update(_ workspace: Workspace) async throws
    func delete(_ id: UUID) async throws
}

public protocol ClaudeAdapter: Sendable {
    func spawn(in workspace: Workspace) async throws -> ClaudeSession
    func terminate(_ session: ClaudeSession) async
}

public protocol ClaudeSession: Sendable {
    var events: AsyncThrowingStream<ClaudeEvent, Error> { get }
    func send(_ text: String) async throws
}

public enum ClaudeEvent: Sendable, Equatable {
    case text(String)
    case toolCall(name: String, input: String)
    case toolResult(success: Bool, output: String)
    case statusChange(StatusKind)
    case completed(exitCode: Int32)
    
    public enum StatusKind: Sendable, Equatable { case thinking, executing, idle }
}

public enum YuminaiError: Error, LocalizedError, Sendable {
    case claudeNotInstalled(path: String)
    case claudeSpawnFailed(reason: String)
    case workspaceNotFound(id: UUID)
    case workspaceAlreadyExists(name: String)
    case keychainReadFailed(status: OSStatus)
    case keychainWriteFailed(status: OSStatus)
    case ptyOpenFailed(errno: Int32)
    case sessionCorrupted(id: UUID, reason: String)
    case pathTraversalAttempted(relative: String)
}
```

### 의존성
- 없음 (Foundation만)

### 테스트
- 도메인 invariant
- 에러 메시지 한국어 검증

---

## YuminaiClaudeAdapter

### 책임
- `claude` CLI를 자식 프로세스로 spawn
- PTY 처리 (PATH, TTY, ANSI)
- stdin → 사용자 입력 전달
- stdout → ANSI 파싱 → ClaudeEvent 스트림
- 종료 (SIGTERM → SIGKILL)
- 비정상 종료 감지/보고

### Public API

```swift
public final actor LiveClaudeAdapter: ClaudeAdapter {
    public init(claudePath: URL, environment: [String: String])
    public func spawn(in workspace: Workspace) async throws -> ClaudeSession
    public func terminate(_ session: ClaudeSession) async
}

public final actor MockClaudeAdapter: ClaudeAdapter {
    public init(scriptedEvents: [ClaudeEvent])
    public func spawn(in workspace: Workspace) async throws -> ClaudeSession
    public func terminate(_ session: ClaudeSession) async
}
```

### 의존성
- YuminaiCore (protocol)
- Foundation (Process, FileHandle, URL)
- Darwin (forkpty, kill, errno)

### 테스트
- MockClaudeAdapter로 ChatViewModel 단위 테스트
- LiveClaudeAdapter는 통합 테스트 (`@Suite("integration", .disabled())`)

### 상세
[`30_CLAUDE_ADAPTER.md`](30_CLAUDE_ADAPTER.md) 참조.

---

## YuminaiPersistence

### 책임
- SwiftData 모델 (`@Model` 클래스)
- ModelContainer 셋업
- 마이그레이션 plan
- WorkspaceStore 구현
- 백업/복원

### Public API

```swift
public final class YuminaiModelContainer {
    public static let shared: ModelContainer = { ... }()
    public static let backgroundContext: ModelContext = ...
}

public final actor SwiftDataWorkspaceStore: WorkspaceStore {
    public init(container: ModelContainer)
    // ... protocol 구현
}

public struct BackupManager: Sendable {
    public func backup(to url: URL) async throws
    public func restore(from url: URL) async throws
    public func listBackups() async throws -> [URL]
}
```

### 의존성
- YuminaiCore
- SwiftData

### 테스트
- in-memory ModelContainer로 CRUD
- 마이그레이션 시뮬레이션

### 상세
[`40_PERSISTENCE.md`](40_PERSISTENCE.md) 참조.

---

## YuminaiUI

### 책임
- 공용 SwiftUI 컴포넌트 (Button, ChatBubble, CodeBlock, Sidebar, etc.)
- Theme namespace (Color/Typography/Spacing/Radius)
- Liquid Glass 적용 모디파이어
- ANSI → SwiftUI Text/AttributedString 렌더러

### Public API

```swift
public enum Theme {
    public enum Color { /* see 70_UIUX.md */ }
    public enum Typography { /* */ }
    public enum Spacing { /* */ }
    public enum Radius { /* */ }
}

public struct ChatBubble: View {
    public let message: Message
    public init(message: Message)
    public var body: some View { ... }
}

public struct CodeBlock: View {
    public let code: String
    public let language: String?
    public init(code: String, language: String? = nil)
}

public struct ANSIRenderer {
    public static func render(_ ansi: String) -> AttributedString
}
```

### 의존성
- YuminaiCore (Message 타입)
- SwiftUI

### 테스트
- snapshot test (앱 셸 도입 후)
- ANSIRenderer 단위 테스트 (다양한 escape sequence)

---

## YuminaiHarness

### 책임
- rules/agents/skills/hooks 로딩
- 글로벌 + 워크스페이스 settings 머지
- Hook 디스패처
- 워크스페이스 .harness/ 스캐폴딩
- (v0.3) MCP bridge

### Public API

```swift
public struct HarnessLayout: Sendable {
    public let workspaceURL: URL
    public var harnessURL: URL { workspaceURL.appendingPathComponent(".harness") }
    public var rulesURL: URL { harnessURL.appendingPathComponent("rules") }
    public var agentsURL: URL { harnessURL.appendingPathComponent("agents") }
    // ...
}

public struct HarnessScaffolder: Sendable {
    public func scaffold(template: HarnessTemplate, at workspaceURL: URL) async throws
}

public enum HarnessTemplate: String, Sendable, CaseIterable {
    case empty, swift, typescript, python, general
}

public final actor HookDispatcher {
    public init(globalHooks: URL?, workspaceHooks: URL?)
    public func dispatch(_ event: HookEvent) async
}

public enum HookEvent: Sendable {
    case sessionStart(workspaceId: UUID)
    case userPromptSubmit(text: String)
    case preToolUse(tool: String, input: String)
    case postToolUse(tool: String, output: String)
    case stop(reason: StopReason)
    case taskCompleted(success: Bool)
    case obsidianNoteInjected(path: String)
    case telegramAlertSent(category: String)
}
```

### 의존성
- YuminaiCore
- Foundation

### 테스트
- 머지 정책 단위 테스트
- 스캐폴딩 결과 디렉토리 구조 검증

---

## App (Yuminai.app)

### 책임
- SwiftUI Scene/Window 구성
- @main 진입점
- DI 컨테이너 초기화
- 라우팅
- 전역 단축키
- 메뉴

### 의존성
- 모든 Yuminai* 모듈

### 테스트
- UI 테스트 (XCUITest, 후순위)
- 주요 경로 수동 QA

---

## 미래 모듈 (v0.2+)

### YuminaiObsidian
- Vault 파일 IO, FSEvents watcher, frontmatter 파싱
- Daily Note 자동 append
- 노트 검색

### YuminaiTelegram
- Bot API (URLSession)
- Long polling
- 알림 송신
- (v0.3) 양방향 명령 라우팅

### YuminaiGit
- `git` 바이너리 wrapper
- Worktree 관리
- 브랜치/dirty 상태

---

## 모듈 간 통신 규칙

### 허용
- View → @Observable ViewModel (양방향 binding)
- ViewModel → Service (await call)
- Service → Adapter/Store (await call)
- Adapter → Infra (Process/SwiftData/...)

### 금지
- View → Service 직접 (ViewModel 경유)
- Service → View (역방향)
- Module A → Module B의 internal type
- Concrete 타입 직접 의존 (protocol을 통해서만)

### 이벤트 전파
- domain event는 actor → AsyncStream → consumer
- UI 이벤트는 SwiftUI Binding으로
- Hook 이벤트는 HookDispatcher actor로
