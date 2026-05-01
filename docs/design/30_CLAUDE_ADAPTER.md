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

## 알아야 할 것 — Claude CLI 실제 동작 (W1 Spike 결과로 채워짐)

| 질문 | 답 (TBD) |
|---|---|
| `claude --version` 표준 출력 형식? | TBD |
| `claude` 실행 시 어떻게 입력 받나? (REPL? 단발?) | TBD |
| Stream JSON 모드 있는가? (`--json`?) | TBD |
| 멀티턴 세션 ID 노출? (`--session-id`?) | TBD |
| OAuth 토큰 위치? (`~/.claude/auth.json`?) | TBD |
| Settings 디렉토리 환경변수? (`CLAUDE_CONFIG_DIR`?) | TBD |
| Tool 호출 출력 포맷? | TBD |
| `--no-color` 또는 stdin이 TTY 아닐 때 ANSI 자동 제거? | TBD |

→ MVP-0 W1 첫 task로 이 표를 채운다. `claude --help` 출력 분석 + 실제 테스트.
