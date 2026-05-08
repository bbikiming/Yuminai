# ADR-141: 접근성(Accessibility) 개선

**날짜**: 2026-05-08  
**상태**: Accepted  
**연관**: ADR-073 (UI 컴포넌트 표준)

---

## 1. 배경

VoiceOver 사용자를 위한 접근성 레이블이 누락된 인터랙티브 요소들이 발견됐다. 특히:

- 아이콘만으로 이루어진 버튼 (SF Symbol, 라벨 없음)
- 탭 선택 상태를 알리지 않는 탭 picker
- 목록 헤더의 역할 미선언
- 44×44pt 최소 히트 영역 미달 요소

---

## 2. 결정

### HITLApprovalSheet — 탭 picker 접근성

```swift
.accessibilityLabel("요청 \(index + 1): \(req.action)")
.accessibilityAddTraits(index == selectedIndex ? [.isSelected] : [])
```

### CommandPaletteEditor — 목록 헤더

```swift
.toolbar { ToolbarItem { ... } }
// 헤더 Text에:
.accessibilityAddTraits(.isHeader)
.accessibilityLabel("텔레그램 명령어 목록")
```

### BotStatusDockView — 에러 로그 버튼

```swift
.frame(minWidth: 44, minHeight: 44)
.contentShape(Rectangle())
.accessibilityLabel("봇 에러 로그 열기")
```

### HITLApprovalSheet — 타임아웃 카운트다운

`remaining < 15` 조건으로 색상 변경 시 VoiceOver 공지를 위해 `.animation` value 바인딩 유지.

---

## 3. 기준

- 모든 인터랙티브 요소: 최소 44×44pt 히트 영역 (Apple HIG)
- SF Symbol 단독 버튼: `.accessibilityLabel` 필수
- 선택 가능한 탭: `.accessibilityAddTraits([.isSelected])` 상태 반영
- 목록/섹션 헤더: `.accessibilityAddTraits(.isHeader)`

---

## 4. 영향 파일

`HITLApprovalSheet.swift`, `CommandPaletteEditor.swift`, `BotStatusDockView.swift`, `LibrarySheet.swift`
