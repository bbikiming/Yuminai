# ADR-107 — 사용자 프로필 고도화

**Status**: Accepted  
**Date**: 2026-05-04  
**Author**: Yuminai  

---

## 1. 배경 (사용자 요청 4가지)

ADR-106으로 도입된 사용자 프로필 기능에 대해 다음 4가지 개선 요청이 접수됐다:

1. **이미지 크롭/리사이징** — 이미지 선택 시 크기와 비율을 조정할 수 있게
2. **SwiftUI 네이티브 GUI 적극 활용** — Slider, Picker, Magnification gesture 등
3. **목표 상태별 추가 입력값/선택값** — GoalContext 모델로 하네스 주입 강화
4. **선호 설정 아코디언 안 열리는 버그 수정** — `.contentShape(Rectangle())` 누락

---

## 2. 이미지 크롭 구현

### 2.1 흐름

```
사용자 카메라 버튼 클릭
  → NSOpenPanel (이미지 선택)
  → ImageCropSheet(originalImage:) sheet 표시
  → 드래그 + MagnificationGesture로 위치/크기 조정
  → 비율 Picker (1:1 / 4:3 / 16:9) + 출력 크기 Picker (128 / 256 / 512px)
  → "저장" 버튼 → cropAndSave() → Core Graphics 크롭
  → ~/Library/Application Support/Yuminai/profile-image-<UUID>.png 저장
  → profileImagePath 반환 → UserProfileSheet에 반영
```

### 2.2 드래그 + 핀치 (SwiftUI native gestures)

```swift
Image(nsImage: originalImage)
    .resizable()
    .interpolation(.high)
    .scaledToFit()
    .scaleEffect(imageScale)                       // 0.5x ~ 3.0x
    .offset(imageOffset)
    .gesture(DragGesture().onChanged { ... })
    .simultaneousGesture(MagnificationGesture().onChanged { ... })
```

동시 제스처를 위해 `.simultaneousGesture`를 사용한다. Drag 누적은 `dragStartOffset`으로 관리한다.

### 2.3 크롭 마스크 오버레이

`Canvas`와 `.compositingGroup()` + `.destinationOut` blend mode로 크롭 영역을 "구멍 뚫기" 방식으로 구현했다. 어두운 배경 위에 밝은 크롭 창 경계선이 표시된다.

### 2.4 Core Graphics 크롭

```swift
private func cropAndSave() -> String? {
    guard let cgImage = originalImage.cgImage(...) else { return nil }
    // scaledToFit 기준 display 비율 계산
    // imageScale + imageOffset → 픽셀 좌표 변환
    // cgImage.cropping(to: cropRect)
    // CGContext로 outputSize 리사이즈
    // NSBitmapImageRep → PNG data → 파일 저장
}
```

`NSImage.cgImage(forProposedRect:context:hints:)` → `CGImage.cropping(to:)` → `CGContext` 리사이즈 → `NSBitmapImageRep.representation(using: .png)` 파이프라인을 사용한다.

### 2.5 저장 경로

```
~/Library/Application Support/Yuminai/profile-image-<UUID>.png
```

UUID를 사용하므로 여러 번 저장해도 이전 파일과 충돌하지 않는다.

---

## 3. GoalContext 모델 + 목표 상태별 질문 디자인

### 3.1 GoalContext 구조체

```swift
public struct GoalContext: Sendable, Codable, Hashable {
    // defined 전용
    public var targetDeadline: String        // "2026년 6월"
    public var biggestObstacle: String       // "시간 부족"

    // exploring 전용
    public var exploringOptions: String      // "SwiftUI\nReact" (한 줄에 하나)
    public var explorationCriteria: String   // "학습 곡선, 재미"

    // undecided 전용
    public var strengths: String             // "분석력, 디자인 감각"
    public var interests: String             // "영화, 운동"
    public var pastExperience: String        // 자기소개

    // 공통
    public var interestKeywords: String      // "SwiftUI, AI" (콤마 구분)
}
```

상태를 자주 바꿔도 각 상태별 필드가 독립적으로 유지된다 — 상태 전환 시 이전 입력값이 보존된다.

### 3.2 backward-compat

구 JSON(goalContext 키 없음)에서 디코딩 시 `decodeIfPresent ?? .default`로 처리한다:

```swift
goalContext = try c.decodeIfPresent(GoalContext.self, forKey: .goalContext) ?? .default
```

### 3.3 UI — 동적 질문 섹션

목표 상태 카드 아래 `CardSection(style: .accent)`로 GoalContext 입력 카드가 표시된다. 상태 변경 시 `.transition(.opacity.combined(with: .move(edge: .top)))` + spring 애니메이션으로 전환된다.

| 상태 | 표시 필드 |
|------|-----------|
| defined | 언제까지 이루고 싶으세요? / 가장 큰 장애물은? |
| exploring | 탐색 중인 옵션들 (멀티라인) / 비교 기준 |
| undecided | 강점/잘하는 것 / 관심사 / 이전 경험 (멀티라인) |
| 공통 | 관심 키워드 (콤마 구분) |

---

## 4. 하네스 주입 강화

### 4.1 renderHarnessRules() 출력 예시 (defined + 마감일/장애물 입력 시)

```markdown
## 목표 상세
- **목표 시점**: 2026년 6월
- **현재 가장 큰 장애물**: SwiftUI 학습 시간 부족

## 응답 가이드 (LLM에게)
사용자는 명확한 목표가 있어요. 답변은 직접적이고 행동 지향적으로.
- 마감일(2026년 6월)을 역산해서 우선순위를 제안하세요.
- 'SwiftUI 학습 시간 부족'이 가장 큰 장애물입니다. 이를 해소하는 실전 팁을 우선 제공하세요.
```

### 4.2 설계 원칙

- **빈 필드 제외**: 입력된 필드만 출력. 빈 GoalContext는 '목표 상세' 섹션 자체를 미출력.
- **상태 격리**: defined 상태에서는 exploring 전용 필드를 출력하지 않음 (반대도 마찬가지).
- **공통 키워드**: 모든 상태에서 `interestKeywords`가 입력되면 '관심 키워드' 섹션 출력.

---

## 5. 아코디언 버그 진단 + 수정

### 5.1 원인

```swift
// 버그 코드 (ADR-106)
Button { showAdvanced.toggle() } label: {
    HStack {
        SectionHeaderRow(...)  // Spacer()를 내부에 포함
        Spacer()
        Image(systemName: ...)
    }
    // .contentShape(Rectangle()) 누락!
}
.buttonStyle(.plain)
```

`.buttonStyle(.plain)`은 기본 hit-test 영역을 실제 불투명 픽셀로 제한한다. HStack 안의 빈 공간(`Spacer()`)은 투명하므로 클릭 이벤트를 받지 못했다.

### 5.2 해결

```swift
Button { showAdvanced.toggle() } label: {
    HStack {
        // inline label (SectionHeaderRow 제거 — Spacer 중복 방지)
        ...
        Spacer()
        Image(systemName: ...)
    }
    .contentShape(Rectangle())  // 핵심: 빈 공간도 클릭 영역
}
.buttonStyle(.plain)
```

`.contentShape(Rectangle())`을 label에 추가하면 HStack 전체 영역(투명 공간 포함)이 hit-test 대상이 된다.

`SectionHeaderRow`를 inline label로 교체한 이유: `SectionHeaderRow` 내부에 `Spacer()`가 있어 hit-test 영역이 의도치 않게 분산될 수 있었다.

---

## 6. SwiftUI 네이티브 GUI 요소 활용 현황

| 컴포넌트 | 용도 |
|----------|------|
| `Slider` | 이미지 줌 레벨 (0.5x ~ 3.0x) |
| `Picker(.segmented)` | 크롭 비율 (1:1 / 4:3 / 16:9) + 출력 크기 |
| `MagnificationGesture` | 핀치 줌 |
| `DragGesture` | 이미지 이동 |
| `Canvas` | 크롭 마스크 오버레이 |
| `Image.interpolation(.high)` | 프로필 이미지 고화질 표시 |
| `withAnimation(.spring)` | 모든 상태 전환 |
| `TextField(axis: .vertical)` | 멀티라인 입력 (exploringOptions, pastExperience) |
| `.transition(.opacity.combined(with: .move))` | GoalContext 카드 전환 |

---

## 7. 검증

### 7.1 신규 테스트 (UserProfileGoalContextTests.swift)

총 18개 테스트 케이스:

| 범주 | 항목 수 |
|------|---------|
| GoalContext 기본값/hasContent | 3 |
| Codable round-trip | 2 |
| backward-compat (구 JSON) | 1 |
| renderHarnessRules defined | 3 |
| renderHarnessRules exploring | 2 |
| renderHarnessRules undecided | 2 |
| 공통 키워드 | 2 |
| 빈 GoalContext — 섹션 미출력 | 3 |

### 7.2 회귀 보호

기존 `UserProfileTests.swift` (ADR-106) 22개 케이스 전부 유지. `UserProfile.init()`에 `goalContext` 기본값 파라미터를 추가해 기존 호출부 호환성을 유지했다.

### 7.3 수동 검증 경로

1. 앱 실행 → 좌측 하단 프로필 카드 클릭 → 프로필 편집 sheet 열림
2. 카메라 아이콘 클릭 → NSOpenPanel → 이미지 선택 → ImageCropSheet 자동 표시
3. 드래그로 이미지 이동, 슬라이더로 줌, 비율/출력 크기 Picker 변경 후 저장
4. 목표 상태 카드에서 "이미 분명한 목표" 선택 → GoalContext 카드에 마감일/장애물 필드 표시
5. "여러 가지를 탐색 중" 선택 → 탐색 옵션/비교 기준 필드로 전환 (spring 애니메이션)
6. "아직 정하지 않았어요" 선택 → 강점/관심사/이전 경험 필드로 전환
7. 선호 설정 아코디언 — HStack 빈 공간 클릭 시 정상적으로 열림/닫힘 확인
8. 저장 후 `.harness/rules/USER_PROFILE.md` 내용 확인 — GoalContext 반영됨

---

## 8. 후속 과제

- **CLAUDE.md global 동기화**: renderHarnessRules 출력을 CLAUDE.md에도 주입하는 옵션 (ADR-108 후보)
- **이미지 미리보기 개선**: profile-image 파일 정리 정책 (UUID 파일 누적 방지)
- **GoalContext 필드 유효성**: 목표 시점 날짜 파싱 → 실제 D-day 계산 지원
