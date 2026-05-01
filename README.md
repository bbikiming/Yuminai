# Yuminai

> **Yuminai (유미나이)** — 바이브 코딩을 위한 1인 macOS 워크스페이스. Claude Code의 추론 엔진을 코어로 두고, Obsidian Vault·Telegram·외부 도구를 한 화면에서 오케스트레이션해 *사고 → 코드 → 문서화 → 공유* 사이클을 끊김 없이 잇는 SwiftUI 네이티브 앱.

> **상태**: PRE-MVP / 기획 단계
> **타깃 사용자**: 본인 1인 (출시·배포 계획 없음)
> **타깃 OS**: macOS 26.0 (Tahoe) +
> **언어/프레임워크**: Swift 6.2 / SwiftUI / SwiftData

## Why Yuminai

Claude Code는 강력하지만 *터미널 안*에 갇혀 있다. 바이브 코딩 워크플로우의 핵심 자산인 **외부 노트(Obsidian)**, **모바일 알림·명령(Telegram)**, **다른 도구들**과의 결합이 매번 수동이거나 ad-hoc 스크립트에 의존한다.

Yuminai는 이 결합을 **앱 레벨에서 1급 시민**으로 만든다. Claude Code는 그대로 추론 엔진으로 위임(A1 wrapper)하고, GUI·통합·세션 관리·하네스 패턴은 자체 구현한다.

## Repo Structure

```
Yuminai/
├── docs/
│   ├── prd/         # 제품 요구사항 (00~99 번호)
│   ├── design/      # 아키텍처/모듈 설계
│   ├── log/         # CHANGELOG, DECISIONS
│   └── knowledge/   # 외부 참조 자료
├── rules/           # Yuminai 개발 규칙 (Swift 스타일, 동시성, 보안 등)
├── agents/          # Claude Code 에이전트 (이 프로젝트 *개발*용)
├── skills/          # 슬래시 스킬
├── hooks/           # 이벤트 훅 스크립트
├── commands/        # 슬래시 명령 정의
├── Sources/         # SPM 라이브러리 (모듈)
│   ├── YuminaiCore/          # 도메인 모델, 비즈니스 로직
│   ├── YuminaiClaudeAdapter/ # Claude Code CLI 자식 프로세스
│   ├── YuminaiPersistence/   # SwiftData 스토리지
│   ├── YuminaiUI/            # 공용 SwiftUI 컴포넌트, 디자인 토큰
│   └── YuminaiHarness/       # rules/agents/skills 매핑 엔진
├── Tests/           # 모듈별 단위 테스트
├── App/             # Xcode App 타깃 자리 (Xcode에서 직접 추가)
├── Package.swift
├── CLAUDE.md        # Claude Code 세션 컨텍스트
├── MEMORY.md        # 자동 로드 메모리
├── settings.json    # 프로젝트 settings
└── .mcp.json        # MCP 서버 등록
```

## Quick Start

### 즉시 실행 (MVP-0)

```bash
cd ~/Documents/vibe_coding/Yuminai
swift run YuminaiApp
```

처음 실행 시 윈도우가 열리면:
1. **Settings (`⌘,`) → 일반**: Claude CLI 경로 확인 (자동 탐지됨)
2. **Settings → Telegram**: 봇 토큰/Chat ID 설정 (옵션)
3. **사이드바 `+` 또는 `⌘N`**: 새 워크스페이스 생성 → 디렉토리 선택
4. 워크스페이스 클릭 → 채팅창에 메시지 입력 → `⌘+Return`

### 개발 명령

```bash
swift build          # 모든 모듈 빌드
swift test           # 47개 단위 테스트 실행
swift run YuminaiApp # 앱 실행
```

### 사전 준비

- macOS 26.0+, Xcode 26.0+, Swift 6.2+
- Claude Code CLI: `which claude` → `~/.local/bin/claude` (자동 탐지)
- (옵션) Telegram bot: BotFather에서 봇 생성 → 토큰을 SettingsView에 입력

### Xcode App 번들 (v0.2+, 후속)

정식 `.app` 번들/Dock 아이콘/자동 업데이트는 `App/README.md` 참조 (현재 SPM executable로 충분히 사용 가능 — ADR-011).

자세한 내용은 [`docs/prd/00_OVERVIEW.md`](docs/prd/00_OVERVIEW.md), [`docs/design/00_HARNESS_DESIGN.md`](docs/design/00_HARNESS_DESIGN.md) 참고.

## Documentation Map

| 문서 | 목적 |
|------|------|
| [`docs/prd/00_OVERVIEW.md`](docs/prd/00_OVERVIEW.md) | 비전, 1줄 정의, 핵심 가치 |
| [`docs/prd/40_FUNCTIONAL_REQS.md`](docs/prd/40_FUNCTIONAL_REQS.md) | Must/Should/Could 기능 |
| [`docs/prd/90_ROADMAP.md`](docs/prd/90_ROADMAP.md) | MVP→v0.2→v1.0 마일스톤 |
| [`docs/prd/99_OPEN_QUESTIONS.md`](docs/prd/99_OPEN_QUESTIONS.md) | 미해결 결정사항 (꼭 읽기) |
| [`docs/design/10_ARCHITECTURE.md`](docs/design/10_ARCHITECTURE.md) | 시스템 아키텍처 |
| [`docs/design/30_CLAUDE_ADAPTER.md`](docs/design/30_CLAUDE_ADAPTER.md) | Claude Code CLI 통합 |
| [`CLAUDE.md`](CLAUDE.md) | Claude Code 작업 시 컨텍스트 |
