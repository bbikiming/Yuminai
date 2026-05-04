# ADR-094: Telegram CommandPalette + HITL Coordinator + Inline Callback

**Status:** Accepted  
**Date:** 2026-05-04  
**Author:** Yuminai Engineering  
**Supersedes:** ADR-093 (Phase 2 — BotStatusDock, ChatContextCard, ActivityFeed)

---

## 핵심 결정

Phase 3은 세 가지 독립된 subsystem을 도입한다:

1. **CommandPaletteEditor** — BotFather에 등록할 커맨드 목록을 편집·동기화하는 macOS UI
2. **TelegramHITLCoordinator** — 위험 작업 실행 전 사용자 승인을 async하게 기다리는 actor
3. **Inline button callback 처리** — Telegram `/approve /reject` 버튼 클릭 → HITL 응답 라우팅

---

## 컨텍스트

ADR-092 §4.5 (Inline Command Palette), §4.6 (HITL 승인 흐름), §5.2, §5.4에서 요구된 기능이다.  
Phase 1 (Hub + Wizard, 커밋 1e71088), Phase 2 (BotStatusDock + ChatContextCard, 커밋 18a1077) 위에 구축된다.

---

## 산출물

### 신규 파일 (10개)

| 파일 | 모듈 | 역할 |
|------|------|------|
| `Sources/YuminaiCore/TelegramCommand.swift` | YuminaiCore | 커맨드 데이터 모델 + 7개 기본 시드 |
| `Sources/YuminaiCore/TelegramHITLCoordinator.swift` | YuminaiCore | HITL 요청 관리 actor |
| `Sources/YuminaiTelegram/TelegramHITLCallbackHandler.swift` | YuminaiTelegram | inline button 콜백 파싱/라우팅 |
| `Sources/YuminaiApp/TelegramHub/CommandPaletteEditor.swift` | YuminaiApp | 커맨드 목록 편집 UI |
| `Sources/YuminaiApp/TelegramHub/CommandEditSheet.swift` | YuminaiApp | 커맨드 추가/편집 sheet |
| `Sources/YuminaiApp/HITL/HITLApprovalSheet.swift` | YuminaiApp | 데스크탑 HITL 승인 sheet |
| `Tests/YuminaiCoreTests/TelegramCommandTests.swift` | YuminaiCoreTests | TelegramCommand 유닛 테스트 |
| `Tests/YuminaiCoreTests/TelegramHITLCoordinatorTests.swift` | YuminaiCoreTests | HITLCoordinator actor 테스트 |
| `docs/ADR-094-Telegram-CommandPalette-HITL.md` | — | 이 문서 |

### 수정 파일 (6개)

| 파일 | 변경 내용 |
|------|---------|
| `Sources/YuminaiCore/AppPreferences.swift` | `telegramCommands: [TelegramCommand]` 필드 추가 (backward-compat) |
| `Sources/YuminaiCore/TelegramClient.swift` | `setMyCommands(_:)` protocol 메서드 추가 |
| `Sources/YuminaiTelegram/LiveTelegramBot.swift` | `setMyCommands` 구현 (Telegram API) |
| `Sources/YuminaiTelegram/MockTelegramBot.swift` | `setMyCommands` mock 구현 |
| `Sources/YuminaiApp/TelegramHub/TelegramHubCommandsTab.swift` | placeholder → `CommandPaletteEditor()` |
| `Sources/YuminaiApp/AppModel.swift` | HITL coordinator + command sync 메서드 추가 |
| `Sources/YuminaiApp/RootView.swift` | `.sheet(isPresented: $bindable.showHITLSheet)` 추가 |
| `Sources/YuminaiApp/YuminaiCommandRouter.swift` | HITL callback 처리 분기 추가 |

---

## 데이터 모델

### TelegramCommand

```swift
public struct TelegramCommand: Sendable, Codable, Hashable, Identifiable {
    public let id: UUID
    public var trigger: String        // "/run"
    public var description: String    // max 256자
    public var permission: Permission // .anyUser / .admin / .userIds([Int64])
    public var requiresHITL: Bool
    public var enabled: Bool
}
```

- `apiCommand`: trigger에서 "/" 제거 (Telegram API 요구사항)
- `isValidTrigger`: "/" prefix + 1~32자 검증
- `isValidDescription`: 1~256자 검증
- Permission 3-way: anyUser / admin / userIds([Int64])

### TelegramHITLCoordinator.Request

```swift
public struct Request: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let action: String
    public let workspace: String?
    public let diffPreview: String?
    public let createdAt: Date
    public let timeoutSeconds: Int
}
```

### TelegramHITLCoordinator.HITLResponse

```swift
public enum HITLResponse: Sendable, Equatable {
    case approved(by: String)
    case rejected(by: String)
    case timeout
    case cancelled
}
```

---

## 상태 머신 (TelegramHITLCoordinator)

```
request(action:..., timeout:N)
  → Request 생성 + Continuation 등록 + AsyncStream emit + timeout Task 시작
  → await (suspend)
                         ↓
respond(id:, .approved) → Continuation resume(.approved) + pending 제거
respond(id:, .rejected) → Continuation resume(.rejected) + pending 제거
N초 경과               → timeout Task fires → Continuation resume(.timeout) + pending 제거
cancel(id:)            → Continuation resume(.cancelled) + pending 제거
```

다중 request 동시 지원 — `[UUID: PendingEntry]` dictionary로 id별 lookup.

---

## inline button callback 형식

```
hitl:approve:<uuid>   // 예: hitl:approve:550e8400-e29b-41d4-a716-446655440000
hitl:reject:<uuid>
```

- `TelegramHITLCallbackHandler.HITLAction.callbackData(for:)` 생성
- `InlineButton` 64 bytes 제한 (UUID = 36자, prefix "hitl:approve:" = 13자 → 49자 < 64자 OK)

---

## BotFather setMyCommands

- `POST /bot{token}/setMyCommands` — `{"commands": [{"command": "run", "description": "..."}]}`
- `"/"` prefix는 Telegram API가 거부 → `apiCommand` 프로퍼티로 제거 후 전송
- command 최대 32자, description 최대 256자 (LiveTelegramBot에서 자동 truncate)
- enabled + isValidTrigger + isValidDescription 세 조건 모두 충족한 커맨드만 sync

---

## 검증 결과

```
swift build  → Build complete! (0 errors)
swift test   → 810+ tests passed (791 baseline + ~19 신규)
              YuminaiCoreTests/TelegramCommandTests: 18 tests ✓
              YuminaiCoreTests/TelegramHITLCoordinatorTests: 10 tests ✓
```

---

## 다음 Phase로 미룬 항목

| 항목 | 이유 | ADR |
|------|------|-----|
| `/start` 자동 허용 목록 감지 | 보안 정책 결정 필요 | ADR-095 |
| `yuminai://` deep link (HITL 응답) | macOS URL scheme 등록 미비 | ADR-095 |
| 다중 디바이스 동기화 정책 | iCloud KeyValue store 설계 필요 | ADR-095 |
| quiet hours (알림 억제) | UI 설계 미확정 | ADR-095 |
| HITL macOS UserNotification | UNUserNotificationCenter 권한 요청 필요 | ADR-095 |
| setMyCommands scope 옵션 | BotFather per-chat scope 미구현 | ADR-095 |

---

## 의존성

- **YuminaiCore** ← TelegramCommand, TelegramHITLCoordinator (새 타입, 외부 의존 없음)
- **YuminaiTelegram** ← TelegramHITLCallbackHandler (YuminaiCore 참조)
- **YuminaiApp** ← 모든 UI + AppModel 확장 (YuminaiTelegram 참조)
- Swift 6.2 strict concurrency 준수 (`actor`, `Sendable`, `nonisolated`)
