# Process Spawning (Yuminai)

> Claude CLI를 자식 프로세스로 spawn하는 핵심 규칙. **`YuminaiClaudeAdapter` 모듈 외에서는 `Process` 직접 사용 금지**.

## 왜 까다로운가

GUI 앱이 셸 명령을 실행하는 건 터미널과 다르다:

1. **PATH 미상속**: GUI 앱은 `~/.zshrc` / `~/.zprofile`을 읽지 않음. `/usr/local/bin`, `~/.local/bin` 등이 PATH에 없을 수 있음.
2. **TTY 미존재**: `Process` + `Pipe`는 PTY가 아니라서 ANSI 색·줄바꿈·라인 버퍼링이 깨진다. `claude`는 TTY를 가정한다.
3. **시그널 처리**: 사용자가 cancel 누르면 SIGTERM → 0.5초 후 SIGKILL 시퀀스 필요.
4. **stdout/stderr 구분**: 로그와 응답 분리.
5. **종료 감지**: `Process.terminationHandler`는 main queue에서 호출되지 않을 수 있음.

## 정답 패턴

### 1. PATH 명시적 구성

```swift
public struct ProcessEnvironment {
    public static func augmented(extending base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = base
        let extras = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            NSString(string: "~/.local/bin").expandingTildeInPath,
            NSString(string: "~/.cargo/bin").expandingTildeInPath
        ]
        let current = env["PATH", default: ""]
        let merged = (extras + current.split(separator: ":").map(String.init))
            .reduce(into: [String]()) { acc, p in if !acc.contains(p) { acc.append(p) } }
        env["PATH"] = merged.joined(separator: ":")
        return env
    }
}
```

### 2. PTY 사용 (`forkpty`)

`Process` + `Pipe`로는 부족. `Darwin.forkpty` 또는 `SwiftTerm` 의존성 활용:

```swift
// 옵션 A: Darwin C API 직접
import Darwin

func openPTY() throws -> (master: Int32, slave: Int32, name: String) {
    var master: Int32 = 0
    var slave: Int32 = 0
    var nameBuf = [CChar](repeating: 0, count: 1024)
    
    let result = openpty(&master, &slave, &nameBuf, nil, nil)
    guard result == 0 else { throw YuminaiError.ptyOpenFailed(errno: errno) }
    
    return (master, slave, String(cString: nameBuf))
}
```

> 옵션 B: SwiftTerm 의존성 추가 (`migueldeicaza/SwiftTerm`) — `LocalProcessTerminalView` 활용. MVP에서 검토 후 결정.

### 3. ANSI 파싱 → 도메인 이벤트

```swift
public enum ClaudeEvent: Sendable, Equatable {
    case text(String)
    case toolCall(name: String, args: String)
    case toolResult(success: Bool, content: String)
    case statusChange(StatusKind)
    case done(exitCode: Int32)
}

actor ANSIStreamParser {
    func parse(_ chunk: Data) -> [ClaudeEvent] {
        // ESC [ ... m → 색상 (보존하되 도메인 이벤트엔 빼기)
        // ESC ] ... BEL → OSC (Claude Code 특수 이벤트?)
        // 평문 → .text
    }
}
```

### 4. Cancel 시퀀스

```swift
public func terminate(_ process: Process) async {
    process.terminate()  // SIGTERM
    try? await Task.sleep(for: .milliseconds(500))
    if process.isRunning {
        kill(process.processIdentifier, SIGKILL)
    }
}
```

`AsyncThrowingStream.continuation.onTermination`에 위 코드 연결.

## App Sandbox 처리

`com.apple.security.app-sandbox = NO` (entitlements). 또는 sandbox ON 시 `com.apple.security.temporary-exception.unix-process-execution` (제한적).

본인 사용 unsigned 가정 → **sandbox OFF가 단순/안전**.

## 검증 (스폰 전)

```swift
public func validateClaudeBinary(at path: URL) throws {
    guard FileManager.default.isExecutableFile(atPath: path.path) else {
        throw YuminaiError.claudeNotInstalled(path: path.path)
    }
    
    // 옵션: --version 호출해서 응답 확인 (단, 그 자체도 spawn이라 chicken-and-egg)
}
```

기본 경로 후보:
1. 사용자 설정 (Keychain or settings)
2. `~/.local/bin/claude`
3. `which claude` 결과 (login shell 호출 필요)

## stdin 주입

사용자 입력을 stdin에 보내는 것:

```swift
let inputHandle: FileHandle = process.standardInput as! FileHandle
try inputHandle.write(contentsOf: text.data(using: .utf8) ?? Data())
```

주의: 줄바꿈 정책 (LF vs CRLF), 입력 모드(line-buffered vs raw)는 PTY 설정에 따름.

## 금지 사항

- `Process`를 `YuminaiClaudeAdapter` 외에서 직접 import
- `Process.launchPath` 사용 (`launch()` deprecated) — `executableURL` + `run()` 사용
- shell 호출 (`/bin/sh -c "..."`) — injection 위험. 직접 binary 호출
- 환경변수 기본값 의존 — 항상 명시
- main thread block (`process.waitUntilExit()` 메인에서) — `async` 패턴

## 참고

- Apple: [`Process` 클래스 문서](https://developer.apple.com/documentation/foundation/process)
- SwiftTerm: <https://github.com/migueldeicaza/SwiftTerm>
- Anthropic Claude Code stdin/stdout 프로토콜: 자체 조사 필요 (운영 시 `claude --help`로 stream 모드 확인)
