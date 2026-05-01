# 81_NOTES_ENHANCEMENTS — 노트 기능 7종 상세 명세

> **목적**: ADR-021 (Obsidian Vault + 마크다운 뷰어) 위에 7개 enhancement를 추가.
> 의존성 순서대로 구현 후 통합 검증.
>
> **작성일**: 2026-05-01
> **선행**: `80_OBSIDIAN_VIEWER.md`

---

## 1. Frontmatter 표시

### 결정
노트 본문 위(MarkdownViewer 헤더 영역)에 frontmatter 메타를 시각화.

### 명세
```
[노트 헤더]
├── 제목 (h1 톤, frontmatter.title 또는 파일명)
├── 부제 (옵션, frontmatter.subtitle)
├── 메타 row:
│   ├── tags (pill — accent muted bg, 클릭 시 검색 필터)
│   ├── date (`📅 2026-05-01`)
│   ├── 기타 키:값 (회색 작은 글)
└── divider
```

### 토큰
- 제목: `Theme.Typography.title` (17 semibold) — 마크다운 h1과 분리 (frontmatter title이 별도)
- tag pill: `bg=accentMuted`, `fg=accent`, `radius=pill`, `padding H 8 V 2`, `font=micro`
- 메타 라벨: `font=small`, `fg=textSecondary`

### 동작
- frontmatter 비어있으면 헤더 자체 미표시 (본문만)
- title 없으면 파일명을 제목으로
- tags는 쉼표/공백 분리: `tags: a, b, c` 또는 `[a, b, c]` 모두 허용

---

## 2. File Watcher

### 결정
**FSEventStream** (CoreServices) 경량 wrapper. 단일 actor + AsyncStream.

### 명세
```swift
public actor VaultWatcher {
    public init(rootURL: URL, debounce: Duration = .milliseconds(800))
    public var changes: AsyncStream<Set<String>> { get }  // 변경된 path들
    public func start() async
    public func stop() async
}
```

### 동작
- FSEventStream으로 root + 모든 하위 폴더 감시 (`kFSEventStreamEventFlagItemModified`, `Created`, `Removed`)
- 800ms debounce → 변경된 상대 경로 set으로 emit
- AppModel이 changes 구독:
  - 트리 자동 reload
  - 현재 보고 있는 노트가 변경되면 reload (단, 편집 모드 시 충돌 처리 §6)

### Lifecycle
- `setupObsidianVault()` 안에서 새 watcher 생성 + start
- vault 변경 시 이전 watcher stop → 새 watcher start
- 앱 종료 시 자동 stop (deinit)

### Sandbox
- App sandbox OFF (이미 ADR-003) → FSEvents 자유롭게 사용 가능

---

## 3. 본문 검색 (FTS)

### 결정
**Lazy in-memory** 검색. SwiftData FTS 미지원이므로 자체 구현. 큰 Vault(1000+) 부담 회피 위해 lazy.

### 명세
```swift
extension ObsidianVault {
    /// 파일명 + 본문 매칭. concurrent file read.
    public func searchFullText(_ query: String, limit: Int = 50) async throws -> [SearchHit]
}

public struct SearchHit: Sendable, Identifiable {
    public let path: String
    public let title: String
    public let matchedLine: String?  // 본문 매칭 시 컨텍스트 (앞뒤 30자)
    public let matchSource: MatchSource  // .filename | .body
}
```

### 알고리즘
1. 트리에서 모든 .md path 수집
2. 각 path를 concurrent 그룹으로 read + grep
3. 매칭된 첫 라인 + 컨텍스트 추출
4. limit개 수집 후 반환

### UI
- NoteTreeView 검색창 우측에 toggle: `[파일명] [+본문]`
- `+본문` 활성 시 SearchHit 표시 (회색 작은 글로 매칭 라인)

---

## 4. Wiki 링크 `[[Page]]`

### 결정
**Preprocessing** — 마크다운 렌더링 전에 `[[X]]` → `[X](yuminai-note://X)` 변환. swift-markdown-ui가 일반 link로 렌더. 클릭 시 우리 URL handler가 인터셉트.

### 명세
```swift
public enum WikiLinkPreprocessor {
    /// `[[Page]]` → `[Page](yuminai-note://Page)`
    /// `[[Page|Display]]` → `[Display](yuminai-note://Page)`
    public static func process(_ markdown: String) -> String
}
```

### URL Handler
SwiftUI `.environment(\.openURL)` override:
```swift
.environment(\.openURL, OpenURLAction { url in
    if url.scheme == "yuminai-note" {
        let page = url.host ?? url.path.trimmingCharacters(in: .init(charactersIn: "/"))
        Task { await appModel.openNoteByName(page) }
        return .handled
    }
    return .systemAction
})
```

### 노트 이름 → path 해석
- AppModel에 `findNoteByName(_:)` — vaultTree에서 매칭하는 첫 노트 path 반환
- 못 찾으면 toast/alert "‘\(name)’ 노트를 찾을 수 없어요"

### 정규식
```
\[\[([^\]|]+)(\|([^\]]+))?\]\]
group 1 = page name
group 3 = display (옵션)
```

---

## 5. 이미지 임베드 `![[image]]`

### 결정
**Preprocessing** — `![[image.png]]` → `![](file:///vault/image.png)`. swift-markdown-ui가 NetworkImage로 로드.

### 명세
- 확장자 화이트리스트: `png, jpg, jpeg, gif, svg, webp, pdf`
- 그 외 (예: `![[Note]]`) → 노트 임베드는 v0.3 (현재는 wiki link로 fallback)
- 절대 경로 변환: `image.png` → vault root 기준

### 노트 임베드 (`![[Note]]`)
- v0.3 보류. 현재는 `![[Note]]`를 일반 wiki link `[[Note]]`로 fallback (preprocessing 분기)

---

## 6. 노트 편집 모드

### 결정
**보기/편집 toggle** + `⌘S` 저장 + 외부 변경 충돌 감지.

### 명세
```swift
@MainActor @Observable
extension AppModel {
    public var isEditingNote: Bool
    public var editingDraft: String  // raw markdown
    public var noteIsDirty: Bool  // draft != original

    public func startEditingNote()
    public func saveNote() async
    public func discardEdits()
}
```

### UI
- 노트 헤더 우측에 "보기" / "편집" toggle (segmented)
- 편집 모드: TextEditor 풀 너비, font mono 13
- 변경 시 `noteIsDirty = true`, 헤더에 "● 저장 안 됨" 표시
- `⌘S` → 저장 → file write → noteIsDirty = false
- 보기 모드 복귀 시 unsaved 확인 alert

### 충돌 처리
- 편집 모드일 때 file watcher가 같은 노트 변경 감지 → toast "외부에서 변경됨. ⌘S로 덮어쓰거나 [다시 불러오기]로 갱신" + 버튼

---

## 7. 채팅 `@note` 주입

### 결정
**Composer attachment 재사용** — 노트 = 파일 첨부와 동일 메커니즘. 추가 UI: 노트 picker.

### 명세
- Composer footer에 "📓 노트" 버튼 추가 (📎 첨부 옆)
- 클릭 시 popover — NoteTreeView (간소화 버전, 단일 선택)
- 노트 선택 → 그 노트의 절대 경로를 `attachedFiles`에 추가
- send 시 기존 `@<path>` 메커니즘으로 prompt에 prepend

### 대안 검토
- ❌ 본문 inline (토큰 폭발 위험)
- ✅ path mention (Claude가 Read 도구로 — 일관)

### NotePicker (popover)
```swift
public struct NotePickerPopover: View {
    let vault: ObsidianVault?
    let vaultTree: [VaultNode]
    @Binding var query: String
    let onSelect: (URL) -> Void
    let onClose: () -> Void
}
```

NoteTreeView 재사용하되 select 콜백을 path → URL 변환.

---

## 8. UI/UX 검증 매트릭스 (최종)

| 영역 | 항목 | 검증 |
|---|---|---|
| 색 | accent (시안) | send 버튼, sidebar selected, streaming, link, tag pill |
| 색 | textTertiary 대비 | 11~12px 한정, body 14px엔 사용 X |
| 폰트 | sans 본문 + mono code/통계 | 일관 |
| 인터랙션 | 모든 button hover/press | scale + bg 변화 |
| 인터랙션 | popup (PickerMenu, NotePicker) | popover 정상 위치 |
| 라이팅 | 친화 한글 | placeholder/empty/error 모두 |
| 반응형 | compact (<760) | sidebar overlay, inspector 강제 hidden |
| 반응형 | medium (760-1080) | sidebar inline, inspector 강제 hidden |
| 반응형 | regular (1080-1440) | 전부 inline |
| 반응형 | wide (>=1440) | 전부 |
| 노트 | frontmatter title/tags 표시 | tag pill 시안 톤 |
| 노트 | file watcher 외부 변경 감지 | 트리 자동 갱신 |
| 노트 | 검색 — 파일명 / +본문 | 매칭 라인 컨텍스트 |
| 노트 | wiki link 클릭 | 다른 노트로 이동 |
| 노트 | 이미지 임베드 표시 | 인라인 로드 |
| 노트 | 편집 모드 + ⌘S | 저장 후 보기 복귀 |
| 채팅 | @note 첨부 | path mention prepend |
| 키보드 | ⌘N/⌘1~9/⌘D/⌘,/⌘⌥1/⌘⌥I | 동작 |
| Settings | 5탭, .formStyle(.grouped), 한글 | 정렬 ok |

---

## 9. 단계별 구현 순서 (의존성)

1. **Frontmatter 표시** (이미 파싱됨, UI만) — 단순
2. **File watcher** (자체 actor)
3. **본문 검색** (Vault에 메서드 추가)
4. **Wiki 링크 + 임베드 preprocessing** (별도 module 함수)
5. **편집 모드** (AppModel state + UI toggle + file write)
6. **@note 주입** (Composer 통합)
7. **단위 테스트** (각 기능별)
8. **통합 빌드/실행/검증**

---

## 10. 비범위 (이번 라운드)

- 노트 임베드 ![[Note]] (이미지만, 노트 임베드는 v0.3)
- 본문 FTS index 영속 (현재 lazy in-memory)
- collaborative editing
- 노트 생성/삭제 (편집만)
- frontmatter 편집 UI (raw 마크다운으로만)
