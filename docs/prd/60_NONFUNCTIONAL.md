# 60_NONFUNCTIONAL — 비기능 요구사항

## 성능

### 시작 시간
- Cold start (앱 처음 실행): < 1.5초까지 윈도우 표시
- Warm start (워크스페이스 전환): < 200ms

### 채팅 스트리밍
- 첫 토큰 도착 ~ 화면 표시: < 50ms 추가 지연
- 스크롤 fps: 60+ 유지 (메시지 1000개 기준)

### 메모리
- Idle: < 200MB
- 활성 채팅 1개: < 400MB
- 워크스페이스 5개 + 활성 채팅 1개: < 700MB

### 디스크
- 앱 본체: < 50MB
- 워크스페이스 데이터: 메시지 1만개 기준 < 100MB

## 신뢰성

### 데이터 무결성
- 모든 메시지 저장은 트랜잭션
- Claude CLI 비정상 종료 시 사용자에게 알리고 마지막 메시지 보존
- SwiftData migration 실패 시 백업 복원 옵션

### 복구
- 앱 크래시 시 다음 실행에 자동 복원
- 진행 중이던 Claude 작업은 알림: "지난 세션이 비정상 종료됐습니다. 마지막 입력은 X였습니다."

### 시그널 처리
- ⌘Q 시 Claude 자식 프로세스 정상 종료 (SIGTERM)
- Force quit 시도 안 함 (사용자가 알림 받음)

## 보안

[`rules/50_SECURITY.md`](../../rules/50_SECURITY.md) 참조.

핵심:
- 시크릿 = Keychain only
- 입력 검증 (path traversal, command injection 방어)
- HTTPS only, ATS 강제
- 로그에 시크릿 노출 금지

## 접근성 (a11y)

본인 1인 사용이지만 "본인이 미래에 접근성 필요할 수도" 가정.

- VoiceOver: 모든 버튼/입력에 `.accessibilityLabel`
- 키보드 전체 조작 (마우스 없이 사용 가능)
- 다이내믹 타입 (시스템 폰트 크기 따름)
- 색 대비: WCAG AA (4.5:1)
- 단축키 모두 커스터마이즈 가능

## 다국어

- UI 언어: 한국어 (1차) + 영어 (Claude 출력 그대로)
- 사용자 입력은 어떤 언어든 OK
- Claude 출력 자동 번역 안 함

## 오프라인

- Claude API: 인터넷 필수 (Anthropic 서버)
- 세션 조회 / 워크스페이스 관리 / Vault 검색: 오프라인 OK
- Telegram: 오프라인 시 큐잉 안 함 (의도적 단순)

## 호환성

- macOS: 26.0 (Tahoe)+ — 본인 환경
- 이전 버전 지원 안 함
- Apple Silicon 전용 (Intel 빌드 안 함)

## 관측성

### 로깅
- `os.Logger` 카테고리:
  - `core` — 워크스페이스/세션 lifecycle
  - `claude-adapter` — Claude CLI spawn/stream
  - `obsidian` — Vault IO
  - `telegram` — bot 통신
  - `keychain` — 시크릿 액세스
  - `ui` — 사용자 액션
- Console.app에서 `subsystem == com.yuminai`로 필터

### 메트릭 (로컬, 본인만 봄)
- 일일 활성 시간 (앱 active 시간)
- 메시지 수 / 토큰 수 (Claude 응답에서 파싱 가능하면)
- Claude CLI spawn 횟수 / 평균 지속 시간 / 비정상 종료 비율
- 외부 통합 호출 횟수
- 저장: SwiftData 별도 entity

### 익명 telemetry
- 없음 (외부 전송 없음)

## 유지보수성

- 모듈별 책임 분리 (CLAUDE.md 표 참조)
- 80%+ 테스트 커버리지
- DocC 주석 (public API)
- 의존성 최소 (외부 SPM 의존성 < 5개 목표)

## 개발 환경

- Xcode build time (clean): < 30초
- 단위 테스트 전체: < 10초
- Module 1개 incremental build: < 3초

## 분석/메트릭 표 (요약)

| 카테고리 | 메트릭 | 목표 |
|---|---|---|
| 성능 | Cold start | < 1.5s |
| 성능 | 첫 토큰 지연 | < 50ms |
| 성능 | 메모리 idle | < 200MB |
| 신뢰성 | 크래시율 | < 0.1% (세션당) |
| 보안 | 평문 시크릿 검출 | 0건 |
| 빌드 | Clean build | < 30s |
| 테스트 | 커버리지 | > 80% |
