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

    // MARK: - ADR-065 Phase 1 + ADR-066 Phase 3 — Holt-Winters (additive + multiplicative)

    /// **ADR-066 Phase 3** — Holt-Winters seasonal model 종류.
    public enum HoltWintersModel: String, Sendable, Hashable, Codable {
        case additive       // X = level + trend + seasonal (작은 값 안정)
        case multiplicative // X = (level + trend) × seasonal (비율 변동 데이터)
    }

    /// **ADR-065 Phase 1 + ADR-066 Phase 3** — Holt-Winters forecast.
    /// - additive: `level + trend + seasonal[t-L]`
    /// - multiplicative: `(level + trend) × seasonal[t-L]`
    /// 작은 값 (≤ 0)은 multiplicative에서 무한대/0 가능 — additive로 자동 fallback.
    public static func holtWintersForecast(
        _ values: [Double],
        seasonLength: Int = 24,
        alpha: Double = 0.3,
        beta: Double = 0.1,
        gamma: Double = 0.1,
        steps: Int = 1,
        model: HoltWintersModel = .additive
    ) -> [Double]? {
        // multiplicative은 0 또는 음수 있으면 additive로 fallback
        let effectiveModel: HoltWintersModel = (model == .multiplicative && values.contains(where: { $0 <= 0.0001 }))
            ? .additive
            : model
        if effectiveModel == .multiplicative {
            return holtWintersMultiplicative(values, seasonLength: seasonLength, alpha: alpha, beta: beta, gamma: gamma, steps: steps)
        }
        return holtWintersAdditive(values, seasonLength: seasonLength, alpha: alpha, beta: beta, gamma: gamma, steps: steps)
    }

    private static func holtWintersAdditive(
        _ values: [Double],
        seasonLength: Int,
        alpha: Double,
        beta: Double,
        gamma: Double,
        steps: Int
    ) -> [Double]? {
        // 충분한 데이터: 최소 2 cycle
        guard values.count >= 2 * seasonLength else { return nil }

        // initial level: 첫 cycle 평균
        let firstCycle = Array(values.prefix(seasonLength))
        var level = firstCycle.reduce(0, +) / Double(seasonLength)
        // initial trend: cycle 평균의 차이 / seasonLength
        let secondCycle = Array(values.dropFirst(seasonLength).prefix(seasonLength))
        let secondAvg = secondCycle.reduce(0, +) / Double(seasonLength)
        var trend = (secondAvg - level) / Double(seasonLength)
        // initial seasonal: 첫 cycle / level
        var seasonal = firstCycle.map { $0 - level }

        // update for remaining samples
        for i in seasonLength..<values.count {
            let s = seasonal[i % seasonLength]
            let prevLevel = level
            level = alpha * (values[i] - s) + (1 - alpha) * (prevLevel + trend)
            trend = beta * (level - prevLevel) + (1 - beta) * trend
            seasonal[i % seasonLength] = gamma * (values[i] - level) + (1 - gamma) * s
        }

        // forecast N steps
        var forecasts: [Double] = []
        for h in 1...steps {
            let s = seasonal[(values.count + h - 1) % seasonLength]
            forecasts.append(level + Double(h) * trend + s)
        }
        return forecasts
    }

    /// **ADR-066 Phase 3** — Holt-Winters multiplicative.
    /// 같은 algorithm이지만 seasonal은 ratio (X / level), forecast는 곱셈.
    private static func holtWintersMultiplicative(
        _ values: [Double],
        seasonLength: Int,
        alpha: Double,
        beta: Double,
        gamma: Double,
        steps: Int
    ) -> [Double]? {
        guard values.count >= 2 * seasonLength else { return nil }
        let firstCycle = Array(values.prefix(seasonLength))
        var level = firstCycle.reduce(0, +) / Double(seasonLength)
        guard level > 0.0001 else { return nil }
        let secondCycle = Array(values.dropFirst(seasonLength).prefix(seasonLength))
        let secondAvg = secondCycle.reduce(0, +) / Double(seasonLength)
        var trend = (secondAvg - level) / Double(seasonLength)
        // initial seasonal = ratio (X / level)
        var seasonal = firstCycle.map { $0 / level }

        for i in seasonLength..<values.count {
            let s = seasonal[i % seasonLength]
            let prevLevel = level
            level = alpha * (values[i] / max(s, 0.0001)) + (1 - alpha) * (prevLevel + trend)
            trend = beta * (level - prevLevel) + (1 - beta) * trend
            seasonal[i % seasonLength] = gamma * (values[i] / max(level, 0.0001)) + (1 - gamma) * s
        }
        var forecasts: [Double] = []
        for h in 1...steps {
            let s = seasonal[(values.count + h - 1) % seasonLength]
            forecasts.append((level + Double(h) * trend) * s)
        }
        return forecasts
    }

    // MARK: - ADR-066 Phase 5 — Forecast confidence interval

    /// **ADR-066 Phase 5** — EWMA forecast + 95% confidence interval (±2σ).
    /// 잔차 (residuals) 기반 stddev 계산.
    public static func forecastWithCI(_ values: [Double], alpha: Double = defaultAlpha) -> ForecastWithCI? {
        guard values.count >= minSamples else { return nil }
        let smoothed = ewmaSeries(values, alpha: alpha)
        let next = smoothed.last ?? 0
        // residuals
        let residuals = zip(values, smoothed).map { abs($0 - $1) }
        let mean = residuals.reduce(0, +) / Double(residuals.count)
        let variance = residuals.map { pow($0 - mean, 2) }.reduce(0, +) / Double(residuals.count)
        let stddev = sqrt(variance)
        // 95% CI ≈ ±2σ
        let halfWidth = 2 * stddev
        return ForecastWithCI(
            forecast: next,
            lowerBound: max(0, next - halfWidth),
            upperBound: next + halfWidth,
            stddev: stddev
        )
    }

    public struct ForecastWithCI: Sendable, Hashable {
        public let forecast: Double
        public let lowerBound: Double
        public let upperBound: Double
        public let stddev: Double

        public init(forecast: Double, lowerBound: Double, upperBound: Double, stddev: Double) {
            self.forecast = forecast
            self.lowerBound = lowerBound
            self.upperBound = upperBound
            self.stddev = stddev
        }
    }

    // MARK: - ADR-065 Phase 3 — Z-score anomaly detection

    /// **ADR-065 Phase 3** — Z-score 기반 anomaly detection.
    /// 각 sample의 z = (x - mean) / stddev. |z| > threshold면 anomaly.
    public static func detectAnomalies(_ values: [Double], threshold: Double = 2.0) -> [Anomaly] {
        guard values.count >= 3 else { return [] }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
        let stddev = sqrt(variance)
        guard stddev > 0.0001 else { return [] }
        var anomalies: [Anomaly] = []
        for (idx, v) in values.enumerated() {
            let z = (v - mean) / stddev
            if abs(z) > threshold {
                anomalies.append(Anomaly(index: idx, value: v, zScore: z))
            }
        }
        return anomalies
    }

    public struct Anomaly: Sendable, Hashable, Identifiable {
        public let id = UUID()
        public let index: Int
        public let value: Double
        public let zScore: Double

        public var direction: AnomalyDirection {
            zScore > 0 ? .high : .low
        }
    }

    public enum AnomalyDirection: String, Sendable, Hashable {
        case high  // 평균보다 매우 높음 (spike)
        case low   // 평균보다 매우 낮음 (drop)
    }
}
