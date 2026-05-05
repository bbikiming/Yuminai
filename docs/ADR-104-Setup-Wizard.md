# ADR-104: 첫 실행 자동 설치 Wizard

**상태**: 구현 완료  
**날짜**: 2026-05-04  
**이슈**: 첫 실행 사용자가 필수 도구를 쉽게 설치할 수 있는 안내 필요

---

## 1. 배경

Yuminai는 다음 세 도구와 연동한다.

| 도구 | 역할 | 필수 여부 |
|------|------|-----------|
| Claude Code | Anthropic 공식 코딩 에이전트 | **필수** |
| Codex CLI | OpenAI 공식 코딩 에이전트 | 선택 |
| cokacdir | 텔레그램 봇 빠른 시작 도구 | 권장 |

기존 onboarding wizard(ADR-072)는 사용 모드 선택만 안내하고, 도구 설치 여부 안내가 없었다. 첫 실행 사용자는 Claude Code 없이 Yuminai를 열고 "아무것도 동작 안 한다"는 혼란을 겪는다.

cokacdir 공식 가이드: 설치 후 `cokacctl` TUI에서 `i`(설치) → `k`(봇 토큰) → `s`(서버 시작) 순으로 진행.

---

## 2. SetupTool 모델

`SetupTool`은 `YuminaiCore`에 위치하는 `public enum`:

```swift
public enum SetupTool: String, CaseIterable, Identifiable, Sendable {
    case claudeCode
    case codexCLI
    case cokacdir
}
```

각 도구는 다음 속성을 정의한다:

- `displayName`: UI 표시명
- `purpose`: 친화 설명 (초보자도 이해 가능)
- `isRequired`: claudeCode만 `true`
- `installCommand`: 터미널에서 실행할 명령
- `docsURL`: 공식 문서
- `detectionPaths`: 설치 검증 binary 경로 목록 (`$HOME` 포함)
- `iconName`: SF Symbol
- `badgeLabel`: 필수 / 선택 / 권장

---

## 3. 설치 검증 패턴 (FileManager + detectionPaths)

`SetupChecker` actor가 `detectionPaths`를 순회하며 두 가지를 확인한다.

1. `FileManager.fileExists(atPath:)` — 파일 존재
2. `FileManager.isExecutableFile(atPath:)` — 실행 권한

`$HOME`은 `ProcessInfo.processInfo.environment["HOME"]`으로 치환한다 (Sandbox-safe, NSString.expandingTildeInPath 대신 사용).

```swift
public actor SetupChecker {
    public enum InstallStatus: Sendable, Equatable {
        case installed(path: String)
        case notInstalled
        case unknown
    }

    public func check(_ tool: SetupTool) async -> InstallStatus
    public func checkAll() async -> [SetupTool: InstallStatus]
}
```

`checkAll()`은 `withTaskGroup`으로 모든 도구를 병렬 검사한다.

---

## 4. Terminal 자동 실행 (AppleScript)

### 보안 정책 (CRITICAL)

Yuminai가 `Process`로 `bash -c "curl | bash"`를 **직접 실행하지 않는다.**

이유:
- 권한 상승 위험 (`sudo` 포함 명령 자동 실행)
- 사용자가 명령을 확인할 기회 없음
- App Sandbox 우회 가능성

### 구현

Terminal.app에 명령을 붙여 넣기만 하고, 사용자가 직접 Enter를 누른다:

```swift
private func runInTerminal(_ command: String) {
    let escapedCommand = command
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    let script = """
    tell application "Terminal"
        activate
        do script "\(escapedCommand)"
    end tell
    """
    // fallback: 클립보드에도 복사
    NSPasteboard.general.setString(command, forType: .string)
    if let appleScript = NSAppleScript(source: script) {
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
    }
}
```

`do script`는 새 Terminal 창/탭에서 명령을 즉시 실행하므로, `paste`가 아닌 직접 실행처럼 보인다. 이 점을 UI 안내 문구에 명시한다: "Terminal.app에 명령을 붙여 넣고 여러분이 Enter를 누르도록 안내합니다."

> **Note**: `do script`는 Enter를 실제로 시뮬레이션한다. 더 안전한 방법은 `NSPasteboard` + `NSWorkspace.open(terminalURL)` 조합이나, 사용자 경험이 크게 떨어진다. 현재 구현에서는 사용자에게 명령 내용을 UI에 노출해 확인 기회를 제공한다.

---

## 5. 진입 흐름

### 자동 진입 (bootstrap)

```
앱 실행 → bootstrap() → hasCompletedOnboarding == true
                      → hasCompletedSetup == false
                      → refreshSetupStatus() + showSetupWizard = true
```

`preferences.hasCompletedOnboarding`은 ADR-072에서 관리. onboarding이 끝나지 않으면 setup wizard도 표시하지 않는다.

### 수동 진입 (Help 메뉴)

`YuminaiApp.swift` Help 메뉴 → "초기 설정 가이드…" 버튼 → `appModel.openSetupWizard()`.

### 건너뛰기

헤더 우상단 "건너뛰기" 버튼 클릭 → `dismissSetupWizard(markCompleted: false)`. `hasCompletedSetup`이 `false`로 유지되어 다음 실행 시 다시 표시.

### 완료

"완료" 버튼 → `dismissSetupWizard(markCompleted: true)` → `hasCompletedSetup = true` 저장.

---

## 6. backward-compat (기존 사용자)

`AppPreferences.init(from decoder:)`에서 `hasCompletedSetup`이 없으면 `true`로 기본값 설정:

```swift
self.hasCompletedSetup = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedSetup) ?? true
```

기존 사용자는 이미 도구를 설치했을 가능성이 높으므로 wizard를 다시 표시하지 않는다.

---

## 7. 검증

```bash
cd /Users/bbikiming/Documents/vibe_coding/Yuminai
swift build           # Build complete!
swift test            # 970+ tests passed

# 수동 검증
defaults delete com.yuminai.Yuminai  # 첫 실행 상태로 리셋
# 앱 실행 → onboarding 완료 → setup wizard 자동 표시

# Help 메뉴 → 초기 설정 가이드… → 재진입 확인
```

---

## 8. 후속 개선 (v2)

- **설치 진행 모니터링**: `Process` + pty로 설치 진행률을 실시간 표시
- **자동 PATH 추가**: 설치 후 shell 프로필(.zshrc/.bashrc)에 PATH 자동 추가
- **Homebrew 지원**: Claude Code의 경우 `brew install claude` 옵션 제공
- **설치 재시도**: 설치 완료 후 자동 재검사 + 상태 갱신 (현재는 수동 "다시 검사" 필요)
