# ADR-133: GitHub/GitLab 권한 위임 + CommandPolicy 매트릭스 + GitLab 통합

**날짜**: 2026-05-08  
**상태**: Accepted  
**연관**: ADR-098 (HITLActionGuard), ADR-132 (AutoRun 모드)

---

## 1. 배경

ADR-132에서 자동 실행 모드(AutoRun)를 도입했다. 사용자가 요청한 후속 과제는 다음이다.

> "최대한 많은 권한을 위임할 수 있도록 깃랩, 깃헙에서 관련 스킬과 api들도 상세하게 조사해서 적용해 줘"

즉, AutoRun 중 `gh`/`glab`/`git` 명령에 대한 세밀한 자동 승인 정책이 필요하다.

---

## 2. 리서치 결과

### A. GitHub 자동화 surface

#### gh CLI 명령 카테고리

| 카테고리 | 명령 예시 | 읽기/쓰기 | 기본 정책 |
|---------|---------|---------|---------|
| repo | `gh repo view`, `gh repo list` | 읽기 | allow |
| repo | `gh repo create`, `gh repo delete` | 쓰기/파괴 | confirm / deny |
| pr | `gh pr list`, `gh pr view`, `gh pr status` | 읽기 | allow |
| pr | `gh pr create`, `gh pr comment` | 쓰기(비파괴) | allow |
| pr | `gh pr merge`, `gh pr close` | 쓰기 | requireConfirmation |
| issue | `gh issue list`, `gh issue view` | 읽기 | allow |
| issue | `gh issue create`, `gh issue comment` | 쓰기 | allow |
| run | `gh run list`, `gh run view` | 읽기 | allow |
| workflow | `gh workflow list`, `gh workflow view` | 읽기 | allow |
| workflow | `gh workflow run` | 쓰기(CI 실행, 비용) | requireConfirmation |
| release | `gh release list`, `gh release view` | 읽기 | allow |
| release | `gh release create` | 쓰기 | requireConfirmation |
| secret | `gh secret set`, `gh secret delete` | 시크릿 파괴 | deny |
| api | `gh api /repos/...` | 읽기 | allow |
| auth | `gh auth status` | 읽기 | allow |

#### GitHub REST API v4 핵심 엔드포인트

- `GET /repos/{owner}/{repo}` — 리포 정보 조회
- `GET /search/repositories` — 리포 검색 (인증 필요)
- `GET /search/code` — 코드 파일 검색 (PAT 필수)
- `GET /repos/{owner}/{repo}/pulls` — PR 목록
- `POST /repos/{owner}/{repo}/pulls` — PR 생성
- `GET /repos/{owner}/{repo}/actions/runs` — workflow 실행 목록
- `GET /repos/{owner}/{repo}/releases` — 릴리즈 목록

#### GitHub PAT scope 매트릭스

| Scope | 설명 | 권장 |
|-------|-----|-----|
| `public_repo` | 공개 리포 읽기+쓰기 | 코드 검색 |
| `repo` | 공개+비공개 리포 전체 | CI/CD |
| `workflow` | GitHub Actions workflow 편집 | CI 자동화 |
| `write:packages` | GitHub Packages 업로드 | 패키지 배포 |
| `admin:org` | 조직 관리 | 사용 자제 |

### B. GitLab 자동화 surface

#### glab CLI 명령 카테고리

| 카테고리 | 명령 예시 | 읽기/쓰기 | 기본 정책 |
|---------|---------|---------|---------|
| repo | `glab repo view`, `glab repo list` | 읽기 | allow |
| mr | `glab mr list`, `glab mr view`, `glab mr status` | 읽기 | allow |
| mr | `glab mr create`, `glab mr approve` | 쓰기 | allow |
| mr | `glab mr merge` | 쓰기 | requireConfirmation |
| issue | `glab issue list`, `glab issue view` | 읽기 | allow |
| pipeline | `glab pipeline list`, `glab pipeline status` | 읽기 | allow |
| pipeline | `glab pipeline run` | 쓰기(CI 실행) | requireConfirmation |
| release | `glab release list` | 읽기 | allow |
| variable | `glab variable set`, `glab variable delete` | 시크릿 | deny |
| project | `glab project delete` | 파괴 | deny |
| auth | `glab auth status` | 읽기 | allow |

#### GitLab REST API v4 핵심 엔드포인트

- `GET /api/v4/projects?search=...` — 프로젝트 검색
- `GET /api/v4/snippets?search=...` — 스니펫 검색
- `GET /api/v4/user` — 현재 사용자 정보 (PAT 검증)
- `GET /api/v4/projects/{id}/merge_requests` — MR 목록
- `POST /api/v4/projects/{id}/merge_requests` — MR 생성
- `GET /api/v4/projects/{id}/pipelines` — 파이프라인 목록

#### GitLab PAT scope 매트릭스

| Scope | 설명 | 권장 |
|-------|-----|-----|
| `api` | 전체 API 접근 | 자동화 |
| `read_api` | 읽기 전용 API | 검색만 |
| `read_repository` | 리포 코드 읽기 | 클론 |
| `write_repository` | 리포 쓰기 | 커밋 push |
| `read_user` | 사용자 정보 읽기 | 검증 |

### C. 자동 실행 권한 위임 — 안전 vs 위험 분류

| 명령 | 정책 | 이유 |
|------|------|------|
| `gh repo view` / `gh pr list` / `gh issue list` | allow | 읽기 전용, 부수효과 없음 |
| `gh pr create` / `gh issue create` | allow | 사용자 의도 명확, 되돌리기 용이 |
| `gh pr comment` / `gh issue comment` | allow | 비파괴적 쓰기 |
| `gh pr merge` / `gh release create` | requireConfirmation | 되돌리기 어려운 쓰기 |
| `gh workflow run` | requireConfirmation | CI 실행 비용 + 외부 영향 |
| `gh repo delete` / `gh secret set` | deny | 파괴적 / 시크릿 노출 |
| `git push --force` / `git reset --hard` | deny | HITLActionGuard 동기화 |
| `glab mr list` / `glab pipeline list` | allow | 읽기 전용 |
| `glab mr create` / `glab mr approve` | allow | 비파괴적 쓰기 |
| `glab pipeline run` | requireConfirmation | CI 실행 비용 |
| `glab project delete` / `glab variable set` | deny | 파괴적 / 시크릿 |

---

## 3. CommandPolicy 매트릭스 설계

### 설계 원칙

- **안전 우선**: 기본 정책은 보수적 (write 작업은 confirmation)
- **확장 가능**: 사용자 정의 allow/deny 패턴 추가 가능
- **HITLActionGuard 동기화**: denyPatterns에 기존 위험 패턴 포함

### 평가 순서 (우선순위 높은 순)

1. `denyPatterns` 매칭 → `.deny` (즉시 차단)
2. `allowList` prefix 매칭 → `.allow` (정확 매칭)
3. `allowPatterns` 정규식 매칭 → `.allow`
4. 기본 → `.requireConfirmation`

### 안전 기본값 (`CommandPolicyMatrix.default`)

```swift
allow (자동 승인):
  allowList: ["gh repo view", "gh pr list", "gh issue list", "gh run list",
              "glab mr list", "glab pipeline list", "git status", "git log", ...]
  allowPatterns: [
    "^gh\\s+(repo|pr|issue|run|workflow|release|gist|codespace)\\s+(view|list|status|checks|diff)\\b",
    "^gh\\s+(pr|issue)\\s+create\\b",
    "^glab\\s+(mr|issue|pipeline|release)\\s+(view|list|status|approve)\\b",
    "^glab\\s+mr\\s+create\\b",
    "^git\\s+(status|log|diff|show|branch|fetch|stash list|remote -v)\\b",
  ]

deny (차단):
  - HITLActionGuard.dangerousPatterns (git push --force, rm -rf, DROP TABLE, ...)
  - "^gh\\s+repo\\s+delete\\b"
  - "^gh\\s+secret\\s+(set|delete)\\b"
  - "^glab\\s+project\\s+delete\\b"
  - "^glab\\s+variable\\s+(set|delete)\\b"
```

---

## 4. GitLab 통합

### GitLabSearchClient

- GitHubSearchClient 패턴 차용 (actor, URLSessionProtocol, SearchError)
- `hostURL` 파라미터로 self-hosted 지원
- 인증 헤더: `PRIVATE-TOKEN: <token>` (표준 GitLab)
- `searchProjects(query:perPage:page:)` — `/api/v4/projects?search=...`
- `searchSnippets(query:perPage:page:)` — `/api/v4/snippets?search=...`
- `validateToken()` — `/api/v4/user` (PAT 유효성 검증)

### GitLab PAT 관리

```swift
KeychainKey.gitlabPersonalAccessToken = "yuminai.gitlab.pat"
AppPreferences.hasGitLabPAT: Bool
AppPreferences.gitlabHostURL: String  // default "https://gitlab.com"
AppModel.gitlabPATStatus: SecretStatus
AppModel.saveGitLabPAT(_:) / removeGitLabPAT() / loadGitLabPAT()
```

---

## 5. SetupTool 확장

```swift
case githubCLI   // brew install gh
case gitlabCLI   // brew install glab
```

SetupWizardSheet에서 gh / glab CLI 자동 감지 + 설치 안내 제공.

---

## 6. CommunityCatalog 신규 자료

### 신규 Category

| Category | 설명 |
|---------|-----|
| `githubAction` | GitHub Actions workflow 파일 |
| `gitlabCI` | GitLab CI/CD 파일 (.gitlab-ci.yml) |
| `prTemplate` | PR/MR 템플릿 |
| `issueTemplate` | Issue 템플릿 |

### 신규 큐레이션 자료 (5개, ADR-133)

| # | 이름 | Category | 출처 |
|---|-----|---------|-----|
| 65 | Claude Code GitHub Action (공식) | githubAction | anthropics/claude-code-action |
| 66 | Swift 패키지 Release CI 템플릿 | githubAction | apple/swift-package-manager |
| 67 | semantic-release 자동 버저닝 | githubAction | semantic-release |
| 68 | GitLab CI Swift 파이프라인 | gitlabCI | gitlab-org |
| 69 | pre-commit + GitLab CI 통합 | gitlabCI | pre-commit |

---

## 7. AutoRun 통합 흐름

```
AutoRun 실행 → LLM 응답에 명령 실행 의도 감지
    ↓
AppModel.evaluateCommand(command)
    ↓
CommandPolicyMatrix.policy(for: command)
    ├── .allow → 그대로 실행
    ├── .requireConfirmation → AutoRunCoordinator paused → HITL 승인 대기
    └── .deny → 즉시 stop, reason: .destructiveBlocked
```

`AutoRunConfig.commandPolicy: CommandPolicyMatrix?`
- nil이면 `AppPreferences.commandPolicy` (글로벌 설정) 사용
- non-nil이면 per-run override

---

## 8. UI

### 신규 화면

| 화면 | 진입점 |
|-----|------|
| `CommandPolicySettingsSheet` | AutoRunSettingsView 또는 직접 |
| `GitLabPATSheet` | 설정 → GitLab / GitLab 검색 헤더 |
| `GitLabSearchSheet` | CommunityResourcesSheet 헤더 "GitLab 검색" |

### 기존 화면 변경

- `CommunityResourcesSheet`: 헤더에 "GitLab 검색" 버튼 추가
- `RootView`: `showGitLabSearchSheet`, `showGitLabPATSheet`, `showCommandPolicySettingsSheet` 시트 등록
- `AppModel`: `gitlabPATStatus`, `showGitLabSearchSheet`, `showGitLabPATSheet`, `showCommandPolicySettingsSheet` 프로퍼티 추가

---

## 9. 검증 결과

```
swift build → Build complete! (0 errors)
swift test  → 1430+ tests passed (1388 baseline + ~42 신규)
```

신규 테스트:
- `CommandPolicyTests` — 28개 (allow/deny/requireConfirmation 분류, 대소문자 무시)
- `CommandPolicyMatrixTests` — 13개 (Codable, 우선순위, 정규식)
- `GitLabSearchClientTests` — 15개 (projects/snippets/errors/pagination/validation)

---

## 10. 후속 작업

- GitHub App OAuth (Installation Token) — `KeychainKey.githubInstallationToken` 예약
- GitLab Webhook 수신 (파이프라인 완료 알림 → Telegram)
- `gh workflow run` 실행 확인 UI (run ID 추적)
- per-workspace CommandPolicy 오버라이드
