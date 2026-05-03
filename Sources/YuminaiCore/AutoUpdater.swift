import Foundation

// MARK: - AutoUpdater (ADR-069 Phase 2 — Sparkle 호환 infrastructure)

/// **ADR-069 Phase 2** — Sparkle 호환 auto-update infrastructure.
///
/// Sparkle 본체는 별도 SPM dependency 추가 필요 (https://github.com/sparkle-project/Sparkle).
/// 이 파일은 Sparkle을 도입하기 전 단계의 추상화 — appcast.xml 파싱 + 버전 비교 + 알림.
///
/// 흐름:
/// 1. 앱 실행 시 (또는 수동 트리거) appcastURL fetch
/// 2. 최신 버전 vs 현재 버전 비교
/// 3. 더 높은 버전 있으면 사용자에게 알림 + 다운로드 URL 제공
///
/// 향후 Sparkle 도입 시:
/// - SPUUpdater + SPUStandardUserDriver 사용
/// - `Info.plist`에 `SUFeedURL` 추가
/// - 자동 다운로드 + 검증 + 설치
public actor AutoUpdater {
    public let appcastURL: URL
    public let currentVersion: String
    /// 마지막 check 시간 (rate-limit용)
    private var lastCheckedAt: Date?
    /// 최소 check 간격 (1시간)
    public let minCheckInterval: TimeInterval = 3600

    public init(appcastURL: URL, currentVersion: String) {
        self.appcastURL = appcastURL
        self.currentVersion = currentVersion
    }

    /// 새 버전 check.
    /// 마지막 check로부터 1시간 미만이면 cached result 반환 (실제 fetch X).
    public func checkForUpdate() async -> UpdateCheckResult {
        if let last = lastCheckedAt, Date().timeIntervalSince(last) < minCheckInterval {
            return .recentlyChecked
        }
        lastCheckedAt = Date()
        do {
            let (data, _) = try await URLSession.shared.data(from: appcastURL)
            guard let appcast = try? AppcastParser.parse(data) else {
                return .error("Appcast parse 실패")
            }
            // 최신 버전 찾기
            guard let latest = appcast.items.sorted(by: { $0.version > $1.version }).first else {
                return .error("Appcast에 release item 없음")
            }
            // 현재 버전과 비교
            if compareVersions(latest.version, currentVersion) > 0 {
                return .updateAvailable(latest)
            }
            return .upToDate
        } catch {
            return .error(error.localizedDescription)
        }
    }

    /// Semantic version 비교 (a > b면 1, ==면 0, <면 -1).
    private func compareVersions(_ a: String, _ b: String) -> Int {
        let aParts = a.split(separator: ".").compactMap { Int($0) }
        let bParts = b.split(separator: ".").compactMap { Int($0) }
        let maxCount = max(aParts.count, bParts.count)
        for i in 0..<maxCount {
            let av = i < aParts.count ? aParts[i] : 0
            let bv = i < bParts.count ? bParts[i] : 0
            if av > bv { return 1 }
            if av < bv { return -1 }
        }
        return 0
    }
}

public enum UpdateCheckResult: Sendable, Hashable {
    case upToDate
    case updateAvailable(AppcastItem)
    case recentlyChecked
    case error(String)
}

/// **ADR-069 Phase 2** — Sparkle Appcast XML schema (subset).
public struct AppcastItem: Sendable, Hashable {
    public let title: String
    public let version: String
    public let downloadURL: URL
    public let pubDate: Date
    public let description: String?

    public init(title: String, version: String, downloadURL: URL, pubDate: Date, description: String? = nil) {
        self.title = title
        self.version = version
        self.downloadURL = downloadURL
        self.pubDate = pubDate
        self.description = description
    }
}

public struct Appcast: Sendable, Hashable {
    public let items: [AppcastItem]

    public init(items: [AppcastItem]) {
        self.items = items
    }
}

/// **ADR-069 Phase 2** — Appcast XML 단순 parser.
/// 정식 Sparkle XML 스키마 일부 — Sparkle 도입 전 임시.
public enum AppcastParser {
    /// 단순 string-based parse (Sparkle 도입 시 XMLParser delegate로 교체).
    public static func parse(_ data: Data) throws -> Appcast {
        guard let xml = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "AppcastParser", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid UTF-8"])
        }
        // 매우 단순한 regex-style parse — production은 XMLParser 사용 권장
        var items: [AppcastItem] = []
        let itemBlocks = xml.components(separatedBy: "<item>").dropFirst()
        let formatter = ISO8601DateFormatter()
        for block in itemBlocks {
            guard let endIdx = block.range(of: "</item>")?.lowerBound else { continue }
            let itemContent = String(block[block.startIndex..<endIdx])
            let title = extractTag(itemContent, "title") ?? "Update"
            let version = extractTag(itemContent, "sparkle:shortVersionString") ?? extractTag(itemContent, "version") ?? "0.0.0"
            let urlStr = extractAttr(itemContent, "enclosure", "url") ?? ""
            let pubDateStr = extractTag(itemContent, "pubDate") ?? ""
            let description = extractTag(itemContent, "description")
            guard let url = URL(string: urlStr) else { continue }
            let pubDate = formatter.date(from: pubDateStr) ?? Date()
            items.append(AppcastItem(
                title: title, version: version, downloadURL: url,
                pubDate: pubDate, description: description
            ))
        }
        return Appcast(items: items)
    }

    private static func extractTag(_ text: String, _ tag: String) -> String? {
        guard let openRange = text.range(of: "<\(tag)>"),
              let closeRange = text.range(of: "</\(tag)>", range: openRange.upperBound..<text.endIndex)
        else { return nil }
        return String(text[openRange.upperBound..<closeRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractAttr(_ text: String, _ tag: String, _ attr: String) -> String? {
        guard let tagRange = text.range(of: "<\(tag) ") else { return nil }
        let after = String(text[tagRange.upperBound...])
        guard let attrRange = after.range(of: "\(attr)=\"") else { return nil }
        let afterAttr = String(after[attrRange.upperBound...])
        guard let endQuote = afterAttr.firstIndex(of: "\"") else { return nil }
        return String(afterAttr[afterAttr.startIndex..<endQuote])
    }
}
