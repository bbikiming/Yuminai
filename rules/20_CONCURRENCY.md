# Concurrency (Yuminai)

> Swift 6.2 Approachable Concurrency. `StrictConcurrency` enable 됨.

## Mental Model

Swift 6.2의 핵심: **모든 코드는 어떤 isolation에 속한다**. `@MainActor`, custom actor, `nonisolated`, 또는 `@concurrent`. 명시하지 않으면 컴파일러가 안전한 쪽으로 추론한다(보통 `@MainActor` 또는 호출자 isolation 상속).

## 기본 규칙

### 1. UI 코드 = `@MainActor`

```swift
@MainActor
@Observable
final class ChatViewModel {
    var messages: [Message] = []
    
    func append(_ msg: Message) {
        messages.append(msg)  // MainActor 보장
    }
}
```

SwiftUI View는 자동으로 `@MainActor` (Swift 6+).

### 2. IO/CPU 작업 = actor or `nonisolated`

```swift
// 디스크 IO 격리
actor ObsidianVault {
    private let root: URL
    
    func read(_ note: String) async throws -> String {
        try String(contentsOf: root.appending(component: note), encoding: .utf8)
    }
}

// 순수 함수 = nonisolated
nonisolated func parseANSI(_ data: Data) -> [ANSIToken] { ... }
```

### 3. Sendable 준수

actor 경계를 넘는 모든 값은 `Sendable`.

```swift
// GOOD: struct of value types — 자동 Sendable
struct Message: Sendable {
    let id: UUID
    let role: Role
    let content: String
}

// BAD: class 혼용 (NSAttributedString 등)
final class MessageBundle {
    var attributed: NSAttributedString  // not Sendable
}

// 강제로 Sendable: 마지막 수단, 이유 적기
@unchecked Sendable
final class CachedClient {
    // 이유: 내부 lock으로 보호함. 변경 시 testCachedClientThreadSafety 확인.
    private let lock = NSLock()
}
```

### 4. async/await 우선

```swift
// BAD
func loadAsync(completion: @escaping (Result<[Workspace], Error>) -> Void) { ... }

// GOOD
func load() async throws -> [Workspace] { ... }
```

### 5. `Task {}` 남발 금지

```swift
// BAD: 매번 detached
struct MyView: View {
    var body: some View {
        Button("Load") {
            Task {
                await viewModel.load()
            }
        }
    }
}

// GOOD: 가능하면 .task / .refreshable 활용
struct MyView: View {
    var body: some View {
        Button("Load", action: viewModel.load)  // async action 직접
        .task { await viewModel.refresh() }
    }
}
```

## 구체 패턴

### Async Sequence 스트리밍

```swift
// Claude CLI 출력 스트림
public func spawn(in workspace: Workspace) -> AsyncThrowingStream<ClaudeEvent, Error> {
    AsyncThrowingStream { continuation in
        let task = Task { ... }
        continuation.onTermination = { @Sendable _ in
            task.cancel()
            // SIGTERM → SIGKILL after 0.5s
        }
    }
}

// 사용자 (View)
.task {
    do {
        for try await event in adapter.spawn(in: workspace) {
            messages.append(event.toMessage())
        }
    } catch is CancellationError {
        // 정상 취소
    } catch {
        showError(error)
    }
}
```

### Cancellation

- `Task.cancel()` 호출 후, async 함수 내부에서 `try Task.checkCancellation()` 또는 `await Task.yield()` 시 자동 throw
- 외부 프로세스/IO는 `withTaskCancellationHandler` 로 직접 cleanup
- 절대로 cancel 무시 금지

### Actor Reentrancy 주의

```swift
actor ChatStore {
    private var messages: [Message] = []
    
    func send(_ msg: Message) async throws {
        messages.append(msg)
        let response = try await api.send(msg)  // ← await 동안 다른 호출자가 끼어들 수 있음
        messages.append(response)
    }
}
```

해결: 짧은 critical section + 외부 호출은 actor 밖에서.

## 금지 사항

- `DispatchQueue.main.async { ... }` — `await MainActor.run` or `@MainActor`
- `DispatchQueue.global().async` — `Task.detached` (그것도 정말 필요할 때만)
- `@unchecked Sendable` 무근거 사용
- `Task.detached { }` — 99% 케이스 `Task { }`로 충분
- `ContinuationCheckedContinuation` 잘못 사용 (resume 누락/중복)

## 디버깅 팁

```bash
# 데이터 레이스 검출
swift test -Xswiftc -sanitize=thread

# Xcode 스킴: Scheme → Run → Diagnostics → Thread Sanitizer
```

`os_signpost`로 actor hop 측정 권장.
