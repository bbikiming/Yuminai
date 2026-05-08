# ADR-144: GitLab Webhook 통합 플레이스홀더

**날짜**: 2026-05-08  
**상태**: Proposed (Phase 1 플레이스홀더)  
**연관**: ADR-133 (GitLab 통합), ADR-080 (Telegram 봇 통합)

---

## 1. 배경

현재 GitLab 통합은 PAT 기반 REST API (MR 조회, 파이프라인 상태 등)로 한정된다. Push/MR/Pipeline 이벤트를 실시간 수신하려면 Webhook이 필요하다.

---

## 2. Phase 1 결정 (현재)

`GitLabWebhookPlaceholder.swift`에 설계 문서만 코드 주석으로 남긴다.

---

## 3. Phase 2 설계 (미구현)

### 외부 엔드포인트 확보 방안

**Option A: ngrok/Cloudflare Tunnel**
- 로컬 HTTP 서버 (예: Swifter, 또는 URLSessionStreamTask)를 외부에 노출
- 장점: 구현 단순
- 단점: 앱 실행 중에만 유효, 터널 재시작 시 URL 변경

**Option B: Telegram Bot Relay (ADR-080 패턴)**
- GitLab → GitHub Actions Webhook → Telegram Bot → Yuminai
- 장점: 외부 서버 불필요
- 단점: 레이어 복잡도 증가

### 이벤트 스키마

```swift
enum GitLabWebhookEvent {
    case push(ref: String, commits: [Commit], author: String)
    case mergeRequest(action: MRAction, title: String, url: URL)
    case pipeline(status: PipelineStatus, duration: Int, url: URL)
}
```

### Telegram 알림 형식

```
🔀 MR Opened — feat: Add dark mode
@username → main
https://gitlab.com/org/repo/-/merge_requests/42
```

---

## 4. 전제 조건

- `entitlements`: `com.apple.security.network.server` 추가 필요 (현재 미포함)
- 또는 Telegram relay 방식 선택 시 불필요
- GitLab 프로젝트에서 Webhook URL 등록 권한 필요

---

## 5. 영향 파일 (Phase 1)

| 파일 | 변경 |
|------|------|
| `Sources/YuminaiApp/GitLabWebhookPlaceholder.swift` | 신규 (설계 문서) |
