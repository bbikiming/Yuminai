# Xcode App 타깃 추가 가이드

이 디렉토리는 **Xcode macOS App 타깃 자리**입니다. SPM만으로는 SwiftUI 데스크탑 앱(.app)을 깔끔하게 빌드/배포할 수 없으므로, Xcode 프로젝트로 직접 만들어야 합니다.

## 한 번만 하는 셋업

### 1. Xcode 새 프로젝트 생성

1. Xcode 26 → **File → New → Project…**
2. **macOS → App** 선택
3. 옵션:
   - Product Name: `Yuminai`
   - Team: 본인 Apple ID (없으면 Personal Team)
   - Organization Identifier: `com.yuminai` (또는 본인 도메인 역순)
   - Bundle Identifier: `com.yuminai.Yuminai`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Storage: **SwiftData** (체크)
   - Include Tests: 체크 해제 (SPM Tests/ 사용)
4. 저장 위치: `~/Documents/vibe_coding/Yuminai/App/` ← 이 디렉토리 선택
5. **Create Git Repository**: 체크 해제 (이미 상위에 git이 있음)

### 2. SPM 패키지 의존성 추가

Xcode에서:
1. 프로젝트 navigator 최상단 **Yuminai** 클릭
2. **Package Dependencies** 탭
3. **+** 버튼 → **Add Local…**
4. 상위 디렉토리 `~/Documents/vibe_coding/Yuminai/` 선택 (Package.swift가 있는 곳)
5. 추가할 라이브러리 모두 체크: `YuminaiCore`, `YuminaiClaudeAdapter`, `YuminaiPersistence`, `YuminaiUI`, `YuminaiHarness`
6. 타깃: `Yuminai` (앱 타깃)

### 3. App Sandbox 비활성화

1. 앱 타깃 → **Signing & Capabilities**
2. **+ Capability** → **App Sandbox** 추가됐다면 → 휴지통 아이콘으로 제거
   - (또는 sandbox는 두고 모든 권한 끄기)
3. **Hardened Runtime**은 유지 + 다음 entitlement 추가:
   - `com.apple.security.cs.allow-unsigned-executable-memory` ← Claude CLI 실행에 필요할 수 있음
   - `com.apple.security.cs.disable-library-validation` ← 외부 .dylib 로드 시

### 4. Info.plist 추가 키

```xml
<key>NSDocumentsFolderUsageDescription</key>
<string>Obsidian Vault 접근에 사용됩니다.</string>
<key>NSDownloadsFolderUsageDescription</key>
<string>다운로드 폴더의 파일을 첨부하기 위해 사용됩니다.</string>
<key>NSAppleEventsUsageDescription</key>
<string>외부 앱과 연동(예: Obsidian URL 스킴)에 사용됩니다.</string>
```

### 5. 빌드 설정

- **Deployment Target**: macOS 26.0
- **Swift Language Version**: 6.2
- **Strict Concurrency Checking**: Complete
- **Code Signing Identity**: Apple Development (또는 Sign to Run Locally)

### 6. 첫 빌드 검증

`⌘B` → 성공해야 함. 실패 시:
- "missing module YuminaiCore" → SPM 의존성 다시 확인
- "Cannot find Process" → `import Foundation` 누락
- Concurrency 에러 → `rules/20_CONCURRENCY.md` 참조

## App 진입점 초안

`App/Yuminai/YuminaiApp.swift` (Xcode가 자동 생성한 후 다음으로 교체):

```swift
import SwiftUI
import YuminaiCore
import YuminaiUI
import YuminaiPersistence

@main
struct YuminaiApp: App {
    @State private var appModel = AppModel()
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            // 메뉴 명령 (CommandMenu) 추후 추가
        }
        
        Settings {
            SettingsView()
                .environment(appModel)
        }
    }
}
```

(`AppModel`, `RootView`, `SettingsView`는 향후 작성)

## 주의

- `App/` 디렉토리 내부에 `Yuminai.xcodeproj` 가 생성됩니다 — git에 함께 커밋
- `xcuserdata/`, `xcuserstate`는 `.gitignore`에 이미 포함
- **이 README 자체는 Xcode 프로젝트 생성 후 삭제하지 말 것** — 재셋업 가이드
