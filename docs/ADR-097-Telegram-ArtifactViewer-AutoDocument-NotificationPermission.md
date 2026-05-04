# ADR-097 — Telegram Artifact Viewer + Auto sendDocument + macOS Notification Permission

**날짜**: 2026-05-04  
**상태**: Accepted  
**선행 ADR**: ADR-096 (Telegram Phase 4 Finalization)

---

## 배경

ADR-096에서 Telegram 통합 Phase 4를 완료했으나 3개 항목이 후속 작업으로 미뤄졌다:

1. `yuminai://diff/{uuid}` / `yuminai://log/{uuid}` 딥링크 클릭 시 실제 viewer가 없어 console log만 출력
2. `TelegramAlertDispatcher`가 5MB+ 메시지를 자동으로 `sendDocument`로 전환하지 않고 truncate만 함
3. macOS `UNUserNotificationCenter` 권한 요청 UI가 없어 사용자가 알림을 받지 못하는 경우 발생

이 ADR은 3개 항목을 구현하여 ADR-092부터 시작된 Telegram 통합을 완전히 종결한다.

---

## 산출물 A — Telegram Diff/Log Viewer Sheet

### 데이터 모델: TelegramArtifactStore

`Sources/YuminaiCore/TelegramArtifactStore.swift`

- Swift `actor` 기반 thread-safe 컨테이너
- `Artifact` enum: `.diff(content:files:added:removed:workspace:)` / `.log(content:title:elapsed:success:)`
- 메모리 기반 ring buffer (기본 capacity: 50, TTL: 1시간)
- `store(_ artifact:) -> UUID` — 저장 + UUID 반환
- `fetch(_ id:) -> Artifact?` — UUID 조회, TTL 초과 시 nil
- `gc()` — 만료 항목 정리
- 앱 재시작 시 초기화 (Telegram 발송 → 즉시 클릭 시나리오만 보장)

### Viewer Sheet: TelegramArtifactViewerSheet

`Sources/YuminaiApp/TelegramHub/TelegramArtifactViewerSheet.swift`

- `YuminaiSheet(width: 720, height: 560)` container
- diff 타입: +/-/@@ 라인별 syntax highlight (green/red/cyan), `TextSelection` enabled
- log 타입: monospaced + 마지막 줄 자동 스크롤 (`ScrollViewReader`)
- 만료/없음: `AnimatedEmptyState` (ID 표시)
- footer: [복사] [닫기], diff면 [Workspace 열기] 추가

### AppModel 통합

```swift
public let telegramArtifactStore: TelegramArtifactStore = TelegramArtifactStore()
public var showTelegramArtifactSheet: Bool = false
public var artifactSheetId: UUID? = nil
```

- `handleDeepLink(.diff(id:))` / `.log(id:)` → `artifactSheetId = id` + `showTelegramArtifactSheet = true`

### RootView.swift

```swift
.sheet(isPresented: $bindable.showTelegramArtifactSheet) {
    if let id = appModel.artifactSheetId {
        TelegramArtifactViewerSheet(artifactId: id).environment(appModel)
    }
}
```

---

## 산출물 B — 5MB+ 자동 sendDocument 전환

`Sources/YuminaiTelegram/TelegramLargePayloadSender.swift`

### 라우팅 규칙

| 크기 | 동작 |
|------|------|
| < 4000 bytes | `client.send(text, to:)` |
| 4000 ≤ size < 5MB | `client.send(truncated + warning, to:)` |
| ≥ 5MB | `client.sendDocument(fileName:data:caption:to:)` |
| ≥ 50MB | `TelegramLargePayloadError.exceedsAbsoluteMax` throw |

`TelegramMessageFormatter.shouldSendAsDocument(byteCount:)` (ADR-095) 활용.

### API

```swift
public static func sendOrAttach(
    text: String,
    fileName: String,
    caption: String,
    to chatId: Int64,
    client: any TelegramClient
) async throws -> SentTelegramMessage
```

---

## 산출물 C — macOS UserNotification 권한 요청

`Sources/YuminaiCore/MacOSNotificationPermission.swift`

### Status enum

```swift
public enum Status: String, Sendable, Equatable, CaseIterable {
    case notDetermined, denied, authorized, provisional, ephemeral, unavailable
}
```

### API

- `currentStatus() async -> Status` — 현재 권한 상태 조회
- `requestPermission() async -> Status` — 권한 요청 (`.alert`, `.sound`, `.badge`)

### TelegramHubSettingsTab 통합

설정 탭 최상단에 "macOS 알림 권한" 카드 추가:
- 현재 상태 아이콘 + 설명
- `notDetermined`: [권한 요청] 버튼
- `denied`: [Settings 열기] 버튼
- `authorized`: ✅ 아이콘

### AppModel 통합

```swift
public var macOSNotificationStatus: MacOSNotificationPermission.Status = .notDetermined
public func setupNotificationStatusCheck() async  // 앱 시작 시 상태 확인
public func requestMacOSNotificationPermission() async  // 사용자 요청
```

---

## 검증

### 자동 테스트

| 테스트 파일 | 항목 수 | 커버리지 |
|------------|---------|---------|
| `TelegramArtifactStoreTests.swift` | 8 | store/fetch round-trip, TTL, capacity eviction, gc(), 동시성, diff/log 구별, workspace nil, 없는 UUID |
| `MacOSNotificationPermissionTests.swift` | 4 | Status Equatable, rawValue, CaseIterable |
| `TelegramLargePayloadSenderTests.swift` | 6 | 라우팅 결정 (3500B/10KB/1MB/6MB), send 호출, sendDocument 호출, 51MB throw |

### 빌드 + 테스트

```bash
cd /Users/bbikiming/Documents/vibe_coding/Yuminai
swift build    # → Build complete!
swift test     # → 895+ tests passed (885 + 신규 18)
```

### 수동 검증 가이드 (E2E)

1. **Artifact Viewer**:
   ```swift
   // AppModel에서 artifact 저장 후 deep link 트리거
   let id = await appModel.telegramArtifactStore.store(
       .diff(content: "+ var x = 1", files: 1, added: 1, removed: 0, workspace: nil)
   )
   await appModel.handleDeepLink(.diff(id: id))
   // → TelegramArtifactViewerSheet가 표시되어야 함
   ```

2. **Auto sendDocument**:
   ```swift
   // 6MB 텍스트로 sendOrAttach 호출
   let bigText = String(repeating: "A", count: 6 * 1024 * 1024)
   try await TelegramLargePayloadSender.sendOrAttach(
       text: bigText, fileName: "diff.txt", caption: "preview", to: chatId, client: bot
   )
   // → sendDocument 호출 확인 (bot.sentDocumentLog에 기록)
   ```

3. **Notification Permission**:
   - Telegram Hub → 설정 탭 열기
   - 상단 "macOS 알림 권한" 카드 확인
   - [권한 요청] 버튼 클릭 → 시스템 다이얼로그 확인
   - 허용 후 ✅ 상태로 전환 확인

---

## 후속 항목

이 ADR로 ADR-092부터 시작된 Telegram 통합 시리즈가 완전히 종결된다.

향후 개선 사항 (별도 ADR):
- `TelegramArtifactStore` 영속 저장 (iCloud KeyValue / Keychain) — 앱 재시작 후에도 링크 유효
- `sendOrAttach` → `TelegramAlertDispatcher.dispatch`에 통합
- diff viewer에 Accept/Reject HITL 버튼 추가 (현재는 read-only)
