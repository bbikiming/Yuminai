# Changelog

> 변경 사항 시간순 기록. 의미 있는 변경만.

## [Unreleased] — 2026-05-01

### Changed/Added — Settings macOS 네이티브 정렬 + 첨부 파일 기능 (ADR-020)

사용자 보고: "설정 팝업 깨진 layout (라벨/컨트롤 우측 몰림, helper 잘림). 맥 네이티브 설정 메뉴 퀄리티로 정렬." + "첨부파일 업로드 동작화 + 안내 문구"

처리:
1. **SettingsView 전면 재구성**:
   - `.formStyle(.grouped)` macOS 표준 — System Settings와 동일한 GroupBox 룩
   - `LabeledContent` 사용 — 좌측 라벨 + 우측 컨트롤 자동 정렬
   - 모든 Section은 `Section { } header: { } footer: { }` 명시적 형식 (macOS 26 SwiftUI ambiguity 회피)
   - 윈도우 minWidth 640 → idealWidth 720 → maxWidth 880, height 480~760
   - 라벨 일관 한글 ("Permission mode" → "권한 모드", "Effort" → "강도")
   - Toggle에 helper 텍스트 inline VStack 패턴 (시스템 룩)
   - Stepper에 `+2pt` 같은 monospaced digit 표시
   - SecretField는 inline status badge (✓ 준비 완료 / ⚠ 에러 / 아직 안 넣음) + "바꾸기/넣기/지우기" 버튼

2. **첨부 파일 기능 동작화**:
   - `AppModel.attachedFiles: [URL]` state 추가
   - `openAttachmentPicker()` — NSOpenPanel (파일+폴더, 다중 선택, "Claude가 함께 살펴볼 파일이나 폴더를 선택하세요" 안내)
   - `removeAttachment(_:)` / `clearAttachments()`
   - `sendMessage()` — 첨부 있으면 prompt 앞에 `다음 파일이 첨부됐어요:\n@<path>` 형식 prepend (Claude의 `@` mention 구문, 자동 Read 도구 호출)
   - 송신 후 attachedFiles 자동 클리어
   - **Composer**:
     - `attachedFiles` + `onRemoveAttachment` + `onClearAttachments` parameter 추가
     - 입력창 위에 horizontal scroll로 chips 표시
     - 각 chip: 파일/폴더 icon (확장자 추정) + 이름 + ✕ 버튼 + hover 시 ✕가 danger 색
     - chip hover bg 변화 + tooltip은 절대 경로
     - 첨부 2개+ 시 "모두 지우기" 버튼
     - attachment 버튼 tooltip: "파일이나 폴더를 첨부합니다. Claude가 자동으로 살펴봐요."

ADR-020 채택. 검증: build 2.36s, test 52/52, run 정상.

### Changed — 브랜드 컬러 = AG2R 시안 + Picker 전면 재구성 (ADR-019)

사용자 답변: ar2r → AG2R La Mondiale 자전거 팀 → 시그니처 시안. 추가 — "설정 버튼/모델 변경 스위치 인터랙션 작동 안 함, Claude Code 같은 dropdown 디자인"

처리:
1. **Theme.Brand.accent → 밝은 시안** (`#22C8E0`, AG2R 톤). accentDeep `#0FA8C0`, accentMuted dark cyan `#0A2128`. Brand 한 곳만 교체로 전체 자동 반영
2. **Settings 호출 fix** — `NSApp.sendAction("showSettingsWindow:")` → `@Environment(\.openSettings)` (SwiftUI 14+ 표준)
3. **PickerMenu 신규 컴포넌트** — Claude Code 데스크탑 dropdown 룩 그대로:
   - native `.popover()` 기반 (안정적 위치)
   - `PickerSection` (title + shortcutHint + items)
   - `PickerItem` (label + subtitle + isSelected + shortcutHint)
   - `ShortcutKeyBadge` (`[⇧] [⌘] [I]` 같은 cap 디자인)
   - 항목 hover bg + ✓ 마커 + 우측 단축키 숫자
4. **ModelPicker/EffortPicker/ModePicker** 모두 PickerMenu로 교체:
   - 모델: 5개 모델 + ✓ + 1~5 단축키 hint + ⇧⌘M section hint
   - 권한 모드: 6개 모드 + 부제 (shortDescription) + 선택 ✓
   - 작업량: 4단계 + 부제 + ⇧⌘E section hint
5. `PickerTriggerLabel` — Composer footer의 inline button (`label · value ▾`), hover 시 chevron이 accent 색

ADR-019 채택. 검증: build 2.49s, test 52/52, run 정상.

### Added — 브랜딩 + 인터랙션 + UX 라이팅 (ADR-018, 2026-05-01)

사용자 요청: "각 버튼 인터랙션·애니메이션 + 모든 설정/버튼 동작화 + UX 라이팅 한글 친화 + ar2r 자전거 팀 컬러로 브랜딩"

진행:
1. **ar2r 조사** — codex CLI로 web search, 공개 웹에서 자전거 팀 식별 불가 → fallback 자전거 저지 표준 팔레트 사용 (사용자 답변 시 토큰 한 곳만 교체)
2. **브랜드 시스템** — `Theme.Brand` namespace 신규 (`primary` deep navy `#0E2A47`, `accent` orange-red `#FF5A36`, `accentDeep`, `accentMuted`, `accentBorder`). `Theme.Color.accent`/`accentMuted`/`accentBorder`/`accentHover`/`liveDot` 모두 Brand로 위임 → 한 곳 변경으로 전체 반영
3. **인터랙션 강화**:
   - `PressedScaleStyle` (모든 버튼 0.97 scale on press, 80ms easeOut)
   - `PrimaryButtonStyle` (CTA hover 1.02 scale + brightness +0.04)
   - `FlatButton` 모든 variant에 hover bg 토큰 (`bgHover` 추가)
   - `IconButton` press 0.92 scale + hover bg 100ms 애니메이션
   - `SendButton` hover/press 별도 애니, "보내기"/"중단" 한글 + tooltip
   - `WorkspaceItemRow` hover 시 `⌘N` 단축키 hint 표시 (10개 미만)
4. **UX 라이팅 한글 친화 (전수 패스)**:
   - Composer placeholder → "무엇을 도와드릴까요? `/`로 명령, `@`로 노트"
   - Composer "자동 모드" → "응답 중", attachment tooltip → "파일 첨부는 곧 지원됩니다"
   - Sidebar "Settings" → "설정", "Workspaces" → "워크스페이스"
   - Sidebar empty → "아직 시작한 작업이 없네요. 위 ‘+ 새 워크스페이스’로 시작해보세요."
   - UpdateCard → "업데이트 준비 / 새 버전이 도착했어요"
   - WorkspaceItemRow 우클릭 "삭제" → "지우기"
   - ChatView empty → "여기서 새 작업을 시작해보세요." + 단축키 힌트 친화화
   - ChatToolbar streaming "streaming" → "응답 중"
   - ChatToolbar inspector tooltip → "창을 더 넓혀주세요 (1080px↑)"
   - ContextInspector 섹션 → "활성/컨텍스트/토큰/비용/최근 도구" + key 한글
   - UsageDashboard 제목/섹션 한글 ("이번 세션", "앱 실행 후 누적", "모델 가격")
   - CreateWorkspaceSheet 전수 한글 ("어떤 폴더에서 시작할까요?", "이 폴더로", "만들기")
   - RootView empty → "어떤 작업으로 시작할까요?" + 부제
   - Error alert "오류" → "잠깐, 문제가 생겼어요" / "확인" → "알겠어요"
5. **미동작 버튼 wiring**:
   - Breadcrumb 클릭 → 워크스페이스 switcher menu (체크 마크 + "+ 새 워크스페이스")
   - ⌘1~9 → 워크스페이스 빠른 전환 (invisible button 9개)
   - Sidebar 워크스페이스 hover 시 단축키 hint 표시
6. **`docs/design/70_BRANDING_AND_INTERACTION.md`** 작성 (ar2r 조사 결과 + 브랜드 시스템 + 인터랙션 매트릭스 + UX 라이팅 표 + 동작 명세)

ADR-018 채택. 사용자 답변(ar2r 정확한 컬러) 시 Brand namespace 한 곳만 교체.

검증: build 1.5s, test 52/52, run 정상

### Added — 반응형 Layout 시스템 (ADR-017, 2026-05-01)

사용자 요청: "반응형부터 명확하게 구현"

- `LayoutMode` enum (compact/medium/regular/wide) — Theme.Layout 외부 namespace
- `Theme.Layout` 신규 토큰: `breakpointCompact (760)`, `breakpointMedium (1080)`, `breakpointWide (1440)`, `minWindowWidth (600)`, `minWindowHeight (480)`, `minChatWidth (520)`
- `Theme.Layout.mode(for:)` 정적 함수 — 너비 → mode
- `LayoutMode.allowsInspector` / `sidebarIsOverlay` computed
- **RootView 반응형**: GeometryReader로 윈도우 크기 추적, mode 변경 시 `handleSizeChange` 자동 정리
- **User intent 영속**: `@AppStorage("yuminai.sidebar.userVisible")` / `"yuminai.inspector.userVisible")` — 다음 실행 복원
- **Sidebar overlay**: compact 모드에서 toggle 시 콘텐츠 위에 popup + semi-transparent backdrop 클릭으로 닫힘
- **Inspector 자동 hide**: medium/compact에서 사용자 의도와 무관하게 강제 hidden, 다시 regular+로 가면 사용자 의도 복원
- **Toolbar 적응**: inspector 버튼이 mode에 따라 disabled (조명 ↓ + tooltip), layoutBadge로 "compact"/"medium" 모드 표시
- 신규 테스트 3건 (LayoutMode boundaries / inspector allowance / sidebar overlay)

검증: `swift build` 2.53s, `swift test` 52/52 통과, `swift run YuminaiApp` 윈도우 정상

### Redesigned v3 (Claude Code 데스크탑 룩 — codex 검증 반영, 2026-05-01 심야)

사용자 피드백 — "이 정도 디자인 퀄리티 (Claude Code 데스크탑 스크린샷)로 / 냉정 조사 / 무한 iteration / 기획 검증 후 구현"

처리 절차:
1. 스크린샷 정밀 분석 → 색/타이포/spacing/component 상세 추출
2. 외부 레퍼런스 검증 (Anthropic Console, Linear, Vercel, shadcn dark, Raycast)
3. `docs/design/60_UI_DESIGN_SPEC.md` v2 작성
4. **codex CLI 0.116.0으로 명세서 review** → 9건 critical 이슈 도출 (ADR-016)
5. 명세서 v3로 보완 (warm 톤, 대비 ↑, palette 단순화, Composer 핵심 컨트롤, interaction 표, SwiftUI 함정 회피)
6. 구현

신규/재작성 컴포넌트:
- **Theme v3**: warm 다크 토큰 (R>B), 4단 hierarchy (bgSidebar/bg/surface/surfaceHi/elevated/inlineCode), sans+mono 분리, monoSmall/monoStat 추가, Layout 토큰 정밀 정의 (sidebarWidth/sidebarItemHeight/composerOuterPadding 등), CenteredContent + SelectedBar modifier
- **FlatComponents v3**: FlatButton 5 variants × 4 sizes, IconButton (hover bg), SendButton (idle/streaming/disabled 3-state), PulseDot (streaming 표시), FlatSection/FlatRow/FlatTextField/FlatToggle/FlatHDivider/FlatVDivider
- **SidebarView v3**: top header (collapse + search) → primary action ("+ 새 워크스페이스") → menu ("Settings") → group "Workspaces" → WorkspaceItemRow (○/● dot + selected 좌측 2px bar) → UpdateCard → BottomUserCard
- **MessageBubble v3**: role 분기 — UserMessageBlock (warm muted bg + 2px accent bar), AssistantMessageBlock (박스 없음 + role 라벨), ToolMessageBlock (작은 ● + 작은 텍스트), SystemMessageBlock (centered)
- **Composer (신규)**: git/diff meta row → TextEditor + placeholder → footer (model/mode/effort picker + attachment + 자동 모드 + SendButton)
- **ChatToolbar v3**: sidebar toggle + Breadcrumb (folder + name + chevron) + streaming badge + dashboard/inspector buttons
- **ChatStatusBar v3**: ContextGauge (50/75% 임계 색) | msg/in/out/cache | cost
- **ContextInspector v3**: 박스 없는 sections (active/context/tokens/cost/recent tools)
- **SessionPickers v3**: InlinePicker — "label · value ▾" hover bg
- **UsageDashboard v3 / CreateWorkspaceSheet v3**: FlatSection 사용
- **RootView v3**: 자체 HStack (sidebar/main/inspector), Composer 통합, EmptyWorkspaceView

ADR-016 — codex review 결과 반영 + design spec v3 정식 채택

검증:
- swift build → 2.21s 성공
- swift test → 49/49 통과
- swift run YuminaiApp → 윈도우 정상 (PID 94678)

### Redesigned (CLI-flat 룩으로 전면 재구성, 2026-05-01 늦은밤)
- **macOS 네이티브 컴포넌트 우회** — NavigationSplitView 제거 (직접 HStack), Form/Picker/.regularMaterial 모두 chrome에서 제거
- **Theme 전면 재정의** — 시스템 색 (`Color(NSColor.windowBackgroundColor)` 등) 모두 제거 → 명시적 light/dark 적응형 hex 토큰. 모든 폰트 monospace 기본
- **자체 Flat 컴포넌트** (`FlatComponents.swift`): FlatButton (5 variants × 2 sizes), FlatTextField, FlatSection, FlatRow, FlatHDivider/FlatVDivider, FlatToggle
- **flatChrome modifier** — `.regularMaterial` 대신 단색 + 옵션 1px border (top/bottom/leading/trailing 선택)
- **MessageBubble 완전 재작성** — 박스/배경 제거, prefix 마커 (`>`, `·`, `○`, `—`) + lowercase role 라벨 + 본문만 (Claude Code CLI 룩)
- **InlinePicker** — `model · sonnet ▾` 형식의 monospace 1px-border 픽커
- **ChatToolbar** — `[ws-name] | model·sonnet▾ mode·default▾ effort·medium▾ │ ●streaming` flat 룩
- **ChatStatusBar** — `ctx ▓▓░ 23.4% │ msg 8 in 12.3k out 4.5k cache 890 │ $0.0451`
- **ContextInspector** — 박스 없는 섹션 (uppercase 라벨 + key/value)
- **SidebarView** — flat row, `>` 선택 마커, hover/select 단색 배경
- **MessageInputView** — `>` prompt + flat textarea + send/cancel
- **SidebarToggle 버튼** — Toolbar 좌측, 사이드바 hide/show
- **CreateWorkspaceSheet, UsageDashboard** — 자체 flat 컴포넌트 사용
- 정수 spacing (2/4/8/12/16/24)으로 정보 밀도 ↑

### Added (UI/UX 대폭 개선, 2026-05-01 후반)
- **모델·모드·효과 picker (인라인)** — ChatToolbar에서 즉시 변경. 변경 시 Claude CLI 자동 재spawn (현재 메시지 보존)
- **ChatToolbar** — Claude orange 액센트, monospace 라벨, 워크스페이스명 + model/mode/effort + 스트리밍 뱃지 + dashboard/inspector 버튼
- **ChatStatusBar** (입력창 위) — 컨텍스트 게이지 (색상 임계값 50/75%), 메시지 수, in/out/cache 토큰, 비용 inline
- **UsageDashboard sheet (⌘D)** — 현재 세션 + 누적 사용량 통계 + 모델별 가격 풋터
- **ContextInspector (⌘⌥I 토글)** — 우측 사이드 패널: Active 설정 / Context 게이지 / Tokens / Cost / Recent Tools
- **SettingsView 5탭** — 일반 / 모델·모드 / 편집 / Telegram / Anthropic. 기본 모델/모드/효과/예산 모두 GUI 편집
- **EditPreferences struct** — autoFormat, showDiffOnEdit, autoBackup
- **Liquid Glass chrome** — Toolbar/StatusBar/Inspector에 `.regularMaterial` 배경
- **Theme 토큰 정밀화** — chrome/surface/role tints, monospace 통계 폰트, pill radius 추가
- **사용량 트래킹** — JSONStreamParser가 `usage` 객체 + `total_cost_usd` 추출 → `.usage(UsageDelta)` 이벤트 → AppModel이 currentSessionUsage / allTimeUsage 누적
- **PermissionMode / EffortLevel / ClaudeModel enum** — Claude CLI 옵션 1:1 매핑 + displayName/shortDescription/가격 메타
- **SessionSettings struct** — model + permissionMode + effortLevel + includeHookEvents + maxBudgetUSD
- 단위 테스트 추가: UsageStats accumulate/contextUsage clamp (49 tests / 17 suites 모두 통과)

### Decided (ADR-014, 2026-05-01)
- Toolbar inline picker 패턴 — picker 변경 시 즉시 새 ClaudeStreamSession spawn (활성 settings 적용). 메시지 로그는 UI에 보존.

### Fixed (2026-05-01)
- SPM executable이 background-only로 시작되어 윈도우가 안 보였던 문제 — `NSApplication.shared.setActivationPolicy(.regular)` + `NSApplicationDelegateAdaptor` + `applicationDidFinishLaunching`에서 `activate(ignoringOtherApps: true)` 추가

### Added (MVP-0 골격, 2026-05-01)
- **YuminaiCore**: KeychainStore (Live + InMemory), WorkspaceStore/SessionStore protocol, TelegramClient protocol, AppPreferences + UserDefaultsStore
- **YuminaiPersistence**: SessionModel, MessageModel + SchemaV1 갱신, SwiftDataWorkspaceStore, SwiftDataSessionStore, live ModelContainer factory
- **YuminaiClaudeAdapter**: JSONStreamParser (NDJSON), LiveClaudeAdapter (Process + Pipe spawn, ADR-009 인자 조합)
- **YuminaiTelegram (신규 모듈)**: LiveTelegramBot (HTTPS API + long polling), MockTelegramBot, TelegramAlertDispatcher (정책 기반 알림), TelegramCommandPump + TelegramCommandRouter protocol, EchoCommandRouter
- **YuminaiUI**: MessageBubble, MessageInputView, ChatView, SidebarView + WorkspaceRow, CreateWorkspaceSheet, SettingsView (3-tab) + SecretField/SecretStatus
- **YuminaiApp (신규 executable)**: @main YuminaiAppMain, AppModel (@MainActor @Observable, 모든 모듈 DI + lifecycle), RootView (NavigationSplitView), ChatDetailView, SettingsContainer, YuminaiCommandRouter (Telegram→Claude 라우터)
- 단위 테스트: 47개 / 16 suite (KeychainStore, AppPreferences Codable, JSONStreamParser 8건, MockTelegramBot, AlertDispatcher 정책, EchoRouter, SwiftDataWorkspaceStore CRUD 6건, SwiftDataSessionStore CRUD + messages 3건)
- 검증: `swift build` 성공, `swift test` 47/47 통과, `swift run YuminaiApp` 프로세스 정상 시작/종료

### Decided (2026-05-01 — 사용자 답변)
- **Q-B 확정**: B2 (CLI 스타일 채팅 GUI). ADR-013 정식 채택
- **Q-D1 잠정**: Obsidian Vault는 사용자 미정 → SettingsView에서 경로 입력 받고 v0.2에서 활성화. 코어/UI 변경 없이 추후 모듈 추가 가능 구조
- **Q-D2 확정**: Telegram bot은 SettingsView에서 토큰/Chat ID/허용 user ID 추가. 양방향(알림 + 명령 수신) 둘 다 구현. ADR-012 정식 채택

### Discovered (W1 Spike, 2026-05-01)
- Claude CLI 2.1.101이 `-p --input-format stream-json --output-format stream-json --include-partial-messages --include-hook-events` 로 JSON 양방향 스트리밍을 공식 지원 → **PTY 불필요, ANSI 파싱 불필요**
- `--session-id <uuid>`, `-r/--resume`, `-c/--continue`로 멀티턴 세션 영속을 Claude가 자체 처리
- `--settings`, `--mcp-config`, `--agents`, `--plugin-dir`, `--add-dir`로 워크스페이스 하네스 완벽 주입 가능
- 결과: ADR-005 superseded → **ADR-009 채택** (`-p` + stream-json), **ADR-010 채택** (세션 영속 Claude 위임 + SwiftData 캐시)

### Added
- 프로젝트 초기 스캐폴딩 (디렉토리 구조 + 하네스 골격)
- PRD 문서 12개 (00~99)
- 설계 문서 6개 (`docs/design/`)
- Swift 6.2 / SwiftUI / SwiftData 기반 5개 모듈 정의:
  - `YuminaiCore` — 도메인 모델 / DI 프로토콜
  - `YuminaiClaudeAdapter` — Claude CLI 자식 프로세스 + PTY
  - `YuminaiPersistence` — SwiftData 모델 / 마이그레이션
  - `YuminaiUI` — SwiftUI 컴포넌트 / Liquid Glass
  - `YuminaiHarness` — rules/agents/skills/hooks 디스패처
- 5개 테스트 타깃 placeholder
- claude-forge 패턴 매핑 (rules/, agents/, skills/, hooks/, commands/, settings.json, .mcp.json)
- `Package.swift` (macOS 26.0+, Swift 6.2, StrictConcurrency 활성)
- Xcode App 타깃 추가 가이드 (`App/README.md`)

### Decided
- 기술 스택: SwiftUI 네이티브 / Swift 6.2 / SwiftData / Keychain
- Claude Code 관계: A1 (CLI Wrapper)
- 본인 1인 사용 / unsigned / App Sandbox OFF
- macOS 26.0+ (deployment target)

### Open
- UI 형태 확정 (B1/B2/B3 — 잠정 B2)
- Obsidian 통합 구체 명세 (Vault 경로 등)
- Telegram bot 토큰 / user ID
- "다양한 외부 앱들" 구체 후보

[`docs/prd/99_OPEN_QUESTIONS.md`](../prd/99_OPEN_QUESTIONS.md) 전체 참조.
