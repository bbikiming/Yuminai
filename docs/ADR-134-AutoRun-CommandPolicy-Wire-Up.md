# ADR-134: AutoRun + CommandPolicy 실제 연동

**날짜**: 2026-05-08  
**상태**: Accepted  
**연관**: ADR-132 (AutoRun 모드), ADR-133 (CommandPolicy 매트릭스), ADR-098 (HITLActionGuard)

---

## 1. 배경

ADR-133에서 `CommandPolicyMatrix`와 `HITLActionGuard`를 정의했으나, `AppModel+AutoRun.swift`의 `executeTurn` 콜백에서 실제로 이 정책을 평가하는 코드가 빠진 채로 merge됐다. AutoRun이 LLM 응답 안의 shell 명령을 정책 검사 없이 그대로 흘려보내는 상태였다.

---

## 2. 결정

### AutoRunCommandExtractor 신설

`Sources/YuminaiCore/AutoRunCommandExtractor.swift`에 정적 유틸리티를 추가했다.

- **펜스드 코드 블록** (` ```sh … ``` ` 또는 ` ```bash … ``` `): 정규식으로 추출
- **인라인 백틱** (`\`command arg\``): 단일 줄 단위 추출
- 결과: 중복 제거된 `[String]` 배열

### executeTurn 콜백 연동

`AppModel+AutoRun.swift`의 `executeTurn` 완료 시점에:

1. `AutoRunCommandExtractor.extract(from: lastResponse)` 호출
2. `config.commandPolicy ?? preferences.commandPolicy` (run-specific 오버라이드 우선)로 `CommandPolicyMatrix` 결정
3. 각 명령에 대해 `.deny` → `blockedCommands`에 추가 + warning 생성
4. `blockedCommands`가 있으면 응답에 `[COMMAND_POLICY_BLOCKED: ...]` 마커 주입
5. `HITLActionGuard`가 이 마커를 감지하여 AutoRunCoordinator의 destructive 중단 경로를 타도록 설계

---

## 3. 결과

- `.deny` 정책 명령이 LLM 응답에 포함될 경우 AutoRun이 안전하게 멈춘다.
- `.requireConfirmation` 명령은 warning 로그에 기록되고 HITL 흐름으로 라우팅된다.
- `.allow` 명령은 기존과 동일하게 실행된다.
- `AutoRunTurnLog.warnings`에 모든 정책 판단이 기록된다.

---

## 4. 영향 파일

| 파일 | 변경 |
|------|------|
| `Sources/YuminaiCore/AutoRunCommandExtractor.swift` | 신규 |
| `Sources/YuminaiApp/AppModel+AutoRun.swift` | executeTurn 콜백에 정책 평가 추가 |
