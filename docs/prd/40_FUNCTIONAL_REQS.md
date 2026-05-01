# 40_FUNCTIONAL_REQS — 기능 요구사항

> MoSCoW 우선순위. **Must = MVP**, **Should = v0.2**, **Could = v0.3+**, **Won't = 비범위 (30번 문서 참조)**.

## M (Must — MVP-0)

### F-M01. 워크스페이스 CRUD
- 새 워크스페이스 생성: 이름, 디렉토리(git 워크트리 또는 일반), 하네스 템플릿
- 워크스페이스 목록 (좌측 사이드바)
- 빠른 전환 단축키 ⌘1~⌘9
- 워크스페이스 닫기 / 삭제

### F-M02. Claude Code CLI Spawn
- 워크스페이스 활성화 시 자식 프로세스로 `claude` 실행
- stdin 입력 → stdout 스트리밍 수신
- 종료/cancel 처리 (SIGTERM → SIGKILL)
- PATH 자동 구성

### F-M03. 채팅 UI (B2 — CLI 스타일 GUI)
- monospace 다크 테마, Claude Code 룩
- 사용자 메시지 / Claude 응답 스트리밍
- 코드 블록 신택스 하이라이트 (구문 인식만, 편집 X)
- 슬래시 명령 자동완성 (글로벌/프로젝트 명령)
- 입력창 단축키: ⌘+Return 전송, ⌘+L 클리어, Esc cancel

### F-M04. 세션 영속
- 모든 메시지를 SwiftData에 저장 (워크스페이스별)
- 워크스페이스 재진입 시 최근 세션 자동 표시
- 세션 분기/새 세션 시작
- 세션 검색 (워크스페이스 내)

### F-M05. 시크릿 관리 (Keychain)
- 첫 실행 시 Anthropic API key 입력 (또는 Claude Code OAuth가 이미 셋업되어 있으면 건너뛰기 — Claude CLI가 자체 처리)
- 시크릿 저장/조회/삭제 GUI

### F-M06. 기본 설정 화면
- 일반: Claude CLI 경로, 기본 모델 (위임)
- 통합: Obsidian Vault 경로, Telegram bot token (둘 다 옵션)
- 외관: 폰트 크기, 다크/라이트, Liquid Glass 강도

## S (Should — v0.2)

### F-S01. Obsidian 통합 (단방향: 컨텍스트 주입)
- Vault 경로 등록 → 노트 트리 사이드바
- 노트 클릭 → 채팅창에 `@note-name` 인라인 삽입
- 인라인 마커는 Claude에 전달 시 노트 본문으로 expand
- 검색 (Vault 전체 텍스트, 단순)

### F-S02. Obsidian 통합 (양방향: 자동 노트화)
- 작업 완료 시 Daily Note에 자동 append (옵션)
- `/note save` 슬래시 명령으로 현재 세션 → 새 노트
- 템플릿: 작업명, 시간, 핵심 변경, 후속

### F-S03. Telegram 알림 (단방향)
- 작업 시작/완료/실패 시 Telegram 메시지
- 사용자 의사결정 필요 시 inline keyboard
- 알림 종류 토글 (설정)

### F-S04. 워크스페이스 = git 워크트리 통합
- 워크스페이스 생성 시 `git worktree add` 옵션
- 좌측 사이드바에 현재 브랜치/dirty 상태 표시
- 워크스페이스 삭제 시 worktree cleanup 옵션

### F-S05. 슬래시 명령 카탈로그 GUI
- 사용 가능한 슬래시 명령 사이드패널
- 글로벌 + 워크스페이스 명령 분리 표시
- 즐겨찾기

### F-S06. 코드 블록 부가 기능
- 복사 버튼
- 파일 저장 (Save As) — Claude가 출력한 코드 빠른 추출
- diff viewer (Claude가 변경한 파일 vs 원본)

## C (Could — v0.3+)

### F-C01. Telegram 양방향 (모바일 명령 수신)
- 봇이 메시지 수신 → 데스크탑 Yuminai에 푸시
- 의도 분류 (어떤 워크스페이스인지) — 작은 자체 분류기 또는 Claude에 위임
- 실행 후 결과 봇으로 응답

### F-C02. 워크스페이스 하네스 템플릿
- 신규 워크스페이스 생성 시 템플릿 선택 (Swift / TypeScript / Python / General)
- 각 템플릿이 `.harness/` 폴더 + 기본 rules/agents/skills 스캐폴딩
- 사용자 커스텀 템플릿 저장

### F-C03. 다중 LLM 프로바이더 라우팅
- Claude / OpenAI / Gemini 위임 라우팅 (Claude Code의 멀티프로바이더 기능 활용)
- 작업 종류별 모델 자동 선택 (계획 = Opus, 단순 = Haiku)

### F-C04. 음성 입력 (모바일 Telegram)
- Telegram 음성 메시지 → Whisper API → 텍스트 → Yuminai 명령

### F-C05. iCloud Drive 동기화 옵션
- 워크스페이스 메타데이터를 iCloud 폴더에 미러 (디바이스 간)
- 시크릿은 동기화 안 함 (각 디바이스 Keychain)

### F-C06. 작업 일정/캘린더 통합
- 워크스페이스에 deadline 설정
- macOS Calendar에 표시

### F-C07. 모바일 컴패니언 앱
- iOS Yuminai (별도 프로젝트로 분리될 수 있음 — 비범위 위험)

### F-C08. 미디어 첨부
- 스크린샷 드래그 → 채팅 입력 → Claude에 이미지 전달

### F-C09. 멀티 모델 토론
- 같은 질문을 여러 모델에 동시 → 비교

## W (Won't — 명시적 비범위)

[`30_GOALS_NONGOALS.md`](30_GOALS_NONGOALS.md) Non-goals 섹션 참조.

## 기능 우선순위 매트릭스

```
            High Value
                |
   F-M03  F-M02 |  F-S01  F-S02
   F-M04        |  F-S03  F-C01
                |
  Low Effort ---+--- High Effort
                |
   F-M01  F-M05 |  F-S04  F-C02
   F-M06        |  F-C03  F-C04
                |
            Low Value
```

> MVP는 좌상단 (Must, Low Effort, High Value) 우선.
