# Yuminai 개발용 에이전트

이 디렉토리는 **Yuminai를 *개발*할 때** Claude Code가 사용하는 에이전트 정의를 둔다. (Yuminai 앱이 *런타임에* 사용하는 사용자-워크스페이스 에이전트와는 별개.)

## 상속

글로벌 `~/.claude/agents/` 와 `claude-forge/agents/`의 모든 에이전트를 그대로 사용 가능. 이 디렉토리는 **Yuminai 특화 추가**만 둔다.

## 추가 예정 (TODO)

| 에이전트 | 모델 | 용도 |
|---|---|---|
| swift6-reviewer | opus | Swift 6.2 concurrency / Sendable / actor isolation 전문 리뷰 |
| swiftui-architect | opus | SwiftUI view 분해, @Observable 마이그레이션, Liquid Glass 적용 |
| pty-debugger | sonnet | Process / PTY / ANSI 관련 이슈 추적 |
| claude-cli-protocol | sonnet | Claude CLI stdin/stdout 포맷 분석 (역공학) |
| keychain-auditor | sonnet | Keychain 사용 패턴 검증 |

각 에이전트는 별도 `.md` 파일로 추가. 형식은 claude-forge `agents/code-reviewer.md`를 참조.

## 작성 규칙

- frontmatter: `name`, `description`, `model`, `tools`, `memory: project`, `color`
- 본문은 XML 섹션: `<Role>`, `<Why_This_Matters>`, `<Success_Criteria>`, `<Constraints>`, `<Investigation_Protocol>`, `<Tool_Usage>`, `<Execution_Policy>`, `<Output_Format>`, `<Failure_Modes_To_Avoid>`, `<Final_Checklist>`
- Self-evolution 활성화: `memory: project` 설정 + `~/.claude/agent-memory/{name}/MEMORY.md` 자동 생성
