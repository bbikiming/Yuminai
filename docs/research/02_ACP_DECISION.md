# 02_ACP_DECISION — Agent Client Protocol 채택 평가 (Spike Summary)

> **목적**: Yuminai의 자체 wire protocol vs ACP (Agent Client Protocol) 채택 결정 자료. v0.6 시작 시점의 reference.
>
> **상태**: **Spike summary only** — 실제 채택 결정은 v0.6에서. 이 doc은 평가 근거 + Swift SDK 작성 비용 추정.

---

## 1. ACP 개요

**Agent Client Protocol** (https://github.com/agentclientprotocol/agent-client-protocol):
- "code editor ↔ coding agent" wire protocol 표준화
- JSON-RPC 2.0 기반 (LSP / DAP 와 같은 패턴)
- 공식 SDK: Kotlin, Java, Python, Rust, TypeScript
- **Swift SDK 부재** — 자체 작성 필요

**왜 부상**:
- Zed (81k stars)가 push
- `obsidian-agent-client` (1.9k) — Yuminai와 가장 인접한 use case
- `OpenACP` (307) — Telegram에서 ACP 세션 제어
- 외부 에이전트 (Claude Code / Codex / Gemini CLI 등) 자동 호환

---

## 2. Yuminai vs ACP — 매핑 분석

### Yuminai 현재 (자체 wire protocol)

```
Yuminai App (Swift)
    ↓ Process spawn
ClaudeStreamSession protocol (JSON over stdin/stdout)
    ↓ implementation
LiveClaudeAdapter (claude CLI -p stream-json)
LiveCodexAdapter (codex exec --json)
```

**특징**:
- 각 CLI에 맞춤 어댑터 (claude vs codex 코드가 다름)
- ClaudeStreamSession이 사실상 Yuminai의 internal protocol
- 새 agent 추가 = 새 어댑터 작성 + JSON parser

### ACP 채택 시 (가설)

```
Yuminai App (Swift)
    ↓ JSON-RPC over stdin/stdout
ACP Swift SDK
    ↓ Process spawn (any ACP-compliant agent)
{Claude Code (ACP-mode) | Codex (ACP-mode) | Gemini CLI | ...}
```

**특징**:
- Yuminai가 모든 agent를 동일 protocol로 호출
- 새 agent 추가 = ACP-compliant이면 코드 변경 X
- 단, agent CLI가 ACP를 지원해야 함 (현재 claude/codex는 미지원)

---

## 3. 가치 평가

### Pro (장점)
1. **표준 프로토콜** — Yuminai가 ACP 호환 agent 모두 지원 (외부 ecosystem 의존성 ↓)
2. **신규 agent 추가 비용 ↓** — 어댑터 작성 X (단, agent가 ACP 준수)
3. **인접 reuse 가능** — `obsidian-agent-client` 등 코드 패턴 차용
4. **장기적 유지보수 ↓** — claude/codex 각자 schema 변화 추적 X

### Con (단점)
1. **Swift SDK 자체 작성 비용** — JSON-RPC 매핑, ACP spec 따라 type 정의, conformance 테스트
2. **claude/codex가 ACP 미지원** — 결국 어댑터 layer 1개 더 추가 (ACP ↔ claude CLI 변환)
3. **외부 ecosystem 성장 의존** — ACP가 안 자라면 ROI 음수
4. **현재 어댑터 잘 작동** — 변경 risk가 가치보다 클 수 있음

---

## 4. Swift SDK 자체 작성 비용 추정

**TS SDK 코드량 분석** (가설):
- ACP TypeScript SDK는 추정 ~3000-5000 LOC (RPC + types + transports)
- Swift 매핑 시 JSON-RPC 처리 (Foundation `JSONSerialization`만으로 충분, 의존성 X)
- type 정의 (Codable structs 50-100개)

**예상 일정**:
- Spike (작동하는 minimum): **2-3일** (one-method round-trip)
- Production-ready (전체 spec): **2-3주**
- Yuminai 기존 어댑터를 ACP-wrap: **3-5일** (claude CLI ↔ ACP 변환 layer)

**총**: **~3-4주 작업** — v0.6 메이저 라운드

---

## 5. 권고

### 단기 (v0.5)
- **현재 어댑터 유지** — claude/codex가 잘 작동, 변경 risk
- ACP 동향 관찰 — Zed/obsidian-agent-client 사용자 피드백, agent 호환성 데이터

### 중기 (v0.6 시작 시)
- **2-3일 Spike** — ACP Swift PoC (1 method round-trip)
- spike 결과 + ACP ecosystem 성장 검토 후 결정:
  - **GO**: 본격 SDK 작성 + 어댑터 wrapping (3-4주)
  - **NO-GO**: 자체 wire protocol 유지, ACP는 v0.7 재평가

### 장기 (v0.7+)
- ACP가 mainstream되면: 자체 wire protocol을 deprecation, ACP만 유지
- ACP가 죽으면: 자체 protocol 계속 유지

---

## 6. Decision Triggers

다음 중 하나라도 발생하면 spike 우선순위 ↑:
- claude CLI 또는 codex CLI가 공식 ACP 지원 발표
- obsidian-agent-client 등 인접 도구가 5k+ stars 도달
- 사용자가 Gemini CLI 등 외부 agent 추가 명시 요청
- ACP 0.x → 1.0 stable release

---

## 7. 결론

**v0.5에서 ACP는 진행 X**. 현재 자체 어댑터로 charged value 충분. ACP 채택은 **외부 ecosystem 검증 후 v0.6+ 메이저 결정**.

이 doc은 **결정 자료 보존** 목적 — Spike 진행 시 출발점. 코드 변경 없음.

---

## 출처

- agent-client-protocol GitHub: https://github.com/agentclientprotocol/agent-client-protocol
- Zed editor: https://github.com/zed-industries/zed (81k stars)
- obsidian-agent-client: 1.9k stars (인접 use case)
- ADR-027 횡단 결정 표 참조
