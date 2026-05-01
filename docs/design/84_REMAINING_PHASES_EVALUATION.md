# 84_REMAINING_PHASES_EVALUATION — Phase C 이후 권고 항목 냉정 평가

> **컨텍스트**: ADR-027 plan에서 권고한 phase 순서 (M3→M5→M4→M1→M2) 중 Phase A(M3+M5.a) / B(M4) / C foundation(M1) 완료. 남은 권고 항목을 사용성·단위 기능 측면에서 다시 평가하고 우선순위 재조정.
> **방법**: 각 항목별 가치(value) × 비용(cost) × 사용성 impact를 표로 정리 → go / defer 결정.

---

## 1. 평가 매트릭스

| ID | 항목 | 가치 | 비용 | 사용성 impact | 결정 |
|----|------|-----|------|--------------|------|
| T1 | **Panes 영속** (workspace 재진입 시 보존) | **높음** — 매번 panes 다시 만들기 비용 | 작음 (SwiftData column + serialization) | 높음 — 멀티 pane 진짜 활용 가능 | ✅ 즉시 |
| T2 | **Phase D — 인터-에이전트 메시지** (`@codex review`) | **높음** — 진짜 협업 (자동 위임) | 보통 (MessageBus + parser + UI) | 높음 — Yuminai 차별화 | ✅ 즉시 |
| T3 | **Codex JSONL schema 정밀화** | 보통 (사용 빈도 따라 다름) | 작음 (실측 데이터 보고 매핑 추가) | 보통 (codex 사용 시 정확도 ↑) | ✅ 안전 매핑 추가 (실측은 사용자 사용 후) |
| T4 | **Phase C2 — 좌/우 split layout** | 보통 — power user only | 큼 (HSplitView + focus + per-side composer) | 모호 — tab 전환으로 충분 가능 | ⏸ 보류 (사용자 요청 시) |
| T5 | **Per-pane Composer 설정** | 낮음 — tab swap이 동일 효과 | 보통 (Composer state 분리) | 낮음 — 현재 swap이 자연스러움 | ⏸ 보류 |
| T6 | **PreviewPane (WKWebView)** | 보통 — 구체적 use case 의존 (web 개발) | 보통 (WKWebView wrap + URL 관리) | 모호 — 사용자 use case 명시 필요 | ⏸ 보류 (요청 시) |
| T7 | **Pane drag-reorder / rename sheet** | 낮음 — current order로 충분 | 작음 | 낮음 — 자주 안 쓸 것 | ⏸ 보류 |
| T8 | **M5.b Block 그룹화 (Warp UX)** | 보통 — Warp 사용자에게 익숙 | 보통 (terminal 출력 grouping) | 보통 — terminal 가독성 ↑ | ⏸ 보류 (terminal 사용 늘면) |

### 결정 요약
- **이번 라운드 진행**: T1 (panes 영속) + T2 (Phase D 인터-에이전트) + T3 (Codex schema 안전 추가)
- **보류**: T4-T8 — 사용자 명시 요청 시 또는 사용 빈도 데이터 보고 결정. ADR에 명시 보존

---

## 2. 진행 항목별 상세

### T1. Panes 영속 (workspace 재진입 시 보존)

**문제**: 현재 workspace 전환 → 다시 돌아오면 panes는 새 primary 1개만. Codex pane 추가했어도 사라짐.

**참조 패턴**: SwiftData `WorkspaceModel.deliveryConfigJSON` 패턴과 동일 (JSON column nullable). ADR-029의 마이그레이션 호환 패턴 재사용.

**구현 범위**:
- `WorkspaceModel.panesJSON: Data?` — `[AgentPane]` JSON 직렬화
- nil → 빈 배열 fallback (기존 워크스페이스 호환)
- `AppModel.startSession`이 저장된 panes 복원, 없으면 default primary 생성
- `addPane`/`removePane`/`renamePane`/`setActivePane` 시 자동 영속

**사용성 검토**:
- ✅ 사용자가 의도적으로 만든 panes는 보존돼야 자연스러움
- ⚠️ session ID는 영속 X (Claude/Codex CLI session id resume) — 다음 phase에서 검토
- ⚠️ `paneMessages`는 일시 (워크스페이스 재진입 시 빈 messages, claude resume으로 컨텍스트만 복원)

**단위 기능 검토**:
- AgentPane이 이미 `Codable` 가능한지 확인 (Sendable + struct + 모든 필드 Codable)
- SwiftData column 추가 (nullable Data) — 기존 데이터 호환

---

### T2. Phase D — 인터-에이전트 메시지 패싱

**문제**: 한 pane에서 다른 pane으로 명시적 위임할 syntax 없음. 사용자가 직접 tab 전환 후 입력해야.

**참조 패턴** (ADR-027 evidence):
- **MetaGPT 메시지 환경** (67.6k) — publish/subscribe bus + `watch()` 구독
- **AutoGen GroupChat speaker selection** — manual hint 우선
- syntax: `@codex` mention (Telegram 친숙)

**구현 범위**:
- `Sources/YuminaiCore/AgentMessage.swift` — `AgentMessage { id, from, to, type, payload, timestamp }`
- `Sources/YuminaiCore/MessageBus.swift` — actor + `publish` / `subscribe(filter:)` AsyncStream
- `Sources/YuminaiCore/MentionParser.swift` — `@<pane-id-or-kind>` 추출
- AppModel: `dispatch(to: PaneId, text:)` — 대상 pane이 있으면 해당 pane 활성화 + input + sendMessage
- Composer가 mention 자동 인식 → 발송 시 dispatch
- ChatView 메시지 메타에 source/target 라벨 표시 ("→ Codex" 같은)

**사용성 검토**:
- ✅ Telegram에서도 `@codex` 동작 — bound pane이 메시지 받으면 mention 파싱 후 다른 pane으로 forward
- ⚠️ mention 자동완성 picker 없으면 사용자가 pane id 기억해야 → agent kind로 fallback (`@codex` = 첫 codex pane, `@claude` = 첫 claude pane)
- ✅ 같은 워크스페이스라 file system 공유 → "방금 만든 파일 검토해줘" 자연스러움
- ⚠️ pane 응답을 누가 받는지 (사용자 or 원본 pane) — 결정 필요. **default**: 사용자 (단순함). v0.5에서 pane → pane 답장 검토

**단위 기능 검토**:
- 단순 형태로 시작: `@<kind>` parsing → 첫 매칭 pane으로 dispatch → 사용자에게 응답
- 자동 새 turn (pane → pane 답장)은 X — 무한 루프 위험, v0.5
- ChatView에서 어떤 pane이 보낸/받은 메시지인지 시각적 구분 (색 또는 라벨)

---

### T3. Codex JSONL schema 안전 정밀화

**문제**: 현재 defensive 파싱이지만 unknown type은 raw text로만 fallback. 실제 codex 출력의 알려진 type은 더 추가 가능.

**참조**: codex CLI 0.116.0 changelog + GitHub issues 검색

**구현 범위 (이번 라운드 — 안전한 것만)**:
- 알려진 type alias 추가 (예: `agent_message_chunk` / `tool_call_arguments_delta` 등)
- 실제 사용 시 unknown type을 logger로 기록 → 사용자가 PR로 매핑 추가 가능

**사용성 검토**:
- 사용자가 codex 사용 시작하면 데이터 모임
- 현재는 "[codex unknown_type] raw" prefix로 보이지만 메시지는 손실 안 됨
- 정밀화는 점진적

**단위 기능 검토**:
- 새 type 추가 시 기존 테스트 안 깨짐 (default fallback 유지)

---

## 3. 보류 항목 — defer 사유

### T4. 좌/우 split layout
- 비용: HSplitView + focus management + per-side Composer (Composer 자체가 큰 컴포넌트)
- 가치: 모호 — tab 전환 (현재 구현)이 macOS 사용자에게 자연스러운 패턴. Cursor/Cline 모두 sidebar 방식, split는 power user only
- **defer 조건**: 사용자가 "두 pane 동시에 보고 싶다" 요청 시 진행

### T5. Per-pane Composer 설정
- 비용: Composer 상태 분리 (현재 한 Composer가 모든 pane 입력 처리)
- 가치: 낮음 — 현재 setActivePane이 settings도 swap. swap 즉시 picker UI 갱신
- **defer 조건**: 사용자가 "Claude pane은 항상 sonnet, Codex pane은 항상 o4-mini" 같은 명시적 요구 시

### T6. PreviewPane (WKWebView)
- 비용: 보통 — WKWebView wrap, URL 관리, dev server 감지 등
- 가치: 사용자 use case 의존 — web 개발자면 가치 ↑, CLI 도구 개발자면 불필요
- **defer 조건**: 사용자가 use case 명시 (예: "React dev server 옆에 띄우고 싶음")

### T7. Pane drag-reorder / rename sheet
- 비용: 작음
- 가치: 낮음 — 사용자가 panes 1-3개만 쓸 가능성 높음, 순서 바꿀 동기 약함
- **defer 조건**: 사용자가 panes 5개+ 쓰기 시작하면 검토

### T8. M5.b Block 그룹화 (Warp UX)
- 비용: 보통 — terminal 출력에 명령 경계 인식 + UI grouping
- 가치: 보통 — terminal 가독성 ↑, 하지만 사용자가 SwiftTerm 빈도 보고 결정
- **defer 조건**: 사용자가 terminal pane 자주 사용한다는 데이터 또는 명시 요청

---

## 4. 검증 매트릭스 (구현 후)

| 항목 | 검증 방법 |
|------|----------|
| T1 panes 영속 | workspace 전환 → 재진입 → panes 그대로 확인 (manual + unit test on Codable) |
| T2 mention dispatch | `@codex 검토` 입력 → codex pane 활성화 + Composer 입력 + 자동 send 확인 (unit test on parser + e2e) |
| T2 mention picker | (있으면) Composer에서 `@` 입력 시 사용 가능한 pane 자동완성 표시 (UI manual) |
| T3 codex schema | 새 type 추가 시 default fallback 깨지지 않음 (parser test) |

---

## 5. 후속 (이번 라운드 X)

- T4-T8: 위 defer 사유에 따라 사용자 트리거 시
- ACP (Agent Client Protocol) 채택: ADR-027의 횡단 결정에 따라 v0.5 spike
- Editable diff editor (Cline SOTA): SwiftUI 자체 구현 비용 큼, v0.5
- 적극적 fix loop mode (즉시 새 turn auto-spawn): v0.5 토글

---

## 6. 진행 순서 (이번 라운드)

1. **T1 panes 영속** — 작업 작음, 가치 큼, 다른 작업 의존성 X
2. **T2 인터-에이전트 메시지** — T1 위에서 자연스럽게 동작 (저장된 panes로 dispatch 대상 매칭)
3. **T3 codex schema 안전 추가** — 시간 남으면

각 commit 별도. ADR-031 (T1+T2 통합)으로 결정 기록.
