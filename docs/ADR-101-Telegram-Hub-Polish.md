# ADR-101: Telegram Hub UX 최상위 고도화

**날짜**: 2026-05-04  
**상태**: 완료 (accepted)  
**커밋**: feat(telegram): ADR-101 — Telegram Hub UX 최상위 고도화

---

## 1. 배경 (사용자 8개 요청)

사용자가 Telegram Hub 화면의 UX를 전면 개선해 달라는 요청(ADR-101)을 제출. 요청을 8개 영역으로 분해:

| # | 요청 | 구현 Phase |
|---|---|---|
| 1 | 친화 언어 — 어려운 단어를 쉬운 표현으로 | Phase B |
| 2 | Chat type 안내 — 그룹/1:1 차이 설명 | Phase C/D |
| 3 | 중복 validation UX — 이미 등록된 봇 안내 | Phase D |
| 4 | CTA 활성화 — 필수값 입력 시에만 버튼 활성 | Phase C |
| 5 | 점진 정보 노출 — 부가 정보 expand/collapse | Phase E |
| 6 | iOS 동화 디자인 — List + swipeActions + contextMenu | Phase F |
| 7 | 전체 UI/UX 점검 — 일관성/spacing/색상 | Phase B+E+F |
| 8 | 단위 테스트 — 새 helper/validator | Phase A |

---

## 2. 친화 언어 사전

### 신규 파일: `TelegramHubFriendlyText.swift`

| 어려운 표기 | → 쉬운 표기 | 적용 위치 |
|---|---|---|
| Bindings / binding | 연결 / 연결 설정 | 탭 라벨, 섹션 헤더, 에러 메시지 |
| Chat ID / chat id | 대화방 번호 | TelegramBotBindingEditSheet, OnboardingStep3, CokacdirImportSheet |
| workspace | 작업 폴더 | TelegramBotBindingEditSheet, OnboardingStep3, TelegramBotBindingSection |
| Chat ↔ Workspace 매핑 | 대화방 → 작업 폴더 연결 | TelegramBotBindingSection |
| whitelist / allowedUserIds | 접근 허가 목록 / 사용 가능한 사람 | TelegramBotEditSheet, CommandEditSheet |
| HITL / HITL 설정 | 위험 명령 확인 / 위험 명령 확인 설정 | TelegramHubSettingsTab |
| HITL 타임아웃 | 확인 대기 시간 | TelegramHubSettingsTab |
| Diff 미리보기 라인 한도 | 변경사항 미리보기 줄 수 | TelegramHubSettingsTab |
| Quiet Hours | 방해 금지 시간 | TelegramHubSettingsTab |
| Notification Policy Matrix | 알림 정책 표 | TelegramHubSettingsTab |
| desktopActive/Idle/Off | 데스크탑 사용 중/잠시 자리 비움/꺼짐 | DeviceState.displayLabel |
| macOSOnly/telegramOnly/both/suppressed | 데스크탑만/텔레그램만/둘 다/알림 끔 | DeliveryChannel.displayLabel |
| HITL 승인 요청 | 위험 명령 확인 요청 | NotificationKind.displayLabel |
| Rate Limit 경고 | 사용량 한도 경고 | NotificationKind.displayLabel |
| Commands 탭 | 명령어 탭 | TelegramHubView.Tab |
| Activity 탭 | 활동 로그 탭 | TelegramHubView.Tab |
| Bots 탭 | 봇 목록 탭 | TelegramHubView.Tab |
| Bindings 탭 | 연결 탭 | TelegramHubView.Tab |
| multi-bot 목록 | 봇 목록 (여러 봇 목록) | CokacdirImportSheet |
| Keychain key | macOS 비밀번호 저장소 키 | TelegramBotEditSheet |
| Whitelist 표시 | 접근 허가됨 / 전체 허용 (주의) | ChatContextCard |
| chat 후보 | 대화방 후보 | CokacdirImportSheet BotRow |

---

## 3. Chat Type 안내 (ADR-101 요청 #2)

### 구현 위치
- `CokacdirImportSheet.chatPicker()` 상단에 `InfoCallout(.info)` 추가
- `OnboardingStep3Binding` Chat ID 입력 영역에 인라인 chat type 배지 추가 (입력값 기반 즉시 표시)

### 안내 문구
```
• 1:1 대화 (번호 > 0): 나만 볼 수 있는 비공개 대화방. 가장 안전하고 추천합니다.
• 그룹 채팅 (번호 < 0): 여러 명이 함께 볼 수 있는 단체방. 신뢰하는 멤버만 있는 방을 권장합니다.
```

---

## 4. iOS 디자인 가이드 적용

### List + swipeActions + contextMenu

봇 목록과 그룹 목록을 `ScrollView + VStack`에서 `List`로 전환:

```swift
List {
    ForEach(items) { item in
        Row(item)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { delete(item) }
                    label: { Label("삭제", systemImage: "trash") }
                Button { edit(item) }
                    label: { Label("편집", systemImage: "pencil") }
                    .tint(.blue)
            }
            .contextMenu { ... }
    }
}
.listStyle(.inset)
.scrollContentBackground(.hidden)
```

적용 파일:
- `TelegramBotListSection.swift` — 봇 목록
- `TelegramBotGroupSection.swift` — 그룹 목록

---

## 5. CTA 활성화 패턴

### 원칙
모든 sheet/wizard에서 필수값이 충족될 때만 [저장]/[가져오기]/[다음] 버튼 활성화.

### 구현
`TelegramBotValidator`에 공통 로직 위임:

```swift
// TelegramBotEditSheet
private var isFormValid: Bool {
    TelegramBotValidator.validateBot(
        displayName: displayName, username: username,
        keychainKey: keychainKey, existingId: existing?.id,
        existingBots: appModel.preferences.telegramBots
    ).isValid
}

// footer button
FlatButton("저장", variant: .primary) { ... }
    .disabled(!isFormValid)
```

적용된 sheet 목록:
| Sheet | 검증 조건 |
|---|---|
| TelegramBotEditSheet | displayName 비어있지 않음 + keychainKey 비어있지 않음 + username 중복 없음 |
| TelegramBotGroupEditSheet | displayName 비어있지 않음 |
| TelegramBotBindingEditSheet | selectedBotId != nil + chatId 유효한 숫자 |
| CommandEditSheet | trigger '/'로 시작 + 이름 1~32자 + description 비어있지 않음 |
| CokacdirImportSheet | 봇 선택 + chatId 유효 + 중복 아님 |
| TelegramOnboardingWizard | Step 1: token 형식 valid + displayName 비어있지 않음 |

---

## 6. 중복 Validation UX

### CokacdirImportSheet
1. **BotRow** — 이미 등록된 봇에 `DuplicateBadge` (회색 capsule + checkmark.shield) 표시
2. **중복 봇 선택 시** — `InfoCallout(.warning)` 표시: "이 봇은 이미 Telegram Hub에 등록되어 있어요."
3. **[가져오기] 버튼** — `canImport = selectedBot != nil && chatId != nil && !isDuplicate`로 비활성화

### TelegramBotEditSheet
- username 입력 실시간으로 `TelegramBotValidator.validateBot()` 호출
- footer에 `validationResult.errorMessage` 즉시 표시 (빨간 글자)
- [저장] 버튼 `.disabled(!isFormValid)`

---

## 7. 점진 정보 노출 패턴

### 신규 컴포넌트: `ExpandableInfoSection.swift`

```swift
ExpandableInfoSection(label: "자세히 보기", labelIcon: "info.circle") {
    VStack(alignment: .leading) {
        infoLine(label: "macOS 비밀번호 저장소 키", value: bot.keychainKey)
        infoLine(label: "사용 가능한 사람", value: "\(bot.allowedUserIds.count)명")
    }
}
```

- chevron이 90° 회전하는 spring 애니메이션
- `.transition(.opacity.combined(with: .move(edge: .top)))`

적용 위치:
- `TelegramBotListSection` — 봇 row의 keychainKey, 허가 목록, 메모, 아이콘/색상
- `TelegramBotGroupSection` — 그룹 row의 응답모드 override, budget, 공유 스킬

추가 신규 컴포넌트:
- `ChatTypeBadge` — chatId 부호로 "1:1 대화" / "그룹 채팅" 배지 자동 생성
- `DuplicateBadge` — 이미 등록된 봇 시각 표시

---

## 8. 검증 + 회귀

```
swift build → Build complete!
swift test  → 958 tests passed (0 failures, 0 skipped)
```

신규 테스트 스위트:
- `TelegramBotValidatorTests` — 26개 테스트
- `TelegramHubFriendlyTextTests` — 12개 테스트

총 신규 테스트: 38개

---

## 9. 신규 파일 목록

| 파일 | 위치 | 역할 |
|---|---|---|
| `TelegramHubFriendlyText.swift` | Sources/YuminaiCore | 친화 언어 사전 (static strings) |
| `TelegramBotValidator.swift` | Sources/YuminaiCore | 폼 유효성 검사 helper |
| `ExpandableInfoSection.swift` | Sources/YuminaiUI | 점진 정보 노출 컴포넌트 + ChatTypeBadge + DuplicateBadge |
| `TelegramBotValidatorTests.swift` | Tests/YuminaiCoreTests | 26개 단위 테스트 |
| `TelegramHubFriendlyTextTests.swift` | Tests/YuminaiCoreTests | 12개 단위 테스트 |

---

## 10. 수동 검증 가이드

1. **탭 라벨 확인**: Telegram Hub 열기 → "봇 목록 / 연결 / 명령어 / 활동 로그 / 설정" 표시 확인
2. **봇 추가 CTA**: [봇 추가] → 이름 비워두면 [저장] 비활성화 → 이름 입력 시 활성화
3. **중복 봇 배지**: cokacdir에서 봇 가져오기 → 이미 등록된 봇에 "이미 등록됨" 배지 표시
4. **중복 봇 경고**: 이미 등록된 봇 선택 → 노란 경고 callout + [가져오기] 비활성화
5. **대화방 종류 안내**: cokacdir import에서 봇 선택 → 대화방 선택 화면에 1:1/그룹 안내 callout
6. **점진 노출**: 봇 목록에서 "자세히 보기" 클릭 → keychainKey, 허가 목록 등 펼쳐짐
7. **swipeActions**: 봇 목록 row에서 왼쪽으로 스와이프 → 삭제/편집 버튼 나타남
8. **contextMenu**: 봇 목록 row 우클릭 → 편집/활성화/삭제 메뉴
9. **설정 탭**: "방해 금지 시간 / 위험 명령 확인 설정 / 알림 정책 표" 라벨 확인
10. **연결 탭 빈 상태**: 연결 없을 때 "연결 없음" + "대화방 → 작업 폴더 연결" 안내

---

## 11. 후속 항목 (시간 부족 시 별도 ADR)

- `TelegramHubCommandsTab` 상세 UI (현재 placeholder)
- `ActivityFeedView` 친화 언어 전면 적용
- `ChatContextCard` ExpandableInfoSection 적용 (현재 hover 패턴 유지)
- ChatRow에도 ChatTypeBadge 통합
- OnboardingStep2Whitelist 친화 언어 ("허용 목록" → "사용 가능한 사람 목록")
