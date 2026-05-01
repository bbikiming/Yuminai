# Yuminai 개발용 스킬

Yuminai 개발 시 Claude Code가 호출하는 슬래시 스킬. 글로벌/`claude-forge`/`everything-claude-code` 스킬을 모두 상속하므로 여기엔 **Yuminai 특화**만 둔다.

## 추가 예정 (TODO)

| 스킬 | 용도 |
|---|---|
| `yuminai-build` | `swift build` + `xcodebuild` 두 빌드 모두 실행, 첫 에러까지만 |
| `yuminai-test` | 모듈별 `swift test --filter` + 커버리지 리포트 |
| `yuminai-spawn-debug` | Claude CLI spawn 시 PATH/TTY/exit 상태 진단 |
| `yuminai-keychain-list` | `security find-generic-password -s com.yuminai` 항목 정리 |
| `yuminai-vault-stub` | 테스트용 Obsidian Vault 픽스처 생성 |

## 작성 규칙

- 디렉토리: `skills/{skill-name}/SKILL.md`
- frontmatter: `name`, `description`, `version`, `last_updated`
- 본문 섹션: Purpose / Use_When / Do_Not_Use_When / Why_This_Exists / Execution_Policy / Steps
