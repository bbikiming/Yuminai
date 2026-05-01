# 00_OVERVIEW — Yuminai 제품 개요

> 이 문서는 PRD의 진입점. 한 페이지에 비전·정체성·핵심 가치를 압축. 세부는 후속 문서로.

## 1줄 정의

> **바이브 코딩을 위한 1인 macOS 워크스페이스.** Claude Code의 추론 엔진을 코어로 두고, Obsidian Vault·Telegram·외부 도구를 한 화면에서 오케스트레이션해 *사고 → 코드 → 문서화 → 공유* 사이클을 끊김 없이 잇는 SwiftUI 네이티브 앱.

## 비전 (3년)

> 본인의 모든 *코딩 사이클*이 Yuminai 한 화면에서 시작·끝나도록 만든다. 외부 도구는 통합되어 있고, 컨텍스트는 자동으로 따라온다. 모바일에서 명령을 띄우면 책상 앞 macOS가 받아 작업을 진행한다.

## 미션 (1년)

> Claude Code의 능력을 그대로 누리되, **외부 통합이 매번 수동/스크립트가 아니라 1급 시민으로 들어간** 데스크탑 워크스페이스를 본인이 매일 쓸 수 있게 만든다.

## 정체성 — 무엇이 *아닌가*

| 아닌 것 | 이유 |
|---|---|
| Cursor / Windsurf 같은 IDE | 코드 편집은 별도 IDE/에디터가 담당. Yuminai는 *대화형 작업 셸* |
| 일반 LLM 채팅 앱 (ChatGPT 데스크탑 등) | 바이브 코딩 워크플로우(파일/git/외부 통합)가 1급 |
| 팀 협업 도구 | 1인용. 멀티유저 기능 없음 |
| 새 LLM 추론 엔진 | Claude Code가 추론. Yuminai는 그 위의 통합·UI 레이어 |
| Claude Code의 직접 대체재 | **공존**. Claude Code를 자식 프로세스로 활용 |

## 핵심 가치 (3개)

1. **컨텍스트 무중단성**: Obsidian 노트·이전 세션·코드베이스 상태가 자동으로 작업 컨텍스트로 들어간다. 매번 복사·붙여넣기 안 한다.
2. **모바일 ↔ 데스크탑 연속성**: Telegram으로 명령을 띄우면 데스크탑이 받아서 진행하고 결과를 알린다. 책상 떠나도 작업이 멈추지 않는다.
3. **하네스 가능성**: claude-forge처럼 사용자(본인)가 자기 워크플로우에 맞는 rules·agents·skills·hooks를 워크스페이스에 끼워넣는다.

## 1차 사용자 (Persona)

- **본인 1명**. 상세는 [`10_PERSONAS.md`](10_PERSONAS.md).

## 핵심 워크플로우 (예시)

> 사용자가 새 기능을 구현하는 전형적 흐름.

1. macOS Yuminai 열기 → 워크스페이스 `nunchi-v2` 클릭 → 마지막 세션 자동 복원
2. 사이드바의 Obsidian 패널에서 어제 작성한 PRD 노트 클릭 → "컨텍스트로 주입"
3. 채팅창에 "여기 PRD대로 옵션 B 흐름 구현, /tdd 먼저" 입력
4. Claude Code(자식 프로세스)가 Plan → Test → 구현 진행. 출력은 Yuminai UI에 스트리밍
5. 작업 30분 소요 — 자리 비움 → Telegram에 진행 상황/완료 알림
6. 모바일에서 "PR 만들고 머지해줘" 답신 → Telegram 봇이 데스크탑 Yuminai에 명령 전달 → 실행
7. 완료 후 작업 요약이 Obsidian Daily Note에 자동 append

## 측정 가능한 성공 (1차)

본인용이지만 측정 불가하면 발전 안 한다.

| 지표 | 측정 방법 | 1년 목표 |
|---|---|---|
| 일일 활성 사용 시간 | 앱 telemetry (로컬, 본인만 봄) | 평일 4시간+ |
| Claude Code 직접 호출 대비 | 셸에서 `claude` 직접 vs Yuminai에서 — bash history 카운트 | Yuminai 80%+ |
| 컨텍스트 복붙 횟수 | Obsidian 노트→채팅 자동주입 사용 빈도 | 수동 복붙 90% 감소 |
| 모바일 명령으로 시작된 작업 | Telegram 트리거 카운트 | 주 5회+ |
| 워크스페이스 수 | DB 쿼리 | 활성 3개 동시 운영 |

## 비범위 (Non-goals)

[`30_GOALS_NONGOALS.md`](30_GOALS_NONGOALS.md) 참조.

## 다음 단계

- [`20_PROBLEM.md`](20_PROBLEM.md) — 풀려는 페인포인트
- [`40_FUNCTIONAL_REQS.md`](40_FUNCTIONAL_REQS.md) — Must/Should/Could 기능 리스트
- [`90_ROADMAP.md`](90_ROADMAP.md) — MVP→v1.0
- [`99_OPEN_QUESTIONS.md`](99_OPEN_QUESTIONS.md) — 미해결 결정사항 (꼭 읽기)
