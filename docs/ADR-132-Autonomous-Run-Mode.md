# ADR-132 — 자동 실행 모드 (Autonomous Run Mode)

**상태:** 구현 완료  
**날짜:** 2026-05-08  
**기반:** Claude Code `--dangerously-skip-permissions` 패턴 + 하네스 엔지니어링

---

## 1. 배경

사용자 요청:
> "클로드코드처럼 완전한 자동화로 구현할 수 있는 기능을 추가해 줘. 모든 권한에 대해 부여하고 알아서 마칠 수 있도록 하네스엔지니어링에 따라서 진행 가능하도록 설계해 줘"

### 동기

Claude Code는 `--dangerously-skip-permissions` 플래그로 사용자 개입 없이 다중 turn을 자동으로 진행한다. Yuminai도 동일한 패턴을 내장하여:
- 초기 prompt 한 번으로 작업을 끝까지 자동 진행
- `.harness/rules/*.md` 규칙을 LLM 컨텍스트에 자동 주입
- 위험 명령(rm -rf, DROP TABLE 등) 감지 시 자동 일시정지
- turn/예산/시간 hard cap으로 무한 루프 방지

---

## 2. AutoRunConfig 설계 (안전장치 우선)

```swift
public struct AutoRunConfig: Sendable, Codable, Hashable {
    public var enabled: Bool = false
    public var maxTurns: Int = 30           // hard cap: 200
    public var maxBudgetUSD: Double = 3.0
    public var maxDurationSeconds: TimeInterval = 1800  // hard cap: 14400 (4시간)
    public var stopOnDestructive: Bool = true  // 절대 false 권장 안 함
    public var errorThreshold: Int = 3
    public var stopKeywords: [String] = ["작업 완료", "DONE", "✅ 완료", "ALL DONE"]
    public var autoApprovePermissions: Bool = true
    public var autoLoadHarnessRules: Bool = true
    public var autoLoadHarnessSkills: Bool = false
    public var notifyOnComplete: Bool = true
    public var notifyChannel: NotifyChannel = .macOS
}
```

### 핵심 설계 결정

| 결정 | 이유 |
|------|------|
| `stopOnDestructive = true` default | HITLActionGuard 통합 — rm -rf, DROP TABLE 등 24개 패턴 차단 |
| `maxTurns` hard cap 200 | `init/decode` 양방향에서 `min(value, 200)` 강제 |
| `maxDurationSeconds` hard cap 4시간 | 의도치 않은 무한 실행 방지 |
| backward-compat `decodeIfPresent` | 기존 JSON에 필드 없으면 default 적용 |

---

## 3. AutoRunCoordinator 상태 머신

```
idle
 │── start() ──► running
                  │
                  ├── pause() ──► paused ──── resume() ──► running
                  │
                  ├── stop keyword 감지 ──► completed(stopKeyword)
                  ├── maxTurns 도달 ──────► completed(maxTurnsReached)
                  ├── maxBudget 초과 ─────► completed(maxBudgetReached)
                  ├── maxDuration 초과 ───► completed(maxDurationReached)
                  ├── errorThreshold 초과 ► completed(errorThreshold)
                  ├── destructive 감지 ───► paused → (stop) → stopped
                  └── stop() 호출 ────────► stopped
```

### Actor 설계

- `AutoRunCoordinator`는 Swift actor — 모든 상태 접근이 격리됨
- `stateStream()` → `AsyncStream<State>` — UI가 실시간 구독
- `resumeSignal: CheckedContinuation<Void, Never>` — pause 해제 시 루프 재개
- kill switch: `shouldStop = true` + continuation.resume() 즉시 탈출

---

## 4. .harness/rules 자동 로드

`HarnessRulesLoader.loadAll(workspaceURL:)`:
1. `<workspace>/.harness/rules/*.md` 탐색 (파일명 알파벳 오름차순)
2. 빈 파일 skip
3. 각 파일을 `## <filename>` 헤더 + 내용으로 합침
4. 합쳐진 문자열을 첫 turn의 prompt 앞에 prepend (system context)

`autoLoadHarnessRules == true` (default)일 때만 적용.

---

## 5. UI 흐름

```
Composer footer
  └── [🤖 자동 실행] (AutoRunToggle)
       │── idle → 클릭 → startAutoRun(inputText) 호출
       │── running → 클릭 → AutoRunControlSheet 열기
       └── completed → 클릭 → AutoRunControlSheet (로그 보기)

AutoRunControlSheet
  ├── 헤더: 상태 badge (실행 중 🟢 / 일시정지 ⏸ / 완료 ✓)
  ├── 진행 상황 카드 (turn N/30, budget $X/$3, 경과 시간, 진행 바)
  ├── 실행 로그 (최근 10개 turn)
  ├── 설정 섹션 (토글로 expand — AutoRunSettingsView)
  └── 푸터: [일시정지] [중단] [닫기]
```

---

## 6. HITL guard 통합

`HITLActionGuard.category(for:)` — 기존 24개 패턴 그대로 재사용:
- 응답 텍스트에서 destructive 패턴 감지
- 감지 시 → `paused(runId: pauseReason: "위험 명령 감지: <category>")`
- 사용자가 `resume()` 또는 `stop()` 선택
- `stopOnDestructive = false`면 이 검사 건너뜀 (비권장)

---

## 7. Kill switch + Max limits hard cap

| 안전장치 | 구현 |
|--------|------|
| 즉시 중단 | `stop()` → `shouldStop = true` + `resumeSignal.resume()` |
| Max turns 200 | `init/decode` 양방향 clamp |
| Max duration 4시간 | `init/decode` 양방향 clamp |
| 에러 임계값 | `consecutiveErrors >= config.errorThreshold` → 자동 stop |
| Resume 시 limit 리셋 없음 | 누적 turn/cost/elapsed 유지 — 우회 불가 |

---

## 8. 자동 실행 로그 영구 보관

경로: `<workspace>/.harness/auto-run-log/<run-id>.jsonl`

포맷 (한 줄당 JSON):
```json
{"runId":"...","turn":1,"timestamp":"...","userPrompt":"...","agentResponse":"...","toolCalls":[],"costUSD":0.0123,"durationSeconds":3.2,"warnings":[]}
```

이후 Activity 탭에서 과거 자동 실행 로그 조회 가능 (선택 — 후속 ADR).

---

## 9. 검증

### 신규 파일

| 파일 | 모듈 | 역할 |
|------|------|------|
| `AutoRun.swift` | YuminaiCore | 데이터 모델 (Config/TurnLog/CompletionReason) |
| `AutoRunCoordinator.swift` | YuminaiCore | 상태 머신 actor |
| `HarnessRulesLoader.swift` | YuminaiCore | .harness/rules 로더 |
| `AutoRunConfigTests.swift` | Tests | Config 검증 (21개 테스트) |
| `AutoRunCoordinatorTests.swift` | Tests | Coordinator 상태 + 종료 조건 (16개 테스트) |
| `HarnessRulesLoaderTests.swift` | Tests | 파일 로더 (8개 테스트) |
| `AutoRunToggle.swift` | YuminaiUI | Composer 토글 버튼 |
| `AutoRunControlSheet.swift` | YuminaiApp | 제어 패널 sheet |
| `AutoRunSettingsView.swift` | YuminaiApp | 설정 카드 |
| `AppModel+AutoRun.swift` | YuminaiApp | AppModel 통합 extension |

### 수정 파일

| 파일 | 변경 내용 |
|------|---------|
| `AppPreferences.swift` | `autoRunConfig: AutoRunConfig` 필드 추가 (backward-compat) |
| `AppModel.swift` | `autoRunCoordinator`, `autoRunState`, `autoRunLogs`, `showAutoRunControlSheet` 추가 |
| `Composer.swift` | `autoRunState`, `autoRunMaxTurns`, `onAutoRun` 파라미터 + 토글 버튼 |
| `RootView.swift` | Composer 호출 파라미터 + `AutoRunControlSheet` sheet 등록 |

---

## 10. 후속 ADR

- **ADR-133**: 자동 실행 로그 viewer (Activity 탭)
- **ADR-134**: Telegram `/auto <prompt>` 커맨드 — 원격 자동 실행 트리거
- **ADR-135**: 자동 실행 프리셋 (저장된 config + prompt 조합)
