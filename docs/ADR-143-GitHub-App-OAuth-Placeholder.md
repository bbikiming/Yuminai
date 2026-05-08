# ADR-143: GitHub App OAuth 플레이스홀더

**날짜**: 2026-05-08  
**상태**: Proposed (Phase 1 플레이스홀더)  
**연관**: ADR-133 (GitHub 권한 위임)

---

## 1. 배경

현재 GitHub 인증은 Fine-grained PAT 방식이다. GitHub App OAuth는 조직 단위 권한 위임과 설치 토큰(60분 TTL) 자동 갱신 등 장점이 있으나, 다음 사전 조건이 필요하다:

- GitHub App 생성 및 등록 (별도 계정 설정)
- Client ID / Private Key 관리
- Notarized 빌드 환경 (P0 Apple Developer)

---

## 2. Phase 1 결정 (현재)

`GitHubAppOAuthPlaceholder.swift`에 설계 문서만 코드 주석으로 남긴다.

---

## 3. Phase 2 설계 (미구현)

### OAuth Device Flow

1. `POST /login/device/code` → `device_code`, `user_code`, `verification_uri`
2. 사용자에게 `user_code`를 Telegram 또는 앱 내 알림으로 안내
3. `POST /login/oauth/access_token` polling (interval 초마다)
4. 성공 시 `access_token` → Keychain 저장

### Installation Token

- GitHub App Private Key (PEM) + App ID로 JWT 생성
- `POST /app/installations/{id}/access_tokens` → 60분 TTL 토큰

### AppModel 통합

```swift
// AppModel+GitHub.swift에 추가
func authorizeWithGitHubApp() async throws {
    let deviceFlow = try await GitHubDeviceFlow.start(clientId: appClientId)
    // Telegram으로 user_code 전송
    let token = try await deviceFlow.poll()
    try await Keychain.save(token, key: "github_oauth_token")
}
```

---

## 4. 전제 조건

- P0 (Apple Developer 계정, Notarization) 완료 후 진행
- GitHub App 등록: https://github.com/settings/apps/new
- `entitlements`: `com.apple.security.network.client` 이미 포함 → 추가 불필요

---

## 5. 영향 파일 (Phase 1)

| 파일 | 변경 |
|------|------|
| `Sources/YuminaiApp/GitHubAppOAuthPlaceholder.swift` | 신규 (설계 문서) |
