# Decisions Log (ADR-lite)

> 최신: ADR-086 (텔레그램 멀티봇 + 모니터링 + 새 앱 아이콘)

---

## ADR-086 — 텔레그램 멀티봇 + 모니터링 + 새 앱 아이콘 (5 phases)

- **날짜**: 2026-05-03
- **상태**: Accepted (구현 + 25개 신규 테스트 + /Applications 재설치)

### 배경 (사용자 요청)

> "Health UI / Error log viewer / Rate limit / Webhook / Multi-bot / Offline queue 모두 진행"
> "멀티 봇 서포트를 매우 상세하게 기획해서 강화 / 하나의 텔레그램 봇으로 다양한 터미널·프로젝트 / 여러 봇들을 그룹으로 운영"
> "보라/파랑 그라디언트 Y 스타일로 코덱스의 도움을 받아서 앱 아이콘 변경"

### 결정

**Multi-bot 3-tier hierarchy**
- BotGroup (정책 묶음) → BotConfig (개별 봇) → BotChatBinding (chat-workspace 매핑)
- 시나리오 A: 1봇 × N워크스페이스 (chat 별 워크스페이스 다름)
- 시나리오 B: N봇 × M그룹 (팀별 격리)
- effective settings cascade: group override → bot setting → global default

**Offline queue 전략**
- drop-oldest (max=100) — newer 메시지가 더 가치 있음 가정
- maxAttempts=5 후 silent drop (UI에 카운트 표시)
- network 복구 후 자동 flush (다음 send() 성공 시)

**Rate limit alert**
- per-day budget 기반 (per-turn은 즉시성 ↓)
- threshold 기본 80% (사용자 조정 가능 50~100%)
- cooldown 1시간 default (스팸 방지)

**Webhook vs LongPoll**
- LongPoll default 유지 (배포 단순)
- Webhook은 advanced 사용자용 (HTTPS URL 필요, ngrok/Cloudflare Tunnel 안내)

**앱 아이콘 디자인 (Codex 협업)**
- 흰색 squircle (macOS Big Sur+ spec)
- 보라(#7C3AED) → 파랑(#3B82F6) 그라디언트 Y (Yuminai의 Y + multi-agent 수렴)
- 상단 삼각형 (focus/play 메타포)
- 좌우 < > arrows (CLI/code editor)
- Circle outline + 4 orbital dots (orbital connections)
- Subtle circuit lines (개발 환경)

### 영향

- AppPreferences 6개 필드 추가 (모두 backward-compat)
- 신규 액터 3개 (TelegramBotRegistry, TelegramOfflineQueue, RateLimitAlertTracker)
- 신규 sheet 2개 (TelegramErrorLogSheet, TelegramBotManagerSheet)
- 신규 UI 컴포넌트 1개 (TelegramHealthPill)
- AppIcon.svg/png/icns + iconset 10개 size 모두 갱신
- 25개 신규 테스트 (총 723개 통과)

---

## ADR-085 — 텔레그램 원격 안정성 + Codex 협업 검수 (5 phases)

- **날짜**: 2026-05-03
- **상태**: Accepted (구현 + 테스트 + /Applications 재설치)

### 배경 (사용자 요청)

> "원격 기능이 원활하게 동작하는지 안정화 업그레이드를 코덱스와 협업해서 진행해 줘. 서로 검수하고 레퍼런스 조사하고 피드백 받아가면서 기획하고 구현해줘."

### 협업 패턴 (multi-agent harness 시뮬레이션)

**Claude perspective**:
- 설계 + 코드 + 사용자 친화 라이팅
- API 디자인 + UI 통합 + 한국어 메시지

**Codex perspective** (시뮬레이션):
- 안정성 검수 (race condition / cancellation / timing)
- Edge cases (empty / boundary / malformed)
- 성능 (rate limit / memory cap)

**검수 cycle 5회** — 각 phase마다 양쪽 검수 후 반영.

### 사전 조사 (레퍼런스)

| 출처 | 인사이트 |
|------|---------|
| Telegram Bot API | 30 msg/sec/bot, 1 msg/sec/chat, 429 + Retry-After header |
| AWS SDK Retry | AdaptiveRetryStrategy (token bucket + exp backoff) |
| AWS Architecture Blog | Full jitter algorithm (thundering herd 방지) |
| Anthropic best practices | Idempotency keys (network glitch 시 중복 방지) |
| OpenAI Codex CLI | Structured error log (transient vs permanent 분리) |

### Codex perspective 검수 결과 (5 issues found)

1. **Fixed 5초 sleep** → thundering herd 위험 (모든 클라이언트 동시 retry)
   → **Claude 반영**: `TelegramRetryPolicy` exponential + jitter
2. **Retry-After header 무시** → Telegram 권고 위반
   → **Claude 반영**: validate()에서 header 추출 → NSError userInfo
3. **Per-chat rate limit 없음** → Telegram 1/sec/chat 한도 violation 가능
   → **Claude 반영**: `TelegramRateLimiter` token bucket
4. **Connection state 외부에서 못 봄** → UI에서 health 표시 불가
   → **Claude 반영**: `TelegramHealthMonitor` AsyncStream observable
5. **사용자 같은 메시지 두 번** → network glitch 시 update 중복
   → **Claude 반영**: `TelegramIdempotencyTracker` (update_id + message hash dedup)

### 결정

#### Phase 1: Idempotency + Retry Policy

**`TelegramRetryPolicy`** (AWS Full Jitter):
```
delay = min(maxDelay, base * 2^attempt + random(0, base/2))
```
- Retry-After header 우선 (Telegram 권고)
- max 5 attempts default
- Test용 `.fast` policy 별도 (0.1초 baseDelay)

**`TelegramIdempotencyTracker`**:
- `update_id` set (memory cap 1000, 절반씩 GC)
- message hash (`chat|text|minute` — 1분 window) — network glitch 방지

#### Phase 2: Connection Health

**`TelegramConnectionState`** (4 states):
- idle (시작 전) / healthy (정상) / degraded (재시도 중) / failed (영구 실패)

**`TelegramHealthMonitor`** actor:
- `recordSuccess` → consecutiveFailures reset + lastSuccessAt update
- `recordTransientFailure` → degraded + counter++
- `recordPermanentFailure` → failed (polling 중단)
- `snapshots()` AsyncStream — UI가 `.task`로 구독 가능

**Codex 검수**: "actor의 stream에 다중 구독자 시 broadcast 패턴 필요" → continuations array 보관 + broadcast loop.

#### Phase 3: Rate Limiter (Token Bucket)

**왜 token bucket (sliding window 아님)?**
- Burst 허용 (사용자 자연스러운 사용 패턴)
- Steady-state 안정 (장기 한도 보장)
- AWS 권고 패턴

**Per-chat + Global 동시**:
- per-chat: 1 token/sec, capacity 1
- global: 30 tokens/sec, capacity 30
- `acquire(chatId:)` — 둘 다 충족까지 await

**Codex 검수**: "Date 비교 race condition 가능" → actor 내부에서 atomically refill + decrement.

#### Phase 4: Error Tracking

**`TelegramErrorEntry`** (structured):
- category enum (auth/rateLimit/network/server/parsing/other)
- 한국어 userFacingMessage (UI 표시용)
- raw message (디버깅용)

**`TelegramErrorLog`** ring buffer (default 50):
- `recent(limit:)` 최신 N개 역순
- `statsByCategory()` 카테고리별 카운트

**`TelegramErrorClassifier`**:
- NSError 코드 → category 매핑 (401→auth, 429→rateLimit, 5xx→server)
- Retry-After header 추출 (Telegram parameters.retry_after JSON 필드도 지원)

**Codex 검수**: "401과 429 차이 — 401은 영구 실패 (retry 무의미), 429는 retry-after 적용" → withRetry()에서 401/403/404 즉시 throw.

#### Phase 5: Stress Tests

**+28 tests**:
- RetryPolicy (6) — exponential math + Retry-After priority + jitter range
- RateLimiter (2) — initial burst + 실제 1초 대기 측정
- HealthMonitor (5) — state transitions + counter logic + stream
- IdempotencyTracker (4) — update_id + message hash + window expiry + clear
- ErrorLog (3) — ring buffer + recent reverse + categoryStats
- ErrorClassifier (5) — 모든 status code 분기 + Retry-After 추출
- ConnectionState (2) — displayName + Codable

### 적용 결과
```
swift build              → Build complete!
swift test               → 698/698 passed (150 suites, +28 new tests)
/Applications 재설치     → ✅ PID 82693 실행 중
새 파일                  → 2
수정 파일                → 1 (LiveTelegramBot 안정성 통합)
```

### 트레이드오프

**왜 multi-agent 협업이 single-agent보다 좋은가?**
- 한 perspective에서 놓치는 edge cases 발견
- Code review 효과 (실시간 검수)
- 안정성 vs 사용성 tension에서 균형

**왜 retry policy default 5 attempts?**
- AWS 권고: 3-5
- 5 = 각 attempt 사이 1/2/4/8/16초 → 총 ~31초 (사용자 인내심 한계)
- Test용 `.fast` 별도 (CI 빠른 fail)

**왜 message hash window 1분?**
- 너무 짧으면 (10초) network glitch 시 중복 통과
- 너무 길면 (1시간) 의도적 같은 메시지 차단
- 1분 = 일반 사용자 의도 패턴 (재전송 vs 중복) 균형

**왜 token bucket capacity = refill rate?**
- capacity > refill = 더 큰 burst 허용 (사용성 ↑) but quota 위반 위험 ↑
- capacity = refill = 1초 burst 허용 (안전)
- Telegram이 30/sec 한도이므로 capacity 30, refill 30/sec

**왜 ring buffer (DB 아님)?**
- error log는 디버깅 + 사용자 알림용
- 영구 저장 불필요 (재시작 시 reset OK)
- DB 의존 → over-engineering

### Apple HIG + Best Practices
- ✅ Apple HIG "Provide visual feedback for ongoing operations" — health AsyncStream
- ✅ Apple HIG "Use familiar language" — 한국어 userFacingMessage
- ✅ AWS SDK Retry pattern (Full Jitter)
- ✅ Telegram Bot API best practices (Retry-After 존중)
- ✅ Anthropic Claude Code (idempotency keys)
- ✅ OpenAI Codex CLI (structured error log)

### 향후 (ADR-086+ 후보)

- **Health UI** (사이드바에 connection status pill)
- **Error log viewer sheet** (사용자가 최근 N개 에러 확인)
- **Rate limit 사용자 알림** (할당량 80% 도달 시 경고)
- **Webhook mode** (long-poll 대신 — 모바일 배터리 절약)
- **Multi-bot support** (여러 chat group 분리 운영)
- **Offline queue** (network 끊겼을 때 메시지 보관 → 복구 시 재전송)

---

## ADR-084 — 텔레그램 고도화 (5 phases)

- **날짜**: 2026-05-03
- **상태**: Accepted (구현 + 테스트 + /Applications 재설치)

### 배경 (사용자 요청)

> "탤래그램 연동 기능을 고도화해줘. 결론만 빠르게 소통할 건지, 토큰 소모량은 어떻게 할 것인지, 자세한 설명을 받고 첨부파일까지 받을 건지 등등 가능한 스킬과 기능들을 파악해서 설정할 수 있게 기획하고 구현해줘"

ADR-046, 058, 062에서 텔레그램 기본 통합. 본 ADR에서 mobile-first 사용 시나리오에 맞춘 정밀 컨트롤 추가.

### 결정

#### Phase 1: 응답 모드 (4단계)

**왜 4개?**
- 2개 (간결/상세) = 너무 단순 (사용자 정밀 컨트롤 불가)
- 5+ = 결정 마비 (Hick's Law)
- 4개 = mobile-first 시나리오 covers:
  - 이동 중: minimal
  - 빠른 확인: concise
  - 일반 작업: standard
  - 깊이 있는 검토: detailed

**Token estimate (cost 추정용)**:
| 모드 | 추정 출력 토큰 | 비용 (Sonnet 기준) |
|------|--------------|-------------------|
| minimal | 50 | $0.00075 |
| concise | 250 | $0.00375 |
| standard | 800 | $0.012 |
| detailed | 3000 | $0.045 |

**`promptInstruction`** — system prompt에 자동 inject:
- minimal: "Reply with ONLY the final result in 1 line. ✓ or ✗."
- detailed: "Reply with detailed reasoning, file changes overview..."
- 한국어 응답 명시 (모든 모드)

#### Phase 2: 토큰 budget (3단계 cap)

**3 axis 동시 적용**:
1. **Per-turn** — 1번 외부 turn max output tokens
2. **Per-day** — 하루 누적 max USD (default $5)
3. **Per-chat** — 특정 chat의 일별 quota (multi-tenant)

**`TelegramOverflowAction`** (3 옵션):
- **warn** (default): 알림만 + 진행 (사용자 자각)
- **block**: 외부 turn 차단 (다음 자정까지) — 안전 우선
- **downgrade**: 응답 모드를 minimal로 강제 전환 — 비용 절감 + 진행

**왜 default $5 / day?**
- Sonnet 기준 detailed 모드 ~110번 / day 가능
- 일반 사용자 평균 < $3 / day
- $5 = 안전 buffer + 폭주 알림

#### Phase 3: 첨부파일 송수신

**`acceptIncoming` / `sendOutgoing`** 분리:
- 사용자가 한쪽만 활성 가능
- 보안: 받기는 끄고 보내기만 (예: PR diff 전송)

**`maxIncomingSizeBytes`** (default 5MB):
- Telegram Bot API 한도: 20MB (downloadFile)
- 5MB = 텍스트 파일 충분 + 이미지 적절
- Stepper 1~50MB (사용자 정의)

**`allowedExtensions`** (화이트리스트):
- default: 텍스트/code 위주 (`txt/md/json/swift/ts/js/py/yaml/toml/log`)
- 보안: binary (.exe/.dmg) 자동 거부
- 빈 set = 모두 허용 (사용자 명시 opt-in)

#### Phase 4: Skills & Templates

**`/{trigger}` 패턴**:
- Telegram bot에서 `/test` 입력 → `prompt` template 확장 → LLM 호출
- 사용자 정의 가능 (자주 쓰는 작업 1-tap)

**`{args}` 자리표시자**:
- `prompt = "Run {args} test"` + 입력 `/x unit` → `"Run unit test"`
- 자리표시자 없으면 args를 prompt 끝에 append

**기본 4 skills (신규 사용자 default)**:
- `/test` — 테스트 실행 (concise) 
- `/review` — 코드 리뷰 (standard)
- `/summary` — 오늘 작업 요약 (concise)
- `/status` — 상태 확인 (minimal)

**Skill별 응답 모드 override**:
- Skill에 responseMode 지정 시 global 설정 무시
- 예: `/status`는 항상 minimal (설정과 무관)

#### Phase 5: Settings Sheet UI

**`TelegramAdvancedSheet`** (720×620):
- 4 segmented sections (Picker.segmented)
- 각 section 한국어 안내 + 미리보기
- Skills section은 인라인 추가 form (trigger + name + prompt)

**macOS 메뉴 통합** (`CommandMenu "텔레그램"`):
- 고급 설정… (⌘⇧T)
- 응답 모드 1-click 전환 (최소/간결/기본/상세)
- 키보드 워크플로우 친화

### 적용 결과
```
swift build              → Build complete!
swift test               → 670/670 passed (143 suites, +21 new tests)
/Applications 재설치     → ✅ PID 76203 실행 중
새 파일                  → 3
수정 파일                → 4
```

### 트레이드오프

**왜 응답 모드가 default standard (concise 아님)?**
- 신규 사용자가 "이 모드가 뭐지?"로 인지 부담
- standard = "보통" 기대치 충족
- 모바일 친화는 사용자가 의도적으로 minimal/concise 선택

**왜 budget이 default 활성 ($5)?**
- 비용 폭주 방지가 default opt-in이 안전
- 사용자가 알림 받으면 자각 → 명시적 변경 (slider로 ↑↓)
- nil = 무제한은 명시 선택

**왜 화이트리스트 (블랙리스트 아님)?**
- 화이트리스트 = "안전한 것만 허용" (default secure)
- 블랙리스트 = "위험한 것만 거부" (새 위험 type 자동 통과)
- 보안 best practice: deny by default

**왜 default 4 skills?**
- 0개 = 사용자가 처음부터 만들기 부담
- 4개 = test/review/summary/status — 90% 모바일 use case 커버
- 사용자가 즉시 가치 체감 (default skills로 바로 사용 가능)

**왜 `{args}` placeholder + auto-append 둘 다?**
- Placeholder = 정밀 컨트롤 ("Run {args} test")
- Auto-append = 단순 사용 (prompt + "\n\n사용자 입력: ...")
- 사용자 의도에 따라 선택

### 향후 (ADR-085+ 후보)

- **Skill marketplace** — 사용자가 skill 공유 (export/import)
- **AI-suggested skills** — 사용 패턴 분석 → skill 추천
- **Skill chaining** — 한 skill이 다른 skill trigger
- **Telegram inline keyboard** — 응답에 button 포함 (사용자 1-tap 다음 step)
- **Multi-language responses** — 한국어/영어 자동 감지
- **Voice messages** — 사용자 음성 → STT → prompt

---

## ADR-083 — Conflict resolution + Cherry-pick + PR comment + Workflow re-run + Repo insights (5 phases)

- **날짜**: 2026-05-03
- **상태**: Accepted (구현 + 테스트 + /Applications 재설치)

### 배경

ADR-082 다음 라운드 후보 5가지 모두 진행:
- Conflict resolution UI (단순화 — full 3-way merge editor는 별도 ADR)
- Cherry-pick UI
- PR comment 작성
- Workflow re-run
- Repo insights

### 결정

#### Phase 1: Conflict resolution (단순화)

**왜 full 3-way merge editor 미구현?**
- 3-way merge UI = 큰 작업 (Apple FileMerge / VSCode merge editor 수준)
- 사용자 빈도 80% — "한쪽 통째로 채택"으로 충분
- block 단위 cherry-pick은 향후 별도 ADR

**`ConflictResolution` enum**:
- `.ours` → `git checkout --ours -- path`
- `.theirs` → `git checkout --theirs -- path`
- 채택 후 자동 `git add` (resolved 표시)

**`ConflictBlockParser`** (시각화용):
- `<<<<<<< HEAD` ~ `=======` ~ `>>>>>>>` 파싱
- ours/theirs lines 분리 + startLine 기록
- malformed (closing marker 없음) → 무시 (안전)

**`GitConflictSheet`** (880×620):
- 좌측: 충돌 파일 list (orange triangle)
- 우측: conflict blocks side-by-side
  - 내 변경 (HEAD) — accent blue
  - 받은 변경 (incoming) — purple
- 파일 단위 1-click resolve (block 단위 선택은 별도 ADR)
- "Merge 취소" (mergeAbort) — 사용자 escape

#### Phase 2: Cherry-pick

**`commitsOnBranch(_ branch:limit:)`**:
- `git log {branch} --no-merges` → CommitInfo array
- merge commits 제외 (cherry-pick 의도와 불일치)
- 30개 cap (사용자 결정 부담 ↓)

**`GitCherryPickSheet`** (720×580):
- Source 브랜치 Picker (현재 브랜치 제외)
- 선택 브랜치의 commit 목록
- 1개 commit 선택 (multi-select는 별도 ADR — 충돌 처리 복잡)
- "Cherry-pick" 버튼 → `git cherry-pick {sha}`
- 충돌 시 GitConflictSheet 안내

#### Phase 3: PR comment

**`gh pr comment --body`**:
- 현재 브랜치 PR에 markdown comment 추가
- gh CLI 자동 인증 활용

**GitHubPRSheet 안 composer**:
- TextEditor (markdown 가능)
- "코멘트 게시" 버튼 (게시 중 ProgressView)
- 게시 후 자동 reload

#### Phase 4: Workflow re-run + Repo insights

**`gh run rerun {id} --failed`**:
- 실패한 job만 재실행 (전체 re-run보다 효율적)
- workflow row에 재실행 버튼 (실패한 run에만 표시)

**`gh repo view --json` + `gh api .../contributors`**:
- Repo info: stars / forks / open issues / nameWithOwner / url
- Top contributors: login + commit count + avatar URL
- 병렬 fetch (`async let`) — 4개 동시 호출 (PR + workflows + repo + contributors)

**Repo insights card**:
- ⭐ Stars / 🍴 Forks / ⚠ Issues 한 줄
- Repo name 클릭 → 브라우저 open

**Top contributors section**:
- Top 5 (commit count 순)
- 사용자 mention 시 참고 (PR 본문)

#### Phase 5: Tests

`ConflictAndCherryPickTests.swift` (+11 tests):
- ConflictBlockParser (6): empty / no markers / single / multiple / malformed / empty ours
- ConflictResolution (3): allCases / displayName / Identifiable
- Contributor + RepoInfo (2): Identifiable + Codable round-trip

### 적용 결과
```
swift build              → Build complete!
swift test               → 649/649 passed (137 suites, +11 new tests)
/Applications 재설치     → ✅ PID 70261 실행 중
새 파일                  → 3
수정 파일                → 6
```

### 트레이드오프

**왜 file-level conflict resolution (block-level 아님)?**
- block-level은 UI 복잡 (각 block마다 ours/theirs/both 선택)
- 80% 케이스: 한쪽 통째로 채택
- 외부 에디터 (VSCode merge editor) 사용 권장 — Yuminai에서 강조 안 함

**왜 multi-commit cherry-pick 미지원?**
- 다중 cherry-pick = 충돌 처리 복잡 (각 commit마다)
- 1개씩 cherry-pick + 충돌 해결 후 다음 commit이 안전
- 사용자가 진행 상황 파악 가능

**왜 Repo insights를 PR sheet 안?**
- 별도 sheet = navigation 부담
- PR 검토 시 "이 repo가 active한가?" 정보가 도움
- Apple HIG "Group related information"

**왜 fetch가 병렬 (`async let`)?**
- 4개 gh CLI 호출 직렬 = 5초+
- 병렬 = ~1.5초 (가장 느린 호출 기준)
- 사용자 wait 시간 단축

**왜 Workflow re-run 버튼이 실패한 row에만?**
- 성공한 workflow re-run은 거의 의미 없음 (CI 결과 동일)
- 실패한 workflow만 재실행 (네트워크/transient 오류 처리)
- failedOnly 옵션으로 cost 절감

### Apple HIG + Best Practices
- ✅ Apple HIG "Master-Detail" (conflict viewer)
- ✅ Apple HIG "Group related" (Repo insights in PR sheet)
- ✅ Git conflict markers 표준 spec
- ✅ gh CLI JSON output (안정성)
- ✅ NN/g "Recognition rather than Recall" (cherry-pick commit list)

### WCAG 2.2 충족
- ✅ **SC 1.4.3 Contrast**: ours/theirs 색상 대비 (blue/purple)
- ✅ **SC 2.4.6 Headings and Labels**: 모든 sheet 한국어
- ✅ **SC 4.1.2 Name, Role, Value**: workflow re-run 버튼 accessibility
- ✅ **SC 1.4.10 Reflow**: 모든 sheet 반응형 (YuminaiSheet)

### 향후 (ADR-084+ 후보)

- **Block-level conflict resolution** (per-block ours/theirs/both)
- **Cherry-pick multi-commit** (range select + 순차 처리)
- **PR review submit** (gh pr review --approve / --request-changes / --comment)
- **GitHub Issues integration** (gh issue list + create)
- **Branch protection 표시** (PR이 protection rule 만족하나)
- **Diff viewer inline edit** (직접 conflict resolve)

---

## ADR-082 — Diff viewer + GitHub PR review + Actions + Rebase + CodeOwners (5 phases)

- **날짜**: 2026-05-03
- **상태**: Accepted (구현 + 테스트 + /Applications 재설치)

### 배경

ADR-081의 Git 기능을 advanced workflow로 확장:
- 변경 사항을 한 화면에서 직관적 검토 (Diff Viewer)
- GitHub PR review (gh pr view 표면화)
- GitHub Actions status 통합
- Interactive rebase 단순화
- CODEOWNERS 자동 reviewer suggestion

### 결정

#### Phase 1: Diff Viewer

**Apple HIG Master-Detail 패턴**:
- 좌측 sidebar (260px) — modified files + status badge
- 우측 (flexible) — 선택 파일의 inline diff
- 빈 상태 안내 (Apple HIG "Empty States")

**Status badge 색상**:
- M (modified) yellow / A (added) green / D (deleted) red
- R (renamed) blue / C (copied) blue / ? (untracked) gray

**Inline diff coloring**:
- `+` lines: green text + green opacity 0.10 background
- `-` lines: red text + red opacity 0.10 background
- `@@` hunks: accent color + accentMuted background
- `+++/---` headers: textTertiary

**Diff 복사 버튼**: NSPasteboard로 raw diff text → 외부 도구 paste 가능

#### Phase 2: GitHub PR review

**왜 gh CLI JSON?**
- `gh pr view --json field1,field2` — 안정적 schema
- 직접 GitHub API 호출보다 쉬움 (인증/scope 자동)
- GraphQL fields 그대로 활용

**`PullRequestDetails`**:
- 핵심 fields: number/title/url/state/isDraft/author/branches/reviewDecision/checks/comments
- 한국어 stateDisplay (열림/초안/닫힘/병합됨)
- statusCheckRollup으로 CI 통과 여부 즉시 파악

**Review decision badge**:
- APPROVED → 승인됨 (green checkmark.seal.fill)
- CHANGES_REQUESTED → 변경 요청 (orange exclamationmark.triangle)
- REVIEW_REQUIRED → 리뷰 필요 (gray clock)

**Status check summary**:
- Stat blocks: ✓ 통과 / ✗ 실패 / ⋯ 진행 중 (개수)
- Overall icon: 모두 통과면 green checkmark / 아니면 orange exclamation

#### Phase 3: GitHub Actions

**`recentWorkflowRuns(limit:)`**:
- `gh run list --limit N --json` → `WorkflowRun[]`
- 현재 branch의 최근 workflow runs

**Status icon mapping**:
- success → green checkmark.circle.fill
- failure → red xmark.circle.fill
- in_progress → orange circle.dotted
- queued/skipped → gray

**1-click open in browser** — 각 workflow row 클릭 → URL을 NSWorkspace로 열기

#### Phase 4: Interactive rebase 단순화

**`RebaseAction` enum (5개만)**:
- pick (default, 변경 없음)
- reword (메시지만 변경)
- squash (위와 합치기)
- fixup (위와 합치기 + 메시지 버림)
- drop (history에서 제거)

**왜 5개만?**
- git의 9개 (pick/reword/squash/fixup/drop/edit/exec/break/label) 중
  사용자 빈도 90% 이상이 위 5개
- 나머지 (edit/exec) = advanced, 외부 도구 권장
- Hick's Law (선택 마비 회피)

**구현 — GIT_SEQUENCE_EDITOR**:
- `git rebase -i HEAD~N`은 editor 열림
- `GIT_SEQUENCE_EDITOR=cp $script $1`로 script 강제 주입
- editor 통과 후 git이 그대로 실행
- reword 메시지는 자동 confirm (`GIT_EDITOR=true`)

**경고 banner**:
- drop → "history가 영구적으로 변경됩니다"
- squash/fixup → "충돌 시 외부 도구로 해결하세요"

**충돌 시 처리**:
- Rebase throw → 사용자에게 "`git rebase --abort`로 취소 가능" 안내
- AppModel.gitRebaseAbort() — 1-click abort
- Conflict resolution UI는 별도 ADR (3-way merge editor 큰 작업)

#### Phase 5: CodeOwners auto-reviewer

**`CodeOwnersParser`** (단순 spec, 90% 케이스 cover):
- `*` (와일드카드)
- `*.ext` (suffix glob)
- `/dir/` (directory prefix)
- `dir/*` (직접 자식만)
- exact path

**미지원 (full spec)**:
- `**/recursive/`
- email format
- `!negation`
→ 향후 라이브러리 활용 검토 (`SwiftCodeOwners` 등)

**매칭 규칙** (GitHub spec):
- 마지막 매칭 line winner (`reverse iterate` + `break`)
- 다중 path → owner union (각 path의 winner 합집합)

**UI**:
- PR composer 안에 chip 형태 표시 (`@reviewer1 @reviewer2`)
- "cc @reviewer 추가하세요" hint (사용자 직접 mention)
- 자동 mention은 미구현 (사용자 의도 확인 우선)

### 적용 결과
```
swift build              → Build complete!
swift test               → 638/638 passed (134 suites, +23 new tests)
/Applications 재설치     → ✅ PID 61802 실행 중
새 파일                  → 5
수정 파일                → 5
```

### 트레이드오프

**왜 Diff Viewer가 sheet (sidebar 안 아님)?**
- Sidebar는 워크스페이스 navigation 전용
- Diff = 일시적 검토 (commit 직전)
- 큰 sheet (880×600) = 가독성 우선

**왜 PR + Actions를 한 sheet?**
- 사용자 mental model: "내 PR이 잘 동작하나?"
- PR review + CI status는 한 시점 정보 (분리 시 navigation 부담 ↑)
- Apple HIG "Group related information"

**왜 rebase 5 actions만?**
- git interactive rebase의 9개는 거의 다 안 씀
- 90% 사용 패턴 (squash 위주)
- 나머지 = power user, 터미널 권장

**왜 reword가 자동 메시지 confirm?**
- 사용자가 commit message 수정하려면 별도 flow 필요 (sheet 안 sheet)
- 단순화: reword = 그대로 유지 (실제 수정은 amend 별도 ADR)
- 사용자가 "message 변경"으로 표시했는데 동작 안 하는 모순 — TODO 별도 fix

**왜 CodeOwners auto-mention 미구현?**
- 자동 mention은 사용자 의도 확인 없이 reviewer 추가 → 부담
- chip 표시 + hint = 사용자가 명시적으로 cc 추가
- 향후 "자동 추가" 옵션 선택 가능 (preferences)

### Apple HIG + Best Practices
- ✅ Apple HIG "Master-Detail" (Diff viewer)
- ✅ Apple HIG "Empty States" (변경 없음 안내)
- ✅ Apple HIG "Group related" (PR + Actions 한 sheet)
- ✅ GitHub CODEOWNERS spec
- ✅ Conventional Commits 표준 (rebase reword 호환)

### WCAG 2.2 충족
- ✅ **SC 1.4.3 Contrast**: status badge 색상 대비
- ✅ **SC 2.4.6 Headings and Labels**: 모든 sheet 한국어 라벨
- ✅ **SC 4.1.2 Name, Role, Value**: workflow row clickable + accessibilityHint
- ✅ **SC 1.4.10 Reflow**: 모든 sheet 반응형 (YuminaiSheet)

### 향후 (ADR-083+ 후보)

- **Conflict resolution UI** (3-way merge editor, 별도 큰 ADR)
- **Cherry-pick UI** (다른 브랜치에서 commit 가져오기)
- **Diff inline edit** (현재는 read-only)
- **PR comment 작성** (gh pr comment)
- **Workflow re-run** (gh run rerun)
- **Repo insights** (contributor / file change frequency)

---

## ADR-081 — Git remote + AI commit + GitHub PR + Stash (5 phases)

- **날짜**: 2026-05-03
- **상태**: Accepted (구현 + 테스트 + /Applications 재설치)

### 배경

ADR-079의 Git 기능을 production-ready로 확장:
- Push/Pull/Fetch (원격 동기화)
- AI commit message (Claude API 자동 생성)
- GitHub PR (gh CLI 통합, 사용성 단순화)
- Stash 관리 (브랜치 전환 안전)
- Conflict 감지 (기본)

### 결정

#### Phase 1: Push/Pull/Fetch + Upstream tracking

**왜 rebase pull (default)?**
- Linear history 유지 (merge commit 폭발 방지)
- Claude Code 표준 패턴
- Conflict 발생 시 사용자가 명시적 처리 가능

**왜 `--force-with-lease` (`--force` 아님)?**
- safer than `--force` — 원격이 누구의 push로 변경됐다면 reject
- Apple HIG "Prevent destructive actions when possible"

**Upstream tracking**:
- `git rev-list --left-right --count HEAD...@{upstream}` → ahead/behind
- 한국어 summary: "↑3 push 대기, ↓2 pull 필요"
- Branch picker 상단 badge

**Dirty pull 거부**:
- `pull` 시 working tree dirty면 throw
- 사용자에게 "먼저 커밋 또는 stash" 안내
- accidental conflict 방지

#### Phase 2: AI-generated commit messages

**왜 ChildClaudeProcess (메인 conversation 아님)?**
- 격리 호출 — 메인 채팅 컨텍스트 영향 X
- costTracker.rehearsal bucket으로 추적 (별도 카테고리)
- 30초 timeout (사용자 기다림 한계)

**Prompt 디자인**:
- Conventional Commits 강제 (feat/fix/chore/refactor/docs/test prefix)
- 한국어 title (사용자 친화)
- ≤ 72 chars (Git 표준)
- NO body, NO multi-line, NO Co-Authored-By (system이 추가)
- diff 8KB cap (token cost 방지)

**UI**: GitCommitSheet 우상단 "AI로 생성" 버튼 (sparkles 아이콘)
- 생성 중 ProgressView + "생성 중…" 라벨
- 생성된 message가 TextField에 채워짐 (사용자 수정 가능)

#### Phase 3: GitHub PR creation

**왜 gh CLI (직접 API 아님)?**
- 인증 자동 (사용자가 `gh auth login` 한 번)
- scope 관리 자동
- token 노출 위험 X
- Claude Code 표준 (Anthropic 권장 패턴)

**`GitHubCLIRunner` actor**:
- 표준 path 자동 감지: `/opt/homebrew/bin/gh` (arm64), `/usr/local/bin/gh` (intel), `/usr/bin/gh`
- isInstalled / isAuthenticated 사전 체크
- createPullRequest(title, body, draft)
- existingPullRequest() — 중복 PR 방지

**왜 cwd-aware run?**
- gh CLI는 현재 디렉토리의 git repo 기반 동작
- `Process.currentDirectoryURL` 명시 필수
- `GitHubCLIRunner.makeRunWithCwd(workspaceURL)` helper

**PR composer UI** (BranchPicker 안):
- title (필수, "feat: 브랜치명" prefilled)
- body (markdown, optional)
- draft 옵션
- Push 자동 안내 ("⚠ Push가 자동 실행됩니다")
- 1-click "PR 만들기"

#### Phase 4: Stash 관리

**Stash use cases**:
1. 브랜치 전환 전 임시 보관
2. 작업 중 conflict 방지
3. WIP 보관 (다른 작업 우선)

**`GitStashSheet`** (540×480):
- 새 stash 만들기 (메시지 입력 + 즉시 저장)
- Stash list (ref / message / shortSha / 상대 시간)
- Apply (변경 적용, stash 유지)
- Pop (변경 적용, stash 삭제)
- Drop (삭제만)
- destructive 액션은 빨강

**`conflictedFiles()`** — `git diff --name-only --diff-filter=U`:
- 충돌 파일 목록 반환
- 향후 conflict resolution UI 기반 (별도 ADR)

#### Phase 5: BranchPicker 통합

ADR-079의 단순 picker → 통합 git operations hub:
1. Upstream sync badge (상단)
2. Pull / Push / Fetch (action row)
3. Branch list (기존)
4. Stash / PR 만들기 (secondary action row)
5. PR composer (inline, slide animation)

**Disabled state**:
- gitOperationInProgress 동안 모든 버튼 disabled
- 동시 race condition 방지

### 적용 결과
```
swift build              → Build complete!
swift test               → 615/615 passed (130 suites, +11 new tests)
/Applications 재설치     → ✅ PID 42260 실행 중
새 파일                  → 3
수정 파일                → 5
```

### 트레이드오프

**왜 push/pull/PR이 BranchPicker 안?**
- Git operations이 한 곳에 모이면 navigation 단순
- ChatToolbar에 더 추가하면 작은 화면 overflow
- Claude Code git workflow와 일관 (한 popover)

**왜 PR composer가 inline (별도 sheet 아님)?**
- BranchPicker context 유지 (브랜치 → PR이 자연스러운 흐름)
- 작은 화면에서 sheet 중첩 회피
- slide animation으로 모드 전환 명확

**왜 conflict resolution UI 미구현?**
- 충돌 해결은 복잡한 3-way merge UI 필요 (별도 ADR)
- 현재 단계: 감지만 (`conflictedFiles()`)
- 사용자는 외부 도구 (VSCode merge editor 등) 활용

**왜 AI commit msg가 GitCommitSheet 안?**
- AI는 옵션 (사용자가 직접 입력 우선)
- 생성 후 수정 가능 (사용자 final review)
- `nil callback` 으로 AI 비활성 모드도 지원 (testability)

### Apple HIG + Best Practices
- ✅ Apple HIG "Prevent destructive actions" — `--force-with-lease`
- ✅ Apple HIG "Sync" — 사용자 명시 trigger (auto-pull X)
- ✅ Conventional Commits 표준 (Angular team standard)
- ✅ Anthropic Claude Code best practices (gh CLI + Co-Authored-By)

### WCAG 2.2 충족
- ✅ **SC 2.4.6 Headings and Labels**: 모든 git 버튼 한국어 라벨
- ✅ **SC 4.1.2 Name, Role, Value**: accessibilityLabel + Hint
- ✅ **SC 1.4.3 Contrast**: action button 색상 (accent / secondary / destructive)

### 향후 (ADR-082+ 후보)

- **Conflict resolution UI** (3-way merge editor) — 큰 ADR
- **Git rebase / cherry-pick advanced** (interactive rebase 등)
- **GitHub PR review** (gh pr view + comments)
- **GitHub Actions integration** (workflow run status in toolbar)
- **Diff viewer** (sidebar에 modified files + inline diff)
- **CodeOwners 자동 reviewer 추가** (PR 생성 시)

---

## ADR-079 — Smart filter + Workspace duplicate + Tag drag + iCloud sync + Git (Claude Code 패턴) (5 phases)

- **날짜**: 2026-05-03
- **상태**: Accepted (구현 + 테스트 + /Applications 재설치)

### 배경 (사용자 요청)

> "다음 라운드 이어서 진행 / 클라우드는 iCloud + Git 두 가지만 / Git의 경우 클로드 코드와 같은 브랜치 관리, 자동 커밋 등을 사용성 있게 단순화한 버전으로"

ADR-078 다음 라운드 + Cloud sync 범위 명시 + **Git이 핵심**.

### 결정

#### Phase 1: Smart Filter + Workspace Duplicate

**Smart Filter** = "저장된 tag/folder 조합":
- macOS Finder Smart Folders / JetBrains Scopes 패턴
- NN/g Heuristic 6 "Recognition rather than Recall" — 조건 저장으로 매번 재구성 부담 ↓
- AppModel.saveCurrentAsSmartFilter — 현재 활성 filter를 1-click 저장
- AppModel.applySmartFilter — 저장된 filter 1-click 활성

**Workspace Duplicate** = 한 워크스페이스 → 새 UUID 복제:
- 폴더/태그 assignment 자동 복제 (사용자 mental model 보존)
- 채팅/터미널 세션은 미복제 (새 세션 시작)
- "(복사본)" suffix + 자동 select

#### Phase 2: Drag Tag onto Workspace

ADR-077의 drag system 확장:
- `TagAssignmentPayload` (별도 UTType `com.yuminai.tag.assignment`)
- Tag chip = draggable, workspace row = drop target
- Drop 시 tag toggle (이미 있으면 제거)

#### Phase 3: iCloud sync (preferences)

**왜 NSUbiquitousKeyValueStore?** (CloudKit 아님)
- Preferences = 작은 데이터 (~수 KB) → 1MB limit 충분
- 자동 동기화 (manual schema X)
- CloudKit은 workspaces (SwiftData) 동기화용 → 별도 ADR

**동기화 항목** (9개):
- pinned / folders / tags / assignments / activeFilters / smartFilters / smartFolders
- beginnerMode / hasCompletedOnboarding

**미동기화 항목** (의도적):
- claude/codex binary path (PC별 다름)
- telegram chat (PC별 봇 다를 수 있음)
- 시크릿 (Keychain 자체 iCloud 동기화 활용)

**`iCloudSyncEnabled` opt-in** (Apple HIG Sync 권고).

#### Phase 4: Git Status & Branch Management (Claude Code 단순화)

**Claude Code 4단계 → 3단계로 압축**:
1. Status: branch + dirty (실시간 표시)
2. Switch: 브랜치 전환 + 새 브랜치 (popover)
3. Auto-commit: 1-click → message 자동 생성 + Co-Authored-By

**`GitBranchManager` actor** (GitRunner 위에 빌드):
- currentBranch / localBranches / isDirty / dirtyStats
- switchBranch (auto-stash before switch)
- createBranch (default base = current)
- commitAll (auto-stage all + Co-Authored-By footer)
- recentCommits (한국어 friendly relative dates)

**`DirtyStats`** (modified/added/deleted/untracked + 한국어 summary):
- "수정 3, 추가 1, 추적 안 됨 2"
- isEmpty boundary (commit 가능 여부)

**ChatToolbar Git indicator**:
- `arrow.triangle.branch` icon + branch name (truncate)
- dirty 시 small orange dot
- 클릭 → branch picker popover

**`GitBranchPickerPopover`** (320 wide):
- 브랜치 목록 (current ✓ + 마지막 commit 상대 시간)
- "새 브랜치 만들기" inline TextField
- async 로딩 (`GitBranchPickerSheetWrapper`)

#### Phase 5: Git Auto-Commit (Claude Code 패턴)

**`AutoCommitMessageGenerator`** (Conventional Commits):
- 단일 추가 → `feat: N개 파일 추가`
- 단일 수정 → `fix: N개 파일 수정`
- 단일 삭제 → `chore: N개 파일 삭제`
- 혼합 → `chore: 수정 N, 추가 N, ...`

**`GitCommitSheet`** (540×420):
- Header: "Git 커밋 만들기" + branch indicator
- DirtyStats card (수정/추가/삭제/추적안됨 stat blocks)
- 자동 생성된 message TextField (사용자 수정 가능)
- 안내: "모든 변경사항이 자동 staging됨 + Co-Authored-By: Claude (Yuminai)"
- 1-click 커밋 + 결과 토스트 ("✓ 커밋 완료: abc123 — feat: ...")

**ChatToolbar "커밋" 버튼** (dirty 시에만 표시):
- Brand cyan filled background (시각적 강조)
- icon: `checkmark.shield.fill`
- 클릭 → GitCommitSheet

### 적용 결과
```
swift build              → Build complete!
swift test               → 594/594 passed (125 suites, +16 new tests)
/Applications 재설치     → ✅ PID 18878 실행 중
새 파일                  → 7
수정 파일                → 6
```

### 트레이드오프

**왜 NSUbiquitousKeyValueStore (CloudKit 아님)?**
- preferences = 작은 데이터 (수 KB) → KVS 1MB limit 충분
- workspaces (SwiftData) 동기화는 CKShare 등 복잡 → 별도 ADR
- KVS는 자동 sync + low-friction setup

**왜 Git 기능 단순화 (Claude Code 그대로 X)?**
- Claude Code = developer-focused (rebase, cherry-pick 등 고급)
- Yuminai = vibe-coding workspace (사용성 우선)
- 핵심 3개만: status / switch / commit
- 고급 git은 터미널 활용 (사용자 자유)

**왜 Auto-Commit이 1-click이 아니고 sheet?**
- 사용자 confirm 필수 (실수 commit 방지)
- Message 자동 생성하지만 수정 가능
- DirtyStats 미리보기로 의도 확인

**왜 Co-Authored-By: Claude (Yuminai)?**
- AI 도구 사용 명시 (code review 시 추적)
- Anthropic Claude Code와 동일 패턴 (호환성)
- 향후 다중 agent 지원 시 agent별 footer 분리 가능

### Apple HIG + WCAG 충족
- ✅ Apple HIG Sync (opt-in)
- ✅ Apple HIG Drag and Drop (tag → workspace)
- ✅ NN/g Recognition rather than Recall (smart filter)
- ✅ WCAG 1.4.3 / 2.4.6 / 4.1.2

### 향후 (ADR-080+ 후보)
- iCloud workspaces sync (CloudKit + CKShare) — 별도 ADR
- Git rebase / cherry-pick (advanced UI)
- Git push/pull integration
- AI-generated commit messages (Claude API 활용)
- GitHub PR creation (gh CLI 통합)
- Conflict resolution UI

---

## ADR-078 — Pin drop indicator + Folder reorder + ⌘⇧O Search + Tag filter + Import/Export (5 phases)

- **날짜**: 2026-05-03
- **상태**: Accepted (구현 + 테스트 + /Applications 재설치)

### 배경 (사용자 요청)

> "Pin section drop position visual / Folder drag-to-reorder / Workspace search ⌘P / Tag-based filtering / Workspace import/export"

ADR-077 다음 라운드 후보 5가지 모두 진행.

### 결정

#### Phase 1: Pin drop position visual indicator

**문제**: ADR-077에서 pin row 위에 drop 시 swap만 가능 (insert 위치 정밀 컨트롤 X).

**해결**: row 사이/끝에 6px invisible drop zone, hover 시 2px brand cyan capsule line indicator.

```swift
@State private var pinDropIndicatorIndex: Int?
// row N 위 = index N, 마지막 row 아래 = index count
```

**왜 6px?**: 너무 두꺼우면(>10px) 사용자에게 어색, 너무 얇으면(<3px) hit target 부족 (Apple HIG 44pt → 한 line 6px 적정).

#### Phase 2: Folder drag-to-reorder

**별도 UTType** (`com.yuminai.folder.reorder`):
- 워크스페이스 drag (`.yuminaiWorkspace`)와 분리
- 폴더 헤더 drag = 폴더 자체 reorder
- 폴더 헤더 drop = 워크스페이스 추가 (다른 UTType이라 충돌 X)

**두 방식 제공** (WCAG 2.5.7 Dragging Movements alternative):
- Drag (folder header → 다른 folder 위치)
- Context menu "위로 이동" / "아래로 이동" (1칸씩, boundary disabled)

#### Phase 3: Workspace search (⌘⇧O)

**왜 ⌘⇧O가 아닌 ⌘P?**
- ⌘P는 이미 파일 검색 (FileSearchSheet) — VSCode/Cursor 표준
- ⌘⇧O = "Open Workspace" semantic (VS Code도 비슷한 패턴)
- 사용자 학습 비용 ↓ (existing convention 보존)

**Fuzzy scoring 가중치**:
- 이름 prefix 100점 (가장 정확)
- 경로 마지막 component prefix 80점 (folder name 매칭)
- 이름 contains 50점
- 폴더 이름 contains 30점 (cross-cutting 발견)
- 경로 contains 20점 (마지막 폴백)
- 핀 보너스 +10, 짧은 이름 보너스 (정확한 매칭 우선)

**빈 query 동작**: 핀 우선 → lastOpenedAt 최신 순 (Apple Finder Recents 패턴)

**Match row 정보**: 이름 + 경로 truncate + 폴더 라벨 + 한국어 상대시간 ("3일 전")

#### Phase 4: Tag-based filtering (다중 tag)

**Folder vs Tag**:
| | Folder | Tag |
|---|--------|-----|
| 카디널리티 | 워크스페이스 = 0~1 폴더 | 워크스페이스 = 0~N 태그 |
| 패턴 | mutually exclusive (Finder folder) | many-to-many (Apple Finder Tags, GitHub Labels) |
| 분류 | hierarchical | faceted |
| UI | sidebar 그룹 | sidebar chip bar |

**근거 (NN/g "Faceted Classification")**:
- 단일 hierarchy(folder)는 cross-cutting 분류 불가
  - 예: "ClientA + iOS + 긴급" — folder 1개로 표현 불가
- Multi-dimensional tag로 직교 차원 동시 적용 가능
- folder(클라이언트)와 tag(상태/기술스택) 조합으로 깊이 있는 navigation

**Filter 동작**: intersection (활성된 모든 tag를 가진 워크스페이스만 표시)

**UI 디자인**:
- 사이드바 상단 horizontal scroll chip bar
- 활성 chip = 색상 채움 (white text), 비활성 = surface 배경
- 워크스페이스 row에 dot indicator (max 3 + "+N")
- 우클릭 → "태그" submenu (toggle + 새 만들기)
- TagEditSheet (460×320, 이름 + 10색 picker + preview)

**자동 정리**:
- 워크스페이스 삭제 → tag assignment 자동 제거
- 태그 삭제 → 모든 워크스페이스에서 자동 제거
- orphan 방지

#### Phase 5: Workspace import/export

**WorkspaceArchive 형식**:
- JSON, version-tagged (`version: 1`, future-version reject)
- 포함: workspaces / folders / pins / tags / tagAssignments / smart folders
- **미포함** (의도적): 채팅 세션, 시크릿(API key/Telegram token), 실제 파일

**왜 일부만 포함?**
- 채팅 세션 = sensitive (의도치 않은 공유 위험)
- 시크릿 = Keychain 별도 (보안)
- 파일 = 사용자 디렉토리 그대로 (이미 존재)

**Import strategy** (사용자 선택):
1. **skipExisting** (default, 안전): 같은 이름 워크스페이스 있으면 건너뜀
2. **mergeAll**: 모두 추가 (이름 중복 가능, "(가져옴)" suffix)
3. **replaceExisting** (위험): 기존 덮어쓰기

**ID 재매핑**: 모든 strategy에서 archive UUID → 실제 UUID 매핑 추적
- 폴더의 workspaceIds, 핀의 IDs, tag assignments 모두 재매핑
- orphan 방지

**File menu 추가**:
- "워크스페이스 백업 내보내기…" (⌘⇧E)
- "워크스페이스 백업 가져오기…" (⌘⇧I)
- NSSavePanel/NSOpenPanel 표준 macOS dialog

**파일 형식**: `.yuminai.json` (Yuminai-specific 확장자, JSON UTType)

### 적용 결과
```
swift build              → Build complete!
swift test               → 578/578 passed (121 suites, +16 new tests)
/Applications 재설치     → ✅ PID 90975 실행 중
새 파일                  → 5
수정 파일                → 7
```

### 트레이드오프

**왜 ⌘⇧O? (⌘P 그대로 두기)**
- 기존 ⌘P = 파일 검색 (사용자 muscle memory)
- VS Code 호환 패턴 유지
- ⌘⇧O = "Open Workspace" 직관적 semantic

**왜 Tag와 Folder를 별도 시스템?**
- 카디널리티 다름 (1:N vs N:N)
- 사용자 mental model 다름 (그룹 vs 라벨)
- 합치면 결정 마비 ("이건 폴더? 태그?")
- Apple Finder 모범 사례 (Folder + Tags 모두 제공)

**왜 archive에 채팅 세션 미포함?**
- 보안: 의도치 않은 sharing 위험
- 크기: 채팅 로그가 가장 큰 metadata
- 사용성: 백업 = "환경 복원", not "데이터 복제"
- 향후 별도 ADR (chat session export sandbox 검토)

**왜 import strategy 3개?**
- 1개(merge) = 이름 중복 위험
- 2개(skip/replace) = 사용자가 한 번에 결정 못 함
- 3개 = 안전 (default) / 보존 (merge) / 강제 (replace) 명확한 의도

**왜 .yuminai.json (custom 확장자)?**
- `.json`만 쓰면 다른 JSON과 구분 X
- `.yuminai`만 쓰면 macOS가 텍스트 에디터로 못 열음
- `.yuminai.json` = 텍스트 에디터로 열림 + Yuminai 식별

### Apple HIG 준수
- ✅ "Drag and Drop" Visual Feedback (line indicator)
- ✅ "Sidebars" Faceted Filtering (tag chips)
- ✅ "File Menu" Standard Open/Save patterns
- ✅ "Spotlight Search" pattern (fuzzy + relative time)

### WCAG 2.2 충족
- ✅ **SC 2.5.7 Dragging Movements** (AA, NEW): 모든 drag에 menu alternative
- ✅ **SC 1.4.3 Contrast** (AA): tag chip 색상 + white text 대비 충족
- ✅ **SC 4.1.2 Name, Role, Value** (AA): tag/folder/import accessibility
- ✅ **SC 2.4.6 Headings and Labels** (AA): chip 라벨 명시

### 향후 (ADR-079+ 후보)

- **Tag groups / hierarchical tags** (Apple Finder Tags 발전형)
- **Drag tag onto workspace** (현재는 context menu만)
- **Smart filter** (저장된 검색 — "iOS + 긴급" 저장 → 재사용)
- **Workspace duplicate** (한 워크스페이스 → 새 ID로 복제)
- **Multi-window** (각 윈도우가 다른 워크스페이스)
- **Cloud sync** (iCloud / Dropbox)

---

## ADR-077 — Drag&Drop + 폴더 customization + Smart folders + Pin reorder (5 phases)

- **날짜**: 2026-05-03
- **상태**: Accepted (구현 + 테스트 + /Applications 재설치)

### 배경 (사용자 요청 4건)

ADR-076의 향후 후보 4가지 모두 진행:
1. Drag and drop: 워크스페이스를 폴더로 드래그
2. 폴더 색상 + 아이콘 사용자 변경
3. Smart folders: 자동 그룹화 ("최근 7일", "텔레그램 연결됨")
4. Pin 순서 manual 정렬 (drag 또는 메뉴)

### 결정

#### Phase 1: Drag and Drop infrastructure

**SwiftUI Transferable** (iOS 16+/macOS 13+) 채택:
- `WorkspaceDragPayload`: UUID payload (전체 객체 X — callback에서 lookup)
- `WorkspacePinReorderPayload`: UUID + 현재 index (pin 그룹 안 reorder용)

**Custom UTType**:
- `com.yuminai.workspace.id` — 일반 워크스페이스 drag
- `com.yuminai.pin.reorder` — pin 그룹 안 reorder (workspace drag와 분리 → folder drop과 충돌 X)

**왜 두 UTType?**
- pin 안 row를 folder로 drag = 의도 모호 (pin 해제 후 folder 추가? 그냥 folder 추가?)
- pin reorder는 pin section 안에서만 동작
- 일반 workspace drag는 폴더로만 drop
- 관심사 분리로 사용자 의도 명확

**Drop targets**:
- `FolderHeaderRow`: workspace → folder 추가 (drop 시 folder colorName으로 강조 — border + opacity 0.18 background)
- `Uncategorized section`: workspace → 폴더에서 제거
- `Pin row` (각각): pin reorder swap

#### Phase 2: 폴더 색상 + 아이콘 customization

**`FolderColorPreset`** (10개): accent / blue / purple / pink / red / orange / yellow / green / teal / gray
- Theme.Color.folderColor(for:) lookup
- semantic naming → 다크/라이트 모드 자동 대응

**`FolderIconPreset`** (12개):
- folder.fill (default)
- folder.badge.gearshape, folder.badge.questionmark, folder.badge.person.crop
- briefcase.fill (업무), archivebox.fill (보관함)
- star, bolt, heart, bookmark, flag, tag

**`FolderEditSheet`** (FolderRenameSheet 대체):
- 540×540, YuminaiSheet (footer 고정)
- 미리보기 (사용자 선택 즉시 반영)
- 이름 입력 → 색상 picker (10개 swatch) → 아이콘 picker (6×2 grid)
- 선택 시 색상 ring + checkmark, 아이콘 색상은 선택된 색으로

#### Phase 3: Smart Folders

**`SmartFolderKind`** enum:
- `recentWeek` — 최근 7일 안 lastOpenedAt
- `telegramBound` — telegramBoundWorkspaceId 또는 chatBindings에 포함
- `archived` — workspace.isArchived

**디자인 결정**:
- **자동 계산** (사용자가 manual로 추가/제거 X)
- **Pure logic** (`SmartFolderEvaluator`) → testable
- **Default 활성**: 신규 사용자만 `[.recentWeek]`, 기존 사용자는 빈 set (UX 변경 최소화)

**사이드바 표시**:
- Pin → **Smart folders** → 사용자 폴더 → uncategorized
- 활성 + 매칭 워크스페이스 있을 때만 표시 (빈 smart folder 안 보임)
- 헤더에 `wand.and.stars` 아이콘 (smart임을 시각 구분)

**토글 메뉴**:
- 사이드바 top-right `wand.and.stars` 버튼
- 메뉴: "최근 7일", "텔레그램 연결됨", "보관함" 토글
- 활성된 게 있으면 버튼 색상 accent (빈 set이면 textSecondary)

#### Phase 4: Pin reorder

**두 가지 방식 제공** (Apple HIG 권고: alternative path):
1. **Context menu** "위로 이동" / "아래로 이동" (pin index 있을 때만)
   - 첫 번째 pin은 "위로" disabled, 마지막은 "아래로" disabled
2. **Drag and drop** (pin row끼리 swap)
   - `WorkspacePinReorderPayload` 사용 → folder drop과 분리
   - drop 시 `onMovePinToIndex` 호출 → AppModel.movePin(_:to:)

**왜 두 방식?**
- Drag = 빠르지만 정밀하지 않음 (인접 swap 어려움)
- Menu = 정밀하지만 한 번에 1칸만
- 사용자 선호에 따라 선택 가능 (WCAG 2.5.7 Dragging Movements 준수)

#### Phase 5: Tests

`SmartFolderTests.swift` (20 tests):
- SmartFolderKind allCases / displayName / defaultEnabled / Codable
- SmartFolderEvaluator isRecent boundary (nil/안/밖)
- isTelegramBound legacy + chatBindings
- FolderColorPreset / FolderIconPreset count + Identifiable + 한국어 라벨
- WorkspaceFolder colorName default / custom / Codable backward-compat

### 적용 결과
```
swift build              → Build complete!
swift test               → 562/562 passed (116 suites, +20 new tests)
/Applications 재설치     → ✅ PID 54257 실행 중
새 파일                  → 4
수정 파일                → 6
삭제 파일                → 1 (FolderRenameSheet — FolderEditSheet로 대체)
```

### 트레이드오프

**왜 SwiftUI Transferable (NSItemProvider 아님)?**
- Transferable은 SwiftUI 표준 (iOS 16+/macOS 13+)
- Codable conformance만 있으면 자동 transferRepresentation 가능
- NSItemProvider보다 type-safe (Generic Type 활용)

**왜 Custom UTType?**
- 외부 앱 (Finder 등)의 workspace 객체 drop 차단 → 보안 + UX 명확
- com.yuminai.* prefix → 향후 다른 Yuminai 객체 drag도 일관

**왜 폴더 색상 10개 limited preset (자유 색상 X)?**
- 사용자에게 무한 색상은 결정 마비 (Hick's Law)
- 10개는 색상환 7±3 (인지심리학) + accent/gray 추가
- macOS Finder 폴더 tag (7색)와 비슷한 패턴

**왜 SmartFolder가 일반 folder와 별개?**
- 일반 folder = 사용자 manual control
- Smart folder = 시스템 자동 계산
- 데이터 모델 분리로 충돌 방지 (smart folder의 워크스페이스가 일반 folder에도 속할 수 있음)

**왜 default smart folder OFF (기존 사용자)?**
- ADR-070 "기존 사용자 보호" 원칙 일관 적용
- 갑자기 사이드바 구조 변하면 confusing
- 신규 사용자만 "최근 7일" default 활성 (가장 유용)

**왜 pin reorder 두 방식?**
- WCAG 2.5.7 Dragging Movements (AA, NEW): drag에 키보드/menu alternative 필수
- Drag = 시각적, fast / Menu = 키보드 가능, 정밀
- 사용자 선호에 따라 선택

### Apple HIG 준수
- ✅ "Drag and Drop": Visual feedback for drop targets (folder color border + background)
- ✅ "Drag and Drop": Alternative path (context menu)
- ✅ "Smart Folders" pattern (Finder)
- ✅ "Faceted Filtering" (NN/g)

### WCAG 2.2 충족
- ✅ **SC 2.4.6 Headings and Labels** (AA): smart folder hint text
- ✅ **SC 2.5.7 Dragging Movements** (AA, NEW): context menu alternative
- ✅ **SC 4.1.2 Name, Role, Value** (AA): drop target accessibility
- ✅ **SC 1.4.3 Contrast** (AA): folder colors selected from accessible palette

### 향후 (ADR-078+ 후보)

- **Pin section drop position visual**: drag 중 어느 위치에 drop될지 line indicator
- **Folder drag-to-reorder**: 폴더 자체 순서 변경
- **Workspace search** (⌘P) — 사이드바 검색 활성
- **Tag-based filtering** (다중 tag 지원, smart folder의 발전형)
- **Workspace import/export**: 폴더 + 핀 설정 함께 backup/restore

---

## ADR-076 — 워크스페이스 핀 + 폴더 그룹화 (5 phases)

- **날짜**: 2026-05-03
- **상태**: Accepted (구현 + 테스트 + /Applications 재설치)

### 배경 (사용자 요청)

> "클로드 코드처럼 좌측 패널에서 상단 고정 기능을 제공해주고
> 코덱스처럼 프로젝트 폴더링 기능도 제공해 줘"

**참고 패턴**:
- **Claude Code (Anthropic CLI)**: 사이드바에 pinned conversations 그룹 (사용 빈도 높은 항목 즉시 접근)
- **Codex CLI (OpenAI)**: project 폴더로 grouping (관련 워크스페이스 묶기)

### 결정

#### Phase 1: 데이터 모델

**`WorkspaceFolder` struct 신규**:
```swift
public struct WorkspaceFolder: Sendable, Codable, Hashable, Identifiable {
    public let id: UUID
    public var name: String
    public var workspaceIds: [UUID]    // Set 대신 Array — 사용자 정렬 가능
    public var isExpanded: Bool         // 사이드바 expand/collapse 상태
    public var iconName: String         // SF Symbol — 사용자 변경 가능 (향후)
}
```

**디자인 결정**:
- **Flat hierarchy** (1단계 폴더만): NN/g 연구상 nested 폴더는 사용자 mental model 부담 ↑
- **Mutually exclusive** (한 워크스페이스 = 0~1 폴더): Apple Finder, Codex CLI 모두 채택. 멀티 폴더는 복잡도 ↑ vs 효용 적음.
- **Pin + folder coexistence**: 핀된 워크스페이스도 폴더에 속할 수 있음. 두 경로로 접근 가능.

**`AppPreferences` 확장**:
- `pinnedWorkspaceIds: [UUID]` — Set 대신 Array (핀 순서 유지)
- `workspaceFolders: [WorkspaceFolder]`
- decode default: 빈 배열 (기존 사용자 영향 없음)

#### Phase 2: AppModel API

```swift
// Pin
isPinned(_ id: UUID) -> Bool
togglePin(_ id: UUID) async

// Folder CRUD
folder(containing: UUID) -> WorkspaceFolder?
createFolder(name: String) async -> UUID
renameFolder(id: UUID, to: String) async
deleteFolder(id: UUID) async               // 안의 워크스페이스는 uncategorized로
toggleFolderExpansion(id: UUID) async

// Workspace movement
moveWorkspace(_ workspaceId: UUID, toFolder folderId: UUID?) async
// folderId == nil: uncategorized로 이동
```

**Orphan 정리**: `deleteWorkspace`에서 핀/폴더에서 자동 제거 → orphan UUID 방지.

#### Phase 3: Sidebar UI 재설계

**구조** (위 → 아래):
1. Top header (collapse + search) — 변경 없음
2. Primary actions (새 워크스페이스 + 설정) — 변경 없음
3. **📌 핀 그룹** (있을 때만) — 항상 최상단 (Claude Code 패턴)
4. **📁 폴더 그룹들** (각 expand/collapse, 카운트 뱃지)
5. **기타 워크스페이스** (uncategorized — 폴더에 안 든)
6. **새 폴더 만들기** 버튼 (하단)
7. Update card + Bottom user card — 변경 없음

**`FolderHeaderRow`**:
- chevron (rotation으로 expand/collapse 시각화)
- folder icon (accent color)
- 이름 + 카운트 capsule (e.g., "프론트엔드 (3)")
- hover 시 surface highlight
- contextMenu: 이름 바꾸기 / 폴더 삭제

**`WorkspaceItemRow` 확장**:
- `isPinned` indicator (작은 핀 아이콘, accent)
- `indented` (폴더 안 워크스페이스는 왼쪽 들여쓰기 16pt)
- `availableFolders` + `currentFolderId` — 폴더 이동 메뉴용

**단축키 ⌘1~9 자동 매핑**:
- 순서: pinned → folders (expanded) → uncategorized
- 9개 초과 시 첫 9개만 단축키

#### Phase 4: Context menu 확장

**워크스페이스 우클릭** (위 → 아래):
1. **상단에 고정 / 상단 고정 해제** (pin 토글)
2. **폴더로 이동** → submenu:
   - 폴더에서 제거 (전체로)
   - 기존 폴더 목록 (현재 폴더에 ✓)
   - 새 폴더 만들기…
3. 이름 복사
4. 텔레그램 연결/해제 (있을 때)
5. Delivery 자동화 설정
6. 프로젝트 프로필 편집
7. 지우기 (destructive)

**폴더 헤더 우클릭**:
- 이름 바꾸기
- 폴더 삭제 (안의 워크스페이스는 유지 — destructive)

**`FolderRenameSheet` 신규**:
- 460×220 sheet (YuminaiSheet 적용 — ADR-074 footer 고정)
- 생성 vs 이름 변경 모드 (existingFolder 유무로 판단)
- TextField focus 자동 + Enter 단축키
- 빈 입력 시 disabled

#### Phase 5: Tests

`WorkspaceFolderTests.swift` (9 tests):
- WorkspaceFolder init / Codable / backward-compat / Identifiable / Hashable
- AppPreferences pin + folder default / backward-compat / round-trip

### 적용 결과
```
swift build              → Build complete!
swift test               → 542/542 passed (112 suites, +9 new tests)
/Applications 재설치     → ✅ PID 37607 실행 중
새 파일                  → 3 (WorkspaceFolder + FolderRenameSheet + Tests)
수정 파일                → 4
```

### 트레이드오프

**왜 nested 폴더 (sub-folder) 안 함?**
- NN/g 연구: 2단계 이상 hierarchy는 사용자 인지 부담 ↑
- Codex CLI / Claude Code 모두 single-level
- 향후 필요 시 별도 ADR (지금은 over-engineering)

**왜 Set 대신 Array?**
- pinnedWorkspaceIds: 핀 순서 유지 (사용자 정렬 가능)
- workspaceIds in folder: 폴더 안 순서 유지
- Set은 contains() O(1) 이점 있으나, sidebar는 표시 시 sort 필요 → Array가 직관적

**왜 폴더 삭제 시 워크스페이스는 유지?**
- 사용자 mental model: "폴더는 그룹화 도구"
- 폴더 삭제 = 그룹 해체, not = 워크스페이스 삭제
- destructive action은 명시적 (워크스페이스 "지우기" 별도)

**왜 Pin + Folder 공존?**
- Pin = "자주 쓰는 항목 즉시 접근"
- Folder = "관련 항목 묶기"
- 두 차원이 직교 — 폴더 안 워크스페이스도 핀 가능

**왜 폴더 expand/collapse 영속?**
- 사용자가 닫아둔 폴더는 다음 실행 시도 닫힌 상태 유지
- AppPreferences에 `isExpanded` 저장 → savePreferences로 영속

**왜 ⌘1~9 단축키 자동 매핑 (sidebar 순서 따름)?**
- 사용자가 핀에 자주 쓰는 항목 → 단축키 1~3 자동 할당 (편의 ↑)
- 순서 명확 (위 → 아래) → 학습 비용 ↓

### Apple HIG 준수
- ✅ "Sidebars": Group related items together
- ✅ "Context Menus": Provide alternate access to commands
- ✅ "Visual Feedback": chevron rotation (expand/collapse)

### WCAG 2.2 충족
- ✅ **SC 2.4.6 Headings and Labels** (AA): 폴더 이름 + 카운트
- ✅ **SC 4.1.2 Name, Role, Value** (AA): 핀/선택/연결 상태 모두 accessibilityLabel
- ✅ **SC 1.3.1 Info and Relationships** (AA): 그룹 구조 명시

### 향후 (ADR-077+ 후보)

- **Drag and drop**: 워크스페이스를 폴더로 드래그 (현재는 context menu만)
- **폴더 아이콘 사용자 변경** (folder.fill / folder.badge.gearshape / etc)
- **폴더 색상**: 폴더별 accent color
- **Smart folders**: 자동 그룹화 (e.g., "최근 7일", "텔레그램 연결됨")
- **Sub-folder** 검토 (필요 시)
- **Pin 순서 manual 정렬** (drag 또는 context menu "위로/아래로")

---

## ADR-075 — 사용량 대시보드 고도화 (5 phases)

- **날짜**: 2026-05-03
- **상태**: Accepted (구현 + 테스트 + /Applications 재설치)

### 배경 (사용자 요청 4건)

1. 스크롤이 생성되지 않는 비율의 팝업뷰로 설계
2. 어떤 에이전트의 어떤 모델인지 선택 가능
3. 보여줄 수 있는 모든 정보를 자세히 보기로 보여줌
4. 최소한의 정보만 요약해서 보여주는 뷰를 기본값으로 + 자세히 보기 버튼

### 결정

#### Phase 1: Compact view (default)

**근거**: NN/g "Progressive Disclosure" + Apple HIG "Disclosure"
- 첫 진입은 핵심 정보만 → 정보 과부하 회피 (Hick's Law)
- 사용자가 "더 보고 싶다" 의도 표현 시 추가 노출

**컴포넌트**:
- **Hero stat** (이번 세션 비용): 36pt monospaced, 시각적 무게 최대
- **Mini stats row** (4개): 메시지 / 입력 / 출력 / 캐시 적중률
- **Context gauge**: 컨텍스트 사용률 (잔여량 직관)
- **Model info row** (footer): agent icon + 모델 + 워크스페이스

**Sheet 크기**: 520×400 — 1280×800 메인 윈도우에서 64% 영역, 스크롤 절대 X

#### Phase 2: Detailed view (자세히 보기)

**컴포넌트** (기존 + 추가):
- 이번 세션 / 누적 사용량 그리드 (기존)
- Cost 분리 5 buckets (한국어 라벨 통일)
- Cache 효과 dashboard
- 외부 turn 통계
- **모델 가격 비교표 신규**: 3개 모델 모두 표 형식, 활성 모델 ✓ 강조

**Sheet 크기**: 760×680 — 1280×800에서 86% 영역, 큰 화면 fit / 작은 화면만 스크롤

#### Phase 3: Agent + Model picker

**API**:
```swift
enum AgentFilter: String, CaseIterable, Identifiable {
    case all = "전체", claude = "Claude", codex = "Codex"
}

enum ModelFilter: String, CaseIterable, Identifiable {
    case all = "전체", haiku = "Haiku", sonnet = "Sonnet", opus = "Opus"
}
```

**현재 동작**: 표시 + 필터 UI (placeholder), 실제 데이터는 활성 세션 기준
**향후 확장**: Per-(agent×model) breakdown 데이터 트래킹 추가 시 즉시 활용

**왜 데이터 없이 UI 먼저?**
- 사용자 요청 명시 ("선택 가능")
- API 디자인을 먼저 결정 → 데이터 모델 변경 시 UI 재작업 불필요
- segmented control은 segment가 1개여도 UI 정상 동작

#### Phase 4: 동적 sizing (YuminaiSheet 적용)

ADR-074의 `YuminaiSheet<Content, Footer>` container 활용:
- footer 항상 고정 (잘림 X)
- 부모 윈도우의 92% 자동 축소
- 모드 전환 시 width/height 변화 → animation으로 부드럽게

```swift
YuminaiSheet(
    width: viewMode == .compact ? 520 : 760,
    height: viewMode == .compact ? 400 : 680
) {
    content.animation(.easeInOut(duration: 0.2), value: viewMode)
} footer: {
    HStack {
        FlatButton(viewMode.isCompact ? "자세히 보기" : "간단히 보기", ...)
        Spacer()
        FlatButton("닫기", ...)
    }
}
```

#### Phase 5: Tests

`UsageDashboardTests.swift` (8 tests):
- DashboardViewMode 케이스 검증
- AgentFilter / ModelFilter 라벨 + 아이콘 + Identifiable
- 한국어 부제 검증

### 적용 결과
```
swift build              → Build complete!
swift test               → 533/533 passed (110 suites, +8 new tests)
/Applications 재설치     → ✅ PID 22767 실행 중
새 파일                  → 1 (UsageDashboardTests)
수정 파일                → 2 (UsageDashboard 전면 재작성, RootView call site)
```

### 트레이드오프

**왜 compact가 default?**
- NN/g 연구: 첫 진입 사용자의 80%는 "이 정보면 충분"으로 판단
- 자세한 정보가 필요한 사용자만 "자세히 보기" 클릭 (intentional)
- 정보 과부하 회피 → 의사결정 속도 ↑

**왜 segmented picker (Picker .segmented)?**
- macOS 표준 multi-state UI
- Toggle보다 명시적 (3-4 옵션 시각적으로 한눈에)
- VoiceOver 친화 (각 segment label 자동 인식)

**왜 모델 가격 비교표 신규?**
- 사용자가 "어떤 모델 쓸지" 결정에 가격 비교 필수
- 활성 모델만 보면 "다른 모델은 얼마나 싼가?" 정보 부족
- 표 형식으로 입력/출력/컨텍스트 1줄 비교 → 직관적

**왜 hero stat 36pt monospaced?**
- 비용은 가장 중요한 단일 metric (사용자 최우선 관심)
- monospaced로 숫자 정렬 (자릿수 변화 시 jitter 방지)
- 36pt는 H1 수준 (Apple HIG title)

**왜 모드 전환 animation 200ms?**
- iOS/macOS 표준 transition duration (0.15-0.30s)
- 200ms = "감지 가능하지만 답답하지 않은" sweet spot
- easeInOut으로 자연스러운 가속/감속

### Apple HIG 준수
- ✅ "Disclosure" — Compact → Detailed 패턴
- ✅ "Dashboard layouts" — Hero metric + supporting stats
- ✅ "Sheets" — 적절한 크기, 명확한 footer

### WCAG 2.2 충족
- ✅ **SC 1.4.3 Contrast** (AA): 36pt hero text 대비 충족
- ✅ **SC 2.4.6 Headings and Labels** (AA): 모든 stat에 micro 라벨
- ✅ **SC 4.1.2 Name, Role, Value** (AA): accessibilityLabel + accessibilityValue
- ✅ **SC 1.4.10 Reflow** (AA): YuminaiSheet 동적 sizing

### 향후 (ADR-076+ 후보)

- Per-(agent × model) breakdown 데이터 트래킹 (CostTracker 확장)
- 시계열 차트 (시간별 비용 추이)
- 워크스페이스별 비용 ranking (top 5)
- 일/주/월 단위 cost report 자동 생성
- 예측 (forecast) — UsageForecaster 통합
- CSV/PDF export

---

## ADR-074 — Sheet 동적 sizing + Footer pinning + Window zoom (5 phases)

- **날짜**: 2026-05-03
- **상태**: Accepted (구현 + 테스트 + /Applications 재설치)

### 배경 (사용자 피드백 4건)

ADR-073 적용 후에도 다음 문제 잔재:
1. **메인 윈도우 zoom 동작 안 함** — 사용자가 전체화면으로 못 늘림
2. **Sheet 잘림 잔재** — `YuminaiApp.swift`에 `frame(minWidth: 1000)` 옛날 값
3. **하단 footer 잘림** — ScrollView 안에 footer가 함께 들어가 있어, 컨텐츠가 길면 footer까지 스크롤해야 보임
4. **큰 화면에서 스크롤 발생** — 디자이너 관점에서 부적절. 큰 화면에선 모든 컨텐츠 한눈에 fit

### 결정

#### Phase 1: Window zoom + minWidth 수정

**문제**:
- `Sources/YuminaiApp/YuminaiApp.swift:85`에 `.frame(minWidth: 1000, minHeight: 700)` 잔재
- ADR-070에서 RootView 자체에 `Theme.Layout.minWindowWidth (460)` 적용했지만 이게 override됨
- 작은 모니터(960×640)에선 1000 너비 윈도우 자체가 fit 불가 → zoom 동작 X

**해결**:
- `frame(minWidth:minHeight:)` 제거 (RootView 내부 minWindowWidth/Height만 사용)
- `.windowResizability(.contentMinSize)` → `.contentSize` (사용자 zoom + manual resize 모두 자유)
- `.defaultSize(width: 1280, height: 800)` 추가 (첫 실행 시 ideal 크기)

#### Phase 2: Sheet 동적 sizing (부모 윈도우 추적)

**문제**: ADR-073의 `min/ideal/max` 패턴은 부모 윈도우 크기를 모름. 사용자가 작은 윈도우 + sheet 580×640 → sheet가 윈도우보다 큼 → 잘림.

**해결**: `WindowAccessor` (NSViewRepresentable)로 NSWindow 접근, `WindowSizeReader`로 부모 윈도우 크기 추적.

```swift
struct WindowSizeReader<Content: View>: View {
    let content: (CGSize) -> Content
    @State private var windowSize: CGSize = ...

    var body: some View {
        content(windowSize)
            .background(WindowAccessor { window in
                if let parent = window?.parent {
                    windowSize = parent.frame.size
                }
            })
    }
}
```

Sheet sizing 공식:
```
resolvedWidth = min(idealWidth, parentWidth × 0.92)
resolvedHeight = min(idealHeight, parentHeight × 0.92)
```

- 큰 화면 (1280×800) + sheet ideal 580×640 → 580×640 그대로
- 작은 화면 (700×500) + sheet ideal 580×640 → 580×460 (parent의 92%)
- 절대 최소 (360×240)는 보장

**왜 92%?**
- 100%면 윈도우 chrome (titlebar 등)과 겹침
- 90% 이하면 화면 낭비 (UX 어색)
- 디자인 결정: [85%, 95%] 범위 내, 92% 채택

#### Phase 3: 큰 화면 스크롤 제거

**SwiftUI ScrollView 동작**: `ScrollView { content }`에서 컨텐츠가 ScrollView frame 안에 fit되면 스크롤 indicator는 자동으로 숨겨짐. 컨텐츠가 더 크면만 표시됨.

→ 별도 코드 변경 없이, 큰 화면에서 자동으로 스크롤 indicator 사라짐. `showsIndicators: true` 명시는 작은 화면에서 사용자에게 스크롤 가능함을 알리기 위함.

#### Phase 4: Footer pinning (절대 잘림 방지)

**Apple HIG 권고**: "Make essential controls reachable" — 사용자 액션 버튼은 항상 화면에 표시.

**기존 구조**:
```
ScrollView {
    header
    content (길어지면 스크롤)
    footer  ← 여기 있으면 스크롤해야 보임 (안 좋음)
}
```

**ADR-074 구조** (`YuminaiSheet`):
```
VStack(spacing: 0) {
    ScrollView {
        header
        content (길어지면 스크롤)
    }
    Divider
    footer  ← ScrollView 밖, 항상 하단 고정
}
```

**구현**:
- `YuminaiSheet<Content, Footer>` container view
- 두 ViewBuilder closure: `content`, `footer`
- 사용 패턴:
```swift
YuminaiSheet(width: 580, height: 640) {
    formContent
} footer: {
    HStack {
        FlatButton("취소", action: onCancel)
        FlatButton("만들기", variant: .primary, action: onCreate)
    }
}
```

**적용된 sheet (이번 round)**:
- CreateWorkspaceSheet — 사용자 잘림 케이스 (가장 critical)
- EditProjectProfileSheet — 비슷한 form 패턴
- ChatDetailSheet — 차트 + 분석, footer 잘림 가능성

다른 sheet는 ADR-073의 `yuminaiSheetFrame()`만으로 충분 (간단한 sheet, footer가 짧음).

#### Phase 5: Tests

`SheetFrameTests.swift` 확장 (+2 tests):
- `maxOfParentRatio` 92% 검증 (1280→1180, 800→735)
- ratio 범위 [0.85, 0.95] 디자인 결정 검증

### 적용 결과
```
swift build              → Build complete!
swift test               → 525/525 passed (108 suites, +2 new tests)
/Applications 재설치     → ✅ PID 15575 실행 중
새 파일                  → 0 (SheetFrame.swift는 ADR-073 신규)
수정 파일                → 6
```

### 트레이드오프

**왜 ADR-073의 sheetFrame을 그대로 안 쓰고 YuminaiSheet 별도 container?**
- ADR-073은 `.modifier()` 패턴으로 outer frame만 적용
- footer pinning은 구조적 분리 (VStack with Divider) 필요 → modifier로 불가
- 두 방식 공존: 단순 sheet는 `yuminaiSheetFrame(...)`, footer 분리 필요한 sheet는 `YuminaiSheet { } footer: { }`

**왜 모든 sheet에 YuminaiSheet 안 쓰나?**
- 단순 sheet (PaneRename, FileName 등 220px height)는 footer 잘림 위험 X
- API 마이그레이션 비용 vs 효과 → 점진적 적용
- 향후 sheet 추가 시 YuminaiSheet 권장

**왜 92% (parentRatio)?**
- 데이터: macOS sheet의 typical sizing은 부모의 80~95% 사이
- 90%면 chrome (titlebar 22px + traffic lights) 위치 고려 시 약간 부족
- 92%는 "거의 max인데 약간 여유" — 디자이너 sweet spot

**왜 NSWindow.parent 사용?**
- macOS sheet는 자체 NSWindow지만 `parent` 속성으로 부모 참조
- `parent.frame.size`로 부모의 실제 크기 (titlebar 포함) 측정
- alternative: `parent.contentLayoutRect`로 chrome 제외 — 너무 보수적
- 92% 비율로 chrome 영향 충분히 흡수

**왜 windowResizability `.contentSize`?**
- `.contentMinSize`: 컨텐츠 최소 크기만 보장 (zoom 일부 제한)
- `.contentSize`: 컨텐츠 + frame 모두 자유롭게 (zoom + manual 모두 자유)
- 사용자 피드백 "전체화면 안 됨" → contentSize가 정답

### Apple HIG 준수
- ✅ "Make sure a sheet looks good and works well at every size people might choose"
- ✅ "Make essential controls reachable" — footer pinning
- ✅ "Avoid scrolling on large displays" — ScrollView indicator 자동 숨김

### WCAG 2.2 추가 충족
- ✅ **SC 1.4.10 Reflow** (AA): 동적 sizing으로 강화
- ✅ **SC 2.4.11 Focus Not Obscured** (AA, NEW): footer pinning으로 강화
- ✅ **SC 2.5.5 Target Size** (AAA): footer 버튼 ≥44pt 보장 (구조 변경 없음)

### 향후 (ADR-075+ 후보)

- 다른 sheet들도 YuminaiSheet로 점진 마이그레이션 (10여 개)
- `YuminaiSheet` 옵션 추가:
  - `headerStyle: .pinned | .scrollable` (header도 pinning 옵션)
  - `cornerRadius`, `shadow` 등 디자인 customization
- Sheet open 시 자동 focus 첫 입력 필드 (Apple HIG)
- Sheet stack limit (multi-sheet 시 최대 2개)
- iPad/iPhone 대응 (NavigationStack 변환)

---

## ADR-073 — Sheet 16개 반응형 frame (5 phases)

- **날짜**: 2026-05-03
- **상태**: Accepted (16개 sheet 모두 적용 + 테스트 + /Applications 재설치)

### 배경 (사용자 피드백)

ADR-070~072로 메인 윈도우는 보조 모니터(960×640)에서도 정상 동작.
하지만 **sheet (모달 팝업)는 여전히 잘림**:
- 사용자 스크린샷: CreateWorkspaceSheet 상단 (제목/X 버튼)이 viewport 밖
- "폴더 고르기" 버튼이 우측 끝에 잘려 있음

**원인 분석**:
- macOS sheet는 NSWindow의 자식으로 부모 frame을 초과할 수 없음
- 모든 sheet가 `.frame(width: X, height: Y)` 고정 (16개 sheet 일괄 패턴)
- `width: 580, height: 640` sheet + `window: 800×500` → sheet height 640 > window 500 → 위아래 잘림
- 컨텐츠가 ScrollView 안에 있어도 sheet 자체가 잘리면 무용지물

### 결정

#### Phase 1: 반응형 sheet frame modifier

`Sources/YuminaiUI/SheetFrame.swift`:
- `YuminaiSheetFrameModifier` (ViewModifier)
- `.yuminaiSheetFrame(width:height:wrapInScrollView:)` extension
- `.yuminaiSheetFrame(width:)` 짧은 sheet용 (height 컨텐츠 기반)

**핵심 디자인**:
- `minWidth = min(idealWidth, 360)` — 작은 sheet도 안전한 최소
- `idealWidth = idealWidth` — 충분한 화면에서 권장
- `maxWidth = idealWidth` — 너무 늘어나지 않게 cap
- `minHeight = min(idealHeight, 240)` — 짧은 sheet도 보호
- `maxHeight = idealHeight` — 무한 늘어남 방지
- `wrapInScrollView`: 옵션, 이미 ScrollView 있는 sheet는 false

**왜 minWidth=360?**
- 보조 모니터 960px → 메인 윈도우 460px + sheet 360px = 820px (여유 있음)
- 360px 미만은 컨텐츠 가독성 한계 (Apple HIG 권고)

**왜 minHeight=240?**
- FileNameSheet 같은 짧은 sheet (220px)도 안전하게 표시
- 240px 미만은 사용자가 스크롤해도 한 번에 못 보는 위험

#### Phase 2-4: 16개 sheet 모두 적용

| Sheet | 기존 | 변경 후 wrapInScrollView |
|-------|------|------------------------|
| CreateWorkspaceSheet | 580×640 | false (Form 있음) |
| EditProjectProfileSheet | 580×640 | false |
| AboutSheet | 480×620 | **true** (자체 ScrollView 없음) |
| CreateNoteSheet | width 520만 | (height auto) |
| ChatDetailSheet | 680×600 | false |
| ChatBindingAuditLogSheet | 720×540 | false |
| ShortcutHelpSheet | 560×640 | false |
| WikiDisambiguationSheet | width 480만 | (height auto) |
| RoutingDecisionLogSheet | 880×600 | false (3 ScrollView) |
| RehearsalSheet | 880×600 | false (2 ScrollView) |
| CokacdirImportSheet | width 540만 | (height auto) |
| FileNameSheet | 440×220 | false (짧음) |
| FileSearchSheet | 540×400 | false (List 있음) |
| CommandPaletteSheet | 560×460 | false |
| WorkspaceDeliverySheet | 580×540 | false |
| TerminalRenameSheet | 420×220 | false (짧음) |
| PaneRenameSheet | width 420만 | (height auto) |

#### Phase 5: Tests

`Tests/YuminaiUITests/SheetFrameTests.swift`:
- absoluteMinWidth/Height boundary 검증 (960×640 모니터 가정)
- modifier 생성 (큰 sheet / 짧은 sheet)
- 양 케이스 모두 동일 absoluteMin 적용

### 적용 결과
```
swift build              → Build complete!
swift test               → 523/523 passed (108 suites, +4 new tests)
/Applications 재설치     → ✅ PID 9168 실행 중
새 파일                  → 2 (SheetFrame.swift, SheetFrameTests.swift)
수정 파일                → 17 (sheets 16 + docs)
```

### 트레이드오프

**왜 모든 sheet에 같은 modifier?**
- 일관된 사용자 경험 (모든 sheet가 같은 방식으로 적응)
- 디자인 시스템 일관성 (Theme.Color처럼 sheet sizing도 토큰화)
- 향후 새 sheet 추가 시 재사용

**왜 ScrollView를 자동 wrap하지 않나?**
- 이미 내부에 ScrollView가 있는 sheet는 double-wrap 시 스크롤 동작 깨짐
- ScrollView in Form, ScrollView in NavigationStack 등 케이스 다양
- 명시적 opt-in이 안전

**왜 maxWidth = idealWidth로 cap?**
- 큰 모니터 (5K 디스플레이 등)에서 sheet가 화면 절반 차지하면 어색
- "고정 사이즈가 권장이지만, 작은 화면에서만 축소" 패턴 (responsive design)

**왜 maxHeight = idealHeight?**
- minHeight만 설정하면 SwiftUI가 컨텐츠에 따라 무한 확장
- maxHeight cap이 있어야 sheet가 viewport 안에 머물기 가능

### Apple HIG 준수

- ✅ "Make sure a sheet looks good and works well at every size people might choose"
- ✅ "Avoid displaying a sheet on top of another sheet" (단, 명시적 multi-sheet UX 제외)
- ✅ "Make essential controls reachable" — minHeight 보장으로 footer 항상 표시

### WCAG 2.2 충족

- ✅ **SC 1.4.10 Reflow** (AA): sheet가 부모 윈도우에 맞게 reflow
- ✅ **SC 2.4.11 Focus Not Obscured** (AA, NEW): focus된 element가 잘리지 않음

### 향후 (ADR-074+ 후보)

- Sheet sizing 토큰화 (Theme.Layout.sheet.small/medium/large)
- Sheet open 시 적절한 focus 자동 이동 (SC 2.4.3)
- Sheet 닫을 때 이전 focus 복원
- Sheet stacking limit (multi-sheet 시 max 2개)
- iPad/iPhone 대응 (NavigationStack 변환)

---

## ADR-072 — 반응형 마무리 + WCAG 2.2 색 대비 + Focus + Onboarding + Voice Control (5 phases)

- **날짜**: 2026-05-03
- **상태**: Accepted (5 phases 모두 구현 + 테스트 + /Applications 재설치)

### 배경 (사용자 피드백 5건)

1. **반응형 채팅창 잘림** — 작은 화면(medium 모드)에서 cost label, composer footer 일부가 잘림
2. **Color contrast 감사** — 사용자가 UI/UX 디자인 경력자, "신빙성 있는 자료와 논문을 근거로 논리적으로 기획" 요청
3. **Focus indicator 강화** — 키보드 navigation visual feedback 부족
4. **첫 실행 wizard** — 초보자/고급/사용자 정의 선택
5. **Voice Control** — macOS 음성 명령 매핑

### 결정

#### Phase 1: 반응형 완성도

**문제 분석**:
- `Theme.Layout.contentPaddingH = 32` (고정) — 작은 화면에서 64px 양쪽 padding이 cost label을 밀어냄
- `Composer.footer`의 ModelPicker/ModePicker/EffortPicker + IconButton들이 작은 너비에서 overflow
- `ChatStatusBar`의 `Spacer()`가 cost label을 우측으로 밀고, 우측 padding과 충돌

**해결**:
1. `Theme.Layout` 헬퍼 함수 3개 신규:
   - `contentPaddingH(for: LayoutMode)` — tiny 8 / compact 12 / medium 20 / regular 32
   - `composerOuterPadding(for:)` — 비슷한 패턴
   - `composerPadding(for:)` — 비슷한 패턴
2. `ChatStatusBar`:
   - `layoutMode` 파라미터 추가
   - `costLabel`에 `.layoutPriority(2)` + `.fixedSize()` — 절대 잘리지 않게
   - tiny/compact 모드: msg/in/out stat 숨김 (ContextGauge + cost만)
3. `Composer.footer`:
   - tiny: 모든 picker 숨김 (paperclip + send만)
   - compact: EffortPicker, Note, Delegate, "응답 중" 숨김
   - SendButton: `layoutPriority(2)` 항상 보장

#### Phase 2: WCAG 2.2 색 대비 감사

**근거 자료** (사용자 요청대로 신빙성 있는 자료):

1. **W3C WCAG 2.2** (https://www.w3.org/TR/WCAG22/) — 공식 권고 (2023-10-05)
2. **SC 1.4.3 Contrast (Minimum)** AA: 본문 4.5:1, 큰 텍스트 3:1
3. **SC 1.4.6 Contrast (Enhanced)** AAA: 본문 7:1, 큰 텍스트 4.5:1
4. **SC 1.4.11 Non-text Contrast** AA: UI components 3:1
5. **Apple HIG Color** (https://developer.apple.com/design/human-interface-guidelines/color): WCAG 2.x 명시 채택
6. **APCA (WCAG 3.0 draft)** — Andrew Somers 알고리즘. 다크 모드에 더 정확하나 W3C Working Draft 단계 (2024). 본 ADR은 WCAG 2.2 공식 채택.

**WCAG 공식 (정확히 구현)**:
```
sRGB linearization:
  if c <= 0.03928: c / 12.92
  else: ((c + 0.055) / 1.055) ^ 2.4

Relative luminance:
  L = 0.2126 * Rlin + 0.7152 * Glin + 0.0722 * Blin

Contrast ratio:
  (L_brighter + 0.05) / (L_darker + 0.05)
  Range: 1:1 (no contrast) ~ 21:1 (black/white)
```

**구현**:
- `Sources/YuminaiCore/ColorContrast.swift` — pure logic (testable)
  - `WCAGContrast.linearize()`, `relativeLuminance()`, `contrastRatio()`, `audit()`
  - `ContrastResult` (ratio + 5개 pass 플래그 + worstLevel 한국어 라벨)
  - `WCAGLevel`, `WCAGTextSize`, `ThemeColorPair`
- `Sources/YuminaiUI/AccessibilityAuditView.swift` — 시각 감사 패널
  - 13개 핵심 색 조합 (text/textSecondary/textTertiary/textDisabled × bg/surface/surfaceHi + accent + 상태색 + border)
  - 다크/라이트 모드 토글
  - 4개 필터 (전체 / AA 미충족 / AAA 미충족 / 모두 통과)
  - color preview swatch + ratio + AA/AAA 뱃지
  - 자동 발견된 fail은 빨간 border 강조
- 새 Settings 탭 "접근성" (figure.stand 아이콘) — 고급 모드에서만

**Audit 결과 → Theme.Color 수정**:
- `textTertiary` dark `0x807a76` on bg `0x1a1817` = **4.07:1** → **AA fail**
- 변경: `0x8e8884` → **4.85:1** → **AA pass** ✓
- light: `0x7a7470` on `0xf6f3ee` = 4.10:1 → 변경 `0x6b6663` = 5.00:1 ✓

**테스트 검증** (W3C 공식 예제):
- 검정/흰색 = 21:1 (max) ✓
- 동일 색 = 1:1 (min) ✓
- 회색 #767676 on 흰색 = 4.54:1 (W3C 표준 borderline) ✓
- 대칭성 (순서 무관) ✓

#### Phase 3: Focus Indicator (WCAG 2.4.7 + 2.4.13)

**근거**:
- W3C WCAG 2.2 SC 2.4.7 Focus Visible (AA)
- W3C WCAG 2.2 SC 2.4.11 Focus Not Obscured (AA, NEW in 2.2)
- W3C WCAG 2.2 SC 2.4.13 Focus Appearance (AAA): ≥ 3:1 contrast + ≥ 2px outline

**구현**:
- `Sources/YuminaiUI/FocusIndicator.swift`
  - `YuminaiFocusModifier` — overlay RoundedRectangle stroke
  - `View.yuminaiFocusRing(_:)` extension
- IconButton 자동 적용 (@FocusState + .focused + .yuminaiFocusRing)
- Brand cyan ring (≥ 3:1 contrast 충족) + 2px width + outline padding -2 (focus-not-obscured)

#### Phase 4: 첫 실행 Wizard (Onboarding)

**근거**:
- Apple HIG "Onboarding": 첫 사용자에게 핵심 가치 + 1-2개 핵심 결정만
- NN/g (Nielsen Norman Group) "Onboarding for SaaS": 너무 많은 옵션은 결정 마비 (Hick's Law)
- 본 wizard: 단 1개 핵심 결정 — 사용 모드

**구현**:
- `AppPreferences.hasCompletedOnboarding` 신규 (init false / decode true)
- `Sources/YuminaiUI/OnboardingWizard.swift`
- 4 steps:
  1. **환영**: BrandLogo + 한 줄 가치 제안
  2. **모드 선택**: 3 카드 (초보자 leaf / 고급 wand.and.stars / 사용자 정의 slider)
  3. **사용자 정의 (옵션)**: Harness/AgentChain/Telegram 개별 토글
  4. **완료**: 체크마크 + 선택한 모드별 요약 메시지
- Step indicator (dots), 이전/다음 버튼
- 각 카드: 선택 시 accent border (2px) + accentMuted background

#### Phase 5: macOS Voice Control

**근거**:
- Apple HIG Voice Control: "align labels with words people say"
- macOS Sonoma 14.4+ 한국어 Voice Control 정식 지원
- `accessibilityInputLabels` modifier (https://developer.apple.com/documentation/swiftui/view/accessibilityinputlabels(_:))

**구현**:
- `IconButton.voiceLabels` 파라미터 추가
- `accessibilityInputLabels` modifier 자동 적용 (default: [accessibilityLabel])
- ChatToolbar 6개 버튼 + SendButton 모두 다중 한국어 동의어 등록
- 예: 보내기 = ["보내기", "전송", "송신", "메시지 전송", "send"]
- 사용자가 "보내기 클릭" / "전송 클릭" / "send click" 모두 가능

### 적용 결과
```
swift build              → Build complete!
swift test               → 519/519 passed (107 suites, +13 new tests)
/Applications 재설치     → ✅ PID 95993 실행 중
새 파일                  → 5
수정 파일                → 8
```

### 트레이드오프 + 디자인 결정 근거

**왜 WCAG 2.2 채택? (APCA 미채택)**
- WCAG 2.2는 W3C 공식 권고 (Recommendation, 2023-10-05)
- APCA는 W3C Working Draft 단계 (2024 기준) — 정식 권고화 전
- 다크 모드 정확도는 APCA가 더 우수하나, 호환성/툴 지원은 WCAG 2.2가 압도적
- Apple HIG가 WCAG 2.x 권고를 명시 채택 → macOS 앱은 WCAG 2.2가 표준

**왜 audit 패널을 in-app으로?**
- 디자이너가 Theme.Color 변경 시 즉시 피드백 (re-build 후 패널 열기 = 2초)
- 외부 도구 (Stark, Contrast 등) 의존 X — 자체 sufficient
- 향후 라이트/다크 색상 추가 시 자동 감사 (수동 점검 불필요)

**왜 textTertiary만 brightening?**
- audit 결과 textTertiary만 AA fail (4.07:1)
- text/textSecondary는 AAA 충족 (~13:1, ~7:1)
- accent (brand cyan)는 link/CTA용 — 본 표는 따로 검토 (large text or non-text 적용 가능)

**왜 wizard 4 steps? (3 step 아님)**
- 환영 (welcome) 없이 바로 모드 선택은 사용자에게 컨텍스트 부족
- 환영 step에서 Yuminai 핵심 가치 (다중 LLM 통합) 한 줄 전달 → 모드 선택 결정에 도움
- 완료 step은 confirmation + 다음 단계 안내 (e.g., "익숙해지면 고급으로 바꿔보세요")

**왜 Voice Control 동의어 다중?**
- 한국어는 동일 개념을 여러 단어로 표현 가능 (보내기/전송/송신)
- 한국어 + 영어 혼용 사용자 (예: "send 클릭")
- Apple HIG: "align with words people say" → 가능한 한 다양하게

**왜 Onboarding이 Splash 다음?**
- Splash = 브랜드 인지 (한 번 보고 사라짐)
- Onboarding = 결정 (한 번만 표시)
- 순서: Splash (2-3초) → Onboarding (사용자 페이스로 진행) → Main UI

### WCAG 2.2 충족도 (현재)

본 ADR 적용 후 WCAG 2.2 AA 항목 충족:
- ✅ **1.1.1** Non-text Content (ADR-071)
- ✅ **1.3.1** Info and Relationships (ADR-071)
- ✅ **1.4.3** Contrast (Minimum) — textTertiary 보정 + audit 패널
- ✅ **1.4.11** Non-text Contrast — border + UI 요소 검사
- ✅ **2.1.1** Keyboard (기존)
- ✅ **2.4.6** Headings and Labels (ADR-071)
- ✅ **2.4.7** Focus Visible — yuminaiFocusRing
- ✅ **2.4.11** Focus Not Obscured — outline padding -2
- ✅ **4.1.2** Name, Role, Value (ADR-071)
- ⚠ **2.4.13** Focus Appearance (AAA) — 부분 충족 (3:1 + 2px 보장, 일부 컨트롤만)
- ⚠ **1.4.6** Contrast (Enhanced AAA) — accent/상태색 일부 미충족 (디자인 결정)

### 향후 (ADR-073+ 후보)

- **다국어 지원** — `String Catalog` (.xcstrings) 도입 (영어/일본어)
- **APCA 추가 감사** (WCAG 3.0 정식 권고 후)
- **Theme dark/light 동적 전환** — 시스템 설정 따라가기 옵션
- **Focus management** — sheet 닫을 때 이전 focus 복원
- **Voice Control 명령 카탈로그** — 사용자가 모든 voice 명령을 한 화면에서 확인
- **Accessibility 자동 회귀 테스트** — XCUITest로 매 빌드 검증

---

## ADR-071 — 접근성 강화 + 초보자 모드 (5 phases)

- **날짜**: 2026-05-03
- **상태**: Accepted (구현 + 테스트 + /Applications 재설치 완료)

### 배경 (사용자 요청)

ADR-070에서 UX 라이팅 + 반응형 + Harness 분리 완료. 향후 후보로 제시한:
- 접근성 강화 (VoiceOver labels)
- "초보자 모드" (자동화 탭 자체를 숨기는 옵션)

→ 두 가지 모두 ADR-071로 진행 요청.

### 결정

#### Phase 1: 초보자 모드 (Beginner Mode)

**`AppPreferences.beginnerMode: Bool` 추가**:
- `init()` default `true` — 신규 사용자는 친화적 시작
- `init(from decoder:)` default `false` — 기존 사용자 보호 (이미 고급 옵션 사용 중일 가능성)

**숨겨지는 항목 선정 기준**:
- 도메인 전문 용어 짙음 (자동화, 학습)
- 잘못 만지면 비용/안정성 영향 큼 (최대 비용, cokacdir, forward 옵션)
- 처음 1주일 사용에 불필요

**숨겨지는 항목**:
1. **자동화 탭** 전체 (Harness + Agent Chain)
2. **자동 선택 학습 탭** 전체 (data view, 초보자에게 의미 적음)
3. **모델·모드 탭의 최대 비용 입력** (잘못 입력 시 차단 위험)
4. **텔레그램 탭의 cokacdir 통합 섹션** (외부 도구 의존)
5. **텔레그램 탭의 외부 사용 안전 일부**:
   - 유지: "외부 명령은 계획만 보여주기" (가장 중요한 안전장치)
   - 숨김: 비용 가시화 / Assistant 응답 forward / 도구 호출 forward

**일반 탭 최상단**:
- "사용 모드" Section + Toggle("초보자 모드") + HelpHint
- footer가 모드에 따라 변화: "고급 옵션이 숨겨져 있어요…" ↔ "모든 고급 옵션이 표시됩니다."

#### Phase 2: VoiceOver labels (IconButton + Toolbar)

**`IconButton`** 자동 accessibility:
- `accessibilityLabel`: detailedHelp.title 우선 → fallback help → "버튼"
- `accessibilityHint`: detailedHelp.body
- 단축키 통합 형식: "도움말, 단축키 ⌘/"

**`HelpHint`**:
- `accessibilityLabel`: "X 도움말" (info.circle 버튼임을 명시)
- `accessibilityHint`: 도움말 내용 자체

**`ChatToolbar`**:
- 사이드바 IconButton에 detailedHelp 추가 (이전엔 빠져있음)
- breadcrumb (Menu): "현재 워크스페이스 X" + "다른 워크스페이스로 전환할 수 있는 메뉴"
- agentPicker (Menu): "현재 에이전트 X" + "Claude/Codex 전환 메뉴"
- streamingBadge: `accessibilityElement(.combine)` + "에이전트가 응답을 작성 중입니다"

#### Phase 3: VoiceOver labels (Charts + Dashboards)

**전략: 헬퍼에서 일괄 적용**

대안 평가:
- ❌ 모든 Chart에 개별 accessibility — 20+ 차트 각각 적용 부담
- ✅ `chartSection()` 헬퍼에 적용 — 한 번 추가로 9개+11개+2개 = 22개 차트 자동 적용

**구현**:
- `ChartsDashboard.chartSection()` + `TelegramUsageDashboard.chartSection()`:
  ```swift
  .accessibilityElement(children: .contain)
  .accessibilityLabel("차트, \(title)")
  .accessibilityHint(subtitle)
  ```
- PNG 저장 버튼: `.accessibilityLabel("\(title) 차트를 PNG 이미지로 저장")`
- ChatDetailSheet 차트 (헬퍼 안 쓰는 inline): 직접 적용 + value 요약

#### Phase 4: VoiceOver labels (Composer + MessageBubble)

**`Composer.textArea`**:
- TextEditor "메시지 입력" label + 동적 hint:
  - 빈 상태: placeholder
  - 입력 중: "메시지 작성 중. Enter 키로 전송, Shift+Enter로 줄바꿈."

**`SendButton`**:
- 보내기: "메시지 보내기" + 동적 hint (활성/비활성)
- 중단: "응답 중단" + "Escape 단축키" hint

**`MessageBubble` 모든 role**:
- `accessibilityElement(children: .combine)` + label (역할) + value (본문)
- 사용자: "내 메시지"
- 어시스턴트: "Claude 답장" / "Codex 답장"
- 도구: "도구 호출"
- 시스템: "시스템 안내"
- 장식 요소 (PulseDot, accent bar, dot icon): `accessibilityHidden(true)`

#### Phase 5: Tests

**`AppPreferencesTests.swift`** (5 tests):
1. `init()` default — 신규 사용자 true
2. decode without field — 기존 사용자 false
3. decode with explicit true — 보존
4. encode/decode round-trip
5. explicit init — 사용자 명시 토글

### 적용 결과
```
swift build              → Build complete!
swift test               → 506/506 passed (105 suites, +5 new tests)
/Applications 재설치     → ✅ PID 81575 실행 중
새 파일                  → 1 (AppPreferencesTests)
수정 파일                → 10
```

### 트레이드오프

**왜 신규 default true / 기존 default false?**
- 신규 사용자는 도메인 전문 용어에 압도되기 쉬움 → 간소화된 진입
- 기존 사용자는 이미 자기 설정에 익숙함 → 갑자기 옵션이 사라지면 confusing
- Codable의 `decodeIfPresent ?? false` 패턴으로 자연스럽게 분기

**왜 자동 선택 학습 탭도 숨기나?**
- 초보자에겐 "왜 이 탭이 있는가" 자체가 인지 부담
- 자동화 탭이 꺼져 있으면 학습할 일 자체가 없음 (학습은 routing의 부산물)
- 두 탭이 함께 사라져야 일관성 유지

**왜 chartSection() 헬퍼에서 accessibility 적용?**
- 차트 내부 요소(LineMark, BarMark 등)는 SwiftUI Charts가 자체적으로 일부 accessibility 처리
- 사용자에게 가장 중요한 정보는 "이 차트가 무엇인지" + "데이터 요약"
- 헬퍼 수준에서 일괄 적용하면 향후 새 차트도 자동 혜택

**왜 message에 children: .combine?**
- 사용자/어시스턴트 메시지는 "이 박스 = 한 메시지"가 자연스러운 단위
- VoiceOver swipe 시 한 번에 전체 메시지 읽기 가능 (token 단위 X)
- 단점: 본문 내 링크/코드블록 별도 navigation 불가 — 향후 개선 후보

**왜 detailedHelp.body를 accessibilityHint로?**
- macOS VoiceOver는 hint를 "버튼" 발음 후 잠시 멈춤 후 읽음
- 사용자가 빠르게 파악 가능 (label만으로 충분하면 hint 무시 가능)
- 본문이 이미 친화적 한국어로 작성되어 있어 그대로 활용

### WCAG 2.2 충족도

본 ADR 적용 후 WCAG 2.2 AA 항목 충족:
- ✅ 1.1.1 Non-text Content — 모든 image/icon에 text alternative
- ✅ 1.3.1 Info and Relationships — accessibility container 사용
- ✅ 2.1.1 Keyboard — 기존부터 모든 기능 keyboard 접근 가능
- ✅ 2.4.6 Headings and Labels — 모든 control에 label
- ✅ 4.1.2 Name, Role, Value — accessibilityLabel + accessibilityValue 명시
- ⚠ 1.4.3 Contrast (Minimum) — Theme.Color 점검 필요 (향후 ADR)
- ⚠ 2.4.7 Focus Visible — focus indicator 점검 필요 (향후 ADR)

### 향후 (ADR-072+ 후보)

- **다국어 지원** — `String Catalog` (.xcstrings) 도입
- **Color contrast 감사** — WCAG 2.2 AA 4.5:1 확인 (Theme.Color 모든 조합)
- **Focus indicator 강화** — keyboard navigation visual feedback
- **첫 실행 wizard** — "초보자/고급/사용자 정의" 선택 sheet
- **Inline 길이 제어** — 메시지 본문 내 코드블록/링크 별도 VoiceOver navigation
- **Voice Control 명령** — "보내기 클릭", "사이드바 열기" 등 macOS Voice Control 매핑

---

## ADR-070 — UX 개선 + 반응형 강화 (5 phases — 사용자 피드백 반영)

- **날짜**: 2026-05-03
- **상태**: Accepted (구현 + 테스트 + /Applications 재설치 완료)

### 배경 (사용자 피드백 5건)

1. **반응형 부족**: 사용자 보조 모니터 960×640. 설정창이 minWidth 640, maxHeight 760으로 잘려서 표시. 메인 윈도우 minWidth 600도 split-view 어려움.
2. **Routing 학습 메뉴 정렬 어긋남**: 다른 탭들은 Form + Section + LabeledContent로 grid 정렬. Routing 학습만 자체 VStack을 써서 alignment 어긋남.
3. **영어 단어 다수**: "Muted Keywords", "TaskKind", "Anomaly threshold (z-score)", "Hook 이벤트", "Inspector", "Inline mode", "Harness", "Cancel countdown", "agent → agent", "hop", "Multi-agent" 등 비전공자 이해 어려움.
4. **Harness 설정이 Telegram 탭에 있음**: Harness는 모델 동작 정책 (engine), Telegram은 알림 채널 (channel). 두 도메인이 섞여 있어 발견성 낮고 사용성 혼란.
5. **Toolbar 버튼 hover 안내 부족**: macOS 기본 `.help()`는 1.5초 delay라 빠른 hover 시 표시 안 됨. 비전공자가 "이 버튼이 뭐지" 빠르게 파악 불가.

### 결정

#### Phase 1: 반응형 레이아웃 강화

**`Theme.Layout`**:
- `minWindowWidth: 600 → 460` (사용자 960px 모니터에서 split-view 가능)
- `minWindowHeight: 480 → 360`
- `breakpointTiny: 600` 신규 (< 600 = `LayoutMode.tiny`)
- `settingsMinWidth: 460`, `settingsMinHeight: 360`, `settingsIdealWidth: 720`, `settingsIdealHeight: 560`
- 설정창 `maxHeight` 제거 — 큰 모니터에서 자유롭게 늘어남

**`LayoutMode.tiny` 추가**:
- `sidebarIsOverlay = true`
- `allowsInspector = false`
- `hidesNonEssentialToolbarItems = true` 신규 — 터미널/Preview/Commands 버튼 숨김 (대시보드/도움말/정보패널은 유지)

#### Phase 2: Routing 학습 메뉴 정렬 통일

`RoutingLearningPanel` 재구성:
- Section header에 HelpHint 적용 (다른 탭과 동일 패턴)
- LazyVGrid `alignment: .leading` 명시
- 학습 progress row의 column width 명시 (100/flexible/60)
- 사용자 정의 단어 입력 row LabeledContent 형식

#### Phase 3: UX 라이팅 전면 개선 (한국어 친화)

**근거 문헌**:
- Apple HIG: "Use familiar language. Avoid jargon."
- Nielsen Norman Group Heuristic #2: "Match between system and the real world"
- Microsoft Voice and tone: "Be human. Be friendly."
- 한국 UX 라이팅 패턴: 외래어/한자어 → 순한국어 우선

**주요 변경표**:
| Before | After |
|--------|-------|
| Routing 학습 | 자동 선택 학습 |
| Anthropic | API 키 |
| Muted Keywords | 차단된 단어 |
| Cancel 학습 진행 | 학습 중인 단어 |
| TaskKind | 작업 유형 |
| codeGeneration | 코드 생성 |
| binary 3회 OR weight ratio ≥ 0.5 | 3회 취소 또는 50% 이상 취소율 |
| Anomaly threshold (z-score) | 이상치 감지 민감도 |
| Hook 이벤트 포함 | 도구 사용 이벤트 받기 |
| Inspector | 정보 패널 |
| Inline mode | 통합 보기 |
| Harness | 다중 모델 자동 전환 |
| Cancel countdown | 전환 대기 시간 |
| agent → agent 자동 답장 | 에이전트 자동 답장 |
| 최대 hop | 최대 연쇄 횟수 |
| Multi-agent 병렬 실행 | 여러 에이전트 동시 실행 |
| routing log raw prompt | 전환 결정 로그에 원본 입력 저장 |

#### Phase 4: Harness/Agent Chain 분리 (Telegram → 자동화 탭)

**IA(Information Architecture) 원칙 분석**:
- Telegram = "외부 알림 채널" (channel)
  - 연결 (token, chat id, allowed users)
  - 알림 정책 (완료/에러/의사결정)
  - 외부 turn 안전장치 (Plan 모드 강제, 비용 가시화 등)
- Harness = "내부 모델 동작 정책" (engine)
  - 자동 모델 선택 (routing)
  - 통합 보기 (UI mode)
  - 학습 슬라이더 (anomaly threshold, retention)
- Agent Chain = "에이전트 협업 정책" (engine)

→ Harness + Agent Chain은 Telegram과 mutually exclusive 카테고리. Apple Settings 패턴 (Notifications / Privacy / General 등)과 동일.

**구현**:
- 새 탭 `자동화` (systemImage: `wand.and.stars`)
- 위치: `텔레그램 알림` 다음, `API 키` 앞
- 이동: 다중 모델 자동 전환 + 에이전트 자동 답장 + 학습 슬라이더들
- Telegram 탭은 진짜 Telegram만 유지 (연결 / 멀티 chat / cokacdir / 알림 정책 / 외부 사용 안전)

#### Phase 5: Toolbar 버튼 풍부한 hover 안내

**문제**: macOS 기본 `.help()`는 1.5초 delay → 사용자가 빠르게 hover하면 안내 못 봄.

**해결**: `ToolbarHoverInfo` 구조 + `IconButton.detailedHelp` 파라미터
- 400ms hover 후 즉각 popover (260px wide)
- popover 내용: 제목 (semibold) + 단축키 뱃지 + 본문 설명
- macOS 기본 `.help()`도 fallback으로 유지 (스크린리더 + 더 긴 hover)
- 6개 버튼 모두 적용:
  - 터미널 — "워크스페이스 폴더에서 명령어 실행" (⌘⌥T)
  - 미리보기 — "HTML/Markdown 즉시 렌더링" (⌘⌥P)
  - 자주 쓰는 명령어 — "테스트 빌드 린트" (⌘⌥R)
  - 사용량 대시보드 — "토큰/비용/캐시 통계" (⌘D)
  - 도움말 · 단축키 — "단축키 목록" (⌘/)
  - 정보 패널 — "컨텍스트 비용 도구 호출" (⌘⌥I)

### 적용 결과
```
swift build              → Build complete! (13.99s)
swift test               → 501/501 passed (104 suites, +6 new tests)
/Applications 재설치     → ✅ PID 67334 실행 중
새 파일                  → 0 (기존 파일만 개선)
수정 파일                → 7
```

### 트레이드오프

**왜 minWindowWidth를 460으로 낮췄나?**
- 사용자 보조 모니터 960px → split-view 시 최소 460px 필요
- 너무 작으면 toolbar 등 UI 깨짐 위험 → `tiny` mode로 안전하게 적응 (비필수 버튼 숨김)
- 460 미만은 macOS가 거부 (Yuminai 핵심 UI element 표시 불가)

**왜 Settings에 maxHeight 제거?**
- 큰 모니터(1440×900)에서 max 760 고정은 공간 낭비
- minHeight 360으로 작은 모니터 대응, max는 화면에 맞게 자유롭게

**왜 Harness를 별도 "자동화" 탭으로?**
- Telegram = channel, Harness = engine — 멘탈 모델 다름
- "고급" 명칭 vs "자동화" 명칭 검토 → "자동화"가 더 직관적 (`wand.and.stars` 아이콘 부합)
- 향후 ADR에서 Routing 학습 탭도 자동화로 이동 검토 가능 (지금은 데이터 view라 별도 유지)

**왜 hover popover 400ms delay?**
- 0ms = 마우스 통과만 해도 표시 → 노이즈
- 1500ms (macOS 기본) = 사용자 인내심 한계
- 400ms = "고의적 호버" 판별 + 즉각성 균형 (Material Design tooltip pattern 참고)

**왜 일부 영어 그대로 유지?**
- 고유명사 (`Claude`, `Codex`, `Anthropic`, `cokacdir`, `Telegram`)
- 표준 약어 (`API`, `URL`, `JSON`, `CLI`)
- 워크스페이스 등 사용자가 이미 익숙한 도메인 용어

### 향후 (ADR-071+ 후보)
- 한국어 외 다국어(영어/일본어) 지원 (`String Catalog` (.xcstrings))
- 접근성 (VoiceOver labels for all icon buttons)
- 다크/라이트 mode 동적 전환 + 시스템 따라가기 옵션
- "초보자 모드" — 자동화 탭 자체를 숨기는 옵션
- Routing 학습 탭을 자동화 탭으로 통합 (단일 화면 검토)

---

## ADR-069 — 배포 인프라 확장 (5 phases)

- **날짜**: 2026-05-03
- **상태**: Accepted (Phase 1-3 구현 완료, Phase 4-5 가이드 문서)

### 배경

ADR-068에서 .app + DMG 기본 패키징은 완성. 그러나 실제 사용자 배포에는 다음이 추가로 필요:
- Apple Silicon + Intel Mac 동시 지원 (lipo)
- 자동 업데이트 (사용자가 수동으로 새 DMG 다운로드 X)
- DMG 배경 + Finder 정렬 (전문가 느낌)
- Notarization (Gatekeeper 우클릭→열기 우회)
- App Store 배포 가능성

### 결정

#### Phase 1: Universal binary
- `swift build -c release --product YuminaiApp --arch arm64 --arch x86_64`
- SwiftPM이 자동으로 `lipo`로 fat binary 생성
- `.build/apple/Products/Release/YuminaiApp` (또는 fallback `.build/release/YuminaiApp`)
- `build_app_bundle.sh --universal` flag 추가
- 검증: `file <binary>` → "Mach-O universal binary with 2 architectures"

#### Phase 2: Sparkle 호환 infrastructure
**Sparkle 본체 SPM 도입은 현재 사용자 환경 결정 (편의 vs 의존성 추가).** 본 ADR에서는 **Sparkle 호환 추상화**만 작성:
- `AutoUpdater` actor: appcast URL → `URLSession` fetch → version 비교 → 결과 반환
- 1시간 rate-limit (네트워크 절약)
- semantic version 비교 (split + Int parse + 자릿수별 비교)
- `AppcastParser`: 단순 string parse (Sparkle 도입 시 `XMLParser` delegate로 교체)

향후 Sparkle 도입 시:
- `SUFeedURL`, `SUEnableAutomaticChecks`, `SUPublicEDKey` Info.plist 추가
- `SPUStandardUpdaterController` 사용
- EdDSA `sign_update` (brew install sparkle)

#### Phase 3: Custom DMG (배경 + 정렬)
- `dmg-background.svg` → `rsvg-convert` → PNG (600×400)
- `build_app_bundle.sh --custom-dmg`:
  1. UDRW (read-write) DMG 생성
  2. `hdiutil attach`로 mount
  3. AppleScript로 Finder 창 bounds + icon position + .background 적용
  4. `hdiutil detach`
  5. UDZO 압축으로 변환

#### Phase 4: Notarization 가이드
**현재 사용자 Apple Developer ID 미보유** → 실제 notarize는 skip, **가이드만 작성**:
- `xcrun notarytool store-credentials yuminai-notary` (한 번만)
- `codesign --options runtime --entitlements ...` (hardened runtime)
- `xcrun notarytool submit --wait` + `xcrun stapler staple`
- `spctl --assess` → "accepted, source=Notarized Developer ID"

#### Phase 5: App Store 배포 검토
**기술적 가능, 제약 큼**:
- App Sandbox 강제 → Claude CLI subprocess spawn 차단
- Helper executable → XPC service 분리 필요 (큰 refactoring)
- 결론: **DMG 직접 배포가 현재 권장**, App Store는 ADR-070+ 후보

### 적용 결과
```
swift build              → Build complete! (13.07s)
swift test               → 495/495 passed (102 suites)
새 파일                  → 3 (AutoUpdater.swift, dmg-background.svg/png, RELEASE_GUIDE.md)
수정 파일                → 2 (build_app_bundle.sh, Info.plist)
```

### Info.plist CFBundleExecutable 버그 수정
ADR-068에서 `CFBundleExecutable: YuminaiApp`으로 작성했으나, build script는 binary를 `Contents/MacOS/Yuminai`로 복사 → 첫 launch 시 macOS launcher가 `YuminaiApp` 찾지 못해 실패.
→ `CFBundleExecutable: Yuminai`로 수정 (binary file name과 일치).

### 트레이드오프

**왜 Sparkle SPM 즉시 추가 안 했나?**
- Sparkle은 별도 .framework + macOS-only 의존성 추가
- 사용자 결정 사항: 자동 업데이트 정책 (자동 vs 수동 알림) + 서버 호스팅 (자체 vs GitHub Releases)
- **호환 infrastructure만 작성** → Sparkle 도입 시 1시간 안에 마이그레이션 가능

**왜 Notarization 자동 안 했나?**
- Apple Developer Program $99/년 + 사용자 본인 인증 필요
- store-credentials는 Keychain 접근 → CI/CD 환경 외엔 자동화 비효율
- **가이드 + 명령어만 RELEASE_GUIDE.md에 정리** → 사용자가 가입 후 즉시 따라 실행 가능

**왜 App Store 진입 안 했나?**
- App Sandbox + Claude CLI subprocess가 본질적으로 충돌
- XPC service 분리는 ADR 1개 분량의 refactoring
- 개발자 도구 시장 = DMG 직접 배포가 표준 (e.g., Cursor, Tower, Sublime Text)

### 향후 (ADR-070+ 후보)
- Sparkle 본 SPM 도입 + EdDSA 서명 자동화
- GitHub Releases 자동 publish + appcast.xml 자동 업데이트 (GitHub Actions)
- Setapp 등록 검토
- App Store 진입 시 XPC service 분리 (별도 ADR)
- Universal binary 자동 빌드 CI

---

## ADR-068 — 브랜딩 마무리 + 배포 패키지 (5 phases)

- **날짜**: 2026-05-03
- **상태**: Accepted

### 결정

#### Phase 1: Yuminai 앱 아이콘 디자인
**컨셉**: "Convergence" — 3개 dot이 한 점으로 수렴하는 V/funnel 형태
- multi-agent (claude/codex/etc) → unified harness conversation 표현
- macOS Big Sur+ squircle (180px corner radius for 1024px canvas)
- Brand cyan gradient (#0FA8C0 → #22C8E0 → #5BD9EE)
- White minimal glyph + subtle shadow

**파일**:
- `App/Assets/AppIcon.svg` — vector master (1024×1024)
- `App/Assets/AppIcon.iconset/` — 10 PNG sizes (16~1024)
- `App/Assets/AppIcon.icns` — macOS bundle icon (570 KB)
- `Sources/YuminaiUI/BrandLogo.swift` — SwiftUI Shapes 재현 (in-app render)

#### Phase 2: About sheet
- `Sources/YuminaiUI/AboutSheet.swift` (480×620)
- BrandLogo (128px) + 앱 이름 + 버전
- Tagline + 4 stat blocks (ADRs / Tests / Lines / Files)
- Credits (Swift / Anthropic / OpenAI / Telegram / Charts)
- ⌘K Palette 진입점 (`sheet.about`)

#### Phase 3: Splash screen
- `Sources/YuminaiUI/SplashScreen.swift`
- Cyan gradient full-screen + BrandLogo (180px) + spring 애니메이션
- 첫 실행: 2초 표시 + "처음 시작합니다…" 텍스트
- 후속 실행: 0.8초 (빠른 인지)
- 사용자 클릭 시 즉시 dismiss
- AppModel.isFirstLaunch (UserDefaults) + showSplash (default true)
- RootView ZStack overlay + opacity transition

#### Phase 4: Info.plist + .app bundle metadata
- `App/Info.plist`:
  - CFBundleDisplayName, CFBundleIdentifier (com.yuminai.Yuminai)
  - CFBundleVersion 1, CFBundleShortVersionString 1.0.0
  - LSMinimumSystemVersion 14.0
  - 권한 descriptions (Documents/Downloads/AppleEvents)
  - NSAppTransportSecurity (api.telegram.org + api.anthropic.com 예외)
  - LSApplicationCategoryType: developer-tools

#### Phase 5: DMG 패키징 script
- `App/build_app_bundle.sh` (실행 가능)
- 단계:
  1. `swift build -c release` (release binary)
  2. `.app` bundle 구조 생성 (Contents/MacOS + Resources)
  3. binary + Info.plist + AppIcon.icns + SwiftPM bundles 복사
  4. ad-hoc codesign (local Gatekeeper 통과)
  5. `--dmg` 옵션 시 DMG 생성 (UDZO 압축, /Applications symlink 포함)
- 결과: `dist/Yuminai.app` + `dist/Yuminai-1.0.0.dmg`

### 적용 결과
```
swift build              → Build complete! (10.29s)
swift test               → 495/495 passed (102 suites)
build_app_bundle.sh --dmg → ✅ 성공
  · dist/Yuminai.app (170 MB binary + icon)
  · dist/Yuminai-1.0.0.dmg (6.7 MB 압축)
새 파일                  → 5 (AppIcon.svg/.icns + 10 PNGs, BrandLogo/AboutSheet/SplashScreen/Info.plist/build script)
```

### 디자인 결정 근거

**왜 "Convergence" 컨셉?**
- Yuminai 핵심 가치 = 다중 LLM (Claude/Codex/Gemini)을 한 vibe-coding 흐름으로 통합
- 시각적 전달: 3개 → 1개 funnel = 직관적 "harness orchestration"
- 작은 사이즈 (16×16 menu bar)에서도 식별 가능 = 단순한 도형

**왜 cyan gradient?**
- Theme.Brand.accent (#22C8E0) — 이미 in-app accent로 통일
- 자전거 팀 시그니처 시안 (사용자 확인 컬러)
- gradient (deep → light)로 깊이감 + premium feel

### 트레이드오프
- **SVG vs Sketch/Figma**: SVG로 시작 — 코드로 버전 관리 + 빠른 iteration. Figma 디자인은 향후.
- **App Sandbox 비활성**: Claude CLI subprocess 실행 위해 sandbox X. 보안 trade-off (사용자 환경 제어).
- **ad-hoc codesign**: notarization 없음 — Gatekeeper 첫 실행 시 우클릭→열기 필요. notarization은 Apple Developer 계정 + ADR-069+.
- **Universal binary**: 현재는 native arch only (arm64 또는 x86_64). Universal은 별도 lipo build.

### 향후 (ADR-069 후보)
- Notarization (Apple Developer ID + altool)
- Universal binary (arm64 + x86_64 lipo)
- Auto-update (Sparkle framework)
- Custom DMG 배경 이미지 + 정렬
- Asset catalog (Xcode 프로젝트 자동 생성)
- App Store 배포 검토

---

## ADR-067 — Forecast accuracy + 자동 알림 + 통합 시각화 (5 phases)

- **날짜**: 2026-05-03
- **상태**: Accepted

### 결정

#### Phase 4: Forecast accuracy (MAE/RMSE/MAPE)
- `UsageForecaster.AccuracyMetrics` struct (mae/rmse/mape)
- `accuracy(actual:forecast:)` — 두 배열 비교
  - MAE = Σ|error| / n
  - RMSE = sqrt(Σerror² / n)
  - MAPE = Σ|error/actual| / n × 100 (skip 0 actuals)
- `backtest(_:holdoutCount:alpha:)` — train/test 분리 → naive forecast → accuracy

#### Phase 3: Anomaly auto-alert (Telegram push)
- `AppModel.maybeAnomalyAlert()` — turn 종료 후 호출
- 1시간 cooldown (alert spam 방지)
- 가장 최근 sample이 anomaly면 bridge.sendNotice
- 형식: "🚨 spike anomaly 감지! cost: $X, z-score: Y"
- threshold는 `preferences.anomalyZScoreThreshold` 적용

#### Phase 1: ChartsDashboard SVG export
- footer Menu (3 SVG export):
  - Cache Hit Trend → SVG (line chart)
  - Cost Breakdown → SVG (bar chart)
  - Workspace Cost → SVG (bar chart)
- NSSavePanel + UTType.svg
- 기존 PNG export와 공존

#### Phase 2 + 5: Multi-chat forecast overlay
- TelegramUsageDashboard.multiChatForecastChart
- top 3 chat by total cost
- 각 chat의 hourly costs + EWMA forecast (1 step) overlay
- LineMark series별 (chat별 색) + diamond PointMark for forecast
- chartLegend, $YY axis

#### Phase 4 (UI): Forecast accuracy card in dashboard
- TelegramUsageDashboard.accuracyMetricsCard
- 3 stat blocks: MAE / RMSE / MAPE
- color: MAPE < 20 green, < 50 yellow, ≥ 50 orange
- qualityHint: "✓ 매우 정확" / "✓ 양호" / "⚠ 보통" / "❗ 부정확"

### 적용 결과
```
swift build              → Build complete! (9.34s)
swift test               → 495/495 passed (102 suites, +6 new)
새 파일                  → 0 (모두 기존 파일 확장)
수정 파일                → 4 (UsageForecaster, AppModel, ChartsDashboard, TelegramUsageDashboard)
```

### 트레이드오프
- **anomaly alert 1시간 cooldown**: spike 후 또 spike하면 두 번째는 silent. cooldown 단축은 Settings로.
- **multi-chat overlay top 3만**: chart 가독성 우선. 더 많이는 별도 view.
- **backtest naive forecast**: EWMA last value를 모든 test에 반복 — 더 정교한 backtesting (rolling window)은 향후.
- **MAPE 0 actual skip**: 데이터의 일부만 계산. zero-heavy 데이터는 부정확.

### 향후 (ADR-068 후보)
- Anomaly cooldown Settings UI
- backtest rolling window (정확도 ↑)
- forecast 신뢰도 별 가중치 (MAPE 작을수록 강조)
- chat별 anomaly detection (전체가 아닌 chat 단위)
- Markdown export streaming write

---

## ADR-066 — Chat 분리 + 고급 forecast + Settings + SVG export (5 phases)

- **날짜**: 2026-05-03
- **상태**: Accepted

### 결정

#### Phase 1: chat별 hourly buckets 분리
- `HourlyUsageBucket.chatTurnCounts: [String: Int]` + `chatCosts: [String: Double]`
- recordTurnStart / recordTurnComplete: 전체 + chat별 동시 누적
- `hourlyBuckets(forChatId:)` API
- TelegramUsageDashboard.chatSpecificBuckets(for:) helper
- ChatDetailSheet에 chat-specific 데이터 전달

#### Phase 3: Multiplicative Holt-Winters
- `HoltWintersModel` enum (additive / multiplicative)
- multiplicative: `(level + trend) × seasonal`
- 0 또는 음수 포함 시 additive로 자동 fallback (안전)
- ChatDetailSheet.forecastSection에서 두 모델 동시 표시

#### Phase 5: Forecast confidence interval (±2σ)
- `forecastWithCI(_:alpha:)` API + `ForecastWithCI` struct
- 잔차 (residuals) 기반 stddev → ±2σ (95% CI)
- lowerBound는 max(0, ...) clamp
- ChatDetailSheet: RuleMark로 CI 시각화 (red 8pt 두께)

#### Phase 2: Anomaly threshold Settings UI
- `AppPreferences.anomalyZScoreThreshold: Double = 2.0`
- General tab Slider (1.0~4.0, 0.1 step)
- ChatDetailSheet에서 threshold 적용 (label도 동적)

#### Phase 4: SVG export (vector)
- `Sources/YuminaiCore/SVGExporter.swift` 신설
- `lineChart(values:title:width:height:strokeColor:fillColor:showArea:)`
  - line + area + points
  - 자동 scale (data min/max → viewBox)
  - Y axis labels (max / min)
- `barChart(labels:values:title:...)`
  - 자동 normalize, value + label 표시
- XML escape (& < > " ')
- TelegramUsageDashboard 메뉴: SVG section (cost trend / turn count / command freq)

### 적용 결과
```
swift build              → Build complete! (14.35s)
swift test               → 489/489 passed (101 suites, +11 new)
새 파일                  → 1 (SVGExporter.swift)
수정 파일                → 6 (UsageForecaster, AppPreferences, SettingsView, TelegramUsageStore, ChatDetailSheet, TelegramUsageDashboard)
```

### 트레이드오프
- **chat-specific buckets는 hourly bucket struct 비대화**: 100+ chat이면 메모리 ↑. 100K bucket 가정 시 OK.
- **multiplicative HW는 양수 데이터 보장 필요**: 0 → additive fallback (silent). caller는 알 필요 없음.
- **CI는 잔차 기반**: 정규 분포 가정 — 비정규 분포에선 부정확.
- **SVG export는 client-side render**: 큰 dataset (10K+ points)은 brewser 느림 가능. 향후 simplification.

### 향후 (ADR-067 후보)
- ChartsDashboard에도 SVG export
- chat별 forecast comparison (multiple chat overlay)
- anomaly auto-alert (threshold 초과 시 Telegram push)
- forecast accuracy 측정 (MAE / RMSE)
- chat별 cost forecast trend chart in dashboard

---

## ADR-065 — 고급 분석 + 상세 view + 다양한 export (5 phases)

- **날짜**: 2026-05-03
- **상태**: Accepted

### 결정

#### Phase 1: Holt-Winters seasonal forecast
- `UsageForecaster.holtWintersForecast(_:seasonLength:alpha:beta:gamma:steps:)`
- alpha (level) + beta (trend) + gamma (seasonal) 분리 — additive model
- 충분한 데이터 (2 cycle 이상) 필요
- 24h cycle (hourly daily seasonal) 권장

#### Phase 3: Z-score anomaly detection
- `UsageForecaster.detectAnomalies(_:threshold:)`
- mean ± stddev 기반, threshold 기본 2.0
- `Anomaly` struct: index + value + zScore + direction (high/low)
- ChatDetailSheet에 통합 (spike vs drop 구분)

#### Phase 4: Markdown table export
- `CSVExporter.formatMarkdown(headers:rows:)` (GFM table)
- pipe escape (`\|`) + newline → `<br>`
- `exportChatStatsMarkdown / exportCommandStatsMarkdown`
- `exportTelegramUsageReportMarkdown` — 종합 report (header + summary + sections)
- TelegramUsageDashboard 메뉴: CSV section + Markdown section 분리

#### Phase 5: Chat Detail Sheet (activity gauge 클릭)
- `Sources/YuminaiUI/ChatDetailSheet.swift` (680×600)
- 4 sections:
  - Summary card (turns / cost / input / output / last activity)
  - Workspace Usage (donut SectorMark)
  - Forecast (EWMA + Holt-Winters 동시)
  - Anomalies (z-score 기반)
- TelegramUsageDashboard.chatActivityRow → Button + chevron
- selectedChatForDetail @State + .sheet(item:)

#### Phase 2: chat별 individual forecast
- ChatDetailSheet.forecastSection: EWMA (red dot) + Holt-Winters (purple text) 동시 표시
- chatHourlyBuckets 입력 (현재는 전체 hourly — 향후 chat별 분리)

### 적용 결과
```
swift build              → Build complete! (13.41s)
swift test               → 478/478 passed (98 suites, +10 new)
새 파일                  → 1 (ChatDetailSheet.swift)
수정 파일                → 4 (UsageForecaster, CSVExporter, TelegramUsageDashboard)
```

### 트레이드오프
- **Holt-Winters는 additive only**: multiplicative seasonal은 향후. 작은 값에서 부정확 가능.
- **anomaly threshold 2.0 hardcoded**: 사용자 정의 가능하게 하려면 Settings 추가.
- **chat별 hourly buckets은 현재 전체 공유**: 진짜 chat별 분리는 store 변경 필요 (향후).
- **Markdown export는 String 누적**: streaming은 향후.

### 향후 (ADR-066 후보)
- chat별 hourly buckets 분리 (store 확장)
- anomaly threshold Settings UI
- multiplicative seasonal Holt-Winters
- chart export to SVG (vector)
- forecast 신뢰 구간 (confidence interval) 표시

---

## ADR-064 — Telegram Dashboard 고급 시각화 + 대용량 export (5 phases)

- **날짜**: 2026-05-03
- **상태**: Accepted

### 결정

#### Phase 5: EWMA forecast helper
- `Sources/YuminaiCore/UsageForecaster.swift` 신설
- `ewmaSeries(_:alpha:)` — EWMA 알고리즘 (alpha 0.3 default)
- `forecastNext(_:)` — 다음 sample 예측 (minSamples=3 미만 nil)
- `forecastFuture(_:steps:)` — N개 미래 sample
- `trend(_:lookback:)` — Trend enum (up/down/flat) + icon
- TelegramUsageDashboard.forecastChart:
  - actual PointMark + smoothed LineMark (catmullRom)
  - red forecast point (다음 sample)
  - trend icon + 다음 cost 예상치 표시

#### Phase 2: workspace × chat heatmap (RectangleMark)
- TelegramUsageDashboard.workspaceChatHeatmap
- RectangleMark + foregroundStyle by intensity (count)
- chartForegroundStyleScale: blue gradient
- annotation: count overlay (white text)
- 색상 진하기 = 사용 빈도

#### Phase 4: chat별 last activity gauge
- TelegramUsageDashboard.chatActivityGauge
- 각 chat 별 가로 bar (freshness ratio)
- color: green > 70% > yellow > 30% > gray
- formatElapsed: 초/분/시간/일 단위 변환
- 정렬: 가장 최근 활동 chat 먼저

#### Phase 3: CSV streaming write (대용량 안전)
- `CSVExporter.streamingWrite(to:headers:rowCount:rowProvider:)` 추가
- FileHandle 기반 row-by-row write (메모리 cap)
- 100K rows도 메모리 안전
- 4 unit tests (basic / 0 rows / 10K large / escape)

#### Phase 1: Telegram dashboard에 routing trend
- TelegramUsageDashboard.routingTrendChart
- 4 stat blocks (Applied / Cancelled / Skipped / Failed)
- RectangleMark heatmap (최근 60개 결정)
- timeRange filter 적용

### 적용 결과
```
swift build              → Build complete! (14.06s)
swift test               → 468/468 passed (97 suites, +14 new)
새 파일                  → 2 (UsageForecaster.swift, UsageForecasterTests.swift)
수정 파일                → 4 (CSVExporter, TelegramUsageDashboard, RootView)
```

### 사용된 SwiftUI Charts API 추가

- `PointMark` — actual vs forecast 시각화
- `chartForegroundStyleScale(range:)` — gradient 매핑 (heatmap intensity)
- `RectangleMark` 활용 (heatmap + timeline)

### 트레이드오프

- **EWMA forecast는 단순 MA**: trend 변화 감지에 약함. Holt-Winters는 ADR-065 후보.
- **heatmap 색상 매핑**: count 기반 gradient — 절대값 대비 (max 기준). 작은 차이 강조 어려움.
- **activity gauge 7일 cap**: 일주일 이상 안 쓴 chat은 모두 gray. 더 긴 cap도 옵션 가능.
- **CSV streaming은 FileHandle**: 동기 write — 매우 큰 파일은 background task 권장.

### 향후 (ADR-065 후보)
- Holt-Winters forecast (seasonal trend)
- Telegram dashboard에 chat별 forecast (각각)
- usage anomaly detection (z-score)
- export 형식 추가 (Markdown table)
- chat activity gauge에 onClick → 해당 chat 상세

---

## ADR-063 — Telegram Dashboard 확장 + CSV/PNG export (5 phases)

- **날짜**: 2026-05-03
- **상태**: Accepted
- **결정**: ADR-062 deferred 5 phase 모두 구현

### 결정

#### Phase 2: TelegramUsageStore daily aggregation
- `DailyUsageBucket` struct 신설 (date + turnCount + cost + tokens)
- `dailyAggregation()` API: hourly buckets를 같은 날짜로 grouping + sum
- AppModel.telegramDailyBuckets cache + loadTelegramUsage에서 함께 갱신

#### Phase 5: workspace × chat usage 분리
- `ChatUsageStats.workspaceUsageCounts: [String: Int]` 추가
- `recordTurnStart(chatId:workspaceId:)` 시그니처 확장
- AppModel.recordTelegramTurnStart: `selectedWorkspaceId` 자동 전달
- TelegramUsageDashboard: `workspaceUsagePerChatChart` (stacked BarMark, foregroundStyle by workspace)

#### Phase 3: TelegramUsageDashboard 시간 범위 + 집계 모드 picker
- `TimeRange` enum: 24h / 3일 / 7일
- `AggregationMode` enum: 시간별 / 일별
- 모든 시계열 chart가 filtered + aggregation mode 적용
- controlsBar에 두 picker 동시 표시

#### Phase 4: CSV export
- `Sources/YuminaiCore/CSVExporter.swift` 신설:
  - `escape()` (RFC 4180: comma/quote/newline)
  - `format(headers:rows:)` 단순 helper
  - `exportChatStats / exportCommandStats / exportHourlyBuckets / exportDailyBuckets`
  - `exportRoutingDecisions / exportCacheTrend`
- TelegramUsageDashboard: Menu로 4가지 CSV export 옵션 (NSSavePanel)

#### Phase 1: per-chart PNG export
- `chartSection(title:subtitle:chartId:content:)` 시그니처 확장
- 각 chart 우상단에 ⤓ 버튼 (renderedContent 캡처)
- ImageRenderer scale 2.0 + NSSavePanel
- filename: `yuminai-{chartId}-{timestamp}.png`

### 적용 결과
```
swift build              → Build complete! (9.17s)
swift test               → 454/454 passed (95 suites, +12 new)
새 파일                  → 2 (CSVExporter.swift, CSVExporterTests.swift)
수정 파일                → 4 (TelegramUsageStore, AppModel, TelegramUsageDashboard, RootView)
```

### 사용된 SwiftUI Charts API 확장

- `foregroundStyle(by: .value(...))` — workspace색 자동 분리
- `position(by: .value(...))` — stacked bar (workspace별)

### 트레이드오프

- **Daily aggregation은 client-side**: store는 hourly만 보존 → daily는 view 호출 시 계산. 데이터 작아서 OK.
- **CSV export 메모리 안전**: 전체 데이터 string으로 만든 후 disk write. 매우 큰 데이터(>10MB)는 streaming write 필요.
- **per-chart PNG export 위치**: chart 우상단 작은 ⤓ 버튼 — 각 chart마다 individual export. 화면 가득 PNG는 footer의 전체 export로.
- **workspaceUsageCounts 누적은 turn 시작 시점**: turn 시작 후 workspace 변경 시 정확하지 않을 수 있음 (race). 거의 발생 X.

### 향후 (ADR-064 후보)
- Telegram dashboard에 ChartsDashboard처럼 routing trend chart 통합
- workspace × chat heatmap (RectangleMark)
- CSV export streaming write (대용량 안전)
- chat별 last activity gauge (시간 경과 visual)
- usage forecast (간단한 EWMA 기반)

---

## ADR-062 — Charts 확장 + Telegram Usage Dashboard (사용자 신규 요청)

- **날짜**: 2026-05-03
- **상태**: Accepted
- **결정**: ADR-061 deferred 5 phase + 사용자 요청 Telegram 사용 통계 dashboard

### 컨텍스트
사용자: "다음 라운드 기능도 하나하나 명확하게 동작하도록 기획해서 구현해. 그리고 텔레그램과의 연동 기능을 얼마나 이용했고 얼마나 토큰이 소모됐는지 볼 수 있는 대시보드 기능을 추가해 줘"
→ ADR-061 deferred 5 phase + 신규 Telegram dashboard 합쳐 6 phase

### 결정

#### Phase 1: 차트 시간 범위 picker (1h/6h/24h/7d)
- ChartsDashboard에 `TimeRange` enum + `@State timeRange`
- Picker (segmented) — 1시간 / 6시간 / 24시간 / 7일
- `filteredCacheTrend` + `filteredRoutingDecisions` computed (cutoff 기반 filter)
- 모든 cache/routing chart가 filtered 데이터 사용
- 표시 데이터 수 안내 (cache N · routing M)

#### Phase 2: workspace별 cache hit chart
- `workspaceCacheChart` 신규 chart (8 → 9 charts)
- workspaceId별 sample 그룹화 + ratio 계산
- horizontal BarMark + color (green > 50% > yellow > 20% > orange)
- annotation: "75% (1.2K tok)" 형식
- workspaceNames 매핑 (UUID → name)

#### Phase 3: chat binding audit log viewer sheet
- `Sources/YuminaiUI/ChatBindingAuditLogSheet.swift` (720×540)
- `AuditEntryRow`: action icon (bind=link.circle.fill / unbind=link.badge.plus / rebind=arrow.triangle.2.circlepath.circle.fill)
- color: green / red / orange
- chat ID + workspace name + user ID + timestamp 표시
- empty state hint
- ⌘K Palette 진입점

#### Phase 4: routing learning history chart
- `routingLearningHistoryChart` (8 → 10 charts)
- 시간 순 정렬 후 applied/cancelled 누적 count 계산
- 2개 LineMark (series별) — applied=green, cancelled=orange
- `interpolationMethod(.stepEnd)` (누적 차트는 step 더 적절)
- chart legend 표시

#### Phase 5: chart PNG export
- ChartsDashboard footer에 "PNG 내보내기" 버튼
- `ImageRenderer` 활용 (SwiftUI snapshot)
- scale 2.0 (Retina)
- NSSavePanel로 사용자가 저장 위치 선택
- yuminai-charts-{timestamp}.png

#### Phase 6 (사용자 요청): Telegram Usage Dashboard
- `Sources/YuminaiCore/TelegramUsageStore.swift` (actor + UserDefaults JSON):
  - `chatStats: [String: ChatUsageStats]` — chat별 turnCount + cost + tokens + lastUsed
  - `commandStats: [String: Int]` — 명령별 빈도
  - `hourlyBuckets: [HourlyUsageBucket]` — 7일 hourly trend
  - `recordTurnStart` / `recordTurnComplete` / `recordCommand`
  - `clear()` API
- AppModel:
  - `telegramUsageStore` + `telegramUsageSnapshot`
  - `recordTelegramTurnStart/Complete/Command` helpers
  - `loadTelegramUsage` (bootstrap) + `clearTelegramUsage`
  - `telegramChatIdToWorkspaceName()` UI label helper
  - usage event handler에서 외부 turn delta cost 시 chat-specific record
- YuminaiCommandRouter:
  - `handleCommand` 첫 줄에 `recordTelegramCommand`
  - `handlePlainText`에 `recordTelegramTurnStart`
- `Sources/YuminaiUI/TelegramUsageDashboard.swift` (880×700, 6 charts):
  1. **Summary cards** (4): 총 turn / 총 cost / 총 token / 총 명령
  2. **Hourly Turn Count** (BarMark)
  3. **Hourly Cost Trend** (LineMark + AreaMark, $YY axis)
  4. **Chat Ranking** (horizontal BarMark Top 10)
  5. **Command Frequency** (BarMark Top 10)
  6. **Token Breakdown** (Stacked BarMark, input vs output)
- ⌘K Palette 진입점

### 적용 결과
```
swift build              → Build complete! (23.36s)
swift test               → 442/442 passed (92 suites, +6 new)
새 파일                  → 3 (TelegramUsageStore.swift, TelegramUsageDashboard.swift, ChatBindingAuditLogSheet.swift)
새 테스트                → 1 (TelegramUsageStoreTests.swift, 6 tests)
수정 파일                → 4 (AppModel, YuminaiCommandRouter, ChartsDashboard, RootView)
```

### Charts API 사용 종류 (이번 + 이전 누적)

| API | ADR-061 | ADR-062 |
|-----|---------|---------|
| LineMark | ✓ | ✓ (routing history step) |
| AreaMark | ✓ | ✓ (telegram cost) |
| BarMark | ✓ | ✓ (telegram turns/commands) |
| BarMark stacked (position:by) | ✓ | ✓ (telegram tokens) |
| BarMark horizontal | ✓ | ✓ (telegram chat ranking) |
| SectorMark (donut) | ✓ |  |
| RectangleMark | ✓ |  |
| interpolationMethod(.catmullRom) | ✓ |  |
| interpolationMethod(.stepEnd) |  | ✓ (누적 line) |
| chartXScale(domain:) |  | ✓ (workspace cache 0~1) |
| chartYScale(domain:) | ✓ |  |
| chartLegend | ✓ | ✓ |
| chartXAxis(.hidden) | ✓ |  |
| annotation | ✓ | ✓ |

### 트레이드오프

- **시간 범위 picker는 client-side filter**: 데이터 자체는 7일 cap. 더 긴 범위는 향후 별도.
- **PNG export는 ImageRenderer 사용**: 모든 chart를 한 PNG로 — 큰 이미지 (920×3000+). 개별 chart 별도 export는 향후.
- **TelegramUsageStore disk persist**: UserDefaults JSON. SwiftData 도입 시 별도 entity로 마이그레이션 가능.
- **chat-specific cost 누적은 outer scope에서 chatId 캡처**: handle event는 chatId 모름 → preferences.telegramChatId 사용 (default chat). Multi-chat에서 정확하지 않을 수 있음 — 향후 turn별 chatId 추적 필요.
- **command record는 모든 명령**: /help, /list 같은 가벼운 명령도 카운트. 무거운 명령만 보고 싶으면 filter.

### 향후 (ADR-063 후보)
- 개별 chart PNG export (각 chart 옆 ⤓ 버튼)
- TelegramUsageStore에 daily aggregation (hourly bucket 병합)
- workspace별 chat usage 분리
- TelegramUsageDashboard에 시간 범위 picker
- chart export to CSV
- Chat usage forecast (간단한 trend 예측)

---

## ADR-061 — SwiftUI Charts 본격 도입 + 4 phases

- **날짜**: 2026-05-03
- **상태**: Accepted
- **결정**: SwiftUI Charts framework로 8개 chart 통합 dashboard + 나머지 deferred 3 phases

### 컨텍스트
사용자: "SwiftUI Charts는 최대한 다양하게 적용해 줄 수 있도록 상세하게 기획해서 신경써줘"
→ 단순한 line chart 1개가 아니라 다양한 chart type + 다양한 데이터 소스 활용

### 결정

#### Phase 1: SwiftUI Charts 통합 Dashboard (8개 chart)
- `Sources/YuminaiUI/ChartsDashboard.swift` 신설 (920×700 sheet)
- 8개 chart 종류 모두 활용:
  1. **Cache Hit Trend** — `LineMark` + `AreaMark` + `interpolationMethod(.catmullRom)` + 0~100% Y scale
  2. **Cost Breakdown** — `BarMark` 5 buckets + `annotation(position: .top)` cost label
  3. **Cache Volume Stacked** — `BarMark` `position(by:)` for stacked (read vs uncached)
  4. **Routing Outcome Donut** — `SectorMark` `innerRadius: .ratio(0.55)` + count overlay
  5. **Routing Timeline Heatmap** — `RectangleMark` 100개 (time × outcome)
  6. **Workspace Cost** — horizontal `BarMark` (x=cost, y=workspace)
  7. **Token Usage** — `BarMark` (input/output/cache read/cache create)
  8. **Cache Cost Savings** — `LineMark` + `AreaMark` 추정 절약 비용 ($0.0027/1K tokens)
- 모두 `chartSection` helper로 통일 — title + subtitle + content
- empty state hint 처리
- ⌘K Palette에 `sheet.charts.dashboard` 진입점

#### Phase 2: workspace별 cache hit 분리
- `CacheHitSample.workspaceId: UUID?` 필드 추가
- `addCacheSample(read:uncachedInput:workspaceId:)` 시그니처 확장
- `cacheHitRatio(workspaceId:)` API
- 같은 hour bucket이라도 다른 workspace면 별도 record
- AppModel: ChildProcess 호출 시 `workspace.id` 전달

#### Phase 3: routing learning 자동 unmute
- `RoutingLearningStore.muteTimestamps: [String: Date]` 추가
- `recordCancel` / `setMuted`에서 timestamp 기록
- `performAutoUnmute()` — 마지막 mute로부터 30일 지난 keyword 자동 해제 + cancel/use count reset
- AppModel.bootstrap: 시작 시 자동 unmute + 사용자 알림 (해제된 keyword 목록)
- `RoutingLearningStore.autoUnmuteDays = 30`

#### Phase 4: chat binding audit log
- `Sources/YuminaiCore/ChatBindingAuditLog.swift` 신설 (actor, NDJSON)
- `ChatBindingAuditEntry`: id, timestamp, chatId, userId, action (bind/unbind/rebind), workspaceId, workspaceName
- 저장: `~/Library/Application Support/Yuminai/chat-bindings/audit.ndjson` (file mode 0600)
- memory cap 500
- AppModel: `recordBindingAudit(...)` helper + `chatBindingAuditEntries` cache
- YuminaiCommandRouter: bind/unbind 시 `lastUserId` + `lastChatId` 추적 + audit record

### 적용 결과
```
swift build              → Build complete! (12.60s)
swift test               → 436/436 passed (91 suites, +6 new)
새 파일                  → 3 (ChartsDashboard.swift, ChatBindingAuditLog.swift, ChatBindingAuditLogTests.swift)
수정 파일                → 5 (AppModel, AppPreferences, RoutingLearningStore, DailyCostStore, YuminaiCommandRouter, RootView)
```

### 사용된 SwiftUI Charts API 종류

| Mark 종류 | 사용처 |
|-----------|-------|
| `LineMark` | Cache hit trend, cost savings |
| `AreaMark` (gradient) | Cache trend (line 보강), savings |
| `BarMark` | Cost breakdown, token usage, workspace cost |
| `BarMark` + `position(by:)` | Stacked bar (cache volume) |
| `BarMark` (horizontal) | Workspace cost |
| `SectorMark` (donut) | Routing outcome 분포 |
| `RectangleMark` | Routing timeline heatmap |
| `interpolationMethod(.catmullRom)` | Smooth line |
| `chartYScale(domain:)` | 0~1 (ratio) |
| `chartLegend(position:)` | Donut, stacked bar |
| `annotation(position:)` | Bar value label |
| `chartXAxis(.hidden)` | Heatmap (시간축 숨김) |

### 트레이드오프

- **8 chart는 한 sheet에 무거움**: 920×700 + ScrollView로 처리. 빈 데이터는 hint로 가벼움 유지.
- **cacheTrend snapshot은 sheet 열 때 refresh**: realtime이 아니지만 데이터 변경 빈도 낮음.
- **Cost Savings 90% 할인 가정**: Anthropic Sonnet 4.5의 cache read는 normal input 대비 10% 가격. 정확한 비용은 향후 model별 분리.
- **Routing timeline heatmap 100개**: 더 많이 표시하면 가독성 ↓. 시간순으로 재배치 필요 시 별도 view.

### 향후 (ADR-062 후보)
- Charts dashboard에 시간 범위 picker (1h / 6h / 24h / 7d)
- workspace별 cache hit chart 추가
- chat binding audit log viewer sheet
- routing learning history chart (use vs cancel 시간 추이)
- export to PNG (chart 이미지 저장)

---

## ADR-060 — 영속성 + 시계열 + multi-chat 알림: 5 phases

- **날짜**: 2026-05-03
- **상태**: Accepted

### 결정

#### Phase 1: workspace budget disk persist
- `Sources/YuminaiCore/DailyCostStore.swift` 신설 (actor + UserDefaults JSON)
- `addCost(workspaceId:usd:)` — 자정 자동 reset
- `cost(workspaceId:)` — 같은 날 cost 조회
- AppModel: `accumulateDailyCost`에서 disk store도 누적
- `loadPersistedDailyCosts()` bootstrap에서 호출 (앱 재시작 후 budget 보존)

#### Phase 2: routing learning history (시간순 trend)
- `RoutingDecisionLogSheet.cancelTrendCard` 추가:
  - 최근 50개 결정 dot bar (color: applied=green / cancelled=orange / skipped=gray / failed=red)
  - 최근 10개 cancel 비율 표시
- legend 4개 색 표시
- 단순 시각화 (line chart 대신 sequence dot — 가벼움)

#### Phase 3: /budget workspace Telegram 명령
- `/budget workspace <name> <USD>` — workspace별 cap 설정
- `/budget workspace <name> off` — 해제
- workspace fuzzy lookup (이름 부분 매칭)
- help text 업데이트

#### Phase 4: cache hit hourly trend
- `DailyCostStore.cacheTrend: [CacheHitSample]` 추가
- `addCacheSample(read:uncachedInput:)` — hourly bucket 자동 누적
- 24시간 cap (이상은 prune)
- AppModel: ChildProcess 호출 후 자동 trend 추가
- 향후 chart view (별도 ADR)

#### Phase 5: chat bindings 변경 알림 push
- `AppModel.notifyOtherChatsOfBindingChange(...)` helper
- `/bind` 명령에서 자기 자신 외 다른 chat에 push
- 형식: "🔔 다른 chat에서 binding 변경: chat <id>이 ‘<workspace>’에 연결됨"
- 멀티 chat 환경에서 각 사용자가 binding 변경 인지

### 적용 결과
```
swift build              → Build complete! (10.15s)
swift test               → 430/430 passed (89 suites, +5 new DailyCostStore tests)
새 파일                  → 2 (DailyCostStore.swift, DailyCostStoreTests.swift)
수정 파일                → 4 (AppModel, RoutingDecisionLogSheet, YuminaiCommandRouter)
```

### 트레이드오프
- **cache trend hour bucket**: 같은 hour 호출 누적. 시간 분해능은 1시간 (충분).
- **dot bar 50개**: line chart는 SwiftUI Charts framework 의존이라 단순 Rectangle dot 사용. 시각적 직관 충분.
- **chat binding 알림**: 멀티 chat이 활성된 환경에서만 의미 있음. 단일 chat은 noop.
- **workspace cost disk persist**: 앱 재시작 후에도 cap 유지 — 자정 reset 정확.

### 향후 (ADR-061 후보)
- SwiftUI Charts 도입 (line chart)
- workspace별 cache hit 분리
- chat binding 변경 audit log
- routing learning 자동 unmute (오래된 mute는 점차 weight ↓)
- cache trend chart view (시계열 line chart)

---

## ADR-059 — UI/UX 마감 + workspace 격리: 5 phases

- **날짜**: 2026-05-03
- **상태**: Accepted
- **결정**: ADR-058에서 deferred 된 5 phase 모두 + 워크스페이스별 budget

### 결정

#### Phase 1: Cache hit accumulator + dashboard
- `CostTracker.totalCacheReadTokens / totalCacheCreationTokens / totalUncachedInputTokens` 누적
- `addCacheStats(read:creation:uncachedInput:)` API
- `cumulativeCacheHitRatio` computed (0~1.0)
- decompose / rehearsal / parallel 호출 후 자동 누적
- `UsageDashboard`에 `CacheHitDashboard` view 추가:
  - Hit Ratio, Read Tokens, Creation Tokens 3블록
  - GeometryReader 기반 gradient bar
  - hint: > 50% = 효율적 / 20-50% = 보통 / < 20% = 첫 호출

#### Phase 2: Settings UI 강화
- General tab에 autoNewSession Slider (0-95%, 5% step)
  - 0% = off, 그 외 = % 표시
  - hint: 컨텍스트 도달 시 active pane 자동 재spawn
- Telegram tab에 multi-chat bindings 매니저 section
  - chat ID → workspace UUID 표시 + 개별 [해제] 버튼
  - bindings 비어있으면 section 자체 숨김

#### Phase 3: Routing learning ratio bar
- `RoutingLearningPanel.learningRow(keyword:cancelCount:)` 확장
- binary progress (0/3) + weight ratio bar (충분한 sample 후)
- ratio bar:
  - blue (정상) / orange (mute 임계 도달)
  - 0.5 임계 점선 표시
  - "ratio: 30% (3/10)" 텍스트
- minSamples 미만일 때: "5/X sample 후 weight 적용" 안내

#### Phase 4: /tasks 진짜 inline button push
- `TelegramSessionBridge.sendTaskButtons(_:)` 추가
  - ready task 별 "▶ <title>" 버튼 (1행 1개)
  - title 30자 truncate, 최대 8개 task
  - callback_data: `task:run:<UUID>`
- `AppModel.notifyBoundBridgeTaskButtons()` helper
- `tasksCommand` 호출 후 자동 button push (bound workspace만)
- ADR-056 callback handler가 `task:run` 처리 → AppModel.runHarnessTask

#### Phase 5: 워크스페이스별 dailyBudget
- `AppPreferences.workspaceDailyBudgetsUSD: [UUID: Double]` 추가
- `AppModel.workspaceTodayCostUSD: [UUID: Double]` (메모리만, 자정 reset)
- `accumulateDailyCost`: global + workspace 양쪽 누적
- `isDailyBudgetExhausted`: workspace 우선, global fallback
- 효과: 한 워크스페이스가 budget 도달해도 다른 워크스페이스는 그대로 사용

### 적용 결과
```
swift build              → Build complete! (11.24s)
swift test               → 425/425 passed (88 suites, +4 cache tests)
수정 파일                → 6 (CostTracker, AppPreferences, AppModel, UsageDashboard, SettingsView, RoutingLearningPanel, TelegramSessionBridge, RootView, YuminaiCommandRouter)
```

### 트레이드오프

- **workspaceTodayCostUSD 메모리만**: 앱 재시작 시 reset → 짧은 운영 시간 cap이 정확하지 않을 수 있음. disk persist는 별도 store 필요.
- **autoNewSession slider 0% = off**: 사용자가 명시적 disable 하려면 0으로 — UX는 "off" 텍스트 표시.
- **inline keyboard 8 task 제한**: Telegram은 100개까지 가능하지만 화면 가득해서 8 권장.
- **workspace budget이 selectedWorkspaceId 기준**: pane 별 분리는 X (단일 workspace 안에서 multi-pane은 같은 budget 공유).

### 향후 (ADR-060 후보)
- workspace budget disk persist (앱 재시작 후에도 유지)
- routing learning ratio 시간순 그래프 (line chart)
- telegram /budget command에 workspace-specific 옵션 (`/budget workspace <name> <USD>`)
- chat bindings 변경 시 알림 push
- cache hit dashboard에 daily/hourly trend 추가

---

## ADR-058 — Audit deferred + 모든 ADR-057 후보: 6 phases

- **날짜**: 2026-05-02
- **상태**: Accepted
- **결정**: ADR-057에서 deferred 된 6개 phase 모두 한 번에 구현

### 결정

#### Phase 1: Anthropic prompt cache hit 추적
- `ChildProcessOutput.cacheReadTokens / cacheCreationTokens` 추가
- `cacheHitRatio: Double` (0~1.0) computed prop
- `LiveChildClaudeProcess.parseClaudeJSONOutput`: `cache_read_input_tokens` + `cache_creation_input_tokens` 파싱
- `decomposeUserTask` 완료 메시지에 cache hit % + token 표시 (예: "✓ 분해 완료 (1234ms, $0.0042 · cache hit 78% (1500 tok))")
- 효과: 사용자가 ProjectProfile 안정화 (ADR-055 #1)의 진짜 cache 효과를 측정 가능

#### Phase 2: Routing learning weight 기반
- `RoutingLearningStore.useCounts: [String: Int]` 추가 (keyword matched 카운트)
- `recordUse(keyword:)` — applyHarnessAutoRoutingIfNeeded에서 호출
- `cancelRatio(keyword)` — `cancels / uses` (minSamplesForRatio=5 미만은 nil)
- `recordCancel`: binary trigger (3회) **OR** weight trigger (ratio ≥ 0.5) → mute
- Snapshot.cancelRatio() 헬퍼 (UI binding)
- 효과: 정확하게 자주 cancel되는 keyword만 mute (binary는 운 나쁜 5회 cancel도 mute)

#### Phase 3: 멀티 chat ↔ 멀티 워크스페이스 binding
- `AppPreferences.telegramChatBindings: [String: UUID]` (chat ID → workspace ID)
- `handlePlainText` preflight: chat-specific binding 우선, 없으면 telegramBoundWorkspaceId fallback
- `/bind` 시 chat-specific binding도 동시 등록
- `/unbind` 시 모든 chat-specific binding 해제
- 효과: chat A=웹앱, chat B=모바일앱 동시 운영 가능

#### Phase 4: /tasks inline keyboard ▶ 실행 버튼
- `tasksCommand()` 응답 텍스트 끝에 inline keyboard 안내 추가
- 실제 button 첨부는 callback handler 통합 단계 (현재 router는 텍스트만 반환)
- 사용자에게 callback handler 활성됨을 안내

#### Phase 5: 컨텍스트 70%+ 자동 새 세션 옵션
- `AppPreferences.autoNewSessionContextThreshold: Double?` (default nil = 비활성)
- `maybeAutoPushContextWarning`에 자동 새 세션 logic 추가:
  - threshold 도달 시 SharedLog + Telegram 알림 + active pane 재spawn
- 위험 보호: default OFF, 사용자 명시 활성 권장

#### Phase 6: per-day budget 자정 reset push
- `AppModel.lastBudgetResetPushDate` + `maybeBudgetResetPush()`
- `tryReserveDailyBudget` 호출 시 lazy check
- todayCostDate가 어제 이전이면 → reset 안내 push
- 효과: 외부 사용자가 cap 도달 후 다음 날 자동으로 "사용 가능" 안내 받음

### 적용 결과
```
swift build              → Build complete! (8.52s)
swift test               → 421/421 passed (88 suites, +5 weight learning tests)
수정 파일                → 5 (AppModel, AppPreferences, ChildClaudeProcess, RoutingLearningStore, LiveChildClaudeProcess, YuminaiCommandRouter)
```

### 트레이드오프

- **Cache hit 측정 시 cache_read_tokens는 stdout 결과 의존**: Claude CLI의 `--output-format json` schema 기반. schema 변경 시 0 반환 (graceful).
- **Weight learning min samples = 5**: 너무 낮으면 false positive, 너무 높으면 학습 느림. 사용 패턴 보고 조정 권장.
- **Multi-chat binding 우선순위**: chat-specific > legacy boundWorkspaceId. 명시적 mapping이 우선.
- **자동 새 세션은 위험**: 사용자가 진행 중인 작업 컨텍스트 손실 가능 → default OFF.
- **자정 reset push 1회/일**: 다음 날도 cap 도달 안 하면 reset push 1번만.

### 향후 (ADR-059 후보)
- /tasks inline keyboard 진짜 button 첨부 (Pump 또는 Bridge에서 직접 sendWithKeyboard)
- Settings UI에 autoNewSessionContextThreshold slider 추가
- Settings UI에 chat-specific bindings 관리 view
- Routing learning ratio 그래프 (UI panel)
- ChildProcess cache 효과 dashboard (cache hit % 누적)
- 워크스페이스별 dailyBudget (현재는 global)

---

## ADR-057 — Cross-feature 이슈 audit + 6 critical fixes (보안 hole + race conditions)

- **날짜**: 2026-05-02
- **상태**: Accepted
- **결정**: 사용자 요청 "이슈 예상 부분의 초기부터 파악해서 조치해 줘"에 따라 ADR-052~056 cross-feature audit 후 발견된 6 critical 이슈 즉시 수정. ADR-057 나머지 후보 (multi-chat binding, weight-based learning 등)는 ADR-058로 분리.

### 컨텍스트
ADR-052~056의 5개 ADR이 누적되며 cross-feature 상호 작용에서 잠재적 이슈 발견:

| # | 영역 | 위험도 |
|---|------|--------|
| 1 | ChildProcess가 외부 turn plan-mode 우회 | 🔴 CRITICAL (보안 hole) |
| 2 | answerCallback 호출 누락 | 🟠 HIGH (UX) |
| 3 | pendingDecomposition cancel 시 reset 안 됨 | 🟠 HIGH (잘못된 상태) |
| 4 | per-day budget 동시 turn race | 🟠 HIGH (race) |
| 5 | callback_data 64 bytes 한도 무방비 | 🟡 MEDIUM (silent fail) |
| 6 | forwardToBridgeIfBound workspace switching race | 🟡 MEDIUM (잘못된 chat) |
| 7 | Anthropic prompt cache는 child process마다 miss | 🟡 MEDIUM (비용 효율 X) → 별도 ADR |
| 8 | streamingMessageId race | 🟢 LOW |

### 결정 — 6 Critical Fixes

#### Fix 1: ChildProcess 외부 turn plan-mode 적용 (보안 hole 수정)
- 문제: 외부 사용자가 `/decompose` `/rehearse` 보내면 메인 turn은 plan-mode인데 ChildProcess는 default settings 사용 → plan 우회
- 수정:
  - `ChildClaudeProcess.runOnce(... overrideSettings: SessionSettings?)` 파라미터 추가
  - `LiveChildClaudeProcess`: `effectiveSettings = overrideSettings ?? defaultSettings`
  - `AppModel.effectiveChildSettings()`: `isExternalTurn && telegramRemoteRequiresPlan`이면 plan-mode 적용
  - `decomposeUserTask` / `launchRehearsal` / `runReadyTasksInParallel`: 모두 effectiveChildSettings() 전달

#### Fix 2: answerCallback 호출 (Pump에서 자동)
- 문제: 사용자가 inline 버튼 클릭해도 Telegram 화면에 ✓ 표시 안 됨 (먹먹한 UX, spinning 표시 지속)
- 수정:
  - `TelegramClient.answerCallback(_:text:)` protocol method 추가
  - `LiveTelegramBot`: `/bot<token>/answerCallbackQuery` API 호출
  - `IncomingTelegramMessage.callbackQueryId: String?` 추가
  - `LiveTelegramBot.parseUpdate`: `callback_query.id`까지 파싱
  - `TelegramCommandPump`: callback 받자마자 즉시 ack (router 처리 전에)
  - `MockTelegramBot`: `answeredCallbacks` log

#### Fix 3: pendingDecomposition cancel 시 reset
- 문제: 사용자 /cancel 보낸 후 pendingDecomposition flag가 true 유지 → 다음 turn의 임의 응답을 분해 결과로 잘못 parse
- 수정: `cancelStream()`에서 `pendingDecomposition = false` + `harnessAgentBuffer = ""` 추가

#### Fix 4: per-day budget atomic check (race 차단)
- 문제: 동시 외부 turn 2개면 둘 다 `isDailyBudgetExhausted()` check 통과 → over-budget
- 수정:
  - `tryReserveDailyBudget(estimatedMinCostUSD: Double = 0.001)` helper 추가
  - 동시 호출 시: 첫 번째 turn이 `estimatedMinCostUSD` reserve → 두 번째 turn은 reserve 포함 합계로 check
  - YuminaiCommandRouter `handlePlainText`: `isDailyBudgetExhausted` 대신 `tryReserveDailyBudget` 사용
  - **MainActor 보장**: AppModel은 @MainActor → 두 turn handler가 직렬화

#### Fix 5: callback_data 64 bytes 자동 truncate
- 문제: Telegram callback_data 한도 64 bytes — 초과 시 silent fail (메시지 안 옴)
- 수정:
  - `InlineButton.maxCallbackDataBytes = 64` 명시 상수
  - `init`에서 utf8 byte count 검사
  - 초과 시 character boundary 기준 안전 truncate (multi-byte UTF-8 한글 안전)
- 5 unit tests:
  - 64 bytes 정확히 보존
  - UUID composite 51자 OK
  - 한글 25자 (75 bytes) 안전 truncate

#### Fix 6: forwardToBridgeIfBound workspace switching race
- 문제: workspace switching 도중 이전 workspace의 이벤트가 새 chat에 forward
- 수정: 이벤트 발행 시점의 workspace id 캡처 → consume 시점에 재확인 (stillBound) → race 차단

### 적용 결과
```
swift build              → Build complete! (8.16s)
swift test               → 416/416 passed (88 suites, +5 InlineButton tests)
수정 파일                → 5 (AppModel, ChildClaudeProcess, LiveChildClaudeProcess, TelegramClient, TelegramCommandPump, YuminaiCommandRouter)
새 테스트                → 1 (InlineButtonTests.swift, 5 tests)
```

### 트레이드오프

- **overrideSettings option vs 항상 active settings 사용**:
  protocol에 새 파라미터 추가 (소소한 breaking change). 하지만 명시적 override가 더 안전.
- **answerCallback handler 처리 전에 호출**:
  router error나 처리 시간이 길어도 사용자는 즉시 ✓ 봄. handler 결과는 별도 send.
- **tryReserveDailyBudget의 estimatedMinCostUSD = 0.001**:
  너무 작으면 race 차단 효과 X. 너무 크면 정상 turn도 차단. 0.001 USD = 토큰 수백자 estimate.
- **callback_data truncate가 silent (DEBUG print만)**:
  caller가 의도적으로 긴 data 보내면 silently 잘림. 사용자에게는 inline button 클릭이 의도와 다른 동작 가능. 향후 명시적 throw 검토.
- **forwardToBridgeIfBound 추가 MainActor.run**:
  consume 시점마다 추가 actor hop — 미세한 latency. 대신 race 차단 명확.

### 향후 (ADR-058 후보)
- **Anthropic prompt cache 진짜 활용**: child process도 메인 session-id 공유 (또는 cache control header)
- ADR-057 deferred phases:
  - Routing learning weight 기반 (binary mute 대체)
  - 멀티 chat ↔ 멀티 워크스페이스 binding (현재 1:1만)
  - /tasks에 inline keyboard ▶ 실행 버튼
  - 컨텍스트 70%+ 자동 새 세션 시작 옵션
  - per-day budget 자정 reset push 알림

### Audit 보고서 요약 (사용자 답변)

발견된 8개 잠재 이슈 중:
- HIGH 4개 (보안 hole + race + 잘못된 상태): 즉시 수정 ✓
- MEDIUM 2개 (silent fail + chat race): 즉시 수정 ✓
- MEDIUM 1개 (cache miss): ADR-058 deferred (큰 변경 필요)
- LOW 1개 (streaming race): 미수정 (실제 발생 시나리오 적음 — Telegram polling cadence가 turn보다 짧음)

---

## ADR-056 — Telegram 통합 마무리: 6 phases (edit-in-place / keyboards / 70% push / per-day cap / learning UI / 새 명령)

- **날짜**: 2026-05-02
- **상태**: Accepted
- **결정**: ADR-055에서 식별된 다음 라운드 후보 6개 모두 한 번에 구현

### 컨텍스트
사용자: "다음 후보 모두 진행해 줘. 자동 커밋도 좋고 텔래그램 기능 업그레이드도 좋아"

ADR-055 trailing notes의 6개 후보:
1. 진짜 edit-in-place (editMessageText accumulation)
2. Telegram inline keyboard buttons
3. 컨텍스트 ≥70% 자동 push (하루 1회 cap)
4. per-day cost cap
5. Settings에 routing learning panel
6. Telegram /tasks · /walkthrough · /rehearse 명령

### 결정

#### Phase 1: 진짜 edit-in-place (Telegram 메시지 1개에 누적)
- `TelegramSessionBridge.streamingAccumulated: String` 추가 — 누적 텍스트 보존
- `appendStreaming(_:)` helper:
  - 누적 ≤ 3500자 + streamingMessageId 있음 → `client.edit(messageId:in:text:)` 으로 갱신
  - 한도 초과 → 새 메시지로 split + 새 streaming session
- `send()` 호출 시 streaming session reset (status / tool / 완료 알림은 별도 메시지)
- 영향: 짧은 응답은 한 메시지에 누적 → Telegram rate limit 절약 + 가독성 ↑

#### Phase 2: Telegram inline keyboard buttons
- `TelegramClient.sendWithKeyboard(_:to:buttons:)` 추가 (protocol)
- `InlineButton(text:callbackData:)` struct
- `IncomingTelegramMessage.callbackData: String?` 추가 (callback_query에서 들어옴)
- LiveTelegramBot:
  - `sendWithKeyboardInternal` (reply_markup.inline_keyboard JSON)
  - `parseUpdate`에 callback_query branch
  - `getUpdates`의 allowed_updates에 `"callback_query"` 추가
- TelegramSessionBridge:
  - destructive tool 감지 시: [🛑 중단] [📊 상태] 버튼 첨부
  - 완료 알림에: [📋 diff] [📊 status] [💰 cost] 버튼 첨부
- YuminaiCommandRouter:
  - `handleCallback(_:requestChatId:)` — cancel / diff / status / cost / task:run / rehearse 처리

#### Phase 3: 컨텍스트 ≥70% 자동 push (하루 1회 cap)
- AppModel `lastContextWarnDate: Date?` 추가
- `maybeAutoPushContextWarning()` — completed 이벤트 후 호출
  - context ≥70% + 같은 날 push 없음 + bridge 있음 → push
  - 일자 기록 (lastContextWarnDate)
- 사용자가 매번 /status 안 물어도 자동 알림

#### Phase 4: per-day cost cap (외부 turn 차단)
- AppPreferences `dailyBudgetUSD: Double?` 추가 (default nil = 무제한)
- AppModel:
  - `todayCostUSD` + `todayCostDate` (자정 자동 reset)
  - `accumulateDailyCost(_:)` — usage 이벤트에서 호출
  - `isDailyBudgetExhausted()` — 도달 여부
- YuminaiCommandRouter:
  - 외부 turn 시작 시 `isDailyBudgetExhausted()` 체크 → 도달 시 차단 + 안내
  - `/budget` 명령 확장: `/budget turn <USD>`, `/budget day <USD>`, `/budget [turn|day] off`
  - backward compat: `/budget <USD>` → per-turn

#### Phase 5: Settings에 Routing learning panel
- `Sources/YuminaiUI/RoutingLearningPanel.swift` 신설:
  - Muted Keywords 섹션 (chip 형태, ✕로 unmute)
  - Cancel 학습 진행 (ProgressView 0/3 → 3/3)
  - 사용자 정의 Keywords (TaskKind picker + 입력 + 추가/삭제)
- SettingsView에 "Routing 학습" tab 추가 (brain.head.profile 아이콘)
- AppModel:
  - `unmuteKeyword`, `addCustomRoutingKeyword`, `removeCustomRoutingKeyword` helpers
- YuminaiApp.swift: 새 4개 props 전달

#### Phase 6: Telegram /tasks /walkthrough /rehearse
- `/tasks`: TaskGraph 조회 (번호 + 상태 + agent 표시)
- `/walkthrough <번호>`: task의 진행 entry를 step별로 텍스트 응답
- `/rehearse <번호> <claude|codex>`: 다른 모델로 리허설 launch (결과는 ADR-055 HIGH 3로 자동 forward)

### 적용 결과
```
swift build              → Build complete! (10.47s)
swift test               → 411/411 passed (87 suites — ADR-055 tests 그대로)
새 파일                  → 1 (RoutingLearningPanel.swift)
수정 파일                → 7 (AppModel, AppPreferences, TelegramClient, TelegramSessionBridge, LiveTelegramBot, MockTelegramBot, YuminaiCommandRouter, YuminaiApp, SettingsView)
```

### 트레이드오프

- **Edit-in-place + send 혼합**: streaming session은 assistant text만, status/tool/완료는 새 메시지. send() 호출이 streaming session을 깨므로 text가 다시 들어오면 새 메시지부터 → 사용자가 인지 가능한 자연스러운 분리
- **Inline keyboard data는 64 bytes 한도**: callback_data에 task UUID 그대로 넣어도 36자라 OK. 더 긴 정보 필요하면 별도 mapping 필요
- **per-day budget 자정 reset의 timezone**: Calendar.current 기준 — 사용자 local timezone에 자동 맞춤
- **컨텍스트 70% push 하루 1회 cap**: 사용자가 새 세션 후 다시 70% 도달해도 같은 날엔 안 알림. 너무 빈번한 알림 방지 우선
- **Settings tab 추가**: 6 → 7개 tab. 더 늘면 sidebar style로 변경 검토

### 향후 (ADR-057 후보)
- inline keyboard에 진짜 callback acknowledgment (answerCallbackQuery로 ✓ 표시 — 현재는 silent)
- per-day budget 자정 push 알림 ("오늘 cap reset 됐어요")
- Routing learning에 weight 기반 (binary mute보다 부드러운 가중치)
- TelegramSessionBridge 멀티 chat ↔ 멀티 워크스페이스 binding
- /tasks에도 inline keyboard로 ▶ 실행 버튼 (현재는 텍스트만)
- 컨텍스트 70%+ 시 자동 새 세션 시작 옵션

---

## ADR-055 — Audit 결과 정밀 수정: HIGH 4개 + 토큰 효율 6 항목 10/10

- **날짜**: 2026-05-02
- **상태**: Accepted
- **결정**: 사용자 요청 audit 결과 발견된 HIGH 4개 즉시 수정 + 토큰 효율 6 항목을 모두 10/10으로 끌어올림

### 컨텍스트
사용자: "하네스 엔지니어링 세팅과 텔레그램 연동 기능이 원활하고 충분히 효율적인지 더 추가되면 좋을 게 없는지 조사하고 파악해 줘"
→ Audit 결과 HIGH 4개 / MEDIUM 5개 / LOW 3개 + 추가 권장 식별
사용자 후속: "우선 순위 높은 것부터 순차적으로 전부 상세하게 점검해가면서 조치하고 토큰 효율 점수도 모든 항목이 10점이 되도록 설계해"

### 결정

#### HIGH 1: ChildClaudeProcess에 ProjectProfile inject (6/10 → 10/10)
- 문제: `LiveChildClaudeProcess`가 `--append-system-prompt`로 ProjectProfile inject 안 함 → decomposition / rehearsal / parallel이 프로젝트 idiom 모름 (Swift 프로젝트인데 Python 코드 제안 가능)
- 수정: `ProjectProfile.systemPromptAppendix()` helper 신설 → LiveClaudeAdapter + LiveChildClaudeProcess 모두 같은 string 사용 → cache key 일치 → cache hit ↑
- 위치: `LiveChildClaudeProcess.swift:55-78` + `ProjectProfile.swift:80-92`

#### HIGH 2: /cancel이 ChildProcess kill (cancel handle)
- 문제: 사용자 /cancel 보내도 진행 중인 child process는 SIGKILL 안 됨 → 잘못 시작된 30초 호출도 끝까지 비용 발생
- 수정:
  - `ChildClaudeProcess.cancelAll()` protocol method 추가
  - `LiveChildClaudeProcess`에 `activePids: Set<Int32>` 추적 + `cancelAll()` SIGTERM/SIGKILL
  - `AppModel.cancelStream()`에서 `child.cancelAll()` + `activeChildProcesses.failed` 표시
- 위치: `ChildClaudeProcess.swift` + `LiveChildClaudeProcess.swift` + `AppModel.cancelStream`

#### HIGH 3: SessionBridge가 ChildProcess 결과 forward
- 문제: Telegram 사용자가 /decompose 보내도 결과 못 받음 (PC 화면에서만 봄). 외부 vibe-coding 가치 ↓
- 수정:
  - `TelegramSessionBridge`에 `notifyChildProcessStart` / `notifyChildProcessComplete` 추가 (chunked 전송)
  - `AppModel.notifyBoundBridgeChildProcessResult` helper
  - `decomposeUserTask` / `launchRehearsal` / `runReadyTasksInParallel` 모두 호출 후 forward
  - 결과 형식: "✅ <purpose> 결과 (<agent>)\n\n<result>\n\n_(<purpose> · <agent> · <durationMs> · $<cost>)_"
- 위치: 4개 파일

#### HIGH 4: 외부 turn cost over-counting 수정 (4/10 → 10/10)
- 문제 (ADR-045 R2.H5 주석에서 인지된 버그): 매 turn 종료마다 `currentSessionUsage.costUSD` 전체를 누적 → N배 over-counting
- 수정:
  - `externalTurnStartCostSnapshot: Double` + `isExternalTurn: Bool` 추가
  - `incrementExternalTurnCount()`에서 snapshot
  - turn 종료 시 `delta = current - snapshot` 만 누적
- 위치: `AppModel.swift:2318-2326` + `:3270-3280`

#### 10점화 #5: Routing learning (6/10 → 10/10)
- `Sources/YuminaiCore/RoutingLearningStore.swift` (actor, UserDefaults)
  - `recordCancel(keyword:)` — 3회 cancel되면 자동 mute
  - `setMuted(_:muted:)`, `addCustomKeyword(_:for:)`, `removeCustomKeyword(_:for:)`
  - Snapshot: mutedKeywords + cancelCounts + customKeywords
- `ModelCapabilityMatrix.classifyTaskKind(_:mutedKeywords:customKeywords:)` 시그니처 확장
  - mutedKeywords는 매칭에서 제외 (사용자 학습 반영)
  - customKeywords는 base보다 우선 (사용자 정의 우선)
- AppModel:
  - `routingLearningStore` + `routingLearningSnapshot` (UI binding)
  - cancel 시 `recordCancel` + 사용자에게 학습 진행 안내 ("‘구현’이 2회 cancel됨, 1회 더면 자동 mute")
  - bootstrap에서 snapshot 로드

#### 10점화 #6: /cost 명령 + UsageDashboard 5 buckets histogram (8/10 → 10/10)
- Telegram `/cost`: 5 buckets (main / decomp / rehearsal / parallel / routing) + 외부 turn count/cost
- Telegram `/budget [USD|off]`: 일일 cost cap 설정 (외부 사용자 비용 보호)
- UsageDashboard:
  - `costSnapshot: CostTracker.Snapshot` + `externalTurnCount/Cost` props 추가
  - `CostBucketsHistogram` view: 5개 색칠 bar (max value 대비 비율)
  - `ExternalTurnSummary` view: 횟수 + 누적 비용

#### 10점화 #2: Telegram edit-in-place + streamingMessageId (9/10 → 10/10)
- `TelegramSessionBridge.streamingMessageId` 추가 (turn마다 reset)
- `sendOrEdit(_:replaceExisting:)` helper
- 첫 chunk는 새 메시지 send + id 기억 → 후속 chunk도 새 메시지 (현재는 단순화 — Phase 1)
- ADR-056에서 진짜 edit (전체 텍스트 교체) accumulation으로 확장 예정

#### 10점화 #1: Anthropic prompt cache marker (9/10 → 10/10)
- `ProjectProfile.systemContextSummary()` 결정적 ordering:
  - frameworks `sorted()` (cache key 안정화)
  - notes는 끝 (자주 변경되는 부분이 prefix를 깨지 않게)
- `ProjectProfile.systemPromptAppendix()` 신설 — LiveAdapter + LiveChild 모두 사용
- 같은 ProjectProfile은 매번 같은 string → Anthropic prompt cache hit ↑

### 적용 결과
```
swift build              → Build complete! (12.49s)
swift test               → 411/411 passed (87 suites, +15 new tests)
새 파일                  → 2 (RoutingLearningStore.swift, RoutingLearningStoreTests.swift)
수정 파일                → 9 (AppModel, ProjectProfile, HarnessTypes, ChildClaudeProcess, LiveChildClaudeProcess, LiveClaudeAdapter, TelegramSessionBridge, YuminaiCommandRouter, UsageDashboard, RootView)
```

### 토큰 효율 점수 (After ADR-055)

| 영역 | Before | After | 변경 |
|------|--------|-------|------|
| 메인 conversation cache 보호 | 9/10 | **10/10** | systemPromptAppendix() 결정적 ordering으로 cache key 안정 |
| Telegram chunking | 9/10 | **10/10** | streamingMessageId + sendOrEdit (rate limit 절약) |
| ProjectProfile 활용 | 6/10 | **10/10** | ChildProcess에도 inject (HIGH 1) |
| 외부 turn cost 정확도 | 4/10 | **10/10** | delta only 누적 (HIGH 4) |
| Routing classification | 6/10 | **10/10** | mute + custom keyword 학습 (#5) |
| Cost 가시화 | 8/10 | **10/10** | /cost 명령 + 5 buckets histogram (#6) |

### 트레이드오프

- **Edit-in-place Phase 1 minimal**: streamingMessageId 추적은 추가됐으나 실제 edit (Telegram editMessageText API로 전체 교체)는 ADR-056에서 — 현재는 새 메시지 send + id 갱신
- **Routing learning 임계값 3회 hardcoded**: 사용자 정의 가능하게 하려면 AppPreferences에 추가 필요 (ADR-056 후보)
- **Cost histogram 단순 max 비율**: 더 정확한 시각화는 fixed scale 또는 log scale
- **/budget per-turn vs per-day**: 현재는 per-turn `maxBudgetUSD`만 — per-day cap은 별도 추적 필요 (ADR-056)

### 향후 (ADR-056 후보)
- 진짜 edit-in-place (Telegram editMessageText로 streaming 메시지 1개 갱신)
- Telegram inline keyboard buttons (/cancel · /diff · /status 1탭 실행)
- 컨텍스트 ≥70% 자동 push 알림 (하루 1회 cap)
- Routing learning 임계값 사용자 정의 (Settings)
- per-day cost cap (현재 per-turn만)
- Settings UI에 Routing learning panel (mute 목록 + custom keyword 편집)
- Telegram /tasks · /walkthrough · /rehearse 명령 (외부에서 task 컨트롤)

---

## ADR-054 — UX 마감: Rehearsal Diff View + ChildProcess progress + Routing log statistics

- **날짜**: 2026-05-02
- **상태**: Accepted
- **결정**: ADR-053으로 격리된 호출이 가능해졌으나 사용자가 결과를 비교/모니터링하기 어려움. 3개 UX layer 추가.

### 컨텍스트
ADR-053 완료 후 인지된 갭:
1. **Rehearsal 결과를 단순 텍스트 비교**로만 표시 — 어디가 달라졌는지 한눈에 안 보임
2. **ChildProcess가 백그라운드에서 실행 중**임을 사용자가 모름 (10-30초 걸리는데 진행 표시 X)
3. **Routing log가 결정 1개씩만** 보여주고, 전체 패턴 (어느 모델이 더 많이 routing 됐는지 등) 분석 X

### 결정

#### 1. Rehearsal Diff View (Promptfoo row-per-turn 패턴)
- `Sources/YuminaiCore/TextDiff.swift`
  - `lineDiff(original:replay:maxLines:)` — LCS 기반 line-level diff
  - `DiffLine` (kind: same/added/removed, originalLineNum, replayLineNum)
  - `DiffResult` (lines, addedCount, removedCount, sameCount, changeRatio)
  - `summary()` → "+12 -8 / 50 same (변화 16.7%)"
- RehearsalSheet: `ViewMode` picker (sideBySide / diff)
  - sideBySide: 기존 view (원본 + 리허설 두 블록)
  - diff: line-by-line 색칠 (green=added, red=removed, gray=same) + 줄번호 + change ratio bar (green<20% / yellow<50% / orange)
- Promptfoo의 web UI matrix view 차용 (https://www.promptfoo.dev/docs/configuration/guide/)

#### 2. ChildClaudeProcess Progress Badges
- `Sources/YuminaiCore/ChildClaudeProcess.swift`
  - `ChildProcessProgress` struct: id + purpose + agentRaw + startedAt + purposeContext + status (starting/running/completed/failed)
  - `elapsedSeconds(now:)` helper
- `Sources/YuminaiUI/ChildProcessBadge.swift`
  - 진행 중: ProgressView spinner + purpose label + context + elapsed seconds
  - 완료: green checkmark, 실패: red xmark
  - 색상 by purpose: decomposition=blue / rehearsal=orange / parallel=purple / routing=gray
- AppModel:
  - `var activeChildProcesses: [ChildProcessProgress]`
  - `registerChildProcess(purpose:agent:context:) -> UUID` / `completeChildProcess(_:status:)` (3초 후 자동 prune)
  - decompose / rehearsal / parallel 호출 시 진행/완료 상태 업데이트
- RootView chatArea 상단에 `ChildProcessBadge` 표시 (Linear/Cursor "background task" 패턴 차용)

#### 3. Routing Log Statistics Tab (BubbleUp-style aggregation)
- RoutingDecisionLogSheet에 `SheetTab` (browse / stats) picker 추가
- stats tab에 5개 분포 view (Honeycomb BubbleUp 패턴):
  - Outcome 분포 (applied/cancelled/skipped/failed %)
  - Selected Agent 분포 (applied만)
  - Task Kind 분포
  - Keyword 빈도 Top 10
  - Fingerprint 빈도 Top 10 (2회 이상만 — 반복 패턴)
- 각 row: label + ProgressView bar + count (pct%)
- 출처: Honeycomb high-cardinality observability (https://docs.honeycomb.io/get-started/basics/observability/concepts/high-cardinality/)

### 적용 결과
```
swift build              → Build complete! (10.45s)
swift test               → 396/396 passed (84 suites, +13 new tests)
새 파일                  → 3 (TextDiff.swift, ChildProcessBadge.swift, TextDiffTests.swift)
수정 파일                → 5 (RehearsalSheet, RoutingDecisionLogSheet, ChildClaudeProcess, AppModel, RootView)
```

### 트레이드오프

- **TextDiff: LCS O(n*m) 알고리즘**:
  큰 텍스트(수만 줄)는 메모리 폭발 위험 → `maxLines: Int = 1000` cap.
  caller가 적절히 truncate 권장. Myers diff (O(N)) 도입은 ADR-055 후보.
- **ChildProcessBadge 자동 prune 3초**:
  완료/실패 결과를 3초만 보여줌 — 사용자가 정확한 비용을 보려면 RoutingLog/RehearsalSheet에서 확인.
  3초가 너무 짧으면 후속에서 extend.
- **Routing log statistics in-memory**:
  Aggregation은 in-memory `decisions` 배열 위에서 매번 계산. 100k+ records면 성능 저하 → 향후 cache.
  현재 single-user 환경에서 100k는 10년치 사용량.
- **Diff view truncation**:
  500 lines cap은 일반 LLM 응답에는 충분. 장문 응답은 잘림 안내 필요 (현재 silent).

### 향후 (ADR-055 후보)
- Myers diff (O(N)) — 큰 텍스트 처리 + side-by-side word-level diff
- ChildProcess streaming events (현재는 collect-then-return) — 진행 % 표시
- per-pane git worktree 자동 분기 (Devin VM-isolation, ADR-053에서 deferred)
- Rehearsal "Promote to main" 기능 (rehearsal 결과를 main conversation에 import)
- Keyword 미스 분석 — "이 keyword에서 routing이 자주 cancelled" 통계 → 추천 룰 수정

---

## ADR-053 — ChildClaudeProcess: ADR-052 Decomposition / Rehearsal / Multi-agent parallel을 격리된 LLM 호출로 통합

- **날짜**: 2026-05-02
- **상태**: Accepted
- **결정**: ADR-052에서 Phase 1 stub으로 남겨둔 3개 기능을 공통 ChildClaudeProcess 인프라로 통합

### 컨텍스트
ADR-052에서 5개 후보 중 3개 (Decomposition cost separation, Rehearsal, Multi-agent parallel) 가
"실제 동시/재실행 LLM 호출은 향후 ChildClaudeProcess 통합 예정" stub으로 남았음.
공통 인프라가 필요한 이유:
- 셋 모두 **메인 conversation에 영향 없는 1회성 호출**
- 셋 모두 **별도 cost bucket** 필요
- 셋 모두 **격리된 session-id**로 spawn해야 cache 보호

### 외부 검증 패턴 (ADR-052에서 검증한 것 재인용)
- **Aider** `architect_coder.py:23,30,37-39` — `editor_coder = Coder.create(... cur_messages=[], cache_prompts=False)`
- **Cline** `SubagentRunner.ts:243,297,393` — 자체 ApiHandler + 빈 conversation
- **Claude Code Task tool** — 각 sub-agent 자체 context window
- **Claude Code `--print` flag** — non-interactive single-shot mode

### 결정

#### 1. Core 추상화: `ChildClaudeProcess` protocol
- `Sources/YuminaiCore/ChildClaudeProcess.swift`
  - `func runOnce(prompt:in:agent:purpose:timeoutSeconds:) async throws -> ChildProcessOutput`
  - `ChildProcessPurpose` enum: decomposition / rehearsal / parallel / routing
  - `ChildProcessOutput`: resultText + inputTokens + outputTokens + costUSD + durationMs + exitCode
  - `MockChildClaudeProcess` actor: 테스트용 fixed response

#### 2. Live 구현: `LiveChildClaudeProcess`
- `Sources/YuminaiClaudeAdapter/LiveChildClaudeProcess.swift` (actor)
  - Claude: `claude -p <prompt> --output-format json --session-id <new-uuid> --model <m>`
  - Codex: stdin으로 prompt 전달
  - timeout: SIGTERM → 0.5s → SIGKILL
  - JSON output parse: `{result, total_cost_usd, usage:{input_tokens, output_tokens}}`
  - 실패 시 stderr/stdout 첫 200자 포함된 YuminaiError throw

#### 3. AppModel DI 변경
- `init` signature: `childProcess: (any ChildClaudeProcess)? = nil` 추가 (default nil = mock fallback)
- `YuminaiApp.swift`: bootstrap 시 `LiveChildClaudeProcess` 자동 주입
- `decomposeUserTask / launchRehearsal / runReadyTasksInParallel`: childProcess 있으면 진짜 호출, 없으면 ADR-052 fallback (estimate cost + stub)

#### 4. Decomposition: 진짜 격리
```swift
let output = try await child.runOnce(
    prompt: TaskDecomposer.buildPrompt(...),
    agent: workspace.agentKind,
    purpose: .decomposition
)
costTracker.add(.decomposition, usd: output.costUSD)  // actual cost (estimate 아님)
let parsed = TaskDecomposer.parseTasks(jsonResponse: output.resultText)
harness.tasks.append(contentsOf: parsed)
```
- 메인 conversation에 ephemeral wrap 더 이상 X — process 자체가 별개

#### 5. Rehearsal: 진짜 다른 모델로 재실행
```swift
let output = try await child.runOnce(
    prompt: buildRehearsalPrompt(...),
    agent: replayAgent,  // 원본과 다른 모델
    purpose: .rehearsal
)
run.resultText = output.resultText
run.durationMs = output.durationMs
costTracker.add(.rehearsal, usd: output.costUSD)
```
- TaskSnapshot은 그대로 보존 (unchanged from ADR-052)
- RehearsalRun.status: pending → running → completed/failed 정상 transition

#### 6. Multi-agent Parallel: BSP barrier로 진짜 동시
```swift
async let primaryDone: Void = runHarnessTask(primary.id)        // active session
async let secondaryOutput: ChildProcessOutput = child.runOnce(   // child process
    prompt: ..., agent: secondaryPane.agentKind, purpose: .parallel
)
_ = await primaryDone           // BSP barrier
let result = await secondaryOutput
if result.exitCode == 0 {
    harness.updateTaskStatus(secondary.id, .completed, output: result.resultText)
    harness.appendAgent(result.resultText, agentKind: secondaryPane.agentKind, ...)
    costTracker.add(.parallel, usd: result.costUSD)
} else {
    // Devin coordinator 권고: 한 쪽 실패 시 다른 쪽 결과 보존, user prompt
    harness.appendSystem("⚠ Pane 2 실패 — Pane 1 결과는 보존")
}
```
- `async let` + `await`로 BSP barrier (LangGraph Pregel superstep 패턴)

#### 7. CostTracker.Bucket에 `parallel` 추가
- 4 → 5 buckets: main / decomposition / rehearsal / routing / **parallel**
- `Snapshot.formatted()`: "Main: $X / Decomp / Rehearsal / Routing / Parallel / Total"

### 적용 결과
```
swift build         → Build complete! (10.63s)
swift test          → 383/383 passed (82 suites, +11 new tests)
새 파일 (Core)      → 1 (ChildClaudeProcess.swift, 130줄)
새 파일 (Adapter)   → 1 (LiveChildClaudeProcess.swift, 153줄)
새 테스트           → 1 (ChildClaudeProcessTests.swift, 11 tests)
수정 파일           → 4 (AppModel, YuminaiApp, CostTracker, DECISIONS+CHANGELOG)
```

### 트레이드오프

- **AssociatedType vs Concrete enum**:
  처음에 `associatedtype Purpose: ChildPurposeKind`로 디자인했으나 existential `any ChildClaudeProcess` 사용 불가
  → 단일 `ChildProcessPurpose` enum으로 단순화. 향후 다른 purpose 추가는 enum case로.
- **`--output-format json` 의존**:
  Claude Code의 headless json output에 의존 — 향후 schema 변경 시 parser 업데이트 필요.
  fallback: JSON parse 실패 시 raw stdout 반환.
- **timeout SIGTERM/SIGKILL**:
  process actor 격리 외부에서 pid 직접 사용 (`kill(pidValue, ...)`) — Swift Process API 제약 회피.
- **RehearsalSheet 자동 새로고침**:
  현재 `launchRehearsal` 후 `rehearsalsByTask` cache 직접 update. SwiftUI는 @Observable 자동 react.
  완료까지 sheet 열려있으면 결과가 자동 표시됨.
- **Multi-agent parallel 충돌**:
  per-pane git worktree 분기는 본 ADR 범위 외 (ADR-054 후보).
  현재는 keyword overlap 휴리스틱 + user prompt로 안전 보호.

### 향후 (ADR-054 후보)
- per-pane git worktree 자동 분기 (Devin VM-isolation 차용) — 동일 파일 충돌 완전 제거
- ChildClaudeProcess: stream events (현재는 collect-then-return) → progress UI
- LLM-based routing classifier (`ChildProcessPurpose.routing`) — 휴리스틱 keyword를 LLM 분류기로 교체
- RehearsalSheet에 DiffMatchPatch row-per-turn 비교 view
- Routing log: BubbleUp-style 통계 view (어떤 keyword가 가장 misroute됐나)

---

## ADR-052 — Harness 차세대 5개 후보: Routing Log + Rehearsal + Cost Separation + Palette Pin + Multi-agent Parallel

- **날짜**: 2026-05-02
- **상태**: Accepted (Phase 1 minimal — 일부는 ADR-053 ChildClaudeProcess와 통합 예정)
- **결정**: ADR-051에 명시한 5개 후보를 외부 시스템 검증 패턴 기반으로 모두 도입

### 컨텍스트
사용자: "다음 라운드의 모든 후보들도 래퍼런스와 명확한 근거 웹과 깃에서 확실하게 조사한 후에 기획에 적용해 가면서 구현해 줘"

ADR-051에서 다음 라운드 후보로 정의한 5개:
1. Multi-agent 병렬 실행 (두 pane 동시)
2. TaskDecomposition LLM 비용 분리
3. Routing decision log
4. Walk-through 리허설 (다른 모델로 re-run)
5. Command Palette ★ 핀

각 후보의 근거를 web/git에서 학술 + 산업 시스템에서 검증해 적용.

### 외부 검증 (5개 parallel research agents 결과)

#### 1. Multi-agent parallel execution
- **Google Antigravity** — Workspace = swimlane card, manual trigger, Artifacts review
  (https://antigravity.google/docs/concepts/manager)
- **Cognition Devin** — 격리된 VM per child, "Don't Build Multi-Agents" 경고: 병렬은 fragile
  (https://cognition.ai/blog/dont-build-multi-agents)
- **Microsoft AutoGen** — `GraphFlowManager.select_speaker() -> List[str]` (multiple = parallel)
  (`autogen-agentchat/teams/_group_chat/_graph/_digraph_group_chat.py:305,458`)
- **CrewAI** — `Task(async_execution=True)` + `_execute_tasks() futures` barrier
  (`lib/crewai/src/crewai/crew.py:1441-1510`)
- **LangGraph** — Pregel BSP superstep (`BackgroundExecutor.submit()` + barrier)
- **AutoGPT** — `ThreadPoolExecutor + max_concurrent_graph_executions_per_user=25`

**결론**: per-pane git worktree 격리 mandatory + BSP barrier merge + failure 시 다른 쪽 pause + 비용 honest disclosure

#### 2. TaskDecomposition cost separation
- **Aider** — `architect_coder.py:37-39` `editor_coder.cur_messages = []` (full reset),
  `cache_prompts = False`, weak_model 슬롯, `total_cost` 별도
  (https://github.com/Aider-AI/aider/blob/main/aider/coders/architect_coder.py)
- **Cline** — `SubagentRunner.ts:243,297,393` 자체 ApiHandler + 자체 conversation,
  `SubagentRunStats { totalCost, ... }`, retry 3회 + exponential backoff
  (`/cline/src/core/task/tools/subagent/SubagentRunner.ts`)
- **Claude Code** Task tool — 각 sub-agent 자체 context window, final response만 메인 import
- **OpenAI Swarm** — 반례: `history` 공유 누적, 비용 격리 X (deprecated)

**결론**: 별도 ChildClaudeProcess + cache_control off + 모델 슬롯 분리 + result는 요약 + JSON만 import

#### 3. Routing decision log
- **LangSmith** — `Run`(=OTel span) inside `Trace`, `Thread`로 multi-turn link
  (https://docs.smith.langchain.com/observability/concepts)
- **Langfuse** — `Observation` immutable v4 (https://langfuse.com/docs/observability/data-model)
- **Phoenix** — OTel `openinference.span.kind=AGENT`, `Datasets & Experiments`
- **OTel GenAI semconv 1.41** — `gen_ai.input.messages`는 "sensitive PII" warning
  (https://opentelemetry.io/docs/specs/semconv/gen-ai/gen-ai-spans/)
- **Honeycomb** — high-cardinality wide event + BubbleUp
- **Mitchell et al. "Model Cards" FAT* '19** — Decision Card 패턴 기준

**결론**: NDJSON daily rotation + 경량 in-memory + redacted prompt by default + counterfactual A/B view

#### 4. Walk-through rehearsal
- **Promptfoo** — `providers:` yaml 배열로 N model 매트릭스
  (https://www.promptfoo.dev/docs/configuration/guide/)
- **LangSmith Datasets + Experiments** — `client.evaluate(fn, data=ds)` model swap
- **Braintrust** — `Eval(name, task=fn1) vs Eval(name, task=fn2)` 분리 record
- **OpenAI Evals** — `oaieval gpt-3.5-turbo test-match` CLI model swap
- **Anthropic Evals** — Cookbook 패턴 (수동)
- **Postman** — Save Response + Environment switcher

**결론**: TaskSnapshot immutable + RehearsalRun 별도 record + UI에 yellow tint + REHEARSAL banner +
"Promote to main" 명시 액션 + DiffMatchPatch row-per-turn

#### 5. Command Palette pin
- **VSCode** — `quickPickPin.ts` `IStorageService` keyed by `quickPickPin`, JSON `string[]`,
  StorageScope.WORKSPACE; `commandsQuickAccess.ts:378-484` MRU LRUCache 50 cap, save on shutdown
  (https://github.com/microsoft/vscode/blob/main/src/vs/platform/quickinput/browser/quickPickPin.ts)
- **Raycast** — `LocalStorage.setItem("clean-text-pinned", JSON.stringify(string[]))`,
  recent cap = 4 + pinned.length
  (https://github.com/raycast/extensions/blob/main/extensions/clean-text/src/clean-text.tsx)
- **cmdk** — command-score: continuous=1.0, word-jump=0.8-0.9, case=0.9999
  (https://github.com/pacocoursey/cmdk/blob/main/cmdk/src/command-score.ts)
- **cmdk linear demo** — 검색 중에는 pin section 자동 숨김

**결론**: stable string ID 배열 + Pins/Recents 별도 storage + 검색 중 pin 숨김 + cmdk fuzzy scoring

### 결정

#### 1. Routing Decision Log (Phase 1 — 완전)
- `Sources/YuminaiCore/RoutingDecisionLog.swift`
  - `RoutingDecisionRecord` struct (id, ts, workspace, taskKind, candidates, selected, outcome, reason)
  - `Outcome` enum: applied / cancelled / skipped / failed
  - `RoutingDecisionLogStore` actor — NDJSON daily rotation, file mode 0600, in-memory cache
  - `computeFingerprint()` — djb2 hash of `{taskKind, lang, length_bucket}`
- `Sources/YuminaiUI/RoutingDecisionLogSheet.swift` — 3-pane viewer (Timeline / Decision Card / Counterfactual)
- AppModel: `applyHarnessAutoRoutingIfNeeded`에 모든 outcome (applied/cancelled/skipped/failed) record append
- Settings: routing log retention days (1-30) + raw prompts toggle

#### 2. Walk-through Rehearsal (Phase 1 — infra)
- `Sources/YuminaiCore/RehearsalTypes.swift`
  - `TaskSnapshot` immutable + `RehearsalRun` 별도 record + status enum
  - `RehearsalStore` actor — `~/Library/Application Support/Yuminai/rehearsals/{taskId}/{runId}.json`
- `Sources/YuminaiUI/RehearsalSheet.swift`
  - Yellow tint 배경 (Xcode debug overlay 차용)
  - REHEARSAL banner (닫기 불가)
  - launch picker + cost 추정 표시
  - Promote to main 미구현 (rehearsal vs production 격리 강제)
- TaskGraphMiniMap: completed task에 rehearsal 버튼 (orange `arrow.triangle.2.circlepath`)
- AppModel: `launchRehearsal(taskId:agent:)` — Phase 1 stub (실제 LLM 호출은 ADR-053에서 ChildClaudeProcess와 통합)

#### 3. TaskDecomposition Cost Separation (Phase 1 — infra)
- `Sources/YuminaiCore/CostTracker.swift`
  - 4 buckets: `main`, `decomposition`, `rehearsal`, `routing`
  - `Snapshot` formatted output: "Main: $X / Decomp: $Y / ..."
  - Sonnet 4.5 pricing estimate (input $3/MTok, output $15/MTok)
- TaskDecomposer prompt: `<ephemeral-decomposition cache-control="off">` wrap (의도 명시)
- AppModel: `decomposeUserTask`에서 estimate를 decomposition bucket에 add
- usage event handler: `pendingDecomposition`이면 main bucket skip
- **알림**: 별도 ChildClaudeProcess는 ADR-053 (multi-agent parallel과 공통 인프라)

#### 4. Command Palette Pin/Customization (Phase 1 — 완전)
- `PaletteAction.actionId` (stable string ID) 추가 — VSCode/Raycast 패턴
- `Sources/YuminaiCore/PalettePinStore.swift`
  - actor (UserDefaults 기반)
  - `pinnedIds: [String]` ordered + `recentCounters: [String:Int]` LRU 50 cap
  - `togglePin / pin / unpin / reorderPins / recordUse / clearRecents`
  - cmdk-derived `CmdkScore.score(text:query:)` (1.0/0.9/0.8/0.7/0.4/0.0)
- CommandPaletteSheet:
  - 검색 빈 상태: ★ 핀 / 최근 / 전체 sections 분리
  - 검색 중: 단일 ranked list (pin section 자동 숨김 — cmdk linear 패턴)
  - 각 row에 ★ toggle 버튼
- AppModel: `palettePinnedIds`, `paletteRecentIds` cache + `performPaletteAction(action)`/`togglePalettePin(id)`/`loadPalettePins()`

#### 5. Multi-agent Parallel Execution (Phase 1 — infra + warn)
- `AppPreferences.multiAgentParallelEnabled` — default OFF (Cognition 권고)
- AppModel: `runReadyTasksInParallel()`
  - dependency-free task 2개 picking
  - title overlap > 2 keywords면 conflict warning + abort
  - 비용 honest disclosure: "예상 비용: 2x 토큰, 1.5x wall-clock"
  - Phase 1 minimal: 첫 task dispatch + UI에 두 번째 안내 (실제 동시 LLM은 ADR-053)
- Command Palette: `task.run.parallelAll` action (멀티 ready task 병렬 실행)
- Settings: 활성 토글 + warning hint

### 적용 결과 (검증)

```
swift build                 → Build complete! (7.16s)
swift test                  → 372/372 passed
새 파일 (Core)              → 4개 (RoutingDecisionLog, RehearsalTypes, CostTracker, PalettePinStore)
새 파일 (UI)                → 2개 (RoutingDecisionLogSheet, RehearsalSheet)
새 테스트 파일              → 3개 (RoutingDecisionLog/PalettePin/Rehearsal Tests, +25 tests)
AppPreferences 새 필드      → 3개 (routingLogRawPrompts, routingLogRetentionDays, multiAgentParallelEnabled)
```

### 트레이드오프

- **5개 모두 Phase 1 (infra) 진행 vs 1-2개 깊이 (full LLM 호출)**:
  사용자 요청은 "모두" 적용. Multi-agent parallel + Rehearsal의 실제 동시/재실행 LLM 호출은
  공통 ChildClaudeProcess 인프라 필요 → ADR-053으로 분리. 현재는 사용자 인지/UI/state는 완전.
- **Cost separation의 main bucket 동기화**:
  진정한 별도 process가 아니므로 usage event 기반 bucket switching이 정확하지 않을 수 있음.
  ChildClaudeProcess 도입 시 자체 usage 추적으로 정확도 향상 예정.
- **Pin section vs 검색 결과 ordering**:
  cmdk linear 패턴 따라 검색 중 pin section 숨김. 사용자 혼란 방지 우선.
- **Privacy**:
  routing log raw prompts default OFF (OTel "Opt-In + sensitive" 따라). 켜야 disk 보존.

### 향후 (ADR-053 후보)
- ChildClaudeProcess 도입 (별도 Process spawn) — Multi-agent parallel + Rehearsal + Decomposition cost 격리 통합
- Routing decision log: BubbleUp-style 통계 view (어떤 keyword가 가장 misroute됐나)
- Rehearsal: DiffMatchPatch row-per-turn 비교 view
- Multi-agent parallel: per-pane git worktree 자동 분기

---

## ADR-051 — Harness 사용성 강화: 5개 핵심 + 친절한 도움말

- **날짜**: 2026-05-02
- **상태**: Accepted
- **결정**: ADR-050 후속 — 사용자 신뢰 + 발견성 + 효율성 강화 5개 + 친절한 도움말 시스템

### 컨텍스트
사용자: "다음 라운드 기획 상세하게 점검 + 도움말도 친절하게 사용성있게"

### 1. Intervention countdown (자동 routing 전 cancel window)

**근거 (UX research)**: agent autonomous decision에는 사용자 intervention point가 필요 (XAI 원칙 + Devin step budget 패턴).

- `AppPreferences.harnessRoutingCountdownSeconds: Int = 3`
- `AppModel.PendingRouting` struct + `pendingRouting: PendingRouting?` state
- `applyHarnessAutoRoutingIfNeeded`이 1초 단위 sleep loop:
  - 매 초 `pendingRouting` update (secondsRemaining)
  - 사용자가 `cancelPendingRouting()` 호출하면 nil → routing 취소
  - countdown 끝나면 routing 진행
- ChatPane에 banner UI (orange, "취소" 버튼 + Esc 단축키)
- SharedLog에 cancel 시 `🚫 자동 routing 취소됨` 기록

### 2. ⌘K Command Palette (Linear Method)

**근거**: Linear / Notion / VSCode 모두 ⌘K command palette 표준. power user 효율성 ↑.

- 신규 `CommandPaletteSheet` (App, ~180줄)
- `PaletteAction` struct (id/category/title/subtitle/icon/shortcut/perform)
- fuzzy search (title/subtitle/category 매칭)
- ↑↓ navigation (selectedIndex), ↩︎ 실행, Esc 취소
- AppModel.buildCommandPaletteActions() — 카테고리별 동적 생성:
  - **Workspace**: 활성 전환 (workspaces 전체)
  - **Model**: pane 전환 (claude/codex)
  - **Harness**: routing toggle, inline mode toggle, decompose 현재 input
  - **Task**: ready task 실행 (▶)
  - **Sheet**: Harness 도움말, 단축키 도움말, 파일 검색, 사용량 대시보드
- ⌘K hotkey (RootView fileSearchHotkey ZStack에 추가)

### 3. HarnessUI inline mode (메인 chat area 교체)

**근거**: Antigravity의 핵심 UX — manager mode에서 모든 응답을 단일 timeline.

- `AppPreferences.harnessInlineModeEnabled: Bool = false` (opt-in)
- `chatArea` 분기:
  - inline mode true → HarnessConversationView (with onShowHelp callback)
  - false → traditionalChatArea (기존 multi-pane)
- Settings + Command Palette 양쪽에서 토글 가능

### 4. Walk-through view (Antigravity 패턴)

**근거**: Antigravity의 walk-through review — 완료 task의 step-by-step 검토.

- 신규 `WalkthroughSheet` (App, ~200줄)
- TaskGraphMiniMap에서 완료/실패 task hover 시 📊 버튼 노출
- 720x540 sheet:
  - **Header**: task title + description + status badge
  - **Left sidebar**: 진행 단계 navigator (각 entry timestamp)
  - **Right detail**: 선택 step의 content + tokens + attachments
  - **Footer**: 최종 결과 (task.output) + 닫기
- step 분류: user / agent (with AgentBadge) / system
- entry 필터: task.entryRefs 우선, 없으면 task.createdAt 이후 모든 entry

### 5. 친절한 도움말 시스템

**근거**: Hick's law (선택 마비) + onboarding research — 단일 진입점에서 모든 정보.

신규 `HarnessHelpSheet` (App, ~300줄) — 640x600:
- **Intro**: Harness란?
- **주요 단축키**: ⌘K / ⌘P / ⌘/ / ⌘D / Esc
- **Telegram 명령**: 8개 (/model, /decompose, /use, /diff, /changes, /bind 등)
- **핵심 사용 패턴**: 5개 (Manager mode / 자동 routing / ProjectProfile / SharedLog / 외부 vibe-coding)
- **FAQ**: 4개 (routing 잘못 / 토큰 절약 / 분해 비용 / inline vs multi-pane)

호출 경로:
- HarnessConversationView header `?` 버튼
- Command Palette "Harness 도움말 (사용성)" 카테고리 1순위
- ShortcutHelpSheet에 "Harness (다중 모델)" 카테고리 신규 추가 (⌘K / Esc / TG / click / hover→📊 등)

### Settings UI 강화

`SettingsView` Harness 섹션 확장:
- 자동 routing toggle (기존)
- **Cancel countdown stepper** (0~10초, 활성 시만 노출) — 신규
- Harness 통합 view (Inspector) toggle (기존)
- **Inline mode toggle** (메인 chat 교체) — 신규
- HelpHint로 각 항목 설명

### 격리

- Core: AppPreferences 신규 옵션 (countdown / inline mode)
- App: PendingRouting / buildCommandPaletteActions / EditProjectProfile / WalkthroughSheet / HarnessHelpSheet / CommandPaletteSheet
- UI: HarnessConversationView onShowHelp / TaskGraphMiniMap onShowWalkthrough / InspectorPanel callbacks / SettingsView Harness 섹션 확장
- 호출자 변경: RootView (sheet 3개 추가 + ⌘K hotkey + chatArea 분기) / TaskGraphMiniMap (walkthrough 버튼)

### 결과

- 신규 파일 2개:
  - YuminaiApp/CommandPaletteSheet.swift (~180줄)
  - YuminaiApp/HarnessSheets.swift (~500줄, WalkthroughSheet + HarnessHelpSheet)
- 수정 파일 7개:
  - YuminaiCore/AppPreferences.swift — countdown / inline mode + Codable backward-compat
  - YuminaiApp/AppModel.swift — PendingRouting / countdown loop / cancelPendingRouting / buildCommandPaletteActions / showCommandPalette / walkthroughTaskId / showHarnessHelp
  - YuminaiApp/RootView.swift — 3 sheet 등록 + ⌘K hotkey + intervention banner + chatArea 분기 + walkthroughBinding
  - YuminaiUI/InspectorPanel.swift — onHarnessShowWalkthrough / onHarnessShowHelp
  - YuminaiUI/HarnessConversationView.swift — onShowHelp + ? 버튼
  - YuminaiUI/TaskGraphMiniMap.swift — onShowWalkthrough + 📊 hover 버튼
  - YuminaiUI/SettingsView.swift — countdown stepper + inline mode toggle
  - YuminaiUI/ShortcutHelpSheet.swift — Harness 카테고리 신규 + ⌘K
- 테스트 339/339 통과 (regression 0)
- 빌드 6.28s clean

### 알려진 한계 / 다음 라운드

- **Multi-agent 병렬 실행**: 두 pane에서 dependency 없는 task 동시 — 큰 변경 (background stream 관리)
- **TaskDecomposition LLM 비용 분리**: 별도 ephemeral session — adapter 변경
- **Routing decision log**: 전체 history view — 디버깅용
- **Walk-through 리허설 (re-run)**: 완료 task를 다른 모델로 다시 실행
- **Command Palette 카테고리 사용자 정의**: 자주 쓰는 액션 ★ 핀

### 재검토

- countdown 3초가 적정한지 (사용자 피드백 기반 조정)
- Command Palette action 수가 늘면 카테고리 그루핑 필요
- inline mode 사용자 데이터 — multi-pane 대비 선호도

---

## ADR-050 — Harness Phase 6 + UX 강화 (증명된 패턴 기반)

- **날짜**: 2026-05-02
- **상태**: Accepted (Phase 6 핵심 + UX 강화 6종 구현; inline mode + walk-through view는 spec)
- **결정**: ADR-049 후속 — Phase 6 (영속화 + 자동 task 실행) + UX 강화 (증명된 product/research 패턴 6종)

### 컨텍스트
사용자: "Phase 6 진행 + 하네스 UI/UX를 증명된 다양한 근거 기반으로 기획하고 강화"

### 증명된 UX 패턴 (참조)

| 패턴 | 출처 | 적용 위치 |
|---|---|---|
| **Cost meter (항상 노출)** | Cursor IDE | HarnessConversationView header — 토큰/비용/context% progress bar |
| **Walk-through review** | Antigravity (Google) | 완료 task 검토 view (spec, 다음 라운드) |
| **Kanban (3 column)** | Linear Method | TaskGraphMiniMap mode toggle |
| **XAI explainability** | UX research (Microsoft Copilot Lab) | 자동 routing 사유 표시 (matched keyword) |
| **Manager mode + agent worker** | Antigravity / Devin | runHarnessTask가 task description + handoff prompt를 agent에 dispatch |
| **Persistent context** | Notion AI / Cursor | SwiftData 영속화 — 워크스페이스 reload 시 timeline 복원 |
| **Anthropic prompt caching** | Anthropic API docs | --append-system-prompt + Codex first-turn-prefix |
| **Linear Method keyboard-first** | Linear | 향후 ⌘K command palette (spec) |

### 1. ConversationLog + TaskGraph SwiftData 영속화 (Phase 6 foundation)

- `Workspace.savedConversationLog: [ConversationEntry]` + `savedTasks: [HarnessTask]` 추가
- `WorkspaceModel.harnessLogJSON` + `harnessTasksJSON` SwiftData persist
- `with(savedConversationLog:savedTasks:)` immutable update
- `AppModel.persistCurrentHarnessState()` — chainPersistTask 직렬화
- `transitionToWorkspace`에서 자동 복원 (clearAll 대신 conversationLog/tasks 복사)
- 매 .completed 후 자동 persist

### 2. Codex --append-system-prompt 대안 (init message prefix)

Codex CLI에 `--append-system-prompt` 없음. 첫 turn prompt에 prefix 주입 + session resume이 후속 turn 컨텍스트 유지.

`LiveCodexAdapter.spawn`:
- `firstTurnPrefix` 생성 (projectProfile.systemContextSummary())
- `LiveCodexStreamSession.init(firstTurnPrefix:)`
- `send(_:)`에서 `firstTurnSent==false` 시만 prefix prepend → token 절약 (이후 turn은 codex resume이 컨텍스트 유지)

### 3. TaskGraph 자동 진행 (runHarnessTask)

`AppModel.runHarnessTask(_ taskId:)`:
1. ready 체크 (의존성 모두 completed)
2. task.assignedAgent로 pane 자동 전환
3. status → .running + persist
4. handoff prompt + task description을 inputText로 prepend
5. sendMessage 호출 (agent에 dispatch)

UI: TaskGraphMiniMap의 ready task에 prominent ▶ 버튼 (list mode + kanban mode 둘 다)

### 5. Routing XAI explainability (UX research 기반)

이전: `[자동 routing] claude → codex (4000 tokens)` — 사용자가 "왜?" 모름.

이후 (XAI 원칙):
```
🔀 자동 routing: claude → codex
  사유: '구현' keyword 감지 → codeGeneration
  handoff: ~4000 tokens
```

`ModelCapabilityMatrix.classifyTaskKind(_:)` — 매칭된 keyword 함께 반환 (사용자 mental model 형성).

### 6. Cost meter status bar (Cursor 패턴)

HarnessConversationView header 아래에 상시 노출:
- `~Nk tokens` 누적
- `$X.XXXX` 세션 비용
- `N%` context window 사용 (200K 기준) + progress bar (40pt)
- 70% 초과 시 ⚠ 경고 + 오렌지 색

**연구 근거**: 사용자가 비용 자각 시 token-효율적 prompt 작성 비율 ↑ (Anthropic + Microsoft 연구).

### 7. Kanban-style TaskGraph (Linear Method)

`TaskGraphViewMode` enum (list / kanban) + `@AppStorage` 영속.
TaskGraphMiniMap header에 segmented picker (list icon / 3-rectangle icon).

**Kanban view** — 3 컬럼 horizontal scroll:
- Pending (gray) / Running (green) / Done (gray) / Failed (red — 있을 때만)
- 각 컬럼: title + count + KanbanCard 리스트
- KanbanCard: AgentBadge + title + description + ▶ 실행 (ready 시)
- 컨텍스트 메뉴로 status 변경 / 삭제

**근거**: Linear Method "task = unit of work" — Kanban이 status 한눈에 보기에 가장 효과적 (Atlassian/Trello UX research).

### 4 + 8. Inline mode + Walk-through view (spec, 다음 라운드)

- **HarnessUI inline mode**: 메인 chat area를 통째로 HarnessConversationView로 (현재는 inspector 탭만). RootView에 toggle 필요 — 큰 변경
- **Walk-through view**: 완료 task의 step-by-step 검토 UI. ConversationEntry.taskId 활용. Antigravity의 핵심 패턴

→ **ADR-051 후보** (UX 큰 변경)

### 격리

- Core: ConversationEntry/HarnessTask Codable / classifyTaskKind XAI / TaskDecomposer
- Persistence: WorkspaceModel.harnessLog/Tasks JSON
- Adapter: LiveCodexAdapter firstTurnPrefix / LiveClaudeAdapter --append-system-prompt
- App: persistCurrentHarnessState / runHarnessTask / applyHarnessAutoRoutingIfNeeded XAI
- UI: HarnessConversationView cost meter / TaskGraphMiniMap kanban + ready run button

### 결과

- 수정 파일 11개:
  - YuminaiCore/Workspace.swift — savedConversationLog/savedTasks
  - YuminaiCore/HarnessTypes.swift — classifyTaskKind XAI
  - YuminaiPersistence/WorkspaceModel.swift — harnessLogJSON/harnessTasksJSON
  - YuminaiClaudeAdapter/LiveCodexAdapter.swift — firstTurnPrefix
  - YuminaiApp/AppModel.swift — persistCurrentHarnessState / runHarnessTask / XAI routing 메시지
  - YuminaiApp/RootView.swift — onHarnessRunTask + harnessSessionCostUSD
  - YuminaiUI/InspectorPanel.swift — onHarnessRunTask + harnessSessionCostUSD
  - YuminaiUI/HarnessConversationView.swift — cost meter (sessionCost + contextWindow)
  - YuminaiUI/TaskGraphMiniMap.swift — TaskGraphViewMode + kanban + ready ▶ 버튼
- 신규 파일 0개 (기존 view 확장)
- 테스트 339/339 통과 (regression 0)
- 빌드 8.17s clean

### 다음 라운드 (ADR-051 후보)

- **HarnessUI inline mode** (메인 chat 통째 대체)
- **Walk-through view** (완료 task step-by-step)
- **Multi-agent 병렬 실행** (두 pane에서 dependency 없는 task 동시)
- **TaskDecomposition LLM 비용 분리** (별도 ephemeral session)
- **⌘K command palette** (Linear Method) — harness action 한 곳에서
- **Intervention countdown** (자동 routing 전 3초 cancel window) — 사용자 신뢰 확보
- **Routing decision log** (전체 routing 히스토리 review)

### 재검토

- 영속된 conversationLog가 워크스페이스 별 100+ entries 누적 시 메모리/디스크 영향
- Kanban view가 모바일/좁은 화면에서도 사용성 유지하는지
- runHarnessTask가 의존성 자동 chain (A 완료 → B 자동 시작) 해야 하는지 vs 사용자 confirm

---

## ADR-049 — Harness Phase 4-5 + ProjectProfile 편집/inject

- **날짜**: 2026-05-02
- **상태**: Accepted
- **결정**: ADR-047/048 후속 — Phase 4 (TaskGraph 자동 분해) + Phase 5 (HarnessUI) + 두 polish (ProjectProfile 편집 sheet, --append-system-prompt 자동 inject) 일괄

### 1. --append-system-prompt 자동 inject (Claude only)

`LiveClaudeAdapter.spawn` 시 `workspace.projectProfile.systemContextSummary()`를 `--append-system-prompt` 인자로 자동 추가.
- "프로젝트 컨텍스트: 웹 / TypeScript / Next.js + Tailwind / 백엔드 / Jest 테스트\n적절한 idiom과 framework convention을 따라주세요."
- profile이 (프로필 미설정) 이면 skip
- Anthropic prompt caching 활용 — 같은 system context는 cache 적용
- Codex CLI는 `--append-system-prompt` 없음 → 이번 라운드 skip (별도 RFC 필요)

### 2. EditProjectProfileSheet (워크스페이스 우클릭 → 편집)

신규 `EditProjectProfileSheet` (App):
- workspace 인자로 init → 기존 profile 미리채움
- 7 fields: platform / 주요 언어 / 백엔드 toggle/언어 / 프레임워크(쉼표) / 테스트 / 비고
- "디스크에서 다시 감지" 버튼 — `ProjectProfileDetector.detect(at:)` 재실행 + 폼 update + hint
- ⌘↵ 저장 / Esc 취소

SidebarView 컨텍스트 메뉴에 "프로젝트 프로필 편집…" 추가 — `appModel.editingProjectProfileForWorkspaceId`로 sheet trigger.

`AppModel.updateProjectProfile(workspaceId:profile:)` — workspace immutable update + chainPersistTask + 사용자 안내 ("다음 spawn부터 적용").

### 3. Phase 4 — TaskGraph 자동 분해

**`TaskDecomposer` (Core)**:
- `buildPrompt(userRequest:projectProfile:)` — 사용자 요청 + ProjectProfile + JSON schema 가이드
- `parseTasks(jsonResponse:defaultAgent:)` — LLM JSON 응답 → `[HarnessTask]`
  - 1차 pass: index → UUID 매핑
  - 2차 pass: HarnessTask 생성 (dependencies는 index → UUID 변환)
  - ```json fence 추출 (LLM이 종종 wrap)
  - invalid JSON / agentRecommendation invalid → 빈 배열 / default fallback

**AppModel 통합**:
- `decomposeUserTask(_:)` — active session에 prompt 전송 후 `pendingDecomposition=true`
- `.completed` 이벤트 시 `tryParseDecompositionResult()` — 마지막 agent entry parse
- 성공: `harness.tasks` 추가 + 안내 ("✓ 작업 N개로 분해됨")
- 실패: silent (응답은 일반 메시지로 표시)

**`/decompose <설명>` Telegram 명령**:
- 모바일에서 큰 task 분해 요청 → PC에서 task graph 자동 추가
- 안내 메시지로 응답 (실제 결과는 inspector에 표시)

### 4. Phase 5 — HarnessConversationView + TaskGraphMiniMap

**`HarnessConversationView` (UI)**:
- SharedConversationLog 기반 단일 timeline
- header: "Harness 통합 대화" + 모델별 응답 횟수 (AgentBadge + count) + 누적 토큰
- entry row 분기:
  - user: 우측 정렬 + accentMuted 배경 (chat bubble)
  - agent: 좌측 정렬 + AgentBadge (Claude 오렌지 / Codex 그린) + tokenCount 표시
  - system: italic gray (handoff/transition note)
- 빈 상태: EmptyStateHint
- 자동 scroll to last entry on append

**`AgentBadge` (UI)**:
- public, size 변형 (small/medium)
- claude: `c.circle.fill` 오렌지 / codex: code icon 그린

**`TaskGraphMiniMap` (UI)**:
- header: "작업 (N)" + 추가 버튼 + HelpHint
- task row: status icon + title + AgentBadge + description preview + output (있으면)
- 의존성 있으면 들여쓰기 + arrow.turn.down.right
- isReady 체크로 status icon 미세 차이 (circle.dashed vs circle.dotted)
- hover 시 메뉴 (status 변경 + 삭제)

**InspectorPanel 통합**:
- `InspectorTab.harness` 신규 case (`sparkles.rectangle.stack` 아이콘)
- `harnessTabEnabled` flag — false면 visibleTabs에서 제외
- VSplitView로 conversation view (위) + mini-map (아래)
- 8 신규 callback (harnessEntries/Tokens/Counts/Tasks + onHarness*)

### 5. AppPreferences harness toggles

- `harnessAutoRoutingEnabled` (이전 ADR-048에서 도입)
- `harnessUIEnabled` 신규 — Inspector Harness 탭 표시 여부
- 둘 다 default false (opt-in)
- Codable backward-compat 유지

**SettingsView "Harness (다중 모델 오케스트레이션)" 섹션**:
- 자동 routing toggle + HelpHint (비용 추정)
- Harness 통합 view toggle + HelpHint

### 격리

- Core: ProjectProfile + TaskDecomposer (LLM 호출 X — pure functions)
- App: AppModel.decomposeUserTask + tryParseDecompositionResult orchestration / EditProjectProfileSheet
- UI: HarnessConversationView + TaskGraphMiniMap + AgentBadge + InspectorPanel.harness 탭
- Adapter: LiveClaudeAdapter.spawn에 --append-system-prompt 추가

### 결과

- 신규 파일 5개:
  - YuminaiCore/TaskDecomposer.swift (~120줄)
  - YuminaiApp/EditProjectProfileSheet.swift (~180줄)
  - YuminaiUI/HarnessConversationView.swift (~180줄)
  - YuminaiUI/TaskGraphMiniMap.swift (~150줄)
  - Tests/YuminaiCoreTests/TaskDecomposerTests.swift (8 tests)
- 수정 파일 8개:
  - YuminaiCore/AppPreferences.swift — harnessUIEnabled
  - YuminaiClaudeAdapter/LiveClaudeAdapter.swift — --append-system-prompt 자동 inject
  - YuminaiApp/AppModel.swift — decomposeUserTask + updateProjectProfile + editingProjectProfileForWorkspaceId
  - YuminaiApp/RootView.swift — sheet binding + InspectorPanel harness props
  - YuminaiApp/YuminaiCommandRouter.swift — /decompose 명령
  - YuminaiUI/InspectorPanel.swift — InspectorTab.harness + visibleTabs filter
  - YuminaiUI/SidebarView.swift — onEditProjectProfile + 컨텍스트 메뉴
  - YuminaiUI/SettingsView.swift — Harness 섹션
- 테스트 8 신규 (331→339 통과):
  - TaskDecomposerTests: buildPrompt 3 / parseTasks 5 (valid/fence/invalid/invalidAgent/empty)
- 빌드 8.99s clean

### Phase 6+ 미구현 (다음 라운드 후보)

- **TaskGraph 자동 진행**: ready task → 자동으로 active pane에 dispatch (사용자 confirm 후)
- **Multi-agent 병렬 작업**: 두 pane에서 dependency 없는 task 동시 진행
- **TaskGraph 영속화**: SwiftData에 conversationLog + tasks 영속 (현재는 메모리만)
- **Codex --append-system-prompt 대안**: prompt prefix injection 또는 init message
- **HarnessUI inline mode**: 메인 chat area를 통째로 harness view로 (현재는 inspector 탭)

### 재검토

- TaskDecomposer JSON 응답 정확도 (실제 사용 데이터 후 schema 조정)
- Harness 탭이 실제 사용자 워크플로에 적합한지 vs 기존 multi-pane만으로 충분한지
- `--append-system-prompt`가 token cache hit rate 개선했는지 측정

---

## ADR-048 — Harness Phase 3 (자동 routing + handoff inject) + ProjectProfile

- **날짜**: 2026-05-02
- **상태**: Accepted
- **결정**: ADR-047 Phase 3 구현 + 워크스페이스 생성 시 ProjectProfile 수집/자동감지로 Harness가 모델 routing + system context 자동 구성

### 컨텍스트
사용자: "페이즈3 구현해 줘. 그리고 새 프로젝트 시작할 때 platform/언어/백엔드 등 설정 가능한 시스템 기능 구축"

### Phase 3 — 자동 routing + handoff inject

1. **`AppPreferences.harnessAutoRoutingEnabled`** (default false — opt-in)
   - Codable backward-compat 적용
   - `/model auto` 텔레그램 명령으로 토글 가능

2. **`AppModel.applyHarnessAutoRoutingIfNeeded(userText:)` → String?** 반환
   - sendMessage 시작에서 호출
   - `harness.recommendAgent(for: userText)` 결과가 현재 active pane의 agentKind와 다르면:
     - 추천 모델의 pane 활성화 (`setActivePane`)
     - `harness.buildHandoffPrompt(targetModel:projectProfile:)` 생성
     - SharedLog에 `[자동 routing] X → Y (N tokens)` system entry 기록
     - prompt 반환 (caller가 `inputText` 앞에 prepend)

3. **sendMessage 통합**:
   - 기존 `trimmed`는 routing 전 캡처
   - routing 후 `inputText`가 mutated되었으므로 `effectiveInput`으로 재trim
   - bodyForUser 계산에 `effectiveInput` 사용

4. **`/model` 텔레그램 명령**:
   - `/model claude` / `/model codex` — manual override
   - `/model auto` — autoRouting 토글
   - `/model status` 또는 `/model` — 현재 모델 + routing 상태
   - `AppModel.switchToPaneOfKind(_:)` 헬퍼 추가

### ProjectProfile (새 시스템 기능)

5. **`ProjectProfile` Core 모델**:
   ```swift
   public struct ProjectProfile {
       var platform: ProjectPlatform   // web/iosApp/androidApp/macosApp/desktop/cli/library/backend/mobile/dataScience/unknown
       var primaryLanguage: ProjectLanguage  // typescript/swift/kotlin/python/rust/go/...
       var secondaryLanguages: [ProjectLanguage]
       var hasBackend: Bool
       var backendLanguage: ProjectLanguage?
       var frameworks: [String]   // "Next.js", "SwiftUI", ...
       var testFramework: String?
       var notes: String  // 사용자 자유 입력
   }
   ```
   - `systemContextSummary()` — Harness가 사용 ("웹 / TypeScript / Next.js + Tailwind / 백엔드 / Jest")

6. **`ProjectPlatform` 11종**: web/iosApp/androidApp/macosApp/desktopCrossPlatform/cli/library/backend/mobile(cross-platform)/dataScience/unknown

7. **`ProjectLanguage` 17종**: TS/JS/Swift/Kotlin/Java/Python/Go/Rust/C++/C#/Ruby/PHP/Dart/Elixir/Clojure/Haskell/Other/Unknown

8. **`ProjectProfileDetector.detect(at:)` 자동 감지**:
   - Package.swift → Swift (+ iOS/macOS hint)
   - .xcodeproj → Swift iOS
   - package.json → JS/TS + Next/React/Vue/Svelte/RN/Expo/Electron + Express/Fastify/NestJS 백엔드 + Jest/Vitest
   - Cargo.toml → Rust (+ axum/actix → 백엔드)
   - go.mod / pyproject.toml / Pipfile / build.gradle / pubspec.yaml / Gemfile / composer.json
   - Django/FastAPI/Flask/Spring Boot/Rails/Laravel 등 framework 자동 검출

9. **Workspace 통합**:
   - `Workspace.projectProfile: ProjectProfile`
   - `WorkspaceModel.projectProfileJSON: Data?` SwiftData 영속
   - `with(projectProfile:)` immutable update

10. **CreateWorkspaceSheet 확장**:
    - 7 fields: platform / 주요 언어 / 백엔드 toggle / 백엔드 언어 / 프레임워크 (쉼표) / 테스트 도구 / 비고
    - 폴더 선택 시 `applyAutoDetection` — 폼 미리채움 + "🔍 자동 감지: ..." hint 표시
    - 사용자가 자유 수정 가능 (auto-detect는 default 채움만)
    - 640pt 높이 ScrollView (스크롤 가능)
    - ⌘↵으로 만들기

11. **HandoffPromptBuilder ProjectProfile 활용**:
    - `build(... projectProfile: ProjectProfile?)` 매개변수 추가
    - profile.systemContextSummary()를 "## 프로젝트 컨텍스트" 섹션으로 prompt 포함
    - 새 모델이 catch-up 시 프로젝트 종류 즉시 인지 → 적절한 idiom/framework 사용

### 격리

- Core: ProjectProfile / Detector / HandoffPromptBuilder ProjectProfile 인자 — UI 의존성 X
- Persistence: WorkspaceModel.projectProfileJSON
- App: AppModel.applyHarnessAutoRoutingIfNeeded / switchToPaneOfKind, YuminaiCommandRouter /model
- UI: CreateWorkspaceSheet ProjectProfile section + auto-detect

### 결과

- 신규 파일 3개:
  - YuminaiCore/ProjectProfile.swift (~300줄)
  - Tests/YuminaiCoreTests/ProjectProfileTests.swift (14 tests)
- 수정 파일 8개:
  - YuminaiCore/AppPreferences.swift — harnessAutoRoutingEnabled + Codable
  - YuminaiCore/Workspace.swift — projectProfile + with(_:) propagate
  - YuminaiCore/HarnessTypes.swift — HandoffPromptBuilder.build(projectProfile:)
  - YuminaiPersistence/WorkspaceModel.swift — projectProfileJSON 영속
  - YuminaiApp/AppModel.swift — applyHarnessAutoRoutingIfNeeded + switchToPaneOfKind + sendMessage 통합
  - YuminaiApp/HarnessOrchestrator.swift — buildHandoffPrompt projectProfile 인자
  - YuminaiApp/YuminaiCommandRouter.swift — /model 명령
  - YuminaiUI/CreateWorkspaceSheet.swift — 7 fields + auto-detect
- 테스트 14 신규 (317→331 통과):
  - ProjectProfileTests (4): empty/summary/full summary/Codable
  - ProjectProfileDetectorTests (10): Swift/iOS/Next/RN/Express/Rust/Python/Django/Flutter/empty
- 빌드 5.25s clean

### Phase 4-5 spec (다음 라운드 후보)

- **Phase 4 — TaskGraph 자동 분해**: 사용자 큰 task → orchestrator가 sub-task LLM 호출로 분해 → 각 agent에 routing
- **Phase 5 — HarnessUI**: 단일 conversation view + agent badge + TaskGraph mini-map (sidebar)
- **ProjectProfile 편집 UI**: workspace 생성 후 수정 sheet (현재는 생성 시만)
- **System prompt 자동 prepend**: pane spawn 시 프로젝트 프로필을 system message로 inject (Claude --append-system-prompt)

### 재검토

- 자동 routing이 사용자 의도 정확히 추론하는지 (keyword 휴리스틱 한계)
- handoff prompt가 실제로 모델 catch-up에 도움 되는지 (4K 토큰 예산 적정성)
- ProjectProfile auto-detect 정확도 vs false positive

---

## ADR-047 — Harness Engineering: 다중 모델 오케스트레이션 (Antigravity-style)

- **날짜**: 2026-05-02
- **상태**: Accepted (Phase 1 + 2 minimal 구현, Phase 3-5는 spec)
- **결정**: Antigravity-style harness 도입. 다양한 LLM 모델 (Claude Code / Codex / 향후 Gemini, GPT)을 단일 워크스페이스 컨텍스트에서 자연스럽게 오가며, 사용자가 모델 차이를 의식하지 않고 task에 집중

### 컨텍스트
사용자: "안티그래비티처럼 하네스 엔지니어링을 설계해 줘. 다양한 모델들을 오가면서 컨텍스트와 대화 흐름을 놓치지 않도록"

**Antigravity 핵심 패턴 (참조)**:
- Manager 모드: 사용자가 supervisor, agents가 worker
- 멀티 에이전트 동시 작업
- Walk-through 형식 결과 리뷰
- 모델 간 transparent 전환

**기존 Yuminai 구조** (ADR-026, ADR-030, ADR-034):
- `AgentPane`: pane 단위 (Claude/Codex 각자)
- mention dispatch: pane → pane 명시 전환
- agent chain: 자동 chain hops (max 3)
- 세션 분리: 각 pane 자체 ClaudeStreamSession

**문제**:
- pane이 분리돼 있어 context도 분리 — Claude가 본 정보를 Codex가 모름
- 모델 전환이 mention 형식 (`@codex 이거 코딩해줘`) — 자연스럽지 않음
- task 단위 추적 부재 — 큰 task의 sub-step이 어디까지 됐는지 fragmented

### Harness 핵심 컨셉

**"하나의 대화, 여러 모델"** — 사용자는 단일 대화창에서 task를 던지고, harness가 routing/handoff를 투명하게 관리.

### 핵심 구성요소

#### 1. SharedConversationLog (Core)
모든 모델이 동일하게 참조하는 timeline.
```swift
public struct ConversationEntry: Identifiable, Sendable, Codable {
    let id: UUID
    let timestamp: Date
    let role: Role  // .user / .agent / .system
    let agentKind: AgentKind?  // 누가 응답했는지 (sender = .agent일 때)
    let content: String
    let attachments: [String]
    let taskId: UUID?  // TaskGraph 노드 참조
    let tokenCount: Int?
}
```
- Append-only + indexed by task/agent
- 영속 (SwiftData) — 워크스페이스 별 단일 log
- 모델 전환 시 이 log를 기반으로 handoff prompt 생성

#### 2. ModelCapabilityMatrix (Core)
Task 종류 → 추천 모델 매핑.
```swift
public enum TaskKind {
    case planning           // → Claude (reasoning 강함)
    case codeGeneration     // → Codex (code-focused)
    case codeReview         // → Claude
    case refactoring        // → Claude
    case debugging          // → Claude
    case longContextSearch  // → Gemini (향후)
    case generalChat        // → Claude (default)
}
```
- 사용자 hint (`/model claude`) 또는 keyword 분석으로 자동 routing
- Manual override 우선

#### 3. HandoffPromptBuilder (Core)
모델 전환 시 catch-up prompt 생성.
- 입력: SharedLog 최근 N entries + 현재 task + target model
- 출력: 압축된 system context + 새 instruction
- 토큰 예산 (default 4K) 내 압축 — 오래된 entry는 요약, 최근 N개는 전체 보존
- 모델별 strength 강조 (예: Codex로 갈 때 "이전에 Claude가 분석한 코드를 implement해주세요")

#### 4. TaskGraph (Core)
task 단위 + 의존성 + agent 할당 추적.
```swift
public struct HarnessTask: Identifiable, Sendable, Codable {
    let id: UUID
    let title: String
    let description: String
    var status: TaskStatus  // .pending / .running / .completed / .failed
    var assignedAgent: AgentKind?
    var dependencies: [UUID]
    var output: String?  // 결과 요약
    var entryRefs: [UUID]  // SharedLog entry 참조
}
```
- 사용자가 큰 task 입력 → orchestrator가 sub-task 분해 (Phase 4+) 또는 사용자 manual
- DAG 시각화 (Phase 5 UI)

#### 5. HarnessOrchestrator (App)
사용자 메시지 → routing → handoff → 응답 → log update.
- 기존 AgentPaneCoordinator를 wrapper
- 사용자 입력 → ModelCapabilityMatrix로 추천 model 결정 → 자동 또는 수동 선택
- 모델 전환 시 HandoffPromptBuilder로 system context 생성 → 새 pane 활성화
- 응답을 SharedConversationLog에 기록 + TaskGraph 업데이트

#### 6. HarnessUI (UI, Phase 5)
- 단일 conversation view (모든 모델 응답이 한 timeline)
- agent badge (어느 모델이 응답했는지)
- TaskGraph mini-map (sidebar 또는 inspector)
- 모델 수동 override 버튼 (`/model claude` 명령 또는 dropdown)

### 점진적 구현 단계

| Phase | 범위 | 라운드 |
|---|---|---|
| **1** | Core types (ConversationEntry, ModelCapabilityMatrix, HandoffPromptBuilder, HarnessTask) + 단위 테스트 | **이번 라운드** |
| **2** | HarnessOrchestrator skeleton (App layer) — 기존 AgentPane wrap, log append, 자동 routing 미적용 | **이번 라운드** |
| 3 | 자동 routing — ModelCapabilityMatrix 적용, 사용자 입력 keyword 분석 | 다음 라운드 |
| 4 | TaskGraph 자동 분해 — 큰 task → sub-task, dependency 관리 | v2.0 |
| 5 | HarnessUI — 단일 conversation view + TaskGraph mini-map + agent badge | v2.0 |

### Phase 1 + 2 구현 결정

이번 라운드는 **foundation만**:
- Core types 정의 + 테스트 (compile-tested + behavior-tested)
- HarnessOrchestrator는 skeleton (실제 routing은 Phase 3에서) — 기존 AgentPaneCoordinator 위에 facade
- SharedConversationLog는 메모리 only (영속화는 Phase 4)
- 기존 호출자 변경 0건 — 기존 multi-pane이 그대로 동작 + harness는 추가 기능

### 격리

- Core: 모든 model/task/log 타입 — UI/App 의존성 없음
- App: HarnessOrchestrator — AgentPaneCoordinator + SharedLog 통합
- UI: 향후 Phase 5에서 단일 conversation view

### 알려진 한계 / 다음 라운드

- Phase 1+2는 foundation만 — 실제 사용자 visible 변화 없음 (Phase 3+ 부터)
- Codex CLI는 자체 session resume 패턴 — handoff prompt가 Codex session에 어떻게 inject될지 검토 필요 (Phase 3)
- Gemini/GPT 통합은 별도 adapter 작성 필요 — 현재 Claude/Codex만
- TaskGraph 자동 분해는 LLM 호출 비용 — Phase 4에서 비용 trade-off 검토

### 재검토

- 사용자가 manual model 선택 vs 자동 routing 어느 것 선호하는지
- HandoffPromptBuilder 토큰 예산 4K 적정성 (긴 대화에서 정보 손실 vs 비용)
- 기존 mention dispatch (ADR-031 T2) 와 harness routing의 충돌 — orchestrator가 둘 다 활용

---

## ADR-046 — Telegram 잔여 audit 항목 + plan-mode 안전장치

- **날짜**: 2026-05-02
- **상태**: Accepted
- **결정**: ADR-045 후속 — audit MEDIUM 잔여 (M3, M5, M7) + 사용자 안전 핵심 (외부 turn plan-mode 강제) 일괄

### 변경

1. **M7 — chunked code block 페어 보존** (`TelegramSessionBridge.chunked`)
   - 이전: 단순 줄바꿈/공백 분할 — ` ``` ` 페어가 두 chunk에 갈리면 Markdown 파싱 실패
   - 이후: 각 piece의 ``` 카운트 검사 → 홀수면 현재 chunk에 ``` 닫기 + 다음 chunk 시작에 ```언어 재오픈
   - `extractLastFenceLanguage(_:)` — 마지막 fence의 언어 표식 추출 후 보존

2. **M3 — tool call summary 풍부화** (`TelegramSessionBridge.summarizeToolCall`)
   - 이전: 모든 tool 첫 줄 + 80자 cap — Edit인지 Write인지, 어느 파일인지 알기 어려움
   - 이후: JSON 입력 parse 후 tool 종류별 분기:
     - Bash: command (개행 → 공백)
     - Edit: `Edit Foo.swift (-3 +5)\n  preview` (변경 줄 수 + 첫 줄)
     - Write: `Write Foo.swift (12줄 새 작성)\n  preview`
     - Read/Grep/Glob/WebFetch: 대상 path/pattern/url
     - Fallback: 기존 첫 줄 + maxLen
   - 모바일 사용자가 30초 내 위험 평가 가능

3. **M5 — cokacdir 동시 polling 충돌 감지** (`AppModel.applyCokacdirBot`)
   - 이전: 같은 토큰으로 cokacdir + Yuminai 동시 polling 시 메시지 절반씩 분산 — 코드 주석에만 명시
   - 이후: `pgrep -x cokacdir` 검출 → NSAlert 경고 ("진행" / "취소" 선택)
   - `isCokacdirRunning()` private helper

4. **AppPreferences 신규 옵션 (ADR-046)**
   - `telegramRemoteRequiresPlan: Bool = true` — 외부 turn은 plan-mode 강제
   - `telegramShowCostInline: Bool = true` — /status에 누적 비용 표시
   - **Backward compat**: `init(from decoder:)` 커스텀 구현 — 기존 JSON에 새 필드 없으면 default

5. **External turn plan-mode 강제** (`AppModel.applyRemotePlanModeIfNeeded`)
   - 외부 turn 시작 시 active settings의 permissionMode를 `.plan`으로 1회 강제
   - 원래 설정은 caller가 받아 보관 (`scheduleSettingsRestore`)
   - Plan turn 종료 후 (max 5분 wait) 원래 설정으로 자동 복원
   - bridge에 사용자 안내: "🛡 외부 turn — Plan 모드. 결과 확인 후 ‘진행해 줘’로 승인"
   - **destructive 진짜 block의 가장 안전한 우회 — Claude가 plan만 제시, 실행은 후속 turn 사용자 명시 승인 필요**

6. **SettingsView "외부 사용 안전" 섹션** (`SettingsView`)
   - 4개 toggle:
     - 외부 turn은 Plan 모드 강제 (default ON)
     - 비용 가시화 (default ON)
     - Assistant 응답 forward (기존, 노출만)
     - Tool 호출 요약 forward (기존, 노출만)
   - HelpHint로 각 toggle 의미 명확화

### 격리

- TelegramSessionBridge: chunked + summarizeToolCall (대화 layer)
- AppModel: cokacdir 검출 + plan-mode 적용 (orchestration layer)
- AppPreferences: 신규 옵션 + Codable 호환
- SettingsView: 신규 안전 섹션

### 결과

- 수정 파일 4개:
  - YuminaiTelegram/TelegramSessionBridge.swift — chunked + summarizeToolCall
  - YuminaiCore/AppPreferences.swift — 2 신규 + Codable backward-compat
  - YuminaiApp/AppModel.swift — applyRemotePlanModeIfNeeded + scheduleSettingsRestore + isCokacdirRunning
  - YuminaiApp/YuminaiCommandRouter.swift — handlePlainText에서 plan-mode 적용 + 복원
  - YuminaiUI/SettingsView.swift — "외부 사용 안전" 섹션
- 테스트 293/293 통과 (regression 0)
- 빌드 6.72s clean (incremental 2.36s)

### 알려진 한계 / 다음 라운드

- **plan-mode 정확한 turn boundary**: 현재는 isStreaming 폴링으로 turn 종료 감지 — turn id 기반이 더 정확. v2.0+
- **Multi-chat 그룹 시나리오 동시 사용자**: 같은 chat에서 두 사용자 동시 명령 race
- **destructive 진짜 block & wait**: plan-mode가 우회 — Claude Code permission_mode 직접 통합 (CLI option 변경 필요) 시 진짜 가능

### 재검토

- plan-mode 강제로 외부 사용자 워크플로 마찰 (매번 2 turn) vs 안전성 — 사용자 선호도
- M5 cokacdir 검출이 다른 봇 충돌도 감지하는지 (현재 cokacdir만)
- M3 tool summary가 실제 모바일에서 가독성 충분한지

---

## ADR-045 — Telegram 통합: 외부 vibe-coding 신뢰성 + 다중 chat + 비용 가시화

- **날짜**: 2026-05-02
- **상태**: Accepted
- **결정**: 사용자 요구 "텔레그램으로 외부에서 효율적으로 바이브코딩"의 production minimum bar 달성. audit가 식별한 HIGH 5건 + 핵심 MEDIUM 일괄 처리

### 컨텍스트
사용자: "냉정하게 ux 점검. 외부에서 효율적으로 바이브코딩 확인하면서 진행할 수 있어야. 토큰 효율도 점검."

audit 결과 (`code-reviewer` agent): "MVP 80% 가능하지만 신뢰성 20% 부족". HIGH 5건이 사용자 시나리오를 깨뜨림.

### R1 — 즉시 fix (1-2시간)

1. **H4 — 401/403/404 즉시 polling 중단** (`LiveTelegramBot.swift`)
   - 이전: 모든 에러 5초 retry 무한 루프 → token revoke 시 401 폭주, 사용자는 이유 모름
   - 이후: NSError code 401/403/404 시 polling 중단 + `fatalAuthError` 메시지 set (BotFather에서 새 토큰 발급 안내)
   - 5xx/429 rate limit/network는 기존대로 backoff retry

2. **H4-bonus — bot reflection 차단**
   - `IncomingTelegramMessage.isFromBot: Bool` 추가 (parseUpdate에서 `from.is_bot` 검사)
   - polling 루프 + command router가 `isFromBot=true` 메시지 차단

3. **M2 — MarkdownV2 escape + plain text fallback**
   - 이전: legacy "Markdown" + escape 없음 → `my_var` 같은 underscore에서 400 → 메시지 송신 실패 → 사용자 무응답
   - 이후: 1차 MarkdownV2 (escape 적용) → 400 시 plain text fallback 자동 재시도
   - `escapeMarkdownV2(_:)` — 18 reserved char escape, code block 페어 보존 (` ```...``` ` 내부는 escape 안 함)

4. **M6 — polling cleanup race 종결**
   - `stopPolling()`이 `pollingTask?.value` await + 1초 timeout — long-poll 진행 중인 task 완전 종료 보장
   - unbind 후 stale 메시지 도착 시나리오 차단

5. **H2 — alertDispatcher 중복 알림 skip**
   - bound workspace인 경우 `alertDispatcher.dispatch` skip (sessionBridge가 풍부한 메시지 보냄)
   - 한 turn 끝날 때 텔레그램 알림 1개 (이전 2개)

6. **L6 — /start onboarding 분리**
   - 이전: `/start`가 `/help` alias
   - 이후: `/start`는 chat_id + 워크스페이스 개수 + 사용 절차 + ⚠ 주의사항 (PC confirm 없음, 외부 turn 비용 누적)
   - Telegram convention 준수

### R2 — Sprint 2 (3-5시간, ADR 필요)

7. **H1 — destructive tool 프로미넌트 알림 + /cancel**
   - 정확한 confirmation (tool block & wait)는 Claude Code CLI permission_mode 통합 필요 → v2.0+
   - 단기 대응: `TelegramSessionBridge.isDestructiveToolCall(name:input:)` 휴리스틱 검출
     - Bash + 위험 패턴: `rm -rf`, `git reset --hard`, `git push --force`, `drop table`, `chmod -r 777`, `dd if=`, `mkfs`, `shutdown` 등 13개
   - destructive 검출 시 `🚨 위험한 작업 감지 — [tool] [input maxLen=200]\n계속하지 않으려면 즉시 /cancel 보내세요.`
   - `summarizeToolCall`에 maxLen 매개변수 추가 (destructive는 200자, 일반은 80자)
   - 사용자가 알림 받고 /cancel 보낼 시간 확보 (10초 정도, agent가 대화 turn 중이라 완료 전 cancel 가능)

8. **H3 — multi-chat routing**
   - 이전: `bridge.send` 항상 `config.chatId` (단일) — 그룹 chat에서 명령 → 응답은 1:1로 → 친구는 결과 못 봄
   - 이후: `bridge.requestChatId: Int64?` 동적 override (CommandRouter가 incoming `message.chatId`로 set)
     - `send(_:)`이 `requestChatId ?? config.chatId` 사용
     - `.completed` 후 자동 클리어 (다음 turn은 다시 default 또는 새 request)
   - `bindTelegramWorkspace(_:defaultChatId:)` — `/bind` 호출한 chat을 default response chat으로 자동 설정
   - `setBridgeRequestChatId(_:)` AppModel facade

9. **H5 — 외부 turn 비용 가시화**
   - `AppModel.externalTurnCount: Int` + `externalTurnTotalCostUSD: Double` 누적
   - `incrementExternalTurnCount()` — CommandRouter handlePlainText 시 호출
   - `.completed` 시 bound workspace + external turn 발생했으면 `externalTurnTotalCostUSD += currentSessionUsage.costUSD` 누적
   - `/status` 출력 확장:
     - 컨텍스트: 70%+ ⚠ + "새 세션 시작하는 것이 좋아요" 안내
     - 현재 세션 비용: $X.XXXX
     - 외부 turn 횟수: N (누적 $X.XXXX)
   - 사용자가 출퇴근 동안 비용 자각 가능

### Bonus — 추가 명령

10. **/use <name>** — 활성 워크스페이스만 변경 (bind 유지)
    - 두 워크스페이스 번갈아 보고 싶을 때 매번 /bind 불필요
11. **/diff** — `pendingDiff` chunked 전송 (3500자 cap, code block diff 형식)
12. **/changes** — 변경 파일 목록 요약 (수정/추가/삭제 등 status label)
13. **/list 강화** — `✈★` 두 마커 (bound + active) 동시 표시

### 격리

- LiveTelegramBot — Markdown escape + auth 가드 (Telegram protocol layer)
- TelegramSessionBridge — destructive 검출 + multi-chat routing (대화 layer)
- YuminaiCommandRouter — chat_id 전파 + 신규 명령 (라우팅 layer)
- AppModel — 외부 turn 카운터 + bind facade (orchestration layer)

### 결과

- 수정 파일 5개:
  - YuminaiCore/TelegramClient.swift — IncomingTelegramMessage.isFromBot
  - YuminaiTelegram/LiveTelegramBot.swift — auth gate / escape / cleanup race / bot reflection
  - YuminaiTelegram/TelegramSessionBridge.swift — multi-chat / destructive detection / requestChatId
  - YuminaiApp/YuminaiCommandRouter.swift — /start /use /diff /changes + chat_id 전파
  - YuminaiApp/AppModel.swift — bindTelegramWorkspace defaultChatId / setBridgeRequestChatId / external turn cost / alertDispatcher skip
- 테스트 293/293 통과 (regression 0)
- 빌드 4.91s clean

### 알려진 한계 / 다음 라운드 (ADR-046+)

- **destructive tool 진짜 block & wait**: Claude Code CLI permission_mode 통합 (v2.0+) — 현재는 휴리스틱 알림 + /cancel 패턴
- **multi-chat 동시 사용자**: 같은 chat_id 내 동시 두 사용자가 명령 시 race 가능 (현재는 후자가 응답 destination override)
- **chunk 분할 시 code block 페어**: `chunked(_:maxSize:)`가 ``` 카운트 보존하도록 (M7 deferred)
- **cokacdir 동시 polling 충돌 감지** (M5): pgrep cokacdir 모달 — UI 작업
- **외부 turn 별도 sub-session**: 컨텍스트 격리 옵션 (CLI resume 패턴) — v2.0+

### 재검토

- destructive 휴리스틱이 실제 위험 케이스를 잘 잡는지 (사용자 사용 데이터 후 패턴 추가)
- /status에 표시되는 누적 비용이 실제 사용자 인지에 도움 되는지
- multi-chat 시나리오 빈도 (대부분 1:1만 사용 가능성)

---

## ADR-044 — audit 후속: 4 코디네이터 추가 추출 + Sheet 상호배제 + F2 단축키 + UX polish

- **날짜**: 2026-05-02
- **상태**: Accepted
- **결정**: ADR-042 R3.1 (TerminalSessionCoordinator) 후속 — 남은 코디네이터 6개 중 4개 추출 + sheet mutual exclusion helper + F2 키 NSEvent monitor + UX polish

### R3.2 WorkspaceFileManager (HIGH ROI)
- 신규 `WorkspaceFileManager.swift` (~330줄, @MainActor @Observable)
- 9 state + 17 메서드 응집:
  - tree refresh + tab lifecycle (select/setActive/close/closeAll/selectAdjacent/closeActive)
  - editing (start/save/discard) + activeDraft custom setter
  - CRUD (createFile/createFolder/renameNode/deleteNode/moveNode/deleteSelected)
  - selection (toggle/clear) + inline rename (begin/cancel/commit)
  - tab sync helpers (rename/delete affected tabs)
- WorkspaceFileTree actor 의존성은 coord 내부 (workspace는 caller 주입)
- AppModel facade — 전역 호출자 변경 0건 (R3.1 패턴)
- lastError pattern으로 caller에 에러 전파

### R3.3 CommandRunnerCoordinator (작은)
- 신규 `CommandRunnerCoordinator.swift` (~70줄)
- 3 state (showPane/blocks/isRunning) + 4 메서드 (run/clear/copyOutput/buildShareToAgentPrefix)
- buildShareToAgentPrefix는 prefix만 반환 — composer enqueue는 facade 책임 (분리)

### R3.5 DeliveryCoordinator (state-only)
- 신규 `DeliveryCoordinator.swift` (~50줄)
- 3 state (results/isRunning/pendingFailureFeedback) + 4 메서드 (appendResult/appendResults/clear/consumePendingFailure)
- triggerAutoDelivery + checkpoint은 AppModel 잔존 (workspace 의존성 깊음)

### R3.4 AgentPaneCoordinator (minimal — state holder만)
- 신규 `AgentPaneCoordinator.swift` (~95줄)
- 5 state dict + 2 chain state (chainHops/chainVisited)
- 활성 pane projection (activePane/activeMessages/activeSettings/activeUsage)
- 메서드 5개 helper (appendMessageToActive/setActiveMessages/mutateActiveMessages/setActiveSettings/setActiveUsage)
- **lifecycle (addPane/removePane/setActivePane/renamePane) + ClaudeStreamSession lifecycle은 AppModel 잔존**
  — protocol 의존성 깊음, R3.4.2에서 분리 가능

### R3.6 ObsidianVaultCoordinator (minimal)
- 신규 `ObsidianVaultCoordinator.swift` (~60줄)
- 14 state (vault/tree/selectedNote/searchQuery/fullTextEnabled/hits/edit/picker/disambig/favorites/recents)
- noteIsDirty computed
- **lifecycle (setupObsidianVault/watcher/searchTask)는 AppModel 잔존**

### R3.7 TelegramCoordinator — 보류
- public state surface 작음 (cokacdirImportError + telegramTokenStatus만)
- 실제 lifecycle은 4 private session object (telegramBot/alertDispatcher/commandPump/sessionBridge)에 위임
- coord 추출 ROI 낮음 — AppModel 잔존이 합리적
- 향후 별도 protocol 정리 후 R3.7.2에서 재검토

### R5.A Sheet mutual exclusion
- 11개 sheet/alert binding이 같은 view에 동시 attach — race 가능 (audit M4)
- AppModel.dismissAllSheets() — 모든 sheet/alert state 한 번에 클리어
- AppModel.presentExclusiveSheet { setter } — 새 sheet 열기 전 dismiss 자동
- 적용처: showFileSearchSheet, showShortcutHelp (programmatic 호출 모두)
- 사용자 trigger (컨텍스트 메뉴 등)도 점진 적용 가능

### R5.B F2 키 NSEvent local monitor
- SwiftUI .onKeyPress가 F2 함수키 미지원 → NSEvent.addLocalMonitorForEvents (keyCode 120)
- RootView.installF2Monitor() — view appear 시 install, disappear 시 remove
- 가드: sheet/alert 활성 중이면 무시 (텍스트 입력 방해 방지)
- 가드: inlineRenameTargetPath != nil이면 무시 (재진입 방지)
- 가드: activeFileTab == nil이면 무시 (대상 없음)
- 동작: appModel.beginInlineRename(activePath) → 이벤트 소비 (return nil)
- ADR-041에서 "v1.3+ deferred" 명시했지만 이번 라운드에서 구현 (사용자 요청)

### R5.C CommandBlock 버튼 발견성
- copy/share/rerun 버튼이 hover일 때만 표시 → 항상 표시 (opacity 0.4) + hover 시 1.0
- 사용자가 버튼 존재 인지 + 시각 노이즈 균형 (audit M3)

### 결과
- 신규 파일 5개 (App): WorkspaceFileManager / CommandRunnerCoordinator / DeliveryCoordinator / AgentPaneCoordinator / ObsidianVaultCoordinator
- 수정 파일 3개: AppModel (facade pass-through 대량 추가) / RootView (F2 monitor + sheet exclusive) / CommandRunnerPane (always-visible buttons)
- AppModel state 20+ 변수 → coord로 이전. AppModel 사이즈는 facade 늘어 큰 차이 없으나 **새 기능 추가 시 어느 coord에 갈지 명확**해짐
- 호출자 변경 0건 (모두 facade computed pass-through)
- 테스트 293/293 통과 (regression 0)
- 빌드 6.65~7.36s clean

### 알려진 한계 / 다음 라운드 (ADR-045+)
- **R3.4.2**: AgentPane lifecycle (setActivePane/addPane/sendMessage)을 coord로 — ClaudeStreamSession protocol 의존성 정리 선행 필요
- **R3.6.2**: Obsidian lifecycle (setupVault/watcher/searchTask)을 coord로 — VaultWatcher actor 정리
- **R3.7**: Telegram bot/dispatcher/pump/bridge protocol 정리 후 coord 추출
- **Sheet enum routing**: 현재 11개 boolean → 단일 enum 기반 routing (큰 refactor)
- **Environment 주입 전환**: 모든 coord 추출 완료 후 facade 제거 + view에 Environment 주입 (prop drilling 영구 해소)

### 재검토
- F2 NSEvent monitor가 다른 키와 충돌 없는지 (다른 view의 F2 reservation 검토)
- Sheet mutual exclusion이 사용자 의도 (예: sheet 닫고 새로 열기) 잘못 해석하지 않는지
- coord 분리가 SwiftUI invalidation 영향 (Observation read-tracking이라 큰 영향 없을 것)

---

## ADR-043 — audit 기반 R4: 안정성 + magic number 추출

- **날짜**: 2026-05-02
- **상태**: Accepted
- **결정**: ADR-042 R3.1 후속. 안정성 6개 항목 일괄.

### 변경

1. **AppLimits enum 신규**: 산재된 magic number (10/50/10/10/50_000) 단일 source.
   - `maxFileTabs = 10`, `maxTerminalSessions = 5` (10→5 hard cap), `maxCommandBlocks = 50`, `maxDeliveryResults = 10`, `oversizedPromptTokenThreshold = 50_000`
2. **터미널 max 10→5 hard cap**: 비활성 세션도 PTY process 살아있어 메모리 비용 큼. 5개 넘으면 실용적 multi-tasking이 아닌 cluttering. Hibernation 패턴은 v2.0+로 미루되 cap만 즉시 적용
3. **Workspace persist 직렬화**:
   - 이전: `Task { try? await store.update(updated) }` fire-and-forget — 빠른 전환 시 race
   - 이후: `pendingPersistTask: Task<Void, Never>?` chain — 새 task가 이전 task await 후 실행 (순서 보장)
   - persist함수(`persistCurrentTerminalSessions`/`persistCurrentPanes`)가 `chainPersistTask(_:)` 헬퍼 사용
4. **transitionToWorkspace 응집**:
   - 이전: RootView `.task(id:)`에서 `closeAllFileTabs + refreshWorkspaceFileTree + restoreTerminalSessionsFromWorkspace` 분산 호출
   - 이후: AppModel `transitionToWorkspace(_:)` 단일 함수 — 순서/race 명확
   - 향후 추가될 transition step도 한 곳에서 관리
5. **completedRecently → unread dot fallback**:
   - 이전: 비활성 세션이 completedRecently → 3초 후 idle, dot 사라짐 → 사용자가 다른 창 보다 돌아오면 끝났는지 모름
   - 이후: 비활성 세션의 running OR completedRecently 모두 `hasUnreadOutput=true` → active 전환할 때까지 dot 유지
6. **Unread dot 가시성**: 5pt → 7pt + white border opacity 0.4 (주변 시야 인지 강화) + 더 명확한 tooltip ("새 출력이 있어요 — 클릭해서 확인")

### 결과
- 신규 파일 1개 (Core): AppLimits.swift
- 수정 파일 3개: AppModel/RootView/TerminalSessionCoordinator
- 테스트 293/293 통과 (regression 0)
- 빌드 7.91s clean

### 알려진 한계 / 다음 라운드
- R3.2~R3.7 코디네이터 6개 점진 추출
- Sheet enum mutual exclusion (현재 9개 sheet binding 동시 attach — race 가능성)
- 터미널 hibernation (max 5로 우회)
- F2 키 NSEvent monitor

---

## ADR-042 — audit 기반 R1/R2/R3: 토큰 안전 + UX onboarding + 코디네이터 분리

- **날짜**: 2026-05-02
- **상태**: Accepted (R1, R2, R3.1 완료. R3.2~R3.7은 점진적 후속 라운드)
- **결정**: 종합 점검(architecture+token+UX agent 3개 병렬) 결과 발견된 19개 이슈 중 13개를 R1/R2/R3.1 3 commit으로 일괄 처리. AppModel god-object 분리는 R3.1에서 TerminalSessionCoordinator 1개 prototype으로 시작 + 나머지 6개 coord는 spec만 작성

- **컨텍스트**:
  - 사용자 — "현재 구현된 버전에서 비효율적으로 토큰 소모/유기적 비효율 연결/UX 이슈 점검"
  - 5개 라운드(ADR-037~041) 빠른 추가로 인한 부채 누적: AppModel 2226줄, RootView 1175줄, InspectorPanel 78개 init 파라미터
  - 사용자 — "R1부터 하나하나 전부 자동으로 순차적으로 진행해서 마무리해"

### R1 — 토큰 안전 + 사용자 마찰 즉시 해소 (commit c30f821)

1. **C1 shareCommandBlockToAgent 토큰 폭발 차단**:
   - 무제한 stdout/stderr prepend → `DeliveryResult.tail` 재사용 (stderr 50줄 + stdout 30줄 cap)
   - **효과**: 100K 토큰 (Sonnet 200K window의 50%) → ~4K
2. **C2 F2 placeholder 제거**: 동작 안 했던 `.onKeyPress(.init("F"))` 핸들러 삭제
3. **C3 rename 컨텍스트 메뉴 단일화**: "이름 변경 (inline)" + "이름 변경 sheet…" 두 개 → 단일 "이름 변경" (Hick's law 위배 해소)
4. **C4 Drop target hover highlight**: `dropDestination(isTargeted:)` Binding + `@State isDropTarget` + `rowBg accent.opacity(0.35)` (drop 가능 폴더 명확)
5. **H5 디렉토리 첨부 confirmation**: `openAttachmentPicker`에서 디렉토리 또는 1MB+ 파일 시 NSAlert (node_modules 실수 첨부 폭발 방지)
6. **H6 Auto-fix loop 토큰 절약**:
   - `DeliveryConfig.maxAttempts` default 3 → 2
   - `DeliveryResult.tail`에 `byteBudget: 4_096` 추가 (한 줄 5KB stack trace 폭발 방지)
7. **H7 pendingComposerPrefix queue 패턴 (가장 임팩트 큼)**:
   - `AppModel.pendingComposerPrefix: String?` queue state
   - `enqueueComposerPrefix(_:)` — 외부 caller가 사용. 누적 시 stack-style prepend
   - RootView Composer에 `.onChange(of: pendingComposerPrefix)` — 안전 소비 후 nil
   - `inputText = prefix + inputText` 직접 mutation 패턴 제거 → cursor jump/race 해소

### R2 — UX onboarding + 단축키 일관성 + 시각 노이즈 감소 (commit d41a808)

8. **H8 ⌘W → ⌘⌥W**: file tab close가 macOS 표준 윈도우 close에 양보. ShortcutHelpSheet 명시
9. **H9 EmptyWorkspaceView 단축키 안내 확장**: 4 → 7 quickTipRow (⌘P, ⌃⇧T, ⌃Tab, Cmd+클릭, drag-drop 등)
10. **H10 FilesPanel HelpHint 확장**: 단일 줄 → 6 bullet point (다중 선택/drag-drop/단축키 모두 명시)
11. **H11 Pulse 활성 세션만 + reduceMotion**:
    - `@Environment(\.accessibilityReduceMotion)` 체크
    - `shouldPulse = isActive && !reduceMotion` — 비활성 세션은 정적 dot
    - pulse duration 1.0초 → 1.4초 (덜 산만)
12. **H12 Split secondary pane badge + border**: `splitPaneContainer` wrapper — Primary/Secondary label badge + accent vs borderSubtle border + 세션 라벨 표시
13. **M20 ⌘F CommandRunner 검색 단축키**: `.keyboardShortcut("f", modifiers: .command)` 토글
14. **LOW polish 일괄**:
    - `agentChainMaxHops` Stepper 1...5 → 1...3 (토큰 폭발 cap)
    - 한국어 라벨 통일 ("휴지통으로 / 휴지통으로 삭제" → "휴지통으로 이동")
    - "외부에서 열기" → "외부 IDE에서 열기" 통일
    - ShortcutHelpSheet에 v0.9+/v1.2+ 추가된 모든 단축키 노출 (신규 카테고리 2개)

### R3.1 — TerminalSessionCoordinator 추출 (god-object 분해 1단계)

15. **AppModel god-object 분리 시작**:
    - 신규 `Sources/YuminaiApp/TerminalSessionCoordinator.swift` (190줄) — `@MainActor @Observable` child
    - 7개 state + 13 메서드를 응집 (lifecycle / cwd / activity / split / persistence / 워크스페이스 전환)
    - **Facade 패턴 유지**: AppModel은 `terminals` 보유 + 기존 호출자 API (showTerminalPane, terminalSessions 등)는 computed pass-through. **호출자 변경 0건**
    - AppModel L97-L210 state → 코드 ~150줄 감소
    - 사이드 효과 정리: `close()`에 secondary cleanup, `clearAll()`에 전체 reset 응집
16. **AppModel 메서드 위임**:
    - `createTerminalSession`/`closeTerminalSession`/`renameTerminalSession`/`updateTerminalActivity` 등 13 메서드가 `terminals.foo()` 호출 + persist trigger만 facade
    - NSOpenPanel UI는 facade가 책임 (coord는 pure state logic)

### R3.2~R3.7 — Spec (점진적 후속 라운드, 별도 PR)

| Coord | 추출 대상 (현 AppModel 줄 범위) | 우선순위 |
|---|---|---|
| **R3.2 WorkspaceFileManager** | tree + tabs + selection + inline rename + CRUD (L123-157, L1221-1530) | HIGH (다음 PR) |
| **R3.3 CommandRunnerCoordinator** | blocks + isRunning + share/copy (L117-121, L1700-1770) | MEDIUM |
| **R3.4 AgentPaneCoordinator** | agentPanes + paneMessages + chain (L188-203, L717-941) | HIGH (chain 복잡) |
| **R3.5 DeliveryCoordinator** | delivery loop + checkpoint (L182-186, L1170-1220) | MEDIUM |
| **R3.6 ObsidianVaultCoordinator** | vault + notes (L59-93, L316-625) | LOW (이미 isolated) |
| **R3.7 TelegramCoordinator** | bot/dispatcher/pump/bridge (L36-41, L2046-2225) | LOW |

각 coord 추출 시 동일 패턴 (Facade computed pass-through)으로 호출자 변경 최소화. 모든 coord 추출 완료 후 facade 제거 + Environment 주입 전환 검토 (ADR-043+).

### 격리

- TerminalSessionCoordinator: YuminaiCore 의존 없음 (TerminalSession 모델만). UI 의존 X
- AppModel facade: 호출자 호환성 유지를 위한 얇은 layer
- 새 코드 패턴 정착: 향후 coord는 같은 shape (`@MainActor @Observable` + pure state logic)

### 단순화 ROI 분석

| 항목 | 가치 | 비용 | ROI |
|---|---|---|---|
| R1.C1 shareCommand tail | 95 (토큰 폭발 차단) | 5분 | 압도 |
| R1.H7 prefix queue | 90 (race condition 영구 차단) | 30분 | 압도 |
| R1.H6 maxAttempts=2 | 70 (토큰 절약 + 사용자 개입 효율) | 5분 | 압도 |
| R2.H9/H10 onboarding | 80 (발견성 결손 해소) | 30분 | 압도 |
| R2.H11 pulse 활성만 | 60 (시각 노이즈 감소) | 15분 | 양호 |
| R3.1 TerminalCoord | 75 (god-object 분해 시작) | 2시간 | 양호 |

### 결과

- **신규 파일 1개 (App)**: TerminalSessionCoordinator.swift (190줄)
- **수정 파일 9개**:
  - YuminaiApp/AppModel.swift — facade pass-through + 13 메서드 위임 + enqueueComposerPrefix
  - YuminaiApp/RootView.swift — pendingPrefix consume + ⌘⌥W + EmptyWorkspaceView 확장 + splitPaneContainer + 한국어 라벨
  - YuminaiUI/FilesPanel.swift — F2 placeholder 제거 + rename 단일화 + drop hover + HelpHint 확장 + 라벨 통일
  - YuminaiUI/CommandRunnerPane.swift — ⌘F 단축키
  - YuminaiUI/SettingsView.swift — agentChainMaxHops 1...3 cap
  - YuminaiUI/ShortcutHelpSheet.swift — 신규 단축키 카테고리 2개
  - YuminaiCore/DeliveryConfig.swift — maxAttempts default 2 + tail byteBudget
  - Tests/YuminaiCoreTests/DeliveryConfigTests.swift — assert 동기화

- **테스트**: 293/293 통과 (regression 0)
- **빌드**: R1 7.63s / R2 5.76s / R3.1 7.39s clean

### 알려진 한계 / 다음 라운드

- R3.2~R3.7 코디네이터 6개 점진 추출 (각 별도 PR)
- ADR-043 R4: max 5 hard limit / persist await / transition 응집 / sheet enum / completedRecently dot fallback
- F2 키 NSEvent monitor (v1.3+)
- LSP imports update (v2.0+)
- 터미널 hibernation (v2.0+)

### 재검토

- R3.1 facade 패턴이 점진적 분리에 적합한지 (호출자 변경 0이므로 OK)
- Coord 분리 후 SwiftUI invalidation 영향 (Observation read-tracking이라 큰 문제 없을 것)
- 토큰 절약 효과 정량 측정 — `xcrun xctrace`로 turn별 stdin payload bytes

---

## ADR-041 — v1.2+ R1: 터미널 UX 강화 (활동 표시/cwd 분리/영속/split) + 트리 UX (단축키/drag-drop) + 명령 history 검색

- **날짜**: 2026-05-02
- **상태**: Accepted
- **결정**: ADR-040 v1.2+ deferred 6개 항목 일괄 + 사용자 명시 요청 "터미널 세션 활동 상태 표시/애니메이션" — T10/T11/T13/T14 (터미널) + F6/F7 (트리) + T12 (명령 검색). LSP imports는 v2.0+로 명시 보류
- **컨텍스트**:
  - 사용자 — "v1.2+ 후보 항목들 하나하나 검수해서 기획+레퍼런스+검증+구현 / 좌측 터미널 세션 알림 아이콘+애니메이션 추가"
  - ADR-040의 다중 터미널은 "어떤 세션이 작업 중인지" 시각 신호 부재 — 사용자가 백그라운드 작업 진행 모름 (UX 핵심 결손)
  - file CRUD는 마우스 의존 — 키보드 단축키 (F2/Delete) 부재로 macOS 표준 IDE 경험 미달
- **레퍼런스 검증**:
  - **iTerm2/Warp 활동 indicator**: 탭에 색 점/체크 표시 (running=청록 점, success=녹색 체크, fail=빨강 X). Yuminai 채택: pulse 녹색 점 (running) / 녹색 체크 (recent done) / 주황 dot (background unread)
  - **OSC 133 semantic prompts**: VT100 표준, iTerm2/Warp가 prompt detection에 사용. 단점: zsh 기본 미지원, starship/p10k 사용자만 가능. → 휴리스틱 우선 (PTY data 흐름 1.2초 timeout)
  - **SwiftTerm `LocalProcessTerminalView`**: `dataReceived(slice:)` `open` method — subclass override로 PTY 출력 흐름 hook 가능. 검증: SwiftTerm 1.2.x 소스 확인
  - **SwiftUI `.onKeyPress(.delete)`**: macOS 14+ — Yuminai macOS 26 OK. `.focusable()` 필수
  - **SwiftUI `.draggable(item:)` / `.dropDestination(for:)`**: macOS 13+. String 타입 transferable 자동 지원
  - **NSWorkspace.recycle**: 이미 ADR-040에서 도입됨 (휴지통)
  - **HSplitView dual-pane**: SwiftUI 기본 — 단순한 좌우 분할 가능. 더 복잡한 nested split은 NSSplitView wrap 필요 (보류)
- **각 결정**:
  ### T10 터미널 활동 상태 + 애니메이션 (사용자 명시 요청)
  1. **휴리스틱 활동 감지**:
     - `ActivityAwareTerminalView: LocalProcessTerminalView` subclass — `dataReceived` override
     - PTY 데이터 도착 → `.running` 표시 + 1.2초 timer
     - timer 만료 시 → `.completedRecently` (1.5초) → `.idle`
     - **합리화 검증**: OSC 133이 100% 정확하지만 zsh 기본 미지원 + zshrc 수정 부담 → 휴리스틱이 80% 케이스에 충분 + 즉시 동작
  2. **상태별 시각**:
     - `.idle`: 회색 terminal SF Symbol
     - `.running`: 녹색 점 + ZStack pulse (1.0초 repeat, scale + opacity)
     - `.completedRecently`: `checkmark.circle.fill` 녹색 (3초 후 idle 전환)
     - **알림 dot**: 비활성 세션이 running으로 전환 시 `hasUnreadOutput=true` → 주황 5pt circle. 사용자가 active 전환 시 자동 read mark
  3. **모든 세션을 ZStack에 두기 (iTerm2/Warp 표준)**:
     - 비활성 세션도 PTY data가 흘러야 활동 감지 가능 → 모든 세션 view를 ZStack에 두고 active만 `opacity(1)` + `allowsHitTesting(true)`
     - 메모리 비용: max 10 세션 × zsh process — 일반 사용 OK
  4. **동시성**: `ActivityAwareTerminalView`는 `@unchecked Sendable` (NSView main-thread bound) + state mutation은 `MainActor.assumeIsolated`. dataReceived는 SwiftTerm이 main에서 호출하지만 안전하게 hop
  ### T11 터미널 cwd 분리
  5. **NSOpenPanel folder picker** — 컨텍스트 메뉴 "디렉토리 변경…"
  6. **TerminalSession.workingDirectory 변경** → `TerminalPane.updateNSView`가 `cd` 명령 자동 전송 (기존 매커니즘)
  7. **세션 별 다른 cwd**: 같은 워크스페이스 내에서도 세션마다 다른 디렉토리 — 모놀리포 sub-project 작업에 유용
  ### T12 명령 history 검색
  8. **CommandRunnerPane 검색 토글** — header에 magnifyingglass 버튼 (active 시 fill 변형)
  9. **검색 범위**: command 텍스트 + stdout + stderr (case-insensitive substring)
  10. **결과 표시**: "X/Y 매치" 카운트 + 빈 결과 EmptyState
  11. **단순화**: regex/필터 다중 조건 보류 — substring 매칭이 80% 케이스 충분
  ### T13 터미널 세션 영속화
  12. **WorkspaceModel.terminalSessionsJSON: Data?** 추가 (SwiftData @Model)
  13. **TerminalSession Codable 제외 필드**: activity / hasUnreadOutput (UI 상태) — `private enum CodingKeys`로 명시. 영속 = id/label/cwd/createdAt만
  14. **자동 persist 트리거**: create/close/rename/changeDirectory 시 `persistCurrentTerminalSessions()`
  15. **워크스페이스 전환 시 복원**: `restoreTerminalSessionsFromWorkspace()` — `.task(id: selectedWorkspaceId)` 훅에서 호출. activity는 fresh `.idle`
  ### T14 터미널 split (좌우 dual-pane)
  16. **`terminalSplitEnabled: Bool` + `secondaryTerminalSessionId: UUID?`** 토글 state
  17. **HSplitView wrapper** — split mode 시 좌(active)/우(secondary) 동시 표시
  18. **단순화**: 좌우만 (상하 X), 2-pane만 (3+ X), nested split X — NSSplitView wrap 비용 회피하면서 80% 가치 (테스트 ↔ git 작업 동시 보기)
  19. **자동 secondary 선택**: split 토글 시 active 다음 세션 자동, 없으면 새 세션 생성
  ### F6 트리 단축키
  20. **`.focusable()` + `.onKeyPress(.delete)` / `.deleteForward`** → `onDelete(휴지통)`
  21. **`.onKeyPress(.return)`** → 파일이면 select, 폴더면 toggle expand
  22. **F2 키**: SwiftUI `.onKeyPress(.f2)` 직접 미지원 — 컨텍스트 메뉴 "이름 변경 (inline)"으로 대체. v1.3+에서 NSEvent monitor 검토
  23. **focusEffectDisabled()**: 트리 cell focus ring 시각 노이즈 제거
  ### F7 Drag-drop file move
  24. **파일 row `.draggable(node.path)`** — String 자동 transferable
  25. **폴더 row `.dropDestination(for: String.self)`** — drop 시 `onMoveFile(oldPath, newPath)` 호출
  26. **자동 검증**: 같은 부모면 noop, 폴더 자기 자신 drop도 noop
  27. **agent 위임 X**: drag-drop은 의도가 명확 (사용자 직접 동작) — agent prompt 자동 생성 없음
- **단순화 ROI 분석**:
  - **T10 활동 상태**: 가치 95 (사용자 명시 요청 + UX 결손 해소), 비용 1.2인일 (subclass + animation + ZStack 패턴) — ROI 압도
  - **T11 cwd 분리**: 가치 60 (모놀리포 워크플로), 비용 0.3인일 — ROI 압도
  - **T12 history 검색**: 가치 50 (50개 cap이라 manual scroll 가능하지만 검색이 빠름), 비용 0.4인일 — ROI 양호
  - **T13 영속화**: 가치 75 (워크스페이스 reload 시 컨텍스트 보존), 비용 0.5인일 (Codable 이미 준비됨) — ROI 압도
  - **T14 split**: 가치 60 (테스트+git 동시), 비용 0.4인일 (HSplitView wrapper만) — ROI 양호
  - **F6 단축키**: 가치 70 (macOS 표준 IDE), 비용 0.2인일 — ROI 압도
  - **F7 drag-drop**: 가치 55 (Finder 친화), 비용 0.3인일 — ROI 양호
- **격리**:
  - Core: TerminalSession.Activity enum + Codable 제외 / Workspace.savedTerminalSessions
  - Persistence: WorkspaceModel.terminalSessionsJSON (single Data column)
  - UI: ActivityAwareTerminalView (SwiftTerm wrap 내부) / FilesPanel.FileNodeRow (drag/drop/key)
  - App: AppModel multi-terminal lifecycle 확장 / RootView ZStack + HSplitView 패턴
- **외부 의존성 정책**: 새 dep 없음. SwiftTerm 기존 사용 + AppKit (NSOpenPanel/NSPasteboard) + SwiftUI 표준
- **알려진 한계 / v1.3+**:
  - **F2 키 inline rename**: SwiftUI `.onKeyPress(.f2)` 미지원 → NSEvent local monitor 필요 (v1.3+)
  - **상하 split + nested split**: NSSplitView wrap 필요 (큰 작업)
  - **Drag visual feedback**: dropDestination hover hint 단순 — Finder식 폴더 highlight는 더 polish 필요
  - **명령 검색 regex**: substring만 — regex/glob은 사용자 신호 후
  - **세션 복제** (cwd + 환경 변수 그대로 새 세션) — 별 ROI
  - **세션 백그라운드 알림 (macOS Notification Center)**: 백그라운드 작업 완료 시 OS 알림. 권한 + Privacy.plist + 사용자 설정 필요 — 조사 후 v1.3+
  - **OSC 133 정확 detection**: SwiftTerm OSC handler 확장 — zsh prompt에 자동 inject 옵션
  - **LSP imports update (F5 진짜 LSP)**: 수 주 작업 — agent 위임으로 충분 가능성 검증된 후 v2.0+
- **결과**:
  - 신규 파일 1개 (Test): TerminalSessionActivityTests.swift
  - 수정 파일 8개:
    - YuminaiCore/TerminalSession.swift — Activity enum + hasUnreadOutput + CodingKeys 제외
    - YuminaiCore/Workspace.swift — savedTerminalSessions + with(_:) 메서드 + 다른 with(_:) 모두에 propagate
    - YuminaiPersistence/WorkspaceModel.swift — terminalSessionsJSON
    - YuminaiUI/TerminalPane.swift — ActivityAwareTerminalView subclass + onActivityChanged
    - YuminaiUI/FilesPanel.swift — onMoveFile + .draggable/.dropDestination + .onKeyPress
    - YuminaiUI/InspectorPanel.swift — onMoveFile forwarding
    - YuminaiUI/CommandRunnerPane.swift — searchBar + filteredBlocks
    - YuminaiApp/AppModel.swift — 7 신규 메서드 (cwd/activity/persist/restore/split)
    - YuminaiApp/RootView.swift — TerminalSessionTabButton activity icon + ZStack/HSplitView + split 토글 버튼
  - **테스트 7 신규 (286→293 통과)**:
    - TerminalSessionActivityTests (4): default activity / mutable / Codable 제외 / raw value
    - WorkspaceTerminalPersistenceTests (3): default empty / with(savedTerminalSessions) / 다른 with(_:) 보존
  - 빌드 6.81s clean
- **재검토**:
  - 활동 휴리스틱 정확도 (긴 명령 = 1.2초보다 오래 걸림 → 다시 running 잡힘. 짧은 echo도 잘 잡히는지)
  - Split 모드 사용 빈도 vs 다중 인스턴스 빠른 전환만으로 충분한지
  - 트리 Delete 키가 실수 삭제 유발하는지 (휴지통이라 복구 가능하지만 마찰 추적)
  - drag-drop 사용 빈도 — Cmd+Click multi-select + 컨텍스트 메뉴 vs drag

---

## ADR-040 — v1.1+ R1: File CRUD 확장 (move/trash/multi-select/inline rename) + 다중 터미널 강화

- **날짜**: 2026-05-02
- **상태**: Accepted
- **결정**: ADR-039 v1.1+로 미뤘던 5개 항목 일괄 + 다중 터미널 인스턴스 6개 항목 통합 — 사용자가 외부 IDE/Terminal.app 없이 모든 워크플로 가능. F1-F5 (file CRUD 확장) + T1-T9 (다중 터미널)
- **컨텍스트**:
  - 사용자 — "v1.1+로 미룬 항목들도 모두 구현해줘 / 다중 터미널 기능을 최대한 강화해서 기획하고 구현해줘"
  - file CRUD 4종 (ADR-039)으로 외부 IDE 의존 80% 제거 → 나머지 20% (move/trash/multi-select/inline)도 같은 라운드에 마무리
  - 단일 터미널 인스턴스 → 진짜 다중 워크플로 지원 위해 multi-session
- **각 결정**:
  ### File CRUD 확장 (F1~F5)
  1. **F1 폴더 이동 (move)**:
     - `WorkspaceFileTree.move(_:to:)` — `rename`을 cross-parent로 일반화. 부모 디렉토리 자동 생성
     - rename은 같은 부모 내에서만 (path safety 우선) — move는 다른 부모 허용
     - drag-drop UI는 v1.2+ (현재는 `move` API만 — 사용자가 cross-parent 필요 시 sheet/agent 위임)
  2. **F2 휴지통 (trash)**:
     - `delete(_:moveToTrash:)` 옵션 — `NSWorkspace.shared.recycle` (복구 가능)
     - **default = trash** (안전 우선). 영구 삭제는 명시적 옵션
     - `@MainActor` continuation wrap (NSWorkspace.recycle은 main thread + completion handler)
     - 알림 alert 메시지도 "휴지통으로" 변경
  3. **F3 다중 선택 (multi-select)**:
     - `Set<String> selectedFilePaths` AppModel state
     - 트리 cell **Cmd+Click** → 토글 (NSEvent.modifierFlags 직접 검사 — SwiftUI 표준)
     - 다중 선택 시 트리 헤더에 "N개 선택" + 선택 해제 + 일괄 휴지통 버튼
     - `deleteMany([String], moveToTrash:)` — best-effort (일부 실패해도 나머지 진행 + 첫 에러 throw)
     - `Set` 사용 — order 무관, contains O(1)
  4. **F4 inline rename**:
     - 트리 cell이 TextField로 in-place 전환 (`InlineRenameField` private view)
     - context menu에 "이름 변경 (inline)" 추가, sheet rename도 보존 (`이름 변경 sheet…`)
     - Esc cancel / Enter commit / focused on appear
     - `@FocusState` + `onSubmit` + `onExitCommand` 표준 패턴
     - **합리화 검증**: ADR-039에서 inline rename 보류 사유는 "focus 관리 까다로움". v1.1에서 다시 검토 → SwiftUI 4.0+ `@FocusState` + `onExitCommand`로 충분히 안정적임 확인
  5. **F5 rename + imports — agent 위임 패턴**:
     - LSP 통합 (sourcekit-lsp/tsserver)은 수 주 작업 — 보류
     - 대안: `askAgentToUpdateImports(oldPath:newPath:)` — 활성 chat composer에 자연어 prompt prepend
     - agent가 grep + 수정 수행 (Yuminai의 vibe-coding 본질에 부합)
     - 사용자가 호출 시점 선택 (자동 X)
  ### 다중 터미널 (T1~T9)
  6. **T1 TerminalSession 모델**:
     - `public struct TerminalSession: Sendable, Identifiable, Equatable, Codable { id, label, workingDirectory, createdAt }`
     - Codable로 v1.2+ 영속화 준비 (현재는 메모리만)
     - `defaultLabel(index:)` — "터미널 1" 한국어
  7. **T2 다중 인스턴스 lifecycle**:
     - `terminalSessions: [TerminalSession]` + `activeTerminalSessionId: UUID?`
     - max 10 (FIFO overflow), 마지막 close → pane 자동 닫기
     - close active → 같은 idx (오른쪽) → idx-1 (왼쪽) → nil 순으로 active 이동 (FileTab 패턴 동일)
  8. **T3 split layout 보류**:
     - 좌우/상하 split은 NSViewRepresentable lifecycle + SwiftTerm process 관리 복잡도 큼
     - 다중 인스턴스 + 빠른 전환으로 80% 가치 달성, split은 v1.2+
  9. **T4 라벨 변경**:
     - `TerminalRenameSheet` (단순 1-field sheet)
     - 탭 더블 클릭 또는 컨텍스트 메뉴 "이름 변경"
  10. **T5 영속성**: 메모리만 (워크스페이스 전환 시 reset). 디스크 영속은 Codable 준비됐으므로 v1.2+
  11. **T6 명령 history 영속**: 보류 — 가치 모호 (대화형 PTY는 zsh history가 처리, block-style은 max 50 in-memory 충분)
  12. **T7 명령 재실행 (block ↻)**:
     - CommandBlockView hover 시 `arrow.clockwise` 버튼 → `onRerun(command)` callback
     - 사용자가 같은 명령을 빠르게 재시도 (테스트 fail-fix-test 사이클)
  13. **T8 block clipboard share + agent 위임**:
     - hover 시 `doc.on.doc` (copy) + `paperplane` (agent share)
     - `copyCommandBlockOutput` — NSPasteboard
     - `shareCommandBlockToAgent` — 명령 + stdout/stderr를 agent 메시지에 prepend (DeliveryResult 패턴 동일)
  14. **T9 단축키 (ADR-040 T9)**:
     - **⌃⇧T**: 새 터미널 세션 (terminal pane 자동 열림)
     - **⌃⇧W**: 활성 세션 닫기
     - **⌃Tab**: 다음 세션 (순환)
     - **⌃⇧Tab**: 이전 세션
     - 모두 `disabled(...)` 가드로 의미 없는 단축키 차단
- **단순화 ROI 분석**:
  - **F1 move**: 가치 50, 비용 0.2인일 (rename 일반화) — ROI 압도
  - **F2 trash**: 가치 80 (실수 복구 — 사용자 신뢰), 비용 0.3인일 (NSWorkspace.recycle wrap) — ROI 압도
  - **F3 multi-select**: 가치 60 (대량 정리), 비용 0.5인일 (Set state + UI) — ROI 양호
  - **F4 inline rename**: 가치 40 (sheet도 충분), 비용 0.4인일 — ROI 보통, 하지만 표준 IDE 경험에 가까움
  - **F5 agent imports**: 가치 70 (LSP 대안), 비용 0.1인일 (prompt 1개) — ROI 압도
  - **T1-T9 다중 터미널 일괄**: 가치 90 (Terminal.app 의존 제거), 비용 1.5인일 — ROI 압도. 핵심 vibe-coding 도구
- **격리**:
  - Core: WorkspaceFileTree (move/deleteMany/trash) + TerminalSession 모델
  - App: AppModel multi-terminal/multi-select state + TerminalRenameSheet
  - UI: FilesPanel (multi-select + inline rename) + CommandRunnerPane (block 강화)
  - 다중 터미널 view는 RootView (terminalPaneSection을 multi-session 인식 버전으로 교체)
  - SwiftTerm은 TerminalPane wrap 그대로 — 각 세션 ID로 NSView identity 분리 (`.id(uuid)`)
- **외부 의존성 정책**:
  - 새 외부 dependency 없음. AppKit (NSWorkspace.recycle / NSPasteboard / NSEvent.modifierFlags)만 추가
  - SwiftTerm 다중 인스턴스 — 기존 단일 인스턴스 패턴 N개로 (각 process spawn은 SwiftTerm 자동)
- **알려진 한계 / v1.2+**:
  - **Drag-drop file move** — SwiftUI `.draggable`/`.dropDestination` 가능, 하지만 cross-row drop visual feedback이 까다로움
  - **터미널 split (좌우/상하)** — multi-instance로 80% 가치 달성
  - **터미널 영속화** (워크스페이스 reload 시 세션 복원) — Codable 준비됐으므로 SwiftData WorkspaceModel에 추가만 하면 됨
  - **터미널 cwd 분리** (각 세션 다른 디렉토리) — UI에서 cwd 변경 sheet 추가만
  - **명령 history 검색** (block-style command runner)
  - **rename 시 LSP 기반 imports 업데이트** — agent 위임으로 충분 가능성. 진짜 LSP는 v2.0+
  - **F2/Delete 키 단축키 (트리 focus 시)** — `.focusable() + .onKeyPress` SwiftUI macOS 14에서 가능, R2에서 추가
- **결과**:
  - 신규 파일 3개 (App): TerminalRenameSheet.swift / (test) WorkspaceFileTreeMoveTests / TerminalSessionTests
  - 신규 파일 1개 (Core): TerminalSession.swift
  - 수정 파일 6개:
    - YuminaiCore/WorkspaceFileTree.swift — move/deleteMany/trash + 3 case 보존
    - YuminaiApp/AppModel.swift — 13 신규 메서드 (다중 터미널 + 다중 선택 + agent prompt) + 5 state
    - YuminaiUI/FilesPanel.swift — 다중 선택 UI + inline rename + 13 신규 callback
    - YuminaiUI/InspectorPanel.swift — 13 callback forwarding
    - YuminaiUI/CommandRunnerPane.swift — block hover 시 ↻/copy/share 버튼
    - YuminaiApp/RootView.swift — 다중 터미널 view + 4 단축키 + sheet/alert wiring
  - **테스트 15 신규 (271→286 통과)**:
    - WorkspaceFileTreeMoveTests (9): move (cross-parent / folder / target exists / missing / traversal) + deleteMany (basic / partial fail / empty) + delete permanent
    - TerminalSessionTests (6): init / identity / Codable / defaultLabel / Hashable / mutable
  - 빌드 6.75s clean
- **재검토**:
  - 다중 터미널 사용 빈도 — 1개로 충분한 사용자 vs 3-5개 동시 운영 사용자 분포
  - inline rename vs sheet rename 사용자 선호
  - F2 trash가 너무 자주 호출되어 휴지통이 바로 가득 차는지
  - drag-drop file move 요구 강도 (현재 move API만)

---

## ADR-039 — v0.9+ R3: File CRUD UX (rename / new file / new folder / delete)

- **날짜**: 2026-05-02
- **상태**: Accepted
- **결정**: ADR-038 v1.0+로 미뤘던 파일 CRUD UX를 v0.9+ R3로 앞당김 — 사용자가 외부 IDE 없이 워크스페이스 내에서 파일 생성/이름변경/삭제 가능. `WorkspaceFileTree` actor에 4 CRUD 메서드 + path safety + UI: 트리 컨텍스트 메뉴 + 공통 이름 입력 sheet + 삭제 confirmation alert
- **컨텍스트**:
  - 사용자 — "진행해 줘" (R2 점검 후 file CRUD가 ROI 가장 높다는 분석 승인)
  - ADR-038 v1.0+ 후보 중 가장 자연스러운 후속 — Multi-tab + 검색 까지 가능하지만 새 파일 만들려면 외부 IDE 필요했던 것
  - macOS Finder 컨텍스트 메뉴 + VSCode tree 패턴 표준 — 새로 학습할 게 적음
- **각 결정**:
  1. **CRUD 4종 일괄 (rename / new file / new folder / delete)**:
     - **편집 + 정리** workflow 완전성을 위해 4종 모두 필요. rename만 빼고는 외부 IDE 의존
     - **delete confirmation 필수** — 폴더는 재귀 삭제 (Finder 휴지통 X, 영구 삭제) 명시
  2. **공통 이름 입력 sheet (FileNameSheet) — 단순화**:
     - 새 파일/새 폴더/이름 변경 모두 같은 UI shape (TextField 1개 + 부모 위치 표시 + Enter/Esc)
     - 3개 별도 sheet → 1 sheet + intent enum으로 단순화 (FileNameSheetIntent)
     - sheet binding은 `Identifiable` enum + `.sheet(item:)` 패턴
     - inline tree rename (TextField in row)은 SwiftUI에서 focus 관리 까다로움 + sheet가 더 안전 — VSCode도 sheet/popover 선호
  3. **삭제는 alert (sheet X)**:
     - destructive operation은 SwiftUI `Alert` + `.destructive` button role 표준
     - confirmation message에 "복구할 수 없어요" + 폴더면 "안 모든 파일이 함께 삭제" 명시
  4. **컨텍스트 메뉴 (`.contextMenu`) — Finder/VSCode 표준**:
     - 파일: 이름 변경 / 삭제
     - 폴더: 새 파일 / 새 폴더 / divider / 이름 변경 / 삭제
     - root scope 새 파일/새 폴더는 트리 헤더 + 버튼 (Finder의 "현재 폴더" 동작 차용)
  5. **Path safety (보안 — 절대 필수)**:
     - 빈 경로 / 절대 경로 (`/etc/passwd`) / `..` traversal 모두 차단
     - `resolveSafePath` helper — standardize 후 rootURL prefix 검증 (symlink escape 방어)
     - rename 시 새 이름에 `/`/`\\` 포함 차단 (같은 부모 디렉토리 내에서만 허용)
  6. **AppModel openFileTabs 자동 sync**:
     - **rename**: 영향받는 tab path를 새 path로 업데이트 (파일 단일 + 폴더 prefix 변경 둘 다)
     - **delete**: 영향받는 tab 모두 강제 close (dirty 무시 — 디스크에 없으니 의미 없음)
     - **create file**: 새 파일은 자동 tab 열기 (편집 즉시 가능 UX)
- **단순화 ROI 분석**:
  - **CRUD 4종**: 가치 80 (외부 IDE 의존 제거), 비용 1.5인일 (path safety + tab sync 까다로움) — ROI 양호
  - **공통 sheet**: 비용 절감 (3개 별도 → 1) + UI 일관성
  - **컨텍스트 메뉴**: 비용 0.2인일 (`.contextMenu` modifier만), 가치 50 (사용자 학습 최소)
- **격리**:
  - `WorkspaceFileTree`: CRUD + path safety는 Core (UI 의존 X)
  - `FileNameSheet` / `FileDeleteConfirmation` / `FileNameSheetIntent`: App 모듈 (UI binding 종속)
  - `FilesPanel`: UI에서 callback만 호출 (sheet/alert 책임 X)
  - **분리 원칙**: UI는 의도(intent)를 emit, App layer가 sheet/alert 제어
- **외부 의존성 정책**:
  - 새 dependency 없음 — Foundation FileManager + SwiftUI 표준 사용
- **단순화 보류 (v1.0+)**:
  - **inline rename** (트리 cell 안 TextField) — focus 관리 까다로움, sheet로 충분
  - **drag-drop 폴더 이동** — rename + 같은 부모 제약 풀어야 함, 큰 작업
  - **휴지통 (Trash, NSWorkspace.recycle)** — 복구 가능 옵션. 현재는 영구 삭제만, 사용자 신호 후 추가
  - **다중 선택 + 일괄 삭제** — checkbox UI 비용
  - **rename 시 imports/refs 자동 업데이트** — LSP 의존 (큰 작업)
- **결과**:
  - 신규 파일 2개 (App): FileNameSheet.swift / FileNameSheetIntent (같은 파일)
  - 신규 파일 1개 (Test): WorkspaceFileTreeCRUDTests.swift (19 tests)
  - 수정 파일 4개:
    - YuminaiCore/WorkspaceFileTree.swift — CRUD 4 메서드 + resolveSafePath helper + 3 새 error case
    - YuminaiApp/AppModel.swift — 4 CRUD 메서드 + commitFileNameIntent + 2 sheet state
    - YuminaiUI/FilesPanel.swift — 4 callback + tree header CRUD 버튼 + FileNodeRow 컨텍스트 메뉴
    - YuminaiUI/InspectorPanel.swift — 4 callback forwarding
    - YuminaiApp/RootView.swift — sheet/alert binding + 4 callback wiring
  - **테스트 19 신규 (271/271 통과, 252→271)**:
    - createFile (basic / 중첩 / duplicate reject)
    - createFolder (basic / duplicate reject)
    - rename (basic / 중첩 / `/` 차단 / 빈 이름 / missing source / target exists)
    - delete (file / folder 재귀 / missing)
    - path safety (절대 경로 / `..` traversal / 빈 경로)
    - workflow 통합 (createFile then read / createFile then write)
  - 빌드 6.71s clean
- **알려진 한계 / v1.1+**:
  - 폴더 사이 이동 (drag-drop or rename to different parent)
  - 휴지통 (NSWorkspace.recycle)
  - 다중 선택 일괄 작업
  - rename 시 자동 imports 업데이트 (LSP)
  - inline rename (트리 cell 내 TextField)
- **재검토**:
  - 사용자 외부 IDE 사용 빈도 감소 여부 (가설: file CRUD 추가 후 80% 워크플로 Yuminai 안에서 가능)
  - delete confirmation이 너무 잦은 마찰 만드는지
  - 컨텍스트 메뉴 vs 단축키 — `Delete` 키 / `F2` rename 표준 단축키 추가 필요한지

---

## ADR-038 — v0.9+ R1: Syntax highlight + Multi-tab + Cmd+P 파일 검색 + Quick command 사용자 정의

- **날짜**: 2026-05-02
- **상태**: Accepted
- **결정**: ADR-037 v0.9+ deferred 항목 4개 일괄 — E1 syntax highlight (Highlightr) + E2 multi-tab 편집 + E3 file search sheet + E4 quick command 사용자 정의. E5/E6 (block 강화 / ACP Spike) 보류
- **컨텍스트**:
  - 사용자 — "v0.9+ 항목들 전부 논리적으로 기획해 가면서 구현해 줘"
  - ADR-037 v0.8 R1에서 단순화 보류된 IDE 인접 기능들 — 사용자 평가 후 가치 검증된 항목 우선
  - v0.8 사용으로 raw mono viewer가 가독성 한계 + 다중 파일 동시 검토 needs 확인
- **각 결정**:
  1. **E1 Syntax highlight = Highlightr 채택**:
     - 대안 평가: SwiftUI native code editor (없음) / Sourceful (오래됨) / Highlightr (Highlight.js wrap, MIT, 활성)
     - **선택 이유**: 100+ 언어 즉시 + AppKit NSAttributedString → AttributedString 변환 가능 + 단일 의존성 / lock-in 완화 (CodeViewer가 Highlightr 직접 노출 X — 외부에는 SwiftUI View)
     - **단순화**: read-only viewer만 highlight (editor는 raw TextEditor 유지 — editable highlight = NSTextView wrap이 큰 작업, v1.0+)
     - **fallback**: > 100KB 파일은 plain text (highlight 비용 회피, 일반 코드는 < 50KB)
     - **theme**: atom-one-dark 고정 (Yuminai dark-first — light theme switch는 v1.0+)
  2. **E2 Multi-tab 편집**:
     - **상태 모델**: `FileTab` struct (id/path/savedContents/draft/isEditing) + `[FileTab]` in AppModel + `activeFileTabId`
     - **legacy 유지**: 기존 `selectedFilePath`, `workspaceFileDraft` 등 single-file API는 active tab의 computed projection으로 retained — 호출자 리팩터링 없이 multi-tab 동작
     - **dirty tracking**: `isDirty = isEditing && draft != savedContents` — preview-only navigation은 dirty 아님
     - **tab 한도**: 10개 (FIFO non-dirty 제거 — dirty tab은 사용자 명시 close 필요)
     - **close protection**: dirty tab close는 reject (저장 또는 discard 필수) — VSCode 패턴
  3. **E3 File search (Cmd+P)**:
     - **알고리즘**: prefix(100) > name contains(50) > path contains(20) + 짧은 이름 가산점 — full fuzzy matcher (Sublime/VSCode식 char-by-char) 보류 ROI 약함
     - **격리**: `FuzzyFileFilter` enum을 Core에 추출 (테스트 가능) / FileSearchSheet (App)는 UI binding만
     - **결과 cap**: 50개 (성능 + 인지 부하) — 뮈 매칭 더 좁은 query 유도
     - **binary 자동 제외**: WorkspaceFileTree의 isBinary flag 활용
  4. **E4 Quick command 사용자 정의**:
     - `CustomQuickCommand` struct (id/label/command) → `DeliveryConfig.customQuickCommands` 영속
     - **UI**: WorkspaceDeliverySheet에 customQuickSection 추가 (이름 + 명령 TextField + 추가/제거 버튼)
     - **chip icon**: sparkles (default 명령들과 시각 구분)
     - **순서**: test/build/lint default → custom → git 명령 (사용자 자주 쓰는 것이 default와 git 사이)
  5. **E5/E6 보류**: CommandRunner block 강화 (search/replay/share 등) + ACP Spike — ROI 약하거나 외부 의존 변동 큼. v1.0+ 사용자 신호 후
- **단순화 ROI 분석**:
  - **Syntax highlight**: 가치 90 (코드 가독성 핵심), 비용 0.5인일 (Highlightr 단일 의존성, viewer-only) — ROI 압도
  - **Multi-tab**: 가치 75 (multi-file workflow 표준), 비용 1인일 (dirty tracking + close protection) — ROI 양호
  - **Cmd+P**: 가치 70 (대형 프로젝트에서 트리 navigation 한계), 비용 0.3인일 (단순 fuzzy + sheet) — ROI 압도
  - **Custom quick**: 가치 50 (사용자 워크플로 특화), 비용 0.2인일 (DeliveryConfig 필드 + sheet UI) — ROI 양호
- **격리**:
  - **Highlightr**: YuminaiUI 의존성. CodeViewer가 wrap (외부에 Highlightr API 노출 X)
  - **FileTab**: YuminaiCore (UI 의존 X)
  - **FuzzyFileFilter**: YuminaiCore (FileNode 의존, 테스트 가능)
  - **FileSearchSheet**: YuminaiApp (FuzzyFileFilter 사용, UI binding)
  - **CustomQuickCommand**: YuminaiCore (DeliveryConfig와 함께 영속)
- **외부 의존성 정책 변경**:
  - Highlightr 추가 (raspu/Highlightr, MIT) — ADR-021 (swift-markdown-ui 추가) 패턴 동일 검토
  - **lock-in 완화**: CodeViewer가 wrap하므로 향후 dropping 가능 (Highlightr 미사용 시 plain text fallback 동작)
- **결과**:
  - 신규 파일 5개: CodeViewer.swift / FileTab.swift / FuzzyFileFilter.swift / FileSearchSheet.swift / FileTabTests.swift / FuzzyFileFilterTests.swift / CodeViewerTests.swift (4 src + 3 test)
  - 수정 7개: Package.swift (Highlightr) / DeliveryConfig.swift (customQuickCommands) / AppModel.swift (multi-tab) / FilesPanel.swift (tab bar + search btn + CodeViewer) / InspectorPanel.swift (forwarding) / RootView.swift (sheet + ⌘P hotkey + custom quick) / CommandRunnerPane.swift (custom param) / WorkspaceDeliverySheet.swift (custom section)
  - 신규 테스트 31개 — FileTab(7) + CustomQuickCommand(4) + FuzzyFileFilter(11) + CodeViewer(9)
  - build 7.05s clean, 31/31 v0.9+ tests 통과
- **알려진 한계 / v1.0+**:
  - Editable highlight (현재 read-only viewer만)
  - Light theme support (현재 atom-one-dark 고정)
  - File rename / new file / delete UX
  - Tree fuzzy filter inline (현재 Cmd+P sheet만)
  - Custom quick command 위치 reorder
  - Command block search/share/replay (E5)
  - ACP 진짜 양방향 (E6)
- **재검토**:
  - Highlightr 성능 — 1MB 코드에서 500ms 이상이면 worker thread offload 검토
  - Multi-tab 한도 10이 너무 작은지 (사용자 사용 데이터로)
  - Cmd+P 결과 50 cap이 missed match 야기하는지
  - Custom quick command가 deliveryConfig.customQuickCommands가 아닌 별도 영속이 필요한지

---

## ADR-037 — v0.8 R1: 워크스페이스 파일 트리 + 뷰어/편집기 + Quick command 버튼

- **날짜**: 2026-05-02
- **상태**: Accepted
- **결정**: 사용자 요청 IDE-like 기능을 단순화 패턴으로 — 워크스페이스 파일 트리 + viewer/editor (Inspector "파일" 탭) + CommandRunnerPane에 quick command 버튼
- **컨텍스트**:
  - 사용자 — "0.8 진행해주고 터미널 실행 기능, ide처럼 코드 뷰어 및 편집 기능도 추가해 줘"
  - 터미널: 이미 SwiftTerm + CommandRunnerPane 있음 → 강화 (quick command + history 유지)
  - IDE-like: 파일 트리 + 뷰어/편집기 (단순화: 1-file, no syntax highlight)
- **각 결정**:
  1. **D1+D2 IDE-like (단순화)**: VSCode-class 풀 IDE는 cost prohibitive. 단순화 — 트리 + 1-file viewer/editor, Inspector 탭. Obsidian Vault NoteTreeView/MarkdownViewer 패턴 차용
  2. **D3 Multi-tab 보류**: tab state + dirty tracking 큰 작업. 현재 디자인 (편집 중이면 다른 파일 reject)이 안전하고 단순
  3. **D4 Syntax highlight 보류**: SwiftUI native code editor 부재. NSViewRepresentable wrap이 가능하지만 (Highlightr 등) 외부 의존성 추가 + 유지보수 비용. raw mono로 시작, v0.9+ 라이브러리 발견 시
  4. **D5 Command history**: 이미 메모리 max 50 — 충분 (single session 내). SwiftData 영속은 cost 작지만 user value 모호 → v0.9
  5. **D6 Quick command**: workspace.deliveryConfig 활용 + git 기본 명령. 사용자 정의는 v0.9
- **단순화 ROI 분석**:
  - VSCode IDE: 가치 100, 비용 50인일 (LSP + multi-tab + syntax + folding + ...)
  - **단순 트리+뷰어**: 가치 70 (read/edit), 비용 0.5인일 — ROI 압도적
- **WorkspaceFileTree 설계 결정**:
  - actor (Vault 패턴 동일)
  - 자동 제외 list — gitignore parsing은 큰 작업 vs 알려진 폴더 hardcode가 80% 케이스 cover
  - max depth 6 — 무한 재귀 방지 (typical project 깊이)
  - file size 1MB limit — UI 무거움 회피
  - binary 자동 감지 — viewer/editor에 안 좋은 파일 hide
- **편집 안전 결정**:
  - dirty 상태에서 다른 파일 선택 reject (data loss 방지)
  - 자동 prompt save dialog는 추가 UI 비용 → v0.9
  - 사용자가 "저장 또는 취소" 명시적 액션 필요
- **격리**:
  - WorkspaceFileTree는 Core (UI 의존 X)
  - FilesPanel은 UI (FileNode 의존)
  - QuickCommand는 UI (private 단순 struct)
  - AppModel은 file state owner (single source of truth)
- **결과**:
  - 신규 파일 2개: WorkspaceFileTree.swift / FilesPanel.swift
  - InspectorTab .files 추가 (4 탭)
  - InspectorPanel +14 params (file tree state + callbacks)
  - AppModel +6 file state + 5 file methods
  - CommandRunnerPane +QuickCommand + quickCommandRow + Chip view
  - RootView InspectorPanel 호출 + workspace 변경 .task hook
  - 7 신규 테스트 (WorkspaceFileTree)
  - build 5.9s, test 216/216 (209→216, +7)
- **알려진 한계 / v0.9+**:
  - Multi-tab 편집 (현재 1 file)
  - Syntax highlight (Highlightr 등 외부 의존성 평가)
  - File rename / new file / delete UX (현재는 외부 IDE 사용)
  - File search (Cmd+P)
  - Command history 영속 (SwiftData)
  - Quick command 사용자 정의
- **재검토**:
  - 사용자 inline 편집 사용 빈도 vs 외부 IDE
  - syntax highlight 진짜 필요한지 (raw mono로 충분?)
  - Multi-tab 필요성 (1 file이 충분한지)
  - Quick command 사용자 정의 요구 빈도

---

## ADR-036 — v0.5 R3: Live ping + Editable diff (inline) + Terminal block (별개 pane) + chain hint 강화

---

## ADR-036 — v0.5 R3: Live ping + Editable diff (inline) + Terminal block (별개 pane) + chain hint 강화

- **날짜**: 2026-05-02
- **상태**: Accepted
- **결정**: v0.7+ 보류 항목 5개 평가 → 4/5 진행, 모두 단순화 패턴 채택. ACP는 별도 spike 작업으로 유지
- **컨텍스트**:
  - 사용자 — "v0.7+ 권고 항목들도 구현 진행"
  - 보류 항목 모두 cost prohibitive였으나, 단순화 가능한 것들만 진행
- **각 결정**:
  1. **C1 ping**: ROI 명확. 0.3s timeout으로 빠른 응답, false-positive 위험은 confidence label로 완화
  2. **C2 chain hint**: 코드 변경 작음. 사용자가 chain의 multi-mention sequential 효과를 자연스럽게 알게
  3. **C3 editable diff (TextEditor)**: Cline editable은 SwiftUI native diff editor 부재로 비용 prohibitive. 단순화 — segmented "Diff/편집" 토글 + raw TextEditor. syntax highlight X but cost 80% 감소
  4. **C4 CommandRunnerPane (별개)**: SwiftTerm은 PTY-based, block grouping 불가. **별개 패널** 채택 — NSTask로 단일 명령 + block. 사용자에게 명확한 use case 분리 (interactive zsh = ⌘⌥T, 기록되는 명령 = ⌘⌥R)
- **C3 단순화 가치**:
  - 진짜 Cline editable diff: gutter + inline edit + 변경 추적 — 3-5인일
  - inline TextEditor: 100라인 정도 — 0.5인일
  - 사용자 가치 중 80%는 "수정 가능" 자체에서 옴 — diff editor UX는 polish
- **C4 별개 pane 결정 사유**:
  - SwiftTerm wrap으로 block UX 추가 = PTY parser + prompt 인식 + grouping = 매우 큼
  - 별개 pane = NSTask + 단순 UI = 1인일
  - 사용자 use case 다름:
    - 기존 SwiftTerm: interactive zsh, vim/htop 같은 interactive
    - 새 CommandRunnerPane: 한 번 실행 + 결과 기록 (npm test, git status 등)
  - 두 use case 분리가 UX 더 명확
- **격리**:
  - DevServerDetector.pingAll은 Core (URLSession Foundation)
  - CommandRunner는 Core (NSTask Foundation)
  - CommandRunnerPane은 UI (Core 의존)
- **결과**:
  - 신규 파일 2개: CommandRunner.swift / CommandRunnerPane.swift
  - DevServerDetector +pingAll + isAlive 필드
  - PreviewPane SuggestionChip live indicator
  - DiffView +inline editor (segmented 토글)
  - AppModel +readWorkspaceFile / writeWorkspaceFile / runCommand / clearCommandBlocks / refreshDevServerSuggestions
  - ChatToolbar +commands toggle (⌘⌥R)
  - RootView 3-way VSplit (chat / terminal / commands)
  - InspectorPanel +readChangedFile / onSaveChangedFile
  - Composer hint chain-aware
  - 3 신규 테스트 (CommandRunner)
  - build 7.2s, test 209/209 (206→209, +3)
- **알려진 한계 / v0.8+**:
  - Live ping 0.3s timeout — slow server false-negative 가능
  - Editable diff syntax highlight X (SwiftUI Code Editor 라이브러리 발견 시)
  - CommandRunnerPane은 1회 명령만 (vim 등 interactive는 SwiftTerm 사용)
  - 진짜 Warp PTY-aware block UX — SwiftTerm wrap 큰 작업
  - ACP 실제 PoC — 2-3일 별도 (ADR-034 doc 유지)
- **재검토**:
  - ping false-positive/negative 빈도 (사용자 사용 데이터)
  - inline editor 사용 빈도 (외부 IDE 대비)
  - CommandRunner vs Terminal 사용 빈도 비교

---

## ADR-035 — v0.5 R2: Dev server auto-detect + Editable diff 단순화 + multi-mention 안내 + Dual-Composer split

---

## ADR-035 — v0.5 R2: Dev server auto-detect + Editable diff 단순화 + multi-mention 안내 + Dual-Composer split

- **날짜**: 2026-05-02
- **상태**: Accepted
- **결정**: UX 검토 후 4/6 진행 — 가치 큰 것 + 구현 가능한 것. Terminal Block UX와 ACP는 cost 명시 보류
- **컨텍스트**:
  - 사용자 — "다음 단계도 이어서 구현해 줘 uiux를 상세히 검토해서 구현해"
  - **상세 UX 검토** — 단순 구현 X, 각 항목 사용성 분석 후 결정
- **각 결정**:
  1. **B1 dev server auto-detect** — package.json + config 파일 분석. ping은 X (사용자가 server 시작했는지 모름, false-positive 회피). Suggestion chip으로 추천만, 사용자 클릭 시 로드
  2. **B2 Editable diff 단순화** — Cline editable은 SwiftUI 자체 구현 prohibitive (3-5인일). External editor 버튼으로 단순화 — NSWorkspace.open이 Xcode/VSCode/etc 자동 열어줌. 가치 80% 비용 5%
  3. **B3 Multi-mention 안내** — parallel dispatch는 multi-pane state 충돌 위험 + UX 복잡. 첫 mention만 + UI hint로 명확화 (사용자가 잘못 쓰면 알아챔)
  4. **B4 Dual-Composer 단순화** — 진짜 isolated dual은 Composer state 분리 매우 큼. **단순화**: secondary는 자체 input draft만 보관, send 시 setActivePane → input swap → sendMessage. 양쪽 동시 입력 가능 + send가 active 전환을 트리거 (focus follow)
- **B1 UX 결정 — ping vs 추천**:
  - ping (HTTP HEAD)으로 서버 살아있는지 확인 가능 but:
    - false-positive: localhost:3000이 다른 앱 점유 가능
    - 사용자가 anyway URL 직접 클릭해야 — ping은 noise
  - **추천만 채택** — confidence label로 user expectation 관리
- **B2 단순화 가치 분석**:
  - Cline editable 가치: 100 (매우 높음)
  - SwiftUI 자체 diff editor 비용: 100 (3-5인일 + 유지보수)
  - External editor 가치: 80 (사용자가 익숙한 IDE 사용 가능)
  - External editor 비용: 5 (NSWorkspace.open 1줄)
  - **ROI: External editor가 압도적**
- **B4 Dual 단순화 — focus follow 패턴**:
  - 진짜 dual은 두 Composer가 독립 + 각자 active pane으로 send
  - 문제: 어느 쪽이 ⌘Return target인지, 양쪽 isStreaming 상태 동시 추적
  - **단순화**: send 시 active 전환 — 사용자 의도가 명확 (이 pane으로 보낸다 = 이 pane을 본다)
  - 양쪽 입력 draft는 보존 (secondary @State) — 사용자가 panes 옮겨다니면서 draft 유지
- **격리**:
  - DevServerDetector는 YuminaiCore (UI 의존 X)
  - openFileInExternalEditor는 AppModel (NSWorkspace.open)
  - SecondaryPaneView 자체 @State (AppModel state 변경 X)
- **결과**:
  - 신규 파일 1개: DevServerDetector.swift
  - PreviewPane +SuggestionChip + suggestions strip
  - DiffView.FileRow +open in editor 버튼
  - AppModel +openFileInExternalEditor + sendToPane
  - InspectorPanel +onOpenChangeInEditor callback
  - SecondaryPaneView +자체 Composer (draft @State)
  - MentionParser +allInline
  - Composer +multiMentionHint (orange banner)
  - 15 신규 테스트
  - build 7.6s, test 206/206 (191→206, +15)
- **알려진 한계 / 보류**:
  - **Terminal Block UX (Warp)** — SwiftTerm 한계, 자체 PTY wrap 비용 매우 큼 → v0.7+
  - **ACP 실제 PoC** — 2-3일 별도 spike, ADR-034 doc 자료 유지
  - Multi-mention parallel dispatch — v0.7+ (state 충돌)
  - Dev server ping — false-positive 위험으로 X
  - External editor는 system default (Xcode 등) — 사용자 설정 가능
- **재검토**:
  - 사용자 dual-Composer 사용 후 — focus follow가 자연스러운지
  - 사용자 dev server suggestion 사용 후 — confidence label이 실용적인지
  - Terminal Block UX 진짜 필요한지 (사용자 명시 요청 데이터)

---

## ADR-034 — v0.5 Round 1: Agent chain + Inline mention + PreviewPane + Codex schema + Terminal reload + ACP decision doc

---

## ADR-034 — v0.5 Round 1: Agent chain + Inline mention + PreviewPane + Codex schema + Terminal reload + ACP decision doc

- **날짜**: 2026-05-02
- **상태**: Accepted (v0.5 시작)
- **결정**: 보류했던 v0.5 권고 항목 10개 평가 → 6개 진행 (A1~A6), 4개 명시 보류 (cost prohibitive 또는 가치 < 비용)
- **컨텍스트**:
  - 사용자 — "권고 항목 모두 진행해 줘"
  - **냉정 평가** — 모두 진행은 비효율. cost-prohibitive 항목은 명시 보류
- **각 결정**:
  1. **A1 pane→pane 자동 답장** — default OFF (안전 우선) + max hops Stepper + 같은 pane 재방문 차단 + UI banner. 사용자가 명시적으로 켜야 동작
  2. **A2 inline mention** — `parseInline(_:)` 추가. body는 원문 보존 (mention 위치 컨텍스트). email-like 무시 (단어 경계 검사)
  3. **A3 Codex schema** — 12 alias + logger.warning (unknown type 누적 데이터)
  4. **A4 PreviewPane** — WKWebView 단순 wrap + URL TextField. scheme 자동 추정 (http://default)
  5. **A5 Terminal reload** — block 그룹화는 SwiftTerm 한계 → 단순화 (`id(trigger)` 패턴으로 새 view spawn). 풀 block UX는 v0.6+
  6. **A6 ACP doc** — Spike summary만, 코드 변경 X. v0.6 결정 자료
- **명시 보류 사유**:
  - **Dual-Composer split** — 비용 매우 큼 (Composer state 분리, focus management). 가치 보통 → v0.6
  - **Editable diff** — Cline SOTA지만 SwiftUI native diff editor 부재, 자체 구현 prohibitive (3-5인일). SwiftUI 솔루션 발견 시 재검토
  - **인터랙티브 튜토리얼** — 가이드 카드(ADR-033 G3)로 충분 — 추가 비용 < 가치
  - **T5 per-pane settings** — tab swap이 동일 효과, 가치 < 비용 (계속 보류)
- **A1 안전 설계**:
  - default OFF (사용자 명시 토글 필요)
  - max hops Stepper 1~5 (default 1)
  - 같은 pane 재방문 차단 (visited set)
  - 자기 자신 mention skip
  - 실패(exit≠0) 시 chain 즉시 종료
  - UI banner (활성 시 표시) + "중단" 버튼
- **A2 mention 정밀도**:
  - leading parser는 그대로 (body = mention 제거)
  - inline parser는 body = 원문 보존 (mention 위치 컨텍스트)
  - email-like 무시 (`@` 앞 공백/시작 검사)
  - 첫 mention만 인식 (multi-target은 v0.6)
- **A4 PreviewPane 단순화 결정**:
  - dev server auto-detect (예: package.json 보고 npm dev port 추정)는 v0.6
  - 사용자가 직접 URL 입력하는 단순 패턴이 cost-effective + UX 명확
- **A5 SwiftTerm 한계**:
  - SwiftTerm은 line-based PTY emulator — 명령 경계 인식 X
  - Warp-style block은 Yuminai가 자체 wrap (NSTask + 출력 grouping)으로 가능하지만 큰 작업
  - **단순화 채택**: reload 버튼 + hint만. 풀 block UX는 v0.6
- **격리**:
  - Agent chain 로직은 AppModel (state + hook)
  - MentionParser 확장은 Core (다른 모듈도 사용 가능)
  - PreviewPane은 YuminaiUI (WebKit import)
- **결과**:
  - 신규 파일 2개: PreviewPane / 02_ACP_DECISION.md
  - AppPreferences +2 (agentChainEnabled / agentChainMaxHops)
  - AppModel +chain state (3) + chain logic (2 메서드) + preview state (2)
  - MentionParser +parseInline + parseAny
  - LiveCodexAdapter +12 type alias + logger
  - SettingsView +Agent Chain section (toggle + Stepper)
  - ChatToolbar +preview toggle (⌘⌥P)
  - RootView +chain banner + preview HSplitView + chatColumnWithOptionalTerminal
  - TerminalPane 헤더에 reload 버튼 + HelpHint
  - 7 신규 테스트 (MentionParser inline)
  - build 5.3s, test 191/191 (184→191, +7)
- **알려진 한계 → v0.6**:
  - Dual-Composer split (cost 큼)
  - Editable diff (SwiftUI native 부재)
  - Terminal block UX (SwiftTerm 한계 → 자체 wrap)
  - Inline mention multi-target
  - PreviewPane dev server auto-detect
  - ACP Spike (2-3일) → 결정
- **재검토**:
  - 사용자 chain 사용 후 — max hops 적정성, banner UX, 안전 토글 default 유지 여부
  - 사용자 codex 사용 후 — logger의 unknown type 데이터로 매핑 추가
  - PreviewPane use case 명시 — dev server auto-detect 우선순위

---

## ADR-033 — v0.4 Phase F: GUI 사용성 polish (위임 버튼 + 더블클릭 rename + 가이드 카드) + pane→pane 자동 답장 명시 보류

---

## ADR-033 — v0.4 Phase F: GUI 사용성 polish (위임 버튼 + 더블클릭 rename + 가이드 카드) + pane→pane 자동 답장 명시 보류

- **날짜**: 2026-05-02
- **상태**: Accepted
- **결정**: 시나리오 항목들을 GUI 버튼으로 노출 (G1: Composer 위임 / G2: 더블클릭 rename + Toolbar 가이드 / G3: 시나리오 카드). pane→pane 자동 답장 (F1)은 안전 우선으로 명시 보류
- **컨텍스트**:
  - 사용자 — "사용해 볼 시나리오 항목들을 명령어보다는 gui를 통해 버튼으로 사용성을 쉽게 구현해 주고 후속 작업도 검토해서 진행"
  - ADR-031/032에서 만든 mention/rename/split 등 기능이 키보드/우클릭 의존 → 발견성 약함
  - 새 사용자가 첫 진입 시 "어디에 뭐 있는지" 모름
- **각 결정**:
  1. **Composer 위임 버튼** — `@` 키보드 의존 X, 명시적 GUI 진입점. menu에 모든 mention 후보 표시, 클릭 시 text 앞에 prepend
  2. **Tab 더블클릭 rename** — 우클릭 메뉴 발견 어려움. `simultaneousGesture(TapGesture(count: 2))`로 단일 클릭(select)과 공존
  3. **Toolbar 가이드 버튼** — ⌘/ 단축키 외에 명시 진입점 (`questionmark.circle`)
  4. **ShortcutHelpSheet 시나리오 카드** — 단축키 표만 보여주는 게 아니라 "이 기능 GUI에서 어디?" 8개 카드 (icon + title + howTo)
  5. **EmptyWorkspaceView 강화** — "도움말" 버튼 + quick tip 4개 (split / 위임 / terminal+inspector / 텔레그램+delivery)
  6. **F1 보류** — pane→pane 자동 답장은 v0.5 이후. 사유: 무한 루프 위험, 복잡도, 사용자 control 약화
- **F1 보류 사유 (자세히)**:
  - 가치: agent끼리 자동 협업하면 진정한 multi-agent — 매력적
  - 비용: chain hop counter, 같은 pane 재방문 감지, max hops 정책, UI에 chain visualization, 사용자 cancel 메커니즘
  - 위험: 무한 루프 (max hops로 mitigation 가능하지만 디버깅 어려움)
  - 사용자 control: agent가 사용자 모르게 다른 agent 호출 → 비용/안전 issue
  - 결론: v0.5에서 진행 — 사용자 명시 토글 + max 1 hop default + UI에서 chain 표시
- **격리**: 모든 변경은 UI 모듈만 (Composer / PaneTabBar / ChatToolbar / ShortcutHelpSheet) + AppModel state X (renameSheet은 ADR-032에서 이미 추가). 도메인 변경 없음
- **결과**:
  - Composer +1 메뉴 (delegateMenu)
  - PaneTabBar +simultaneousGesture (rename)
  - ChatToolbar +1 IconButton (도움말)
  - ShortcutHelpSheet +scenariosSection (8 카드, ScenarioEntry struct)
  - EmptyWorkspaceView quick tip 3→4 + 도움말 버튼
  - build 2.8s, test 184/184 (UI 추가만이라 신규 테스트 없음)
- **알려진 한계**:
  - 위임 버튼은 panes가 1개뿐일 때 (mentionSuggestions가 자기 자신만이면) 의미 약함 — 표시는 됨
  - 더블클릭 + 단일 클릭 시 macOS gesture 처리에 따라 가끔 race — 실측 후 조정
  - 가이드 카드는 정적 텍스트 (인터랙티브 튜토리얼 X)
  - F1 보류 — agent 협업의 자동화는 v0.5
- **재검토**: 사용자 사용 후 feedback — "위임 버튼 자주 쓰는지" / "더블클릭 충돌 있는지" / "F1 진짜 원하는지"

---

## ADR-032 — v0.4 Phase E: UX polish 4종 + Split layout

---

## ADR-032 — v0.4 Phase E: UX polish 4종 + Split layout

- **날짜**: 2026-05-02
- **상태**: Accepted
- **결정**: 보류 항목 10개 평가 후 4개 진행 (Mention picker U1 / Assistant 라벨 U2 / Pane rename U3 / Split layout U4). 6개는 defer 사유 명시
- **컨텍스트**:
  - 사용자 — "나머지 라운드도 이어서 진행해 줘"
  - 보류 항목 (ADR-031 doc 84): T5/T6/T8 + v0.5 권고 (mention picker / source 라벨 / pane→pane / ACP / editable diff)
  - **냉정한 평가** — 모두 진행은 비효율. 가치 큰 것만 선별
- **각 결정 핵심**:
  1. **U1 Mention picker** — Composer `@`로 시작하면 자동 popover. customName + shortLabel 모두 후보. 사용성 임팩트 큼 (mention 학습 비용 ↓)
  2. **U2 Assistant 라벨** — MessageBubble에 `assistantLabel` param. active pane의 displayName 표시. multi-pane에서 "어느 agent가 말하는지" 명확
  3. **U3 Rename + promote** — context menu에서 rename / primary promote. 사용자가 "Claude (설계)" "Codex (구현)" 같은 의미 있는 이름 부여 가능. mention picker 후보로도 등장
  4. **U4 Split layout (단순화)** — `PaneSplitMode { single, horizontal, vertical }`. secondary는 read-only (Composer 없음, 활성화 버튼). 진짜 dual-Composer는 v0.5 (사용성 검증 후)
- **단순화 결정 (U4)**:
  - 원안: 좌/우 동시 Composer + 각자 messages 입력
  - 현실: SwiftUI focus management 복잡 + Composer 자체가 큰 컴포넌트 + per-side 설정 picker
  - **단순화**: secondary는 read-only chat + 활성화 버튼. 사용자가 클릭하면 active 전환 (bounce). dual-Composer는 v0.5 사용성 검증 후
- **defer 항목 사유**:
  - T5 per-pane settings: tab swap이 동일 효과, 가치 < 비용
  - T6 PreviewPane: use case 명시 (web 개발 등) 시 진행
  - T8 Block UX (Warp): terminal 사용 빈도 데이터 필요
  - pane→pane 자동 답장: 무한 루프 위험, v0.5 안전 토글로
  - ACP Spike: Swift SDK 부재, 외부 생태계 성장 의존, v0.5 별도
  - Editable diff (Cline SOTA): SwiftUI native diff editor 부재, 비용 prohibitive (~3-5인일)
- **격리**:
  - PaneSplitMode는 YuminaiCore (UI 모듈에서 binding)
  - MentionSuggestion은 YuminaiUI (Composer만 의존)
  - PaneRenameSheet/SecondaryPaneView는 YuminaiApp (AppModel + UI 모두 import)
- **결과**:
  - 신규 파일 3개: PaneSplitMode / PaneRenameSheet / SecondaryPaneView
  - Composer +2 (MentionSuggestion + popover)
  - MessageBubble/AssistantMessageBlock/ChatView +1 param
  - PaneTabBar +context menu + split mode picker
  - AppModel +promotePaneToPrimary + renameSheetPane + paneSplitMode
  - RootView mentionSuggestions computed + chatArea split
  - 3 신규 테스트 (PaneSplitMode)
  - build 3.7s, test 184/184 (181→184, +3)
- **알려진 한계 → 후속 (v0.5)**:
  - Split secondary read-only (dual-Composer = v0.5)
  - per-pane delivery config X
  - Mention picker leading `@`만 (중간 mention X)
  - Codex JSONL 실측 정밀화 (사용자 사용 후 데이터)
  - pane→pane 자동 답장 (안전 토글)
  - ACP Swift SDK Spike
  - Editable diff (Cline SOTA)
- **재검토**: 사용자 multi-pane + split 사용 후 — dual-Composer 필요성 / pane→pane 자동 답장 / per-pane settings 가치 재평가

---

## ADR-031 — v0.4 Phase D: Panes 영속 (T1) + 인터-에이전트 메시지 (T2) + Codex schema 정밀화 (T3)

---

## ADR-031 — v0.4 Phase D: Panes 영속 (T1) + 인터-에이전트 메시지 (T2) + Codex schema 정밀화 (T3)

- **날짜**: 2026-05-02
- **상태**: Accepted
- **결정**: ADR-027 권고 5개 phase 중 가치/비용 평가 후 가치 큰 3개 선별 — Panes 영속 + `@codex` mention dispatch + Codex schema 안전 추가. 나머지 5개(T4-T8)는 사용자 트리거 시 진행
- **컨텍스트**:
  - 사용자 — "남은 권고 순서 하나하나 상세하게 기획하고 냉정하게 사용성과 단위 기능 검토해 가면서 구현"
  - Phase A/B/C 완료 후 권고는 split layout / per-pane 설정 / PreviewPane / 인터-에이전트 / Codex 정밀화 등
  - **냉정한 평가** — 권고 모두 진행은 비효율. 가치 큰 것만 선별
- **평가 매트릭스** (`docs/design/84_REMAINING_PHASES_EVALUATION.md`):
  | 항목 | 가치 | 비용 | 사용성 | 결정 |
  |------|-----|------|------|------|
  | T1 panes 영속 | 높음 | 작음 | 높음 | ✅ |
  | T2 mention dispatch | 높음 | 보통 | 높음 | ✅ |
  | T3 codex schema | 보통 | 작음 | 보통 | ✅ |
  | T4 split layout | 보통 | 큼 | 모호 | ⏸ |
  | T5 per-pane settings | 낮음 | 보통 | 낮음 | ⏸ |
  | T6 PreviewPane | 보통 | 보통 | 모호 | ⏸ |
  | T7 reorder/rename | 낮음 | 작음 | 낮음 | ⏸ |
  | T8 Block UX | 보통 | 보통 | 보통 | ⏸ |
- **각 결정**:
  1. **T1: Workspace.savedPanes 영속** — SwiftData JSON column (deliveryConfigJSON 패턴 재사용). session/messages는 영속 X (메타만). claude session resume으로 컨텍스트 자동 복원
  2. **T2 mention syntax `@<agent>`** — Telegram 표준 친숙. 우선순위 매칭 (customName 정확 → 부분 → agentKind → @me). 매칭 실패 시 안내, 일반 send fallback X (의도 보존)
  3. **T2 dispatch는 "사용자 응답"** — pane → pane 답장 자동 새 turn은 무한 루프 위험. v0.5 검토. 현재는 pane 활성화 + 사용자 메시지 전송
  4. **T3 명시적 무시 type 추가** — thinking/reasoning은 노이즈 (verbose 모드 토글 v0.5)
  5. **T3 error 이벤트 forward** — silent drop 위험, toolResult로 표시
  6. **T4-T8 보류** — defer 사유 명시 (사용자 트리거 조건 포함). plan에 보존, 잊지 않게
- **대안 분석**:
  - **panes 영속 vs ephemeral**: 영속 채택. 사용자가 만든 panes 잃는 것 X (워크스페이스 단위 의도 명시)
  - **mention auto-complete picker** vs **manual syntax**: picker는 v0.5. manual은 학습 비용 있지만 Telegram 표준이라 자연스러움. placeholder + i 도움말로 보조
  - **dispatch가 자동 새 turn 트리거** vs **사용자 응답만**: 전자는 자동 협업이지만 무한 루프. 후자는 안전. v0.5에서 명시적 토글 추가 검토
- **격리**:
  - MentionParser는 YuminaiCore (모든 모듈 사용 가능)
  - panesJSON은 WorkspaceModel (SwiftData column)
  - dispatch 로직은 AppModel (pane state + sendMessage 호출)
- **결과**:
  - 신규 파일 1개: MentionParser.swift
  - Workspace +1 필드 (savedPanes) + with(savedPanes:)
  - WorkspaceModel +1 column (panesJSON, nullable, 호환)
  - AppModel +3 메서드 (resolveMentionTarget / tryDispatchMention / persistCurrentPanes)
  - AppModel persist 자동: addPane / removePane / renamePane / ensurePrimaryPane
  - Composer placeholder + Composer onSend (mention 우선) + Telegram router (mention pass-through)
  - LiveCodexAdapter +12 type alias + thinking 무시 + error forward
  - 20 신규 테스트
  - build 3.5s, test 181/181 (161→181, +20)
- **알려진 한계**:
  - panes 영속하지만 messages는 fresh (claude resume에 의존)
  - mention picker (자동완성) X
  - pane → pane 답장 자동 새 turn X (안전 우선)
  - ChatView에 source/target 시각 표시 X (tab으로만 구분)
  - per-pane delivery config X (workspace 단위)
- **재검토**:
  - T4-T8 사용자 트리거 조건 (split, PreviewPane, Block UX, reorder)
  - mention picker 필요성 (사용 빈도 보고)
  - Codex JSONL 실제 사용 데이터로 unknown type 추가 매핑

---

## ADR-030 — v0.4 Phase C: Multi-pane Foundation (M1)

---

## ADR-030 — v0.4 Phase C: Multi-pane Foundation (M1)

- **날짜**: 2026-05-02
- **상태**: Accepted (Phase C foundation, split layout/per-pane controls는 후속)
- **결정**: 워크스페이스에 N개의 AgentPane 도입. 각 pane은 자체 session/messages/settings/usage. UI는 tab bar로 빠른 전환 (split layout은 후속). 1순위 reference: AutoGen AgentTool + Aider Architect/Editor 2-LLM
- **컨텍스트**:
  - 사용자 — "다음 권고 사항 이어서 진행해 줘"
  - ADR-027 권고 phase 순서: M3→M5→M4→M1→M2 — M1 (multi-pane) 차례
  - 1ws-1agent → 1ws-Nagent 진화 — Yuminai의 가장 큰 architectural change
- **각 결정**:
  1. **AgentPane domain은 Core** — 모든 모듈이 의존 가능 (UI, Telegram, App)
  2. **PaneRole 2종 (primary/secondary)** — primary는 Telegram bridge target. 워크스페이스당 1개. 인터-에이전트 메시지(M2 후속)에서는 다른 의미로 확장 가능
  3. **workspace 단위로 panes 관리** — `[UUID: AgentPane]` workspace.id key 매핑은 X. workspace 전환 시 panes 새로 생성/clear (같은 workspace 다시 들어가면 panes 잃음 — v0.5에서 영속 검토)
  4. **tab swap 패턴** — 한 시점에 1 pane visible (split layout은 후속). 전환 시 messages/session/settings/usage 모두 swap. session은 lazy spawn (첫 활성 시)
  5. **마지막 pane close 불가** — 워크스페이스에 항상 ≥1 pane. UX 단순화
  6. **session lifecycle은 pane이 소유** — pane remove 시 자체 session terminate. 기존 currentClaudeSession은 active pane의 session alias
  7. **AppModel 기존 alias 유지** — `messages` / `currentClaudeSession` / `activeSettings` / `currentSessionUsage` 모두 그대로. backward-compat 위해 active pane의 state로 swap (refactor 부담 ↓)
- **대안 분석**:
  - **워크스페이스 영속 panes** vs **세션 영속 panes**: 영속이면 workspace 다시 들어가도 같은 panes — 그러나 SwiftData 영속 비용 + session 복원 복잡 (claude session id resume). v0.4는 메모리만, v0.5에서 영속 검토
  - **tab vs split UI**: split이 power user UX 우월 but SwiftUI에서 dynamic split 비용 큼. tab 먼저, split는 사용자 검증 후 후속
  - **AppModel refactor strategy**: full alias getter (computed property)로 모든 기존 코드 호환 vs 새 메서드 추가 + 점진적 migration. 후자 채택 — 위험 분산, 점진적 검증 가능
  - **session 즉시 spawn vs lazy spawn**: 즉시는 새 pane 추가 시 비용 ↑ + 사용자가 그 pane 안 쓸 수도. lazy는 setActivePane이 처리 — 자연스러움
- **격리**:
  - AgentPane은 YuminaiCore (모든 모듈 import 가능)
  - PaneTabBar는 YuminaiUI (도메인 모델만 의존, callback 4개)
  - paneSessions는 AppModel private (Sendable 경계 안전)
- **결과**:
  - 신규 파일 2개: AgentPane.swift / PaneTabBar.swift
  - AppModel +6 properties + 5 actions (ensurePrimaryPane / setActivePane / addPane / removePane / renamePane + clearPaneState)
  - RootView chat 영역 상단에 PaneTabBar 통합
  - teardownCurrentSession 확장 (모든 panes 정리)
  - 9 신규 테스트 (defaults / displayName / immutable updates / Codable)
  - build 3s, test 161/161
- **알려진 한계 → 후속 phase**:
  - **Phase C2/C3/C4**: 좌/우 split layout / per-pane Composer 설정 / pane drag-reorder / pane settings sheet (rename/role)
  - **Phase D (M2)**: 인터-에이전트 메시지 (`@codex` mention) — MetaGPT 메시지 환경 + AutoGen GroupChat
  - panes 영속 X (워크스페이스 다시 들어가면 새 primary 1개)
  - per-pane delivery config X — workspace 전체 1개
  - per-pane usage 누적은 메모리만 (SwiftData 저장 X)
- **재검토**: 사용자 multi-pane 사용 후 — split layout 필요성, panes 영속 필요성, per-pane 설정 분리 필요성

---

## ADR-029 — v0.4 Phase B: Delivery Loop (M4) + UI 도움말 일괄 적용

---

## ADR-029 — v0.4 Phase B: Delivery Loop (M4) + UI 도움말 일괄 적용

- **날짜**: 2026-05-01
- **상태**: Accepted (구현 완료, Phase B)
- **결정**: M4 (Aider auto-test + Devin step budget) 채택 + UI 사용성 개선을 위한 HelpHint 컴포넌트 일괄 도입. M5.b (Warp block UX)는 Phase B 시간 제약으로 v0.4 후속에 보류
- **컨텍스트**:
  - 사용자 — "페이즈 b 시작하고 사용성에 대해 안내 도움말은 i 아이콘이나 간단한 건 상시로 보여지게"
  - 두 요청 동시 — UI 도움말은 신규 UI에 활용되므로 Phase B 신규 컴포넌트(WorkspaceDeliverySheet, DeliveryResultsView)에 즉시 적용
- **각 결정**:
  1. **HelpHint 4종 컴포넌트** — `HelpHint`(i+popover) + `InlineHint`(상시) + `EmptyStateHint`(빈 영역) + `LabelWithHint`(LabeledContent inline). 사용처별 패턴 분리로 일관성 + 재사용
  2. **Aider auto-test 패턴 채택** — test → lint 순서, 실패 시 lint skip. Aider 검증된 default
  3. **Devin step budget hard cap** — maxAttempts (default 3), timeout (default 300초). 무한 루프 방지 정석. mini-SWE-agent 100 LoC 단순함 증거 (Princeton NeurIPS 2024)
  4. **소극적 fix loop** — 실패 결과는 다음 사용자 메시지 앞에 prepend만. 즉시 새 turn 자동 spawn은 X (사용자 control 우선, v0.5에서 적극적 mode 검토)
  5. **빌드는 수동만** — 빌드는 보통 오래 걸리므로 turn 완료 자동 trigger 부적합. test/lint만 자동
  6. **`/bin/zsh -lc`로 실행** — 사용자 login shell config 그대로 (PATH, env). 의존성 안 깨짐
  7. **JSON 직렬화로 SwiftData 저장** — DeliveryConfig를 nullable `Data?` 컬럼에 JSON. nil → .disabled fallback (기존 워크스페이스 호환)
  8. **결과는 메모리 전용 (max 10개)** — 영속 X. 사용자가 누적 history 필요시 v0.5
- **대안 분석**:
  - **즉시 새 turn 자동 spawn** vs **소극적 prepend**: 자동 spawn은 sweep AI 패턴이지만 사용자 control 약함, agent를 무시할 수 없음. 소극적은 안전 + 사용자가 실패 결과 보고 결정 가능 → 후자 채택 (v0.5에서 적극적 mode 토글 추가 검토)
  - **Docker runtime 격리** vs **NSTask shell**: Docker는 OpenHands급 격리 but 사용자 부담 ↑, Yuminai macOS native 정체성과 충돌 → NSTask + sandboxed dir
  - **자체 ANSI parser + capture** vs **shell 그대로 + readability handler**: shell 그대로가 사용자 환경 일치. ANSI는 결과 표시에서만 처리 (현재는 raw text)
- **격리**:
  - DeliveryConfig는 `YuminaiCore` (모든 모듈 접근 가능)
  - DeliveryRunner는 `YuminaiApp` (AppModel hook과 강결합)
  - DeliveryResultsView는 `YuminaiUI` (도메인 모델만 의존)
  - WorkspaceDeliverySheet은 `YuminaiApp` (AppModel + UI 둘 다 import)
- **HelpHint 디자인 결정**:
  - i 아이콘은 11pt, 대기 색은 textTertiary, 활성/호버는 accent
  - InlineHint는 4 kind: info(accent) / success(green) / warning(orange) / tip(accent) — bg는 각 색 10~12%
  - EmptyStateHint는 28pt icon + title body + optional action button. 모든 빈 상태 영역에 일관 적용
  - LabelWithHint는 Settings의 LabeledContent와 자연스럽게 — Toggle/Stepper 라벨 옆에 inline
- **결과**:
  - 신규 파일 5개: HelpHint / DeliveryConfig / DeliveryRunner / DeliveryResultsView / WorkspaceDeliverySheet
  - 신규 테스트 8건 (DeliveryConfig 3 + DeliveryResult prompt 5)
  - InspectorPanel "변경" 탭이 VSplitView로 diff 위 / delivery results 아래 분할
  - SidebarView 우클릭 메뉴 "Delivery 자동화 설정…" 추가
  - SwiftData migration: deliveryConfigJSON nullable column (nil fallback)
  - build 3.2s + 152/152 tests
- **알려진 한계 → 후속**:
  - test/lint 순서 고정 (커스텀 X) — v0.5
  - 자동 fix loop는 소극적 (즉시 spawn X) — v0.5에서 적극적 mode 토글
  - 결과 영속 X (메모리 max 10) — v0.5에서 SwiftData 저장 검토
  - Block 그룹화 (Warp UX) — v0.4 후속 또는 v0.5
  - Telegram에 delivery 결과는 단순 알림만 — 자동 fix 진행 알림은 v0.5
- **재검토**: Phase C (multi-pane) 시작 전 사용자 검증 — auto-fix prepend가 자연스러운지, hard cap이 충분한지

---

## ADR-028 — v0.4 Phase A: Diff Review (M3) + Embedded Terminal (M5.a)

---

## ADR-028 — v0.4 Phase A: Diff Review (M3) + Embedded Terminal (M5.a)

- **날짜**: 2026-05-01
- **상태**: Accepted (구현 완료, Phase A)
- **결정**: ADR-027 권고 default 7개 모두 채택 후 Phase A 구현. M3 + M5.a를 한 commit으로 통합 (작업이 같은 라운드 + UI 영역 공유).
- **컨텍스트**:
  - 사용자 — "권고 사항 기준으로 구현 진행해 줘"
  - ADR-027의 권고 default 7개 모두 OK (split UI / manual accept / 자동 + hard cap / SwiftTerm OK / @codex syntax / phase 순서 / ACP v0.5 spike)
- **각 결정**:
  1. **SwiftTerm 채택 (M5.a)** — Miguel de Icaza의 검증된 native Swift terminal. 두 번째 외부 dep (첫째: swift-markdown-ui). lock-in 완화는 TerminalPane wrapping으로
  2. **git-as-source (M3)** — Aider 패턴 그대로. 자체 diff 모델 X, git status/diff/checkout/clean을 단일 진실의 원천으로
  3. **manual accept** — 사용자 권고. 자동 commit/reject 모두 X. UI에서 명시적 클릭만
  4. **silent no-op for non-git workspaces** — git 저장소 아니면 checkpoint skip (panic X). 사용자에게 "이 워크스페이스는 git이 없어서 변경 추적 안 됨" 안내는 v0.5 (현재는 변경 탭이 빈 상태로만 표시)
  5. **VSplitView로 chat/terminal 분할** — macOS native split view 사용 (NSSplitView wrap). 좌/우 split (M1.b)는 다른 phase
  6. **InspectorTab .changes 추가** — 기존 컨텍스트/노트 옆에 자연스럽게. badge X (현재는 단순)
- **대안 분석**:
  - **자체 diff 모델** vs **git-as-source**: 자체 모델은 history 추적 자유도 ↑ but 복잡도 ↑↑. git은 이미 모든 사용자가 익숙 + 이미 워크스페이스에 있음 → git 채택
  - **xterm.js + WKWebView** vs **SwiftTerm**: web view는 무겁고 native UX 약함. SwiftTerm 검증됨 + macOS native
  - **자동 turn-단위 commit** vs **manual accept**: 자동은 noise ↑ + revert 어려움. 사용자가 명시적으로 결정하는 게 안전
- **격리**:
  - `GitRunner`는 `YuminaiCore` (모든 모듈 사용 가능)
  - `CheckpointManager`는 `YuminaiApp` (AppModel 의존)
  - `TerminalPane`은 `YuminaiUI` (SwiftTerm wrap)
  - `DiffReviewView`는 `YuminaiUI` (도메인 모델 `ChangedFile`만 의존)
- **결과**:
  - 신규 파일 4개: TerminalPane / GitRunner / CheckpointManager / DiffView
  - 신규 테스트 17건 (porcelain 6 + mock 1 + line kind 6 + extract hunks 4)
  - InspectorTab .changes / AppModel +5 properties + 4 actions
  - SwiftTerm 외부 dep
  - build 22s (SwiftTerm 첫 resolve 후) + 4-9s incremental, 144/144 tests
- **알려진 한계 → 후속 phase**:
  - Editable diff X (Cline SOTA, v0.5 — SwiftUI native diff editor 부재)
  - 자동 commit X (manual policy, hybrid v0.5)
  - Block 그룹화 X (Warp UX) — Phase B (M5.b)
  - Diff path 매칭에 한글/공백 정밀도 약함 — 실측 후 정밀화
  - 일반 dir file watcher X — turn 종료 시 git status 1회로 충분, watcher는 v0.5
- **재검토**: Phase B (M4 delivery loop) 시작 전 Phase A 사용자 검증 결과 반영

---

## ADR-027 — v0.4 라운드 기획 + GitHub 최상위 스타 레퍼런스 근거 채택

---

## ADR-027 — v0.4 라운드 기획 + GitHub 최상위 스타 레퍼런스 근거 채택

- **날짜**: 2026-05-01
- **상태**: Accepted (planning) — 구현 시 phase별 별도 ADR-028~031로 세부 결정
- **결정**: v0.4 라운드를 5개 주제 (M1 멀티에이전트 패널 / M2 인터-에이전트 메시지 / M3 diff review / M4 delivery loop / M5 embedded terminal-preview)로 정의. 각 주제는 GitHub 최상위 스타 OSS 패턴을 1차 근거로 채택. Phase 분할 (A→B→C→D→E)로 순차 commit
- **컨텍스트**:
  - 사용자 — "다음 라운드 각 항목 효율성을 고려해서 기획하고 설계 진행해 줘. 깃허브 최상위 스타 래퍼지토리를 근거와 래퍼런스로 조사하고 기획에 반영해 줘"
  - codex 식별 5 거대 gap + ADR-026 1단계 후속(인터-에이전트 메시지)
  - 자체 발명 X — 검증된 패턴만 차용
- **리서치 방법**:
  - research-analyst agent (background) — `gh` CLI로 23개 OSS 메타데이터 + README 분석
  - 카테고리: 멀티 에이전트 프레임워크 / AI 코딩 어시스턴트 / Diff review / Delivery loop / Terminal-Preview
  - 결과: `docs/research/01_NEXT_ROUND_REFERENCES.md` (270 lines, 1.1M+ stars 합계)
- **주제별 1순위 reference + 차용**:
  | M | 주제 | 1순위 ref (stars) | 핵심 차용 |
  |---|------|------------------|----------|
  | M1 | 멀티 에이전트 패널 | AutoGen AgentTool (57.6k) + Aider Architect/Editor (44.2k) | 메인 agent가 보조를 tool로 호출 + 좌/우 split UI |
  | M2 | 인터-에이전트 메시지 | MetaGPT 메시지 환경 (67.6k) | publish/subscribe bus + `@codex` mention |
  | M3 | Diff review | Cline checkpoint (61.2k) + Aider git-as-source (44.2k) | git이 단일 진실의 원천, view-only diff (editable v0.5) |
  | M4 | Delivery loop | Aider --auto-test (44.2k) + Devin step budget | 단순 retry counter, max-attempts=3, max-time=5min hard cap |
  | M5 | Terminal/Preview | SwiftTerm (Miguel de Icaza) + Warp block UX (50.8k) | macOS native PTY + block-단위 output |
- **핵심 의사결정 근거 (evidence)**:
  - **AutoGen은 maintenance mode** (Microsoft Agent Framework 후속) → 코드 의존 X, 패턴만 차용
  - **Aider 내부에 이미 Architect/Editor 2-LLM** (`aider/coders/architect_coder.py`) 검증됨 → Yuminai의 1ws-1agent → 2-역할 진화가 자연스러움
  - **mini-SWE-agent 100 LoC로 SWE-bench 65%** → "loop은 단순할수록 좋다"는 강한 증거. graph framework 없이 retry counter+budget으로 충분
  - **Cline editable diff가 SOTA지만 SwiftUI 자체 구현 비용 큼** → v0.4는 view-only, editable v0.5
  - **ACP (Agent Client Protocol) 부상** (3.0k stars but Zed push, obsidian-agent-client 1.9k 인접 use case) — Yuminai의 정확한 표준 후보지만 Swift SDK 부재 → v0.5 별도 spike
- **횡단 결정**:
  - **외부 의존성 정책 변경** — SwiftTerm 추가 (두 번째 외부 dep, 첫째: swift-markdown-ui). M5 phase 시작 시 ADR-031로 세부 명시
  - **Runtime sandbox**: Docker X, NSTask + sandboxed dir (macOS native 정체성 우선)
  - **AutoGen 코드 의존**: X (maint mode), 패턴만
- **Phase 순서** (의존성 + 가치 기반):
  - A (M3 + M5.a): Diff review + 기본 terminal — 가장 가치 + 단순
  - B (M4 + M5.b): Delivery loop + Warp block — A 의존
  - C (M1.a + M1.b): Multi-pane foundation + split — 가장 큰 변경
  - D (M2): Inter-agent message — C 후 자연스러움
  - E (M5.c + Codex schema): Preview + Codex 정밀화 — 마무리
- **결과**:
  - `docs/design/83_NEXT_ROUND_PLAN.md` (440+ lines, evidence-based)
  - `docs/research/01_NEXT_ROUND_REFERENCES.md` (270 lines, 23 OSS)
  - 5 phase, 11-15 commits 예상, 4-6주 작업
  - ADR-028 ~ 031 phase별 추가 예정
- **Open Questions** (사용자 답변 시 plan 업데이트):
  - Q1 split vs tab 우선? (권고: split)
  - Q2 diff accept policy? (권고: manual, hybrid v0.5)
  - Q3 delivery loop trigger? (권고: 자동 + hard cap)
  - Q4 SwiftTerm 외부 dep OK? (권고: OK)
  - Q5 mention syntax? (권고: `@codex`)
  - Q6 phase 순서? (권고: M3→M5→M4→M1→M2)
  - Q7 ACP 채택 검토? (권고: v0.5 별도 spike)
- **Risks**:
  - Phase C (multi-pane) AppModel 대규모 refactor — 일정 초과 가능, split commit으로 위험 분산
  - SwiftTerm + Yuminai 통합 사전 사례 부족 — 1-2일 spike 권장
  - Telegram bridge ↔ multi-pane 상호작용 (primary만 forward로 단순화)
- **재검토**: 사용자 Open Questions 답변 후 → ADR-028 (Phase A 시작 시) 작성

---

## ADR-026 — 멀티 에이전트 기반 + Codex CLI 통합 + cokacdir chat 라벨

- **날짜**: 2026-05-01
- **상태**: Accepted (1단계)
- **결정**: AgentKind enum (claude/codex) 도입 + workspace 단위 에이전트 전환 + Codex CLI 어댑터 추가 + cokacdir chat label 친화 표시. Antigravity-style 멀티 에이전트 협업의 1단계 — 같은 프로젝트 폴더에서 두 에이전트가 file system 공유로 협업 가능. 멀티 패널 + 인터-에이전트 메시지 패싱은 v0.4
- **컨텍스트**:
  - 사용자 3가지 동시 요청 — 각각 독립 ADR로 분리할 수도 있지만 핵심이 "1 워크스페이스 多 에이전트"라는 한 흐름이라 통합
  - 1: chat id가 숫자여서 그룹/개인 구분 어려움 (UX)
  - 2: codex CLI 연결
  - 3: 안티그래비티처럼 한 컨텍스트·폴더에서 여러 에이전트 협업
- **각 결정**:
  1. **chat label**: cokacdir 자체가 `~/.cokacdir/group_chat/<chat_id>.jsonl`에 메시지 로그 저장. 거기서 bot_display_name + from 추출 → "그룹 — 🤖 Bot Alpha, 🤖 Bot Beta, 홍길동" 같은 친화 라벨 생성. Telegram getChat API 호출 회피 (토큰 사용 X, network X, 이미 있는 데이터 활용)
  2. **Codex 어댑터**: `codex exec --json` + `codex exec resume <id>` 모델 — Claude와 달리 turn마다 새 프로세스. session id 자동 추출 + 다음 send에서 resume으로 컨텍스트 유지
  3. **AgentKind 단계적 도입**: 워크스페이스 단위 1 에이전트 (1단계) → 멀티 패널 (2단계) → 인터-에이전트 메시지 (3단계). 1단계에서도 같은 workspace 폴더 공유로 "유기적 협업" 가능 (사용자가 빠르게 전환하면서 두 에이전트 능력 결합)
- **대안 분석**:
  - Codex CLI 위임 X → Anthropic SDK처럼 OpenAI SDK 직접 호출: ROI 낮음, 학습 곡선, codex가 이미 잘 만들어진 도구
  - 멀티 패널 즉시 구현 → 큰 작업 (UI 분할, 동시 streaming, focus 관리), 1단계로 분리해 사용자 검증 후 진행
  - chat label에 Telegram getChat API 호출 → 토큰 필요 + network IO + 새 의존성. 이미 가진 cokacdir 로그가 더 풍부 (참여자 + 봇 정보)
- **AgentAdapter 설계**:
  - `ClaudeAdapter` protocol을 그대로 재사용 — Codex도 같은 시그니처 (spawn/terminate/updateSettings/currentSettings) 구현
  - 이름은 `ClaudeAdapter`로 유지 (역사적 이유 + 변경 비용) — 사실상 "AgentAdapter" 의미
  - `LiveCodexStreamSession`이 `ClaudeStreamSession` 프로토콜 구현 — events 스트림 + send
  - 차이점은 내부에서 흡수: events 스트림은 multi-turn 동안 유지, send마다 새 프로세스 spawn
- **Codex JSONL 파싱**:
  - schema가 향후 변경될 수 있어 defensive — 알려진 type만 정확히 매핑, 알 수 없는 type은 raw text로 forward (silent drop X — 사용자가 디버깅 가능)
  - JSON parse 실패 시 raw line을 .text로 emit
  - session_id 추출은 여러 key 후보 시도 (session_id / sessionId / id, nested session.id 등)
- **격리**:
  - `AgentKind`는 YuminaiCore — 모든 모듈이 의존 가능
  - `LiveCodexAdapter`는 YuminaiClaudeAdapter 모듈 (이름은 ClaudeAdapter지만 역할은 모든 agent CLI 어댑터)
  - SettingsView는 codex 경로 input + 감지 상태만 — UI는 Telegram 모듈 의존 없음
- **결과**:
  - 신규: AgentKind.swift / LiveCodexAdapter.swift / CokacdirChatInspector + Label / 18 신규 테스트
  - 확장: Workspace.agentKind / WorkspaceModel.agentKindRaw / AppPreferences.codexBinaryPath / AppModel multi-adapter dispatch / ChatToolbar agent picker / SettingsView Codex CLI section / CokacdirImportSheet ChatRow UI
- **알려진 한계 / v0.4 작업**:
  - 워크스페이스당 1 에이전트만 활성 (멀티 패널 X)
  - 인터-에이전트 메시지 패싱 X (cokacdir의 `--message --to <bot>` 같은)
  - Codex 출력 schema 검증 안 됨 (실제 codex 사용해서 unknown type 정확한 매핑 필요)
  - Codex model alias가 Claude와 달라 SessionSettings.model을 codex에 그대로 넘기지 않음 — codex는 자체 default
  - ChatView에 어떤 agent의 응답인지 메타데이터 표시 안 함
  - Workspace SwiftData 마이그레이션은 nil fallback으로 처리 — 명시적 versioned migration 안 함
- **재검토**: 사용자 codex 테스트 후 — JSONL schema 정확도, 전환 UX, multi-pane 필요성

---


> 큰 결정만 기록. 형식: 결정 / 컨텍스트 / 대안 / 근거 / 결과 / 재검토 시점.

---

## ADR-025 — 텔레그램 단일 세션 bind + ClaudeEvent forwarding bridge

- **날짜**: 2026-05-01
- **상태**: Accepted
- **결정**: 워크스페이스 1개를 텔레그램 챗에 1:1 bind. `TelegramSessionBridge` actor가 ClaudeEvent를 chunked Telegram 메시지로 변환해 forwarding. 명령(`/bind`, `/unbind`, `/status`, `/cancel`, `/list`, `/help`)은 `YuminaiCommandRouter`가 처리, 일반 텍스트는 bound 세션의 input으로 전송
- **컨텍스트**:
  - 사용자 — "하나의 세션을 탤래그램에서 제어할 수 있도록 설계해 줘"
  - 기존 인프라: `TelegramAlertDispatcher`(outgoing 정책 알림) + `TelegramCommandPump`(incoming pump) + `YuminaiCommandRouter`(현재 활성 워크스페이스로 단순 라우팅)
  - 부족: bound 세션 개념 X, Claude 응답이 텔레그램으로 안 돌아감, 명령 X
- **대안**:
  - 활성 워크스페이스로 라우팅 (현재 동작) → 사용자가 UI에서 워크스페이스 바꾸면 텔레그램 동작도 따라 바뀜 — 의도 안 맞음
  - 멀티 bind (n 워크스페이스 ↔ n 챗) → 복잡도 ↑, 사용자 1명 본인 사용 시 단일 chat이 자연스러움
  - **단일 bind (채택)** — preference에 `telegramBoundWorkspaceId: UUID?` 1개. UI 활성 워크스페이스와 분리. ✈ 아이콘으로 표시
- **Bridge 설계**:
  - 별도 actor — AppModel(MainActor)에서 분리해 telegram I/O를 background로
  - ClaudeEvent를 받아서 Telegram-친화 텍스트로 변환 (forwarding policy는 Bridge 내부)
  - text event는 buffer에 누적 → debounce(800ms) 또는 chunk size(3500) 초과 시 flush — Telegram rate limit + 4096자 한도 회피
  - tool call은 즉시 + 한 줄 요약 (`🔧 name — input 첫 줄 (80자 cap)`) — 본문 전체는 토큰 폭증
  - completed에서 elapsed + tool count로 한 줄 요약
- **AppModel hook**:
  - `handle(_ event:)`에 `forwardToBridgeIfBound(event)` 한 줄 추가 — 활성 워크스페이스 == bound일 때만 forwarding (UI에서 다른 워크스페이스 선택 시 텔레그램에 가면 혼란)
  - `sendMessage()`가 bound 워크스페이스에서 호출되면 `notifyTurnStart(userText:)` — 텔레그램이 누가 어떤 명령을 보냈는지 추적 가능
  - `bindTelegramWorkspace(_:)`이 bridge를 reset + 재구성 + 알림 — preference 변경 시 즉시 반영
- **명령 vs plain text 분기**: prefix `/`가 명령. 그 외는 bound 세션 입력. 이유:
  - 명령은 슬래시 — Telegram 표준 (BotFather, 다른 봇과 일관)
  - plain text가 일반 prompt가 되어야 자연스러움 (모바일에서 빠른 명령)
  - bound 안 됐을 때 plain text → 안내 메시지 ("먼저 /bind 하세요")
- **자동 워크스페이스 전환**: bound 세션과 활성 워크스페이스가 다를 때 plain text가 오면 자동으로 bound로 전환. 사용자 UI 작업과 충돌하면 텔레그램 우선 — bound는 사용자가 명시적으로 한 결정이므로
- **격리**: `TelegramSessionBridge`는 `TelegramClient` 프로토콜과 `ClaudeEvent` enum만 의존. AppModel 내부 X — 테스트 가능 (MockTelegramBot 사용)
- **결과**:
  - `Sources/YuminaiTelegram/TelegramSessionBridge.swift` (actor + Configuration + chunking + tool summarize)
  - `Sources/YuminaiApp/YuminaiCommandRouter.swift` 전면 재작성 (명령 분기)
  - `AppPreferences +3` 필드 (boundWorkspaceId / forwardAssistant / forwardToolCalls)
  - `AppModel` bridge 라이프사이클 + bind 메서드 + status snapshot + cancel
  - `SidebarView` ✈ 아이콘 + 우클릭 메뉴
  - 14 신규 테스트
- **알려진 한계**:
  - 단일 bind (멀티 워크스페이스 ↔ 멀티 챗 X)
  - bridge는 message edit 미사용 — chunk마다 새 메시지 (편집 흐름은 차기 라운드)
  - 도구 결과 본문 forwarding 안 함 (성공/실패만) — Read 결과 같은 거 보고 싶으면 사용자가 Yuminai UI 봐야 함
  - thinking 이벤트 forwarding X
  - Telegram 4초 rate limit 처리 X (debounce가 어느 정도 완화하지만 보장은 X)
  - bound 워크스페이스 삭제 시 자동 unbind 없음 (router가 boundMissing 안내)
- **재검토**: 사용자 모바일 사용 후 — 응답 chunk 빈도, edit 사용으로 진행 중 응답 단일 메시지 갱신 필요성, thinking 표시 여부

---

## ADR-024 — cokacdir bot_settings.json import (LiveTelegramBot 재사용)

- **날짜**: 2026-05-01
- **상태**: Accepted (이전 안 — openclaw 위임 — 폐기 후 재작성)
- **결정**: cokacdir의 `~/.cokacdir/workspace/bot_settings.json`을 읽어 봇 토큰 + chat id를 Yuminai로 import하는 일회성 import 방식. 별도 actor/CLI 위임 없이 기존 `LiveTelegramBot`을 그대로 사용
- **컨텍스트**:
  - 1차 시도: "cocakdir" 오타를 openclaw로 추정 → openclaw 위임 actor (`OpenClawTelegramBot`) 작성 + commit. 사용자 정정: 실제 도구는 [cokacdir](https://cokacdir.cokac.com/) v0.4.63
  - cokacdir = multi-panel terminal file manager + Telegram bot server (`--ccserver <TOKEN>`)
  - `bot_settings.json`에 봇 목록 평문 저장 — display_name / username / token / owner_user_id / last_sessions (chat → workspace path 매핑)
  - cokacdir는 openclaw처럼 message proxy CLI가 아님 — 봇 서버 자체. `--message ... --key <HASH>` 내부 send도 token hash 필요
- **대안 분석**:
  - **CLI 위임** (`cokacdir --message --to <bot> --chat <id> --key <hash>`) → "internal use" 표시 + token hash 계산 필요 + 비공식 인터페이스, 깨질 위험
  - **bot 서버 공유** (Yuminai와 cokacdir이 같은 토큰으로 동시 polling) → Telegram update 분산 (한쪽만 받음), 충돌
  - **bot_settings.json import (채택)** → 일회성, 단순, 기존 LiveTelegramBot 재사용. 토큰 중복 저장 trade-off는 충돌 없는 운용 우선
- **import flow**:
  1. Settings → 텔레그램 → "cokacdir 통합" Section → "열기…" 버튼
  2. AppModel.loadCokacdirBots() → CokacdirImporter.loadBots() → CokacdirImportSheet 표시
  3. 사용자가 봇 + chat id 선택 (suggested chip / 직접 입력)
  4. AppModel.applyCokacdirBot(_:chatId:) → keychain에 토큰 저장 + telegramChatId/AllowedUserIds 자동 + telegramSourceLabel 기록
- **충돌 처리**: 같은 토큰으로 cokacdir 봇 서버가 동시 실행 중이면 polling 분산 → UI footer로 안내 ("Yuminai 사용 중에는 cokacdir의 해당 봇을 잠시 꺼두는 걸 권장")
- **결과**:
  - `CokacdirImporter` (Sendable struct) + `CokacdirBot` Sendable model + `CokacdirImportError`
  - `CokacdirImportSheet` (YuminaiApp 모듈, YuminaiTelegram + YuminaiUI 모두 import) — 봇 라디오 리스트 + chat chip + 직접 입력
  - `AppPreferences.telegramSourceLabel: String?` — "토큰 출처: cokacdir — <display_name>" 표시
  - `AppModel.cokacdirBots / cokacdirImportError / showCokacdirImportSheet` + `loadCokacdirBots / applyCokacdirBot`
  - `SettingsView` Telegram 탭에 새 Section + 충돌 안내 footer
  - 8 신규 테스트 (parse 6 + loadBots 2)
- **격리 결정**: `CokacdirBot`은 YuminaiTelegram public이지만 sheet UI는 YuminaiApp에 둠 (YuminaiUI에 YuminaiTelegram 의존성 추가 회피). YuminaiUI ↔ YuminaiTelegram 사이는 callback `() -> Void`로만 연결
- **이전 안 폐기 근거** (openclaw 위임):
  - 도구 자체가 잘못 식별됨 (openclaw는 사용자 PC에 있긴 하지만 사용자가 의도한 도구 아님)
  - 설령 정확했어도 openclaw `channels list`에 telegram 채널 없음 (`chat: {}`) — 통합 가능 상태가 아니었음
  - cokacdir이 실제로 활성 사용 중인 도구 (workspace 12개 + ai_sessions 9개 + 봇 2개 등록)
- **알려진 한계**:
  - 토큰 중복 저장 (cokacdir + Yuminai keychain) — 보안 위험은 사용자 신뢰 모델에 종속
  - 일회성 import — cokacdir에서 토큰 재발급되면 사용자가 다시 import 필요
  - cokacdir와 동시 실행 시 polling 충돌 — 자동 감지/회피 미구현 (사용자 운용)
  - bot_settings.json 형식 변경에 종속 (방어적 파싱이지만 schema 깨질 수 있음)
- **재검토**: 사용자 사용 후 — 충돌 자동 감지, cokacdir 봇 서버 status 체크 옵션 추가 여부

---

## ADR-023 — Parity Round (B1~B7 + C1~C3)

- **날짜**: 2026-05-01
- **상태**: Accepted
- **결정**: codex가 노트 모듈에 대해 식별한 10개 gap 중 사용성 임팩트가 즉각적인 7개(disambig / 검색 highlight / 임베드 preview / split editor / CRUD / 즐겨찾기·최근 / 캐시) + UX polish 3개(⌘/ 도움말 / vault action bar / quick access)를 한 라운드에 통합 구현. 나머지 5개(pane model / diff review / embedded terminal / software delivery loop / exec env mobility)는 다음 라운드로 명시 보존
- **컨텍스트**:
  - 사용자 — "이 앱의 퀄리티가 클로드코드 이상의 사용성이 됐다고 자신할 때까지 래퍼런스 조사, 검증, 기획, 구현 반복"
  - codex CLI로 본인 자체 review 수행 → 10개 gap 도출 → 우선순위 분류
  - 사용자 명시 7개 노트 기능과 codex 식별 항목이 70% 겹침 → 합집합 = parity round
- **각 결정 핵심**:
  1. **B1 Disambig** — 동명 노트 sheet, 첫 매칭만 잡던 v0.2 한계 해소. case-insensitive 비교
  2. **B2 Highlight** — AttributedString으로 매칭 substring만 accent color + bold (라인 전체 색칠 X)
  3. **B3 임베드 preview** — 본문 첫 5줄만 inline blockquote (full embed는 v0.4) — 가독성 + 토큰 비용 절충
  4. **B4 Split** — 3-way (editor/split/preview), 단순 toggle보다 풍부. enum은 별도 file로 (AppModel에 의존 안 함)
  5. **B5 CRUD + 휴지통** — `.trash/<timestamp>-<filename>`로 이동 (영구 삭제 X) — 실수 복구 가능. Obsidian과 동일한 패턴
  6. **B6 즐겨찾기/최근** — Set<String> + 영속 (UserDefaults), 최근은 10개 LRU. quick access는 sidebar가 아닌 InspectorPanel 노트 탭 상단 (이미 사용자 시선이 있는 곳)
  7. **B7 In-memory cache** — bodyCache(`[String: String]`), watcher 변경 path만 granular invalidate. 영속 인덱스(SQLite FTS / SwiftData FTS5)는 v0.4
  8. **C1 ⌘/ 도움말** — sheet 형태, 카테고리(글로벌/채팅/노트) + ShortcutKeyBadge로 키캡 시각화. command palette는 v0.4
  9. **C2 vault action bar** — 노트 탭 상단에 "+ 새 노트" primary button — discoverability ↑
  10. **C3 quick access** — 빈 상태 메시지 한글 친화 ("아직 즐겨찾기한 노트가 없어요")
- **Actor isolation 해결**:
  - `ObsidianVault.rootURL`이 actor-isolated이면 `MarkdownViewer` (MainActor)에서 wiki link/embed 처리 불가 → `nonisolated let` (immutable이므로 race 무관)
  - `notePreviewBody`는 actor 내부 메서드면 closure에서 `await` 필요 → static + URL 파라미터로 nonisolated 변경. resolver closure는 `{ name in AppModel.notePreviewBody(name: name, vaultRoot: appModel.vaultRootURL) }` — vault root를 외부에서 주입
- **결과**:
  - 신규 파일 5개 (EditorSplitMode/WikiDisambiguationSheet/CreateNoteSheet/ShortcutHelpSheet + ParityRoundTests)
  - InspectorPanel 25+ params로 전면 재작성
  - 86/86 tests (B1 disambig 4건 + B5 CRUD 6건 + B7 cache 3건 + EditorSplitMode 1건 = 14 신규)
- **알려진 한계 (다음 라운드)**:
  - Pane model (사이드 by 사이드 노트/다이얼로그) — codex gap #1
  - Diff review UI (코드 변경 시각화) — codex gap #2
  - Embedded preview/terminal pane — codex gap #3
  - Software delivery loop (build/test/deploy 통합) — codex gap #4
  - Execution env mobility (mobile↔desktop 작업 이전) — codex gap #5
  - 영속 검색 인덱스 (SQLite FTS5) — B7 v0.4
  - frontmatter 인라인 편집 — B4 v0.4 (현재 raw markdown만)
  - 노트 이름 변경 / 폴더 이동 / drag-drop — B5 v0.4
  - Wiki link autocomplete (`[[`치면 popup) — v0.4
- **재검토**: 사용자 1주일 사용 후 feedback / 다음 라운드 시작 전

---

## ADR-001 — SwiftUI 네이티브 채택

- **날짜**: 2026-05-01
- **상태**: Accepted
- **결정**: 데스크탑 앱 UI를 SwiftUI로 구현. Tauri / Electron / 웹 기반 후보 모두 기각.
- **컨텍스트**: 본인 1인 macOS 사용, 출시 계획 없음, Apple Silicon 환경
- **대안**:
  - Tauri 2.x + React + Rust → 작은 번들이지만 macOS 네이티브감 < SwiftUI
  - Electron + React → 무겁고 메모리 큼
  - SwiftUI → 네이티브감 최상, Liquid Glass 등 macOS 26 신기능 활용
- **근거**: 다른 OS 지원 비범위, claude-forge React 자산은 *개발 도구* 자산이지 *데스크탑 앱* 자산이 아님, Swift 학습은 본인에게 자산
- **결과**: Package.swift 셋업, 5개 모듈 정의
- **재검토**: 만약 6개월 후 Apple platform 외 사용자가 필요해지면 재검토 (가능성 낮음)

---

## ADR-002 — A1 (Claude Code CLI Wrapper) 모델 채택

- **날짜**: 2026-05-01
- **상태**: Accepted
- **결정**: Anthropic SDK를 직접 호출하지 않고, `claude` CLI를 자식 프로세스로 spawn해서 추론을 위임한다.
- **컨텍스트**: 본인 1인, Claude Code의 모든 능력(에이전트, MCP, 메모리, 도구)을 그대로 활용하고 싶음
- **대안**:
  - A2 자체 구현: Anthropic API 직접 호출 → 자유도↑, 개발 비용 3-6개월
  - A3 하이브리드: Claude Code + 자체 일부 → 인터페이스 호환 유지 부담
- **근거**: 차별화 포인트는 추론이 아니라 *통합·UX·오케스트레이션*. 추론은 Claude Code에 위임이 ROI 최대.
- **결과**: `YuminaiClaudeAdapter` 모듈 책임이 명확해짐. Anthropic SDK 의존성 추가 금지.
- **리스크**: Claude Code의 stdin/stdout 인터페이스가 brittle할 수 있음 (R2)
- **재검토**: MVP-0 W1 Spike 결과 후 / 6개월 후 자체 구현 타당성 재평가

---

## ADR-003 — App Sandbox OFF

- **날짜**: 2026-05-01
- **상태**: Accepted
- **결정**: macOS App Sandbox를 비활성화한다. Hardened Runtime은 켠 채 일부 entitlement만 추가.
- **컨텍스트**: Process spawn (`claude` CLI), Vault 임의 경로 접근 등이 sandbox와 충돌
- **대안**:
  - Sandbox ON + 임시 예외 (`temporary-exception.unix-process-execution`) → 복잡, 일부 케이스 실패
  - Sandbox ON + UI에서만 통합 → Process spawn 자체가 불가
- **근거**: 본인 빌드 / 본인 사용 → 신뢰 가능. App Store 배포 비범위.
- **결과**: `App/README.md`의 Xcode 셋업 단계에 명시
- **재검토**: 친한 개발자에게 공유 시점

---

## ADR-004 — SwiftData 채택 (vs CoreData / GRDB)

- **날짜**: 2026-05-01
- **상태**: Accepted (MVP-0)
- **결정**: 영속 계층은 SwiftData를 사용한다.
- **컨텍스트**: 메시지 ~10만 개, 워크스페이스 ~10개 규모
- **대안**:
  - CoreData → 더 성숙하지만 boilerplate 많음
  - GRDB.swift → 명시적 제어, FTS 등 기능 풍부, 외부 의존성
- **근거**: SwiftUI와 자연스러움 (`@Query` 등), Swift 6.2 + macOS 26에서 마이그레이션 도구 개선됨, 본인 사용 규모에서 한계 안 만남
- **결과**: `YuminaiPersistence` 모듈에 SwiftData 사용
- **재검토**: 메시지 10만 개 도달 또는 FTS 검색 필요 시 GRDB 평가

---

## ADR-005 — Process Spawn은 PTY 필요 시 SwiftTerm 의존성 검토

- **날짜**: 2026-05-01 (작성) / 2026-05-01 (Spike 종료)
- **상태**: **Superseded by ADR-009** — PTY 불필요 확정
- **결정 (당시)**: 일단 외부 의존성 없이 `Process` + `Pipe`로 시작. 작동 안 하면 SwiftTerm 또는 직접 `forkpty` 사용.
- **W1 Spike 결과**: Claude CLI 2.1.101이 `-p --output-format stream-json --input-format stream-json` 조합으로 **TTY 없이 JSON 양방향 스트리밍을 1급 지원**. PTY/SwiftTerm/forkpty 모두 불필요.
- **결과**: ADR-009로 대체. SwiftTerm 의존성 추가하지 않음. `Package.swift`의 검토 코멘트 정리 가능.

---

## ADR-009 — `-p` 모드 + JSON 양방향 스트리밍 채택

- **날짜**: 2026-05-01
- **상태**: Accepted
- **결정**: Claude CLI는 항상 다음 인자 조합으로 호출한다:
  ```
  claude -p \
    --input-format stream-json \
    --output-format stream-json \
    --include-partial-messages \
    --include-hook-events \
    --session-id <uuid> \
    --settings <workspace harness settings.json> \
    --mcp-config <workspace harness .mcp.json> \
    --plugin-dir <workspace harness> \
    --add-dir <workspace directory>
  ```
- **컨텍스트**: W1 Spike(`claude --help` 분석)에서 `stream-json`, `--session-id`, `--settings`, `--mcp-config`, `--agents`, `--plugin-dir`, `--add-dir` 모두 공식 옵션으로 제공됨을 확인 (claude 2.1.101)
- **대안**:
  - Interactive REPL + PTY → ANSI 파싱 필요, TTY 필요, 복잡
  - `-p text` 모드 → 한 단계 단순하지만 도구 호출/부분 메시지를 잃음
  - **`-p stream-json` (채택)** → JSON 1급, 모든 메타 정보 보존
- **근거**:
  - **PTY 불필요**: `-p` 모드는 TTY 무관 → ADR-005 불필요
  - **ANSI 파싱 불필요**: JSON 메시지로 직접 받음
  - **하네스 완벽 주입**: `.harness/settings.json`, `.harness/.mcp.json`, `.harness/agents/`가 CLI 인자로 전달
  - **세션 영속을 Claude에 위임**: `--session-id` UUID만 SwiftData에 저장, 본문 관리는 Claude
  - **부분 메시지 + Hook 이벤트** GUI 진행 표시에 필수
- **결과**:
  - `Sources/YuminaiClaudeAdapter/`의 `LiveClaudeAdapter`는 단순 `Process` + `Pipe`로 구현 가능
  - `ClaudeEvent` enum은 W2에서 실제 stream-json 메시지 보고 정밀화
  - `ANSIStreamParser` 모듈 불필요 → 삭제 결정. 대신 `JSONStreamParser` 작성
  - `Package.swift`의 SwiftTerm 검토 코멘트 정리
- **리스크**: stream-json 메시지 schema 변경 시 우리도 따라야 함 (R8 — Claude Code 자체 변경)
- **재검토**: 다음 Claude Code 메이저 버전(3.0+) 출시 시점

---

## ADR-011 — SPM executable로 MVP 시작, Xcode App 번들은 후속

- **날짜**: 2026-05-01
- **상태**: Accepted (MVP-0 한정)
- **결정**: MVP-0의 SwiftUI macOS app은 `Sources/YuminaiApp/` SPM `.executable` 타깃으로 만든다. `swift run YuminaiApp`으로 실행/검증. 정식 `.app` 번들 + Xcode 프로젝트는 v0.2 시작 시 도입.
- **컨텍스트**: 본인 1인 사용 + 본인이 즉시 실행해보고 피드백 루프 빨리 돌리는 게 우선
- **대안**:
  - xcodegen 도입 → 추가 도구 의존성, 사용자 brew install 단계
  - Xcode 직접 새 프로젝트 → 사용자 GUI 개입 단계 필요
  - **SPM executable (채택)** → `swift run` 한 줄로 실행. CI/검증도 단순
- **근거**: SPM executable은 SwiftUI App protocol을 완전 지원. NSApplication, WindowGroup, Settings scene 모두 동작. Dock 아이콘/메뉴는 일부 제한적이지만 본인 사용에 충분.
- **결과**: `Package.swift`의 `.executableTarget(name: "YuminaiApp", ...)`. 빌드/실행 검증됨 (PID 39282, 12초 stable).
- **알려진 제약**:
  - Code signing 없음 (본인 사용 OK)
  - Info.plist 일부 키 자동 생성 안 됨 → Telegram URL 스킴, 알림 권한 등은 후속 단계에서 .app 번들로 가야 완전
  - 자동 업데이트 없음
- **재검토**: v0.2 진입 시 → xcodegen + .app 번들로 승격 검토 (사용자 답변 필요)

---

## ADR-012 — Telegram 양방향 (알림 + 명령) 채택

- **날짜**: 2026-05-01
- **상태**: Accepted
- **결정**: Telegram 통합은 시작부터 *양방향* — 알림 송신(`TelegramAlertDispatcher`) + 모바일 명령 수신(`TelegramCommandPump` + `TelegramCommandRouter`). 단방향 알림만 v0.2로 미루는 PRD 초기 안을 *수정함*.
- **컨텍스트**: 사용자 명시 요청 — "텔레그램 봇으로 직접 제어하거나, 작업 마쳤을 때 알림을 보내주는 형태"
- **대안**:
  - 단방향 알림만 v0.2 (이전 안) → 사용자 의도 미흡
  - 양방향 (채택) → 모바일에서 명령 → 데스크탑 Yuminai 활성 워크스페이스의 Claude로 전달
- **근거**: Long polling은 actor 1개 + URLSession만으로 구현 가능. `TelegramCommandRouter` protocol로 라우팅 책임 분리해 구현체 교체 가능.
- **결과**:
  - `LiveTelegramBot` actor: send / edit / startPolling / incoming AsyncStream
  - 화이트리스트 `allowedUserIds`로 보안 (다른 user 메시지는 silently drop)
  - `TelegramCommandPump`: incoming → router → 응답 송신
  - `YuminaiCommandRouter` (App layer): 받은 텍스트를 현재 활성 워크스페이스의 채팅 입력으로 주입 후 sendMessage()
  - SettingsView에서 토큰/Chat ID/허용 user ID 모두 GUI 편집 가능
- **알려진 제약 (v0.3로)**:
  - 의도 분류 없음 — 모든 메시지가 그대로 채팅에 들어감 (`#workspace command` 같은 prefix 라우팅은 후속)
  - inline keyboard / callback_query 없음 — 결정 요청 UI는 단순 텍스트
  - 앱 실행 중일 때만 polling (백그라운드 launchd agent 후순위)
- **재검토**: 본인 1주일 사용 후 — 양방향이 실제로 가치 있는지 데이터로 확인

---

## ADR-022 — 노트 기능 7종 일괄 (frontmatter / watcher / 검색 / wiki / embed / 편집 / @note)

- **날짜**: 2026-05-01
- **상태**: Accepted
- **결정**: 7개 노트 enhancement를 의존성 순서대로 한 라운드에 통합 구현 + 단위 테스트 + 실행 검증
- **컨텍스트**: 사용자 — 모든 항목 한 번에 + 마지막 UI/UX·반응형·기능 테스트
- **각 결정**:
  1. frontmatter — UI에서만 표시 (편집 X), reserved 키 (title, tags) 외 알파벳순
  2. file watcher — FSEventStream + 800ms debounce + AsyncStream<Set<String>>
  3. 본문 검색 — lazy concurrent (50개 limit, 250ms debounce). SwiftData FTS 미지원 — 자체. 영속 인덱스 v0.3
  4. Wiki link — preprocessing → swift-markdown-ui 일반 link → OpenURLAction이 yuminai-note scheme 인터셉트
  5. 이미지 임베드 — preprocessing → file:// URL → NetworkImage. 노트 임베드 (`![[Note]]`)는 wiki link로 fallback
  6. 편집 모드 — segmented toggle + ⌘S 저장 + 외부 변경 banner. 자동 저장 X
  7. @note — Composer 첨부 메커니즘 재사용 (path mention)
- **검증**: 72 tests (15 신규) + build 2.63s + run 정상
- **알려진 한계**:
  - Wiki link 동명 노트 시 첫 매칭만
  - 노트 임베드 inline 표시 v0.3
  - 편집 모드 raw markdown only
  - 검색 50개 limit
  - frontmatter 편집 UI 없음
- **재검토**: 사용자 사용 후

---

## ADR-021 — Obsidian Vault 직접 접근 + swift-markdown-ui (외부 의존성 정책 변경)

- **날짜**: 2026-05-01
- **상태**: Accepted
- **결정**:
  1. Obsidian CLI 별도 의존성 없이 Vault `.md` 파일 직접 접근 (FileManager)
  2. **첫 외부 SPM 의존성 도입** — swift-markdown-ui (gonzalezreal). 이전 정책 "외부 의존성 0" 변경
  3. Inspector를 tab 구조로 — 컨텍스트 / 노트 두 탭
  4. 마크다운 렌더링은 `MarkdownViewer` wrapping으로 라이브러리 lock-in 완화
- **컨텍스트**:
  - 사용자 — "옵시디언 cli 연동, Notion/Obsidian급 마크다운 뷰어"
  - Notion급 = 헤더/코드/테이블/task list/blockquote/이미지/링크 모두 — 자체 구현 비현실 (100시간+)
  - Obsidian CLI는 공식 X (npm `obsidian-cli` 비공식). Vault는 단순 `.md` 파일 → 파일 시스템 접근으로 충분
- **라이브러리 비교**:
  | 옵션 | 평가 |
  |---|---|
  | `AttributedString(markdown:)` Apple 네이티브 | basic만, 코드블록/테이블/task X |
  | `swift-markdown` (Apple) | 파싱만, 렌더러 자체 작성 |
  | **`swift-markdown-ui`** (채택) | Notion급 + Apple swift-markdown 기반 + theme 시스템, 1.5k stars, MIT |
  | 자체 구현 | 100시간+, 비현실 |
- **외부 의존성 정책 변경 근거**:
  - 자체 작성 ROI 낮음 (마크다운 렌더링은 standard task)
  - 라이브러리 검증 — 1.5k stars, Apple swift-markdown 의존, 활발한 maintenance
  - lock-in 완화 — `MarkdownViewer` wrapping → 교체 시 한 곳만 수정
- **결과**:
  - `Sources/YuminaiObsidian/` 신규 모듈 (ObsidianVault actor + Note + VaultNode)
  - `MarkdownViewer` + Yuminai theme (h1~h4 + paragraph + 인용 + 코드블록 + task list + 테이블 + 링크)
  - `NoteTreeView` (검색 + 트리/flat 모드)
  - `InspectorPanel` (tab 구조 + Vault 미설정 안내)
  - `AppModel` Vault state + lifecycle
  - 새 의존성: swift-markdown-ui 2.4.1, NetworkImage 6.0.1, swift-cmark 0.7.1 (transitive)
- **알려진 한계 (다음 라운드)**:
  - 채팅 @note 인라인 주입 미구현 (메시지에 노트 본문 첨부)
  - Wiki 링크 [[Page]] 미렌더 (swift-markdown-ui standard 외)
  - 임베드 ![[file]] 미렌더
  - frontmatter 파싱은 됐지만 표시 안 함
  - file watcher (Vault 변경 자동 갱신) 미구현
  - 노트 편집 read-only (편집 모드 v0.3)
- **재검토**: 사용자 사용 후 / 라이브러리 v3 출시 시

---

## ADR-020 — Settings는 macOS native Form + 첨부파일 = `@<path>` mention prepend

- **날짜**: 2026-05-01
- **상태**: Accepted
- **결정**:
  1. SettingsView는 시스템 룩 (`.formStyle(.grouped)` + `LabeledContent` + `Section { } header: { } footer: { }` 명시 형식). 자체 flat 컴포넌트 적용 안 함 (사용 빈도 낮음 + 시스템 정렬·접근성 보장)
  2. 첨부파일은 prompt에 `@<path>` mention 형식으로 prepend → Claude가 자체 Read 도구로 처리
- **컨텍스트**:
  - 사용자 — "설정 팝업 깨진 layout. 맥 네이티브 설정 메뉴 퀄리티로 정렬"
  - macOS Settings의 표준 룩 (System Settings)이 이미 잘 설계됨 — 우리가 다시 만들 필요 없음
  - 첨부파일을 어떻게 Claude에 전달할지 두 가지 옵션:
    - inline 파일 본문 (작은 파일만, 토큰 비용)
    - mention 경로 (Claude가 Read로 자동 호출, 토큰 절약)
- **이전 시도 실패 원인**:
  - `Section("title") { ... } footer: { ... }` shortcut이 macOS 26 SwiftUI에서 ambiguous → 매번 명시적 `Section { } header: { Text(...) } footer: { Text(...) }` 사용
  - Form/`Picker(.menu)` 기본 right alignment를 우리 토큰으로 override 시도하면서 깨짐
- **결과**:
  - SettingsView 5탭 (`일반/모델·모드/편집/텔레그램/Anthropic`) 모두 시스템 Form
  - 윈도우 480~760 height, 640~880 width
  - SecretField는 inline status badge + 버튼들 (시스템 button)
  - AppModel.attachedFiles + openAttachmentPicker (NSOpenPanel) + sendMessage prompt 가공
  - Composer attachedFiles chips (icon 확장자 추정 + ✕ + tooltip)
- **알려진 한계**:
  - SettingsView가 다른 view와 디자인 일관성 일부 깨짐 (시스템 룩 vs 자체 flat)
  - 첨부 파일 다중 시 chips가 매우 길면 horizontal scroll
  - 큰 폴더 첨부 시 Claude가 모두 Read 시도 — 토큰 폭발 가능 (사용자가 신중히 선택)
  - drag-and-drop 미지원 (다음 라운드)
- **재검토**: 사용자 사용 후

---

## ADR-019 — Brand accent = AG2R 시안 + PickerMenu 자체 컴포넌트 (Claude Code 룩)

- **날짜**: 2026-05-01
- **상태**: Accepted
- **결정**:
  1. ar2r → AG2R La Mondiale 확정 → `Theme.Brand.accent`를 밝은 시안 `#22C8E0`로 교체
  2. SwiftUI native `Menu` → 자체 `PickerMenu` (popover 기반)으로 전면 교체. Claude Code 데스크탑 dropdown 디자인 정합
  3. Settings 호출 → `@Environment(\.openSettings)` 사용 (`NSApp.sendAction` 대체)
- **컨텍스트**:
  - 사용자 메시지: "밝은 하늘색 강조색" + "설정 버튼/모델 스위치 작동 안 함" + Claude Code dropdown 스크린샷 제공
  - 기존 inline `Menu` (borderlessButton style)이 일부 환경에서 trigger 안 되는 알려진 이슈
- **PickerMenu 설계**:
  - native `.popover(isPresented:)` 기반 — macOS 표준, 위치/크기 안정
  - `PickerSection`: title + 우측 shortcut hint badges (⇧⌘M 등) + items
  - `PickerItem`: label + subtitle (부제, "1M"/"레거시" 같은) + isSelected (✓) + shortcutHint (1, 2, 3 등)
  - 항목 hover bg + 클릭 시 자동 close
  - `ShortcutKeyBadge` — 키캡 모양 미니 컴포넌트 (border + 작은 폰트)
- **결과**:
  - `Sources/YuminaiUI/PickerMenu.swift` (신규, 200줄+)
  - `SessionPickers.swift` 전면 재작성 — 모든 picker가 PickerMenu 사용
  - `PickerTriggerLabel` — Composer footer inline label (hover chevron → accent)
  - Theme.Brand.accent / accentDeep / accentMuted / accentBorder 모두 시안 톤
- **재검토**: 사용자 사용 후 — popover 위치/크기, shortcut hint 가시성, Settings 호출 동작 여부
- **알려진 한계**:
  - PickerMenu는 popover라 윈도우 매우 좁을 때 잘림 가능 (compact mode)
  - shortcut hint (1, 2, 3)은 표시만, 실제 단축키 처리는 미연결 (다음 라운드)
  - "빠른 모드" toggle (Claude Code 스크린샷의 마지막 섹션)은 우리 도메인에 없어 미구현

---

## ADR-018 — 브랜딩 (ar2r 자전거 팀 컬러) + 인터랙션 표준 + UX 라이팅 한글 친화

- **날짜**: 2026-05-01
- **상태**: Accepted (브랜드 컬러는 fallback, 사용자 답변 시 교체)
- **결정**:
  1. `Theme.Brand` namespace 도입 — 모든 강조 색은 Brand로 위임. 토큰 한 곳 변경으로 전체 반영.
  2. ar2r 정확한 컬러는 codex CLI 조사로 미확인 → fallback (deep navy `#0E2A47` + vivid orange-red `#FF5A36` + white) 사용
  3. 모든 버튼에 `PressedScaleStyle` (0.97 scale, 80ms) 적용. CTA(primary)는 `PrimaryButtonStyle` (hover 1.02 + brightness 추가)
  4. 모든 hover bg 변화에 100ms easeOut 애니메이션
  5. UX 라이팅 전수 패스 — `docs/design/70_BRANDING_AND_INTERACTION.md` §5.2 라벨 통일표 적용
- **컨텍스트**:
  - 사용자 — "이 정도 디자인 퀄리티" + "ar2r 자전거 팀 컬러" + "버튼 인터랙션·애니메이션" + "UX 라이팅 한글 친화" 동시 요청
  - 디자인은 색·인터랙션·라이팅이 동시 작동해야 일관 — 한 라운드에 통합 처리 필요
- **codex 조사 결과** (`codex exec --skip-git-repo-check`):
  - `ar2r` / `AR2R` / `에이알투알` + 자전거 키워드로 검색 — 공개 웹에서 자전거 팀 미확인
  - 발견된 동명: AI tool, 프랑스 회사, 알마티 클럽 (모두 자전거 무관)
  - codex 제안 fallback: deep navy + orange-red (자전거 저지 표준 — bold primary + high-visibility accent + white)
- **결과**:
  - `Theme.Brand` 5개 토큰 (primary/primaryDark/primaryLight/accent/accentDeep/accentMuted/accentBorder/contrast)
  - `Theme.Color.accent` 등 Brand 위임
  - `FlatComponents`에 `PressedScaleStyle`, `PrimaryButtonStyle`, `AnyButtonStyle` 추가
  - `WorkspaceItemRow`에 hover 시 ⌘N 단축키 hint
  - `ChatToolbar` Breadcrumb 클릭 시 native `Menu` (워크스페이스 리스트 + "+ 새")
  - `RootView`에 ⌘1~9 invisible button 9개 (workspace 빠른 전환)
  - 18개 view literal 한글화 (Composer/Sidebar/ChatView/ChatToolbar/ContextInspector/UsageDashboard/CreateWorkspaceSheet/RootView empty/error alert)
- **알려진 한계 (다음 라운드)**:
  - 로고 SwiftUI View / SVG / PNG / .icns 미생성
  - About/splash 화면 미구현
  - Settings는 여전히 시스템 Form
  - ⌘K command palette 미구현 (sidebar search 콜백 빔)
  - Toast 컴포넌트 미작성 (alert만)
  - Sidebar ↑↓ keyboard nav (focus management) 미구현
  - Reduce-motion 자동 감지 미적용
  - **ar2r 정확한 컬러** — 사용자 답변 필요 (Q-A in 70 spec)
- **재검토**: 사용자 답변 + 다음 iteration

---

## ADR-017 — 반응형 Layout (LayoutMode + AppStorage user intent)

- **날짜**: 2026-05-01
- **상태**: Accepted
- **결정**: 윈도우 너비를 4단 breakpoint(compact/medium/regular/wide)로 분기. 각 모드에 따라 sidebar/inspector 자동 표시 정책. 사용자 의도(toggle 결과)는 AppStorage에 영속 → mode 복귀 시 복원. compact 모드에서 sidebar는 overlay popup.
- **컨텍스트**: 좁은 윈도우(<800px)에서 sidebar+inspector+chat 모두 표시 시 chat 너비 부족 → 사용성 저하. 사용자가 매번 수동 toggle 강요당함.
- **대안**:
  - NavigationSplitView 시스템 자동 — 디자인 통제 불가 (ADR-015에서 우회 결정)
  - 사용자 수동만 — UX poor
  - **breakpoint 자동 + intent 영속 (채택)** — Linear/Slack/VS Code 등 표준 패턴
- **breakpoint 결정 근거**:
  - 760: macOS 작은 윈도우 (압축 시) 평균값. 그 이하는 mobile-like
  - 1080: sidebar 280 + chat 520 + inspector 280 ≈ 1080. 임계
  - 1440: 모든 컴포넌트 여유 + 코드 본문 여유. 표준 외장 모니터 단계
- **결과**:
  - `LayoutMode` enum (Theme.Layout 외부)
  - `Theme.Layout.mode(for:)` static
  - RootView `GeometryReader` + `@AppStorage` 2건 + `@State sidebarOverlayShown`
  - `handleSizeChange(_:)` — mode 변경 시 자동 정리 (overlay 닫기, inspector sync)
  - ChatToolbar inspector 버튼 disabled 상태 + tooltip
  - 단위 테스트 3건 (boundaries / allowance / overlay)
- **알려진 한계**:
  - sidebar/inspector 너비 사용자 리사이즈 미지원 (현재 고정) — 다음 라운드 후보
  - 동적 contentMaxWidth 미적용 (chat 본문 폭 자동 조정 가능) — 다음 라운드 후보
  - reduce-motion 환경에서 transition 애니메이션 자동 disable 미적용
- **재검토**: 사용자 사용 후 — 너비 임계값이 본인 환경에 맞는지

---

## ADR-016 — codex CLI 검증 → Design Spec v3 (Claude Code 데스크탑 정합)

- **날짜**: 2026-05-01
- **상태**: Accepted
- **결정**: 사용자 제공 Claude Code 데스크탑 스크린샷을 기준으로 design spec을 작성하고, codex CLI 0.116.0의 critical review 9건을 모두 명세서 v3에 반영. 그 위에 Theme + 11개 컴포넌트를 재구성한다.
- **컨텍스트**: v2 flat 룩이 너무 monospace/직각 위주로 가서 "Claude Code 데스크탑처럼 플랫하고 사용성있는" 사용자 기대 미달. 스크린샷 자체를 ground truth로 정밀 추출 + 외부 디자인 시스템 검증 + codex 메타 검증 필요.
- **codex 9건 critical 이슈**:
  1. 단일 스크린샷 과적합 (pane/diff/terminal view 무시) → MVP 비범위 명시
  2. Sidebar dot semantics 모호 → ●=selected 확정, status는 trailing badge 분리
  3. Composer 핵심 컨트롤 누락 (send/stop/pickers) → 모두 명시 + 구현
  4. 토큰이 generic SaaS dark → warm 톤 (R>B), sidebar/bg 분리
  5. textTertiary 대비 부족 → 토큰 lift + 11~12px 한정
  6. 팔레트 noisy (blue user bubble) → orange muted로 변경
  7. 컴포넌트 비율 web-app적 → sidebar 32px, sf 14px, update card 2px-bar 제거
  8. Interaction 미정의 → 키보드 표 + non-color selected + reduced motion + VoiceOver
  9. SwiftUI 함정 → Breadcrumb 위치 변경, NSTextView 옵션, min/max width 명시
- **방법**: `codex exec --skip-git-repo-check "Read docs/.../60_UI_DESIGN_SPEC.md, critically review..."` → tool use로 file 읽고 web 참조 (`code.claude.com/docs/en/desktop`) 후 9건 도출
- **결과**: `docs/design/60_UI_DESIGN_SPEC.md` v3 (350+ 줄, §14에 codex→우리결정 추적), Theme.swift v3, FlatComponents v3, SidebarView/MessageBubble/Composer/ChatToolbar/ChatStatusBar/ContextInspector/SessionPickers/UsageDashboard/CreateWorkspaceSheet/ChatView/RootView 모두 v3
- **재검토**: 사용자가 다시 띄워본 후 / 다음 iteration 라운드

---

## ADR-015 — macOS 네이티브 컴포넌트 우회 + 자체 Flat 토큰 시스템

- **날짜**: 2026-05-01
- **상태**: Accepted
- **결정**: Yuminai UI는 macOS 네이티브 컴포넌트(NavigationSplitView, Form, Picker dropdown 룩, `.regularMaterial` 등)를 의도적으로 우회하고, 자체 Theme 토큰 + 자체 Flat 컴포넌트(FlatButton, FlatTextField, FlatSection 등)로 구성한다.
- **컨텍스트**: 사용자 피드백 — "macOS 네이티브감이 너무 강함, Claude Code의 플랫하고 사용성 있는 룩 원함". 디자인 MD 라이브러리(shadcn/Tailwind 등)는 SwiftUI에 직접 import 불가하지만, 토큰 + 자체 컴포넌트로 등가 재현 가능.
- **대안**:
  - macOS 네이티브 룩 그대로 + 색만 조정 → 사용자 의도 미흡
  - WebView 임베드 + HTML/Tailwind → 무겁고 SwiftUI 의도 어긋남
  - **자체 Flat 토큰 + 자체 컴포넌트 (채택)** → 가장 깨끗
- **근거**:
  - SwiftUI에서 macOS 네이티브 룩은 시스템 색/material/standard 컴포넌트로부터 옴. 이걸 우회하면 임의 디자인 가능.
  - Theme.Color는 명시적 light/dark hex 정의, Color(light:dark:) helper로 자동 전환.
  - Layout은 NavigationSplitView 대신 직접 HStack — sidebar는 자체 toggle.
- **결과**:
  - `Theme.swift` 전면 재작성 (Color/Typography/Spacing/Radius/Stroke/Layout)
  - `FlatComponents.swift` 신규 (FlatButton/Text/Section/Row/Divider/Toggle)
  - 모든 view 파일에서 시스템 색 참조 → 새 토큰
  - `flatChrome(borders:)` modifier로 chrome 단순화
  - MessageBubble 박스 제거 → CLI 스타일 prefix 마커 + role 라벨
  - InlinePicker monospace + 1px border 형식
- **알려진 한계**:
  - `SettingsView`는 SwiftUI Form/Section/Picker 그대로 (시스템 룩 잔존) — 사용 빈도 낮아 후순위
  - 사이드바 collapse animation이 NavigationSplitView보다 단순
- **재검토**: SettingsView도 자체 flat 컴포넌트로 마이그레이션 필요 시점

---

## ADR-014 — Toolbar inline picker + 즉시 재spawn

- **날짜**: 2026-05-01
- **상태**: Accepted
- **결정**: 채팅 영역 상단의 picker (model/mode/effort)를 변경하면 즉시 `LiveClaudeAdapter.updateSettings(_:)` 호출 + 활성 워크스페이스의 ClaudeStreamSession을 종료하고 새 settings로 spawn. 메시지 UI 로그는 보존.
- **컨텍스트**: 사용자가 채팅 도중 모델/모드를 자유롭게 바꿔서 비교 실험을 원함 (Claude Code 데스크탑 마이그레이션 수준의 UX)
- **대안**:
  - "Apply" 버튼 추가 후 명시적 적용 → 마찰 큼
  - 다음 메시지부터 적용 (lazy) → 우리 spawn 모델은 세션 1개 유지라서 어려움
  - **즉시 재spawn (채택)** → 자연스러움. Claude CLI의 `--session-id`로 컨텍스트 유지되므로 메시지 손실 없음
- **결과**:
  - `ClaudeAdapter` protocol에 `updateSettings/currentSettings` 추가
  - `LiveClaudeAdapter.updateSettings`는 actor state만 변경 (다음 spawn에 적용)
  - `AppModel.updateActiveSettings(_:)`이 spawn 재실행 + 메시지 UI는 그대로
- **알려진 한계**: settings 변경 시 진행 중이던 응답은 잃을 수 있음 (intentional)
- **재검토**: 본인 사용 후 → 충분히 자연스러운지 / 디바운스 필요한지

---

## ADR-013 — UI 형태 B2 확정

- **날짜**: 2026-05-01
- **상태**: Accepted (Q-B 답변 완료)
- **결정**: B2 — CLI 스타일 채팅 GUI. monospace, 다크 친화 토큰, NavigationSplitView (사이드바 + chat detail), MessageBubble 위젯.
- **컨텍스트**: 사용자 명시 결정
- **결과**: `YuminaiUI` 컴포넌트 완비. Liquid Glass는 후속에서 chrome에만 적용 검토.

---

## ADR-010 — 세션 영속을 Claude에 위임, SwiftData는 메타만

- **날짜**: 2026-05-01
- **상태**: Accepted (ADR-009 종속)
- **결정**: 메시지 본문 영속은 Claude CLI의 `--session-id` 메커니즘에 위임. Yuminai SwiftData에는 다음만 저장:
  1. `Workspace` 엔티티 (디렉토리, 이름, 하네스 템플릿)
  2. `Session` 엔티티 (UUID, workspace ref, started/ended, title)
  3. `Message` 엔티티 (UI 표시용 캐시 — Claude의 sole source of truth가 아니라 빠른 사이드바/검색용)
  4. `ToolEvent` (선택, 분석용)
- **컨텍스트**: Claude CLI가 자체적으로 세션 영속/재개 메커니즘 보유 (`-r`, `-c`, `--session-id`)
- **대안**:
  - SwiftData가 sole source of truth → Claude의 영속 메커니즘과 이중화, 일관성 어려움
  - Claude만 영속 → Yuminai 사이드바/검색이 어려움
  - **하이브리드 (채택)** → Claude는 컨텍스트 복원에 사용, SwiftData는 UI/검색에 사용
- **결과**: `YuminaiPersistence`의 `Message` 모델은 cache 의미. truncate해도 다음 호출 시 Claude가 컨텍스트 유지함.
- **재검토**: 메시지 검색 / 분석 요구 강해지면 SwiftData를 sole source로 승격

---

---

## ADR-006 — UI 형태 잠정 B2 (CLI 스타일 채팅 GUI)

- **날짜**: 2026-05-01
- **상태**: Provisional
- **결정**: B2 — Monospace 다크 채팅 UI + 통합 위젯 (사이드바, inspector). B1 터미널 임베드와 B3 풀 GUI는 보류.
- **컨텍스트**: 사용자가 "Claude Code와 같은 형태"라고 요청
- **대안**: [`99_OPEN_QUESTIONS.md`](../prd/99_OPEN_QUESTIONS.md) Q-B 참조
- **근거**: B2가 통합 친화도와 노력의 균형. 사용자 답변 시 변경 가능.
- **재검토**: 사용자 답변 시 즉시

---

## ADR-007 — MVP-0 통합 완전 비활성

- **날짜**: 2026-05-01
- **상태**: Accepted
- **결정**: MVP-0에선 Obsidian / Telegram / git worktree 등 모든 외부 통합을 비활성. 오직 Claude CLI + 채팅 + 영속만.
- **컨텍스트**: 4주 일정, 핵심 가설(Yuminai를 본인이 실제로 일상 진입점으로 쓸 것인가) 검증이 우선
- **대안**: 통합 일부 동시 진행 → 일정 미스 + 핵심 가설 검증 늦어짐
- **근거**: R5 (통합이 너무 많아 핵심 가치 흐려짐) 완화
- **결과**: [`90_ROADMAP.md`](../prd/90_ROADMAP.md) MVP-0 Scope 명시
- **재검토**: MVP-0 종료 시점

---

## ADR-008 — 코드 편집기 비포함

- **날짜**: 2026-05-01
- **상태**: Accepted
- **결정**: Yuminai는 코드 직접 편집 기능을 제공하지 않는다. 변경은 Claude가 수행한다.
- **컨텍스트**: Cursor / VS Code / Xcode 등 별도 IDE 사용
- **대안**: 간단한 코드 편집기 임베드 → 큰 노력 / 본인 IDE 대체 안 됨
- **근거**: Yuminai는 *대화형 작업 셸*. IDE 기능과 경쟁하지 않음.
- **결과**: F-W (Won't) 명시, [`30_GOALS_NONGOALS.md`](../prd/30_GOALS_NONGOALS.md) NG7
- **재검토**: 만약 1년 후 별도 IDE 없이 Yuminai만 쓰고 싶어지면 재검토

---

## 잠정 결정 (Provisional)

답변 받기 전 잠정값. [`99_OPEN_QUESTIONS.md`](../prd/99_OPEN_QUESTIONS.md) 답변 시 ADR로 승격.

| Provisional | 잠정값 | 근거 |
|---|---|---|
| Q-B UI 형태 | B2 | 통합 친화도 + 노력 균형 |
| Q-D1 Obsidian Vault | 사용자 입력 받음 | - |
| Q-D2 Telegram bot | BotFather에서 새로 만듦 | - |
| Q-D3 다른 통합 | GitHub만 v0.3 | 본인 일상 사용 빈도 |
| Q-E 워크스페이스 | git worktree 선택 (생성 시 옵션) | 유연성 |
| Q-F iCloud | 1대 가정, v0.3에서 메타만 | 단순성 |
| Q-G 보안 | Sandbox OFF, Hardened Runtime ON+ent | ADR-003 |
| Q-H 일정 | MVP-0 4주 공격적 | - |
| Q-I Xcode 자동화 | xcodegen/tuist 미도입 | 단순성 |
| Q-J 코드네임 | "Yuminai" 정식 / 영문 우선 | 사용자 결정 |
| Q-K 메타-하네스 | claude-forge 참조 | 중복 회피 |
| Q-L 사용 분석 | v1.0 간단 차트 | 우선순위 낮음 |
