# ADR-099 — P1 Telegram Wire-up Completion

- **날짜**: 2026-05-04
- **상태**: Accepted
- **선행 ADR**: ADR-098 P0 (command router + HITL request + deliveryChannelProvider + macOS UN)
- **배경**: ADR-098 Gap 분석 §7 P1 4건 — formatter/store/sender 모두 구현됐으나 production 호출 0건

---

## 1. 배경

ADR-098 분석에서 P1으로 분류된 4개 항목은 모두 "백엔드 Actor/Type은 완성, 호출하는 production 코드가 0건"인 패턴이었다:

| # | 항목 | ADR-098 분석 증거 |
|---|---|---|
| P1-1 | `TelegramArtifactStore.store()` 호출 0건 | `grep "\.store(" Sources/` → 0 matches |
| P1-2 | `TelegramMessageFormatter.formatDiff/formatLog` 호출 0건 | `grep "TelegramMessageFormatter\." Sources/` → `enforceMaxBytes` 1건만 |
| P1-3 | `TelegramLargePayloadSender.sendOrAttach` 호출 0건 | Tests 내부만 |
| P1-4 | `editMessageText` HITL 응답 후 호출 0건 | `grep "editMessageText" Sources/` → 0 matches |

---

## 2. 결정

### 2.1 TelegramSendHelper 신규 생성

`Sources/YuminaiTelegram/TelegramSendHelper.swift` — P1-1/P1-2/P1-3를 단일 진입점으로 통합:

```swift
public enum TelegramSendHelper {
    // P1-1 + P1-2 + P1-3
    public static func sendDiffPreview(diff:files:added:removed:workspace:to:store:client:) async throws -> UUID
    public static func sendBuildLog(log:title:elapsed:success:to:store:client:) async throws -> UUID
    // P1-4
    public static func editHITLMessage(response:originalAction:messageId:chatId:client:) async
    // internal
    static func formatHITLResponseEdit(response:originalAction:) -> String
}
```

**라우팅 결정 (P1-3)**:
- raw content < 5MB → `TelegramMessageFormatter` 포맷 → `TelegramLargePayloadSender.sendOrAttach`
- raw content ≥ 5MB → 직접 `client.sendDocument` (전체 내용 첨부 + caption preview)

### 2.2 AppModel 진입점 추가 (P1-1/P1-2/P1-3)

`Sources/YuminaiApp/AppModel.swift`:
- `sendDiffPreviewToTelegram(diff:files:added:removed:workspace:chatId:)` — `telegramBot` (private)에 접근해 `TelegramSendHelper.sendDiffPreview` 호출
- `sendBuildLogToTelegram(log:title:elapsed:success:chatId:)` — 동등

### 2.3 YuminaiCommandRouter.diffCommand 교체 (P1-2)

`Sources/YuminaiApp/YuminaiCommandRouter.swift:diffCommand()`:
- 기존: raw fenced code block + 3500자 truncate, deep link 없음
- 변경: `appModel.sendDiffPreviewToTelegram(...)` 호출 → `nil` 반환 (중복 send 방지)

### 2.4 TelegramHITLCoordinator.Request 확장 (P1-4)

`Sources/YuminaiCore/TelegramHITLCoordinator.swift`:
```swift
public struct Request: Sendable, Equatable, Identifiable {
    // 기존 필드들...
    public var telegramMessageId: Int64?  // 신규
    public var telegramChatId: Int64?     // 신규
    public init(..., telegramMessageId: Int64? = nil, telegramChatId: Int64? = nil)
}
// 신규 메서드
public func setTelegramMessageId(_ messageId: Int64, chatId: Int64, for requestId: UUID)
```

`setupTelegramHITLCoordinator`에서 `sendWithKeyboard` 완료 후 `coordinator.setTelegramMessageId(sent.messageId, ...)` 호출.

`respondToHITL`에서 respond 후 `TelegramSendHelper.editHITLMessage(...)` 호출 — ✅/❌/⏱/🚫 상태 edit.

---

## 3. 변경 파일 매트릭스

| 파일 | 변경 유형 | 핵심 내용 |
|---|---|---|
| `Sources/YuminaiTelegram/TelegramSendHelper.swift` | **신규** | P1-1/P1-2/P1-3/P1-4 통합 헬퍼 (~160줄) |
| `Sources/YuminaiApp/AppModel.swift` | 수정 | `sendDiffPreviewToTelegram`, `sendBuildLogToTelegram` 추가; HITL setup + respond 업데이트 |
| `Sources/YuminaiApp/YuminaiCommandRouter.swift` | 수정 | `diffCommand` 교체 (formatter + store + deep link) |
| `Sources/YuminaiCore/TelegramHITLCoordinator.swift` | 수정 | `Request` 2 필드 추가, `setTelegramMessageId` 메서드, public init |
| `Tests/YuminaiTelegramTests/TelegramSendHelperTests.swift` | **신규** | 13개 통합 테스트 |
| `Tests/YuminaiCoreTests/TelegramHITLCoordinatorP1Tests.swift` | **신규** | 6개 P1-4 테스트 |

---

## 4. Wire-up 매트릭스 (P1-1 ~ P1-4)

검증 명령: `grep -rn "telegramArtifactStore.store|formatDiff|formatLog|sendOrAttach|client.edit|TelegramSendHelper." Sources/ | grep -v "//"` 결과:

| 항목 | production call site | 위치 |
|---|---|---|
| P1-1 `store()` | 2건 | `TelegramSendHelper.swift:40,102` |
| P1-2 `formatDiff` | 1건 | `TelegramSendHelper.swift:59` |
| P1-2 `formatLog` | 1건 | `TelegramSendHelper.swift:122` |
| P1-3 `sendOrAttach` | 2건 | `TelegramSendHelper.swift:66,129` |
| P1-4 `client.edit` | 1건 | `TelegramSendHelper.swift:162` (editHITLMessage) |
| AppModel wire-up | 2건 | `AppModel.swift:4479,4511` |
| Router wire-up | 1건 | `YuminaiCommandRouter.swift:440` |
| HITL edit wire-up | 1건 | `AppModel.swift:5449` |

---

## 5. 사용자 시나리오 매트릭스 업데이트

| Task | 이전 (ADR-098) | 이후 (ADR-099 P1) |
|---|---|---|
| T1 `/run` | ✅ (ADR-098 P0-2) | ✅ |
| **T2 `/diff`** | 🟡 formatter 미사용, deep link 없음 | **✅ formatter + store + deep link** |
| T3 HITL | ✅ (ADR-098 P0-1) | ✅ + edit-after-response |
| T4 `/abort` | ✅ (ADR-098 P0-2) | ✅ |
| T5 `/status` | ✅ | ✅ |

---

## 6. 검증

```bash
swift build    # → Build complete! (0 errors, warnings 기존과 동일)
swift test     # → 952 tests passed in 178 suites (baseline 933 + 19 신규)
```

**신규 테스트 19개**:
- `TelegramSendHelperTests` (13개): sendDiffPreview store, formatter, LargePayloadSender 라우팅, sendBuildLog, HITL edit 포맷, editHITLMessage client call
- `TelegramHITLCoordinatorP1Tests` (6개): Request 신규 필드, setTelegramMessageId, Equatable

---

## 7. 후속 P2/P3 항목

| # | 항목 | 우선도 |
|---|---|---|
| P2-1 | `/run` 결과 완료 시 `sendBuildLogToTelegram` 자동 호출 | P2 |
| P2-2 | HITL request 시 diff_preview가 있으면 store + deep link 첨부 | P2 |
| P2-3 | 봇 polling 라이프사이클 (sleep/wake 자동 stop/restart) | P2 |
| P2-4 | setMyCommands 자동 sync | P2 |
| P3-1 | 다중 디바이스 "seen on desktop" edit | P3 |
| P3-2 | 그룹 채팅 N-of-M approval | P3 |
