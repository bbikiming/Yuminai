# 95_RISKS_ASSUMPTIONS — 리스크와 가정

## 가정 (Assumptions)

이것들이 사실이 아니면 PRD가 흔들린다.

### A1. Claude CLI는 stdin/stdout로 안정적 동작
- 가정: `claude` CLI를 자식 프로세스로 띄우고 stdin으로 명령, stdout으로 응답을 받을 수 있다.
- **리스크**: Claude CLI가 TTY를 강하게 요구해서 PTY가 필수. 또는 멀티턴 세션 유지 메커니즘이 없어서 매 메시지마다 spawn 필요.
- **검증 시점**: MVP-0 W1 Spike

### A2. Claude CLI의 출력 형식이 안정적
- 가정: 평문(ANSI 포함)으로 출력하며, 우리가 파싱할 수 있는 일관된 구조.
- **리스크**: Anthropic이 출력 포맷을 자주 바꾸거나, JSON 모드가 없거나, tool call 표현이 불투명.
- **검증**: W1 Spike — `claude --json` 같은 옵션 존재 여부

### A3. macOS 26 / Swift 6.2가 안정적
- 가정: 최신 OS/언어이지만 production-ready.
- **리스크**: 신규 버그, Liquid Glass API 변경
- **완화**: 본인 환경 = 본인 사용. 문제 시 macOS 25(15)로 deployment target 낮출 옵션 있음.

### A4. SwiftData가 우리 규모에서 안정적
- 가정: 메시지 ~10만 개까지 SwiftData가 견딘다.
- **리스크**: SwiftData가 GRDB만큼 성숙하지 않아 마이그레이션 / 동시성 이슈
- **완화**: 모듈로 격리(`YuminaiPersistence`) → 필요 시 GRDB 교체

### A5. App Sandbox OFF가 본인 사용에 충분히 안전
- 가정: 본인 1인 + 본인 빌드 → 신뢰 가능
- **리스크**: 미래의 본인이 신뢰할 수 없는 외부 코드를 실행할 수도
- **완화**: rules/50_SECURITY.md 검토 + 의존성 추가 시 신중

### A6. Claude Code의 인증을 우리가 그대로 쓸 수 있다
- 가정: 사용자가 셸에서 `claude` 한 번 로그인 → 자식 프로세스로 띄울 때도 인증 상속
- **리스크**: Claude CLI가 TTY 검사를 하거나 환경변수에서 토큰을 찾는데 우리가 못 줌
- **검증**: W1 Spike

### A7. Telegram Bot Long Polling이 본인 라이프스타일에 충분
- 가정: 앱 실행 중일 때만 Telegram 명령 받으면 됨 (24/7 백그라운드 X)
- **리스크**: 앱 닫혀 있을 때 명령 놓침
- **완화**: v0.3에서 launchd agent로 백그라운드 polling 검토

### A8. Obsidian Vault가 단일
- 가정: 본인은 메인 Vault 1개 + 가끔 보조
- **리스크**: 멀티 Vault 사용 시 UI 복잡
- **완화**: 워크스페이스별 Vault 매핑 옵션 (v0.2 후반)

### A9. 본인이 4주를 MVP-0에 투입할 수 있다
- 가정: 사이드 + 다른 프로젝트와 병행
- **리스크**: 다른 프로젝트(`nunchi`, `moodbit`, `emotion-lab`) 우선순위에 밀림
- **완화**: 30분/일 베이스라인 + 주말 집중

## 리스크 (Risks)

### R1. PTY/Process 핸들링이 복잡해서 W2-W3 일정 미스 (확률: 중, 영향: 높)
**완화**:
- W1 Spike에서 핵심 검증 (PATH, PTY, 종료 처리)
- SwiftTerm 라이브러리 채택 검토
- 최악: B1(터미널 임베드) 모드로 fallback

### R2. Claude CLI 출력 파싱이 brittle (확률: 중, 영향: 중)
**완화**:
- 처음엔 평문만 파싱 (ANSI 무시)
- v0.2에서 ANSI/도구 호출 점진 추가
- 파싱 실패 시 raw 표시 (gracefully degrade)

### R3. SwiftData 마이그레이션 사고 (확률: 낮, 영향: 매우 높)
**완화**:
- 일 1회 자동 백업
- 마이그레이션 전 수동 백업 강제
- 단위 테스트로 마이그레이션 검증

### R4. macOS 26 신기능 이슈 (확률: 낮, 영향: 중)
**완화**:
- Liquid Glass는 진행적 enhancement (없어도 동작)
- 베타 OS 사용 안 함 (정식만)

### R5. 통합이 너무 많아 핵심 가치 흐려짐 (확률: 중, 영향: 높)
**완화**:
- MVP-0은 통합 0개 (Claude만)
- v0.2도 Obsidian + Telegram 단방향만
- 새 통합은 본인이 *실제로 매일 쓸지* 사용 데이터로 검증

### R6. 본인이 실제로 안 씀 (확률: 낮~중, 영향: 매우 높)
- "만들면 쓸 거 같은데" 함정
**완화**:
- MVP-0 4주 후 1주 강제 사용 → 측정 (활성 시간, 메시지 수)
- 안 쓰면 Pivot 또는 종료

### R7. 보안 사고 (시크릿 노출, 의존성 백도어) (확률: 낮, 영향: 매우 높)
**완화**:
- rules/50_SECURITY.md 매번 적용
- 의존성 추가 시 검증 (license, stars, 최근 커밋)
- 월 1회 보안 점검

### R8. Claude Code 자체의 변경 (확률: 중, 영향: 중)
- Anthropic이 Claude Code의 동작을 바꿈
**완화**:
- A1 wrapper의 본질적 리스크
- Claude Code 업데이트 시 즉시 회귀 테스트
- 최악: A3(하이브리드)로 일부 자체 구현

### R9. Telegram Bot API 정책 변경 (확률: 매우 낮, 영향: 낮)
**완화**:
- 어차피 본인 사용 봇 1개

### R10. 단일 사용자 = 외부 피드백 부재 (확률: 100%, 영향: 중)
**완화**:
- 결정사항은 PRD에 명문화 (왜 그렇게 결정했는지)
- 한국 개발자 1-2명에게 가끔 보여주고 sanity check

## 리스크 매트릭스

```
영향
 높 │  R6        R1, R5, R7
    │
 중 │  R8       R2, R10        
    │             R4
 낮 │  R9                       R3
    └────────────────────────────────
       낮         중       높   확률
```

> **R1, R5, R7이 핵심 우선 관리 대상**.
