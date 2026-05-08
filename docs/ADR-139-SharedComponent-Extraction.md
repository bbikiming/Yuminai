# ADR-139: 공유 컴포넌트 추출 (LibraryAddButton, StatusBadge, CardIconBox)

**날짜**: 2026-05-08  
**상태**: Accepted  
**연관**: ADR-073 (UI 컴포넌트 표준)

---

## 1. 배경

여러 sheet에서 동일한 UI 패턴이 중복 구현되어 있었다:

- 라이브러리 추가 버튼 (idle → adding → added 상태 전환)
- 상태 배지 (설치됨 / 경고 / 오류 / 중립)
- 아이콘 박스 (카드 상단 컬러 아이콘 영역)

---

## 2. 결정

`Sources/YuminaiUI/SharedComponents.swift`에 3개 컴포넌트를 정의한다.

### LibraryAddButton

```swift
public struct LibraryAddButton: View {
    public enum State { case idle, adding, added }
    public let state: State
    public let action: () -> Void
}
```

- Capsule 형태
- idle: "+ 추가" (secondary variant)
- adding: ProgressView 스피너
- added: "추가됨" (primary variant, 비활성)

### StatusBadge

```swift
public struct StatusBadge: View {
    public enum Tone { case success, warning, danger, neutral, info }
    public let tone: Tone
    public let label: String
    public let systemImage: String?
}
```

- Capsule 형태, 5가지 색상 톤
- 선택적 SF Symbol 앞치기

### CardIconBox

```swift
public struct CardIconBox: View {
    public let systemImage: String
    public let tint: Color
    public let size: CGFloat
}
```

- RoundedRectangle 배경, tint 색상, 중앙 SF Symbol

---

## 3. 마이그레이션

`SetupWizardSheet.swift`의 수동 statusBadge 구현을 `StatusBadge` 컴포넌트로 교체했다.

---

## 4. 영향 파일

| 파일 | 변경 |
|------|------|
| `Sources/YuminaiUI/SharedComponents.swift` | 신규 |
| `Sources/YuminaiApp/SetupWizardSheet.swift` | StatusBadge 사용으로 교체 |
