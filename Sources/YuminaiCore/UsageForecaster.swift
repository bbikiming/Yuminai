import Foundation

// MARK: - UsageForecaster (ADR-064 Phase 5)

/// **ADR-064 Phase 5** — EWMA (Exponentially Weighted Moving Average) 기반 사용량 forecast.
///
/// **알고리즘**:
/// - EWMA: `S_t = α × X_t + (1 - α) × S_{t-1}`
/// - α (smoothing factor) 0.3 권장 (최근 데이터에 30% weight)
/// - 데이터 sample 부족 (< 3개) 시 nil 반환 (forecast 신뢰도 부족)
///
/// **사용 예**:
/// - 시간별 cost trend → 다음 시간 예상 cost
/// - 일별 turn count → 다음 일 예상 turns
public enum UsageForecaster {
    /// 기본 EWMA smoothing factor.
    public static let defaultAlpha: Double = 0.3
    /// 최소 sample 수 (이 미만이면 nil).
    public static let minSamples = 3

    /// **EWMA 누적 시리즈** — 입력 시계열을 smooth된 시리즈로 반환.
    /// 첫 sample은 그대로, 이후 sample마다 EWMA 적용.
    public static func ewmaSeries(_ values: [Double], alpha: Double = defaultAlpha) -> [Double] {
        guard !values.isEmpty else { return [] }
        var result: [Double] = [values[0]]
        for i in 1..<values.count {
            let smoothed = alpha * values[i] + (1 - alpha) * result[i - 1]
            result.append(smoothed)
        }
        return result
    }

    /// **다음 sample 예측**.
    /// 마지막 EWMA 값을 그대로 반환 (단순 EWMA forecast).
    /// 더 정교한 forecast는 Holt-Winters 등으로 확장 가능.
    public static func forecastNext(_ values: [Double], alpha: Double = defaultAlpha) -> Double? {
        guard values.count >= minSamples else { return nil }
        let smoothed = ewmaSeries(values, alpha: alpha)
        return smoothed.last
    }

    /// **N개 미래 sample 예측** — naive: 마지막 EWMA 값 그대로 반복.
    public static func forecastFuture(_ values: [Double], steps: Int, alpha: Double = defaultAlpha) -> [Double] {
        guard let next = forecastNext(values, alpha: alpha) else { return [] }
        return Array(repeating: next, count: max(0, steps))
    }

    /// trend 방향 (positive / negative / flat).
    /// 마지막 N samples의 평균 변화율 기반.
    public static func trend(_ values: [Double], lookback: Int = 5) -> Trend {
        guard values.count >= 2 else { return .flat }
        let recent = Array(values.suffix(min(lookback, values.count)))
        guard recent.count >= 2 else { return .flat }
        let first = recent.first ?? 0
        let last = recent.last ?? 0
        let diff = last - first
        let avg = (first + last) / 2
        guard avg > 0.0001 else { return .flat }
        let pctChange = diff / avg
        if pctChange > 0.1 { return .up }
        if pctChange < -0.1 { return .down }
        return .flat
    }

    public enum Trend: String, Sendable, Hashable, Codable {
        case up
        case down
        case flat

        public var icon: String {
            switch self {
            case .up: return "arrow.up.right"
            case .down: return "arrow.down.right"
            case .flat: return "arrow.right"
            }
        }
    }
}
