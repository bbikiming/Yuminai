# ADR-093 — Telegram Active Dock + Chat Context Cards (Phase 2)

- **날짜**: 2026-05-04 (Monday)
- **상태**: Implemented
- **선행 ADR**: ADR-092 (Telegram Hub Phase 1 — 4-tab shell + Onboarding Wizard)
- **연관 ADR**: ADR-086 (Telegram Reliability), ADR-085 (안정성 인프라)
- **후속 ADR 후보**: ADR-094 (CommandPaletteEditor + HITL + BotFather sync), ADR-095 (Diff/Log format + deep link)

---

## 1. 핵심 결정

### 결정 1: BotStatusDock — TelegramHealthPill 대체 상시 위젯

`TelegramHealthPill`(ADR-086)은 상태 표시만 했다. Phase 2에서는 queue depth + 마지막 활동 + 다중 봇 배지까지 포함하는 `BotStatusDock`으로 교체한다. Pill은 deprecated 마커만 추가 (기존 사용 위치는 SidebarView에서만 쓰이므로 즉시 교체 가능).

**배치**: SidebarView 하단 (`TelegramHealthPill` 위치 그대로).

**단일 클릭**: popover — 각 봇 health + 최근 에러 3건.

**더블 클릭**: `appModel.showTelegramHubSheet = true` (Hub Activity 탭).

### 결정 2: ChatContextCard — Bindings 탭 카드 그리드

기존 `TelegramHubBindingsTab`은 `TelegramBotBindingSection`을 단순 wrap했다. Phase 2에서는 `LazyVGrid(2-column)` of `ChatContextCard`로 교체. binding이 없으면 기존 `AnimatedEmptyState`.

`ChatContextCard`는 hover 시에만 [Edit Binding] / [Disable] 액션 버튼 노출 (`.opacity` transition).

### 결정 3: ActivityFeedView — Activity 탭 실시간 피드

기존 `TelegramHubActivityTab`의 placeholder("Phase 2/3 예정")를 `ActivityFeedView`로 교체. 통합 통계 카드 + `TelegramErrorEntry` 기반 이벤트 피드 + 빠른 액션.

`ActivityEvent` enum은 `TelegramErrorEntry`를 래핑하는 뷰 레이어 타입. 퍼시스턴스 없음 — 매번 `appModel.telegramRecentErrors(limit: 50)`에서 pull.

### 결정 4: getMe API 호출 — Onboarding Step 1 강화

`TelegramTokenValidator+Network.swift`를 `YuminaiCore`에 추가. `TelegramBotInfo` 구조체 + `TelegramTokenValidator.fetchBotInfo(token:)` static 메서드. `OnboardingStep1Token.swift`에서 형식 검증 통과 후 "검증" 버튼 클릭 시 네트워크 호출.

### 결정 5: AppModel queue depth 폴링

`telegramQueueDepth: Int = 0` published property + 5초 interval Task (`setupTelegramQueueDepthPolling()`). 기존 health 구독 패턴(`snapshots()` AsyncStream) 과 동일 방식으로 병렬 Task 실행.

---

## 2. 산출물

### 신규 파일

| 파일 | 모듈 | 역할 |
|---|---|---|
| `Sources/YuminaiCore/TelegramTokenValidator+Network.swift` | YuminaiCore | getMe API + TelegramBotInfo |
| `Sources/YuminaiApp/TelegramHub/BotStatusDock.swift` | YuminaiApp | 상시 표시 Dock 위젯 |
| `Sources/YuminaiApp/TelegramHub/ChatContextCard.swift` | YuminaiApp | Bindings 탭 카드 |
| `Sources/YuminaiApp/TelegramHub/ActivityFeedView.swift` | YuminaiApp | Activity 탭 피드 |
| `Tests/YuminaiCoreTests/TelegramBotInfoTests.swift` | 테스트 | TelegramBotInfo + ActivityEvent |

### 수정 파일

| 파일 | 변경 내용 |
|---|---|
| `Sources/YuminaiApp/AppModel.swift` | `telegramQueueDepth` + `telegramOfflineQueueDepth()` + `telegramRecentChatActivity()` + polling Task |
| `Sources/YuminaiApp/TelegramHub/Onboarding/OnboardingStep1Token.swift` | 검증 버튼 + getMe 호출 + spinner |
| `Sources/YuminaiApp/TelegramHub/TelegramHubBindingsTab.swift` | LazyVGrid + ChatContextCard |
| `Sources/YuminaiApp/TelegramHub/TelegramHubActivityTab.swift` | ActivityFeedView 교체 |
| `Sources/YuminaiUI/SidebarView.swift` | TelegramHealthPill → BotStatusDock |

---

## 3. 데이터 모델 변경

### 신규: TelegramBotInfo (YuminaiCore)

```swift
public struct TelegramBotInfo: Sendable, Equatable {
    public let id: Int64
    public let username: String
    public let firstName: String
    public let canJoinGroups: Bool
}
```

### 신규: ActivityEvent (BotStatusDock/ActivityFeedView 내부 — 퍼시스턴스 없음)

`TelegramErrorEntry`를 뷰 레이어에서 `ActivityEvent`로 래핑. 별도 저장소 불필요.

### AppModel 추가 프로퍼티

```swift
public var telegramQueueDepth: Int = 0
```

---

## 4. 검증 게이트

- [x] `swift build` → Build complete! (0 errors)
- [x] `swift test` → 775+ tests passed (회귀 0)
- [x] 신규 TelegramBotInfo 단위 테스트 추가
- [x] BotStatusDock: 단일 클릭 popover / 더블 클릭 Hub 열기
- [x] ChatContextCard: hover 시 버튼 노출 / Disable → activeWorkspaceId nil
- [x] ActivityFeedView: placeholder 제거 확인

---

## 5. Phase 3으로 미룬 항목

| 항목 | 이유 |
|---|---|
| `/start` 자동 감지 (Bot Step 2) | long polling 인프라 신규 필요 (AsyncStream push → wizard) |
| BotFather `setMyCommands` sync | CommandPaletteEditor가 Phase 3 전체 주제 |
| HITL 승인 흐름 (inline button callback) | `TelegramHITLCoordinator` actor 신규 설계 필요 |
| `yuminai://` deep link URL scheme | Info.plist + URLScheme handler 신규 |
| URLSession mock 기반 getMe 네트워크 단위 테스트 | 간단한 protocol injection 패턴 — Phase 3 TDD 시 추가 |
| 다중 디바이스 "seen on desktop" edit | TelegramAlertDispatcher 확장 필요 |

---

## 6. 설계 원칙 (Phase 1 연속)

- PolishedComponents 적극 사용 (`CardSection`, `AnimatedEmptyState`, `SectionHeaderRow`)
- Theme 토큰 일관 사용
- Spring 애니메이션 (`response: 0.4, dampingFraction: 0.85`)
- Swift 6.2 strict concurrency (`@MainActor`, `@Observable`, `@Bindable`)
- 파일 200-400줄 (BotStatusDock/ChatContextCard는 200줄 이하 목표)
- 불변성 원칙 — AppModel state 변경은 새 값 assign, mutation 없음
