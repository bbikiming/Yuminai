# ADR-146: Sparkle 자동 업데이트 플레이스홀더

**날짜**: 2026-05-08  
**상태**: Proposed (Phase 1 플레이스홀더)  
**연관**: ADR-123 (Release Distribution)

---

## 1. 배경

현재 업데이트는 GitHub Releases 페이지에서 수동으로 DMG를 받아야 한다. macOS 앱 표준 자동 업데이트 경험(Sparkle 2)이 없다.

---

## 2. Phase 1 결정 (현재)

`SparkleUpdatePlaceholder.swift`에 설계 문서를 코드 주석으로 남긴다.

---

## 3. Phase 2 설계 (미구현)

### 패키지 추가

```swift
// Package.swift
.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
```

```swift
// YuminaiApp target
.product(name: "Sparkle", package: "Sparkle")
```

### Info.plist 키

```xml
<key>SUFeedURL</key>
<string>https://raw.githubusercontent.com/yuminai/app/main/appcast.xml</string>
<key>SUPublicEDKey</key>
<string><!-- generate_appcast 출력값 --></string>
<key>SUEnableAutomaticChecks</key>
<true/>
```

### 코드 통합

```swift
// YuminaiApp.swift (App body)
import Sparkle

@NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

// AppDelegate.swift
class AppDelegate: NSObject, NSApplicationDelegate {
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
}
```

### appcast.xml 호스팅

GitHub Pages (`gh-pages` 브랜치) 또는 raw GitHub URL을 통해 `appcast.xml` 제공.

### CI 통합

`release.yml`에 `generate_appcast` 단계 추가:
```bash
./bin/generate_appcast dist/ --ed-key-file sparkle_private.key
```

---

## 4. 전제 조건

- **P0**: Notarization 완료된 빌드 (Apple Developer 계정 + Hardened Runtime)
- Ed25519 키페어 생성 (한 번만, GitHub Secrets에 저장)
- appcast.xml 호스팅 위치 결정

---

## 5. 영향 파일 (Phase 1)

| 파일 | 변경 |
|------|------|
| `Sources/YuminaiApp/SparkleUpdatePlaceholder.swift` | 신규 (설계 문서) |
