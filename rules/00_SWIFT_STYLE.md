# Swift Style (Yuminai)

> Swift 6.2 / macOS 26 / Apple Silicon 가정.

## 명명

- 타입(struct/class/enum/actor/protocol): `UpperCamelCase`
- 함수/변수/프로퍼티: `lowerCamelCase`
- enum case: `lowerCamelCase`
- protocol에 `-able`, `-ing`, `-Type` 접미사 남발 금지 (Swift API Design Guidelines)
- 약어는 모두 대문자 또는 모두 소문자: `URL`, `urlString` (O), `Url`, `URLstring` (X)

## 가시성

기본 → 의도된 확장에만 `public` / `package` 부여:
- 모듈 외부에서 사용: `public`
- 같은 SPM 패키지 내 다른 모듈만: `package`
- 같은 모듈 내: 기본(`internal`)
- 같은 파일 내: `fileprivate`
- 같은 타입 내: `private`

## 옵셔널

```swift
// BAD
if let v = optional { ... } else { fatalError() }
let v = optional!

// GOOD
guard let v = optional else { return }
guard let v = optional else { throw YuminaiError.missingValue }
```

`!` (force unwrap)은 다음 경우에만:
- IBOutlet (있다면)
- 정적 리소스 로드 실패 시 의미 있는 crash가 더 안전한 곳

## 에러 처리

```swift
// throws + Result 둘 다 쓰지 말 것 — 한 가지 선택
enum YuminaiError: Error, LocalizedError {
    case claudeNotInstalled(path: String)
    case workspaceCorrupted(id: UUID, reason: String)

    var errorDescription: String? {
        switch self {
        case .claudeNotInstalled(let path):
            "Claude CLI not found at \(path). Run 'which claude' to verify."
        case .workspaceCorrupted(let id, let reason):
            "Workspace \(id) corrupted: \(reason)"
        }
    }
}
```

- 사용자 보여줄 메시지는 `LocalizedError.errorDescription`에 한국어 우선
- 모든 에러는 도메인별 enum (모듈당 하나 권장)
- `Error`만 throw, `NSError` 신규 사용 금지

## 불변성 (글로벌 골든 원칙 그대로)

```swift
// BAD: var 남발
var user = User()
user.name = "yumi"  // mutation

// GOOD: let + struct + with-style 메서드
struct User {
    let name: String
    let email: String
    
    func with(name: String) -> User {
        User(name: name, email: email)
    }
}
```

`class`는 reference 의미가 *진짜 필요*할 때만. 기본은 `struct`.

## 파일 크기

- 1 파일 1 타입 원칙
- 200줄 권장, 400줄 경고, 800줄 분리 강제
- extension은 별도 파일 (`User.swift` + `User+Validation.swift` + `User+Persistence.swift`)

## 함수 크기

- 50줄 이내. 초과 시 헬퍼 분리.
- 매개변수 4개 초과 → struct로 묶기
- 중첩 4단계 초과 금지 (early return으로 평탄화)

## Computed Property vs 메서드

- 매번 재계산해도 cheap + 부수효과 없음 → property
- 비싸거나 비결정적 → method (`func fetch() async throws`)

## DocC 주석

```swift
/// Claude CLI를 자식 프로세스로 spawn하고 stdout 스트림을 AsyncSequence로 노출한다.
///
/// - Parameter workspace: 작업 디렉토리. claude는 여기서 실행된다.
/// - Returns: 사용자 스트림. cancel 시 SIGTERM 후 0.5초 후 SIGKILL.
/// - Throws: ``YuminaiError/claudeNotInstalled(path:)`` PATH에 claude가 없을 때.
public func spawn(in workspace: Workspace) -> AsyncThrowingStream<ClaudeEvent, Error> { ... }
```

- public API는 DocC 필수
- `///` 사용 (`/** */` 금지)
- `internal` 이하는 의도가 비명백할 때만

## 금지 사항

- `print()` (사용자 디버깅 외) — `Logger` 사용
- `NSLog()` — `Logger`
- `try!` — 단, 정적 리소스 로드 실패가 crash가 정답일 때만 예외
- `as!` — `as?` + guard
- `@unchecked Sendable` — 정말로 필요할 때만 + 주석에 이유
- `DispatchQueue.main.async` — `await MainActor.run` 또는 `@MainActor` 격리
