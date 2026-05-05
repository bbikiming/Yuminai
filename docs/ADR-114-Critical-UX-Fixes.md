# ADR-114 — Critical UX Fixes (P0)

**날짜**: 2026-05-04  
**상태**: 완료  
**베이스라인**: 1185 tests, 커밋 6bf3c35  

---

## 배경

종합 UX 진단(research-analyst)에서 P0 3건 발견:

1. `runCommandFromTelegram`이 `currentWorkspace`만 사용 — chat-specific binding 무시 → 멀티 chat 시 silent misroute
2. 사이드바에 라이브러리/카탈로그/번들 직접 진입 항목 없음 — UserProfileSheet 5단 깊이에 묻힘
3. LLM 도구 호출 시 HITL 트리거 wire-up 미확인 — 조사 필요

---

## P0-1: Telegram Chat-Specific Workspace Routing

### 문제

`AppModel.swift`의 `runCommandFromTelegram(_:)` 메서드는 항상 `currentWorkspace`(데스크탑 active)를 참조했다. 사용자가 chat-A에서 워크스페이스 X를 bind했어도, 데스크탑이 워크스페이스 Y에 있으면 chat-A의 `/run`이 Y에서 실행됨 — **silent misroute**.

### 수정

`Sources/YuminaiApp/AppModel.swift:3971` — `runCommandFromTelegram` 시그니처 변경:

```swift
public func runCommandFromTelegram(_ command: String, chatId: Int64? = nil) async
```

내부 로직: `chatId`가 있으면 `preferences.telegramBotChatBindings`에서 매칭 binding → `activeWorkspaceId`로 workspace 조회. 없으면 `currentWorkspace` fallback (legacy 동작 유지).

`Sources/YuminaiApp/YuminaiCommandRouter.swift:311` — `runCommand` 호출자가 `lastChatId` 전달:

```swift
let chatId = lastChatId != 0 ? lastChatId : nil
await MainActor.run { Task { await model.runCommandFromTelegram(cmd, chatId: chatId) } }
```

`lastChatId`는 `handle(_:)` 진입 시 `message.chatId`로 업데이트되므로 항상 현재 chat 기준.

### 테스트

`Tests/YuminaiCoreTests/RunCommandRoutingTests.swift` — 5개 케이스:
- chatId 있음 + binding 매칭 → bound workspace 반환
- chatId 있음 + binding 없음 → fallback
- chatId nil → fallback (legacy)
- binding의 `activeWorkspaceId`가 nil → fallback
- binding의 `activeWorkspaceId`가 workspaces에 없음 → fallback

### 설계 원칙

- `chatId = nil` default → 기존 코드 경로 변경 없음 (하위 호환)
- 데스크탑 active workspace에 영향 없음

---

## P0-2: 사이드바 라이브러리/번들 직접 진입

### 문제

📚 라이브러리와 🎁 스택 번들은 UserProfileSheet → 탭 → 하위 항목 클릭의 5단 깊이에 묻혀 있었다. 사용자가 원클릭으로 접근하기 어려웠다.

### 수정

`Sources/YuminaiUI/SidebarView.swift`:
- `onOpenLibrary: () -> Void` 콜백 prop 추가
- `onOpenBundles: () -> Void` 콜백 prop 추가
- `primaryAndMenu` 섹션에 두 항목 추가 (Telegram Hub 아래, 사용자 가이드 위):

```
Telegram Hub
📚 라이브러리
🎁 스택 번들
사용자 가이드 (외부)
설정
```

`Sources/YuminaiApp/RootView.swift`:
- `onOpenLibrary` → `appModel.presentExclusiveSheet { $0.showLibrarySheet = true }`
- `onOpenBundles` → `appModel.presentExclusiveSheet { $0.showBundleCatalogSheet = true }`

### 설계 원칙

- 기존 `showLibrarySheet`, `showBundleCatalogSheet` AppModel 프로퍼티 재사용 (신규 상태 없음)
- `presentExclusiveSheet` 패턴 — 기존 시트와 충돌 방지
- 콜백 default `{}` → 기존 `SidebarView` 초기화자 변경 없음

---

## P0-3: LLM 도구 호출 HITL 조사 결과

### 조사 결과: **이미 구현됨**

`TelegramSessionBridge.consume(event:)` (`Sources/YuminaiTelegram/TelegramSessionBridge.swift:116-165`)에서:
- `.toolCall(let name, let input)` 이벤트 수신 시 `Self.isDestructiveToolCall(name:input:)` 호출
- 위험 패턴 감지 시 `hitlCoordinator`가 주입돼 있으면 **차단+승인 흐름** 진입 (`coordinator.request()` suspend)
- coordinator 미주입 시 "알림 + 취소 버튼" 동작 유지

`hitlCoordinator` 주입 경로:
1. `AppModel.setupTelegramHITLCoordinator()` → `coordinator` 생성
2. `sessionBridge?.setHITLCoordinator(coordinator, timeoutSeconds:)` 주입
3. 봇 시작(`startTelegramBot`) 시 호출됨

`/run <cmd>` 경로는 `HITLActionGuard.shouldRequestApproval(command:)` (정규식 패턴)로 별도 가드.

### 갭 식별: 실제 차단 미완성

`TelegramSessionBridge`의 주석(라인 151-153):
> _"rejected / timeout / cancelled 시 toolCall을 계속 실행하면 안 되지만  
> ClaudeEvent는 이미 발생했으므로 bridge는 결과만 알린다.  
> 실제 차단은 AppModel이 HITL 응답에 따라 수행해야 함."_

즉, HITL 알림/응답은 작동하나 **실제 Claude 프로세스 중단이 자동으로 이루어지지 않음** — 사용자가 `/cancel`을 수동 실행해야 한다.

### 권장 조치 (ADR-114-B로 분리)

Phase 1 (단기):
- HITL reject/timeout 시 AppModel이 자동으로 `cancelBoundTurn()` 호출 — Claude 프로세스 종료
- `TelegramSessionBridge`에서 HITL 응답을 AppModel에 콜백으로 통보하는 채널 추가

Phase 2 (중기):
- 새 워크스페이스 생성 시 `.harness/hooks/dangerous-actions.sh` 자동 생성 (비차단 알림)
- Claude CLI `--permission-mode` 설정 연계 검토

---

## 검증

```
빌드: Build complete! (0 errors, 0 warnings)
테스트: 1190 tests passed (1185 baseline + 5 신규)
```

### 신규 테스트 (RunCommandRoutingTests — 5개)

| 테스트 | 검증 내용 |
|--------|---------|
| `chatIdWithMatchingBinding_returnsBoundWorkspace` | binding 매칭 → bound workspace |
| `chatIdWithNoBinding_returnsFallback` | binding 없음 → fallback |
| `nilChatId_returnsFallback` | chatId nil → legacy fallback |
| `bindingWithNilActiveWorkspaceId_returnsFallback` | activeWorkspaceId nil → fallback |
| `bindingWithUnknownWorkspaceId_returnsFallback` | 존재하지 않는 wsId → fallback |

---

## 수동 검증 가이드

### P0-1 검증
1. 봇 A에서 chat-1을 워크스페이스 X에 bind
2. 데스크탑에서 워크스페이스 Y 활성화
3. Telegram chat-1에서 `/run swift build` 입력
4. **기대**: 워크스페이스 X에서 실행 (이전: Y에서 실행)

### P0-2 검증
1. Yuminai 앱 실행
2. 사이드바 확인: "📚 라이브러리", "🎁 스택 번들" 항목이 Telegram Hub 아래 표시됨
3. "📚 라이브러리" 클릭 → LibrarySheet 즉시 열림
4. "🎁 스택 번들" 클릭 → BundleCatalogSheet 즉시 열림

---

## 후속 (P1 4건 — 별도 ADR)

P0-3 조사에서 발견한 실제 차단 미완성 이슈는 ADR-114-B로 분리:
- HITL reject/timeout 시 자동 `cancelBoundTurn()` 연동
- Harness hooks 자동 생성 패턴 정립
- `/run` 경로와 LLM 도구 호출 경로의 HITL 패턴 통합
