# MEMORY.md — Yuminai 자동 로드 메모리

> Claude Code가 모든 세션 시작 시 자동 로드하는 컨텍스트.
> 짧게 유지(<200줄). 새로 알게 된 사실은 여기에 한 줄씩 추가.

## 프로젝트 기본

- **이름**: Yuminai (유미나이)
- **타입**: 본인 1인용 macOS SwiftUI 데스크탑 앱
- **시작일**: 2026-05-01
- **저장소**: 로컬 git only (원격 없음)

## 현재 단계

- **단계**: PRE-MVP (기획 + 골격 스캐폴딩 완료)
- **다음 마일스톤**: MVP-0 (4개 모듈 동작 — `docs/prd/90_ROADMAP.md`)
- **블로커**: Xcode App 타깃 수동 추가 필요 (`App/README.md`)

## 결정된 핵심

- 기술 스택: SwiftUI + Swift 6.2 + SwiftData + Keychain
- Claude Code 관계: A1 (CLI Wrapper, 자식 프로세스)
- App Sandbox: OFF
- macOS 타깃: 26.0+

## 미해결 (PRIORITY)

상세는 `docs/prd/99_OPEN_QUESTIONS.md`. 우선순위 항목:

1. UI 정확한 형태 (B1 터미널 임베드 vs B2 채팅 GUI vs B3 풀 GUI) — 잠정 B2
2. Obsidian 통합 구체 명세 (Vault 경로, 자동 노트화 규칙)
3. Telegram bot 양방향 명령 라우팅 명세
4. "다양한 외부 앱들" 구체 후보 (Linear/Notion/GitHub/...)

## 참조 위치

- claude-forge 하네스 패턴 원본: `~/Documents/vibe_coding/claude-forge/`
- Claude CLI: `~/.local/bin/claude`
- 사용자 워크스페이스 데이터(런타임): `~/Library/Application Support/Yuminai/` (앱이 자동 생성)
