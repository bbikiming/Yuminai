# 50_INTEGRATIONS — Obsidian / Telegram 통합 설계

> v0.2+ 모듈. MVP-0 비범위. 기술 스택과 인터페이스 정의만.

## YuminaiObsidian (v0.2)

### 모듈 책임
- Vault 디렉토리 IO
- 노트 트리 인덱스 + watcher (FSEvents)
- Frontmatter 파싱 (YAML)
- 인라인 주입 (`@note-name` → 본문 expand)
- Daily Note 자동 append

### 의존성
- YuminaiCore
- Foundation (FileManager, FSEvents)
- (옵션) Yams (YAML 파서)

### Public API

```swift
public actor ObsidianVault {
    public init(rootURL: URL)
    
    public func index() async throws -> [Note]
    public func read(_ relativePath: String) async throws -> Note
    public func search(query: String) async throws -> [Note]
    public func append(to relativePath: String, content: String) async throws
    public func create(at relativePath: String, content: String) async throws
    
    public var changes: AsyncStream<VaultChange> { get }
}

public struct Note: Sendable, Identifiable {
    public let id: String              // 상대 경로
    public let title: String
    public let body: String
    public let frontmatter: [String: String]
    public let lastModified: Date
}

public enum VaultChange: Sendable {
    case noteAdded(path: String)
    case noteModified(path: String)
    case noteDeleted(path: String)
}

public struct DailyNoteService: Sendable {
    public init(vault: ObsidianVault, pathPattern: String)  // 예: "Daily/{YYYY-MM-DD}.md"
    
    public func appendWorkSummary(_ summary: WorkSummary, on date: Date = Date()) async throws
}

public struct WorkSummary: Sendable {
    public let workspace: String
    public let title: String
    public let durationMinutes: Int
    public let highlights: [String]
    public let nextSteps: [String]
}
```

### 인라인 `@note-name` 처리

```
사용자 입력: "이 PRD 보고 구현해줘 @yuminai-prd-overview"
                                    ↑
                  @ 이후 노트 검색 → 토큰화
                                    ↓
   전송 시 expand: "이 PRD 보고 구현해줘\n\n## Context: yuminai-prd-overview\n{본문}\n---\n"
```

### FSEvents watcher

```swift
import CoreServices

public actor VaultWatcher {
    private var stream: FSEventStreamRef?
    
    public func start(rootURL: URL, callback: @escaping @Sendable ([URL]) -> Void) {
        // FSEventStreamCreate + Schedule + Start
    }
    
    public func stop() {
        // FSEventStreamStop + Invalidate + Release
    }
}
```

debounce 500ms로 burst 흡수.

### 알려진 도전

- macOS 권한: Documents 폴더 접근 첫 시 다이얼로그 (sandbox OFF면 우회)
- iCloud Drive Vault: `.iCloud` placeholder 파일 처리 필요
- Obsidian 동시 편집: 우리가 쓸 때 사용자가 동시 편집 → 충돌. 마지막 write 우선 (간단)

---

## YuminaiTelegram (v0.2 단방향 / v0.3 양방향)

### 모듈 책임
- Bot Token 관리 (Keychain)
- 메시지 송신 (sendMessage, editMessageText)
- (v0.3) Long polling으로 사용자 메시지 수신
- (v0.3) Inline keyboard 생성 / callback_query 처리
- 화이트리스트 user ID 검증

### 의존성
- YuminaiCore
- Foundation (URLSession)

### Public API

```swift
public actor TelegramBot {
    public init(token: String, allowedUserIds: Set<Int64>)
    
    // v0.2 송신
    public func send(
        text: String,
        chatId: Int64,
        keyboard: InlineKeyboard? = nil
    ) async throws -> SentMessage
    
    public func edit(
        messageId: Int64,
        chatId: Int64,
        text: String
    ) async throws
    
    // v0.3 수신
    public var incoming: AsyncStream<IncomingMessage> { get }
    public func startPolling() async throws
    public func stopPolling() async
}

public struct InlineKeyboard: Sendable {
    public let buttons: [[Button]]
    public struct Button: Sendable {
        public let text: String
        public let callbackData: String  // 예: "approve|workspace=nunchi|action=merge"
    }
}

public struct IncomingMessage: Sendable {
    public let userId: Int64
    public let text: String?
    public let voice: VoiceData?
    public let callbackData: String?
    public let replyToMessageId: Int64?
}
```

### Long Polling 패턴

```swift
private func pollLoop() async {
    var offset: Int64 = 0
    while !Task.isCancelled {
        do {
            let updates = try await getUpdates(offset: offset, timeout: 30)
            for update in updates {
                offset = max(offset, update.updateId + 1)
                if isAllowed(update.userId) {
                    incomingContinuation.yield(update.toIncomingMessage)
                } else {
                    log.warning("Rejected unknown user \(update.userId)")
                }
            }
        } catch {
            log.error("Poll error: \(error)")
            try? await Task.sleep(for: .seconds(5))
        }
    }
}
```

### 알림 디스패처

```swift
public actor TelegramAlertDispatcher {
    public init(bot: TelegramBot, chatId: Int64, settings: AlertSettings)
    
    public func dispatch(_ event: AlertEvent) async {
        guard settings.shouldSend(event) else { return }
        let message = format(event)
        let keyboard = keyboard(for: event)
        try? await bot.send(text: message, chatId: chatId, keyboard: keyboard)
    }
}

public enum AlertEvent: Sendable {
    case workCompleted(workspace: String, summary: String)
    case workFailed(workspace: String, error: String)
    case decisionRequired(workspace: String, question: String, options: [String])
}

public struct AlertSettings: Sendable, Codable {
    public var sendOnComplete: Bool = true
    public var sendOnError: Bool = true
    public var sendOnDecision: Bool = true
    public var quietHours: Range<Int>? = nil  // 22..6
}
```

### 양방향 명령 라우팅 (v0.3)

```
사용자 메시지: "#nunchi 빌드해줘"
       ↓
TelegramBot.incoming → 라우터
       ↓
의도 분류: 워크스페이스 = nunchi, 의도 = "build"
       ↓
WorkspaceRouter.execute(workspace: "nunchi", command: "/build")
       ↓
ClaudeAdapter (해당 워크스페이스 active 또는 ad-hoc)
       ↓
결과 → TelegramBot.edit(messageId: ..., text: 진행 상황)
```

의도 분류 옵션:
- (a) 단순 prefix 매칭 (`#workspace command`)
- (b) Claude에 1턴 분류 요청 ("이 메시지에서 워크스페이스와 명령을 추출해")
- (c) 자체 작은 분류기 (Apple Foundation Models on-device — macOS 26 신기능)

권장: MVP=(a), v0.3 후반=(c)

### Rate Limit

- Telegram Bot API: 30 msg/sec 글로벌
- 우리 사용량: 가벼움
- 그래도 actor 안에서 token bucket 구현

---

## 하네스에서 통합 노출

`YuminaiHarness`의 hook으로 통합 트리거:

```json
// ~/Library/.../workspaces/{id}/.harness/settings.json
{
  "hooks": {
    "TaskCompleted": [
      { "type": "yuminai_telegram_alert", "category": "complete" },
      { "type": "yuminai_obsidian_append", "to_daily_note": true }
    ]
  }
}
```

`YuminaiHarness.HookDispatcher`가 `yuminai_*` prefix를 인식하고 해당 모듈 호출.

---

## 보안

- Telegram Bot Token: Keychain
- 허용 user ID 화이트리스트 강제 (다른 user ID는 ignore)
- Vault 경로: path traversal 방어
- 둘 다 외부 입력 길이 제한 (1MB)

---

## 테스트

### Obsidian
- in-memory FileManager 모킹 어려움 → 임시 디렉토리 사용
- `XCTSkip`이 아닌 `@Test func ...` 안에서 setup/teardown

```swift
@Test func vaultIndexesNotes() async throws {
    let temp = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: URL(fileURLWithPath: "/tmp"), create: true)
    defer { try? FileManager.default.removeItem(at: temp) }
    
    try "# Hello".write(to: temp.appendingPathComponent("note.md"), atomically: true, encoding: .utf8)
    
    let vault = ObsidianVault(rootURL: temp)
    let notes = try await vault.index()
    #expect(notes.count == 1)
}
```

### Telegram
- URLSession `URLProtocol` 모킹

```swift
final class MockURLProtocol: URLProtocol {
    static var responses: [URL: (Data, HTTPURLResponse)] = [:]
    
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { /* ... */ }
    override func stopLoading() {}
}
```

---

## 다음 단계

MVP-0 완료 후 v0.2 시작 시:
1. 이 문서 기반으로 `YuminaiObsidian`, `YuminaiTelegram` 모듈 추가
2. `Package.swift`에 라이브러리 등록
3. `YuminaiCore`에 통합 protocol 정의 (의존 역전)
4. App에서 settings 화면에 통합 셋업 추가
