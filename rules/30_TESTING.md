# Testing (Yuminai)

> Swift Testing(우선) + XCTest(레거시). 80%+ 커버리지.

## Swift Testing 기본

```swift
import Testing
@testable import YuminaiCore

@Suite("Workspace lifecycle")
struct WorkspaceLifecycleTests {
    @Test("새 워크스페이스는 빈 메시지 리스트로 시작한다")
    func newWorkspaceHasEmptyMessages() async throws {
        let ws = Workspace(name: "test")
        #expect(ws.messages.isEmpty)
    }
    
    @Test("이름이 비면 생성 거부", arguments: ["", "  ", "\t"])
    func rejectsBlankName(_ name: String) {
        #expect(throws: YuminaiError.self) {
            try Workspace.create(name: name)
        }
    }
}
```

## TDD 사이클 (글로벌 규칙)

1. **RED**: 실패하는 `@Test` 작성
2. **GREEN**: 최소 구현으로 통과
3. **REFACTOR**: 통과 유지하면서 정리

## 무엇을 테스트하는가

| 모듈 | 우선 테스트 |
|------|------|
| YuminaiCore | 도메인 invariant, 상태 전이, 에러 케이스 |
| YuminaiClaudeAdapter | mock PTY로 stdin/stdout 라우팅, 종료 처리 |
| YuminaiPersistence | SwiftData 마이그레이션, 쿼리 정확성 |
| YuminaiUI | snapshot test (Liquid Glass 외관 회귀) |
| YuminaiHarness | rules/agents/skills 로딩, hook 디스패치 |

## 무엇을 테스트하지 않는가

- SwiftUI 자체의 렌더링 (`Text("Hi")`가 보이는지) — Apple이 책임
- Claude CLI 자체의 동작 — Anthropic이 책임 (단, *우리가 호출했을 때 받는 형식*은 테스트)
- 시스템 API의 정확성 (Keychain이 진짜 저장하는지)

## Mock 전략

### Protocol-based DI

```swift
// 프로덕션 인터페이스
public protocol ClaudeAdapter: Sendable {
    func spawn(in workspace: Workspace) -> AsyncThrowingStream<ClaudeEvent, Error>
}

// Live 구현 (Process 사용)
public struct LiveClaudeAdapter: ClaudeAdapter { ... }

// Mock
public struct MockClaudeAdapter: ClaudeAdapter {
    let events: [ClaudeEvent]
    public func spawn(in workspace: Workspace) -> AsyncThrowingStream<ClaudeEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }
}
```

테스트는 `MockClaudeAdapter`만 의존.

## 외부 프로세스 테스트

`Process` 직접 호출 테스트는 **금지** (느리고 환경 의존). 대신:
- `ClaudeAdapter` 프로토콜로 추상화
- 통합 테스트(integration)는 별도 `@Suite("integration", .disabled())` + 수동 활성화

## 비동기 테스트

```swift
@Test func streamCompletes() async throws {
    let adapter = MockClaudeAdapter(events: [.text("hi"), .done])
    var collected: [ClaudeEvent] = []
    
    for try await event in adapter.spawn(in: .testFixture) {
        collected.append(event)
    }
    
    #expect(collected.count == 2)
    #expect(collected.last == .done)
}
```

## 시간 의존 테스트

`ContinuousClock` 또는 `Clock` 추상화 주입:

```swift
public protocol Clock: Sendable {
    func now() -> Date
}

public struct SystemClock: Clock {
    public func now() -> Date { Date() }
}

public final class FrozenClock: Clock {
    private var current: Date
    public init(_ initial: Date) { current = initial }
    public func now() -> Date { current }
    public func advance(by: TimeInterval) { current.addTimeInterval(by) }
}
```

## 커버리지

```bash
swift test --enable-code-coverage
xcrun llvm-cov report \
  .build/debug/YuminaiPackageTests.xctest/Contents/MacOS/YuminaiPackageTests \
  -instr-profile=.build/debug/codecov/default.profdata
```

목표: 모듈별 80%+. 단, UI snapshot은 별도 카운트.

## 금지 사항

- `Thread.sleep`, `usleep` (테스트에서) — Clock 추상화
- `XCTSkipIf` 남발 — 환경 의존을 추상화로 해결
- 실 네트워크 호출 (`URLSession` 직접) — `URLProtocol` mock 또는 protocol 추상화
- `XCTAssertEqual(a, b, "message")` 의 message에 의존 — `#expect`의 자동 메시지로 충분
