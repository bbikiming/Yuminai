# ADR-137: Color Literal → Theme Semantic Token 전면 마이그레이션

**날짜**: 2026-05-08  
**상태**: Accepted  
**연관**: ADR-147 (Theme Lint Script)

---

## 1. 배경

`Color.orange`, `Color.green`, `Color.red` 등 SwiftUI 시스템 색상 리터럴이 90개 이상의 파일에 분산되어 있었다. 이로 인해:

- 다크/라이트 모드 전환 시 색 일관성이 깨질 수 있음
- 디자인 토큰 시스템(`Theme.Color`)이 유명무실화됨
- ADR-147 lint가 통과하지 못함

---

## 2. 결정

### 신규 토큰 추가 (Theme.swift)

| 토큰 | 값 | 용도 |
|------|-----|------|
| `warningStrong` | `#F59E0B` | 경고, 주의 강조 |
| `gitAdded` | `#4ADE80` | git diff 추가된 줄 |
| `gitRemoved` | `#F87171` | git diff 삭제된 줄 |
| `favoriteStar` | `#FBBF24` | 즐겨찾기/핀 아이콘 |
| `infoBlue` | `#60A5FA` | 정보성 강조 |
| `gitlab` | `#FC6D26` | GitLab 브랜드 색 |
| `autoRunActive` | `#4ADE80` | AutoRun 활성 상태 |
| `autoRunPaused` | `#FBBF24` | AutoRun 일시정지 상태 |

### 치환 규칙

| 원본 | 대체 토큰 | 컨텍스트 |
|------|----------|---------|
| `Color.green` (일반) | `Theme.Color.gitAdded` | diff, 성공 상태 |
| `Color.green` (체크마크) | `Theme.Color.success` | 설치됨, 연결됨 |
| `Color.red` | `Theme.Color.gitRemoved` / `Theme.Color.danger` | diff/오류 |
| `Color.orange` | `Theme.Color.warningStrong` | 경고 |
| `Color.orange` (GitLab) | `Theme.Color.gitlab` | GitLab 브랜드 |
| `Color.blue` | `Theme.Color.infoBlue` | 정보 강조 |
| `Color.yellow` (별/핀) | `Theme.Color.favoriteStar` | 즐겨찾기 |
| `Color.yellow` (AutoRun) | `Theme.Color.autoRunPaused` | AutoRun UI |
| `Color.purple` | `Theme.Color.accent` | 보조 강조 |

### 허용 유지 색상

`Color.clear`, `Color.white`, `Color.black`, `Color.primary`, `Color.secondary`, `Color.accentColor`

---

## 3. 영향 파일

150개 이상 파일에서 색상 리터럴을 교체했다. 주요 파일:

- `DiffView.swift`, `GitDiffSheet.swift`, `TelegramArtifactViewerSheet.swift`
- `AutoRunToggle.swift`, `AutoRunControlSheet.swift`, `AutoRunSettingsView.swift`
- `TelegramUsageDashboard.swift`, `ChartsDashboard.swift`
- `TaskGraphMiniMap.swift`, `RoutingLearningPanel.swift`
- GitLab 관련: `GitLabPATSheet.swift`, `GitLabSearchSheet.swift`
