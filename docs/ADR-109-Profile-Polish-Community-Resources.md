# ADR-109 — Profile UI 폴리시 + GitHub 인기 CLAUDE.md / Skills 자료 통합

**날짜**: 2026-05-04
**상태**: 구현 완료
**관련 ADR**: ADR-108 (Profile Real Injection UI Redesign)

---

## 1. 배경

사용자 신고 및 UX 검토에서 두 가지 문제가 식별됐다:

1. **좌측 SNB(sidebar) 반응형 오류**: HStack 내 sidebar에 명시적 `frame(width:)` 지정이 없어, content 영역이 GeometryReader 등으로 크기가 변할 때 sidebar가 함께 흔들리는 현상 발생.
2. **입력 영역 UX 퀄리티 미흡**: `textFieldStyle(.roundedBorder)` 단독 사용으로 iOS 네이티브 수준의 polished 느낌이 부족. 라벨·필드·헬퍼 텍스트 간격도 일관되지 않음.

추가로, 사용자가 Claude 생태계의 검증된 CLAUDE.md 가이드와 Claude Skill 자료를 프로필 sheet에서 탐색하고 현재 워크스페이스에 바로 적용할 수 있는 기능 요구가 있었다.

---

## 2. UI 폴리시 변화

### 2-1. Sidebar 폭 고정 (반응형 오류 수정)

```swift
HStack(spacing: 0) {
    sidebarColumn
        .frame(width: 200, alignment: .leading)  // 고정 폭
        .background(Theme.Color.bgSidebar)       // 배경 명확화
    Divider()
    contentColumn
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
}
```

- **이전**: `.frame(width: 188)` — sidebar VStack 안에서만 제한, HStack 레벨에서 폭 보장 없음
- **이후**: `sidebarColumn.frame(width: 200, alignment: .leading)` — HStack 레벨에서 완전 고정
- sidebar 내부 `VStack`도 `frame(maxWidth: .infinity, alignment: .leading)` 보장

### 2-2. PolishedInputField 컴포넌트 도입

신규 `Sources/YuminaiUI/PolishedInputField.swift`:

```swift
public struct PolishedInputField: View {
    // label + 필수 표시 + polished TextField + helperText
    // FocusState 활용 — focused border highlight (Theme.Color.accent 0.6 opacity)
    // textFieldStyle(.plain) + 커스텀 배경/border — .roundedBorder보다 polished
}
```

iOS Settings.app 스타일 구현:
- `textFieldStyle(.plain)` + `padding` + `background(RoundedRectangle)` + `overlay(stroke)`
- `@FocusState` 활용 — 포커스 시 accent 색상 border highlight + 애니메이션
- `multiline: Bool` 파라미터 — `TextField(..., axis: .vertical)` 전환

### 2-3. GroupBox 기반 섹션 카드 레이아웃

각 섹션의 관련 필드를 `GroupBox`로 묶어 시각적 분리:

```
┌── 섹션 제목 (icon + title + subtitle) ───────────┐
│ 직업과 하고 싶은 것                               │
│ AI가 더 맞춤형으로 답변할 수 있게 알려주세요.     │
└─────────────────────────────────────────────────┘

┌── GroupBox ──────────────────────────────────────┐
│  직업        [________입력_필드________]          │
│  (헬퍼 텍스트)                                   │
│  ─────────────────────────────────────────────── │
│  주로 하고   [________입력_필드________]          │
│  싶은 것     [________________________]          │
│  (헬퍼 텍스트)                                   │
└─────────────────────────────────────────────────┘
```

### 2-4. 섹션 제목 개선

- **이전**: icon + 16pt semibold title만
- **이후**: icon + `.title2.weight(.semibold)` title + 친절한 subtitle 한 줄 (`Theme.Typography.small`)

### 2-5. 시트 크기 확장

- **이전**: 760×540
- **이후**: 780×580 (커뮤니티 자료 섹션 추가 및 콘텐츠 여유 공간)

### 2-6. 커뮤니티 자료 섹션 추가

sidebar에 5번째 항목 "커뮤니티 자료" 추가:

```swift
case community = "커뮤니티 자료"
// icon: "cube.box.fill", color: .purple
```

---

## 3. CommunityResource 모델 + 큐레이션 정책

### 3-1. 모델 구조

`Sources/YuminaiCore/CommunityResource.swift`:

```swift
public struct CommunityResource: Sendable, Codable, Identifiable {
    public let id: UUID
    public let category: Category       // claudeMd / skill / template
    public let displayName: String
    public let author: String
    public let summary: String          // 한국어 짧은 설명
    public let starsApprox: Int         // 큐레이션 시점 approximate stars
    public let repoURL: URL             // GitHub repo 링크
    public let rawURL: URL?             // raw 파일 다운로드 URL (nil이면 GitHub 안내만)
    public let tags: [String]
    public let recommendedFor: [GoalStatusKey]  // defined / exploring / undecided
}
```

Hashable은 `id` 기반으로 커스텀 구현 (다른 필드가 달라도 id 동일 = 동일 자료).

### 3-2. 큐레이션 정책

- **Anthropic 공식 리포지토리 우선** — stars 검증 가능, URL 안정적
- **stars 100+ community 자료** — 실제 사용자 채택 확인
- **rawURL 검증**: 큐레이션 시점에 HTTPS + host 유효성 확인
- **하드코딩** — 배포 시 안전한 자료만 포함; 추후 GitHub API로 실시간 갱신 가능

### 3-3. 큐레이션된 자료 (7개)

| # | displayName | author | category | starsApprox | rawURL |
|---|-------------|--------|----------|-------------|--------|
| 1 | Anthropic 공식 CLAUDE.md 베스트 프랙티스 | anthropics | claudeMd | 12,000 | ✓ |
| 2 | Cline 추천 CLAUDE.md 템플릿 | cline | claudeMd | 43,000 | ✓ |
| 3 | awesome-claude-code CLAUDE.md 모음 | hesreallyhim | claudeMd | 2,800 | – |
| 4 | TDD 마스터 Skill (tdd-mastery) | anthropics | skill | 8,000 | ✓ |
| 5 | SwiftUI 패턴 Skill (swiftui-patterns) | anthropics | skill | 5,000 | ✓ |
| 6 | 보안 강화 가이드라인 CLAUDE.md | anthropics | claudeMd | 3,200 | ✓ |
| 7 | Next.js + Claude Code 풀스택 스타터 | vercel | template | 85,000 | – |

---

## 4. 다운로드 + 적용 로직

### 4-1. AppModel.applyCommunityResource(_:to:)

```swift
public func applyCommunityResource(
    _ resource: CommunityResource,
    to workspaceURL: URL
) async -> Result<String, Error>
```

동작:
- **`.claudeMd`**: rawURL 다운로드 → `CLAUDE.md` 끝에 마커 블록으로 삽입
  - 마커: `<!-- BEGIN COMMUNITY: <resource.id> -->` ... `<!-- END COMMUNITY: <resource.id> -->`
  - 이미 적용된 경우 기존 블록 교체 (NSRegularExpression 기반)
- **`.skill`**: rawURL 다운로드 → `.harness/skills/<resource.id>.md`에 저장
- **`.template`**: 다운로드 없음, GitHub 안내 메시지 반환

### 4-2. 다운로드 정책

- `URLSession.ephemeral` + timeout 30s
- HTTP 2xx 확인, 비정상 응답은 `CommunityResourceError.httpError(code)` 반환
- UTF-8 인코딩 강제, 실패 시 `invalidEncoding` 오류
- **사용자 명시적 동의 후만 실행** — 자동 다운로드 절대 없음
- UI에서 URL과 자료명을 적용 전에 표시

### 4-3. CommunityResourceError

```swift
public enum CommunityResourceError: Error, LocalizedError {
    case noRawURL        // rawURL 없는 자료 (template 등)
    case httpError(Int)  // 비정상 HTTP 응답
    case invalidEncoding // UTF-8 파싱 실패
}
```

---

## 5. CommunityResourcesPanel UI

`Sources/YuminaiApp/CommunityResourcesPanel.swift`:

- 카테고리 필터 (전체 / CLAUDE.md / Skill / 템플릿) — Capsule 칩 스타일
- 자료 카드 (`GroupBox` 기반):
  - displayName + author + stars (⭐ 형식) + category 배지 (color-coded)
  - 한국어 summary + 태그 chips (FlowLayout 자동 줄바꿈)
  - [GitHub에서 보기] 링크 + [워크스페이스에 적용] 버튼
  - 적용 결과 인라인 표시 (성공 ✓ / 실패 ✗, 3초 후 사라짐)
- 사용자 정의 URL 입력 섹션 (토글 열기/닫기)
- 워크스페이스 미선택 시 적용 버튼 비활성화

---

## 6. 후속 작업

1. **실시간 GitHub API stars 갱신**: GitHub API v3 `GET /repos/{owner}/{repo}` 호출로 starsApprox 갱신 (rate limit 고려 — 1시간 캐싱)
2. **사용자 정의 자료 export**: 즐겨찾기 자료를 `~/.claude/community-resources.json`에 저장
3. **적용 이력 관리**: 워크스페이스별 적용된 커뮤니티 자료 목록 추적 (중복 방지, 버전 관리)
4. **오프라인 번들**: 앱 번들에 핵심 자료 포함 — 네트워크 없이도 기본 자료 적용 가능
5. **자료 검색**: 키워드 검색 + 태그 필터 결합
