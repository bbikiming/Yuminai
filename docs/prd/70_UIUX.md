# 70_UIUX — UI/UX 가이드

> 잠정 결정: **B2 — CLI 스타일 채팅 GUI**. Claude Code 룩 + 통합 위젯. 확정 결정은 [`99_OPEN_QUESTIONS.md`](99_OPEN_QUESTIONS.md) Q-B 참조.

## 디자인 원칙

1. **Claude Code 본능 보존**: 슬래시 명령, 키보드 전부, 다크 다크 다크
2. **Liquid Glass는 chrome에만**: 사이드바·툴바·패널 분할에는 적용, 채팅 본문엔 미적용 (가독성)
3. **Monospace는 코드에만**: UI 텍스트는 SF Pro, 코드/Claude 출력은 SF Mono
4. **마우스 < 키보드**: 모든 액션이 단축키로
5. **밀도 우선**: 본인 사용이라 "친절한 여백"보다 "한 화면 더 보이는 것"

## 화면 레이아웃

```
┌──────────────────────────────────────────────────────────────────┐
│  ⌘ Yuminai          [⌘P] 워크스페이스 검색       ⓘ ⚙             │  ← Toolbar (Liquid Glass)
├──────┬──────────────────────────────────────────────┬──────────────┤
│      │                                              │              │
│ Side │              Chat (메인)                      │  Inspector  │
│ bar  │                                              │              │
│      │  ┌────────────────────────────────────┐      │  - Obsidian │
│ • ws1│  │ 사용자: "오늘 할 것 정리해줘"            │      │    노트 트리 │
│ • ws2│  └────────────────────────────────────┘      │              │
│ • ws3│                                              │  - 슬래시    │
│ ───  │  ┌────────────────────────────────────┐      │    명령      │
│ Note │  │ Claude: 1. ... 2. ... 3. ...        │      │    카탈로그  │
│ tree │  │                                    │      │              │
│      │  └────────────────────────────────────┘      │  - 통합      │
│      │                                              │    상태      │
│      │  > _                                          │              │
│      │  [입력창, slash 자동완성]                       │              │
│      │                                              │              │
└──────┴──────────────────────────────────────────────┴──────────────┘
   240px           가변(min 600px)                       320px
```

### Inspector 패널은 토글 가능
- ⌘+Opt+0 = 좌우 패널 모두 숨기기 (집중 모드)
- ⌘+Opt+1 = 사이드바만 토글
- ⌘+Opt+2 = inspector만 토글

## 색상 (Theme)

```swift
enum Theme {
    enum Color {
        // Background
        static let bgWindow = Swift.Color(.windowBackgroundColor)  // 시스템
        static let bgChat = Swift.Color(NSColor(white: 0.07, alpha: 1.0))
        static let bgInput = Swift.Color(NSColor(white: 0.10, alpha: 1.0))
        static let bgCodeBlock = Swift.Color(NSColor(white: 0.04, alpha: 1.0))
        
        // Foreground
        static let label = Swift.Color.primary
        static let labelSecondary = Swift.Color.secondary
        static let userMessage = Swift.Color(NSColor(white: 0.95, alpha: 1.0))
        static let claudeMessage = Swift.Color(NSColor(white: 0.85, alpha: 1.0))
        
        // Accents (Claude Code 톤)
        static let accent = Swift.Color(red: 0.85, green: 0.55, blue: 0.30)  // Claude orange
        static let success = Swift.Color(red: 0.30, green: 0.80, blue: 0.50)
        static let warning = Swift.Color(red: 0.95, green: 0.75, blue: 0.20)
        static let error = Swift.Color(red: 0.95, green: 0.30, blue: 0.30)
        
        // ANSI mapping (Claude CLI 출력)
        static let ansi8: [Swift.Color] = [...]  // 8 표준 색
        static let ansi16: [Swift.Color] = [...]
    }
}
```

## 타이포그래피

```swift
enum Typography {
    static let body = Font.system(.body, design: .default)        // SF Pro
    static let bodyMono = Font.system(.body, design: .monospaced) // SF Mono
    static let chatMessage = Font.system(size: 13, design: .monospaced)
    static let chatInput = Font.system(size: 13, design: .monospaced)
    static let codeBlock = Font.system(size: 12, design: .monospaced)
    static let label = Font.system(.callout, design: .default)
    static let label2 = Font.system(.footnote, design: .default)
}
```

> 본인 사용이라 폰트 크기는 설정에서 -2 ~ +4 슬라이더로 조정 가능.

## Spacing

```swift
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}
```

## 단축키 (전부 — 본인 메모용)

### 글로벌
| 키 | 동작 |
|---|---|
| `⌘N` | 새 워크스페이스 |
| `⌘W` | 현재 워크스페이스 닫기 |
| `⌘1`~`⌘9` | 워크스페이스 빠른 전환 |
| `⌘P` | 워크스페이스 검색 (Cmd-K palette) |
| `⌘,` | 설정 |
| `⌘Q` | 종료 (Claude 자식 프로세스 cleanup 후) |

### 채팅
| 키 | 동작 |
|---|---|
| `⌘+Return` | 메시지 전송 |
| `⌘+L` | 채팅 스크롤 클리어 |
| `⌘+K` | 새 세션 시작 (현재 워크스페이스) |
| `Esc` | Claude 작업 cancel |
| `⌘+/` | 슬래시 명령 자동완성 강제 표시 |
| `⌘+E` | 마지막 메시지 편집 |
| `⌘+R` | 마지막 메시지 재전송 |

### 패널
| 키 | 동작 |
|---|---|
| `⌘+Opt+0` | 좌우 패널 토글 (집중 모드) |
| `⌘+Opt+1` | 사이드바 토글 |
| `⌘+Opt+2` | inspector 토글 |
| `⌘+Opt+O` | Obsidian 노트 검색 |

### Vault / Obsidian (v0.2)
| 키 | 동작 |
|---|---|
| `@` (입력창에서) | 노트 인라인 검색 |
| `⌘+Shift+S` | `/note save` 슬래시 명령 |

## 인터랙션 패턴

### 슬래시 명령 자동완성
- 입력창에서 `/` 입력 시 즉시 팝업
- 화살표 키로 선택, Tab/Return으로 확정
- 명령 그룹: 글로벌 / 워크스페이스 / 즐겨찾기

### `@note-name` 인라인 검색 (v0.2)
- 입력창에서 `@` 입력 시 노트 목록 팝업
- 퍼지 검색
- 확정 시 `@2026-05-01-DailyNote` 같은 식의 토큰화된 형태로 입력창에 삽입
- 전송 시 토큰이 노트 본문으로 expand

### 코드 블록
- 호버 시 우상단에 [복사] [저장] [diff] 버튼
- 큰 블록(20줄 이상)은 접기 가능

### 작업 진행 표시
- Claude가 응답 중일 때 입력창 위에 진행 상태바
- "Plan", "Tool: Read", "Tool: Edit" 등 단계 표시
- Esc로 cancel

## 빈 상태 / 에러 상태

### 워크스페이스 없음 (첫 실행)
```
┌────────────────────────────────────────┐
│                                        │
│       Yuminai에 오신 것을 환영합니다       │
│                                        │
│    [+ 첫 워크스페이스 만들기]              │
│                                        │
│    또는 ⌘N                              │
│                                        │
└────────────────────────────────────────┘
```

### Claude CLI 없음
- 토스트: "Claude CLI를 찾을 수 없습니다. 설정에서 경로를 지정하세요."
- 버튼: [설정 열기]

### Claude CLI 비정상 종료
- 채팅 본문에 시스템 메시지로 표시
- "Claude가 비정상 종료되었습니다 (exit 1). 다시 시도하시겠습니까?"
- 자동 재시작 안 함 (사용자 의사)

## 첫 실행 온보딩 (3 step)

1. **Welcome**: Yuminai 1줄 설명, "시작" 버튼
2. **Claude CLI 확인**: 자동 탐지 (`which claude`), 없으면 경로 입력
3. **(옵션) 통합 설정**: Obsidian Vault, Telegram bot — 모두 skip 가능

> 본인용이므로 길게 만들지 않음. 5분 이내.
