# ADR-106 — 사용자 프로필 시스템 + 하네스 엔지니어링 자동 주입

**Status**: Accepted  
**Date**: 2026-05-04  
**Author**: ADR-106

---

## 1. 배경

Yuminai는 Claude / Codex CLI를 래핑하는 macOS 앱으로, 워크스페이스마다 `.harness/` 구조를 통해 컨텍스트를 LLM에 주입한다. 그러나 지금까지 "누가 쓰는 앱인지"에 대한 정보가 전혀 없었다.

**사용자 요청:**
1. 좌측 하단 "yuminai" 영역(`BottomUserCard`)에 사용자 프로필 기능 추가
2. 입력 정보가 하네스 엔지니어링에 반영 (모든 워크스페이스의 Claude/Codex 컨텍스트에 자동 주입)
3. 수집 항목: 직업, 주로 하고 싶은 것, 목표 상태 (정해짐/탐색 중/미정)
4. SwiftUI GUI, 프로필 이미지 선택 가능

---

## 2. UserProfile 모델 (3-mode goalStatus)

```swift
public struct UserProfile: Sendable, Codable, Hashable {
    public var displayName: String           // 표시 이름
    public var jobTitle: String              // 직업
    public var primaryGoal: String           // 주로 하고 싶은 것
    public var goalStatus: GoalStatus        // 3-mode: defined / exploring / undecided
    public var preferredAgent: AgentKind?   // 선호 에이전트 (nil = 자동)
    public var additionalContext: String     // 자유 메모
    public var profileImagePath: String?    // 이미지 경로
    public var updatedAt: Date
}
```

### GoalStatus 3-mode 친화 라벨

| mode | displayName | subtitle |
|------|------------|---------|
| `defined` | 이미 분명한 목표가 있어요 | 목표가 명확하니 바로 실행해 드릴게요 |
| `exploring` | 여러 가지를 탐색 중이에요 | 여러 선택지와 트레이드오프를 함께 살펴볼게요 |
| `undecided` | 아직 정하지 않았어요 | 흥미와 강점을 함께 탐색하고 작은 시도부터 제안할게요 |

각 mode별 LLM 응답 가이드가 `renderHarnessRules()` 출력에 포함된다.

---

## 3. `.harness/rules/USER_PROFILE.md` 동기화 정책

### 트리거

- `AppModel.updateUserProfile(_:)` 호출 시 → 모든 워크스페이스 순회 동기화
- `AppModel.createWorkspace(_:)` 호출 시 → 신규 워크스페이스에 즉시 주입

### skip 조건

`.harness/` 디렉토리가 없는 워크스페이스는 하네스 미사용으로 판단, skip한다.

### 파일 내용

`UserProfile.renderHarnessRules()` 가 마크다운을 생성한다:
- 기본 정보 (이름 / 직업)
- 목표 (주로 하고 싶은 것 / 목표 상태 + 설명)
- 응답 가이드 (goalStatus에 따른 LLM 안내)
- 추가 컨텍스트
- Last updated (ISO8601)

---

## 4. 프로필 이미지 저장 전략

- 사용자가 NSOpenPanel에서 선택 → `FileManager.url(for: .applicationSupportDirectory)` 아래 `Yuminai/profile-image.<ext>` 로 복사
- 기존 파일이 있으면 덮어씀 (단일 슬롯)
- `profileImagePath`에 절대 경로 저장 → NSImage(contentsOfFile:) 로 로드
- 이미지가 없으면 displayName 첫 글자 initial 또는 person.fill 아이콘 표시

---

## 5. 검증

```bash
swift build   # Build complete! (0 errors)
swift test    # 1000 tests passed (977 baseline + 23 new UserProfile tests)
```

### 수동 검증 체크리스트

1. 좌측 하단 "yuminai" 영역 클릭 → 프로필 sheet 열림
2. 4개 카드 입력 + 사진 선택 + [저장] → 워크스페이스 동기화
3. 새 워크스페이스 만들기 → `.harness/rules/USER_PROFILE.md` 자동 생성
4. 기존 워크스페이스에서도 갱신 확인

---

## 6. 후속 과제

- 프로필 이미지 cropping/resizing (NSImage 리사이즈 + 정사각 crop)
- 프로필 shareable export (JSON 내보내기)
- 새 워크스페이스 생성 시 하네스가 있을 때만 동기화 (현재 harnessURL 디렉토리 존재 여부로 skip)
- iCloud sync 연동 (ADR-079 Phase 3) — preferences sync에 포함되어 자동으로 지원되나 profileImagePath는 iCloud Drive 외부일 경우 동기화 안 됨
