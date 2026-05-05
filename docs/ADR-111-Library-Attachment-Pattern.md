# ADR-111 — 자료 라이브러리 + 대화 첨부 패턴

**상태**: 구현 완료 (2026-05-04)
**배경**: ADR-109 커뮤니티 자료 "워크스페이스에 적용" 버튼이 네트워크 오류 반환

---

## 1. 배경

### 문제 1: 네트워크 오류

ADR-109에서 구현된 "[워크스페이스에 적용]" 버튼은 커뮤니티 자료를 다운로드해 워크스페이스 CLAUDE.md 또는 `.harness/skills/`에 직접 저장했다. 그러나 기존 rawURL들이 모두 404를 반환해 사용자가 "네트워크 오류"만 보게 됐다.

### 문제 2: UX 모호성

기존 "워크스페이스에 적용" 모델은 어느 워크스페이스에 적용되는지, 어떤 대화에서 사용되는지 명확하지 않았다. 사용자가 자료를 다운로드 → 바로 CLAUDE.md에 덮어씌우는 방식은 돌이키기 어렵고 경계도 불명확했다.

---

## 2. 새 UX 모델: 라이브러리 → 첨부

```
커뮤니티 자료 패널
  ↓ [라이브러리에 추가]
라이브러리 (전역 저장소)
  ↓ Composer의 📚 버튼 → LibraryPickerPopover
메시지 첨부 (명시적 전달)
  ↓ 전송 시 content prepend
LLM 컨텍스트
```

핵심 원칙: **사용자가 어느 대화에 어떤 자료를 전달할지 명시적으로 선택**한다.

---

## 3. LibraryItem 모델

**파일**: `Sources/YuminaiCore/LibraryItem.swift`

```swift
public struct LibraryItem: Sendable, Codable, Hashable, Identifiable {
    public let id: UUID
    public var displayName: String
    public let category: CommunityResource.Category
    public let source: Source
    public var content: String          // markdown 본문
    public var tags: [String]
    public let addedAt: Date
    public var notes: String

    public var byteSize: Int { content.utf8.count }
    public var byteSizeDisplay: String  // "1.2 KB", "34 B" 등

    public enum Source: Sendable, Codable, Hashable {
        case community(resourceId: UUID, originalURL: URL?)
        case userImport(originalURL: URL)
        case userText
    }
}
```

### 디스크 저장 정책

```
~/Library/Application Support/Yuminai/library/
   <id>.md        ← LibraryItem 본문 (markdown)
```

- `AppPreferences.libraryItems` 배열에 메타데이터 저장 (Codable)
- 디스크에 본문 파일 별도 저장 (재생성 지원)
- backward-compat: `decodeIfPresent ?? []`

---

## 4. AppPreferences 확장

`AppPreferences.libraryItems: [LibraryItem] = []` (ADR-111)

기존 사용자: 빈 배열로 시작 (onboarding 불필요).

---

## 5. AppModel 라이브러리 메서드

**파일**: `Sources/YuminaiApp/AppModel.swift`

| 메서드 | 설명 |
|--------|------|
| `addToLibraryFromCommunity(_:)` | CommunityResource 다운로드 → LibraryItem 생성 |
| `addToLibraryFromURL(_:displayName:category:)` | URL 다운로드 → LibraryItem 생성 |
| `addToLibraryFromText(_:displayName:category:tags:)` | 텍스트 입력 → LibraryItem 생성 |
| `removeLibraryItem(_:)` | 삭제 (디스크 + preferences) |
| `updateLibraryItem(_:)` | 수정 (displayName / notes / tags) |
| `attachmentURL(for:)` | 디스크 URL 반환 (없으면 재생성) |
| `isInLibrary(_:)` | 커뮤니티 자료 중복 여부 확인 |
| `attachLibraryItem(_:)` | Composer에 첨부 |
| `removeLibraryItemAttachment(_:)` | Composer 첨부 제거 |
| `clearLibraryItemAttachments()` | 전체 제거 |

### downloadRawContent 개선 (ADR-111)

- timeout 30s → 60s (큰 파일 대비)
- 에러 타입 강화: networkError(Error) / httpErrorWithURL(URL, Int) / invalidEncoding
- 에러 메시지에 URL + suggestion 포함

---

## 6. CommunityResourcesPanel 변경

**파일**: `Sources/YuminaiApp/CommunityResourcesPanel.swift`

| 변경 전 | 변경 후 |
|---------|---------|
| [워크스페이스에 적용] | [라이브러리에 추가] |
| 워크스페이스 없으면 비활성 | 항상 활성 (라이브러리는 워크스페이스 독립) |
| 이미 적용됨 표시 없음 | ✅ "라이브러리에 추가됨" + 비활성 |
| rawURL 없으면 버튼 없음 | "직접 URL 입력 후 추가 가능" 힌트 |
| 헤더에 설명만 | 헤더에 [라이브러리 보기] 버튼 추가 |
| 커스텀 URL → 워크스페이스 적용 | 커스텀 URL → 라이브러리에 추가 |

---

## 7. LibrarySheet 디자인

**파일**: `Sources/YuminaiApp/LibrarySheet.swift`

macOS Settings.app 패턴:

```
┌────────────┬─────────────────────────────────────┐
│ 자료 라이브러리 │  [검색…] [URL로 추가] [텍스트로 추가] [×] │
│────────────│─────────────────────────────────────│
│ 전체 (N)   │                                     │
│ CLAUDE.md  │  [항목 카드]                         │
│ Skill      │   아이콘 + 이름 + 카테고리 배지         │
│ 템플릿     │   출처 + 바이트 크기 + 추가일           │
│            │   notes (있으면)                     │
│            │   tags chips                        │
│            │   [내용 보기] [편집]  [삭제]          │
│            │                                     │
│  N개 항목   │                                     │
└────────────┴─────────────────────────────────────┘
```

보조 Sheet:
- `AddLibraryTextSheet`: 텍스트 직접 입력 (이름 + 카테고리 + 내용 + 태그)
- `AddLibraryURLSheet`: URL 입력 → 다운로드 → 추가
- `LibraryItemContentSheet`: 항목 내용 보기 (읽기 전용, textSelection 활성)
- `EditLibraryItemSheet`: 이름·notes·tags 편집

---

## 8. LibraryPickerPopover (Composer 연동)

**파일**: `Sources/YuminaiUI/LibraryPickerPopover.swift`

Composer footer의 "📚" 버튼 클릭 시 표시:

```
┌────────────────────┐
│ 📚 라이브러리 첨부  [×] │
│ [검색…]            │
│ 전체 CLAUDE.md Skill │
│────────────────────│
│ 📄 자료 A  1.2KB   │
│ ⚡ 자료 B  3.4KB ✓ │ ← 이미 첨부됨
│ ...                │
│────────────────────│
│ 클릭하면 메시지에 첨부  │
└────────────────────┘
```

- 클릭하면 Composer에 칩(chip) 추가 + popover 닫기
- 이미 첨부된 항목: ✓ 표시 + 비활성

---

## 9. Composer 라이브러리 첨부

**파일**: `Sources/YuminaiUI/Composer.swift`

추가된 props:
```swift
public let attachedLibraryItems: [LibraryItem]
public let onRemoveLibraryItem: (LibraryItem) -> Void
public let onAttachLibrary: (() -> Void)?
```

UI 구조 (위→아래):
1. 라이브러리 첨부 chips (`LibraryAttachmentChip`: 📚 아이콘 + 이름)
2. 파일 첨부 chips (기존)
3. git meta row (기존)
4. TextEditor (기존)
5. Footer: [통합 picker] [mode] [effort] ... [📎] [📚] [note] ... [전송]

---

## 10. 메시지 전송 시 처리

`sendMessage()` 안에서 첨부된 라이브러리 항목들을 메시지 앞에 prepend:

```
--- 첨부 자료: <displayName> ---
<content>
---

<원본 사용자 메시지>
```

- LLM이 자료를 먼저 읽고 참고할 수 있도록 메시지 앞에 위치
- 전송 후 `attachedLibraryItems = []` 자동 클리어

---

## 11. 큐레이션 자료 검증 결과 (2026-05-04)

`curl -sI` 로 각 rawURL을 실제 검증:

| # | 자료명 | rawURL 상태 | 처리 |
|---|--------|-------------|------|
| 1 | Anthropic Cookbook CLAUDE.md | ✅ 200 OK | rawURL 경로 수정 (`/main/CLAUDE.md`) |
| 2 | Cline .clinerules | ❌ 404 | rawURL nil (GitHub 직접 확인 안내) |
| 3 | awesome-claude-code | rawURL nil 이었음 | 유지 |
| 4 | TDD Skill (claude-code-skills) | ❌ 404 (리포 없음) | rawURL nil |
| 5 | SwiftUI Skill (claude-code-skills) | ❌ 404 (리포 없음) | rawURL nil |
| 6 | 보안 CLAUDE.md | ❌ 404 | rawURL nil |
| 7 | Next.js 템플릿 | rawURL nil 이었음 | 유지 |
| +8 | Anthropic Quickstarts CLAUDE.md | ✅ 200 OK | **신규 추가** |

살아있는 rawURL (자동 다운로드 가능):
1. `https://raw.githubusercontent.com/anthropics/anthropic-cookbook/main/CLAUDE.md`
2. `https://raw.githubusercontent.com/anthropics/anthropic-quickstarts/main/CLAUDE.md`

나머지 6개는 rawURL nil → [라이브러리에 추가] 버튼 대신 "직접 URL 입력 후 추가 가능" 힌트 표시.

---

## 12. 신규·수정 파일 목록

| 파일 | 타입 | 변경 |
|------|------|------|
| `Sources/YuminaiCore/LibraryItem.swift` | Swift | 신규 (LibraryItem 모델 + 오류) |
| `Sources/YuminaiCore/AppPreferences.swift` | Swift | 수정 (`libraryItems` 필드 추가) |
| `Sources/YuminaiCore/CommunityResource.swift` | Swift | 수정 (URL 검증 후 갱신 + 에러 강화) |
| `Sources/YuminaiApp/AppModel.swift` | Swift | 수정 (라이브러리 관리 메서드 + sendMessage) |
| `Sources/YuminaiApp/CommunityResourcesPanel.swift` | Swift | 수정 ([라이브러리에 추가] 전환) |
| `Sources/YuminaiApp/LibrarySheet.swift` | Swift | 신규 (라이브러리 sheet + 서브 sheet들) |
| `Sources/YuminaiUI/LibraryPickerPopover.swift` | Swift | 신규 (Composer 연동 popover) |
| `Sources/YuminaiUI/Composer.swift` | Swift | 수정 (라이브러리 첨부 props + UI) |
| `Sources/YuminaiApp/RootView.swift` | Swift | 수정 (sheet binding + Composer wiring) |
| `Tests/YuminaiCoreTests/LibraryItemTests.swift` | Swift | 신규 (13 tests) |
| `docs/ADR-111-Library-Attachment-Pattern.md` | Markdown | 신규 (이 문서) |

---

## 13. 수동 검증 가이드

```bash
# 1. 빌드
cd /Users/bbikiming/Documents/vibe_coding/Yuminai
swift build

# 2. 테스트
swift test

# 3. 앱 빌드 (선택)
./App/build_app_bundle.sh && ditto dist/Yuminai.app /Applications/Yuminai.app
```

앱에서 확인:
1. 프로필 → 커뮤니티 자료 → "[라이브러리에 추가]" 버튼 클릭 (Anthropic Cookbook, Quickstarts)
2. 성공 토스트 후 ✅ "라이브러리에 추가됨" 표시 확인
3. 헤더의 "[라이브러리 보기]" 또는 메뉴에서 LibrarySheet 열기
4. 항목 카드 확인 (이름·카테고리·바이트·출처·날짜)
5. [내용 보기] / [편집] / [삭제] 확인
6. Composer footer의 "📚" 버튼 클릭 → LibraryPickerPopover 표시
7. 항목 클릭 → 라이브러리 chip 생성 (📚 아이콘)
8. 메시지 전송 → 전송 내용에 "--- 첨부 자료 ---" 섹션 포함 확인
