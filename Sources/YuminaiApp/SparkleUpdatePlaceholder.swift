/// **ADR-146 Phase 1** — Sparkle 자동 업데이트 플레이스홀더.
///
/// ## 현재 상태
/// 수동 업데이트만 지원 (GitHub Releases 페이지 안내). Sparkle 통합은 Phase 2 예정.
///
/// ## Phase 2 설계 (미구현)
/// 1. Sparkle 2 SPM 패키지 추가: `https://github.com/sparkle-project/Sparkle`
/// 2. appcast.xml 호스팅 (GitHub Pages 또는 별도 CDN)
/// 3. Info.plist 키 추가:
///    - `SUFeedURL`: appcast.xml URL
///    - `SUPublicEDKey`: 업데이트 서명 검증 공개키
/// 4. AppDelegate 또는 App body에 `SPUStandardUpdaterController` 초기화
/// 5. 설정 UI: "자동 업데이트 확인" 토글 → PreferencesSheet 내
///
/// ## appcast.xml 템플릿
/// ```xml
/// <?xml version="1.0" encoding="utf-8"?>
/// <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
///   <channel>
///     <title>Yuminai</title>
///     <item>
///       <title>Version 1.0.0</title>
///       <sparkle:version>1</sparkle:version>
///       <sparkle:shortVersionString>1.0.0</sparkle:shortVersionString>
///       <pubDate>Thu, 08 May 2026 00:00:00 +0000</pubDate>
///       <enclosure url="https://…/Yuminai-1.0.0.dmg"
///                  sparkle:edSignature="…"
///                  length="0"
///                  type="application/octet-stream"/>
///     </item>
///   </channel>
/// </rss>
/// ```
///
/// ## 구현 전제 조건
/// - Notarization 완료된 빌드 (P0: Apple Developer 계정 — 현재 제외)
/// - Ed25519 키페어 생성: `./bin/generate_appcast --generate-keys`
/// - GitHub Pages 또는 S3 버킷 appcast 호스팅 설정
///
/// ADR-146이 승인되면 이 파일을 실제 SPUStandardUpdaterController 초기화 코드로 교체한다.
enum SparkleUpdatePlaceholder {
    // Phase 2에서 구현:
    // static func configureUpdater() -> SPUStandardUpdaterController
    // static let appcastURL = URL(string: "https://…/appcast.xml")!
}
