# Yuminai 개발 hooks

Claude Code 이벤트(PreToolUse, PostToolUse, SessionStart 등)에 연결할 스크립트.

## 등록

`settings.json`의 `hooks` 섹션에 등록. 예:

```json
"hooks": {
  "PreToolUse": [
    { "matcher": "Bash", "hooks": [{ "type": "command", "command": "./hooks/pre-bash-guard.sh", "timeout": 3000 }] }
  ]
}
```

## 추가 예정 (TODO)

- `pre-bash-guard.sh` — `swift package`, `xcodebuild` 외 빌드 명령 차단
- `post-edit-format.sh` — `.swift` 편집 후 `swift-format` 자동 실행
- `session-start-load-context.sh` — Yuminai 프로젝트 진입 시 현재 빌드 상태 출력

## 규칙

- 모두 실행 가능 (`chmod +x`)
- 짧은 timeout (3000ms)
- 실패해도 작업 차단하지 않게 (exit 0 권장, 차단 의도면 exit 2)
- stderr는 사용자에게 노출됨
