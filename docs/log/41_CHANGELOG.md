# Changelog

> 변경 사항 시간순 기록. 의미 있는 변경만.

## [Unreleased] — 2026-05-01

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
