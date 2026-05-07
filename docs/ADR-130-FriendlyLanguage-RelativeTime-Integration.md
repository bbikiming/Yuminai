# ADR-130 — 친화 언어 강화 + RelativeTime helper 통합 + SF Symbol 호환성 정책 회복

**날짜:** 2026-05-07  
**상태:** 완료  
**관련 ADR:** ADR-101, ADR-125, ADR-128, ADR-129  

---

## 배경

ADR-101에서 "P1 친화 언어 정책"을 수립했다. GUI 검수 결과, 이미 한국어화된 파일들에서 영어 원문이 8곳 잔존한다는 사실이 발견됐다. 동시에 ADR-125(P1-8)에서 도입된 `RelativeTime.swift` helper가 있음에도 3개 컴포넌트가 자체 함수를 중복 구현하고 있었다.

ADR-128 GUI 검수 중 사용자 환경에서 일부 SF Symbol 글리프 미렌더링 문제가 발견됐다. ADR-125에서 ADR-118(SF Symbol 정책)을 폐기했으나, macOS 26 minimum 환경이라도 시스템 글리프가 미설치될 수 있음이 실증됐다. 이를 직접 수정한 것이 ADR-129다.

본 ADR(ADR-130)은 이 세 가지 정리를 단일 커밋으로 통합한다.

---

## 1. 친화 언어 일괄 적용 (ADR-101 정책 — 영어 잔존 8곳)

| 파일 | 위치 | 수정 전 | 수정 후 |
|------|------|---------|---------|
| `HITLApprovalSheet.swift` | line 72 | `"HITL Approval Needed"` | `"확인이 필요해요"` |
| `HITLApprovalSheet.swift` | line 160 | `"Action"` | `"실행할 명령"` |
| `HITLApprovalSheet.swift` | line 179 | `"Diff Preview"` | `"변경사항 미리보기"` |
| `HITLApprovalSheet.swift` | line 234 | `"Reject"` | `"거절"` |
| `HITLApprovalSheet.swift` | line 237 | `"Approve"` | `"승인"` |
| `TelegramArtifactViewerSheet.swift` | line 95 | `"Diff Viewer"` | `"변경사항 보기"` |
| `CommandPaletteEditor.swift` | line 68 | `"Commands"` | `"명령어"` |
| `BotStatusDockView.swift` | line 75 | `"+N more"` | `"+N개 더"` |
| `BotStatusDockView.swift` | line 126 | `"queue:"` | `"대기:"` |
| `TelegramOnboardingWizard.swift` | line 125 | `"Step N"` (accessibilityLabel) | `"단계 N"` |

---

## 2. RelativeTime helper 통합

ADR-125에서 `Sources/YuminaiCore/RelativeTime.swift`에 `RelativeTime.format(_:now:)` helper를 도입했다. 그러나 3개 컴포넌트가 자체 `relativeTime(_:)` 함수를 계속 사용하고 있었다.

### 통합 전

```swift
// BotStatusDockView.swift (영어 m/h/d ago)
private func relativeTime(_ date: Date) -> String {
    let interval = Date().timeIntervalSince(date)
    if interval < 60 { return "방금" }
    if interval < 3600 { return "\(Int(interval / 60))m ago" }
    if interval < 86400 { return "\(Int(interval / 3600))h ago" }
    return "\(Int(interval / 86400))d ago"
}

// ChatContextCard.swift (영어 m/h/d ago)
private func relativeTime(_ date: Date) -> String { /* 동일 패턴 */ }

// ActivityFeedView.swift (한국어, 단 1주/1개월 구간 미지원)
private func relativeTime(_ date: Date) -> String {
    let interval = Date().timeIntervalSince(date)
    if interval < 60 { return "방금" }
    if interval < 3600 { return "\(Int(interval / 60))분 전" }
    if interval < 86400 { return "\(Int(interval / 3600))시간 전" }
    return "\(Int(interval / 86400))일 전"
}
```

### 통합 후

3개 파일 모두 자체 함수를 제거하고 `RelativeTime.format(date)` 호출로 교체:

```swift
private func relativeTime(_ date: Date) -> String {
    RelativeTime.format(date)
}
```

**효과:**
- 영어 m/h/d ago → 한국어 N분/시간/일 전
- 1주~1개월 구간 표현 추가 ("N주 전", "N개월 전") — ADR-125 P0-2 버그 수정 자동 적용
- 중복 구현 3 → 1 (helper 단일화)

---

## 3. ADR-129 — SF Symbol 호환성 P0 직접 수정 (통합 메모)

ADR-125에서 ADR-118(SF Symbol macOS 11 호환 정책)을 "ADR-125 P1-8"로 폐기했다. 그러나 ADR-128 검수 중 사용자 환경에서 일부 SF Symbol이 미렌더링되는 현상이 실증됐다.

### ADR-118 폐기 결정 일부 번복

macOS 26 minimum이라도 시스템 글리프 미설치 가능성이 있다. **새 SF Symbol 사용 시 실기기 검증 의무**를 복구한다.

후속 작업으로 ADR-134에서 SF Symbol lint rule 추가 예정.

### 교체된 SF Symbol (11개 파일, 18 위치)

| 이전 Symbol | 교체 Symbol | 사유 |
|-------------|-------------|------|
| `cube.box.fill` | `archivebox.fill` | macOS 12+ 전용, 미렌더링 확인 |
| `clock.badge.xmark` | `clock.arrow.circlepath` | macOS 12+ 전용 |
| `speedometer` | `gauge` | macOS 12+ 전용 |
| `exclamationmark.octagon.fill` | `exclamationmark.triangle.fill` | 일부 기기 미설치 |
| `sparkles.rectangle.stack` | `sparkles` | macOS 13+ 전용 |
| `circle.dotted.circle` | `circle.dashed` | macOS 13+ 전용 |
| `square.and.arrow.down.on.square` | `arrow.down.square.fill` | 미렌더링 확인 |
| `character.ko` | `globe` | macOS 12+ 전용 |

---

## 검증

```
swift build → Build complete! (0 errors, pre-existing warnings only)
swift test  → 1346 tests passed (0 failures, 205 suites)
```

---

## 후속 작업

- **ADR-131** — P1 sheet frame 정리 (HITLApprovalSheet 크기 최적화)
- **ADR-132** — Color literal 정리 (inline Color() → Theme.Color 통합)
- **ADR-134** — SF Symbol lint rule (신규 사용 시 macOS 11 fallback 검증 자동화)
