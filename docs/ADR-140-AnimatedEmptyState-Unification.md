# ADR-140: AnimatedEmptyState 통일

**날짜**: 2026-05-08  
**상태**: Accepted  
**연관**: ADR-073 (UI 컴포넌트 표준)

---

## 1. 배경

빈 상태(empty state) UI가 각 sheet/panel마다 다르게 구현되어 있었다:

- 일부는 `ContentUnavailableView` (iOS 17+)
- 일부는 `VStack { Image + Text + Text }`
- 일부는 아무것도 없음

---

## 2. 결정

`AnimatedEmptyState` 컴포넌트로 통일한다 (이미 YuminaiUI에 존재).

```swift
AnimatedEmptyState(
    icon: "doc.text.magnifyingglass",
    iconTint: Theme.Color.textTertiary,
    title: "결과 없음",
    message: "검색어를 바꿔 보세요."
)
```

### 마이그레이션 대상

| 파일 | 변경 전 | 변경 후 |
|------|--------|--------|
| `HITLApprovalSheet.swift` | VStack { Image + Text } | AnimatedEmptyState |
| `CommandPaletteEditor.swift` | ContentUnavailableView | AnimatedEmptyState |
| `LibrarySheet.swift` | inline VStack | AnimatedEmptyState (검색/카테고리 컨텍스트 반영) |

### LibrarySheet 동적 메시지

```swift
var emptyTitle: String {
    if !searchQuery.isEmpty { return "검색 결과 없음" }
    if selectedCategory != nil { return "이 카테고리에 항목이 없어요" }
    return "라이브러리가 비어 있어요"
}
```

---

## 3. 접근성

빈 상태 컨테이너에 `.accessibilityElement(children: .contain)` 추가하여 VoiceOver에서 아이콘과 텍스트를 하나의 요소로 읽도록 처리.

---

## 4. 영향 파일

`HITLApprovalSheet.swift`, `CommandPaletteEditor.swift`, `LibrarySheet.swift`
