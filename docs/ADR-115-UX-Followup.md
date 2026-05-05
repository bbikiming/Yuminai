# ADR-115 — UX Audit Follow-up: P1 4건 + P0-3 후속

**Status:** Accepted  
**Date:** 2026-05-04  
**Baseline:** commit b4199cf, 1190 tests  
**Outcome:** 1220 tests (+ 30), build clean

---

## 배경

ADR-114에서 P0 Critical UX 버그를 해소했으나 UX 감사 결과 추가 개선 5건이 도출됐다.
- P0-3 follow-up: HITL reject/timeout 시 Claude 프로세스가 계속 실행되는 갭
- P1-1: Telegram 빌드 로그가 어떤 워크스페이스의 것인지 알 수 없음
- P1-2: LLM이 어떤 자료를 참고해 답변했는지 사용자가 모름
- P1-3: Setup Wizard 완료 후 프로필 설정을 놓치는 경우 多
- P1-4: 워크스페이스 생성 시 어떤 번들을 선택해야 할지 가이드 부재

---

## P0-3 후속 — HITL reject/timeout 시 Claude 프로세스 자동 중단

### 문제

Telegram HITL에서 사용자가 "거부(❌)"하거나 응답 시간이 초과되면 `TelegramHITLCoordinator`가 `.rejected`/`.timeout`을 반환한다. 이 결과가 `AppModel.respondToHITL(id:response:)` 데스크탑 경로로 흐를 때 `cancelStream()`이 호출되지 않아 Claude가 계속 스트리밍했다.

### 분석

경로는 두 갈래다.
1. **Telegram 경로**: `TelegramSessionBridge.onHITLCancelRequired` → `cancelBoundTurn()` → `notifyCancelled()`. 이미 처리됨.
2. **데스크탑 경로**: `respondToHITL(id:response:)` — 이곳이 갭.

### 결정

`respondToHITL` 내부에서 `.rejected`, `.timeout`, `.cancelled` 케이스에 `cancelStream()`을 호출한다. `cancelStream()`은 idempotent이므로 Telegram 경로에서 이미 취소된 경우에도 안전하다.

```swift
switch response {
case .rejected, .timeout, .cancelled:
    if isStreaming { cancelStream() }
case .approved:
    break
}
```

---

## P1-1 — Telegram 빌드 로그에 워크스페이스 prefix 추가

### 문제

`sendBuildLog`, `sendDiffPreview` 메시지에 워크스페이스 이름이 없어 다중 워크스페이스 환경에서 어느 프로젝트의 메시지인지 구분이 불가능했다.

### 결정

`TelegramSendHelper.sendBuildLog/sendDiffPreview`에 `workspaceName: String? = nil` 파라미터 추가.
- 이름이 있으면 `📁 [WorkspaceName] ▶ 제목` 형식으로 prefix 삽입
- `AppModel.sendBuildLogToTelegram` → `currentWorkspace?.name` 전달
- `TelegramSessionBridge` → `config.workspaceName` 전달 (빈 문자열이면 nil)

기존 호출자는 파라미터 기본값(nil)으로 자동 호환된다.

---

## P1-2 — MessageAttribution 모델 + MessageBubble footer

### 모델 설계

```swift
public struct MessageAttribution: Sendable, Codable, Hashable {
    public let attachedLibraryItems: [String]  // 참고 라이브러리 display 이름 목록
    public let profileSnapshotSummary: String?  // 사용자 프로필 스냅샷 요약
    public let recordedAt: Date                 // attribution 생성 시각
    public var isEmpty: Bool { ... }            // 표시할 내용 없으면 true
    public var displaySummary: String { ... }   // "참고 자료: X · 프로필: Y" 형식
}
```

### Backward Compatibility

`Message.attribution`은 `Optional<MessageAttribution>`이며 `decodeIfPresent`로 디코딩한다.
기존에 저장된 JSON에 `attribution` 키가 없어도 nil로 디코딩돼 앱이 정상 작동한다.

### Attribution 캡처 흐름

1. `AppModel.sendMessage()`: 전송 직전 `attachedLibraryItems` + 프로필 요약을 캡처해 `pendingAttribution` 저장
2. `AppModel.appendMessage(role:content:)`: role == .assistant일 때 `pendingAttribution`을 소비해 `Message.attribution`에 첨부

### UI

`AssistantMessageBlock`에 disclosure 토글 footer 추가. `attribution.isEmpty`면 숨김.
Theme에 없는 `caption` (10pt) 폰트는 파일 스코프 private extension으로 정의.

---

## P1-3 — Setup Wizard 완료 후 프로필 sheet 자동 유도

### 결정

`dismissSetupWizard(markCompleted: true)` 경로에서 `preferences.userProfile.isEmpty`를 확인한다.
비어 있으면 300ms delay 후 `showUserProfileSheet = true`를 설정한다.

```swift
if preferences.userProfile.isEmpty {
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 300_000_000)
        self.showUserProfileSheet = true
    }
}
```

300ms: Wizard dismiss 애니메이션이 완료될 충분한 시간. 너무 짧으면 sheet가 겹친다.

---

## P1-4 — StackBundleCatalog.findMatching + 번들 추천 카드

### findMatching 알고리즘

```swift
public static func findMatching(for profile: ProjectProfile, limit: Int = 3) -> [StackBundle]
```

1. 프로파일의 `frameworks` 배열을 정규화: `.js` suffix 제거, 공백 → `-`
2. `platform` (ios, macos, android 등) + `primaryLanguage` (swift, kotlin 등) 태그 추가
3. 각 번들의 `stackTags`와 교집합 크기(score)를 계산
4. score > 0인 번들을 내림차순 정렬 후 `prefix(limit)` 반환

### CreateWorkspaceSheet UI

- `@State private var recommendedBundles: [StackBundle]` — auto-detection 시 findMatching 결과 저장
- `@State private var bundlesToAdd: Set<UUID>` — 선택 상태 추적
- `bundleRecommendationSection` / `bundleCard(_:)` @ViewBuilder로 추천 카드 표시
- `onBundlesSelected: (([StackBundle]) -> Void)? = nil` 콜백 파라미터 추가 (기본 nil, backward-compat)
- 워크스페이스 생성 시 선택된 번들을 콜백으로 전달

---

## 검증

| 항목 | 결과 |
|------|------|
| swift build | Build complete (0 errors, warnings only) |
| swift test | 1220 tests passed in 193 suites |
| 신규 테스트 | +30 (P1-1: 4, P1-2: 11, P1-4: 6, P0-3: 기존 HITL 테스트 활용) |
| Backward compat | SwiftDataStoreTests (기존 Message init) 통과 |

---

## Follow-up

- `MessageAttribution.recordedAt`을 UI에 노출 (선택적)
- `onBundlesSelected` 콜백을 `AppModel`에 연결해 워크스페이스 생성 시 번들 자동 추가
- `displaySummary` 포맷을 i18n 대응
