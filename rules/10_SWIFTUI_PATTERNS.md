# SwiftUI Patterns (Yuminai)

> SwiftUI on macOS 26 + Liquid Glass.

## 상태 관리

### `@Observable` 우선 (Swift 5.9+/6.0)

```swift
// GOOD
@Observable
final class WorkspaceViewModel {
    var workspaces: [Workspace] = []
    var selected: Workspace.ID?
    
    func load() async { ... }
}

// 사용
struct SidebarView: View {
    @Bindable var viewModel: WorkspaceViewModel
    var body: some View { ... }
}
```

`ObservableObject + @Published` 신규 추가 금지. 기존 코드는 점진 마이그레이션.

### `@State`는 view-local만

- 토글, 드래그 오프셋, 모달 표시 여부 — OK
- 비즈니스 데이터 — `@Observable` 모델로

### `@Environment` 활용

```swift
// 의존성 주입은 Environment로
private struct ClaudeAdapterKey: EnvironmentKey {
    static let defaultValue: ClaudeAdapter = .live
}

extension EnvironmentValues {
    var claudeAdapter: ClaudeAdapter {
        get { self[ClaudeAdapterKey.self] }
        set { self[ClaudeAdapterKey.self] = newValue }
    }
}
```

## View 구조

### 작게 분해

```swift
// BAD: 200줄짜리 ChatView
struct ChatView: View {
    var body: some View {
        VStack {
            // 헤더 30줄
            // 메시지 리스트 80줄
            // 입력창 50줄
            // 슬래시 명령 자동완성 40줄
        }
    }
}

// GOOD: 분리
struct ChatView: View {
    var body: some View {
        VStack(spacing: 0) {
            ChatHeader()
            ChatMessageList()
            ChatComposer()
        }
    }
}
```

### 1 view = 100줄 이내, 200줄 초과 금지

분리 기준:
- 독립적 의미 단위
- 다른 view에서 재사용 가능성
- 자체 상태 보유

## Liquid Glass (macOS 26)

```swift
// 기본 글래스 위에 콘텐츠
.glassEffect(.regular)
.glassEffect(.regular.tint(.blue.opacity(0.1)))

// 컨테이너 전체에 글래스
GlassEffectContainer {
    HStack { ... }
}
```

- 사이드바, 툴바, 패널 분할 시 자연스럽게 활용
- 채팅 메시지 자체엔 사용 자제 (가독성)
- 기본 윈도우 chrome은 `WindowStyle.hiddenTitleBar` + 자체 툴바 권장

## 디자인 토큰

`YuminaiUI/Theme.swift`의 `Theme` namespace 사용:

```swift
Text("Hello")
    .font(Theme.Typography.body)
    .foregroundStyle(Theme.Color.label)
    .padding(Theme.Spacing.md)
```

직접 `.font(.system(size: 13))` 사용 금지. 토큰을 통해서만.

## 비동기 데이터

```swift
struct WorkspaceList: View {
    @State private var viewModel = WorkspaceViewModel()
    
    var body: some View {
        List(viewModel.workspaces) { ... }
            .task {
                await viewModel.load()
            }
            .refreshable {
                await viewModel.load()
            }
    }
}
```

- 진입 시 로드: `.task` (cancel 자동)
- Pull to refresh: `.refreshable`
- `onAppear` + `Task { }`: 신규 사용 금지 (cancel 안 됨)

## 네비게이션 (macOS)

- `NavigationSplitView` (3 column까지) — 메인 셸 후보
- `NavigationStack` — 디테일 push가 있을 때
- `Sheet`, `.popover`, `.inspector` — 보조 UI

## 접근성

- 모든 인터랙티브 요소는 `.accessibilityLabel(_:)`
- 색 대비 WCAG AA (4.5:1)
- 한국어 + 영어 라벨 모두 자연스러워야 함
- VoiceOver로 한 번 돌려보고 통과해야 PR 머지 가능

## 금지 사항

- `UIViewRepresentable` (iOS API) — `NSViewRepresentable` 사용
- `Color.red` 등 시스템 색 직접 — `Theme.Color.*`
- `GeometryReader` 남발 — 진짜 필요한 곳만 (성능)
- `.frame(minWidth:minHeight:idealWidth:idealHeight:maxWidth:maxHeight:alignment:)` 같은 6-arg frame — 분리하라
