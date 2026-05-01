# Decisions Log (ADR-lite)

> 큰 결정만 기록. 형식: 결정 / 컨텍스트 / 대안 / 근거 / 결과 / 재검토 시점.

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

- **날짜**: 2026-05-01
- **상태**: Provisional (W1 Spike 후 확정)
- **결정**: 일단 외부 의존성 없이 `Process` + `Pipe`로 시작. 작동 안 하면 SwiftTerm 또는 직접 `forkpty` 사용.
- **컨텍스트**: Claude CLI가 TTY 요구 정도 미상
- **대안**:
  - SwiftTerm 처음부터 도입 → 의존성 증가
  - `forkpty` 직접 호출 → C API, 복잡
  - Pipe로 시작 → 가장 간단, 작동 안 할 가능성
- **근거**: 검증 후 결정이 합리적
- **결과**: W1 Spike에서 결정 후 [`docs/log/41_CHANGELOG.md`](41_CHANGELOG.md) 업데이트
- **재검토**: 2026-05-08 (W1 종료 시점)

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
