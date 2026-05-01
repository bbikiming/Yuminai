# 99_OPEN_QUESTIONS — 미해결 결정사항

> 답변 받기 전엔 잠정값으로 진행. 잠정값은 [`42_DECISIONS.md`](../log/42_DECISIONS.md) "잠정 결정" 섹션 참조.

## 우선순위 표기

- 🔴 **CRITICAL**: 답변 없으면 큰 재작업 위험
- 🟡 **HIGH**: 답변에 따라 v0.2 이상 영향
- 🟢 **MEDIUM**: v0.3 이상 영향, 잠정으로 충분

---

## 🔴 Q-B. UI 정확한 형태 (B1 vs B2 vs B3)

**질문**: Claude Code "와 동일한" UI/UX의 의미는?

| 옵션 | 의미 | 노력 | 통합 친화도 |
|---|---|---|---|
| B1 | 진짜 터미널 임베드 (xterm.js Swift 포팅 또는 SwiftTerm) | 중 | 낮음 (위젯 추가 어려움) |
| **B2 (잠정)** | CLI 스타일 채팅 GUI (monospace, 다크, 슬래시 명령) | 중 | 높음 |
| B3 | 풀 GUI (다중 패널, 인스펙터, 풍부한 위젯) | 높음 | 매우 높음 |

**잠정 결정**: B2

**필요 답변**: B1 / B2 / B3 / 다른 방향?

---

## 🔴 Q-D1. Obsidian 통합 구체 명세

**질문**:
1. Vault 위치는? (예: `~/Documents/Obsidian/MainVault/`)
2. Daily Note 경로 패턴? (예: `Daily/{YYYY-MM-DD}.md`)
3. 자동 노트화 정책: 모든 작업 자동 vs 명시적 슬래시 명령만?
4. 노트 인라인 주입 시 본문 전체 vs 일부(첫 N줄)?
5. 사용 중인 Obsidian 플러그인 중 우리가 알아야 할 것? (Templater, Dataview 등)

**잠정**: Vault 사용자 입력, Daily 자동 추정, 자동 노트화 OFF(슬래시만), 전체 본문 주입

---

## 🔴 Q-D2. Telegram 통합 구체 명세

**질문**:
1. Bot Token 보유 / 새로 만들지?
2. 본인 Telegram User ID는?
3. v0.2 알림은 어떤 종류? (제안: 작업 완료, 에러, 의사결정 요청)
4. v0.3 양방향에서 가능한 명령 범위? (제안: 워크스페이스 활성화, 기존 명령 재실행, 새 메시지 보내기)
5. 명령 의도 분류기를 어떻게? (제안: Claude에게 작은 분류 요청)

**잠정**: BotFather 새 봇, 작업 완료/에러만 v0.2, Claude 위임 분류

---

## 🟡 Q-D3. "다양한 외부 앱들" 구체 후보

**질문**: PRD §50_INTEGRATIONS의 후보 중 어떤 것을 v0.3 이상에서 다룰 가치 있나?

| 후보 | 본인 일상에서 사용? |
|---|---|
| GitHub (`gh` CLI) | 거의 매일 |
| Linear | ? |
| Notion | ? |
| Slack | ? |
| Discord | ? |
| Figma / Pencil | ? |
| Calendar | ? |
| Reminders | ? |
| Raycast | ? |
| iA Writer / Bear / Drafts | ? |
| 기타? | ? |

**잠정**: GitHub만 v0.3 후보

---

## 🟡 Q-E. 워크스페이스 모델

**질문**:
1. 워크스페이스 = git worktree 1:1 강제? 아니면 선택?
2. 동시 활성 가능한 워크스페이스 수 (메모리 제한)?
3. 워크스페이스 삭제 시 git worktree도 함께 cleanup?

**잠정**: 선택(생성 시 옵션), 동시 활성 무제한(자원 한계까지), 삭제 시 사용자에게 물어봄

---

## 🟡 Q-F. iCloud 동기화

**질문**:
1. 사용 디바이스 1대인지 2대 이상?
2. 2대 이상이면 동기화할 데이터: 메타만(워크스페이스 목록) vs 메시지까지?

**잠정**: 1대 가정, v0.3에서 메타만

---

## 🟢 Q-G. 보안 강도

**질문**:
1. App Sandbox OFF가 본인에게 OK?
2. Hardened Runtime은 켜고 entitlement 추가?
3. ad-hoc 서명 / 서명 없음 / Personal Team 중?

**잠정**: Sandbox OFF, Hardened Runtime ON+entitlements, ad-hoc

---

## 🟢 Q-H. 일정·범위

**질문**:
1. MVP-0 4주가 현실적? (사이드 프로젝트 가정)
2. 다른 프로젝트(`nunchi`, `moodbit`, `emotion-lab`)와 병행?
3. 우선순위가 바뀌면 어떻게 알릴지?

**잠정**: 4주 공격적, 병행, MEMORY.md 업데이트

---

## 🟢 Q-I. Xcode App 타깃 빌드 자동화

**질문**:
1. Xcode 프로젝트 생성 후 `xcodegen` 또는 `tuist` 도입?
2. 아니면 `.xcodeproj`를 직접 git에 커밋?

**잠정**: 직접 커밋(단일 사용자라 복잡 도구 불필요)

---

## 🟢 Q-J. 코드네임 / 브랜딩

**질문**:
1. "Yuminai"가 정식? 코드네임?
2. 한자 / 한글 / 영문 표기 우선순위?
3. 아이콘 / 로고 디자인 시점?

**잠정**: 정식 = "Yuminai", 표기 = 영문 우선 + (유미나이) 한글 보조, 아이콘은 v0.2 시점

---

## 🟢 Q-K. 메타-하네스: claude-forge 흡수

**질문**:
1. claude-forge의 rules/agents/skills를 Yuminai 워크스페이스에 *복제*해서 쓸 것인지?
2. 아니면 Yuminai가 claude-forge를 그대로 *참조*?

**잠정**: 참조 우선(중복 회피), 사용자 워크스페이스에선 `.harness/`가 그 위에 override

---

## 🟢 Q-L. 자체 분석/사용 데이터

**질문**:
1. 일일 사용 시간, 메시지 수 등을 시각화하는 대시보드?
2. v1.0에서 다룰지 별도 도구?

**잠정**: v1.0에 간단한 차트 1개

---

## 답변 받는 방법

이 문서에서 답변할 항목 번호 (Q-B, Q-D1 등)와 결정 사항을 알려주면, 즉시 PRD/설계 문서 업데이트 + [`42_DECISIONS.md`](../log/42_DECISIONS.md)에 기록.

답변 형식 예시:
```
Q-B: B2 확정 (Claude Code 룩 + 통합 위젯 가능)
Q-D1.1: Vault = ~/Obsidian/main/
Q-D1.3: 자동 노트화 OFF, 슬래시 명령만
Q-D2.2: User ID = 123456789
Q-D3: GitHub + Calendar만 v0.3, 나머지 NO
```
