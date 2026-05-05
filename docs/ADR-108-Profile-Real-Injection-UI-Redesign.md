# ADR-108: 하네스 실제 주입 (system prompt + CLAUDE.md sync) + UI 재디자인

**상태**: Accepted  
**날짜**: 2026-05-04  
**관련**: ADR-106, ADR-107, ADR-049, ADR-055

---

## 1. 배경 — 문제 진단

### 1-1. USER_PROFILE.md는 dead file

ADR-106/107에서 `.harness/rules/USER_PROFILE.md`를 작성했으나:
- Claude Code는 `.harness/rules/` 디렉토리를 **자동으로 읽지 않는다**.
- 하네스 orchestrator가 이 파일을 system prompt에 포함하는 코드가 없다.
- 결과: 사용자가 입력한 직업/목표/GoalContext가 **LLM에 도달하지 못함**.

### 1-2. adapter spawn에 userProfile 미전달

`LiveClaudeAdapter.spawn`은 `workspace.projectProfile.systemPromptAppendix()`만 inject.  
`appModel.preferences.userProfile`은 어디에도 전달되지 않았다.

### 1-3. UI 품질 문제

사용자 신고: UserProfileSheet가 세로 길이 초과 + 전체적인 간격 조정 필요.

---

## 2. 결정 — 3-Pronged 주입 전략

```
Spawn 시:
  [사용자 프로필 (compact)] → --append-system-prompt (첫 번째, cache 안정)
  [프로젝트 프로필]          → --append-system-prompt (두 번째)

저장 시:
  <workspace>/.harness/rules/USER_PROFILE.md (기존 — 하네스 orchestrator용)
  <workspace>/CLAUDE.md marker 섹션 (신규 — Claude Code 자동 읽기)
```

### 2-1. renderForSystemPrompt() — 컴팩트 LLM 주입용

`UserProfile`에 `renderForSystemPrompt() -> String?` 추가:
- 모든 실질 필드가 비어있으면 `nil` 반환 (주입 불필요).
- `[사용자 프로필] 이름: … · 직업: … · 목표: … · 상태: …` 형식.
- 200자 이내 (Anthropic prompt cache 정렬 최적화).
- 필드 concat 순서 **결정적** → 같은 프로필 = 같은 string = cache hit 유지.

### 2-2. userProfileProvider closure — adapter init 시 주입

```swift
LiveClaudeAdapter(
    claudePath: ...,
    userProfileProvider: { [weak model] in
        model?.preferences.userProfile.renderForSystemPrompt()
    }
)
```

- `@Sendable () -> String?` closure → actor 격리 안전.
- spawn마다 호출 → 프로필 변경 즉시 반영 (adapter 재생성 불필요).
- `LiveClaudeAdapter`, `LiveCodexAdapter`, `LiveChildClaudeProcess` 3곳 모두 적용.
- 기존 init signature는 `default nil`로 backward-compatible.

spawn 순서:
1. `userProfileProvider?()` → `--append-system-prompt` (cache key 앞)
2. `workspace.projectProfile.systemPromptAppendix()` → `--append-system-prompt` (뒤)

### 2-3. CLAUDE.md marker 동기화 — CLAUDEMdMerger

Claude Code는 `<workspace>/CLAUDE.md`를 자동으로 읽는다 (Anthropic 공식 동작).

**CLAUDEMdMerger** (`Sources/YuminaiCore/CLAUDEMdMerger.swift`):
```
<!-- BEGIN YUMINAI USER PROFILE -->
> 이 섹션은 Yuminai가 자동으로 동기화해요. 직접 편집하면 다음 갱신 시 덮어쓰기됩니다.

## 사용자 프로필
- 이름: ...
- 직업: ...
...

<!-- END YUMINAI USER PROFILE -->
```

**Merge 정책** (사용자 자체 내용 완전 보존):
| 상황 | 동작 |
|------|------|
| 파일 없음 | marker + section만 새로 작성 |
| 파일 있음, marker 없음 | 끝에 append (기존 내용 앞에 유지) |
| 파일 있음, marker 있음 | marker 사이만 replace, 나머지 보존 |
| profileSection 비어있음 | marker 블록 자체 제거 |

**renderForCLAUDEMd()** — marker 안에 들어갈 본문 (## 사용자 프로필 이하):
- `renderHarnessRules()`와 별개로 간결한 버전.
- 응답 가이드 포함 (LLM이 바로 참조 가능).
- 빈 필드는 제외.

**AppModel.syncUserProfileToCLAUDEMd()** — `updateUserProfile()` 호출 시 함께 실행:
```swift
public func updateUserProfile(_ profile: UserProfile) async {
    preferences.userProfile = profile
    await savePreferences()
    for workspace in workspaces {
        let wsURL = URL(fileURLWithPath: workspace.directoryPath)
        await syncUserProfileTo(workspaceURL: wsURL)       // 기존
        await syncUserProfileToCLAUDEMd(workspaceURL: wsURL) // 신규
    }
    // adapter는 다음 spawn 시 provider closure 통해 자동 반영
}
```

---

## 3. UserProfileSheet — 기존 디자인 유지 + 안내 callout 업데이트

기존 CardSection 5장 구조는 잘 동작하므로 유지.  
InfoCallout 내용만 실제 주입 방식을 반영해 업데이트 (scope 최소화 원칙).

---

## 4. 구현 세부사항

### 4-1. 파일 변경 목록

| 파일 | 변경 내용 |
|------|-----------|
| `Sources/YuminaiCore/UserProfile.swift` | `renderForSystemPrompt()`, `renderForCLAUDEMd()` 추가 |
| `Sources/YuminaiCore/CLAUDEMdMerger.swift` | 신규 — begin/end marker merge 유틸 |
| `Sources/YuminaiClaudeAdapter/LiveClaudeAdapter.swift` | `userProfileProvider` init 파라미터 + spawn inject |
| `Sources/YuminaiClaudeAdapter/LiveCodexAdapter.swift` | 동일 패턴 |
| `Sources/YuminaiClaudeAdapter/LiveChildClaudeProcess.swift` | 동일 패턴 |
| `Sources/YuminaiApp/YuminaiApp.swift` | bootstrap에서 `profileProvider` closure 생성 후 adapter init 전달 |
| `Sources/YuminaiApp/AppModel.swift` | `updateUserProfile` 확장 + `syncUserProfileToCLAUDEMd` 추가 |
| `Tests/YuminaiCoreTests/UserProfileSystemPromptTests.swift` | 신규 — 14 tests |
| `Tests/YuminaiCoreTests/CLAUDEMdMergerTests.swift` | 신규 — 14 tests |

### 4-2. Anthropic Prompt Cache 고려

- `userProfile`은 자주 안 바뀜 → `--append-system-prompt`에 **먼저** 등록.
- `projectProfile`은 워크스페이스마다 다름 → 뒤에 등록.
- `renderForSystemPrompt()` 내 필드 순서 고정 → 같은 프로필 = 같은 string → cache hit 유지.
- 200자 이내 제한으로 cache block 낭비 최소화.

---

## 5. 검증

### 5-1. 자동 검증

```
swift build  → Build complete! (0 errors)
swift test   → 1047 tests passed (baseline 1019 + 신규 28, 0 failed)
```

### 5-2. 수동 검증 가이드

1. 프로필 입력 → 저장
2. 워크스페이스 1개 선택 → 디렉토리에 `CLAUDE.md` 생성 확인
3. `grep "BEGIN YUMINAI" <workspace>/CLAUDE.md` → marker 섹션 확인
4. 채팅 시작 → "내 직업이 뭐야? 내 목표는 뭐야?" → LLM이 정확히 답변
5. 프로필 수정 → `CLAUDE.md` 마커 사이 내용만 갱신, 기타 보존 확인

---

## 5. UI 재디자인 (ADR-108-B)

### 5-1. 좌우 split (sidebar + content) 결정 근거

**문제**: 기존 4장 카드가 세로로 쌓이는 구조 → 작은 화면에서 잘림 + 답답한 UX.

**결정**: macOS Settings.app 스타일 좌우 분할 레이아웃.

```
┌──────────────────┬─────────────────────────────────┐
│ 프로필           │  (선택된 섹션 컨텐츠)            │
│ ────────────     │                                 │
│ ◐ 기본 정보  ✓  │  [큰 입력 영역 with breathing]   │
│ 💼 직업/목표 ✓  │                                 │
│ 🎯 목표 상태 ✓  │                                 │
│ ⚙ 선호 설정    │                                 │
│                  │                                 │
│ 미입력 N개       │                                 │
└──────────────────┴─────────────────────────────────┘
                          [취소]   [저장]
```

**근거**:
- 가로 wide (760×540) → 세로 스크롤 없이 한 화면에 전부 표시 가능
- macOS 플랫폼 패턴 — 사용자 기대에 일치 (System Preferences, Xcode Settings)
- HStack + sidebar/content 구조가 NavigationSplitView보다 modal sheet 안에서 안정적
  (NavigationSplitView는 별도 wrapping 윈도우 필요 — sheet 안에서 불안정)

**구현**: `HStack { sidebarColumn; Divider(); contentColumn }` — 가장 단순하고 안정적인 패턴.

### 5-2. 완성도 ✓ visual feedback 패턴

각 섹션이 "입력됐는지" 체크하여 sidebar 아이템 우측에 녹색 ✓ 표시.

**완성도 로직** (`UserProfileCompletionHelper` — `YuminaiCore` 분리):
- **기본 정보**: `displayName` 비공백 입력
- **직업/목표**: `jobTitle` 또는 `primaryGoal` 중 하나 입력
- **목표 상태**: `GoalContext.hasContent == true` (한 필드라도 입력)
- **선호 설정**: `additionalContext` 입력 또는 `preferredAgent != nil`

**분리 이유**: UI와 무관한 순수 함수 → `YuminaiCoreTests`에서 단위 테스트 가능.

### 5-3. 깜박임 방지 (transition: opacity only)

기존 `.move(edge:).combined(with: .opacity)` → layout shift + 깜박임 발생.

**결정**: 모든 섹션 전환에 `.opacity` 전환만 사용.

```swift
Group { ... }
    .transition(.opacity)
    .animation(.easeOut(duration: 0.15), value: selectedSection)
```

GoalContext 동적 필드 전환도 동일하게 `.opacity` 적용 → 위치 shift 없음.

### 5-4. ImageCropSheet 컨트롤 패널 설계

**문제**: 320px 작은 미리보기 + manual gesture만으로 정밀 조작 어려움.

**결정**: 좌우 분할 — 큰 미리보기(360×360) + 컨트롤 패널(280px).

컨트롤 패널 구성:
1. **확대/축소 Slider** (0.5×~3.0×) + 현재 배율 라벨 — 드래그 보조
2. **출력 크기 Picker** (segmented): 작게(128px) / 보통(256px) / 크게(512px)
3. **빠른 조작 버튼**: "위치/크기 초기화", "이미지 정중앙"
4. **결과 미리보기 thumbnail** — 원형으로 실제 표시 방식 미리보기

**레이아웃 shift 방지**: 미리보기 frame 고정 (360×360), 컨트롤 width 고정 (280px).

드래그/줌 gesture는 유지 (큰 미리보기 영역에서 부드러움) — 슬라이더는 보조 역할.

### 5-5. 후속 개선 (ADR-108-B 미포함)

- 다크모드 컬러 contrast 조정 (sidebar bgSidebar와 bg 경계 미묘)
- 접근성: VoiceOver 레이블 완성 (각 sidebar 섹션 + 완성도 상태 설명)
- 키보드 탐색: Tab 순서 최적화 (sidebar → content → footer)

---

## 6. 후속 옵션 (이번 미포함)

- **글로벌 CLAUDE.md** (`~/.claude/CLAUDE.md`) 동기화 — Claude Code 전역 적용
- **프로필 변경 감지** — adapter에 `setUserProfile()` 메서드로 명시적 갱신

---

*결정: 3-pronged 주입으로 userProfile이 실제로 LLM에 도달함을 보장한다. CLAUDE.md merger는 사용자 자체 내용을 완전 보존한다. ADR-108-B에서 macOS Settings 스타일 split UI로 UX 품질 문제를 해결한다.*
