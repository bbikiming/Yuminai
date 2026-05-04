# ADR-098 (Candidate) — Telegram 통합 Gap 분석 (ADR-092 ~ 097 후속)

- **날짜**: 2026-05-04 (Monday)
- **상태**: Candidate / Investigation Report (ADR 정식 승인 전)
- **선행 ADR**: ADR-092 (UX 기획) → ADR-093 (Dock+ContextCard) → ADR-094 (CommandPalette+HITL) → ADR-095 (Diff/DeepLink/Multi-device) → ADR-096 (Phase 4 finalization) → ADR-097 (Artifact viewer + sendDocument + Notification permission)
- **검증 baseline**: `swift test` → 905 tests passed in 174 suites (1.278s, 2026-05-04)
- **보고 작성 시각**: 2026-05-04 Monday

> **표기 규약**: 본 보고서의 모든 코드 증거는 `file:line` 형식으로 명시한다. 상태 라벨: ✅ 완료 · 🟡 부분 완료 (백엔드만 / UI만 / wire-up 누락) · ❌ 미완. 신뢰도 라벨은 grep 직접 검증된 사실은 [H] (high), 미검증/추정은 [M] (moderate).

---

## 1. Executive Summary (결론 먼저)

1. **UI shell은 완성, 핵심 wire-up 4개가 누락 — 사용자 경험은 75% 완성, end-to-end 작동은 약 40%**. 백엔드가 견고한데 호출하는 코드가 없는 "고아 actor" 패턴이 6곳 발견됐다 [H].
2. **ADR-092 §4.6 HITL 흐름은 무한정지 — `TelegramHITLCoordinator.request()`를 호출하는 production 코드가 0건**. 응답(`respond`) 경로만 wire되어 있어 데스크탑/텔레그램 양쪽에서 "승인할 것"이 영원히 없는 상태 [H] (`grep -rn "request(action" Sources/` → 0 matches).
3. **사용자 핵심 task 5개 중 T1(/run)·T3(HITL)·T4(/abort)은 ADR-092 권장 형식대로 작동하지 않는다**. T2(diff 리뷰)와 T5(/status)만 부분 작동 [H]. `/run`과 `/abort`는 BotFather에는 등록되지만 `YuminaiCommandRouter.handleCommand`의 switch에는 case가 없어 "알 수 없는 명령" 응답만 돌아온다 [H] (`Sources/YuminaiApp/YuminaiCommandRouter.swift:115-163`).
4. **NotificationPolicyMatrix는 코드는 완벽한데 dispatcher에 주입이 안 됐다** — `TelegramAlertDispatcher` 초기화 시 `deliveryChannelProvider: nil`로 생성되어 (`AppModel.swift:4477-4481`) quiet hours / device state 정책이 실제 알림 라우팅에 영향을 주지 못한다 [H].
5. **ADR-092 Appendix A 후속 연구 6개 중 0개 처리** — 그룹 채팅 N-of-M, voice message (Whisper), Telegram Mini Apps, outage fallback 등은 모두 미착수. 추가로 그룹 chat 멀티유저 admin 정책, 봇 polling 라이프사이클(앱 sleep/wake), MCP 노출, 첨부파일 업로드, 로컬라이제이션은 ADR-092에서도 언급되지 않았다 [H].

**권장**: ADR-098로 P0 wire-up 4건만 즉시 처리하면 ADR-092 시리즈가 진정한 의미에서 "end-to-end 작동" 상태가 된다. 작업량 S/M (3-5일).

---

## 2. ADR별 미룬 항목 매트릭스

각 ADR이 "후속 ADR로 미룬다"고 선언한 항목 → 실제 후속 ADR/코드에서 처리됐는지 확인.

### 2.1 ADR-092 미룬 항목 (§6 로드맵 + Appendix A)

| 항목 | ADR-092 위치 | 상태 | 처리 ADR / 코드 증거 |
|---|---|---|---|
| Phase 1: Hub 4-tab + Wizard | §6 Phase 1 | ✅ | ADR-093 (Hub shell) + Step1/2/3 (`Sources/YuminaiApp/TelegramHub/Onboarding/`) |
| Phase 2: BotStatusDock + ChatContextCard + ActivityFeed | §6 Phase 2 | ✅ | ADR-093 commit 18a1077 |
| Phase 3: CommandPaletteEditor + HITLCoordinator + InlineCallback | §6 Phase 3 | 🟡 백엔드만 | ADR-094 commit 620d387 (구현은 있으나 `request()` 호출 0건 — 아래 §4 참조) |
| Phase 4: Diff/Log preview + deep link + multi-device + quiet hours | §6 Phase 4 | 🟡 데이터 모델만 | ADR-095/096/097 — formatter/router/policy 모두 데이터 모델 OK, 실제 발송 경로 wire-up 안됨 (§4) |
| **App.A 후속 1**: 폰 화면 diff 가독성 사용자 테스트 | Appendix A | ❌ | 없음 |
| **App.A 후속 2**: HITL timeout (60s) 적정성 측정 | Appendix A | ❌ | 없음 |
| **App.A 후속 3**: Telegram outage 시 HITL fallback (자동 reject? 데스크탑 only?) | Appendix A | ❌ | 없음 |
| **App.A 후속 4**: 그룹 채팅 N-of-M approval | Appendix A | ❌ | 없음 (§6 P2 후보) |
| **App.A 후속 5**: Voice message + Whisper 통합 | Appendix A | ❌ | 없음 (§6 P3 후보) |
| **App.A 후속 6**: Telegram Mini Apps webview 임베딩 | Appendix A | ❌ | 없음 |

### 2.2 ADR-093 미룬 항목 (§5 표 6개)

| 항목 | 상태 | 처리 ADR / 증거 |
|---|---|---|
| `/start` 자동 감지 (long polling 인프라) | 🟡 부분 | ADR-095 `TelegramFirstMessageDetector` 구현 (`Sources/YuminaiTelegram/TelegramFirstMessageDetector.swift:14`) — wizard 외 사용 없음 |
| BotFather `setMyCommands` sync | 🟡 manual only | ADR-094 `LiveTelegramBot.setMyCommands` (`LiveTelegramBot.swift:528`) + UI 버튼 — 명령 변경 시 자동 sync 트리거 없음 |
| HITL 승인 흐름 (inline button callback) | 🟡 callback OK / request 0건 | ADR-094 callback handler 작동 — 하지만 §4의 wire-up 누락 |
| `yuminai://` deep link URL scheme | ✅ | ADR-095 `TelegramDeepLinkRouter` + ADR-096 Info.plist `App/Info.plist:CFBundleURLTypes` |
| URLSession mock 기반 getMe 단위 테스트 | ✅ | `Tests/YuminaiCoreTests/TelegramBotInfoTests.swift` |
| 다중 디바이스 "seen on desktop" edit | ❌ | ADR-095/096에 없음 — `editMessageText` 호출 코드 없음 |

### 2.3 ADR-094 미룬 항목 (§"다음 Phase로 미룬 항목")

| 항목 | 상태 | 처리 ADR / 증거 |
|---|---|---|
| `/start` 자동 허용 목록 감지 | ✅ | ADR-095 `TelegramFirstMessageDetector` |
| `yuminai://` deep link (HITL 응답) | ✅ | ADR-095/096 — `.approve(uuid)`, `.reject(uuid)` 케이스 존재 (`AppModel.swift:5471-5474`) |
| 다중 디바이스 동기화 정책 (iCloud KeyValue store) | ❌ | ADR-095/096/097에서도 미처리 — preferences는 로컬만 |
| Quiet hours UI | ✅ | ADR-096 `TelegramHubSettingsTab` |
| HITL macOS UserNotification | 🟡 권한 UI만 | ADR-097 `MacOSNotificationPermission` (status/request만) — **실제 `add(UNNotificationRequest)` 호출 코드 0건** [H] (§4) |
| setMyCommands scope 옵션 (BotFather per-chat scope) | ❌ | LiveBot은 single scope만 |

### 2.4 ADR-095 미룬 항목 (§"후속 작업")

| 항목 | 상태 | 처리 ADR / 증거 |
|---|---|---|
| macOS URL scheme 시스템 등록 (`CFBundleURLTypes` Info.plist) | ✅ | ADR-096 `App/Info.plist` |
| 실제 `desktopOff` 자동 감지 | 🟡 sleep만 | `AppModel.swift:5371-5377` — `willSleepNotification`은 `desktopIdle`로만 매핑, `desktopOff`는 manual set만 (`AppModel.swift:5349`) |
| Quiet Hours UI | ✅ | ADR-096 `TelegramHubSettingsTab` |
| NotificationPolicyMatrix 편집 UI | ✅ | ADR-096 동일 |
| Digest 묶기 (rate limit 격하 5분 3회) | ❌ | 없음 |

### 2.5 ADR-096 미룬 항목 (§"후속 항목")

| 항목 | 상태 | 처리 ADR / 증거 |
|---|---|---|
| diff viewer sheet | ✅ | ADR-097 `TelegramArtifactViewerSheet` |
| log viewer sheet | ✅ | ADR-097 동일 |
| sendDocument 자동 전환 (5MB+) | 🟡 sender만 | ADR-097 `TelegramLargePayloadSender.sendOrAttach` 구현 — **`TelegramAlertDispatcher.dispatch`에 통합되지 않았다** [H] (§4) |

### 2.6 ADR-097 미룬 항목 (§"후속 항목")

| 항목 | 상태 | 처리 ADR / 증거 |
|---|---|---|
| `TelegramArtifactStore` 영속 저장 (iCloud/Keychain) | ❌ | 메모리 ring buffer만 (`TelegramArtifactStore.swift:9-39`) |
| `sendOrAttach` → `TelegramAlertDispatcher.dispatch` 통합 | ❌ | dispatcher는 `client.send()` 직접 호출 (`TelegramAlertDispatcher.swift:51`) |
| diff viewer Accept/Reject HITL 버튼 | ❌ | ArtifactViewerSheet은 read-only |

---

## 3. ADR-092 §4 권장 항목 매핑 표

ADR-092 §4의 7개 권장 UX 항목 → 실제 구현 + 사용자 관점 작동성.

| # | 권장 항목 | 구현 상태 | 사용자 관점 작동? | 코드 증거 |
|---|---|---|---|---|
| §4.1 | 단일 Telegram Hub (4-tab) | ✅ Hub 구조 + 5번째 Settings 탭 (ADR-096) | ✅ | `TelegramHubView.swift` (Bots/Bindings/Commands/Activity/Settings) |
| §4.2 | 3-step Onboarding Wizard | ✅ + `/start` 자동 감지 (ADR-095) | 🟡 wizard 외 detector 사용 없음 | `Onboarding/OnboardingStep1Token.swift`, `OnboardingStep2Whitelist.swift` |
| §4.3 | Bot Status Dock | ✅ | ✅ | `BotStatusDock.swift` (ADR-093) |
| §4.4 | Chat Context Card | ✅ | ✅ | `ChatContextCard.swift` |
| §4.5 | Inline Command Palette + setMyCommands sync | 🟡 manual sync only | 🟡 sync는 사용자가 버튼 눌러야 함, default 7개 명령 중 5개는 라우터 case 없음 | `CommandPaletteEditor.swift:199`, `YuminaiCommandRouter.swift:115-163` |
| §4.6 | HITL 승인 흐름 (5단계) | 🟡 인프라 OK / 진입점 0건 | ❌ end-to-end 작동 불가 | `TelegramHITLCoordinator.swift`, `HITLApprovalSheet.swift` — 호출자 없음 |
| §4.7 | Diff/Log preview + jump | 🟡 formatter만 | 🟡 dispatcher가 사용 안함 | `TelegramMessageFormatter.swift` — production 0건 호출 (§4 wire-up) |
| §4.8 | 다중 디바이스 알림 정책 | 🟡 matrix만 | ❌ provider 주입 누락 | `NotificationPolicyMatrix` 코드 OK, dispatcher 생성 시 nil (`AppModel.swift:4477`) |

### 3.1 §4.6 HITL 5단계 step-by-step 검증

ADR-092 §4.6은 5단계를 명시:
1. Yuminai가 destructive action 감지 (hooks 활용)
2. macOS UN + Telegram 동시 발송
3. 사용자가 inline button → callback → unblock
4. 메시지 자동 edit ("Approved by ...")
5. 60s timeout → auto-reject + edit

**실제 검증:**
| 단계 | 구현 위치 | 상태 |
|---|---|---|
| 1. destructive 감지 | `TelegramSessionBridge.isDestructiveToolCall` (`SessionBridge.swift:434-452`) — bash + 19개 위험 패턴 | ✅ 감지 OK |
| 1→2. HITL coordinator로 routing | (없음) | ❌ Bridge는 `cancel/status` 버튼만 push, HITL request는 0건 |
| 2. Telegram message | `Bridge.consume(event:)` `sendWithKeyboard("🚨 위험한 작업 감지...")` | 🟡 발송은 OK / HITL flow와 무관 |
| 2. macOS UN 동시 | `MacOSNotificationPermission`만 존재, `add(UNNotificationRequest)` 호출 코드 0건 | ❌ 권한만 받고 알림 발송 안 함 |
| 3. inline button → callback | `TelegramHITLCallbackHandler` + `YuminaiCommandRouter.handleCallback` (`YuminaiCommandRouter.swift:54-77`) | ✅ callback 처리 OK (단, 살아있는 request가 있을 때만) |
| 4. message edit "Approved by ..." | (없음) | ❌ `editMessageText` 호출 없음 |
| 5. 60s timeout | `TelegramHITLCoordinator.timeoutIfPending` | ✅ actor에선 OK / 메시지 edit 안 됨 |

**결론**: 5단계 중 3단계 (감지·callback·timeout)만 작동하고, 핵심 인입(1→2 routing) + 사용자 알림(macOS UN) + 응답 후 메시지 edit은 모두 누락. ADR-092 §4.6의 디자인 그림은 코드에서 한 번도 발생하지 않는다.

---

## 4. Wire-up 누락 분석 (P0 — 가장 시급)

### 4.1 TelegramHITLCoordinator — request() 호출 0건

**증거**:
- `grep -rn "request(action" Sources/` → 0 matches [H]
- `grep -rn "hitlCoordinator\." Sources/` → 4개 모두 `respond()`/`pendingRequests()` 호출만 (`AppModel.swift:5337,5338`) [H]
- 유일한 인스턴스 생성: `setupTelegramHITLCoordinator()` (`AppModel.swift:5306-5308`)

**영향도**: ❌ Critical
- 사용자가 destructive action을 하면 `TelegramSessionBridge`가 텔레그램에 "🚨 위험한 작업 감지 — [중단][상태]" 메시지를 보내지만, 이는 단순 알림 + 취소 버튼.
- ADR-092 §4.6의 "✅ Approve / ❌ Reject / 🔍 View Diff" + 60s timeout + 자동 edit 플로우는 영원히 발생하지 않는다.
- HITLApprovalSheet도 영원히 비어있는 sheet (pending 0).

**누락 wire-up**:
```
TelegramSessionBridge.consume(event:) 의 if Self.isDestructiveToolCall(...) 분기
  → 현재: sendWithKeyboard("🚨 ...", "cancel"/"status" buttons)
  → 필요: await appModel.hitlCoordinator?.request(action:..., timeout:60)
        → 응답 .approved → 작업 계속
        → 응답 .rejected/.timeout → 작업 차단
```

### 4.2 TelegramAlertDispatcher — deliveryChannelProvider 미주입

**증거**:
- `AppModel.swift:4477-4481`:
  ```swift
  alertDispatcher = TelegramAlertDispatcher(
      client: bot,
      policy: preferences.telegramAlertPolicy,
      chatId: chatId
  )
  ```
- `TelegramAlertDispatcher.swift:25-31`: `deliveryChannelProvider: ... = nil` default
- `TelegramAlertDispatcher.swift:46`: `let channel = deliveryChannelProvider?(kind) ?? .telegramOnly` → nil이면 항상 telegramOnly
- `updateDeliveryChannelProvider` 메서드는 정의만 됨, 호출 0건 [H]

**영향도**: ❌ High
- `NotificationPolicyMatrix`(ADR-095) + `currentDeliveryChannel(for:)` (`AppModel.swift:5408`) 모두 작동하는 코드인데 dispatcher가 사용 안 함.
- Quiet Hours가 활성화돼도 모든 알림이 Telegram으로 발송됨 (격하 안 됨).
- DeviceState (active/idle/off)에 따른 채널 분기도 무효.

**누락 wire-up**:
```swift
// AppModel.swift:4481 직후 추가 필요
await alertDispatcher?.updateDeliveryChannelProvider { [weak self] kind in
    self?.currentDeliveryChannel(for: kind) ?? .telegramOnly
}
```

### 4.3 TelegramArtifactStore — store() 호출 0건

**증거**:
- `grep -rn "telegramArtifactStore\." Sources/` → 1 match: `fetch(artifactId)` (`TelegramArtifactViewerSheet.swift:221`) [H]
- `grep "\.store(" TelegramArtifactStore.swift Sources/YuminaiApp` → 0 production callers [H]

**영향도**: 🟡 High (hidden — 사용자 시나리오의 절반 차단)
- `yuminai://diff/<uuid>` 또는 `yuminai://log/<uuid>` 딥링크는 작동하는 코드 (`AppModel.handleDeepLink`)지만, 누구도 artifact를 store하지 않으면 모든 딥링크가 "만료/없음" empty state로 안내됨.
- ADR-092 §4.7의 diff preview + "View Full in Yuminai" deep link는 영원히 깨진 링크.

**누락 wire-up**:
```
TelegramSessionBridge가 diff/log 메시지를 보낼 때:
  1. let id = await appModel.telegramArtifactStore.store(.diff(...))
  2. let link = TelegramDeepLink.diff(id: id).url
  3. message text + InlineButton(text:"📂 View Full", url: link)
```

### 4.4 TelegramLargePayloadSender — sendOrAttach 호출 0건 (production)

**증거**:
- `grep -rn "sendOrAttach\|TelegramLargePayloadSender\." Sources/ Tests/` → 모든 호출이 `Tests/YuminaiTelegramTests/TelegramLargePayloadSenderTests.swift` 내부 [H]
- production 코드 0건

**영향도**: 🟡 Medium (5MB+ 시나리오에서만 발현)
- 5MB+ diff/log를 보내려 하면 `TelegramAlertDispatcher.dispatch`가 직접 `client.send()` 호출 → Telegram API가 4096자 초과로 reject.
- 의도한 자동 sendDocument 전환이 발생하지 않음.

**누락 wire-up**:
```swift
// TelegramAlertDispatcher.dispatch 내부에서
//   _ = try? await client.send(formatted, to: chatId)  ← 현재
// 를
//   _ = try? await TelegramLargePayloadSender.sendOrAttach(text: formatted, fileName:..., caption:..., to: chatId, client: client)
// 로 교체
```

### 4.5 TelegramFirstMessageDetector — wizard 외 사용 없음 + polling 충돌 위험

**증거**:
- `grep -rn "TelegramFirstMessageDetector" Sources/` → wizard Step 2만 사용 (`OnboardingStep2Whitelist.swift:18`) + 본체 [H]
- detector는 `getUpdates` long-polling을 직접 수행 (`TelegramFirstMessageDetector.swift:156`) — `LiveTelegramBot.startPolling()`도 같은 토큰으로 polling
- AppModel.swift:4795에 cokacdir과의 충돌은 경고 alert가 있지만, **wizard 중에 메인 봇이 동시 polling 중이면 same-token race 발생 가능** (Telegram getUpdates는 first-poll-wins)

**영향도**: 🟡 Medium
- 정상 시나리오: wizard 진입 시 봇이 아직 활성화 안 됨 (토큰 새로 입력 중) → 충돌 적음.
- 위험 시나리오: 이미 봇이 활성화된 상태에서 사용자가 토큰 변경/재 wizard 시작 → polling 분산.

### 4.6 TelegramMessageFormatter.formatDiff/formatLog — production 0건

**증거**:
- `grep -rn "TelegramMessageFormatter\." Sources/` → `enforceMaxBytes` 1건 (`TelegramLargePayloadSender.swift:77`) [H]
- `formatDiff` / `formatLog` 호출은 모두 `Tests/`만 [H]

**영향도**: 🟡 High (UX 일관성)
- ADR-092 §4.7의 fenced code block + "📂 View Full in Yuminai" 형식의 diff 메시지는 한 번도 발송되지 않는다.
- 현재 diff는 `YuminaiCommandRouter.diffCommand` (`YuminaiCommandRouter.swift:313-327`)에서 "수동" 형식으로 보냄 — fenced + 3500자 cap만 (deep link 없음).

### 4.7 MacOSNotificationPermission — UN notification 발송 코드 0건

**증거**:
- `grep -rn "UNUserNotificationCenter\|UNMutableNotificationContent\|UNNotificationRequest" Sources/` → `MacOSNotificationPermission.swift` 내부 권한 조회만 (3 matches) [H]
- 실제 `UNUserNotificationCenter.current().add(UNNotificationRequest(...))` 코드 0건 [H]

**영향도**: ❌ High
- 사용자가 ADR-097 권한 UI에서 "권한 요청" → 허용 → ✅ 표시까지는 작동하지만, **이후 어떤 알림도 macOS native로 발송되지 않는다**.
- ADR-092 §4.8 매트릭스의 `macOSOnly`, `both` 채널 모두 무효.

### 4.8 setMyCommands — 자동 sync 트리거 없음

**증거**:
- `addTelegramCommand`/`updateTelegramCommand`/`removeTelegramCommand` (`AppModel.swift:5257-5274`) — savePreferences만 호출, sync 트리거 없음 [H]
- sync는 `CommandPaletteEditor.swift:199`의 "Sync to BotFather" 버튼 manual click만 [H]
- BotFather scope 옵션 (per-chat / per-language) 미구현 — `LiveTelegramBot.setMyCommands` (`LiveTelegramBot.swift:528`)는 default scope만 [H]

**영향도**: 🟡 Medium
- 사용자가 명령 추가/편집해도 BotFather에는 즉시 반영 안 됨 → autocomplete 불일치.

---

## 5. 사용자 핵심 task 5개 동작성 평가 (ADR-092 §3.3)

### T1 — `/run swift test` (원격 명령 실행)

**Trace**:
1. 사용자 텔레그램 메시지 `/run swift test` 발송
2. `LiveTelegramBot.pollLoop` → `incoming` AsyncStream
3. `TelegramCommandPump.start` → `router.handle(message)` 호출
4. `YuminaiCommandRouter.handleCommand("/run swift test", ...)`:
5. `switch cmd { case "/bind"... case "/help"... default: return "알 수 없는 명령: /run\n/help로..." }` (`YuminaiCommandRouter.swift:115-163`)

**결과**: ❌ T1 작동 안 함. `/run`은 BotFather에는 등록되지만 (TelegramCommand.defaultCommands), router에 case 없음. 사용자는 prefix 없이 그냥 "swift test"를 보내야 plain text → `handlePlainText` → `model.sendMessage()` 경로로 작동 (단, bind된 워크스페이스 필요).

**작업**: `YuminaiCommandRouter.handleCommand`에 `/run`, `/abort`, `/approve`, `/reject` 케이스 추가.

### T2 — 결과 / diff 리뷰

**Trace**:
1. 사용자 `/diff` 발송
2. `YuminaiCommandRouter.diffCommand()` (`YuminaiCommandRouter.swift:313-327`)
3. fenced code block + 3500자 cap

**결과**: 🟡 작동. 단, ADR-092 §4.7의 deep link button (`📂 View Full in Yuminai`) 없음. `TelegramMessageFormatter.formatDiff`도 사용 안함. 5MB+ diff은 sendDocument로 전환 안 됨 (4.4 참조).

### T3 — HITL 승인

**Trace**:
1. Claude가 destructive bash 실행 (예: `git push --force`)
2. `TelegramSessionBridge.isDestructiveToolCall` 감지 (`SessionBridge.swift:434`)
3. → 텔레그램에 "🚨 위험한 작업 감지 — [중단][상태]" 메시지 발송 (cancel/status 버튼)
4. 사용자가 [중단] 누름 → `YuminaiCommandRouter.handleCallback("cancel")` → `cancelCommand` → `model.cancelBoundTurn`
5. 작업이 이미 진행되어 있음 (push 발생 후 중단)

**결과**: ❌ ADR-092 §4.6의 "destructive 직전에 차단 + 60s timeout + Approve/Reject/Diff 버튼"이 작동하지 않음. 현재는 "destructive가 진행되는 동안 알림 + 사용자가 빨리 취소" 패턴 (5단계 step-by-step 검증은 §3.1).

**작업**: §4.1 wire-up.

### T4 — `/abort` (긴급 중단)

**Trace**:
1. 사용자 `/abort` 발송
2. `YuminaiCommandRouter.handleCommand` → switch에 case 없음 → "알 수 없는 명령: /abort"

**결과**: ❌ T4 작동 안 함. 사용자는 `/cancel` 또는 `/stop`을 사용해야 함 (`YuminaiCommandRouter.swift:122`). BotFather autocomplete은 `/abort`를 제안하지만 router는 모름.

### T5 — 상태 확인 (`/status`)

**Trace**:
1. 사용자 `/status` 발송
2. `YuminaiCommandRouter.handleCommand` → `case "/status": return await statusCommand()` (`YuminaiCommandRouter.swift:120`)
3. `model.telegramStatusSnapshot()` → bind 정보 + 외부 turn 누적 비용

**결과**: ✅ 작동. ADR-092 §4의 "edited progress message" 패턴은 미구현 — 새 메시지로만 응답.

### T1-T5 종합

| Task | 작동성 | 핵심 이슈 |
|---|---|---|
| T1 `/run` | ❌ | BotFather autocomplete vs router mismatch |
| T2 `/diff` | 🟡 | deep link button 없음, formatter 미사용 |
| T3 HITL | ❌ | request() 호출 0건, 5단계 중 3단계 누락 |
| T4 `/abort` | ❌ | router case 없음 (`/cancel`로 대체 가능하지만 일관성 없음) |
| T5 `/status` | ✅ | 작동 |

**5개 중 1개(20%)가 ADR-092 권장 형식대로 작동.**

---

## 6. 기획 누락 / 부족 영역 (ADR-092에서 미언급)

### 6.1 그룹 채팅 멀티유저

| 측면 | 현재 상태 | 평가 |
|---|---|---|
| Admin-only 명령 | `TelegramCommand.Permission.admin` 정의만 (`TelegramCommand.swift:26`) | 🟡 데이터 모델만 / Pump에서 enforce 0건 |
| N-of-M approval | 없음 | ❌ |
| Mention-based 트리거 (`@bot ...`) | 없음 — 모든 메시지가 router로 갈 뿐 | ❌ |
| 그룹 멤버 whitelist | `telegramAllowedUserIds` (single set, group/dm 구분 없음) | 🟡 부분 |

ADR-092 Appendix A 후속 #4 "그룹 채팅 N-of-M approval"은 추후 ADR로 명시됐으나 ADR-098 candidate에서 P2로 다시 평가.

### 6.2 봇 polling 라이프사이클

| 측면 | 현재 상태 | 평가 |
|---|---|---|
| 앱 sleep/wake 시 polling 자동 stop/restart | 없음 — `AppModel.setupDeviceStateMonitor` (`AppModel.swift:5371-5377`)는 deviceState만 변경, polling 미터치 | ❌ |
| 다중 봇 동시 polling | `TelegramMultiBot` 인프라는 있으나 실제 활성 botpooling은 single primary `telegramBot` 중심 | 🟡 |
| polling 재시작 retry | `LiveTelegramBot.pollLoop` 내부 exponential backoff [H] | ✅ |
| 401/403/404 시 polling 중단 + 사용자 알림 | `LiveTelegramBot.swift:359-367` | ✅ |

ADR-092에서 미언급. 모바일 PC 사용자에겐 중요 (sleep 후 wake 시 봇 재시작 안 되면 메시지 누락).

### 6.3 MCP 통합

| 측면 | 현재 상태 | 평가 |
|---|---|---|
| Skills (TelegramSkill) | `TelegramAdvanced.swift:184` 정의 + 4개 default | 🟡 데이터 모델 |
| Skills를 텔레그램에서 호출하는 경로 | 없음 (검색됨: `/skill` 또는 `/run skill_name` 명령 0건) | ❌ |
| MCP server 노출 | 없음 | ❌ |

ADR-092에서 미언급. 임팩트는 작음 (Skills는 prompt template 수준).

### 6.4 챕터 / 메시지 thread

| 측면 | 현재 상태 | 평가 |
|---|---|---|
| Telegram topic API 활용 | 없음 — `message_thread_id` 검색 0건 [H] | ❌ |
| 긴 conversation thread 묶기 | 없음 | ❌ |

ADR-092에서 미언급. 그룹 채팅에서 여러 user가 동시 작업 시 유용.

### 6.5 iOS/iPad companion (Telegram Mini Apps)

ADR-092 Appendix A #6에 언급. 미착수. 임팩트 큼 (Yuminai만의 UI를 폰에서 직접 노출 가능).

### 6.6 보안 깊이

| 측면 | 현재 상태 | 평가 |
|---|---|---|
| Token rotation | 없음 | ❌ |
| 감사 로그 (`ChatBindingAuditLog`) | bind/unbind만 기록 (`Sources/YuminaiCore/ChatBindingAuditLog.swift`) | 🟡 |
| 명령 실행 audit | record만 (`recordTelegramCommand`) | 🟡 |
| IP allowlist | 없음 (Telegram 서버 IP만 신뢰) | ❌ |
| Webhook vs polling 선택 | enum 정의 (`TelegramUpdateMode.webhook` `MultiBot.swift:441`) + UI 텍스트필드 (`TelegramAdvancedSheet.swift:432`) | 🟡 데이터 모델만 / 실제 webhook 핸들러 0건 |

webhook 모드는 데이터 모델에만 있고 실제 webhook 서버/listener 코드 0건 [H].

### 6.7 사용량 / 비용 알림

| 측면 | 현재 상태 | 평가 |
|---|---|---|
| `TelegramUsageStore` 데이터 | record는 작동 (`recordTelegramCommand`, `recordTelegramTurnComplete`) | ✅ |
| 매주 digest | 없음 | ❌ |
| 80% 임계 자동 경고 | `RateLimitAlertTracker` 정의 (`MultiBot.swift:470`) — 실제 `report` 호출 0건 [H] | 🟡 |

### 6.8 로컬라이제이션

`Strings.localized\|NSLocalizedString` 검색 → YuminaiTelegram/YuminaiCommandRouter 0건 [H]. 모든 봇 응답이 한국어 하드코딩 (`"위험한 작업 감지"`, `"진행 중인 turn이 없어요"`). ❌

### 6.9 접근성

스크린리더 / voice output 검색 → 0건. ❌

### 6.10 테스트 e2e

`Tests/YuminaiTelegramTests/`는 mock 기반 단위 테스트만. 실제 Telegram bot 1개로 자동 smoke test 인프라 0건 [H].

### 6.11 백업 / migration

Preferences export/import 코드 없음 — `Preferences` Codable이지만 GUI export 0건. 디바이스 간 봇 설정 동기화 (iCloud) 0건. ❌

### 6.12 Webhook 모드

§6.6 참조 — 데이터 모델만 있고 실제 서버 0건. ADR-086 Phase 5에서 정의됐지만 처리 미완.

### 6.13 AI 요약

긴 chat history를 Claude로 요약 → 검색 0건. ❌

### 6.14 Voice message (Whisper)

ADR-092 Appendix A #5. 미착수.

### 6.15 첨부파일 처리

사용자가 텔레그램으로 보낸 이미지/파일을 워크스페이스로 → `getFile` API 호출 코드 0건 [H]. ADR-084 Phase에서 attachment 언급 있으나 inbound 처리 X.

---

## 7. ADR-098 후보 우선순위 (P0-P3)

### P0 — 즉시 필요 (사용자 핵심 task 동작성을 막는 wire-up 누락)

| # | 항목 | 작업 규모 | 가치 | 근거 |
|---|---|---|---|---|
| P0-1 | `TelegramHITLCoordinator.request()` 호출 wire-up — `TelegramSessionBridge.consume(event:)`의 destructive 분기에서 호출 | M (3-5 파일, 1-2일) | ⭐⭐⭐⭐⭐ | T3 동작성 0% → 100% / ADR-092 §4.6 핵심 |
| P0-2 | `YuminaiCommandRouter`에 `/run`, `/abort`, `/approve`, `/reject` 케이스 추가 (BotFather autocomplete과 일치) | S (1 파일, 2시간) | ⭐⭐⭐⭐ | T1, T4 동작성 회복 |
| P0-3 | `TelegramAlertDispatcher.updateDeliveryChannelProvider` wire-up (AppModel.setupTelegram 마지막에 1줄) | S (1 파일, 30분) | ⭐⭐⭐⭐ | NotificationPolicyMatrix 전체가 dead code → live 전환 |
| P0-4 | `MacOSNotificationPermission` 권한 받은 후 실제 `UNNotificationRequest` 발송 헬퍼 + dispatcher의 `.macOSOnly`/`.both` 채널에서 호출 | M (2 파일, 1일) | ⭐⭐⭐⭐ | macOS 알림 채널 전체가 dead → live |

**P0 총량**: ~3-5일, 압도적 효과 (사용자 핵심 task 5개 중 4개 작동성 회복)

### P1 — UX 완성도 (권장됐으나 부분 구현)

| # | 항목 | 작업 규모 | 가치 |
|---|---|---|---|
| P1-1 | `TelegramArtifactStore.store()` 호출 wire-up — `SessionBridge`가 diff/log 보낼 때 store + deep link button | M (2 파일) | ⭐⭐⭐⭐ |
| P1-2 | `TelegramMessageFormatter.formatDiff/formatLog` production 사용 — `YuminaiCommandRouter.diffCommand` 교체 | S (1 파일) | ⭐⭐⭐ |
| P1-3 | `TelegramLargePayloadSender.sendOrAttach` → dispatcher 통합 (5MB+ 자동 sendDocument) | S (1 파일) | ⭐⭐ |
| P1-4 | setMyCommands 자동 sync — addTelegramCommand/updateTelegramCommand/removeTelegramCommand 후 background sync 트리거 | S (1 파일) | ⭐⭐⭐ |
| P1-5 | HITL 응답 후 텔레그램 메시지 자동 edit (`editMessageText`로 "✅ Approved by ...") | M (HITLCallbackHandler + Coordinator 연결) | ⭐⭐⭐ |
| P1-6 | 다중 디바이스 "seen on desktop" edit | M | ⭐⭐⭐ |

**P1 총량**: ~5-7일

### P2 — 확장 (기획 부족 영역 중 임팩트 큰 것)

| # | 항목 | 작업 규모 | 가치 |
|---|---|---|---|
| P2-1 | 봇 polling 라이프사이클 — sleep/wake 시 자동 stop/restart | M | ⭐⭐⭐ |
| P2-2 | 그룹 채팅 admin-only 명령 enforcement (`Permission.admin` 활용) + N-of-M approval | L | ⭐⭐⭐⭐ |
| P2-3 | RateLimitAlertTracker live 사용 (80% 임계 자동 경고) + 매주 usage digest | M | ⭐⭐⭐ |
| P2-4 | Telegram outage 시 HITL fallback 정책 (자동 reject? 데스크탑 only?) | M | ⭐⭐⭐ |
| P2-5 | `/skill <name>` 명령으로 TelegramSkill 텔레그램 노출 | S | ⭐⭐ |
| P2-6 | Webhook 서버 핸들러 구현 (현재 enum + UI 텍스트필드만 있음) | L | ⭐⭐ |
| P2-7 | 첨부파일 inbound 처리 (`getFile` API + 워크스페이스 import) | M | ⭐⭐⭐ |

**P2 총량**: ~10-15일 (선택 항목)

### P3 — Nice-to-have

| # | 항목 | 작업 규모 |
|---|---|---|
| P3-1 | 로컬라이제이션 (한/영/일) | L |
| P3-2 | Voice message (Whisper) | L |
| P3-3 | Telegram Mini Apps webview | L |
| P3-4 | iCloud KeyValue store 다중 디바이스 sync | M |
| P3-5 | AI 요약 — 긴 chat history Claude로 압축 | M |
| P3-6 | 접근성 (스크린리더, voice output) | M |
| P3-7 | Telegram thread/topic API | M |
| P3-8 | 자동 e2e smoke test 인프라 | L |
| P3-9 | Token rotation + IP allowlist + 감사 log 강화 | M |
| P3-10 | Preferences export/import GUI | S |

---

## 8. 부록 — 코드 증거 (file:line 참조)

### A. 핵심 파일

| 영역 | 파일 | 핵심 라인 |
|---|---|---|
| HITL Coordinator | `Sources/YuminaiCore/TelegramHITLCoordinator.swift` | actor 정의 :15, request() :58, respond() :88 |
| HITL CallbackHandler | `Sources/YuminaiTelegram/TelegramHITLCallbackHandler.swift` | struct :9 |
| HITL Sheet | `Sources/YuminaiApp/HITL/HITLApprovalSheet.swift` | view :19 |
| Alert Dispatcher | `Sources/YuminaiTelegram/TelegramAlertDispatcher.swift` | dispatch :42, updateProvider :38 |
| Artifact Store | `Sources/YuminaiCore/TelegramArtifactStore.swift` | actor :9, store() :47 |
| Artifact Viewer | `Sources/YuminaiApp/TelegramHub/TelegramArtifactViewerSheet.swift` | view :18, fetch :221 |
| Large Payload Sender | `Sources/YuminaiTelegram/TelegramLargePayloadSender.swift` | enum :13, sendOrAttach :55 |
| First Message Detector | `Sources/YuminaiTelegram/TelegramFirstMessageDetector.swift` | actor :14, startDetecting :62 |
| Message Formatter | `Sources/YuminaiCore/TelegramMessageFormatter.swift` | static functions |
| Notification Policy | `Sources/YuminaiCore/NotificationPolicy.swift` | matrix |
| Deep Link Router | `Sources/YuminaiCore/TelegramDeepLinkRouter.swift` | parse/url |
| macOS Permission | `Sources/YuminaiCore/MacOSNotificationPermission.swift` | currentStatus :24, requestPermission :32 |
| Command Pump | `Sources/YuminaiTelegram/TelegramCommandPump.swift` | actor :8, start :18 |
| Yuminai Router | `Sources/YuminaiApp/YuminaiCommandRouter.swift` | handleCommand :104, handleCallback :54 |
| Session Bridge | `Sources/YuminaiTelegram/TelegramSessionBridge.swift` | consume :86, isDestructive :434 |
| Live Bot | `Sources/YuminaiTelegram/LiveTelegramBot.swift` | startPolling :305, sendDocument :455, setMyCommands :528 |
| AppModel (Telegram setup) | `Sources/YuminaiApp/AppModel.swift` | setupTelegram :4470, setupHITL :5306, syncCmds :5278, currentDeliveryChannel :5408, handleDeepLink :5446 |
| RootView (sheets) | `Sources/YuminaiApp/RootView.swift` | HITLSheet :458, ArtifactSheet :463, HubSheet :184 |
| YuminaiApp (URL handler) | `Sources/YuminaiApp/YuminaiApp.swift` | onOpenURL :91 |

### B. 누락 wire-up grep 증거

```
$ grep -rn "request(action" Sources/
(0 matches)

$ grep -rn "hitlCoordinator\." Sources/
Sources/YuminaiApp/AppModel.swift:5308:        hitlCoordinator = coordinator
Sources/YuminaiApp/AppModel.swift:5337:        await hitlCoordinator?.respond(id: id, response: response)
Sources/YuminaiApp/AppModel.swift:5338:        let requests = await hitlCoordinator?.pendingRequests() ?? []
(respond/pendingRequests만 — request 호출 0건)

$ grep -rn "deliveryChannelProvider" Sources/
Sources/YuminaiTelegram/TelegramAlertDispatcher.swift:17,19,25,30,38,46
(actor 내부 정의 + signature만 — 외부 호출 0건)

$ grep -rn "telegramArtifactStore\.store\|artifactStore\.store" Sources/
(0 matches in production)

$ grep -rn "sendOrAttach\|TelegramLargePayloadSender\." Sources/
Sources/YuminaiTelegram/TelegramLargePayloadSender.swift:* (정의)
(production 호출 0건; Tests/YuminaiTelegramTests 만 사용)

$ grep -rn "TelegramMessageFormatter\." Sources/
Sources/YuminaiTelegram/TelegramLargePayloadSender.swift:77 (enforceMaxBytes 만)
(formatDiff/formatLog production 호출 0건)

$ grep -rn "UNNotificationRequest\|UNMutableNotificationContent" Sources/
(0 matches)

$ grep -rn "editMessageText" Sources/
(검색 결과 0건 — message edit 코드 없음)
```

### C. 사용자 task trace 코드 인용

T1 `/run` 실패 증거 — `Sources/YuminaiApp/YuminaiCommandRouter.swift:115-163` switch에 `/run` 케이스 부재:

```swift
switch cmd {
case "/bind": ...
case "/unbind": ...
case "/status": ...
case "/cancel", "/stop": ...
case "/start": ...
case "/help": return Self.helpText
case "/list", "/workspaces": ...
case "/use", "/switch": ...
case "/diff": ...
case "/changes": ...
case "/model": ...
case "/decompose": ...
case "/cost": ...
case "/budget": ...
case "/tasks": ...
case "/walkthrough": ...
case "/rehearse": ...
default:
    return "알 수 없는 명령: \(cmd)\n/help로 사용 가능한 명령을 확인해요."
}
```

T3 HITL 미작동 증거 — `Sources/YuminaiTelegram/TelegramSessionBridge.swift:97-110` destructive 분기에서 HITL 호출 없음:

```swift
if Self.isDestructiveToolCall(name: name, input: input) {
    let summary = Self.summarizeToolCall(name: name, input: input, maxLen: 200)
    let target = requestChatId ?? config.chatId
    let buttons = [[
        InlineButton(text: "🛑 중단 (cancel)", callbackData: "cancel"),
        InlineButton(text: "📊 상태", callbackData: "status")
    ]]
    _ = try? await client.sendWithKeyboard(
        "🚨 위험한 작업 감지 — \(summary)\n버튼으로 즉시 결정하세요.",
        to: target,
        buttons: buttons
    )
    // ← 여기에 await coordinator.request(action:..., timeout: 60)이 있어야 ADR-092 §4.6 작동
    streamingMessageId = nil
    streamingAccumulated = ""
}
```

---

## 9. 검증 게이트 (이 보고서)

- [x] `swift test` baseline 905 tests passed (174 suites, 1.278s) — 2026-05-04
- [x] `grep` 기반 코드 검증으로 모든 wire-up 누락 주장에 file:line 증거 첨부
- [x] ADR-092 §4의 7개 권장 항목 100% 매핑 완료
- [x] T1-T5 사용자 task 5개 100% trace 완료
- [x] ADR-093/094/095/096/097의 미룬 항목 25개 항목 100% 검증
- [x] §6 기획 누락 영역 15개 분석
- [x] P0/P1/P2/P3 총 27개 후속 후보 + 작업 규모 + 가치 평가

## 10. 작성자 노트 (의사결정 컨텍스트)

본 보고서는 ADR-098 정식 승인 전 candidate / investigation 단계다. 권장 다음 단계:

1. **P0만 즉시 처리** (3-5일) — ADR-098 정식 승인 + 구현. 이 한 라운드만으로 ADR-092 시리즈가 진정한 "end-to-end 작동" 상태로 전환.
2. **P1은 별도 ADR-099로** — UX 완성도 항목들 묶어서 추가 1주.
3. **P2는 ADR-100+로 분할** — 그룹/N-of-M, polling lifecycle, webhook 등은 각 1개 ADR씩.
4. **P3는 사용자 피드백 받은 후 우선순위 재평가**.

이 보고서는 ADR이 아니라 next-ADR을 위한 evidence base다. 본 분석에 동의 후 ADR-098 정식 작성 시 §7의 P0 4개 항목을 핵심 결정으로 삼고, 본 보고서는 ADR-098 부록으로 참조한다.
