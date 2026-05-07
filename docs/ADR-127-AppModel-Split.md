# ADR-127 — AppModel.swift 도메인별 Extension 분할

**상태**: 완료  
**날짜**: 2026-05-07  
**작성자**: Claude Code (Executor)

---

## 배경

`AppModel.swift`가 6,404줄까지 성장해 가독성·유지보수성이 심각하게 저하됐다.  
단일 파일에 Telegram, GitHub, Library, HITL, Setup, Profile, Notification, DeepLink, Budget/Cost 등 9개 도메인이 혼재하고 있었다.

## 결정

Swift extension을 사용해 각 도메인을 별도 파일로 분리한다.

- Stored properties는 반드시 class 본체에 남겨야 하므로 extension에는 methods/computed properties만 이동
- `private` 접근 한정자는 extension 간 접근을 막으므로 cross-file 접근이 필요한 멤버를 `internal`로 승격
- 분리 기준: 단일 도메인 책임, 호출 경계 명확, 200~800줄 이내

## 분할 결과

| 파일 | 줄 수 | 도메인 |
|------|-------|--------|
| `AppModel+Budget.swift` | 179 | 일일 비용 누적·Budget cap·라우팅 학습·컨텍스트 경고 |
| `AppModel+DeepLink.swift` | 46 | `yuminai://` deep link 라우팅 |
| `AppModel+GitHub.swift` | 191 | GitHub PAT 관리·검색 히스토리·커뮤니티 자료 적용 |
| `AppModel+HITL.swift` | 174 | HITL Coordinator·diff/build 전송·Telegram 연동 |
| `AppModel+Library.swift` | 228 | 리소스 라이브러리 CRUD·첨부 관리 |
| `AppModel+Notification.swift` | 137 | 디바이스 상태·Quiet Hours·알림 정책·HITL timeout |
| `AppModel+Profile.swift` | 104 | 사용자 프로필 갱신·CLAUDE.md 동기화·이미지 선택 |
| `AppModel+Setup.swift` | 69 | Setup Wizard·Claude/Codex 바이너리 경로 선택 |
| `AppModel+Telegram.swift` | 734 | Multi-bot·ChatSession·cokacdir·Commands·사용량·상태 |
| **AppModel.swift (본체)** | **4,628** | 핵심 스트리밍·Workspace·Git·Multi-pane·Multi-agent·Obsidian |

**총 이동 라인**: 1,776줄 (6,404 → 4,628)  
**extension 총 라인**: 1,862줄

## 기술적 결정사항

### 1. `private` → `internal` 승격

extension에서 cross-file 접근이 필요한 멤버:

- `logger`, `telegramBot`, `alertDispatcher`, `commandPump`, `sessionBridge`
- `streamConsumeTask`, `currentClaudeSession`, `pendingAttribution`
- `syncUserProfileTo(workspaceURL:)`, `syncUserProfileToCLAUDEMd(workspaceURL:)`
- `deactivateTelegram()`

### 2. Extension에 추가된 Computed Properties

`AppModel+Telegram.swift`에:
- `activeChatSession: ChatSession?` — activeChatSessionId 기반 조회
- `agentKindForActiveWorkspace: AgentKind` — session/workspace fallback
- `boundWorkspaceName: String?` — telegramBoundWorkspaceId 기반 조회

### 3. Binary Picker 함수 위치

`selectClaudeBinary()`, `selectCodexBinary()`는 NSOpenPanel을 사용하므로 AppKit import가 필요. AppModel+Setup.swift에 배치.

## 검증

- `swift build`: Build complete (0 errors)
- `swift test`: 1346 tests in 205 suites — 모두 통과 (회귀 0)
- 모든 extension 파일 ≤ 800줄

## 후속 작업 (이번 ADR 범위 외)

- AppModel+Obsidian.swift 분리 (Obsidian Vault + 노트 CRUD, ~350줄) — ADR-128 예정
- AppModel+Workspace.swift 분리 (Workspace CRUD/Pin/Folder/Tag/Import/Export, ~500줄) — ADR-128 예정
- AppModel+Git.swift 분리 (Git integration ADR-079/081/082/083, ~490줄) — ADR-128 예정
