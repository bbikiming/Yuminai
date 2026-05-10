# ADR-151 — 텔레그램 핸드오프 버튼 + E2E 검증

**날짜:** 2026-05-10  
**상태:** Accepted  
**분류:** 텔레그램 연계 · UX 흐름 · 통합 검증

---

## 배경

사용자 요청:

> "한 세션에서 작업을 하다가 이제 사용자가 외부에 나가서 텔레그램으로 연계해서 구현할 수 있도록 텔레그램에서 이어서 작업할 수 있는 버튼을 하나 추가해 줘. 그리고 명확하게 텔레그램 봇 연계 기능들과 설정들이 전부 하나로 연결돼서 정상 동작 하는지 확실하게 검증해 줘"

데스크탑에서 진행하던 작업을 텔레그램으로 이어갈 수 있도록 "핸드오프" 진입점을 추가하고, 기존 Telegram 연계 파이프라인 전체를 end-to-end로 검증한다.

---

## Part A — 핸드오프 설계

### A-1. 사용 시나리오

```
[사용자] 데스크탑에서 채팅 중
  → Composer footer "📱 텔레그램으로" 클릭
    또는 ChatToolbar "텔레그램으로" 버튼 클릭
    또는 SidebarView ChatSessionRow 우클릭 → "텔레그램으로 이어서"
  → TelegramHandoffSheet 열림 (전송 대상 + 메시지 미리보기 확인)
  → "텔레그램으로 전송" 클릭
  → 해당 Telegram chat에 컨텍스트 요약 전송
  → 사용자가 텔레그램에서 답장 → 같은 session으로 routing
  → 데스크탑으로 복귀 시 자연스럽게 이어서 작업
```

### A-2. 데이터 모델

**`Sources/YuminaiCore/TelegramHandoff.swift`** (신규):

#### `TelegramHandoffRequest`
| 필드 | 타입 | 설명 |
|------|------|------|
| `id` | UUID | 핸드오프 요청 식별자 |
| `sessionId` | UUID? | ChatSession.id (nil = 자유 대화) |
| `workspaceId` | UUID? | 어느 워크스페이스 |
| `botId` | UUID | 전송할 봇 |
| `chatId` | Int64 | 전송할 chat |
| `initiatedAt` | Date | 핸드오프 시작 시각 |
| `summary` | String | 사용자에게 보낼 메시지 |
| `lastUserPrompt` | String? | 마지막 사용자 입력 |

#### `TelegramHandoffStatus`
- `sent` — 전송 완료
- `pending` — 응답 대기
- `received` — 사용자 답장 도착
- `completed` — 세션 종료
- `failed` — 전송 실패

#### `TelegramHandoffError`
- `botNotActive` — 봇 미활성화
- `noBinding` — 연결된 chat 없음
- `noMatchingBinding` — 워크스페이스 매칭 binding 없음
- `sendFailed(underlying:)` — 전송 실패

### A-3. 핸드오프 메시지 포맷 (한국어 친화)

```
📱 작업 이어가기 — [워크스페이스명]
Yuminai 데스크탑에서 작업 중이던 세션을 여기서 계속할 수 있어요.
최근 작업: <마지막 user prompt, 120자 truncate>
답장 보내면 같은 세션에서 이어집니다.
```

### A-4. UI 진입점 3곳

| 진입점 | 컴포넌트 | 구현 |
|--------|----------|------|
| Composer footer | `TelegramHandoffButton` | AutoRunToggle 옆 (secondary 영역) |
| ChatToolbar | `TelegramHandoffButton` | Spacer 전 좌측 (non-tiny 모드) |
| ChatSessionRow 우클릭 | context menu item | "텔레그램으로 이어서" |

모든 진입점은 `TelegramHandoffSheet`를 열어 전송 전 확인 + 미리보기 제공.

### A-5. 핸드오프 흐름도

```
사용자 클릭
  → TelegramHandoffSheet (확인 + 미리보기)
  → handoffActiveSessionToTelegram() [AppModel+Telegram.swift]
    → binding 조회 (activeWorkspaceId 매칭 우선)
    → TelegramHandoffFormatter.format() → 메시지 생성
    → bot.send(msg, to: chatId)
    → sessionBridge.setRequestChatId(chatId)
      → 후속 텔레그램 메시지가 같은 chat으로 응답됨
  → lastHandoffRequest 갱신 (성공 시)
  → 1.5초 후 sheet 자동 닫힘
```

---

## Part B — E2E 검증 결과

### B-1. 10단계 검증 매트릭스

| 단계 | 컴포넌트 | 검증 방법 | 결과 |
|------|---------|----------|------|
| **1. 봇 등록** | `TelegramBotRegistry` | `E2E_BotRegistryTests` (3 tests) | ✅ |
| **2. Chat binding** | `BotChatBinding` | `E2E_BotChatBindingTests` (2 tests) | ✅ |
| **3. 핸드오프 메시지** | `TelegramHandoffFormatter` | `E2E_HandoffFormatterTests` (2 tests) | ✅ |
| **4. SessionBridge routing** | `TelegramSessionBridge.consume()` | `E2E_SessionBridgeRoutingTests` (4 tests) | ✅ |
| **5. Destructive tool 검출** | `isDestructiveToolCall()` | `E2E_DestructiveToolTests` (4 tests) | ✅ |
| **6. AlertDispatcher 정책** | `TelegramAlertDispatcher.dispatch()` | `E2E_AlertDispatcherTests` (3 tests) | ✅ |
| **7. Multi-chat routing** | `setRequestChatId()` | `E2E_BridgeMultiChatTests` (2 tests) | ✅ |
| **8. Handoff request 완전성** | `TelegramHandoffRequest` | `E2E_HandoffRequestTests` (2 tests) | ✅ |
| **9. OfflineQueue** | `TelegramOfflineQueue` | `E2E_OfflineQueueTests` (3 tests) | ✅ |
| **10. chunking** | `TelegramSessionBridge.chunked()` | `E2E_ChunkingTests` (4 tests) | ✅ |

### B-2. wire-up 검증

| 컴포넌트 체인 | 연결 확인 |
|--------------|----------|
| `activateTelegramIfReady()` → `LiveTelegramBot` → `commandPump.start()` | ✅ AppModel+Telegram.swift:60-82 |
| `TelegramCommandPump` → `YuminaiCommandRouter(appModel:)` | ✅ AppModel+Telegram.swift:73-75 |
| `TelegramAlertDispatcher` + `deliveryChannelProvider` 주입 | ✅ AppModel+Telegram.swift:99-105 |
| `setupTelegramHITLCoordinator()` → `sessionBridge.setHITLCoordinator()` | ✅ AppModel+HITL.swift:82-89 |
| `handoffActiveSessionToTelegram()` → `sessionBridge.setRequestChatId()` | ✅ AppModel+Telegram.swift (신규) |
| Composer `onTelegramHandoff` → `showTelegramHandoffSheet` | ✅ RootView.swift (신규) |
| ChatToolbar `onTelegramHandoff` → `showTelegramHandoffSheet` | ✅ RootView.swift (신규) |
| SidebarView ChatSessionRow `contextMenu` → `showTelegramHandoffSheet` | ✅ SidebarView.swift (신규) |

### B-3. 발견된 이슈 / Dead code

이번 검증에서 wire-up 누락은 발견되지 않음. 기존 연결이 정상 동작 확인.

### B-4. 발견된 빌드 이슈 및 수정

| 이슈 | 파일 | 수정 |
|------|------|------|
| `Theme.Typography.heading` 없음 | TelegramHandoffSheet.swift | `Theme.Typography.title`로 변경 |
| `.toolCall("name", "input")` 레이블 누락 | TelegramIntegrationE2ETests.swift | `name:input:` 레이블 추가 |
| `TelegramHandoffRequest.Hashable` 테스트 잘못된 기대 | TelegramHandoffTests.swift | 실제 synthesized Hashable 동작으로 수정 |

---

## 테스트 카운트

| 파일 | 신규 테스트 수 |
|------|--------------|
| `TelegramHandoffTests.swift` | 20 tests |
| `TelegramIntegrationE2ETests.swift` | 29 tests |
| **신규 합계** | **49 tests** |

**최종 결과:**
- 이전: 1446 tests passed
- 이후: **1495 tests passed** (+ 49 신규, 회귀 0)

---

## 신규/수정 파일 요약

### 신규 파일 (6개)
| 파일 | 설명 |
|------|------|
| `Sources/YuminaiCore/TelegramHandoff.swift` | 데이터 모델 + 포맷터 |
| `Sources/YuminaiUI/TelegramHandoffButton.swift` | 핸드오프 버튼 UI (inline + icon 두 variant) |
| `Sources/YuminaiApp/TelegramHandoffSheet.swift` | 확인 sheet (binding 미연결 안내 포함) |
| `Tests/YuminaiCoreTests/TelegramHandoffTests.swift` | 단위 테스트 20개 |
| `Tests/YuminaiCoreTests/TelegramIntegrationE2ETests.swift` | E2E 통합 테스트 29개 |
| `docs/ADR-151-Telegram-Handoff-E2E-Verification.md` | 이 문서 |

### 수정 파일 (7개)
| 파일 | 변경 내용 |
|------|----------|
| `Sources/YuminaiApp/AppModel.swift` | `showTelegramHandoffSheet`, `lastHandoffRequest` 추가; `presentExclusiveSheet` reset 추가 |
| `Sources/YuminaiApp/AppModel+Telegram.swift` | `handoffActiveSessionToTelegram()` 메서드 추가 |
| `Sources/YuminaiApp/RootView.swift` | TelegramHandoffSheet 연결; Composer/ChatToolbar 핸드오프 콜백 추가; SidebarView 핸드오프 콜백 추가 |
| `Sources/YuminaiUI/Composer.swift` | `onTelegramHandoff`, `telegramHandoffAvailable` 파라미터 + 버튼 추가 |
| `Sources/YuminaiUI/ChatToolbar.swift` | `onTelegramHandoff`, `telegramHandoffAvailable` 파라미터 + 버튼 추가 |
| `Sources/YuminaiUI/SidebarView.swift` | `onTelegramHandoffChatSession`, `telegramHandoffAvailable` + `ChatSessionRow` context menu 항목 추가 |

---

## 친화 언어 적용

ADR-101 원칙 준수 — 사용자 보이는 모든 텍스트 한국어:
- 핸드오프 메시지: "📱 작업 이어가기", "답장 보내면 같은 세션에서 이어집니다"
- 버튼 tooltip: "현재 세션을 텔레그램으로 이어서 작업하기"
- 미연결 안내: "연결된 텔레그램 채팅이 없어요"
- 오류 메시지: "텔레그램 봇이 활성화되어 있지 않아요"

---

## 디자인 원칙 준수

- **backward-compat**: Composer/ChatToolbar/SidebarView 모두 optional 파라미터 (기본값 nil/false) → 기존 호출자 변경 없음
- **HITL guard**: 핸드오프 후 `setRequestChatId` → 이후 텔레그램 destructive tool은 기존 HITL 차단 유지
- **회귀 0**: 1446 → 1495, 기존 테스트 모두 pass

---

## 후속 ADR 후보

- **ADR-152**: 멀티 디바이스 동기 — 핸드오프 이후 desktop이 텔레그램 메시지를 실시간으로 수신하는 양방향 sync
- **ADR-153**: 핸드오프 히스토리 — `AppPreferences`에 최근 핸드오프 목록 저장 + 빠른 재연결
- **ADR-154**: OAuth2 기반 텔레그램 사용자 인증 (현재는 userId allowlist 방식)
