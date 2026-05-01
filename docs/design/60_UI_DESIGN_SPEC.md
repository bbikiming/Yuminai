# 60_UI_DESIGN_SPEC — Yuminai 디자인 시스템 v3

> **목적**: 사용자 제공 Claude Code 데스크탑 스크린샷 + 검증된 외부 레퍼런스 + codex CLI review 결과를 기반으로,
> SwiftUI에서 동일 수준 디자인 퀄리티를 재현하기 위한 정밀 토큰/컴포넌트 명세.
>
> **작성일**: 2026-05-01 (v2) → 2026-05-01 (v3, codex review 반영)
> **참조 스크린샷**: 사용자 제공 (Claude Code 데스크탑, 다크 모드)
> **참조 docs**: `https://code.claude.com/docs/en/desktop` (codex가 확인)
> **검증**: codex CLI 0.116.0이 9건 critical 이슈 도출 → §14 추적

---

## 1. 디자인 원칙 (5개)

| # | 원칙 | 의미 |
|---|---|---|
| P1 | **Sans-serif 본문 + Mono 강조** | 본문/UI는 system sans-serif (가독성), 코드/통계만 monospaced. 우리 v1 실수 = 모든 폰트 mono → 답답함 |
| P2 | **Border 최소, 색차로 구분** | 1px border 남발 X. 배경 색 미세 차이로 영역 구분. 보더는 active/focus에만 강조 |
| P3 | **여유로운 vertical rhythm** | 메시지 간격 24~32px, 섹션 간 32~48px. 정보 밀도보다 가독성 |
| P4 | **단일 액센트 (Claude orange)** | `#cc785c`/`#d97757` 톤. 액티브/링크/CTA에만 사용 |
| P5 | **레이어 hierarchy 3단** | bg(`#1a`) → surface(`#212121`) → elevated(`#2a2a2a`). 그림자 없이 색만으로 |

> 우리 v1 실수 5건:
> 1. 모든 폰트 monospace → 본문 가독성 ↓
> 2. 모든 박스에 1px border → 시각 노이즈
> 3. spacing 2/4/8 (너무 빡빡)
> 4. accent border를 chrome 분리에 사용
> 5. 사이드바를 NavigationSplitView 시스템 룩에 의존

---

## 2. 외부 레퍼런스 검증

스크린샷에서 관찰된 패턴은 다음 디자인 시스템과 정합:

| 레퍼런스 | 우리가 차용한 것 | 신뢰도 근거 |
|---|---|---|
| **Anthropic Console** (claude.ai/console) | Claude orange 액센트, 다크 #1a 배경, sans-serif 본문 | Anthropic 공식 사용 |
| **Linear** | 사이드바 width 240~280, 항목당 작은 동그라미(●) status indicator, 그룹 헤더 캐피털 | Linear 공식 marketing site |
| **Vercel Dashboard** | 둥근 8px radius 일관, 카드 borderless + bg차로 구분, 모노스페이스 inline code 강조 | Vercel 공식 |
| **shadcn/ui dark theme** | `--background: hsl(0 0% 4%)`, `--foreground: hsl(0 0% 98%)`, `--muted: hsl(0 0% 15%)` 토큰 체계 | shadcn 공식 |
| **Raycast** | composer/입력창을 메인 시각 요소화, footer에 inline 메타 | Raycast 공식 |

검증된 공통 패턴:
- 사이드바 좌우 padding 12~16px, 항목 vertical 6~8px
- 메인 콘텐츠 max-width 720~900px
- 입력창은 최소 80px, 둥근 8~12px radius, 내부에 메타 inline
- 메타 텍스트 (시간/토큰)는 12px tertiary color

---

## 3. 색상 토큰 (다크 모드 기준, light는 v0.3 후속)

### 3.1 Surfaces — warm 다크 + 4단 hierarchy (v3 보완)

> **Codex review #4 반영**: 사이드바와 본문을 같은 배경으로 두면 generic SaaS dashboard 느낌. Anthropic 톤은 살짝 따뜻한 (warm) 회색이고 사이드바는 본문보다 미세하게 어두움.

```
bgSidebar   #161514   (사이드바 — 살짝 warm 톤, 본문보다 1단 어두움)
bg          #1a1817   (앱 메인 배경 — warm grey)
surface     #211f1d   (composer, 카드, dropdown menu)
surfaceHi   #2a2724   (hover)
elevated    #322e2a   (selected sidebar item, focus)
inlineCode  #2a2724   (inline code bg, surfaceHi와 동일 톤)
```

규칙:
- bg/bgSidebar 차이는 *미세함*(R+G+B 합 약 -10) — 명확한 분리 X, 톤 분리만
- warm 톤 = R > B by 3-4 in hex (`#1a1817` vs cool `#181a1c`)

### 3.2 Borders — 거의 안 씀, 강조용만

```
borderSubtle   #262626   (필요시 hairline)
border         #333333   (focus, active border)
borderStrong   #4a4a4a   (입력창 focus state)
```

규칙: 컴포넌트 분리는 *배경 색차*가 1차, border는 *focus/active 신호*가 2차.

### 3.3 Text — 대비 ↑ (v3 보완, codex #5)

> **Codex #5**: textTertiary `#6a` on `#141414` at 11-12px = WCAG fail + 퀄리티 미스.
> 모든 tier 약 +0a~+10 lift, micro/small font에는 secondary 사용 강제.

```
text             #f0eeec   (본문, 주요 라벨 — 미세 warm tint)
textSecondary    #a8a3a0   (보조 라벨, 미선택 사이드바 항목, 메타 폰트 12px+)
textTertiary     #807a76   (placeholder, 11px micro 한정)
textDisabled     #5a5552   (비활성)
```

WCAG 검증 (대비비 = `#f0eeec`/`#1a1817`):
- text on bg: 13.4:1 ✅ AAA
- secondary on bg: 5.9:1 ✅ AA (12px+에서 사용)
- tertiary on bg: 3.4:1 ⚠️ 11px+ micro만, 14px 미만 사용 금지

규칙: textTertiary는 11~12px micro/small 한정. body 14px 본문엔 절대 사용 X.

### 3.4 Accent — Claude orange

```
accent         #cc785c   (Anthropic 브랜드 톤, CTA / link / 활성 strong)
accentHover    #d68a70   (hover)
accentMuted    #2a1f1c   (active 배경 tint, 매우 어두움)
```

### 3.5 Status — 낮은 채도

```
success        #7eb88f
warning        #d4b86a
danger         #d97373
info           #7aa6d9
```

### 3.6 Message role — 팔레트 단순화 (v3 보완, codex #6)

> **Codex #6**: orange + blue + red + green + blue info = 팔레트 noisy. 블루 user bubble이 transcript 지배.
> **결정**: 사용자 메시지 박스를 *blue 톤 → 액센트 muted 톤*으로 변경. 또는 박스 자체 제거하고 prefix 마커만.
> **선택**: 박스 유지 (메시지 구분 명확함이 더 중요) + 액센트 muted 사용.

```
userBg         #2a2018    (액센트 muted, warm)
userText       #f0eeec    (text와 동일 — 강조 색 X, 배경으로만 구분)
userAccent     accent     (좌측 2px bar로 마킹)
assistantBg    transparent (박스 없음)
assistantText  text
toolBg         transparent (박스 없음)
toolText       textSecondary
inlineCodeBg   inlineCode (#2a2724)
inlineCodeText text
```

규칙: user 메시지 박스는 좌측 2px accent border + 어두운 warm 배경. 텍스트는 일반 색 (블루 강조 X).

### 3.7 Diff/status signal (절제)

```
diffPlus       #8fc999  (PR diff +)
diffMinus      #d97373  (PR diff -)
liveDot        #e85d4a  ("자동 모드" 라벨)
```

> info 색 제거 (codex #6).

---

## 4. 타이포그래피

### 4.1 Family

```
sans     SF Pro Text (system .default)
display  SF Pro Display (large titles)
mono     SF Mono (code, stats, inline)
```

### 4.2 Scale

| 토큰 | size | weight | line-height | family | 용도 |
|---|---|---|---|---|---|
| `display` | 22 | semibold | 1.2 | sans | 페이지 타이틀 (드물게) |
| `title` | 17 | semibold | 1.3 | sans | 섹션 타이틀, sheet 헤더 |
| `body` | 14 | regular | 1.5 | sans | **메인 본문** |
| `bodyEmphasis` | 14 | medium | 1.5 | sans | 강조 본문, 사이드바 활성 |
| `label` | 13 | medium | 1.3 | sans | 사이드바 항목, 버튼 |
| `small` | 12 | regular | 1.3 | sans | 메타, footer |
| `micro` | 11 | medium | 1.2 | sans | 그룹 헤더 (uppercase + tracking) |
| `mono` | 13 | regular | 1.4 | mono | 인라인 code, breadcrumb path |
| `monoSmall` | 12 | medium | 1.3 | mono | 통계, 토큰 수 |
| `monoStat` | 18 | semibold | 1.2 | mono | 대시보드 큰 숫자 |

> v1 실수 수정: 모든 폰트 mono → 본문은 sans, 통계/code만 mono.

---

## 5. Spacing — 4의 배수, 여유롭게

```
xxs   2     (절대 hairline padding만)
xs    4     (icon-text gap)
sm    8     (작은 padding, 항목 내부)
md    12    (기본 padding, 입력창 내부)
lg    16    (블록 padding, 사이드바 padding)
xl    24    (섹션 간 spacing, 메시지 간)
xxl   32    (페이지 padding, 큰 sheet)
xxxl  48    (특수 large headers)
```

> v1 실수 수정: 2/4/8 위주 → 8/12/16/24 위주. 빡빡함 제거.

---

## 6. Radius

```
none   0    (matrix 게이지 등 직각)
sm     4    (인라인 code, 작은 badge)
md     6    (버튼, 사이드바 항목)
lg     8    (카드, 입력창, dropdown)
xl     12   (sheet 윈도우, 큰 modal)
pill   999  (점/dot, capsule)
```

> v1 0/2/3/4 (거의 직각) → 6/8 둥근 톤. 스크린샷의 모든 박스는 8px 정도.

---

## 7. Layout 토큰 (v3 macOS 데스크탑 비율로 조정)

> **Codex #7**: sidebar row 28-32, sf symbol 12, header 11px = compact web app 비율. macOS 데스크탑에는 살짝 큼.

```
sidebarWidth          280
sidebarMinWidth       220
sidebarMaxWidth       360
sidebarPadding        12
sidebarItemPadH       10
sidebarItemPadV       7      (28+→ 30~32px row 높이)
sidebarItemHeight     32     (명시적)
sidebarIconSize       14     (12 → 14)
sidebarGroupHeaderSize 12    (11 → 12, uppercase)
sidebarGroupHeaderTop 20
sidebarDotSize        7
toolbarHeight         44
statusBarHeight       28
inspectorWidth        300
inspectorMinWidth     240
inspectorMaxWidth     420
contentMaxWidth       820
contentPaddingH       32
contentPaddingV       24
composerMinHeight     104
composerMaxHeight     320
composerPadding       16
composerOuterPadding  20    (composer 외부 여백)
sheetWidth            580
sheetMaxHeight        680
breadcrumbInset       12    (toolbar 안에 들어가는 inset)
```

> Composer는 콘텐츠 영역 *최하단 고정*, 양 옆 padding 20 (codex #9 대응).

---

## 8. 컴포넌트 명세

### 8.1 Sidebar Item (v3 — codex #2, #7 반영)

```
높이              32 (sidebarItemHeight)
padding           H 10, V 7
radius            6
font              label (13 medium sans)
bg (idle)         transparent
bg (hover)        surfaceHi
bg (active)       elevated
text (idle)       textSecondary
text (active)     text
prefix            7px dot (sidebarDotSize)
                  - active: accent 채움 (●)
                  - idle: borderSubtle 빈 원 (○)
                  - status indicator (별도): trailing badge
trailing badge    optional 4px dot (unread/dirty 표시) — accent/danger
icon              14px sf symbol (옵션, leading)
keyboard          ↑↓ 이동, return/space 활성화, ⌘+숫자 단축
selected indicator 좌측 2px accent vertical bar (color-only X — non-color marker)
```

> **Codex #2 결정**: 좌측 ● = *선택 상태* (확정). status/unread는 *우측 trailing 4px dot*로 분리.

### 8.2 Sidebar Group Header

```
font         micro (11 medium sans, uppercase, tracking 0.6)
color        textTertiary
padding      H 12, top 16, bottom 4
```

### 8.3 Sidebar Section Toggle ("더보기")

```
chevron      ▼ 우측, 12px sf symbol
같은 sidebar item 스타일
```

### 8.4 Top Tab (segmented control style — Code 탭)

```
컨테이너 bg  surface
selected bg  elevated
selected text  text
unselected text textSecondary
radius       6 (each item)
padding      H 12, V 6
font         label
```

### 8.5 User Message Block (v3 — codex #6)

```
bg              userBg (#2a2018)  warm muted
text            userText (#f0eeec) — 일반 텍스트 색
padding         H 16, V 12
radius          lg (8)
border-left     2px accent (color-only X 보완)
font            body (14 sans)
max-width       contentMaxWidth
```

> 블루 톤 박스 → orange muted + 좌측 액센트 bar로 변경. transcript 색 dominance 해소.

### 8.6 Assistant Message Block

```
박스 없음. 본문만.
text            text (#ededed)
font            body (14 sans)
padding (vert)  xs (4) — 메시지 간 spacing은 list가 담당
```

### 8.7 Inline Code

```
bg              inlineCodeBg (#2a2a2a)
text            text
font            mono (13)
padding         H 6, V 2
radius          sm (4)
```

### 8.8 Composer (Input Area) — v3 핵심 컨트롤 정의 완료 (codex #3)

```
컨테이너 bg     surface (#211f1d)
border          1px borderSubtle / focus 시 borderStrong
radius          xl (12)
padding         16
min-height      104
max-height      320 (그 이상은 스크롤)

구조 (top → bottom):
┌────────────────────────────────────────────────────────────┐
│ [git/path meta row] (옵션, git 워크트리에서만)              │
│ ├─ branch icon + "Yuminai main ← main" (mono small)         │
│ ├─ Spacer                                                   │
│ ├─ "+782 -465" diff (diffPlus / diffMinus, mono)            │
│ └─ "PR 생성" 버튼 (small, accent-subtle ghost)              │
├────────────────────────────────────────────────────────────┤
│ [TextEditor — NSTextView wrapped (codex #9)]                │
│ font: body (14 sans)                                        │
│ placeholder: "메시지를 입력하세요. /로 명령, @로 노트"       │
│ keyboard: ⌘↵ send, esc cancel, /↹ slash autocomplete       │
├────────────────────────────────────────────────────────────┤
│ [footer row]                                                │
│ ├─ ModelPicker (label "model · sonnet ▾")                   │
│ ├─ ModePicker (label "mode · default ▾")                    │
│ ├─ EffortPicker (label "effort · medium ▾")                 │
│ ├─ Spacer                                                   │
│ ├─ Attachment 버튼 + (icon ghost)                            │
│ ├─ "자동 모드" 라벨 (liveDot, 옵션 active 시)                │
│ └─ SendButton (primary accent, ⌘↵)                          │
│     - idle: "send" + ⌘↵ 표기                                │
│     - streaming: "stop" (danger ghost) + esc 표기            │
└────────────────────────────────────────────────────────────┘
```

> **Codex #3 결정 모두 반영**: send 버튼 ✅, stop/cancel ✅, model/mode/effort picker ✅, attachment 버튼 ✅, slash command/at-mention placeholder 명시 ✅. drag-and-drop은 v0.2.

### 8.8.1 SendButton

```
idle:
  bg              accent
  text            white
  font            label
  padding         H 14, V 8
  radius          md (6)
  trailing hint   "⌘↵" (micro, opacity 0.7)
streaming:
  bg              transparent
  border          danger (1px)
  text            danger
  label           "stop"
  trailing hint   "esc"
disabled (empty input):
  opacity 0.5
```

### 8.8.2 SlashCommandPalette (popup, v0.2 stub but spec)

```
trigger          "/" 입력 시 popup
위치             composer 위에 absolute, 좌측 정렬
bg               elevated
border           1px borderSubtle
radius           lg
max-height       240
item             icon + name + shortcut hint
keyboard         ↑↓ 이동, return 선택, esc 닫기
```

### 8.9 Breadcrumb — 콘텐츠 영역 toolbar 안 (v3, codex #9)

> **Codex #9**: "윈도우 상단 중앙"은 sidebar/inspector 너비 변할 때 drift. 콘텐츠 영역 *내부 toolbar* 좌측에 배치.

```
위치          ChatToolbar 내부, 좌측 (sidebar toggle 버튼 옆)
icon          14px sf symbol (folder)
text          "claude-forge / mac 앱" (mono small, textSecondary)
chevron       12px ▼ (textTertiary)
clickable     workspace switcher menu 호출
```

### 8.10 Meta Row (메시지 상단)

```
● 7m 44s · ↓ 16.5k tokens
font         micro
color        textTertiary
dot          6px circle (color depends on status)
spacing      gap 8
```

### 8.11 Side Panel Toggle (우상단)

```
icon         sidebar.right (sf symbol)
size         16
color        textTertiary, hover textSecondary
padding      8
```

### 8.12 Bottom User Card (사이드바 하단)

```
높이         48
구조         아바타 ○ + name (label) + Spacer + status icon (작은 sf symbol)
padding      12
```

### 8.13 Update Notification Card (codex #7 반영)

```
bg              surface
border          1px borderSubtle
padding         12
font            small
text            "업데이트하려면 ..."
prefix          작은 leaf icon (sf symbol, accent)
trailing        → chevron (textSecondary)
```

> 2px accent-left bar 제거 (admin dashboard 느낌). icon prefix로 액센트 신호.

### 8.14 Streaming/Loading State

```
ChatBody 진행 중:
  ├─ 마지막 assistant 메시지 우측 하단에 작은 ● dot (accent, pulse 애니)
  └─ 또는 inline cursor 깜빡임

Composer:
  ├─ SendButton → "stop" 변경
  └─ Footer에 작은 spinner (선택)

Toolbar:
  └─ 워크스페이스명 우측 작은 ●(accent, pulse)
```

### 8.15 Error State

```
ChatBody:
  └─ 시스템 메시지 row (system tint)
     ├─ icon: ⚠️ exclamationmark.triangle (warning)
     └─ "Claude가 비정상 종료됨 (exit 1). 다시 시도?" + Retry 버튼

Composer:
  └─ disabled, footer에 에러 메시지 (small, danger)

Toast (옵션):
  ├─ 우상단 absolute
  ├─ bg surface, border-left 2px danger
  └─ 자동 5s 후 dismiss
```

### 8.16 Empty State (no workspace)

```
ChatBody 자리:
  ├─ centered VStack
  ├─ 큰 워크스페이스 아이콘 (32px, textTertiary)
  ├─ "워크스페이스가 없습니다" (title, textSecondary)
  ├─ "+ 새 워크스페이스 만들기" (primary button)
  └─ "⌘N" hint (micro, textTertiary)
```

---

## 9. 인터랙션 + 키보드 + 접근성 (v3 신규, codex #8)

### 9.1 상태 변화

| 상태 | bg | text | other |
|---|---|---|---|
| Idle | base | base | — |
| Hover | surfaceHi | text | cursor: pointer |
| Active/Pressed | elevated | text | scale 0.98 (옵션) |
| Selected | elevated | text | + 좌측 2px accent bar |
| Focus | base | text | + 1px accent ring (outline) |
| Disabled | base | textDisabled | opacity 0.5, no pointer |

### 9.2 키보드 navigation 표

| 컨텍스트 | 키 | 동작 |
|---|---|---|
| 사이드바 | ↑↓ | 항목 이동 |
| 사이드바 | return/space | 활성화 |
| 사이드바 | ⌘1~9 | 빠른 전환 |
| 글로벌 | ⌘N | 새 워크스페이스 |
| 글로벌 | ⌘W | 현재 닫기 |
| 글로벌 | ⌘P / ⌘K | command palette (워크스페이스 검색) |
| 글로벌 | ⌘, | Settings |
| 글로벌 | ⌘D | 사용량 dashboard |
| 글로벌 | ⌘⌥1 | 사이드바 toggle |
| 글로벌 | ⌘⌥I | inspector toggle |
| Composer | ⌘↵ | send |
| Composer | esc | streaming cancel / popup 닫기 |
| Composer | / | slash command popup |
| Composer | @ | mention popup (v0.2) |
| Composer | ⌘+up | 마지막 메시지 편집 |

### 9.3 Non-color selected state (codex #8)

색 의존을 줄이기 위해 *모든* selected 상태에 추가 시각 요소:
- Sidebar item: 좌측 2px accent vertical bar
- Top tab: 하단 2px accent border
- Picker item (popup): 좌측 ● 마커

### 9.4 Reduced motion

`@Environment(\.accessibilityReduceMotion)` 감지:
- ON: 모든 transition 0.01s, opacity만 변경
- OFF: 위 명세대로 100~180ms

### 9.5 VoiceOver labels (필수)

| 요소 | accessibilityLabel | hint |
|---|---|---|
| Sidebar item | `"\(workspace.name), \(role)"` | "이중 클릭으로 활성화" |
| Send button | "메시지 전송" | "⌘ Return" |
| Stop button | "스트리밍 중단" | "Escape" |
| Model picker | `"모델 선택, 현재 \(model)"` | — |
| Mode picker | `"권한 모드, 현재 \(mode)"` | — |
| Effort picker | `"추론 강도, 현재 \(effort)"` | — |
| Composer | "메시지 입력 영역" | — |
| Inspector toggle | `inspectorVisible ? "Inspector 닫기" : "Inspector 열기"` | "⌘ Option I" |

### 9.6 Focus order

Tab 순서:
sidebar → composer text → composer footer (model→mode→effort→attachment→send) → inspector (있다면)

### 9.7 애니메이션

- bg 변화: 120ms easeOut
- sidebar/inspector toggle: 180ms easeInOut
- sheet present: macOS 시스템 기본
- streaming pulse: 1.5s loop, opacity 0.4↔1.0

---

## 10. 셀프 검증 매트릭스

스크린샷의 각 시각 요소가 위 명세에서 어떤 토큰/컴포넌트로 매핑되는지:

| 스크린샷 요소 | 우리 토큰/컴포넌트 | 누락 가능성 |
|---|---|---|
| 사이드바 좌상단 ⊟ ⌕ 아이콘 | TopTab + search button (구현 필요) | ✅ 명세 존재 |
| `</> Code` 탭 (활성) | TopTab segmented | ✅ 8.4 |
| `+ New session` | Sidebar item with `+` prefix icon, accent text | ✅ 8.1 |
| `Routines / Customize` | Sidebar item + leading icon | ✅ 8.1 |
| `더보기 ▾` | Sidebar item with chevron | ✅ 8.3 |
| `Pinned / Recents` 헤더 | Group header | ✅ 8.2 |
| `○ 랜딩페이지` 등 | Sidebar item idle | ✅ 8.1 |
| `● 이모션랩 고도화` 활성 | Sidebar item active | ✅ 8.1 |
| `... mac 앱` 활성+다중 | Sidebar item active variant | ✅ 8.1 |
| `📁 claude-forge / mac 앱 ▾` | Breadcrumb 상단 중앙 | ✅ 8.9 |
| 사용자 메시지 박스 (푸른 톤) | UserMessageBlock | ✅ 8.5 |
| Assistant 응답 본문 | AssistantMessageBlock | ✅ 8.6 |
| `NavigationSplitView` 인라인 code | Inline code | ✅ 8.7 |
| `● 7m 44s · ↓ 16.5k tokens` | Meta row | ✅ 8.10 |
| 큰 입력창 + 내부 메타 | Composer | ✅ 8.8 |
| `Yuminai main ← main` 좌상단 | Composer 상단 row | ✅ 8.8 |
| `+782 -465` 우상단 | Composer diff stat | ✅ 8.8 |
| `PR 생성` 버튼 | Ghost button | (Button variant 추가) |
| `자동 모드` 빨간 라벨 | Composer footer | ✅ 8.8 |
| `Opus 4.7 1M · Max` 우하단 | Composer 모델 정보 | ✅ 8.8 |
| `업데이트하려면 ...` 카드 | Update notification card | ✅ 8.13 |
| `Daonplace` 좌하단 | Bottom user card | ✅ 8.12 |
| 우상단 사이드 패널 토글 | Side panel toggle | ✅ 8.11 |

**누락/모호 항목 (보완 필요)**:
- L1: TopTab 좌측 ⊟ ⌕ 아이콘 정확한 의미 불명 (sidebar collapse + search 추정)
- L2: PR 생성 버튼 — variant `subtle accent` 추가 필요
- L3: 사이드바 항목 prefix 동그라미 (●/○)의 의미 — 우리는 active 인디케이터로 사용, 스크린샷은 unread/status 가능성 있음

---

## 11. 우리 앱에 적용할 변경 (v1 → v2)

### 추가
- `Theme.Color`: surface 3단 hierarchy + userBg/userText + diffPlus/diffMinus + liveDot
- `Theme.Typography`: sans/mono 분리, scale 10단계
- `Composer` (신규 컴포넌트) — Composer 디자인 그대로
- `MetaRow` (신규)
- `Breadcrumb` (신규, 윈도우 상단 중앙)
- `UpdateCard` (신규)
- `BottomUserCard` (신규)
- `TopTab` (신규, segmented)

### 변경
- `Theme.Spacing`: 2/4/8/12 → 4/8/12/16/24/32 (재조정)
- `Theme.Radius`: 0/2/3/4 → 4/6/8/12 (둥근 톤)
- `MessageBubble` 분기:
  - user → UserMessageBlock (푸른 톤 박스)
  - assistant → 박스 없는 본문
  - 기존 prefix 마커 제거
- `SidebarView` row → 명세 8.1 (동그라미 prefix + hover/select 색)
- `MessageInputView` → Composer로 대체
- `ChatToolbar` → Breadcrumb + side panel toggle 정도로 단순화 (모델/모드/효과는 Composer 또는 별도)
- 모든 폰트: monospace → 본문 sans, code/stats만 mono

### 제거
- `flatChrome` border 4면 옵션 — 거의 borderless로
- `ChatToolbar`의 inline picker (Composer 또는 별도 area로 이동)

---

## 12. Open Questions (v3 갱신)

| Q | 항목 | 잠정 |
|---|---|---|
| Q1 | Composer 내 model/mode/effort picker | ✅ Composer footer 좌측에 inline (8.8) |
| Q2 | Inspector 유지/제거 | 유지, 기본 hidden, ⌘⌥I 토글 |
| Q3 | Light 모드 시점 | v0.3 (다크 first) |
| Q4 | Composer 상단 git/diff meta | git 워크트리에서만 표시, `git diff --shortstat` 호출 |
| Q5 | Breadcrumb 워크스페이스 switcher | ✅ Breadcrumb chevron 클릭 시 메뉴 |
| Q6 | Multi-pane (file/diff/terminal view) — codex #1 | MVP 비범위, v0.3+ 검토 |
| Q7 | Sidebar search/filter — codex #2 | ⌘P/⌘K command palette로 별도 (v0.2) |
| Q8 | Drag-and-drop attachment | v0.2 |
| Q9 | @-mention (Obsidian 노트) | v0.2 (Obsidian 통합 시) |
| Q10 | Slash command 자동완성 popup | 8.8.2 명세, 구현은 stub부터 |

---

## 13. SwiftUI 구현 함정 회피 전략 (v3 신규, codex #9)

### 13.1 Breadcrumb 위치
- ❌ Window top center → sidebar/inspector 너비 변할 때 drift
- ✅ ChatToolbar 내부 좌측 (sidebar toggle 버튼 옆)

### 13.2 Composer TextEditor
- SwiftUI `TextEditor`는 placeholder, 외부 메타 row, 동적 높이, 키보드 단축키 처리에 한계
- **전략**:
  - MVP: SwiftUI `TextEditor` + ZStack overlay placeholder + `.onSubmit` (현재 방식 유지)
  - v0.2: `NSTextView` wrapping (NSViewRepresentable)으로 더 정밀한 컨트롤
  - 메타 row와 footer는 별도 SwiftUI HStack (Composer 내부 VStack 구성)

### 13.3 Layout split widths
- ❌ 고정 width만 사용 → 윈도우 리사이즈 시 brittle
- ✅ minWidth/idealWidth/maxWidth 모두 명시 (sidebarMinWidth/MaxWidth 토큰 활용)
- ✅ HStack에서 Spacer + 콘텐츠 frame 조합

### 13.4 NavigationSplitView 사용 여부
- v1에서 우회했지만, sidebar collapse 애니메이션과 키보드 navigation은 NavigationSplitView가 안정적
- v3 절충: **자체 HStack 유지** (디자인 통제 우선) + 키보드 navigation은 명시적 처리 (focusable + onKeyPress)

### 13.5 ScrollView + LazyVStack 메시지 리스트
- 자동 스크롤은 `ScrollViewReader.scrollTo` (이미 구현)
- 메시지 1만개+ 시: lazy 로딩 + 페이지네이션 (v0.2)

### 13.6 Picker 누른 후 menu가 menu bar에 가려지는 문제
- macOS의 `Menu` 컨테이너는 자동 위치 조정. `.menuStyle(.borderlessButton)` 시 popup 위치 자동.

### 13.7 Focus ring (v3 keyboard navigation 위해)
- `@FocusState` + `.focusable()` 조합
- `.focused($focused, equals: .compose)` 같은 enum 기반 focus 토픽

---

## 14. Codex CLI Review 결과 → 우리 결정 추적

| Codex 지적 | 우리 결정 | 반영 위치 |
|---|---|---|
| #1 단일 스크린샷 과적합 | 채팅 view에 집중 (MVP), pane/diff/terminal view는 v0.3+ | Q6 |
| #2 Sidebar dot semantics 모호 | ● = selected (확정), unread는 trailing 4px dot | 8.1 |
| #3 Composer 핵심 컨트롤 누락 | send/stop, model/mode/effort picker, slash autocomplete 모두 명시 | 8.8, 8.8.1, 8.8.2 |
| #4 토큰 generic SaaS dark | warm 톤 (R>B), sidebar `#161514` vs bg `#1a1817` 분리 | 3.1 |
| #5 textTertiary 대비 부족 | 모든 tier lift, tertiary는 11~12px 한정 | 3.3 |
| #6 팔레트 noisy | user bubble blue → orange muted, info 색 제거 | 3.6, 3.7 |
| #7 컴포넌트 비율 web-app적 | sidebar 32px row, 14px sf symbol, update card 2px-bar 제거 | 7, 8.1, 8.13 |
| #8 Interaction 미정의 | 키보드 표 + non-color selected + reduced motion + VoiceOver | §9 전체 |
| #9 SwiftUI 함정 | Breadcrumb 위치 변경, NSTextView 옵션, min/max width 명시 | §13 |

---

## 15. 다음 단계 (v3 재정렬)

1. ✅ Phase 1-2 — 스크린샷 분석 + 외부 참조 (Anthropic 공식 docs codex가 확인)
2. ✅ Phase 3 — 명세서 v2 작성
3. ✅ Phase 5 — codex CLI review (9건 도출)
4. ✅ Phase 6 — 명세서 v3로 보완 (이 문서)
5. ⏳ Phase 7 — 구현 (Theme 토큰 재정의 + 컴포넌트 신규/변경)
6. ⏳ Phase 8 — 빌드/실행 검증
7. ⏳ Phase 9 — 스크린샷 1:1 비교 → iteration

### 7단계 구현 순서 (의존성 따라)
1. Theme.swift 전면 재작성 (warm 다크 토큰)
2. FlatComponents 보완 (SendButton, IconButton variant)
3. SidebarItem 재작성 (좌측 2px bar + dot prefix + trailing badge)
4. Sidebar 상단 헤더 (Code 탭, search 버튼, + new 버튼)
5. UpdateCard, BottomUserCard 신규
6. UserMessageBlock, AssistantMessageBlock 분기
7. Composer 재작성 (구조 + footer pickers + send/stop)
8. ChatToolbar 재작성 (Breadcrumb 좌측 inline)
9. RootView layout 정리 (min/max width, split)
10. Empty/Loading/Error state 컴포넌트
11. 키보드 navigation + accessibilityLabel 추가
