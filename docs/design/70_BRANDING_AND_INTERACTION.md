# 70_BRANDING_AND_INTERACTION — Yuminai 브랜딩 + 인터랙션 + UX 라이팅

> **목적**: ar2r 자전거 팀 컬러를 참조한 브랜드 시스템, 모든 버튼/컨트롤의 인터랙션·애니메이션 명세,
> 한글 친화 UX 라이팅 표준화.
>
> **작성일**: 2026-05-01
> **선행 명세**: `60_UI_DESIGN_SPEC.md` (디자인 토큰 v3)

---

## 1. ar2r 컬러 조사 결과 (codex CLI 0.116.0 web search)

| 시도 | 결과 |
|---|---|
| `ar2r` / `AR2R` / `AR-2R` / `에이알투알` + 자전거 키워드 | **공개 웹에서 확인 불가** |
| 발견된 동명 entity | AI 도구(`aitoolnet.com/ar2r`), 프랑스 회사(`pappers.fr/.../ar2r-851383265`), 알마티 클럽(`openresa.com/club/ar2r`) — **자전거 팀 무관** |

**결론**: 사용자 비공개 또는 인스타/Strava 한정 클럽 가능성. 정확한 컬러 확정을 위해 **사용자에게 추가 정보 요청** (§13 Open Questions). 일단 자전거 팀 표준 팔레트로 fallback.

### Fallback 팔레트 (자전거 저지 표준 톤)

| 토큰 | hex | 역할 |
|---|---|---|
| `brand.primary` | `#0E2A47` | Deep Navy — 차분한 chrome / structural |
| `brand.accent` | `#FF5A36` | Vivid Orange-Red — CTA / active / 강조 |
| `brand.contrast` | `#FFFFFF` | White — 본문/대비 |
| `brand.shadow` | `#0A1A2D` | Navy 더 깊은 톤 — overlay backdrop |

근거: 도로 자전거 팀 저지의 시각적 공통 패턴 — bold primary(navy/black 빈도 높음) + high-visibility accent(orange/red — 안전 가시성 + 응원 색) + white contrast (스폰서 로고 가독). 코덱스 분석 결과와 정합.

> **확정 방법**: 사용자가 ar2r 정확한 정보(인스타 핸들, 저지 사진, 또는 정확한 hex)를 알려주면 `Theme.Brand` namespace 한 곳만 교체. 다른 컴포넌트 변경 없음.

---

## 2. 브랜드 시스템 v1

### 2.1 Color hierarchy (브랜드 → semantic → component)

```
brand.primary       #0E2A47   (Navy — chrome accent, brand mark)
brand.accent        #FF5A36   (Orange-Red — CTA, active state, link)
brand.accentDeep    #D94823   (hover 시 진한 톤)
brand.accentMuted   #2A1812   (어두운 muted, 활성 배경)
brand.contrast      #FFFFFF
```

**기존 Theme 매핑 변경**:
- `Theme.Color.accent` → `Theme.Brand.accent` 위임 (Claude orange → ar2r orange-red)
- `Theme.Color.userBg` → `brand.accentMuted` (어두운 muted, navy 톤도 가능)
- 사이드바 selected 좌측 bar → `brand.accent`
- composer focus border, send button → `brand.accent`
- streaming pulse → `brand.accent`

**유지** (브랜드와 무관):
- 모든 grayscale (bg/surface/text)
- success/warning/danger/diff 색

### 2.2 로고 컨셉 (3-layer 디자인)

```
Yuminai mark
============

  ◢━━━◣
  ┃ Y ┃     ← 상단 모노그램 (mono "Y" 또는 한글 "유")
  ◥━━━◤
   ▲▲▲     ← 하단 자전거 페달/체인 모티프 (3개 점 또는 chevron)

색:
  - 외곽 사각형: brand.primary (navy)
  - "Y" 글자: brand.accent (orange-red)
  - 페달 점: brand.contrast (white) 또는 brand.accent
```

(SVG/PNG 실제 디자인은 다음 라운드 — `LogoView.swift` SwiftUI Shape으로 1차 작성, ImageRenderer로 PNG → iconutil로 .icns)

### 2.3 타이포그래피 (변경 없음)

§60 디자인 명세서의 SF Pro + SF Mono 그대로 유지.

---

## 3. 인터랙션 + 애니메이션 명세

### 3.1 상태별 시각 변화 (모든 인터랙티브 컴포넌트 공통)

| 상태 | 시각 변화 | 애니메이션 |
|---|---|---|
| Idle | base 토큰 | — |
| Hover | bg → `surfaceHi`, cursor 포인터 | 100ms easeOut (bg only) |
| Pressed | scale 0.97, bg → `elevated` | 80ms easeOut |
| Focus (keyboard) | 1.5px `brand.accent` outline ring | 120ms easeOut |
| Active (toggle on) | bg → `brand.accentMuted`, fg → `brand.accent` | 150ms easeInOut |
| Selected (sidebar/picker) | bg → `elevated` + 좌측 2px `brand.accent` bar | 150ms easeInOut |
| Disabled | opacity 0.4, cursor default | 즉시 |
| Loading | spinner 또는 PulseDot | 1.5s loop |

### 3.2 Hover scale (subtle)

primary CTA / send button만 hover 시 `scale 1.02`. 그 외는 bg 변화만.

### 3.3 Press feedback

모든 버튼 press 시 `scale 0.97` + bg darken. 80ms.

### 3.4 Sheet / popup 등장

- Sheet (Settings, Create, Dashboard): macOS 기본 (220ms ease)
- Sidebar overlay popup: 180ms easeInOut + opacity transition + slide from leading
- Inspector toggle: 180ms easeInOut + slide from trailing
- Slash command popup: 120ms easeOut + scale 0.96 → 1.0

### 3.5 Streaming/loading

- Streaming pulse: PulseDot — 1.5s opacity loop (0.4 ↔ 1.0)
- Streaming badge: toolbar에 `● streaming` (accent, pulse)
- Composer footer: idle 시 send button, streaming 시 stop button (color shift)
- 메시지 본문 streaming cursor: 마지막 assistant 메시지 끝에 `▌` (1s blink)

### 3.6 Toast / Error

- 우상단 absolute 위치
- bg `surface` + 좌측 3px `brand.accent` (info) 또는 `danger` (error)
- 5초 자동 dismiss + slide-out
- 전환: 200ms easeInOut

### 3.7 Reduce-motion 자동 비활성

```swift
@Environment(\.accessibilityReduceMotion) var reduceMotion
let duration = reduceMotion ? 0 : 0.18
```

모든 transition `.animation()`에 적용.

---

## 4. 컴포넌트별 인터랙션 매트릭스

### 4.1 FlatButton

| variant | idle | hover | press | disabled |
|---|---|---|---|---|
| primary | accent bg + white fg | accentDeep bg + scale 1.02 | scale 0.97 | opacity 0.4 |
| secondary | surface bg + text fg + 1px borderSubtle | surfaceHi bg | scale 0.97 | opacity 0.4 |
| ghost | clear bg + textSecondary fg | surfaceHi bg + text fg | scale 0.97 | opacity 0.4 |
| destructive | clear bg + danger fg + 1px danger40 | danger 10% bg | scale 0.97 | opacity 0.4 |
| accentSubtle | accentMuted bg + accent fg | accentMuted lighten 5% | scale 0.97 | opacity 0.4 |

### 4.2 IconButton

| 상태 | 변화 |
|---|---|
| Idle | textSecondary fg, transparent bg |
| Hover | text fg, surfaceHi bg, radius sm |
| Press | scale 0.92 + accent fg flash 80ms |

### 4.3 SendButton

| 상태 | 변화 |
|---|---|
| Idle (input 있음) | accent bg + white "send" + ⌘↵ hint |
| Idle (input 없음) | surfaceHi bg + textDisabled "send" + opacity 0.5 |
| Hover (enabled) | accent → accentDeep, scale 1.02 |
| Press | scale 0.97 |
| Streaming | red border + "stop" + danger fg, esc hint |
| Streaming hover | danger 10% bg |

### 4.4 Sidebar Item

| 상태 | 변화 |
|---|---|
| Idle, unselected | textSecondary fg, transparent bg, ○ outline dot |
| Hover, unselected | text fg, surfaceHi bg, 100ms easeOut |
| Selected | text fg, elevated bg, ● accent dot, 좌측 2px accent bar |
| Hover, selected | (변화 없음 — 이미 강조 상태) |
| Focused (keyboard) | + 1.5px accent outline ring |

### 4.5 Picker (Inline)

| 상태 | 변화 |
|---|---|
| Idle | clear bg, "label · value ▾" |
| Hover | surfaceHi bg, ▾ accent로 변경 |
| Open | bg surfaceHi 유지, dropdown 등장 (120ms easeOut + scale 0.96→1.0) |
| Item hover (popup) | surfaceHi bg |
| Item selected | accent fg + ● 마커 좌측 |

### 4.6 TextEditor (Composer)

| 상태 | 변화 |
|---|---|
| Idle | placeholder 보임 (textTertiary), border subtle |
| Focus | placeholder 사라짐 (text 시작 시), border → borderStrong (animated 120ms) |
| Typing | (시각 변화 없음, send 버튼 enabled 활성) |

### 4.7 Composer footer toggle (model/mode/effort 변경)

picker 변경 시:
1. footer 우측에 작은 spinner 잠시 (200ms)
2. 새 spawn 진행 중 표시
3. toolbar streaming badge로 신호

### 4.8 Sidebar toggle

- inline 모드: 사이드바 sliding 180ms easeInOut + opacity
- compact overlay 모드: backdrop fade-in (200ms) + sidebar slide from leading (180ms)
- Esc 또는 backdrop 클릭으로 닫기

### 4.9 Inspector toggle

- mode 허용: slide from trailing 180ms easeInOut
- mode 비허용: 버튼 disabled (시각 + tooltip)

### 4.10 Workspace switcher (Breadcrumb)

- 클릭 시 dropdown menu 등장 (네이티브 Menu)
- 워크스페이스 리스트 + "+ 새 워크스페이스" 항목
- 선택 시 즉시 전환 + sidebar selection sync

### 4.11 SlashCommandPalette (⌘P)

- ⌘P 또는 sidebar search 클릭으로 호출
- modal sheet 또는 absolute popup (320px width, max-height 400)
- 입력창 + 결과 리스트
- ↑↓로 이동, return 선택, esc 닫기

### 4.12 Sidebar 키보드 navigation

- ↑↓: 항목 이동
- ⌘1~9: 빠른 전환
- return/space: 활성화
- ⌘N: 새 워크스페이스
- ⌘Backspace: 삭제 (확인 alert)

### 4.13 Toast / Error 알림

- AppModel.error 변경 시 toast 우상단 등장
- 5초 자동 dismiss
- 클릭 시 즉시 dismiss

---

## 5. UX 라이팅 — 한글 친화 표준

### 5.1 원칙

| 원칙 | 예시 |
|---|---|
| **반말 X, 정중 X — 친근한 평어체** | "메시지 보내기" (X "메시지를 전송하십시오") |
| **명령형보단 동작/상태 표시** | "보내기" / "보내는 중" / "전송 완료" |
| **영어 전문용어 보존하되 옆에 한글 라벨** | `model · sonnet ▾` (라벨 영어 OK, popup 안에 한글 부제) |
| **에러는 원인 + 해결 + 재시도** | "Claude 응답이 끊어졌어요. 다시 시도하시겠어요?" |
| **빈 상태는 격려** | "여기서 첫 작업을 시작해보세요" |

### 5.2 라벨 통일표

| 위치 | 영어 (이전) | 한글 친화 (확정) |
|---|---|---|
| Composer placeholder | "Type a message..." | "무엇을 도와드릴까요? `/`로 명령, `@`로 노트" |
| SendButton idle | "send" | "보내기" |
| SendButton streaming | "stop" | "중단" |
| Composer footer model | "model · sonnet ▾" | "모델 · sonnet ▾" |
| Composer footer mode | "mode · default ▾" | "권한 · default ▾" |
| Composer footer effort | "effort · medium ▾" | "강도 · medium ▾" |
| Sidebar primary action | "+ 새 워크스페이스" | (유지) |
| Sidebar settings | "Settings" | "설정" |
| Sidebar group | "Workspaces" | "워크스페이스" |
| Sidebar empty | "아직 워크스페이스가 없습니다." | "아직 시작한 작업이 없네요." |
| Empty chat | "메시지를 입력해 시작하세요." | "여기서 새 작업을 시작해보세요." |
| Empty chat hint | "⌘ Return으로 전송, ⌘D 사용량, ⌘⌥I Inspector" | (유지 — 단축키는 영어 그대로) |
| No workspace title | "워크스페이스를 선택하거나 새로 만드세요" | "어떤 작업으로 시작할까요?" |
| Streaming badge | "streaming" | "응답 중" |
| ChatStatusBar ctx | "ctx" | "컨텍스트" (full label) / "ctx" (compact mode) |
| ChatStatusBar msg | "msg" | "메시지" |
| ChatStatusBar in/out | "in" / "out" | "입력" / "출력" (또는 monospace에서 in/out 그대로) |
| ChatStatusBar cost | "cost" | "비용" |
| Inspector active section | "active" | "활성" |
| Inspector context | "context" | "컨텍스트" |
| Inspector tokens | "tokens" | "토큰" |
| Inspector cost | "cost" | "비용" |
| Inspector recent tools | "recent tools" | "최근 도구" |
| Update card title | "업데이트 가능" | (유지) |
| Update card subtitle | "새 버전 v0.2 빌드" | "새 버전이 준비됐어요" |
| BottomUserCard tooltip | "설정 (⌘,)" | (유지) |
| Toolbar inspector tooltip | "Inspector — 윈도우가 좁아 사용 불가" | "Inspector — 창을 더 넓혀주세요 (1080px↑)" |
| Sidebar overlay backdrop | (없음) | "사이드바 외부 영역" (a11y label) |
| CreateWorkspaceSheet title | "새 워크스페이스" | "새 워크스페이스 만들기" |
| CreateWorkspaceSheet subtitle | "Claude CLI가 실행될 디렉토리를 선택하세요." | "어떤 폴더에서 시작할까요? Claude CLI가 그 위치에서 실행됩니다." |
| CreateWorkspaceSheet name field | "예: nunchi-v2" | "예: 내 새 프로젝트" |
| CreateWorkspaceSheet directory field | "예: ~/Documents/projects/..." | "예: ~/Documents/projects/내-프로젝트" |
| CreateWorkspaceSheet create button | "생성" | "만들기" |
| CreateWorkspaceSheet cancel | "취소" | (유지) |
| Dashboard title | "Usage Dashboard" | "사용량" |
| Dashboard close | "close" | "닫기" |
| Dashboard section "current session" | "current session" | "이번 세션" |
| Dashboard section "all time" | "all time (since launch)" | "앱 실행 후 누적" |
| Dashboard section "model pricing" | "model pricing" | "모델 가격" |
| Settings tabs (label만 유지) | "일반 / 모델·모드 / 편집 / Telegram / Anthropic" | (유지) |
| Settings claude path | "실행 경로" | "Claude CLI 위치" |
| Settings select binary | "선택…" | (유지) |
| Settings telegram enable | "Telegram 통합 활성화" | "텔레그램 알림 켜기" |
| Settings test telegram | "테스트 메시지 전송" | "테스트 메시지 보내보기" |
| Settings update token | "변경…" / "설정…" | "바꾸기" / "넣기" |
| Settings clear secret | "삭제" | "지우기" |
| Settings secret status | "설정됨" / "미설정" | "준비 완료" / "아직 안 넣음" |
| Error alert title | "오류" | "잠깐!" |
| Error alert OK | "확인" | "알겠어요" |
| Workspace context menu copy | "이름 복사" | (유지) |
| Workspace context menu delete | "삭제" | "지우기" |

### 5.3 동작별 메시지 패턴

| 상황 | 메시지 |
|---|---|
| 메시지 전송 시작 | (없음 — 즉시 표시) |
| Claude 응답 시작 | toolbar 뱃지 "응답 중" |
| Claude 응답 완료 | (no message — 자연스럽게 끝) + (옵션) telegram 알림 |
| Claude 비정상 종료 | "Claude가 응답을 멈췄어요 (exit \(N)). 다시 시도하시겠어요?" + [재시도] |
| Stream 에러 | "응답 중에 문제가 생겼어요: \(message). 다시 보내볼까요?" + [다시 보내기] |
| 설정 저장 실패 | "설정을 저장하지 못했어요: \(reason)" |
| Telegram 토큰 잘못됨 | "텔레그램 봇 토큰이 잘못된 것 같아요. BotFather에서 받은 토큰인지 확인해주세요." |
| 워크스페이스 디렉토리 없음 | "이 폴더를 찾을 수 없어요: \(path). 폴더가 옮겨졌거나 지워졌을 수 있어요." |
| Claude CLI 없음 | "Claude CLI를 \(path)에서 못 찾았어요. 설정에서 위치를 확인해주세요." |

---

## 6. 모든 버튼/컨트롤 동작 명세 (현재 상태 + 작업)

### 6.1 사이드바

| 컨트롤 | 현재 | 작업 |
|---|---|---|
| ⊟ 사이드바 토글 | ✅ 동작 | — |
| ⌕ 검색 | ❌ 빈 콜백 | ⌘P palette 호출 (stub) — popup view 작성 |
| + 새 워크스페이스 | ✅ | sheet 등장 |
| ⚙ Settings | ✅ | macOS Settings scene 호출 |
| 워크스페이스 클릭 | ✅ | 활성화 |
| 워크스페이스 우클릭 | ✅ "이름 복사" + "삭제" | "지우기" 라벨 변경 |
| 워크스페이스 ↑↓ keyboard | ❌ | List selection + .focusable() 또는 .focused |
| ⌘N | ✅ | 새 워크스페이스 |
| ⌘1~9 | ❌ | RootView .keyboardShortcut 추가 |
| Update card | ❌ 더미 | 버전 비교 로직 (v0.2) — 일단 클릭 시 GitHub release 페이지 열기 (URL 없음 → 임시 무동작) |
| BottomUserCard ⚙ | ✅ | Settings 호출 |

### 6.2 Toolbar

| 컨트롤 | 현재 | 작업 |
|---|---|---|
| ⊟ 사이드바 토글 | ✅ | — |
| Breadcrumb 클릭 | ❌ 빈 콜백 | dropdown menu (워크스페이스 리스트 + "+ 새") |
| 📊 Dashboard | ✅ | sheet 등장 |
| ▣ Inspector | ✅ (조건부) | — |
| layout badge | ✅ 표시 | — |
| streaming 뱃지 | ✅ | — |

### 6.3 Composer

| 컨트롤 | 현재 | 작업 |
|---|---|---|
| TextEditor | ✅ | — |
| model picker | ✅ | popup label 부제 한글화 |
| mode picker | ✅ | 동일 |
| effort picker | ✅ | 동일 |
| 📎 attachment | 0.5 opacity 빈 콜백 | tooltip "곧 지원" + 클릭 시 toast 안내 |
| send button | ✅ | "보내기"로 라벨 변경 |
| stop button | ✅ | "중단" 라벨 변경 |
| git meta row | ❌ 데이터 없음 | git diff --shortstat 호출 (v0.2, 일단 hidden 유지) |
| PR 생성 버튼 | ❌ 데이터 없음 | gh CLI 호출 (v0.3) |

### 6.4 ChatStatusBar / ContextInspector / UsageDashboard

대부분 표시 전용 — 라벨 한글화만.

### 6.5 Settings

대부분 동작 — 라벨/설명 한글화 + 일부 toggle 검증.

### 6.6 글로벌 키보드

| 단축키 | 동작 | 현재 |
|---|---|---|
| ⌘N | 새 워크스페이스 | ✅ |
| ⌘W | 현재 닫기 | ❌ — 추가 |
| ⌘Q | 종료 | ✅ macOS 기본 |
| ⌘, | Settings | ✅ |
| ⌘D | Dashboard | ✅ |
| ⌘⌥1 | Sidebar toggle | ✅ |
| ⌘⌥I | Inspector toggle | ✅ |
| ⌘P / ⌘K | 워크스페이스 검색 palette | ❌ — 추가 |
| ⌘1~9 | 워크스페이스 빠른 전환 | ❌ — 추가 |
| ⌘+Return | 메시지 전송 | ✅ |
| Esc | streaming cancel / popup 닫기 | ✅ |
| / (composer) | slash command popup | ❌ — 다음 라운드 |
| @ (composer) | mention popup | ❌ — Obsidian v0.2 |

---

## 7. 단계별 구현 순서 (이번 라운드)

### 우선 (이번 응답)
1. ✅ 명세서 작성
2. Theme.Brand namespace + accent 교체 (orange → orange-red 톤)
3. FlatButton/IconButton hover scale + press scale 추가
4. 모든 라벨 한글 친화 (5.2 표)
5. Sidebar ↑↓ keyboard nav + ⌘1~9
6. Breadcrumb workspace switcher menu
7. Sidebar search → ⌘P palette stub (sheet)
8. ⌘W (current workspace 닫기 — soft, selection 해제만)
9. Settings 라벨 한글화
10. Toast 컴포넌트 (error 표시용)

### 다음 라운드
- 로고 SVG 디자인 + .icns 생성
- Settings Form 자체 flat 컴포넌트
- Reduce-motion 자동 감지
- Slash command palette 본격 구현
- Update card 실제 동작
- About 화면 (브랜드 마크 표시)

---

## 8. 검증 매트릭스 (자체 점검)

| 영역 | 항목 | 검증 |
|---|---|---|
| 색 | brand.accent가 모든 active 상태에 적용 | grep `Theme.Color.accent` → 일관 사용 |
| 색 | 사용자 메시지 배경 brand.accentMuted | MessageBubble.swift:UserBg |
| 인터랙션 | 모든 button에 hover/press 시각 변화 | FlatButton/IconButton 코드 확인 |
| 라이팅 | 모든 한글 라벨 5.2 표 일치 | 각 view의 Text() literal grep |
| 키보드 | ⌘1~9 / ⌘W / ⌘P 동작 | 수동 테스트 |
| 동작 | breadcrumb 클릭 시 menu | 수동 |
| 동작 | sidebar search 클릭 시 palette | 수동 |
| 동작 | workspace ↑↓ | 수동 |

---

## 9. Open Questions (사용자 답변 필요)

| Q | 질문 |
|---|---|
| Q-A | **ar2r 자전거 팀의 정확한 이름과 컬러는?** Instagram 핸들, Strava 클럽 링크, 또는 저지 사진 hex 알려주세요. (현재는 fallback navy + orange-red 사용 중) |
| Q-B | 로고에 자전거 모티프를 넣을까요? (페달, 체인, 휠) 또는 단순 모노그램만? |
| Q-C | 앱 이름 "Yuminai"의 의미/유래 (브랜드 메시지에 사용) |
| Q-D | About 화면 / splash 화면 필요? |
| Q-E | 다크/라이트 모두 지원? (현재 다크 first, light 토큰만 정의) |
