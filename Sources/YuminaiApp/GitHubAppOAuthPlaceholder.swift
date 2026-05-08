/// **ADR-143 Phase 1** — GitHub App OAuth Flow 플레이스홀더.
///
/// ## 현재 상태
/// GitHub PAT(Fine-grained) 방식이 기본. App OAuth는 Phase 2에서 구현 예정.
///
/// ## Phase 2 설계 (미구현)
/// 1. GitHub App 등록 (organization 또는 개인 계정)
/// 2. OAuth Device Flow: `POST /login/device/code` → polling `POST /login/oauth/access_token`
/// 3. 토큰 저장: Keychain (SecItemAdd / SecItemCopyMatching)
/// 4. Refresh: App Installation Token (60분 TTL, GitHub App 전용)
/// 5. AppModel+GitHub에 `authorizeWithGitHubApp()` 메서드 추가
///
/// ## 관련 파일
/// - Sources/YuminaiApp/GitHubPATSheet.swift — 현재 PAT UI
/// - Sources/YuminaiCore/GitHubClient.swift (예정) — API 레이어 추상화
///
/// ## 구현 전제 조건
/// - GitHub App 생성 + Client ID/Secret 필요 (P0 Apple Developer 계정처럼 별도 설정)
/// - entitlements: com.apple.security.network.client 이미 포함
///
/// ADR-143이 승인되면 이 파일을 실제 구현으로 교체한다.
enum GitHubAppOAuthPlaceholder {
    // Phase 2에서 구현:
    // static func startDeviceFlow() async throws -> String
    // static func pollForToken(deviceCode: String) async throws -> String
    // static func refreshInstallationToken(appId: Int, privateKey: Data) async throws -> String
}
