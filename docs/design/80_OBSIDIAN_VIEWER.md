# 80_OBSIDIAN_VIEWER — 옵시디언 Vault 연동 + Notion급 마크다운 뷰어

> **목적**: Obsidian Vault의 `.md` 파일을 Yuminai 우측 Inspector에서 Notion/Obsidian급 퀄리티로 렌더링.
> 사용자 작업 중 노트 참조 흐름을 끊김 없이.
>
> **작성일**: 2026-05-01
> **선행 명세**: `docs/prd/50_INTEGRATIONS.md` (Obsidian, v0.2 예정 → 일부 앞당김)

---

## 1. 사용자 흐름 (Persona)

| 시점 | 행동 | 시각 결과 |
|---|---|---|
| 작업 중 노트 참조 필요 | 우측 Inspector "노트" 탭 클릭 | Vault 트리 + 마지막 본 노트 |
| 노트 검색 | 트리 상단 검색창 입력 | 매칭 항목 highlight + 펼침 |
| 노트 본문 읽기 | 트리에서 노트 클릭 | 우측 panel에 마크다운 렌더링 |
| 채팅에 노트 인라인 주입 (v0.2.5) | 노트 우상단 "Claude에 보내기" | Composer에 `@<path>` 첨부 |
| Vault 외부 위치 클릭 | "Obsidian에서 열기" 버튼 | `obsidian://open?vault=X&file=Y` 호출 |

---

## 2. 기술 결정

### 2.1 Vault 접근 방식

**결정**: 파일 시스템 직접 접근 (FileManager).
- Obsidian CLI (`obsidian-cli` npm) 별도 의존성 없음 — 단순 `.md` 파일 모음
- 외부 액션(노트를 Obsidian 앱에서 열기)은 `obsidian://` URL scheme로

### 2.2 마크다운 렌더링 라이브러리

**결정**: `swift-markdown-ui` (gonzalezreal) 도입.

검토:
| 옵션 | 장단 |
|---|---|
| `AttributedString(markdown:)` — Apple 네이티브 | basic 만 (헤더 X, 코드블록 X, 테이블 X) — Notion급 불가능 |
| `swift-markdown` (Apple swift-markdown) | 파싱만, 렌더러는 자체 작성 — 100시간+ |
| **`swift-markdown-ui`** (채택) | Notion급 styling, 코드/테이블/task list 지원, 1.5k stars, MIT |
| 자체 파서 + 렌더러 | 비현실적 노력 |

근거: Notion급 = 코드 블록 + 테이블 + task list + blockquote + 이미지 + 링크 모두 필요. swift-markdown-ui가 standard 모두 지원 + theme 시스템.

### 2.3 외부 의존성 추가 정책 변경 (ADR-021)

지금까지 외부 SPM 의존성 0개 유지. 이번에 1개 추가.

근거:
- 마크다운 렌더링은 brand-new 작업, 자체 작성 비현실
- 라이브러리 신뢰도 높음 (Apple swift-markdown 기반)
- `Theme.MarkdownStyle` 자체 스타일 적용 가능 (lock-in 약함)

---

## 3. UI 위치 — Inspector를 탭 구조로

```
Inspector (우측 패널, 280px)
├── [Context] [Notes]  ← Top tab segmented
└── 본문:
    ├── Context 탭 (기존 — 활성 설정 + 컨텍스트/토큰/비용/도구)
    └── Notes 탭 (신규):
        ├── 검색창 (상단)
        ├── 트리 (중간, scroll)
        └── 마지막 본 노트 미리보기 (하단, 작은 fold)

또는 Notes 탭은 별도 layout:
├── 검색창
├── breadcrumb (현재 노트 경로)
└── 본문 영역 (탭 활성 시 풀):
    ├── 트리 (default 모드)
    └── 또는 노트 본문 (노트 선택 시)
```

**최종 결정**:
- Inspector top에 tab segmented (Context | Notes)
- Notes 탭 활성 시 — 검색창 + 트리 (기본) / 노트 본문 (선택 시 트리 위로 노트 표시)
- 노트 본문 위 breadcrumb (← 트리로 / Obsidian에서 열기)

---

## 4. 컴포넌트 설계

### 4.1 ObsidianVault (YuminaiObsidian 모듈)

```swift
public actor ObsidianVault {
    public let rootURL: URL

    public init(rootURL: URL)
    public func tree() async throws -> [VaultNode]
    public func read(_ relativePath: String) async throws -> Note
    public func search(query: String) async throws -> [Note]
    public func openInObsidian(_ relativePath: String)
}

public enum VaultNode: Sendable {
    case folder(name: String, path: String, children: [VaultNode])
    case note(name: String, path: String, lastModified: Date)
}

public struct Note: Sendable {
    public let path: String          // vault root 기준 상대 경로
    public let title: String
    public let body: String          // markdown 원문
    public let frontmatter: [String: String]
    public let lastModified: Date
}
```

### 4.2 MarkdownViewer (YuminaiUI)

```swift
public struct MarkdownViewer: View {
    public let markdown: String
    public init(markdown: String)
    public var body: some View {
        Markdown(markdown)
            .markdownTheme(.yuminai)  // 우리 테마
            .markdownCodeSyntaxHighlighter(.yuminai)  // 코드 하이라이트
            .padding(...)
    }
}
```

`.yuminai` 테마는 swift-markdown-ui의 `Theme` 정의:
- 헤더: `Theme.Typography.title` 톤 + 적절한 크기 차이 (h1=22, h2=18, h3=16, h4-6=14)
- 본문: `Theme.Typography.body` (sans 14)
- 인라인 코드: `Theme.Color.inlineCode` 배경 + mono
- 코드 블록: 어두운 배경 + 작은 padding + monospace 12
- 인용: 좌측 2px accent border + 어두운 muted bg
- 링크: accent 색
- 리스트/체크박스/테이블: 시스템 표준 + 우리 색

### 4.3 NoteTreeView

```swift
public struct NoteTreeView: View {
    public let nodes: [VaultNode]
    @Binding public var searchQuery: String
    @Binding public var selectedPath: String?
    public let onSelect: (Note) -> Void

    public var body: some View {
        VStack(spacing: 0) {
            searchBar
            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach(filteredNodes) { node in
                        VaultNodeRow(node: node, ...)
                    }
                }
            }
        }
    }
}
```

각 row는 expand/collapse 가능 (folder), 클릭 시 onSelect 호출.

### 4.4 NotesInspectorTab

```swift
struct NotesInspectorTab: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        if let vault = appModel.obsidianVault {
            VStack(spacing: 0) {
                // 노트 선택됐으면 본문, 아니면 트리
                if let note = appModel.selectedNote {
                    notebreadcrumb(note)
                    MarkdownViewer(markdown: note.body)
                } else {
                    NoteTreeView(...)
                }
            }
        } else {
            EmptyVaultView()  // "설정에서 Vault 경로를 입력하세요"
        }
    }
}
```

---

## 5. AppModel 확장

```swift
@MainActor
@Observable
final class AppModel {
    // 기존 + 신규:
    public var inspectorTab: InspectorTab = .context
    public var obsidianVault: ObsidianVault?  // Vault 경로 설정 시 init
    public var vaultTree: [VaultNode] = []
    public var selectedNote: Note?
    public var noteSearchQuery: String = ""

    public func loadVaultTree() async { ... }
    public func selectNote(at path: String) async { ... }
    public func clearSelectedNote() { selectedNote = nil }
    public func openCurrentNoteInObsidian() { ... }
}

public enum InspectorTab: String, CaseIterable {
    case context, notes
}
```

Vault 경로 변경 시 `obsidianVault` 재구성. `loadVaultTree()` 자동 호출.

---

## 6. 사용성 안내

| 상황 | 안내 |
|---|---|
| Vault 경로 미설정 | "설정 → 일반에서 Obsidian Vault 경로를 입력하세요." + [설정 열기] 버튼 |
| Vault 경로 잘못됨 | "Vault 폴더를 찾을 수 없어요: \(path)" |
| 노트 0개 | "이 Vault에 .md 노트가 없네요." |
| 검색 결과 없음 | "‘\(query)’와 매칭되는 노트가 없어요." |
| 마크다운 렌더링 실패 | raw text fallback + "원본으로 표시 중" 작은 라벨 |

---

## 7. 단계별 구현 (이번 라운드 vs 다음)

### 이번 라운드
1. swift-markdown-ui Package.swift 추가
2. YuminaiObsidian 신규 모듈 (Vault + Note + 트리 indexing)
3. MarkdownViewer 컴포넌트 (yuminai theme)
4. NoteTreeView (검색 + 트리)
5. Inspector tab 구조 (Context | Notes)
6. AppModel 확장
7. RootView 통합
8. 빌드/검증

### 다음 라운드
- 채팅 @note 인라인 주입 (Composer에 attached note as inline content)
- 노트 즐겨찾기 (별 표시)
- 노트 편집 모드 (지금은 read-only)
- Wiki 링크 [[Page]] 렌더링 + 클릭 시 이동
- 임베드 ![[file]] 렌더링
- frontmatter 파싱 + 표시
- file watcher (Vault 변경 자동 갱신)

---

## 8. ADR-021 — swift-markdown-ui 외부 의존성 도입

- 이전 정책: 외부 SPM 의존성 0 유지
- 변경: 마크다운 렌더링 1개 도입
- 근거: 자체 작성 비현실 + 신뢰도 높은 라이브러리 + lock-in 약함
- 위험: 빌드 시간 증가, 라이브러리 업데이트 추적 필요
- 완화: `MarkdownViewer`로 wrapping → 라이브러리 교체 시 한 곳만 변경
