# ADR-153: Telegram 연계 안정성 및 보안 일괄 fix (P0 + P1)

- **Status**: Accepted
- **Date**: 2026-05-10
- **Authors**: Executor (Claude claude-sonnet-4-6)
- **Supersedes**: ADR-098, ADR-099 (부분)

---

## 배경

ADR-098/099에서 구현한 Telegram 연계 레이어에 운영 중 발견된 안정성 버그(P0) 및
효율성/정확성 이슈(P1)를 일괄 수정한다.

---

## 결정 사항

### P0: 크리티컬 안정성 수정

#### P0-1: `MainActor.assumeIsolated` 제거
**문제**: `TelegramAlertDispatcher.deliveryChannelProvider`가 sync 클로저로 `MainActor.assumeIsolated`를 사용 → Swift 5.10+ 런타임에서 MainActor가 아닌 스레드에서 호출 시 `preconditionFailure` crash.

**수정**:
- `TelegramAlertDispatcher.deliveryChannelProvider`를 `async` 클로저로 변경
- `dispatch()`가 `await provider(kind)` 호출
- `ClaudeAdapter.spawn()` 및 `ChildClaudeProcess.runOnce()` 시그니처에 `userProfilePrompt: String?` 추가 (기본값 `nil`)
- `AppModel.userProfilePrompt` computed property 추가 — `@MainActor`에서 추출 후 async 경계 전달

**관련 파일**:
- `Sources/YuminaiTelegram/TelegramAlertDispatcher.swift`
- `Sources/YuminaiCore/ClaudeAdapter.swift`
- `Sources/YuminaiCore/ChildClaudeProcess.swift`
- `Sources/YuminaiClaudeAdapter/LiveClaudeAdapter.swift`
- `Sources/YuminaiClaudeAdapter/LiveCodexAdapter.swift`
- `Sources/YuminaiClaudeAdapter/LiveChildClaudeProcess.swift`
- `Sources/YuminaiApp/AppModel.swift`
- `Sources/YuminaiApp/YuminaiApp.swift`

#### P0-2: Offline queue 자동 enqueue + healthy 전환 시 flush
**문제**: `LiveTelegramBot.send()` 실패 시 offline queue에 enqueue되지 않아 메시지 유실 발생.

**수정**:
- `LiveTelegramBot.send()` 내 transient error 발생 시 `offlineQueue.enqueue()` 자동 호출
- auth/forbidden(401/403/404/400) 오류는 throw (영구 오류 — retry 불필요)
- `activateTelegramIfReady()`의 `healthMonitor.snapshots()` 구독 루프에 healthy 전환 감지 → `flushOfflineQueueIfPossible()` 호출

**관련 파일**:
- `Sources/YuminaiTelegram/LiveTelegramBot.swift`
- `Sources/YuminaiApp/AppModel+Telegram.swift`

#### P0-3: Polling sleep/wake lifecycle
**문제**: macOS sleep/wake 시 Telegram long-polling이 자동으로 중단/재개되지 않음 → wake 후 polling 멈춤 또는 중복 polling.

**수정**:
- `AppModel+Notification.swift` sleep/wake 옵저버에 `pauseTelegramPollingForSleep()` / `resumeTelegramPollingAfterWake()` 추가
- wake 시 `flushOfflineQueueIfPossible()` 호출 (sleep 중 쌓인 offline queue 재전송)

**관련 파일**:
- `Sources/YuminaiApp/AppModel+Notification.swift`

---

### P1: 효율성 및 정확성 개선

#### P1-1: TelegramResponseMode.promptInstruction 시스템 프롬프트 주입
**문제**: 외부 turn(Telegram)에서 응답 모드(`TelegramResponseMode`) 지시문이 실제 spawn에 전달되지 않음.

**수정**:
- `AppModel+Telegram.swift`에 `telegramResponseModeInstruction() -> String?` 메서드 추가
- `externalTurnUserProfilePrompt: String?` computed property — userProfile + responseMode 합산

#### P1-2: USER_PROFILE.md 3중 주입 방지
**문제**: AutoRun이 harness rules + userProfile을 동시에 로드해 USER_PROFILE.md가 3중 주입됨.

**수정**:
- `HarnessRulesLoader.loadAll()` `excludeFiles: [String] = []` 파라미터 추가
- AutoRun이 `excludeFiles: ["USER_PROFILE"]`로 호출 → 2중 주입 방지

**관련 파일**:
- `Sources/YuminaiCore/HarnessRulesLoader.swift`
- `Sources/YuminaiApp/AppModel+AutoRun.swift`

#### P1-3: CommandPolicy tool_use 통합
**문제**: `TelegramSessionBridge`가 tool_use 이벤트에서 `CommandPolicyMatrix` 검사를 수행하지 않음.

**수정**:
- `TelegramSessionBridge`에 `commandPolicyMatrix: CommandPolicyMatrix?` 필드 + `setCommandPolicyMatrix()` 추가
- `consume(event:)` 내 `.toolCall` 처리 시 CommandPolicy 검사 우선 수행
- `deny` 시 🚫 메시지 발송 + `onHITLCancelRequired` 콜백 호출
- `makeSessionBridge()` 내 `await bridge.setCommandPolicyMatrix(preferences.commandPolicy)` 주입

**관련 파일**:
- `Sources/YuminaiTelegram/TelegramSessionBridge.swift`
- `Sources/YuminaiApp/AppModel+Telegram.swift`

#### P1-4: Bridge isDestructiveToolCall → HITLActionGuard 단일화
**문제**: `TelegramSessionBridge.isDestructiveToolCall()`이 자체 키워드 목록을 유지해 `HITLActionGuard`와 이중 관리.

**수정**:
- `isDestructiveToolCall()` 내부를 `HITLActionGuard.shouldRequestApproval(command:)`로 위임
- `extractCommand(name:input:)` static helper 추출 (P1-3에서도 재사용)

#### P1-5: Codex prefix 이중 래핑 제거
**문제**: `LiveChildClaudeProcess`가 `appendix`를 `"[프로젝트 컨텍스트]\n\(appendix)"`로 래핑 → `systemPromptAppendix()`가 이미 컨텍스트 헤더를 포함하면 이중 래핑.

**수정**:
- `prefixParts.append("[프로젝트 컨텍스트]\n\(appendix)")` → `prefixParts.append(appendix)`

**관련 파일**:
- `Sources/YuminaiClaudeAdapter/LiveChildClaudeProcess.swift`

#### P1-6: Handoff binding 매칭 일관성
**문제**: `handoffActiveSessionToTelegram()`의 binding 조회 로직이 `telegramBoundWorkspaceId`를 고려하지 않음.

**수정**:
- `resolveHandoffBinding() -> BotChatBinding?` helper 추가 (우선순위: activeWorkspaceId → boundWorkspaceId → 첫 번째)
- `handoffActiveSessionToTelegram()`이 이 helper를 사용하도록 리팩토링

**관련 파일**:
- `Sources/YuminaiApp/AppModel+Telegram.swift`

#### P1-7: HITL 채널 분기 — NotificationPolicyMatrix
**문제**: HITL 승인 요청이 항상 Telegram으로 발송되어 `NotificationPolicyMatrix`의 채널 설정을 무시.

**수정**:
- `setupTelegramHITLCoordinator()` 내 Telegram inline button 발송 전
  `currentDeliveryChannel(for: .hitlApprovalRequest)` 검사
- `.telegramOnly` / `.both` 일 때만 Telegram 발송

**관련 파일**:
- `Sources/YuminaiApp/AppModel+HITL.swift`

#### P1-8: AutoRun cache-friendly — harness rules 시스템 프롬프트 주입
**문제**: AutoRun이 harness rules를 turn-1 user prompt에 prepend → 매 turn 시스템 프롬프트가 달라져 Anthropic prompt cache 미적중.

**수정**:
- `AppModel.autoRunSystemPromptExtra: String?` 프로퍼티 추가
- `AppModel.userProfilePrompt`에 `autoRunSystemPromptExtra` 합산
- AutoRun 시작 시 harness rules를 `autoRunSystemPromptExtra`에 설정 + session respawn
- turn-1 user prompt prepend 제거
- AutoRun 종료 시 `autoRunSystemPromptExtra = nil` 클리어

**관련 파일**:
- `Sources/YuminaiApp/AppModel.swift`
- `Sources/YuminaiApp/AppModel+AutoRun.swift`

---

## 영향 범위

| 모듈 | 변경 파일 수 | 영향 |
|------|------------|------|
| YuminaiCore | 2 | HarnessRulesLoader, ClaudeAdapter 프로토콜 |
| YuminaiClaudeAdapter | 4 | Live/Mock/Codex adapter, ChildClaudeProcess |
| YuminaiTelegram | 2 | LiveTelegramBot, TelegramSessionBridge, TelegramAlertDispatcher |
| YuminaiApp | 5 | AppModel*, YuminaiApp |

## 테스트

새 회귀 테스트: 32개 추가 (총 1495 → 1527)

- `Tests/YuminaiCoreTests/ADR153RegressionTests.swift` — P1-2/P1-3/P1-4/P1-5/P1-6/P1-7 core 검증
- `Tests/YuminaiTelegramTests/ADR153BridgeRegressionTests.swift` — P1-3/P1-4 bridge-level 검증

모든 1527개 테스트 통과 확인.

## 대안 검토

- P0-1: `nonisolated(unsafe)` 사용 → Swift strict concurrency 위반으로 기각
- P1-8: `additionalSystemPrompt` 파라미터 추가 → 기존 spawn 시그니처가 이미 `userProfilePrompt`로 충분히 확장 가능해 별도 파라미터 불필요로 판단
