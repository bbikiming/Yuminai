# ADR-142: Telegram /auto 명령어

**날짜**: 2026-05-08  
**상태**: Accepted  
**연관**: ADR-132 (AutoRun 모드), ADR-080 (Telegram 봇 통합)

---

## 1. 배경

AutoRun 모드를 Telegram에서 원격으로 제어할 방법이 없었다. 데스크탑 앱을 직접 열어야만 AutoRun을 시작/중지할 수 있었다.

---

## 2. 결정

`YuminaiCommandRouter`에 `/auto` 명령을 추가한다.

### 서브커맨드

| 서브커맨드 | 동작 |
|-----------|------|
| `/auto status` | 현재 AutoRun 상태 반환 |
| `/auto stop` | AutoRun 중지 |
| `/auto pause` | AutoRun 일시정지 |
| `/auto resume` | AutoRun 재개 |
| `/auto <prompt>` | 새 AutoRun 시작 (prompt = 첫 번째 task) |

### 상태 응답 형식

```
🤖 AutoRun 상태
━━━━━━━━━━━━━━━━━━━━━━━
상태: 실행 중
진행: 3 / 10 턴
현재 workspace: my-project
```

### helpText 업데이트

`/help` 응답에 `/auto` 섹션 추가:

```
🤖 AutoRun
/auto status — 현재 상태
/auto stop — 중지
/auto pause — 일시정지
/auto resume — 재개
/auto <task> — 새 실행 시작
```

---

## 3. 구현 상세

`autoCommand(_ arg: String) async -> String?` 메서드:

- "status", "stop", "pause", "resume" 키워드는 정확히 일치
- 그 외 모든 텍스트는 `initialPrompt`로 간주하여 `startAutoRun` 호출
- `AppModel`은 `@MainActor`이므로 `Task { @MainActor in ... }` 패턴 사용

---

## 4. 영향 파일

| 파일 | 변경 |
|------|------|
| `Sources/YuminaiApp/YuminaiCommandRouter.swift` | /auto case + autoCommand 구현 + helpText |
