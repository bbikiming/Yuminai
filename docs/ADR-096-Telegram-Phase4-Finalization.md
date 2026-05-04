# ADR-096 — Telegram Phase 4 Finalization

**상태**: 완료  
**날짜**: 2026-05-04  
**참고**: ADR-092 ~ 095 (Phase 1-4)

---

## 배경

ADR-095 Phase 4에서 백엔드(NotificationPolicyMatrix, TelegramDeepLinkRouter, TelegramMessageFormatter.shouldSendAsDocument)를 데이터 모델/유틸리티 형태로 완성했으나, 3개 항목을 후속으로 미루었다.

1. **A.** macOS `yuminai://` URL scheme 등록 + `onOpenURL` 핸들러
2. **B.** Quiet Hours / NotificationPolicyMatrix 편집 UI
3. **C.** 5MB+ `sendDocument` protocol/mock/LiveBot 구현

이 ADR은 3개 항목을 최소 diff로 완료한다.

---

## 산출물 A — URL scheme 등록 + onOpenURL 핸들러

### Info.plist 변경

`App/Info.plist`에 `CFBundleURLTypes` 추가:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>com.yuminai.deeplink</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>yuminai</string>
        </array>
    </dict>
</array>
```

### YuminaiApp.swift onOpenURL

`WindowGroup` body에 `.onOpenURL` 수식자 추가 → `TelegramDeepLink.parse(url)` 호출 → `appModel.handleDeepLink(_:)` 디스패치.

### AppModel.handleDeepLink

```swift
public func handleDeepLink(_ link: TelegramDeepLink) async
```

| 케이스 | 동작 |
|--------|------|
| `.diff(id)` | `NSApp.activate` + 로그 (diff viewer는 후속) |
| `.log(id)` | `NSApp.activate` + 로그 (log viewer는 후속) |
| `.workspace(id)` | `NSApp.activate` + `transitionToWorkspace(id)` |
| `.chat(id)` | `NSApp.activate` + `showTelegramHubSheet = true` |
| `.approve(requestId)` | `respondToHITL(id:, response: .approved(by: "deeplink"))` |
| `.reject(requestId)` | `respondToHITL(id:, response: .rejected(by: "deeplink"))` |

### 수동 검증 가이드

앱 빌드 + 설치 후:

```bash
open "yuminai://approve/<existing-hitl-request-uuid>"
open "yuminai://workspace/<existing-workspace-uuid>"
open "yuminai://chat/0"
```

SPM executable(`swift run YuminaiApp`)은 `.app` 번들이 아니므로 URL scheme이 시스템에 자동 등록되지 않는다. 정식 `.app` 번들(`App/build_app_bundle.sh`)을 빌드하고 `/Applications/`에 설치해야 `open` 명령이 동작한다.

---

## 산출물 B — Quiet Hours / NotificationPolicyMatrix 편집 UI

### 신규 파일: TelegramHubSettingsTab.swift

`Sources/YuminaiApp/TelegramHub/TelegramHubSettingsTab.swift` — 3개 섹션:

1. **Quiet Hours** — Toggle + Stepper(시작/종료 시각 0-23) + 현재 활성 여부 caption
2. **HITL 설정** — timeout Slider(10-300초, step 10) + diffLimit Stepper(10-100줄, step 5)
3. **알림 정책 매트릭스** — 5 NotificationKind × 3 DeviceState × Menu Picker(4 채널) + "기본값으로 재설정" 버튼

### TelegramHubView.swift 변경

`Tab` enum에 `.settings` 탭 추가 (5번째 탭, icon: `bell.badge.fill`).

### AppModel 신규 메서드

```swift
public func updateNotificationPolicy(_ matrix: NotificationPolicyMatrix) async
public func updateQuietHours(start: Int?, end: Int?) async
public func updateHITLTimeout(_ seconds: Int) async
public func updateDiffPreviewLineLimit(_ limit: Int) async
public func resetNotificationPolicyToDefault() async
```

모두 preferences 필드를 불변 패턴(spread copy)으로 업데이트 후 `savePreferences()` 호출.

### DeviceState.CaseIterable 추가

`DeviceState`에 `CaseIterable` 채택을 `YuminaiCore/NotificationPolicy.swift`에 추가. UI 매트릭스 테이블 렌더링 + 테스트에서 활용.

---

## 산출물 C — sendDocument protocol/mock/LiveBot

### TelegramClient protocol 확장

```swift
func sendDocument(
    fileName: String,
    data: Data,
    caption: String?,
    to chatId: Int64
) async throws -> SentTelegramMessage
```

### MockTelegramBot 확장

`sentDocumentLog: [(fileName:, data:, caption:, chatId:)]` 기록. `sentLog`에도 caption/fileName이 기록됨(기존 테스트 호환).

### LiveTelegramBot 확장

- multipart/form-data POST `sendDocument` API
- caption 1024자 truncate [H]
- 파일 50MB 초과 즉시 throw (code=-2) [H]
- `withRetry` + `rateLimiter` 적용 (기존 `send` 패턴 일치)
- `Data.appendMultipartField` / `appendMultipartFilePart` 내부 extension helper

---

## 데이터 모델 변경

없음. 기존 `AppPreferences` 필드(ADR-095) 그대로 활용.

---

## 검증

```
swift build   → Build complete! (0 errors)
swift test    → 885 tests passed (874 baseline + 11 신규)
```

신규 테스트:
- `ADR096NotificationSettingsTests` (YuminaiCoreTests) — 6개
  - DeviceState.allCases 3개 확인
  - NotificationPolicy 단일 셀 변경
  - AppPreferences 불변 업데이트 패턴 (quietHours / hitlTimeout / diffLimit / reset)
- `SendDocumentTests` (YuminaiTelegramTests) — 5개
  - MockBot sentDocumentLog/sentLog 기록
  - caption nil 처리
  - LiveBot 50MB 초과 throw

---

## 후속 항목

| 항목 | 설명 |
|------|------|
| diff viewer sheet | `yuminai://diff/<uuid>` 수신 시 실제 DiffView sheet 표시 |
| log viewer sheet | `yuminai://log/<uuid>` 수신 시 로그 뷰어 sheet 표시 |
| sendDocument 자동 전환 | diff/log 메시지 발송 시 `TelegramMessageFormatter.shouldSendAsDocument` 검사 → 5MB+이면 sendDocument 사용 |
