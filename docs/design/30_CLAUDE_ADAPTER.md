# 30_CLAUDE_ADAPTER — Claude Code CLI 통합 상세

> Yuminai의 핵심 기술 모듈. **여기서 잘못되면 모든 게 무너진다**.

## 핵심 도전

### D1. PATH 미상속
GUI 앱은 `~/.zshrc`를 안 읽음. `claude`가 `~/.local/bin`에 있어도 PATH에 자동 추가 안 됨.

### D2. TTY 부재
`Process` + `Pipe`로는 PTY가 아니라서:
- ANSI 색상이 보존 안 될 수 있음
- 라인 버퍼링이 되어 스트리밍 끊김
- `claude`가 TTY 검사하면 거부

### D3. 멀티턴 세션 유지
두 가지 모델 가능:
- (a) `claude` 한 번 띄워두고 stdin으로 계속 보내기
- (b) 매 턴마다 `claude --resume {session-id} "prompt"` 호출

→ MVP-0 W1에서 검증 필요.

### D4. ANSI 스트리밍 파싱
색상, 커서 이동, 화면 클리어 등의 escape sequence를 도메인 이벤트(`ClaudeEvent`)로 변환.

### D5. 종료 처리
정상/비정상/cancel 모두 안전하게.

---

## 설계: 단계별 접근

### Stage 1 (MVP-0 W1): Spike

**목표**: `claude --version` 호출해서 stdout 잡기. 환경 검증.

```swift
// SpikeOnly.swift
import Foundation

@main
struct Spike {
    static func main() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: NSString(string: "~/.local/bin/claude").expandingTildeInPath)
        process.arguments = ["--version"]
        
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        
        // PATH 보강
        var env = ProcessInfo.processInfo.environment
        let extraPath = "/opt/homebrew/bin:/usr/local/bin:" + NSString(string: "~/.local/bin").expandingTildeInPath
        env["PATH"] = extraPath + ":" + (env["PATH"] ?? "")
        process.environment = env
        
        try process.run()
        process.waitUntilExit()
        
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        
        print("STDOUT: \(String(data: outData, encoding: .utf8) ?? "")")
        print("STDERR: \(String(data: errData, encoding: .utf8) ?? "")")
        print("EXIT: \(process.terminationStatus)")
    }
}
```

**확인 사항**:
- [ ] PATH 보강 없이 실행 시 실패하는지
- [ ] PATH 보강 후 `claude --version` 출력
- [ ] `claude --help` 봐서 stream/json 모드 옵션 확인

### Stage 2 (MVP-0 W2): 단순 stdin/stdout

**목표**: PTY 없이 Pipe로 짧은 prompt 보내고 응답 받기.

```swift
public final actor LiveClaudeAdapter: ClaudeAdapter {
    private let claudePath: URL
    private let environment: [String: String]
    
    public init(claudePath: URL, environment: [String: String]) {
        self.claudePath = claudePath
        self.environment = environment
    }
    
    public func spawn(in workspace: Workspace) async throws -> ClaudeSession {
        let process = Process()
        process.executableURL = claudePath
        process.currentDirectoryURL = URL(fileURLWithPath: workspace.directoryPath)
        process.environment = environment
        // arguments TBD - W1 Spike 후
        
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        
        try process.run()
        
        return PipeBackedClaudeSession(process: process, stdin: stdin, stdout: stdout, stderr: stderr)
    }
    
    public func terminate(_ session: ClaudeSession) async {
        guard let s = session as? PipeBackedClaudeSession else { return }
        s.process.terminate()
        try? await Task.sleep(for: .milliseconds(500))
        if s.process.isRunning {
            kill(s.process.processIdentifier, SIGKILL)
        }
    }
}
```

여기서 막히면 → Stage 3로.

### Stage 3 (필요 시): PTY 직접

```swift
import Darwin

func openPTY() throws -> (master: Int32, slave: Int32, name: String) {
    var master: Int32 = 0
    var slave: Int32 = 0
    var nameBuf = [CChar](repeating: 0, count: 1024)
    
    guard openpty(&master, &slave, &nameBuf, nil, nil) == 0 else {
        throw YuminaiError.ptyOpenFailed(errno: errno)
    }
    return (master, slave, String(cString: nameBuf))
}

// Process에 slave를 stdin/stdout/stderr로 주고
// master 측을 FileHandle로 read/write
```

또는 SwiftTerm 의존성 채택:

```swift
// Package.swift에 추가
.package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0")

// 사용
import SwiftTerm
let process = LocalProcess(delegate: self)
process.startProcess(executable: claudePath.path, args: [], environment: env)
```

---

## ClaudeSession 구체

```swift
public protocol ClaudeSession: Sendable {
    var events: AsyncThrowingStream<ClaudeEvent, Error> { get }
    func send(_ text: String) async throws
}

final class PipeBackedClaudeSession: ClaudeSession, @unchecked Sendable {
    let process: Process
    let stdin: Pipe
    let stdout: Pipe
    let stderr: Pipe
    
    let events: AsyncThrowingStream<ClaudeEvent, Error>
    private let continuation: AsyncThrowingStream<ClaudeEvent, Error>.Continuation
    
    init(process: Process, stdin: Pipe, stdout: Pipe, stderr: Pipe) {
        self.process = process
        self.stdin = stdin
        self.stdout = stdout
        self.stderr = stderr
        
        var cont: AsyncThrowingStream<ClaudeEvent, Error>.Continuation!
        self.events = AsyncThrowingStream { c in cont = c }
        self.continuation = cont
        
        startReading()
        startWatchingProcess()
    }
    
    func send(_ text: String) async throws {
        let data = (text + "\n").data(using: .utf8) ?? Data()
        try stdin.fileHandleForWriting.write(contentsOf: data)
    }
    
    private func startReading() {
        let parser = ANSIStreamParser()
        stdout.fileHandleForReading.readabilityHandler = { [continuation] handle in
            let chunk = handle.availableData
            if chunk.isEmpty { return }
            // ANSI 파싱은 별도 actor에서, 여기선 raw 전달
            Task {
                let events = await parser.feed(chunk)
                for event in events {
                    continuation.yield(event)
                }
            }
        }
    }
    
    private func startWatchingProcess() {
        process.terminationHandler = { [continuation] proc in
            continuation.yield(.completed(exitCode: proc.terminationStatus))
            continuation.finish()
        }
    }
}
```

---

## ANSIStreamParser

```swift
public actor ANSIStreamParser {
    private var buffer: Data = Data()
    
    public func feed(_ chunk: Data) -> [ClaudeEvent] {
        buffer.append(chunk)
        var events: [ClaudeEvent] = []
        
        // ESC [ ... m → SGR 색상 (보존 또는 무시)
        // ESC [ ... J → 화면 클리어 (무시)
        // ESC [ ... H → 커서 이동 (무시 또는 status로 변환)
        // 나머지 평문 → .text
        
        // (구체 구현은 W2 단계)
        return events
    }
}
```

---

## 환경변수 구성

```swift
public enum ProcessEnvironment {
    public static func augmented(
        base: [String: String] = ProcessInfo.processInfo.environment,
        harnessURL: URL? = nil,
        workspaceURL: URL? = nil
    ) -> [String: String] {
        var env = base
        
        // PATH
        let pathExtras = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            NSString(string: "~/.local/bin").expandingTildeInPath,
            NSString(string: "~/.cargo/bin").expandingTildeInPath
        ]
        let currentPath = env["PATH", default: ""].split(separator: ":").map(String.init)
        let merged = (pathExtras + currentPath).reduce(into: [String]()) { acc, p in
            if !acc.contains(p) { acc.append(p) }
        }
        env["PATH"] = merged.joined(separator: ":")
        
        // Claude CLI 하네스 위치 알리기 (env var 이름은 W1 Spike에서 확인)
        if let h = harnessURL {
            env["CLAUDE_CONFIG_DIR"] = h.path  // ← 가설
        }
        
        // TERM (PTY 사용 시)
        env["TERM"] = "xterm-256color"
        
        // HOME 보장
        if env["HOME"] == nil {
            env["HOME"] = NSHomeDirectory()
        }
        
        return env
    }
}
```

---

## Cancel/Terminate 패턴

```swift
// AsyncThrowingStream.continuation.onTermination 활용
init(...) {
    var cont: AsyncThrowingStream<ClaudeEvent, Error>.Continuation!
    self.events = AsyncThrowingStream { c in cont = c }
    self.continuation = cont
    
    cont.onTermination = { [weak self] _ in
        guard let self else { return }
        Task { await self.gracefulShutdown() }
    }
}

private func gracefulShutdown() async {
    process.terminate()  // SIGTERM
    try? await Task.sleep(for: .milliseconds(500))
    if process.isRunning {
        kill(process.processIdentifier, SIGKILL)
    }
}
```

사용자 view에서 cancel:

```swift
struct ChatView: View {
    @State private var streamTask: Task<Void, Never>?
    
    var body: some View {
        Button("Cancel") {
            streamTask?.cancel()  // ← 이게 onTermination 트리거
        }
    }
}
```

---

## 단위 테스트 전략

### MockClaudeAdapter

```swift
public final actor MockClaudeAdapter: ClaudeAdapter {
    private let scriptedEvents: [ClaudeEvent]
    private let delayPerEvent: Duration
    
    public init(scriptedEvents: [ClaudeEvent], delay: Duration = .milliseconds(10)) {
        self.scriptedEvents = scriptedEvents
        self.delayPerEvent = delay
    }
    
    public func spawn(in workspace: Workspace) async throws -> ClaudeSession {
        ScriptedSession(events: scriptedEvents, delay: delayPerEvent)
    }
    
    public func terminate(_ session: ClaudeSession) async { /* no-op */ }
}
```

### 테스트 케이스 (필수)

```swift
@Test func basicEcho() async throws {
    let adapter = MockClaudeAdapter(scriptedEvents: [
        .text("hello"),
        .completed(exitCode: 0)
    ])
    let session = try await adapter.spawn(in: .testFixture)
    var received: [ClaudeEvent] = []
    for try await event in session.events {
        received.append(event)
    }
    #expect(received == [.text("hello"), .completed(exitCode: 0)])
}

@Test func cancelMidStream() async throws { /* ... */ }
@Test func nonZeroExitReportedAsError() async throws { /* ... */ }
@Test func ansiStripping() async throws { /* ... */ }
```

---

## W1 Spike 결과 (2026-05-01, claude 2.1.101)

`claude --help` 분석으로 큰 발견 — **JSON 양방향 스트리밍이 1급 지원**되어 PTY/ANSI 처리 불필요.

| 질문 | 답 |
|---|---|
| `claude --version` 형식 | `2.1.101 (Claude Code)` (한 줄) |
| 실행 모드 | 기본 = interactive REPL (TTY 필요), `-p/--print` = 단발/non-interactive (Pipe 가능) |
| Stream JSON | **YES**. `--output-format stream-json` + `--input-format stream-json` + `--include-partial-messages` |
| 멀티턴 세션 | `--session-id <uuid>`로 명시 지정, `-r/--resume <uuid>`로 재개, `-c/--continue`로 최근 자동 재개 |
| 세션 영속 끄기 | `--no-session-persistence` |
| OAuth/auth | `auth` 서브명령. `--bare` 모드는 `ANTHROPIC_API_KEY` 환경변수만 사용 (OAuth + keychain 차단) |
| Settings 주입 | `--settings <file-or-json>`, `--setting-sources <user,project,local>` |
| MCP 주입 | `--mcp-config <files...>` (JSON 파일/문자열), `--strict-mcp-config`로 다른 MCP 무시 |
| Custom agents 주입 | `--agents <json>` |
| Plugin dir 주입 | `--plugin-dir <path>` (반복 가능) |
| 작업 디렉토리 추가 | `--add-dir <dirs...>` |
| Hook 이벤트 노출 | `--include-hook-events` (stream-json 전용) |
| Tool 출력 포맷 | stream-json 메시지 안에 구조화 (W2에서 실제 메시지로 검증) |
| 권한 우회 | `--dangerously-skip-permissions` (우리는 사용 안 함, GUI에서 사용자 승인) |
| Worktree 자동 생성 | `--worktree [name]` |
| 디버그 로그 | `--debug-file <path>` |

## 설계 영향 (ADR-009 채택)

위 발견에 따라 **MVP-0의 Claude 호출 모드 확정**:

```bash
claude \
  --print \
  --input-format stream-json \
  --output-format stream-json \
  --include-partial-messages \
  --include-hook-events \
  --session-id $WORKSPACE_SESSION_UUID \
  --settings $WORKSPACE_HARNESS/settings.json \
  --mcp-config $WORKSPACE_HARNESS/.mcp.json \
  --plugin-dir $WORKSPACE_HARNESS \
  --add-dir $WORKSPACE_DIRECTORY
```

이 결과:
- **PTY 불필요** — `-p` 모드는 stdin/stdout pipe만으로 동작
- **ANSI 파싱 불필요** — JSON 메시지가 1급 시민
- **세션 영속을 Claude에 위임 가능** — `--session-id` UUID만 SwiftData에 저장, 본문은 Claude가 관리
- **하네스 완벽 주입** — `.harness/settings.json` + `.harness/.mcp.json` + `.harness/agents/`가 그대로 전달됨

## 멀티턴 모델 (확정)

```
1. 워크스페이스 활성화
   ↓
2. UUID 생성 (또는 기존 session.id 재사용)
   ↓
3. 매 사용자 메시지마다 Claude CLI를 단발 호출:
   claude -p --session-id <uuid> --resume ...
   ↓
4. stdin으로 JSON line 보냄: {"type":"user_message","content":"..."}
   ↓
5. stdout에서 JSON line 스트림 수신 → ClaudeEvent로 파싱 → UI
   ↓
6. 종료 후 다음 사용자 입력 대기
   ↓
7. 다음 입력 시 같은 session-id로 재호출 → Claude가 이전 컨텍스트 자동 복원
```

대안: Claude를 살려두고 stdin에 계속 보내는 방식도 가능하지만, *단발 호출 + session-id*가 단순 + 안정.

## ClaudeEvent 정밀화 (W2 일정)

현재 enum:
```swift
public enum ClaudeEvent: Sendable, Equatable {
    case text(String)
    case toolCall(name: String, input: String)
    case toolResult(success: Bool, output: String)
    case statusChange(StatusKind)
    case completed(exitCode: Int32)
}
```

W2에서 실제 `stream-json` 메시지 형식 확인 후 다음과 같이 확장 예정:
- `partialText(String)` — `--include-partial-messages` 청크
- `hookEvent(name: String, payload: String)` — `--include-hook-events`
- `toolPermissionRequest(...)` — 우리가 GUI 다이얼로그로 응답해야 하는 권한 요청
- 파라미터를 `Sendable Codable struct`로 정밀화
