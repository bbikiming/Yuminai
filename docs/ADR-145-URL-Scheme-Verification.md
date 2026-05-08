# ADR-145: yuminai:// URL Scheme 등록 검증

**날짜**: 2026-05-08  
**상태**: Accepted  
**연관**: ADR-130 (DeepLink 통합)

---

## 1. 배경

ADR-130에서 `AppModel+DeepLink.swift`에 URL scheme 처리 로직이 구현됐으나, `Info.plist`에 `CFBundleURLTypes` 등록이 빠진 채로 merge됐다는 의혹이 있었다. 실제 URL scheme 등록 여부를 확인해야 했다.

---

## 2. 검증 결과

`App/Info.plist`에 다음 항목이 이미 정상 등록되어 있음을 확인:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>im.yuminai.app</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>yuminai</string>
        </array>
    </dict>
</array>
```

---

## 3. 동작 확인

ADR-130에서 정의된 deep link 경로:

| URL | 동작 |
|-----|------|
| `yuminai://open` | 앱 포커스 |
| `yuminai://workspace/<id>` | 특정 workspace 선택 |
| `yuminai://autorun/start?prompt=<text>` | AutoRun 시작 |
| `yuminai://hitl/approve/<id>` | HITL 승인 |

---

## 4. 결론

별도 코드 변경 없음. ADR-145는 검증 ADR으로, 기존 구현이 정상임을 확인하는 문서 역할.
