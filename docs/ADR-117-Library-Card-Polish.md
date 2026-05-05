# ADR-117 — 라이브러리 카드 폴리시 + MCP 로고 + 커뮤니티 자료 통합

**날짜**: 2026-05-04  
**상태**: 완료  
**기반 커밋**: 13efe09  

---

## 배경

사용자 요청 3건으로 구성된 라이브러리 UX 개선 이터레이션:

1. MCP 서버 카테고리 아이콘 누락 점검
2. 커뮤니티 자료 직접 진입점 추가 (기존: UserProfileSheet 5단 깊이)
3. 라이브러리 자료 카드 GUI 업그레이드

---

## 1. MCP 서버 아이콘 점검 결과

`CommunityResource.Category.mcp.icon` = `"plug.fill"` (cyan 계열)으로 정의되어 있으며,
`LibrarySheet.categoryIcon(_:)` 함수에서도 동일하게 `"plug.fill"` 반환.

전체 15개 카테고리 아이콘 매핑 (일관 확인):

| 카테고리 | SF Symbol | 색상 |
|---------|-----------|------|
| CLAUDE.md | `doc.text.fill` | accent |
| Claude Skill | `bolt.fill` | orange |
| 템플릿 | `square.grid.2x2.fill` | green |
| 디자인 가이드 | `paintbrush.fill` | purple |
| 워크플로우 | `arrow.triangle.2.circlepath` | blue |
| 시스템 설계 | `building.columns.fill` | indigo |
| 프롬프트 패턴 | `text.bubble.fill` | teal |
| 에디터 규칙 | `shield.fill` | red |
| **MCP 서버** | **`plug.fill`** | **cyan** |
| 웹 프레임워크 | `globe` | blue |
| 모바일 프레임워크 | `iphone` | pink |
| 3D 그래픽스 | `cube.fill` | purple |
| 백엔드 | `server.rack` | green |
| 데이터베이스 | `cylinder.fill` | orange |
| DevOps | `gearshape.2.fill` | gray |

누락 없음. 모든 카테고리가 LibrarySheet sidebar에서 일관되게 표시된다.

---

## 2. 커뮤니티 자료 직접 진입점

### 문제

기존 진입 경로: 사이드바 하단 `[사용자 아이콘]` → UserProfileSheet → 좌측 "커뮤니티 자료" 탭 클릭.
총 5단 인터랙션. 발견성 낮음.

### 결정

**사이드바에 직접 메뉴 항목 추가 + 독립 Sheet 신설.**

- 옵션 A(사이드바 메뉴) + 옵션 B(LibrarySheet 통합) 중 옵션 A 선택:
  - 사이드바 메뉴가 이미 라이브러리·번들 직접 진입 패턴을 쓰고 있음 (ADR-114, ADR-116)
  - LibrarySheet에 탭을 추가하면 "내 자료 관리" 맥락과 "커뮤니티 탐색" 맥락이 혼재
  - 독립 Sheet(CommunityResourcesSheet)로 wrap하면 진입점은 단일, 컨텍스트는 명확

### 변경 파일

| 파일 | 변경 내용 |
|------|-----------|
| `Sources/YuminaiApp/AppModel.swift` | `showCommunityResourcesSheet: Bool` 추가 |
| `Sources/YuminaiApp/CommunityResourcesSheet.swift` | **신규** — CommunityResourcesPanel wrap Sheet (860×640) |
| `Sources/YuminaiApp/RootView.swift` | `.sheet(isPresented: $bindable.showCommunityResourcesSheet)` + `onOpenCommunityResources` wire |
| `Sources/YuminaiUI/SidebarView.swift` | `onOpenCommunityResources` 프로퍼티/init 파라미터/메뉴 행 추가 |

### 사이드바 메뉴 순서 (변경 후)

```
새 워크스페이스  [+]
Telegram Hub    [paperplane.circle.fill]
커뮤니티 자료    [cube.box.circle.fill]   ← 신규
라이브러리       [books.vertical.circle.fill]
스택 번들        [shippingbox.circle.fill]
사용자 가이드    [questionmark.circle.fill]
설정             [gear]
```

---

## 3. 라이브러리 자료 카드 GUI 업그레이드

### 개선 항목

| # | 항목 | 이전 | 이후 |
|---|------|------|------|
| 1 | 카테고리 아이콘 | 22pt 단색, 배경 없음 | 44×44 RoundedRectangle + 카테고리 tint 12% 배경 + 20pt 아이콘 |
| 2 | 제목 | `.body.weight(.semibold)` | 동일 + `lineLimit(2)` 명시 |
| 3 | 메타 행 배치 | 아이콘·제목·메타 혼재 | 아이콘 박스 / 제목·메타 분리 VStack |
| 4 | 태그 +N 표시 | `prefix(5)` 후 `+N` | `prefix(4)` 후 `+N` (Capsule 배경 추가) |
| 5 | 추가일 표시 | 우상단 상대 시간만 | 구분선 아래 별도 행: `clock` 아이콘 + "N분 전" + "yyyy-MM-dd HH:mm" |
| 6 | 내용 보기 버튼 | 텍스트 링크만 | `eye.fill` 아이콘 + RoundedRect 배경 (accentMuted 12%) |
| 7 | 편집 버튼 | 텍스트 링크만 | `pencil` 아이콘 + surfaceHi 배경 |
| 8 | 삭제 버튼 | 텍스트 링크만 | `trash` 아이콘 + danger 8% 배경 + danger 25% outline |
| 9 | 카드 외형 | GroupBox(.automatic) | 직접 VStack + surface background + surfaceHi border + shadow(r=3) |
| 10 | `absoluteDate` 헬퍼 | 없음 | `yyyy-MM-dd HH:mm` 형식 추가 |

### 설계 원칙 준수

- SF Symbol 단색 (ADR-116 컬러 이모지 금지 계승)
- Theme.Radius / Theme.Spacing 일관
- 불변성 — 카드 뷰는 `item` 값 타입 기반, 상태 mutation 없음

---

## 4. 검증

```
swift build     → Build complete! (21.53s) — 에러 0
swift test      → 1232 tests passed        — 회귀 0
```

---

## 5. 후속 고려

- `CommunityResourcesSheet` 크기(860×640)는 현재 CommunityResourcesPanel이 `ScrollView` 없이 `VStack` 기반이므로 적정. 콘텐츠 증가 시 재조정 가능.
- LibrarySheet를 multi-tab(내 라이브러리 / 커뮤니티 / 번들 / GitHub)으로 통합하는 옵션 B는 ADR-118 이후 세션에서 재검토.
- 라이브러리 카드 hover elevation(shadow) 효과는 macOS `.onHover` 기반으로 별도 추가 가능 (현재 정적 shadow 적용).
