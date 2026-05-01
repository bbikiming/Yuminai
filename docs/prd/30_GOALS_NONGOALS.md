# 30_GOALS_NONGOALS — 목표와 비목표

## Goals (의도적으로 *하는* 것)

### G1. Claude Code를 GUI로 감싸 본인 워크플로우의 80%를 흡수
- 터미널 직접 호출 대신 Yuminai를 일상 진입점으로
- 측정: bash history의 `claude` 직접 호출이 80% 감소

### G2. 외부 통합을 1급 시민으로
- Obsidian: 양방향 (컨텍스트 주입 ↔ 결과 자동 노트화)
- Telegram: 양방향 (알림 송신 ↔ 모바일 명령 수신)
- 측정: 컨텍스트 복붙 빈도 90% 감소, 모바일 트리거 주 5회+

### G3. 세션 영속성과 멀티 워크스페이스
- 모든 세션 자동 저장
- 워크스페이스 = git 워크트리 1:1 매핑
- 재진입 시 컨텍스트 복원
- 측정: 활성 워크스페이스 3개 동시 운영 가능

### G4. 하네스 적용 자동화
- 워크스페이스 생성 시 하네스 템플릿 선택
- 글로벌 + 워크스페이스 settings 머지 GUI
- 측정: 새 프로젝트 셋업 시간 < 30초

### G5. 본인 1인 사용에 최적화 — 단순성
- 회원가입/로그인/팀/공유 없음
- 모든 데이터 로컬
- 단축키 / Liquid Glass / 다크모드 기본

## Non-goals (의도적으로 *하지 않는* 것)

### NG1. 멀티 유저 / 팀 협업
- 친구 초대, 권한, 공유 워크스페이스 없음
- 데이터는 본인 1인 디바이스에만

### NG2. 클라우드 백엔드
- 서버 없음, 자체 호스팅 없음
- 모든 통신은 외부 API(Anthropic, Telegram, Obsidian Sync) 직접

### NG3. 다른 OS 지원
- macOS only (Tahoe 26.0+)
- Windows / Linux / iOS / iPadOS 빌드 안 함

### NG4. App Store 배포
- 본인 1인 사용 → 서명·심사·인앱결제 모두 불필요
- unsigned `.app` 또는 ad-hoc 서명만

### NG5. Anthropic SDK 직접 호출 (A1 위반)
- 모든 LLM 추론은 Claude Code CLI 자식 프로세스에 위임
- 직접 Anthropic API 호출 코드 작성 금지 (있다면 리팩토링)
- *예외*: Telegram bot 명령 라우팅에서 간단한 자연어 의도 분류는 자체 작은 모델 사용 가능 (검토 후)

### NG6. 새 추론 엔진 / 프롬프트 엔지니어링
- 프롬프트 / 시스템 메시지 / 에이전트 정의는 Claude Code의 것 그대로 활용
- Yuminai는 그 위의 *오케스트레이션*만

### NG7. IDE 기능
- 코드 편집기, syntax highlighting (사용자 메시지 안의 코드 블록 표시는 OK), debug, lint
- Yuminai 안에서 파일 편집 안 함 — 변경은 Claude Code가 직접 수행

### NG8. 결제 / 수익화 / 분석
- Yuminai는 본인 사용 무료 도구
- 사용자 행동 추적 telemetry는 *로컬만* (본인 분석용)

### NG9. 자체 LLM 호스팅 / Ollama 통합
- 로컬 모델은 후순위
- Claude만 (필요 시 OpenAI/Gemini는 Claude Code의 멀티프로바이더 기능에 위임)

### NG10. 자동 업데이트 시스템
- 본인 빌드 → `.app` 직접 교체
- Sparkle 등 업데이트 프레임워크 미적용

## 결정 매트릭스 (애매한 것)

| 항목 | 결정 | 근거 |
|---|---|---|
| Liquid Glass 적극 사용 | YES (Goal) | macOS 26 네이티브감, 본인 macOS만 사용 |
| Apple Intelligence 통합 | NO (Non-goal) | Claude로 충분, OS 모델 추가는 가치↓ |
| 노트 템플릿 시스템 | LATER (v0.3+) | MVP 후 |
| 음성 입력 (Whisper) | LATER (v0.3+) | Telegram 음성 메시지 처리 시 |
| Plugin 시스템 | NO | 본인 사용이라 코드 직접 수정이 빠름 |
| Markdown export | YES (v0.2) | Obsidian 통합과 자연스러움 |
| Code diff viewer | YES (v0.2) | Claude 출력 가독성 |
| 키보드 전체 조작 | YES (Goal) | Claude Code 사용자 본능 |
