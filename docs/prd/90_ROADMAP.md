# 90_ROADMAP — 마일스톤

> 본인 1인 프로젝트 / 사이드. 시간보다 *완결성* 단위로 마일스톤 끊음. 일정은 참고치.

## MVP-0 — "Claude를 GUI로" (목표 4주)

**완성 정의**: 워크스페이스 1개에서 Claude CLI를 GUI로 띄우고 채팅하며, 세션이 영속된다. 그 외 통합 모두 비활성.

### Scope
- F-M01 워크스페이스 CRUD (단순)
- F-M02 Claude Code CLI Spawn
- F-M03 채팅 UI (B2)
- F-M04 세션 영속
- F-M05 시크릿 관리 (Keychain) — 단, Claude CLI OAuth가 처리 시 우회 가능
- F-M06 기본 설정 화면

### Exit Criteria
- [ ] 빈 워크스페이스 생성 → 채팅 → 종료 → 재실행 → 채팅 복원
- [ ] Claude CLI 비정상 종료 시 사용자에게 알림 + 데이터 보존
- [ ] ⌘1~⌘9 워크스페이스 전환 동작
- [ ] 모든 시크릿 Keychain 검증 (`security find-generic-password -s com.yuminai`)
- [ ] 단위 테스트 커버리지 80%+
- [ ] 로컬 빌드(.app) 더블클릭으로 정상 실행
- [ ] 본인이 실제로 1주일 동안 일상 작업에서 사용

### 주차별 구체

#### W1 — 골격
- [ ] Xcode App 타깃 추가 (`App/README.md` 따라)
- [ ] 5개 모듈 placeholder 구현 (Hello world)
- [ ] CI 없음 (본인 사용) — 수동 빌드 검증
- [ ] `YuminaiClaudeAdapter` Spike: PTY로 `claude --version` 호출 + stdout 캡처

#### W2 — 채팅 골격
- [ ] `YuminaiClaudeAdapter` 본격: stdin 입력 / stdout 스트림 / cancel
- [ ] 단순 채팅 UI (사이드바 없이)
- [ ] ANSI 파서 v0 (색상 무시, 텍스트만)

#### W3 — 영속 + 워크스페이스
- [ ] `YuminaiPersistence` SwiftData 모델 + CRUD
- [ ] 사이드바 워크스페이스 리스트
- [ ] 세션 자동 저장 + 복원
- [ ] 단축키 ⌘1~⌘9, ⌘N

#### W4 — 마감
- [ ] 설정 화면 (Claude 경로, 폰트 크기)
- [ ] 빈 상태 / 에러 상태 UI
- [ ] 첫 실행 온보딩 3-step
- [ ] 단위 테스트 보강 (커버리지 80%+)
- [ ] 본인 1주일 사용 시작 → 버그 트래킹

---

## v0.2 — "통합 살리기" (목표 + 4주)

**완성 정의**: Obsidian 양방향, Telegram 알림(단방향), git worktree 통합.

### Scope
- F-S01 Obsidian 컨텍스트 주입
- F-S02 Obsidian 자동 노트화
- F-S03 Telegram 알림
- F-S04 git worktree 통합
- F-S05 슬래시 명령 카탈로그 GUI
- F-S06 코드 블록 부가 기능 (복사/저장/diff)
- ANSI 파서 v1 (색상 + 코드 블록 렌더링)

### Exit Criteria
- [ ] Vault 노트 클릭 → 채팅에 인라인 → Claude 응답 받음
- [ ] 작업 완료 시 Daily Note에 자동 append (옵션 toggle)
- [ ] Telegram 봇으로 작업 완료 알림 수신
- [ ] 워크스페이스 생성 시 git worktree 자동 생성/삭제
- [ ] 채팅의 코드 블록 호버 시 [복사][저장][diff] 동작

---

## v0.3 — "양방향성과 자동화" (목표 + 4-6주)

**완성 정의**: Telegram 양방향, 워크스페이스 하네스 템플릿, GitHub 통합.

### Scope
- F-C01 Telegram 양방향 (모바일 명령 → 데스크탑 실행)
- F-C02 워크스페이스 하네스 템플릿
- F-C03 다중 LLM 프로바이더 라우팅 (Claude Code 위임)
- GitHub `gh` CLI 통합 (PR 생성/머지)
- Calendar 연동
- 첨부 파일 (이미지 → Claude 전달)

### Exit Criteria
- [ ] Telegram에서 "#nunchi 빌드해줘" → 데스크탑에서 실행 → 결과 응답
- [ ] 새 워크스페이스 생성 시 템플릿 선택 → `.harness/` 자동 생성
- [ ] Yuminai에서 PR 생성 슬래시 명령

---

## v1.0 — "안정화" (목표 + 4-8주)

**완성 정의**: 본인이 1년 동안 매일 쓰면서 큰 문제 없는 수준.

### Scope
- 성능 최적화 (메모리, 시작 시간)
- iCloud Drive 메타 동기화
- 음성 입력 (Telegram → Whisper)
- 백업/복원 GUI
- 본인 사용 데이터 분석 대시보드
- DocC 문서 완비

### Exit Criteria
- [ ] 메모리 idle < 200MB
- [ ] Cold start < 1.5s
- [ ] 30일 연속 사용 시 크래시 0
- [ ] iCloud로 다른 Mac과 메타 동기화

---

## v1.x — "장기"

| 후보 | 우선순위 |
|---|---|
| iOS 컴패니언 앱 | 낮음 (별도 프로젝트로) |
| Plugin 시스템 | 매우 낮음 (본인 사용이라 코드 직접) |
| 친한 개발자 1-2명 공유 | 중간 (안정화 후) |
| 멀티 모델 토론 | 낮음 |

---

## 일정 가이드

| 마일스톤 | 시작 | 완료 (목표) | 누적 |
|---|---|---|---|
| MVP-0 | 2026-05-01 | 2026-05-29 | 4주 |
| v0.2 | 2026-05-30 | 2026-06-26 | 8주 |
| v0.3 | 2026-06-27 | 2026-08-14 | 13-15주 |
| v1.0 | 2026-08-15 | 2026-10-15 | 20-25주 |

> 사이드 프로젝트 / 1인 개발이라 +50% 버퍼 권장. 위 일정은 *공격적 베이스라인*.
