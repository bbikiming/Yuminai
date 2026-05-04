# ADR-095: Telegram Diff/Log Preview + Deep Link + Multi-device + /start Auto-detect + Quiet Hours

**Status:** Accepted  
**Date:** 2026-05-04  
**Author:** Yuminai Engineering  
**Supersedes:** ADR-094 (Phase 3 — CommandPalette + HITL + Inline Callback)

---

## 핵심 결정

Phase 4 (ADR-092 로드맵 최종 단계)는 5가지 subsystem을 도입한다:

1. **TelegramMessageFormatter** — Diff/Log 메시지를 4096자 제한 안에서 preview + deep-link 형식으로 포맷
2. **TelegramDeepLinkRouter** — `yuminai://` URL scheme 파싱/생성 (diff / log / workspace / chat / HITL)
3. **NotificationPolicyMatrix** — 다중 디바이스 상태 × 알림 종류 → 전달 채널 결정 테이블
4. **TelegramFirstMessageDetector** — 토큰 입력 즉시 `/start` 메시지를 polling하여 허용 목록 자동 채우기
5. **Quiet Hours** — AppPreferences 기반 시간대 알림 격하 (22:00~08:00 기본)

---

## 컨텍스트

ADR-092 §4.7 (Diff/로그 전송 형식), §4.8 (다중 디바이스 시나리오)에서 요구된 기능이다.  
Phase 1 (Hub + Wizard, 1e71088), Phase 2 (Dock + ContextCard + ActivityFeed, 18a1077), Phase 3 (CommandPalette + HITL, 620d387) 위에 구축된다.  
820개 회귀 테스트를 유지하며 40+ 신규 테스트를 추가한다.

---

## 산출물

### 신규 파일 (9개)

| 파일 | 모듈 | 역할 |
|------|------|------|
| `Sources/YuminaiCore/TelegramMessageFormatter.swift` | YuminaiCore | Diff/Log 포맷 + 4096자 truncate |
| `Sources/YuminaiCore/TelegramDeepLinkRouter.swift` | YuminaiCore | `yuminai://` URL scheme |
| `Sources/YuminaiCore/NotificationPolicy.swift` | YuminaiCore | NotificationPolicyMatrix + DeviceState + DeliveryChannel |
| `Sources/YuminaiTelegram/TelegramFirstMessageDetector.swift` | YuminaiTelegram | `/start` long-polling actor |
| `Tests/YuminaiCoreTests/TelegramMessageFormatterTests.swift` | YuminaiCoreTests | 포맷터 유닛 테스트 (15+) |
| `Tests/YuminaiCoreTests/TelegramDeepLinkRouterTests.swift` | YuminaiCoreTests | Deep link 유닛 테스트 (12+) |
| `Tests/YuminaiCoreTests/NotificationPolicyMatrixTests.swift` | YuminaiCoreTests | 정책 매트릭스 테스트 (10+) |
| `Tests/YuminaiTelegramTests/TelegramFirstMessageDetectorTests.swift` | YuminaiTelegramTests | 감지기 테스트 (5+) |
| `docs/ADR-095-Telegram-DiffPreview-DeepLink-MultiDevice.md` | — | 이 문서 |

### 수정 파일 (5개)

| 파일 | 변경 내용 |
|------|---------|
| `Sources/YuminaiCore/AppPreferences.swift` | `notificationPolicy`, `quietHoursStart/End`, `hitlTimeoutSeconds`, `diffPreviewLineLimit` 추가 |
| `Sources/YuminaiApp/AppModel.swift` | `deviceState`, `currentDeliveryChannel(for:)`, idle timer, quiet hours 적용 |
| `Sources/YuminaiTelegram/TelegramAlertDispatcher.swift` | `NotificationPolicyMatrix` 기반 채널 결정 후 dispatch |
| `Sources/YuminaiApp/TelegramHub/Onboarding/OnboardingStep2Whitelist.swift` | `/start` 자동 감지 UI — 감지된 user 클릭으로 허용 목록 추가 |
| `Sources/YuminaiApp/YuminaiApp.swift` | `.onOpenURL` 핸들러 — `TelegramDeepLink.parse` → sheet 라우팅 |

---

## 설계 결정

### TelegramMessageFormatter

- **첫 N줄 OR M바이트 중 작은 쪽**: `previewLineLimit` (기본 30줄) + `maxBytes` (기본 2000자)
- **Fenced code block** ` ```diff ` — Telegram monospace 렌더링 보장
- **"... (N more lines)" indicator** — 잘린 경우 명시
- **Deep link 버튼 텍스트** — `[📂 View Full in Yuminai](yuminai://diff/{uuid})`
- **enforceMaxBytes** — Telegram 4096자 한도의 보수적 마진 4000자
- **shouldSendAsDocument** — 5MB 이상이면 caller가 `sendDocument` API로 전환해야 함

### TelegramDeepLinkRouter

- **Scheme**: `yuminai://`
- **지원 경로**: `diff/{uuid}`, `log/{uuid}`, `workspace/{uuid}`, `chat/{int64}`, `approve/{uuid}`, `reject/{uuid}`
- **양방향**: `.url` (생성) + `.parse(_:)` (파싱)
- **macOS Info.plist 등록**: SwiftPM executable 특성상 `.app` 번들 생성 전까지 시스템 등록 불가. dispatch 로직은 완비, 실제 URL scheme 시스템 등록은 정식 `.app` 번들 후속 작업으로 남김.

### NotificationPolicyMatrix

ADR-092 §4.8 표를 그대로 코드화:

| 알림 | active | idle | off |
|---|---|---|---|
| hitlApprovalRequest | macOSOnly | both | telegramOnly |
| taskCompleteSuccess | macOSOnly | suppressed | telegramOnly |
| taskCompleteFailure | both | both | telegramOnly |
| rateLimitAlert | macOSOnly | suppressed | telegramOnly |
| generalAlert | macOSOnly | macOSOnly | telegramOnly |

### DeviceState 판정

- `desktopActive`: 기본값
- `desktopIdle`: 5분 무입력 OR `NSWorkspace.didSleepNotification` (macOS)
- `desktopOff`: 현재 Phase에서는 명시적 설정만 (실제 전원 OFF 감지는 후속)

### TelegramFirstMessageDetector

- `URLSession getUpdates` long-polling (timeout 30s), offset 관리
- `AsyncStream<Detection>` — wizard sheet가 토큰 입력 즉시 구독
- wizard sheet 닫히면 `stop()` 호출
- 감지된 Detection 클릭 → `allowedUserIdsText`에 자동 추가
- 수동 입력은 기존 텍스트필드로 여전히 가능

### Quiet Hours

- `quietHoursStart: Int?` (0-23), `quietHoursEnd: Int?` (0-23)
- 현재 시각이 quiet hours 범위이면 `generalAlert`, `taskCompleteSuccess` 채널을 `suppressed`로 격하
- `currentDeliveryChannel(for:)` 내부에서 시간 비교 처리

---

## 후속 작업 (이 ADR에서 미뤄진 항목)

1. **macOS URL scheme 시스템 등록** (`CFBundleURLTypes` in Info.plist): SwiftPM executable로는 `.app` 번들 없이 시스템 URL scheme 등록 불가. 정식 Xcode 프로젝트 / `.app` 번들 전환 시 처리.
2. **실제 desktopOff 감지**: 현재는 manual set. 추후 `NSWorkspace.willSleepNotification` 기반 자동 off 판정 추가.
3. **Quiet Hours UI**: 데이터 모델은 완비. Settings > Telegram 탭 내 시간 picker UI는 후속 ADR.
4. **NotificationPolicyMatrix 편집 UI**: 표 형태 클릭 편집 UI는 후속 ADR.
5. **Digest 묶기**: rate limit 격하 5분 3회 → digest 기능은 후속 ADR.

---

## 테스트 결과

- 신규 테스트: 42+개 (formatter 15+, deep link 12+, policy 10+, detector 5+)
- 기존 820개 회귀: 유지
- `swift build`: Build complete
- `swift test`: 860+ passed

---

## 이전 Phase 참조

- Phase 1 (ADR-092 구현): Hub + Wizard — 커밋 1e71088
- Phase 2 (ADR-093 구현): Dock + ContextCard + ActivityFeed + getMe — 커밋 18a1077
- Phase 3 (ADR-094 구현): CommandPalette + HITL + Inline Callback — 커밋 620d387
