# Yuminai 배포 가이드 (ADR-068 + ADR-069)

> 빌드 → .app 번들 → DMG → (옵션) Notarization → App Store까지 단계별.

---

## 1. 기본 빌드 (개발자 본인용)

```bash
./App/build_app_bundle.sh
```

→ `dist/Yuminai.app` 생성 (native arch only, ad-hoc signed).

---

## 2. Universal binary (arm64 + x86_64) — ADR-069 Phase 1

Apple Silicon + Intel Mac 모두 지원:

```bash
./App/build_app_bundle.sh --universal
```

→ lipo로 두 architecture 합친 fat binary.

검증:
```bash
file dist/Yuminai.app/Contents/MacOS/Yuminai
# Expected: Mach-O universal binary with 2 architectures
```

---

## 3. DMG 패키징 — ADR-068 Phase 5 + ADR-069 Phase 3

### 기본 DMG (압축만)
```bash
./App/build_app_bundle.sh --dmg
# → dist/Yuminai-1.0.0.dmg
```

### Custom DMG (배경 이미지 + Finder 정렬)
```bash
./App/build_app_bundle.sh --dmg --custom-dmg
```

→ AppleScript로 Finder 창 크기 + icon 위치 + background 이미지 적용.
→ `App/Assets/dmg-background.png` (600×400) 사용.

---

## 4. Notarization (Apple Developer ID 필요) — ADR-069 Phase 4

### 사전 준비 (한 번만)

1. **Apple Developer Program** 가입 ($99/년)
2. **Developer ID Application** certificate 발급
   - Xcode → Settings → Accounts → Manage Certificates → "+ Developer ID Application"
3. **App-specific password** 생성
   - https://appleid.apple.com → "App-Specific Passwords" → "Generate"
4. **Keychain에 저장**:
   ```bash
   xcrun notarytool store-credentials yuminai-notary \
       --apple-id "your@email.com" \
       --team-id "TEAMID12345" \
       --password "app-specific-password"
   ```

### Notarize + Staple

```bash
# 1. Developer ID로 codesign (ad-hoc 대신)
codesign --force --deep --sign "Developer ID Application: Your Name (TEAMID12345)" \
    --options runtime \
    --entitlements App/Yuminai.entitlements \
    dist/Yuminai.app

# 2. DMG도 sign
codesign --force --sign "Developer ID Application: Your Name (TEAMID12345)" \
    dist/Yuminai-1.0.0.dmg

# 3. Notarize submit
xcrun notarytool submit dist/Yuminai-1.0.0.dmg \
    --keychain-profile yuminai-notary \
    --wait

# 4. Staple ticket (오프라인 검증용)
xcrun stapler staple dist/Yuminai-1.0.0.dmg
xcrun stapler staple dist/Yuminai.app

# 5. 검증
spctl --assess --type open --context context:primary-signature -v dist/Yuminai-1.0.0.dmg
# Expected: "accepted, source=Notarized Developer ID"
```

---

## 5. Sparkle Auto-Update — ADR-069 Phase 2

### 5.1 SPM dependency 추가

`Package.swift`:
```swift
.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
```

`YuminaiApp` target:
```swift
.product(name: "Sparkle", package: "Sparkle")
```

### 5.2 Info.plist 추가

```xml
<key>SUFeedURL</key>
<string>https://yuminai.com/appcast.xml</string>
<key>SUEnableAutomaticChecks</key>
<true/>
<key>SUPublicEDKey</key>
<string>YOUR_ED25519_PUBLIC_KEY</string>
```

### 5.3 Appcast XML 호스팅

`appcast.xml` (예시):
```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Yuminai Updates</title>
        <item>
            <title>Version 1.0.1</title>
            <sparkle:shortVersionString>1.0.1</sparkle:shortVersionString>
            <pubDate>Tue, 04 May 2026 10:00:00 +0000</pubDate>
            <enclosure url="https://yuminai.com/Yuminai-1.0.1.dmg"
                       sparkle:edSignature="..."
                       length="7000000"
                       type="application/octet-stream"/>
            <description><![CDATA[<ul><li>버그 수정</li></ul>]]></description>
        </item>
    </channel>
</rss>
```

### 5.4 EdDSA signature 생성

```bash
# Sparkle도구 다운로드 (한 번만)
brew install sparkle

# DMG signature 생성
sign_update dist/Yuminai-1.0.1.dmg
# → 출력된 signature를 appcast.xml의 sparkle:edSignature에 넣음
```

### 5.5 코드 통합

`Sources/YuminaiCore/AutoUpdater.swift`는 Sparkle 도입 전 임시 추상화.
Sparkle 도입 후:

```swift
import Sparkle

@main struct YuminaiAppMain: App {
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    var body: some Scene { ... }
}
```

---

## 6. App Store 배포 검토 — ADR-069 Phase 5

### 가능한가?

**기술적으로 가능**, 하지만 **제약 큼**:

| 제약 | Yuminai 영향 |
|------|--------------|
| **App Sandbox 필수** | Claude CLI subprocess 실행 차단 |
| **Hardened Runtime** | OK (이미 적용 가능) |
| **외부 process spawn 금지** | ChildClaudeProcess 동작 안 함 |
| **App Store Review** | "외부 LLM API 호출 = 본인 cost" 명시 필요 |
| **In-App Purchase 강제** | 무료라면 OK |
| **Helper executable** | XPC service로 분리해야 — 큰 refactoring |

### 결론

- **현재 형태로는 부적합** (CLI subprocess 의존이 너무 깊음)
- **대안**:
  1. **DMG 직접 배포** (현재 권장 — 개발자 도구는 보통 이 방식)
  2. **Setapp** (개발자 도구 큐레이션 마켓)
  3. **GitHub Releases** + Sparkle auto-update

### App Store 도입 시 필요한 변경

1. SPM child process → XPC service 분리
2. App Sandbox entitlement 활성
3. Network exception (api.anthropic.com / api.telegram.org)
4. Privacy manifest (PrivacyInfo.xcprivacy)
5. Screenshot / icon / description 작성
6. App Review 통과 (보통 1-2주)

→ **별도 Phase 또는 ADR-070 후보**로 분리 권장.

---

## 7. 배포 체크리스트

- [ ] Universal binary 빌드
- [ ] App icon 적용 확인
- [ ] About sheet에 정확한 버전 표시
- [ ] DMG 압축 + custom layout
- [ ] Notarization (Developer ID 있으면)
- [ ] Sparkle appcast.xml 호스팅
- [ ] Release notes (CHANGELOG에서 추출)
- [ ] GitHub Release 또는 자체 서버 업로드
