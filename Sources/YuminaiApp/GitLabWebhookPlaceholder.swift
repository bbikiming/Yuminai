/// **ADR-144 Phase 1** — GitLab Webhook 통합 플레이스홀더.
///
/// ## 현재 상태
/// GitLab PAT 기반 API 접근만 지원. Webhook 수신은 Phase 2에서 구현 예정.
///
/// ## Phase 2 설계 (미구현)
/// 1. ngrok / Cloudflare Tunnel로 로컬 서버 외부 노출
///    또는 Telegram Bot을 relay로 활용 (ADR-080 패턴 재사용)
/// 2. GitLab Webhook 이벤트 파싱:
///    - Push events: ref, commits, author
///    - MR events: action (open/close/merge), title, URL
///    - Pipeline events: status, duration
/// 3. AppModel+GitLab에 `handleWebhook(_ payload: Data) async` 추가
/// 4. Telegram 알림 → `TelegramBotRunner.send(...)` 경유
///
/// ## 관련 파일
/// - Sources/YuminaiApp/AppModel+GitLab.swift — 현재 GitLab API 레이어
/// - Sources/YuminaiApp/GitLabPATSheet.swift — PAT 설정 UI
/// - Sources/YuminaiCore/TelegramBotRunner.swift — Telegram 전송
///
/// ## 구현 전제 조건
/// - 외부 접근 가능한 엔드포인트 (ngrok 또는 embedded HTTP server)
/// - entitlements: com.apple.security.network.server 추가 필요 (현재 미포함)
///
/// ADR-144가 승인되면 이 파일을 실제 구현으로 교체한다.
enum GitLabWebhookPlaceholder {
    // Phase 2에서 구현:
    // static func startWebhookServer(port: Int) throws -> WebhookServer
    // static func parseWebhookPayload(_ data: Data) throws -> GitLabWebhookEvent
    // static func routeToTelegram(_ event: GitLabWebhookEvent, bot: TelegramBotRunner) async throws
}
