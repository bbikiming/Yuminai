# Yuminai 개발용 슬래시 명령

Claude Code 세션에서 사용 가능한 `/명령`. 글로벌 명령(`/plan`, `/tdd`, `/code-review`, `/security-review`, `/explore` 등)을 모두 상속하므로 Yuminai 특화만 추가.

## 추가 예정 (TODO)

| 명령 | 동작 |
|---|---|
| `/yuminai-bootstrap` | 첫 빌드 + 의존성 fetch + Xcode App 타깃 가이드 출력 |
| `/yuminai-status` | 현재 모듈별 빌드/테스트/커버리지 상태 한 화면 |
| `/yuminai-spawn-test` | Claude CLI spawn 단위 테스트 한 번 실행 (PTY/PATH 검증) |
| `/yuminai-pr` | 현재 브랜치 → main에 대한 PR 생성 (gh CLI; 단, 본인 사용이므로 옵셔널) |

## 작성 규칙

- 디렉토리: `commands/{command-name}.md`
- frontmatter: `description` (한국어 권장)
- 본문에 명령의 흐름과 호출할 에이전트/스킬 명시
