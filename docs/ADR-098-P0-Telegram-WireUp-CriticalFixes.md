# ADR-098 — Telegram End-to-End Wire-Up P0 Critical Fixes

- **날짜**: 2026-05-04 (Monday)
- **상태**: Accepted / Implemented
- **선행 ADR**: ADR-092 ~ ADR-097 (Telegram 통합 시리즈)
- **분석 근거**: `docs/ADR-098-Candidate-Telegram-Gap-Analysis.md`
- **baseline**: 905 tests → 933 tests (+28)

---

## 1. 배경

ADR-092 ~ ADR-097이 Telegram 통합 UI shell과 백엔드 actor를 완성했으나, **4개의 핵심 wire-up이 누락**되어 production code path에서 실제로 호출되지 않는 "고아 actor" 상태였다. 분석 보고서에 따르면 사용자 핵심 task 5개 중 1개(20%)만 ADR-092 권장 형식대로 작동하는 상태.

## 2. 결정 (P0 4건 즉시 처리)

### P0-1: HITLCoordinator.request() wire-up

**문제**: `TelegramHITLCoordinator.request()`를 호출하는 production 코드가 0건 (`grep -rn "request(action" Sources/` → 0 matches).

**해결**:

1. **`HITLActionGuard.swift`** (신규, `Sources/YuminaiCore/`) — 위험 패턴 감지 pure struct.
   - 19개 정규식 패턴 (force-push, rm-recursive, drop-table 등)
   - `shouldRequestApproval(command:) -> Bool`
   - `category(for:) -> String?`
   - `TelegramSessionBridge.isDestructiveToolCall`과 독립적 — `/run` 경로에서도 사용 가능

2. **`TelegramSessionBridge`** 수정 — `setHITLCoordinator(_:timeoutSeconds:)` 주입 메서드 추가. `consume(event: .toolCall)` 의 destructive 분기에서:
   - coordinator가 주입돼 있으면 → `coordinator.request(action:workspace:diffPreview:timeout:)` suspend
   - 응답 `.approved` → 계속, `.rejected/.timeout/.cancelled` → 사용자에게 알림
   - coordinator 미주입 시 기존 "알림 + cancel/status 버튼" 동작 유지

3. **`AppModel.setupTelegramHITLCoordinator()`** 수정 — coordinator 생성 후 `sessionBridge?.setHITLCoordinator(coordinator, timeoutSeconds:)` 주입 Task 추가.

4. **macOS 알림 연동** — HITL request 스트림 Task에서 `MacOSNotificationSender.sendHITL(requestId:action:workspaceName:)` 동시 호출.

**변경 파일**:
- `Sources/YuminaiCore/HITLActionGuard.swift` (신규)
- `Sources/YuminaiTelegram/TelegramSessionBridge.swift` (+`setHITLCoordinator` + destructive 분기 수정)
- `Sources/YuminaiApp/AppModel.swift` (setupTelegramHITLCoordinator 수정)

### P0-2: YuminaiCommandRouter `/run`, `/abort`, `/approve`, `/reject` cases

**문제**: BotFather에 등록됐지만 router switch에 case 없어 "알 수 없는 명령" 응답 (`YuminaiCommandRouter.swift:115-163`).

**해결**: `YuminaiCommandRouter.handleCommand` switch에 4개 case 추가 + 구현 메서드:

- `/run <cmd>` — `HITLActionGuard` 통과 후 `model.runCommand(cmd)` 실행. 위험 패턴이면 HITL coordinator를 통해 승인 요청 (coordinator 없으면 차단 경고).
- `/abort` — `/cancel`과 동일한 `cancelCommand()` 호출.
- `/approve [uuid]` — `model.respondToHITL(id:response: .approved(by:))`. uuid 생략 시 가장 오래된 pending 사용.
- `/reject [uuid]` — `model.respondToHITL(id:response: .rejected(by:))`. 동일 패턴.

`/help` 텍스트에 4개 명령 + HITL 섹션 추가.

**변경 파일**:
- `Sources/YuminaiApp/YuminaiCommandRouter.swift`

### P0-3: AlertDispatcher deliveryChannelProvider wire-up

**문제**: `TelegramAlertDispatcher`가 `deliveryChannelProvider: nil`로 생성되어 (`AppModel.swift:4477-4481`) `NotificationPolicyMatrix` / quiet hours / deviceState 정책이 한 번도 적용되지 않음.

**해결**: `AppModel.setupTelegram()` 마지막 (`setupTelegramHITLCoordinator()` 직후)에 추가:

```swift
await dispatcher.updateDeliveryChannelProvider { [weak self] kind in
    MainActor.assumeIsolated {
        self?.currentDeliveryChannel(for: kind) ?? .telegramOnly
    }
}
```

`currentDeliveryChannel(for:)`은 ADR-095에서 이미 완성된 메서드 — policy matrix + quiet hours + deviceState 조합을 반환.

**변경 파일**:
- `Sources/YuminaiApp/AppModel.swift` (setupTelegram 내부 1블록 추가)

### P0-4: macOS UserNotification 실제 발송

**문제**: `MacOSNotificationPermission.requestPermission()`만 있고 `UNNotificationRequest`를 add하는 코드가 0건.

**해결**:

1. **`MacOSNotificationSender.swift`** (신규, `Sources/YuminaiCore/`) — 실제 발송 헬퍼.
   - `send(title:body:identifier:categoryIdentifier:userInfo:delay:) async throws`
   - `sendHITL(requestId:action:workspaceName:) async throws` — HITL actionable (Approve/Reject 버튼)
   - `registerCategories()` — HITL category `yuminai.hitl.approval` 등록
   - `dismiss(identifier:) async` / `dismissHITL(requestId:) async`
   - 권한 없으면 throw 없이 skip (테스트 환경 안전)

2. **`TelegramAlertDispatcher.dispatch()`** 수정 — `.macOSOnly` / `.both` 케이스에서 `MacOSNotificationSender.send(...)` 직접 호출. `notificationTitle(for:)` private helper 추가.

3. **`AppModel.bootstrap()`** 에 `MacOSNotificationSender.registerCategories()` 추가.

4. **`AppModel.setupTelegramHITLCoordinator()`** HITL 스트림 Task에 `MacOSNotificationSender.sendHITL(...)` 추가.

**변경 파일**:
- `Sources/YuminaiCore/MacOSNotificationSender.swift` (신규)
- `Sources/YuminaiTelegram/TelegramAlertDispatcher.swift` (dispatch 수정 + notificationTitle helper)
- `Sources/YuminaiApp/AppModel.swift` (bootstrap + setupTelegramHITLCoordinator)

---

## 3. 변경 파일 매트릭스

| 파일 | 변경 종류 | P0 항목 |
|------|----------|--------|
| `Sources/YuminaiCore/HITLActionGuard.swift` | 신규 | P0-1 |
| `Sources/YuminaiCore/MacOSNotificationSender.swift` | 신규 | P0-4 |
| `Sources/YuminaiTelegram/TelegramSessionBridge.swift` | 수정 | P0-1 |
| `Sources/YuminaiTelegram/TelegramAlertDispatcher.swift` | 수정 | P0-4 |
| `Sources/YuminaiApp/YuminaiCommandRouter.swift` | 수정 | P0-2 |
| `Sources/YuminaiApp/AppModel.swift` | 수정 | P0-1, P0-3, P0-4 |
| `Tests/YuminaiCoreTests/HITLActionGuardTests.swift` | 신규 | P0-1 |
| `Tests/YuminaiCoreTests/MacOSNotificationSenderTests.swift` | 신규 | P0-4 |

---

## 4. 검증

### 빌드
```
swift build → Build complete! (0 errors)
```

### 테스트
```
swift test → 933 tests passed in 176 suites (baseline: 905, +28)
```

### Wire-up 호출 site 확인 (grep 증거)

```bash
# P0-1 HITL coordinator.request — sessionBridge에서 호출
grep -n "coordinator.request" Sources/YuminaiTelegram/TelegramSessionBridge.swift
# → line: await coordinator.request(action: summary, workspace: workspaceName, ...)

# P0-1 setHITLCoordinator — AppModel에서 주입
grep -n "setHITLCoordinator" Sources/YuminaiApp/AppModel.swift
# → setupTelegramHITLCoordinator: await self?.sessionBridge?.setHITLCoordinator(coordinator, ...)

# P0-2 /run /abort /approve /reject
grep -n '"/run"\|"/abort"\|"/approve"\|"/reject"' Sources/YuminaiApp/YuminaiCommandRouter.swift
# → 4개 case 존재

# P0-3 updateDeliveryChannelProvider
grep -n "updateDeliveryChannelProvider" Sources/YuminaiApp/AppModel.swift
# → await dispatcher.updateDeliveryChannelProvider { [weak self] kind in ...

# P0-4 MacOSNotificationSender.send
grep -n "MacOSNotificationSender" Sources/
# → TelegramAlertDispatcher.swift: try? await MacOSNotificationSender.send(...)
# → AppModel.swift: MacOSNotificationSender.registerCategories() + sendHITL(...)
```

### 사용자 시나리오 작동성 매트릭스 (T1-T5)

| Task | before | after | 변경 내용 |
|------|--------|-------|----------|
| T1 `/run swift test` | ❌ router case 없음 | ✅ runCommand + HITL guard | P0-2 |
| T2 `/diff` | 🟡 deep link 없음 | 🟡 (변경 없음 — P1 범위) | - |
| T3 HITL 승인 | ❌ request() 0건 | ✅ sessionBridge → coordinator.request() suspend | P0-1 |
| T4 `/abort` | ❌ router case 없음 | ✅ cancelCommand()로 라우팅 | P0-2 |
| T5 `/status` | ✅ | ✅ (변경 없음) | - |

**5개 중 4개(80%)가 ADR-092 권장 형식대로 작동** (baseline: 1/5 = 20%).

---

## 5. 후속 P1/P2/P3 항목

### P1 — UX 완성도 (ADR-099 예정)
- P1-1: `TelegramArtifactStore.store()` 호출 wire-up (diff deep link button)
- P1-2: `TelegramMessageFormatter.formatDiff/formatLog` production 사용
- P1-3: `TelegramLargePayloadSender.sendOrAttach` → dispatcher 통합
- P1-4: setMyCommands 자동 sync (addTelegramCommand 후 background 트리거)
- P1-5: HITL 응답 후 Telegram 메시지 자동 edit (`editMessageText`)
- P1-6: 다중 디바이스 "seen on desktop" edit

### P2 — 확장 (ADR-100+ 예정)
- P2-1: 봇 polling 라이프사이클 sleep/wake 자동 stop/restart
- P2-2: 그룹 채팅 admin-only 명령 enforcement + N-of-M approval
- P2-3: RateLimitAlertTracker live 사용 + 매주 usage digest
- P2-4: Telegram outage 시 HITL fallback 정책
- P2-5: `/skill <name>` 명령으로 TelegramSkill 노출
- P2-6: Webhook 서버 핸들러 구현

### P3 — Nice-to-have
- 로컬라이제이션, Voice message (Whisper), Telegram Mini Apps, iCloud sync, AI 요약, 접근성 등

---

## 6. 설계 원칙 준수

- **Swift 6.2 strict concurrency**: `MainActor.assumeIsolated` 사용으로 actor isolation 경계 명확히 처리
- **불변성**: `HITLActionGuard`는 순수 static struct — 부수효과 없음
- **소규모 파일**: 신규 파일 2개 모두 200줄 이내
- **에러 처리**: `MacOSNotificationSender.send`는 권한 없으면 throw 안 하고 skip — caller에게 부담 없음
- **backward compatibility**: coordinator 미주입 시 기존 "알림 + cancel/status 버튼" 동작 유지
