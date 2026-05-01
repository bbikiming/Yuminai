# 99_OPEN_QUESTIONS — 미해결 결정사항

> 답변 받기 전엔 잠정값으로 진행. 잠정값은 [`42_DECISIONS.md`](../log/42_DECISIONS.md) "잠정 결정" 섹션 참조.

## 우선순위 표기

- 🔴 **CRITICAL**: 답변 없으면 큰 재작업 위험
- 🟡 **HIGH**: 답변에 따라 v0.2 이상 영향
- 🟢 **MEDIUM**: v0.3 이상 영향, 잠정으로 충분

---

## ✅ Q-B. UI 형태 (해결됨, 2026-05-01)

**확정**: B2 — CLI 스타일 채팅 GUI. ADR-013 참조. `YuminaiUI` 모듈 컴포넌트 완비.

---

## 🟡 Q-D1. Obsidian 통합 구체 명세 (잠정 진행 중)

**상태 (2026-05-01)**: 사용자가 "기본 세팅으로 기획해서 연동" 요청 → 잠정값으로 진행. 코어/UI 변경 없이 v0.2에 모듈 추가 가능 구조.

**잠정 결정 (당분간 적용)**:
1. Vault 위치 — SettingsView에서 사용자 입력 (현재 `AppPreferences.obsidianVaultPath`)
2. Daily Note 경로 패턴 — `Daily/{YYYY-MM-DD}.md` 디폴트, 향후 설정에서 변경 가능
3. 자동 노트화 정책 — OFF (슬래시 명령 `/note save`로만)
4. 인라인 주입 — 본문 전체 (크기 제한은 Claude가 알아서)
5. Obsidian 플러그인 호환 — 우리 코드는 plain Markdown만 다룸 (Templater 결과는 그대로 보존)

**언제 정식 답변 필요**: v0.2 Obsidian 모듈 본격 구현 시작 시

---

## ✅ Q-D2. Telegram 통합 (해결됨, 2026-05-01)

**확정 (사용자 답변)**: 
- 설정에서 토큰/Chat ID/허용 user ID 추가 가능 (`SettingsView` Telegram 탭)
- **양방향**: 알림 송신(`TelegramAlertDispatcher`) + 모바일 명령 수신(`TelegramCommandPump`)
- 자세한 결정 = ADR-012

**MVP 라우팅 동작**: 받은 텍스트 → 현재 활성 워크스페이스 채팅 입력 → Claude로 전송. 응답은 봇으로 echo. (`YuminaiCommandRouter`)

**남은 질문 (v0.3 검토)**:
1. `#workspace command` prefix 라우팅 (다른 워크스페이스에 send 등)
2. inline keyboard로 결정 요청 UI
3. 음성 메시지 → Whisper → 명령

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
