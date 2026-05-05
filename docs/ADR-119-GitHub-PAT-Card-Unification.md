# ADR-119: GitHub PAT 인증 + 커뮤니티 카드 디자인 통일

**날짜:** 2026-05-04
**상태:** 구현 완료
**관련 ADR:** ADR-116 (GitHub Search), ADR-117 (Library Card), ADR-118 (Search UI Polish)

---

## 1. 배경

### 문제 1 — GitHub 코드 검색 401 오류

`GitHubSearchSheet`의 "코드 파일" 탭에서 `https://api.github.com/search/code`를 호출하면 항상 `401 Unauthorized`가 반환됐다. GitHub Search Code API는 인증된 요청만 허용한다 (repositories 검색은 비인증 OK). PAT 없이 호출하면 코드 검색 전 기능이 사용 불가.

### 문제 2 — 커뮤니티 자료 카드 디자인 불일치

`CommunityResourcesPanel.swift`의 자료 카드가 `GroupBox` 기반이었고, ADR-117에서 확립한 `LibraryItemCard` 패턴 (44×44 아이콘 박스, Capsule 성공 배지, +N 태그 표시 등)과 불일치했다.

---

## 2. 결정

### PAT Keychain 저장 + 인증 흐름

**`KeychainStore.swift`**

```swift
public enum KeychainKey {
    // ...
    public static let githubPersonalAccessToken = "yuminai.github.pat"
}
```

**`AppPreferences.swift`**

```swift
/// ADR-119 — GitHub PAT가 Keychain에 저장됐는지 (UI 표시용 메타).
public var hasGitHubPAT: Bool  // decodeIfPresent ?? false
```

**`AppModel.swift`**

```swift
public var githubPATStatus: SecretStatus = .notSet

public func saveGitHubPAT(_ token: String) async throws
public func removeGitHubPAT() async
public func loadGitHubPAT() async -> String?
```

**`GitHubSearchClient.swift`**

```swift
case unauthorized  // 401 → PAT 필요 또는 만료
```

401 응답은 기존 `.httpError(401)` 대신 `.unauthorized`로 분류. `errorDescription`에 재설정 안내 포함.

### PAT 입력 sheet (`GitHubPATSheet.swift` 신규)

- 왜 PAT가 필요한지 안내 callout
- 단계별 토큰 발급 가이드 (5단계)
- GitHub 토큰 페이지 열기 버튼 (`NSWorkspace.shared.open`)
- `SecureField`로 토큰 입력
- 실시간 형식 검증 (`ghp_` 또는 `github_pat_` 접두사)
- [Keychain에 저장] 버튼 → 저장 성공 시 자동 dismiss

### GitHubSearchSheet PAT 통합

- 코드 검색 탭 선택 시 PAT 상태 배너 표시:
  - 미설정: 경고 배너 + [PAT 설정] 버튼
  - 설정됨: 성공 배너 + [재설정] / [삭제] 버튼
- PAT 없이 코드 검색 시도 → 검색 차단 + 안내 메시지
- `.unauthorized` 에러 수신 → PAT 자동 삭제 + 재설정 안내
- 매 검색 시 `appModel.loadGitHubPAT()`로 Keychain에서 토큰 로드 후 `GitHubSearchClient(token:)` 생성

---

## 3. 카드 디자인 시스템 통일

### CommunityResourcesPanel (ADR-119)

`GroupBox` 기반 카드를 LibraryItemCard 패턴으로 교체:

| 요소 | 변경 전 | 변경 후 |
|------|---------|---------|
| 아이콘 | 없음 | 44×44 아이콘 박스 (카테고리 tint) |
| 제목 | `.body.weight(.semibold)` | `.body.weight(.semibold)` (동일) |
| 메타 행 | author + stars + 언어 flag (텍스트만) | 카테고리 배지 + ⭐ stars + 언어 flag + by author |
| 설명 | `fixedSize(vertical: true)` | `lineLimit(2)` |
| 태그 | `FlowLayout` 무제한 | `HStack` 최대 4개 + +N |
| 사용 사례 | 황색 전구 아이콘 + italic | 회색 divider + "사용 사례: …" |
| 성공 배지 | 텍스트 + 체크 (패딩 없음) | Capsule 배지 (GitHubSearchSheet 통일) |
| 추가 버튼 | RoundedRectangle | Capsule |
| 공식 배지 | 파란 Capsule (동일) | accent border 추가 |
| 카드 외형 | GroupBox.automatic | surface + clipShape + shadow |

### 통일 현황

| 위치 | 패턴 |
|------|------|
| LibrarySheet.itemCard | ADR-117 원형 (44px 아이콘, Capsule 버튼) |
| GitHubSearchSheet.repoCard | ADR-118 적용 (36px 아이콘) |
| GitHubSearchSheet.codeCard | ADR-118 적용 (36px 아이콘) |
| CommunityResourcesPanel.resourceCard | **ADR-119 이번 적용** (44px 아이콘) |

---

## 4. 검증

**변경 파일 (6개)**
- `Sources/YuminaiCore/KeychainStore.swift` — KeychainKey 추가
- `Sources/YuminaiCore/AppPreferences.swift` — hasGitHubPAT 추가
- `Sources/YuminaiCore/GitHubSearchClient.swift` — .unauthorized 에러 케이스
- `Sources/YuminaiApp/AppModel.swift` — githubPATStatus + PAT 메서드 + showGitHubPATSheet
- `Sources/YuminaiApp/GitHubSearchSheet.swift` — PAT 배너 + PAT 인증 client 주입
- `Sources/YuminaiApp/CommunityResourcesPanel.swift` — 카드 디자인 리디자인

**신규 파일 (2개)**
- `Sources/YuminaiApp/GitHubPATSheet.swift`
- `docs/ADR-119-GitHub-PAT-Card-Unification.md`

**테스트 추가 (~7개)**
- `.unauthorized` 에러 케이스 (repositories, code 검색)
- `unauthorizedLocalizedDescription`
- `tokenInjectedInRequest` (Authorization 헤더 검증)
- `KeychainKey` 유니크 검증
- `AppPreferences.hasGitHubPAT` backward-compat (기존 JSON → false)
- `hasGitHubPAT` 명시적 true 보존
- round-trip encode/decode

---

## 5. 후속 작업

- PAT scope 안내 강화 (Fine-grained PAT 지원 시 업데이트)
- Token 만료 감지 후 자동 배너 표시 강화 (현재는 검색 실패 시 수동 재설정)
- CommunityResourcesPanel 카드에 hover 애니메이션 추가 (.hoverEffect 등)
