import Foundation

// MARK: - PalettePinStore (ADR-052)

/// Command Palette 핀/recent 영속 store.
///
/// **출처/근거**:
/// - VSCode `quickPickPin.ts` (https://github.com/microsoft/vscode/blob/main/src/vs/platform/quickinput/browser/quickPickPin.ts)
///   — `IStorageService` keyed by `quickPickPin`, JSON 배열 of stable IDs
/// - VSCode `commandsQuickAccess.ts:378-484` — MRU `LRUCache<commandId, counter>` saved on shutdown
/// - Raycast `clean-text.tsx:55-81` — `LocalStorage.setItem("clean-text-pinned", JSON.stringify(string[]))`
/// - cmdk command-score (continuous=1.0, word-jump=0.8-0.9) — fuzzy ranking
///
/// **데이터 모델 분리** (VSCode/Raycast 공통):
/// - Pins: ordered array of stable string IDs (label/icon/handler 변경에 깨지지 않음)
/// - Recents: id → counter (LRU 50개 cap)
/// - Pins/Recents 별도 storage key, 별도 lifecycle (sync semantic 다름)
///
/// **단순화**: 단일 사용자 macOS, UserDefaults 충분. SwiftData/Cloud sync 불필요.
public actor PalettePinStore {
    public static let pinnedKey = "yuminai.palette.pinnedIds"
    public static let recentCacheKey = "yuminai.palette.recentCache"
    public static let recentCounterKey = "yuminai.palette.recentCounter"

    /// recent cap (VSCode default 50, Raycast 4 + pinned.length)
    public static let recentCap = 50

    private let defaults: UserDefaults
    private(set) var pinnedIds: [String] = []
    private(set) var recentCounters: [String: Int] = [:]
    private(set) var monotonicCounter: Int = 0

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // load는 actor 격리 — 명시적으로 sync 호출
        if let data = defaults.data(forKey: Self.pinnedKey),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            self.pinnedIds = ids
        }
        if let data = defaults.data(forKey: Self.recentCacheKey),
           let cache = try? JSONDecoder().decode([String: Int].self, from: data) {
            self.recentCounters = cache
        }
        self.monotonicCounter = defaults.integer(forKey: Self.recentCounterKey)
    }

    // MARK: - Pin operations

    public func isPinned(_ actionId: String) -> Bool {
        pinnedIds.contains(actionId)
    }

    public func togglePin(_ actionId: String) {
        guard !actionId.isEmpty else { return }
        if let idx = pinnedIds.firstIndex(of: actionId) {
            pinnedIds.remove(at: idx)
        } else {
            pinnedIds.append(actionId)
        }
        persistPins()
    }

    public func pin(_ actionId: String) {
        guard !actionId.isEmpty, !pinnedIds.contains(actionId) else { return }
        pinnedIds.append(actionId)
        persistPins()
    }

    public func unpin(_ actionId: String) {
        pinnedIds.removeAll { $0 == actionId }
        persistPins()
    }

    /// drag-and-drop reorder support
    public func reorderPins(_ newOrder: [String]) {
        let validated = newOrder.filter { pinnedIds.contains($0) }
        // 누락된 ID는 끝에 보존
        let missing = pinnedIds.filter { !newOrder.contains($0) }
        pinnedIds = validated + missing
        persistPins()
    }

    // MARK: - Recent (MRU) operations

    /// 액션 사용 시 recent counter 증가. monotonic counter로 ranking.
    public func recordUse(_ actionId: String) {
        guard !actionId.isEmpty else { return }
        monotonicCounter += 1
        recentCounters[actionId] = monotonicCounter
        // cap 적용 — 가장 오래된 것 제거
        if recentCounters.count > Self.recentCap {
            let sorted = recentCounters.sorted { $0.value < $1.value }
            let toRemove = sorted.prefix(recentCounters.count - Self.recentCap)
            for (id, _) in toRemove {
                recentCounters.removeValue(forKey: id)
            }
        }
        persistRecents()
    }

    /// 가장 최근 사용된 ID 순서 (사용 빈도 높은 순서).
    public func recentIds(limit: Int = 8) -> [String] {
        recentCounters
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key }
    }

    public func clearRecents() {
        recentCounters = [:]
        monotonicCounter = 0
        persistRecents()
    }

    // MARK: - Snapshot (UI binding용)

    public func snapshot() -> Snapshot {
        Snapshot(
            pinnedIds: pinnedIds,
            recentCounters: recentCounters,
            monotonicCounter: monotonicCounter
        )
    }

    public struct Snapshot: Sendable, Hashable {
        public let pinnedIds: [String]
        public let recentCounters: [String: Int]
        public let monotonicCounter: Int

        public init(pinnedIds: [String], recentCounters: [String: Int], monotonicCounter: Int) {
            self.pinnedIds = pinnedIds
            self.recentCounters = recentCounters
            self.monotonicCounter = monotonicCounter
        }
    }

    // MARK: - Internal persist

    private func persistPins() {
        if let data = try? JSONEncoder().encode(pinnedIds) {
            defaults.set(data, forKey: Self.pinnedKey)
        }
    }

    private func persistRecents() {
        if let data = try? JSONEncoder().encode(recentCounters) {
            defaults.set(data, forKey: Self.recentCacheKey)
        }
        defaults.set(monotonicCounter, forKey: Self.recentCounterKey)
    }
}

// MARK: - Fuzzy scoring (cmdk-derived)

/// Fuzzy 매칭 score 계산 — cmdk(`pacocoursey/cmdk`)의 command-score.ts 차용.
///
/// **알고리즘**:
/// - continuous match = 1.0
/// - space-word jump = 0.9
/// - non-space word jump = 0.8
/// - case-mismatch penalty = 0.9999
/// - empty query = 1.0 (모두 통과)
///
/// 출처: https://github.com/pacocoursey/cmdk/blob/main/cmdk/src/command-score.ts (lines 6-44)
public enum CmdkScore {
    public static func score(text: String, query: String) -> Double {
        if query.isEmpty { return 1.0 }
        if text.isEmpty { return 0.0 }
        let lowerText = text.lowercased()
        let lowerQuery = query.lowercased()

        // contains는 baseline (0.5)
        guard lowerText.contains(lowerQuery) else {
            // partial subsequence match (모든 문자가 순서대로 등장)
            return subsequenceScore(text: lowerText, query: lowerQuery)
        }
        // continuous match
        if lowerText.hasPrefix(lowerQuery) { return 1.0 }
        // word boundary match — 이전 char가 space면 0.9, 다른 boundary면 0.8 (cmdk 차용)
        let wordBoundaryChars: Set<Character> = [" ", "-", "_", "."]
        let textArray = Array(lowerText)
        for i in 1..<textArray.count {
            let prevChar = textArray[i - 1]
            guard wordBoundaryChars.contains(prevChar) else { continue }
            let suffix = String(textArray[i...])
            if suffix.hasPrefix(lowerQuery) {
                return prevChar == " " ? 0.9 : 0.8
            }
        }
        // contains anywhere
        return 0.7
    }

    private static func subsequenceScore(text: String, query: String) -> Double {
        var queryIndex = query.startIndex
        for char in text {
            guard queryIndex < query.endIndex else { break }
            if char == query[queryIndex] {
                queryIndex = query.index(after: queryIndex)
            }
        }
        return queryIndex == query.endIndex ? 0.4 : 0.0
    }
}
